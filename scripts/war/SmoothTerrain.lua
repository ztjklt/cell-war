-- One continuous, resolution-independent tissue surface at every camera scale.
-- Curves and fog are cached outside the simulation; detail sampling is budgeted.
local D,U,W,C=require('war.Data'),require('war.Util'),require('war.World'),require('war.Contour')
local BodyArt=require('war.BodyArt')
local Anatomy=require('war.Anatomy')
local Generated=require('war.UIArt')
local OrganArt=require('war.OrganArt')
local Palette=require('war.MapPalette')
local function anatomy(s) return s.anatomyVersion==2 and require('war.AnatomyV2') or Anatomy end
local S={caches=setmetatable({},{__mode='k'}),budget=0,frame=0}
local colors=D.biomes --[[@as table<number,{color:number[]}>]]
local function cache(s)
 local c=S.caches[s];if not c then c={patches={},order={},cursor=1,details={},detailOrder={},detailCursor=1,fogRevision=-1,seen={},visible={}};S.caches[s]=c end
 return c
end
function S.beginFrame() S.budget=64;S.frame=S.frame+1 end
-- Build only on entering a new world, independent of pan/zoom/DPR.
function S.prepare(s)
 if not W.hasVessels(s) then return end
 local c=cache(s);if c.body then return end
 local scale=W.worldScale(s);local step=16*scale;local cells,fat,inner={},{},{}
 for y=0,D.height(s)-step,step do for x=0,D.width(s)-step,step do
  local field=anatomy(s).surfaceField(x+step*.5,y+step*.5,s.seed,scale);local k=C.key(x,y)
  if field<1 then cells[k]={x,y} end;if field<.93 then fat[k]={x,y} end;if field<.83 then inner[k]={x,y} end
 end end
 c.body=C.build(cells,step);c.fat=C.build(fat,step);c.inner=C.build(inner,step)
end
local function shade(vg,biome,alpha)
 local c=colors[biome].color;nvgFillColor(vg,nvgRGBA(c[1],c[2],c[3],alpha or 255))
end
local function blob(R,g,x,y,rx,ry,biome)
 local px,py=R.project(g,x,y);local sx,sy=rx*32*g.zoom,ry*32*g.zoom
 if px+sx<0 or py+sy<0 or px-sx>R.w or py-sy>R.h then return end
 local c=colors[biome].color
 nvgSave(R.vg);nvgTranslate(R.vg,px,py);nvgScale(R.vg,sx,sy)
 nvgBeginPath(R.vg);nvgCircle(R.vg,0,0,1)
 nvgFillPaint(R.vg,nvgRadialGradient(R.vg,-.12,-.16,.25,1,nvgRGBA(c[1]+12,c[2]+9,c[3]+10,255),nvgRGBA(c[1]-9,c[2]-7,c[3]-5,255)))
 nvgFill(R.vg);nvgRestore(R.vg)
end
local function body(R,g,s,c,x1,x2,y1,y2)
 local scale=W.worldScale(s);local ox,oy=R.project(g,0,0);local z=32*g.zoom
 nvgBeginPath(R.vg);for _,p in ipairs(c.body) do C.path(R.vg,p,ox,oy,z,false,x1-16,x2+16,y1-16,y2+16) end;shade(R.vg,8);nvgFill(R.vg)
 nvgBeginPath(R.vg);for _,p in ipairs(c.fat) do C.path(R.vg,p,ox,oy,z,false,x1-16,x2+16,y1-16,y2+16) end;shade(R.vg,6);nvgFill(R.vg)
 nvgBeginPath(R.vg);for _,p in ipairs(c.inner) do C.path(R.vg,p,ox,oy,z,false,x1-16,x2+16,y1-16,y2+16) end
 nvgFillPaint(R.vg,nvgLinearGradient(R.vg,ox,oy,ox+D.width(s)*z,oy+D.height(s)*z,nvgRGBA(246,213,224,255),nvgRGBA(213,200,232,255)));nvgFill(R.vg)
 -- Soft tissue borders and organ chambers use the same canonical anatomy as play.
 for _,o in ipairs(s.anatomyVersion==2 and {} or require('war.VesselLayout').organs) do
  local biome=o.name=='脑' and 5 or o.name:find('肺') and 7 or o.name=='肝' and 9 or o.name=='肠' and 11 or o.name:find('肾') and 4 or (o.name:find('骨髓') or o.name=='脾') and 15 or o.name=='盆腔' and 10 or 2
  blob(R,g,o.x*scale,o.y*scale,o.rx*scale,o.ry*scale,biome)
 end
end
local function patch(s,x,y,step)
 local c=cache(s);local size=step*16;local key=step..':'..x..':'..y;local p=c.patches[key]
 if not p then
  p={x=x,y=y,step=step,size=size,next=0,groups={},paths=false,readyFrame=0};local old=c.order[c.cursor];if old then c.patches[old]=nil end
  c.order[c.cursor]=key;c.cursor=c.cursor%64+1;c.patches[key]=p
 end
 while p.next<256 and S.budget>0 do
  local xx=x+p.next%16*step;local yy=y+math.floor(p.next/16)*step
  if xx<=D.width(s) and yy<=D.height(s) then
   local t=W.terrain(s,math.floor(xx+step*.5),math.floor(yy+step*.5))
   if t<13 or t==15 or t==16 then local group=p.groups[t];if not group then group={};p.groups[t]=group end;group[C.key(xx,yy)]={xx,yy} end
   S.budget=S.budget-1
  end
  p.next=p.next+1
 end
 if p.next==256 and not p.paths then
  p.paths={};for t,cells in pairs(p.groups) do p.paths[t]=C.build(cells,step) end;p.groups={};p.readyFrame=S.frame
 end
 return p
end
function S.draw(R,g,s,x1,x2,y1,y2)
 S.prepare(s);local c=cache(s);local scale=W.worldScale(s)
 local ox,oy=R.project(g,0,0);local z=32*g.zoom
 body(R,g,s,c,x1,x2,y1,y2)
 if g.zoom>=.12 then
  local step=2;while (x2-x1+1)*(y2-y1+1)/(step*step)>800 do step=step*2 end
  local size=step*16;local batches={}
  for y=math.floor(y1/size)*size,y2,size do for x=math.floor(x1/size)*size,x2,size do
   local p=patch(s,x,y,step)
   if p.paths then for t,paths in pairs(p.paths) do
    local level=math.min(4,math.floor((S.frame-p.readyFrame)/4));local key=t+level*32;local row=batches[key];if not row then row={biome=t,alpha=level*27*U.clamp((g.zoom-.12)/.12,0,1),paths={}};batches[key]=row end;for _,q in ipairs(paths) do row.paths[#row.paths+1]=q end
   end end
  end end
  for _,batch in pairs(batches) do
   nvgBeginPath(R.vg);for _,p in ipairs(batch.paths) do C.path(R.vg,p,ox,oy,z,false,x1-16,x2+16,y1-16,y2+16) end;shade(R.vg,batch.biome,math.floor(batch.alpha));nvgFill(R.vg)
  end
 end
 if g.zoom>.5 then
  nvgBeginPath(R.vg)
  for _,p in ipairs(c.inner) do C.path(R.vg,p,ox,oy,z,false,x1-16,x2+16,y1-16,y2+16) end
  Generated.tissue(R.vg,ox,oy,760*g.zoom,math.floor(26*U.clamp((g.zoom-.5)/.5,0,1)))
 end
 OrganArt.draw(R,g,s,x1,x2,y1,y2)
 -- Clear outside the actual curved body silhouette; holes can have islands.
 nvgBeginPath(R.vg);nvgRect(R.vg,0,0,R.w,R.h)
 for _,p in ipairs(c.body) do C.path(R.vg,p,ox,oy,z,true,x1-16,x2+16,y1-16,y2+16) end
 nvgFillColor(R.vg,nvgRGBA(Palette.background[1],Palette.background[2],Palette.background[3],255));nvgFill(R.vg)
end
local function fogPaths(set)
 local cells={};for k in pairs(set) do local x,y=U.xy(k);cells[C.key(x,y)]={x,y} end
 return C.build(cells,1)
end
function S.fog(R,g,s,x1,x2,y1,y2)
 if g.fogDisabled or g.vesselSurvey then return end
 local c=cache(s);local fa=s.factions[1]
 -- Exploration grows independently of live visibility; do not rebuild it on every vision tick.
 local seenRevision=fa.seenRevision or s.fogRevision or 0
 local visibleRevision=fa.visibleRevision or s.fogRevision or 0
 if c.seenRevision~=seenRevision then c.seen=fogPaths(fa.seen);c.seenRevision=seenRevision end
 if c.visibleRevision~=visibleRevision then c.visible=fogPaths(fa.visible);c.visibleRevision=visibleRevision end
 local ox,oy=R.project(g,0,0);local scale=32*g.zoom
 local function mask(paths,color,alpha)
  nvgBeginPath(R.vg);nvgRect(R.vg,0,0,R.w,R.h)
  for _,p in ipairs(paths) do if C.intersects(p,x1,x2,y1,y2) then C.path(R.vg,p,ox,oy,scale,true,x1-4,x2+4,y1-4,y2+4) end end
  nvgFillColor(R.vg,nvgRGBA(color[1],color[2],color[3],alpha));nvgFill(R.vg)
 end
 mask(c.visible,Palette.shade,95);mask(c.seen,Palette.fog,255)
end
function S.detail(R,g,s,x1,x2,y1,y2)
 if g.zoom<=.65 then return end
 local step=math.max(1,math.ceil(2/g.zoom));local c=cache(s);local count=0
 for y=math.floor(y1/step)*step,y2,step do for x=math.floor(x1/step)*step,x2,step do
  local k=U.key(x,y)
  if (g.fogDisabled or s.factions[1].visible[k]) and U.hash(x,y,s.seed+906)<.34 and count<100 then
   local t=c.details[k]
   if not t and S.budget>0 then t=W.terrain(s,x,y);local old=c.detailOrder[c.detailCursor];if old then c.details[old]=nil end;c.detailOrder[c.detailCursor]=k;c.detailCursor=c.detailCursor%4096+1;c.details[k]=t;S.budget=S.budget-1 end
   if t and t<13 then BodyArt.detail(R,g,s,x,y,t);count=count+1 end
  end
 end end
end
function S.overview(R,s,px,py,width,height,all)
 local g={state=s,camera={x=D.width(s)*.5,y=D.height(s)*.5},zoom=height/(D.height(s)*32),fogDisabled=all,vesselSurvey=all}
 local oldW,oldH=R.w,R.h;R.w,R.h=width,height
 nvgSave(R.vg);nvgIntersectScissor(R.vg,px,py,width,height);nvgTranslate(R.vg,px,py+height*.03)
 S.draw(R,g,s,1,D.width(s),1,D.height(s));S.fog(R,g,s,1,D.width(s),1,D.height(s));nvgRestore(R.vg);R.w,R.h=oldW,oldH
end
return S
