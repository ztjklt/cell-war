local D,U,W=require("war.Data"),require("war.Util"),require("war.World")
local Art={colors=setmetatable({},{__mode="k"})}
local BodyArt=require("war.BodyArt")
local function vertex(s,x,y)
 local cache=Art.colors[s];if not cache then cache={};Art.colors[s]=cache end
 local key=y*(D.INDEX_STRIDE+2)+x;local slot=key%32749+1
 local cached=cache[slot];if cached and cached.key==key then return cached.color end
 ---@type number[]
 local c={}
 for dy=-1,0 do for dx=-1,0 do
  local b=D.biomes[W.terrain(s,x+dx,y+dy)].color --[[@as number[] ]]
  for i=1,3 do c[i]=(c[i] or 0)+b[i]*.25 end
 end end
 local grain=(U.noise(x/9,y/9,s.seed+82)-.5)*9
 for i=1,3 do c[i]=c[i]+grain end
 cache[slot]={key=key,color=c};return c
end
function Art.ground(R,g,s,x,y,visible,winter)
 local biome=W.terrain(s,x,y)
 local ca,cb=vertex(s,x,y),vertex(s,x+1,y+1)
 local pulse=biome==13 and math.sin((g.flowTime or s.time)*5.5)*3 or 0
 local function tint(c)
  local dim=visible and 1 or .4
  return nvgRGBA(math.floor((c[1]+pulse)*dim),math.floor((c[2]+pulse)*dim),math.floor((c[3]+pulse)*dim),255)
 end
 local ax,ay=R.project(g,x,y);local bx,by=R.project(g,x+1,y)
 local cx,cy=R.project(g,x+1,y+1);local dx,dy=R.project(g,x,y+1)
 -- Slight overlap hides NanoVG antialias seams between adjacent tissue tiles.
 local mx,my=R.project(g,x+.5,y+.5)
 local function expand(v,m) return v<m-.01 and v-.8 or v>m+.01 and v+.8 or v end
 nvgBeginPath(R.vg);nvgMoveTo(R.vg,expand(ax,mx),expand(ay,my));nvgLineTo(R.vg,expand(bx,mx),expand(by,my));nvgLineTo(R.vg,expand(cx,mx),expand(cy,my));nvgLineTo(R.vg,expand(dx,mx),expand(dy,my));nvgClosePath(R.vg)
 nvgFillPaint(R.vg,nvgLinearGradient(R.vg,ax,ay,cx,cy,tint(ca),tint(cb)));nvgFill(R.vg)
 return biome
end
function Art.detail(R,g,s,x,y,biome)
 local z=g.zoom;if z<.5 or biome==13 or biome>=17 then return end
 BodyArt.detail(R,g,s,x,y,biome)
end
-- Distant terrain is bounded by screen detail, not by world area. The cache
-- belongs to rendering and never enters saves; only 96 exact queries per frame.
local lodCaches=setmetatable({},{__mode="k"})
local queryBudget=0
local Anatomy=require("war.Anatomy")
function Art.beginFrame() queryBudget=96 end
local function cacheFor(s)
 local cache=lodCaches[s]
 if not cache then cache={blocks={},order={},cursor=1,fog={}};lodCaches[s]=cache end
 return cache
end
local function block(s,x,y,stride)
 local cache=cacheFor(s);local key=stride..":"..x..":"..y
 local old=cache.blocks[key]
 if not old then
  local sx,sy=math.min(D.width(s),x+stride*.5),math.min(D.height(s),y+stride*.5)
  old={x=sx,y=sy,biome=W.hasVessels(s) and Anatomy.overviewTile(sx,sy,W.worldScale(s)) or 1,exact=false}
  local previous=cache.order[cache.cursor];if previous then cache.blocks[previous]=nil end
  cache.order[cache.cursor]=key;cache.cursor=cache.cursor%16384+1;cache.blocks[key]=old
 end
 if not old.exact and queryBudget>0 then
  old.biome=W.terrain(s,math.floor(old.x),math.floor(old.y));old.exact=true;queryBudget=queryBudget-1
 end
 return old.biome
end
local function fog(s,stride)
 local cache=cacheFor(s);local revision=s.fogRevision or 0
 if cache.fog.stride==stride and cache.fog.revision==revision then return cache.fog end
 local row={stride=stride,revision=revision,seen={},visible={}};local fa=s.factions[1]
 for _,bin in pairs(fa.mapSeen) do
  local x=math.floor((bin.x-1)/stride)*stride+1;local y=math.floor((bin.y-1)/stride)*stride+1
  row.seen[U.key(x,y)]=true
 end
 for key in pairs(fa.visible) do local x,y=U.xy(key)
  row.visible[U.key(math.floor((x-1)/stride)*stride+1,math.floor((y-1)/stride)*stride+1)]=true
 end
 cache.fog=row;return row
end
-- Each color is one NanoVG fill even when it covers hundreds of rectangles.
local function beginBatches() return {} end
local function addRect(batches,biome,bright,x,y,w,h)
 local key=biome+(bright and 0 or 32);local batch=batches[key]
 if not batch then batch={biome=biome,bright=bright,rects={}};batches[key]=batch end
 local r=batch.rects;r[#r+1]=x;r[#r+1]=y;r[#r+1]=w;r[#r+1]=h
end
local function flush(R,batches,alpha)
 for _,batch in pairs(batches) do
  nvgBeginPath(R.vg);local r=batch.rects
  for i=1,#r,4 do nvgRect(R.vg,r[i],r[i+1],r[i+2],r[i+3]) end
  local c=D.biomes[batch.biome].color --[[@as number[] ]];local dim=batch.bright and 1 or .4
  nvgFillColor(R.vg,nvgRGBA(math.floor(c[1]*dim),math.floor(c[2]*dim),math.floor(c[3]*dim),alpha or 255));nvgFill(R.vg)
 end
end
function Art.stride(g,xmin,xmax,ymin,ymax)
 local cells=(xmax-xmin+1)*(ymax-ymin+1)
 if g.zoom>=.55 and cells<=4000 then return 1 end
 local stride=2
 while math.ceil((xmax-xmin+1)/stride)*math.ceil((ymax-ymin+1)/stride)>3072 do stride=stride*2 end
 return stride
end
function Art.coarse(R,g,s,xmin,xmax,ymin,ymax,stride)
 local batches=beginBatches();local fa=s.factions[1];local all=g.fogDisabled or g.vesselSurvey
 local coarseFog=not all and stride>=D.MAP_BIN and fog(s,stride) or false
 for y=math.floor((ymin-1)/stride)*stride+1,ymax,stride do
  for x=math.floor((xmin-1)/stride)*stride+1,xmax,stride do
   local sx,sy=math.min(D.width(s),x+stride*.5),math.min(D.height(s),y+stride*.5)
   local sample=U.key(sx,sy);local key=U.key(x,y)
   local visible=all or fa.visible[sample] or coarseFog and coarseFog.visible[key]
   local seen=all or fa.seen[sample] or coarseFog and coarseFog.seen[key]
   if seen then
    local biome=block(s,x,y,stride);local px,py=R.project(g,x,y)
    local width=math.min(stride,D.width(s)-x+1)*32*g.zoom
    local height=math.min(stride,D.height(s)-y+1)*32*g.zoom
    addRect(batches,biome,visible,px-.25,py-.25,width+.5,height+.5)
   end
  end
 end
 flush(R,batches)
end
function Art.overview(R,s,px,py,width,height)
 local cols=width>=256 and 64 or 32;local stride=D.width(s)/cols
 local rows=math.ceil(D.height(s)/stride);local batches=beginBatches()
 for y=0,rows-1 do for x=0,cols-1 do
  local biome=block(s,x*stride+1,y*stride+1,stride)
  addRect(batches,biome,true,px+x*width/cols,py+y*height/rows,width/cols+.4,height/rows+.4)
 end end
 flush(R,batches,230)
end
return Art
