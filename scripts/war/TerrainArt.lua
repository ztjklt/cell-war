local D,U,W=require("war.Data"),require("war.Util"),require("war.World")
local Art={colors=setmetatable({},{__mode="k"})}
local BodyArt=require("war.BodyArt")
local function vertex(s,x,y)
 local cache=Art.colors[s];if not cache then cache={};Art.colors[s]=cache end
 local key=y*(D.MAP+2)+x;local slot=key%32749+1
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
 local z=g.zoom;if z<.5 then return end
 BodyArt.detail(R,g,s,x,y,biome)
end
function Art.overview(R,s,px,py,size)
 if not s.overview then
  s.overview={}
  for y=0,63 do for x=0,63 do s.overview[y*64+x+1]=W.terrain(s,x*16+8,y*16+8) end end
 end
 for y=0,63 do for x=0,63 do
  local c=D.biomes[s.overview[y*64+x+1]].color
  R.rect(px+x*size/64,py+y*size/64,size/64+.5,size/64+.5,c,230)
 end end
end
return Art
