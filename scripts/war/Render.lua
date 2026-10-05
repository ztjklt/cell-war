-- Scene rendering: 2D scaffold + NanoVG mode B (CSS logical pixels / DPR).
local D,U,V,W=require("war.Data"),require("war.Util"),require("war.Survival"),require("war.World")
local Cells,Art=require("war.Cells"),require("war.TerrainArt")
local BodyArt=require("war.BodyArt")
local Motion,Bloodstream=require("war.Motion"),require("war.Bloodstream")
local R={
 ---@type NVGContextWrapper
 vg=nil,font=-1,images={},w=1280,h=720}
local C={grass={92,100,64},forest={65,80,58},mine={94,91,80},swamp={66,80,72},ruin={93,81,64}}
local function rgba(c,a) return nvgRGBA(math.floor(c[1]),math.floor(c[2]),math.floor(c[3]),a or 255) end
function R.rect(x,y,w,h,c,a) nvgBeginPath(R.vg);nvgRect(R.vg,x,y,w,h);nvgFillColor(R.vg,rgba(c,a));nvgFill(R.vg) end
function R.line(x,y,tx,ty,c,w,a) nvgBeginPath(R.vg);nvgMoveTo(R.vg,x,y);nvgLineTo(R.vg,tx,ty);nvgStrokeWidth(R.vg,w or 1);nvgStrokeColor(R.vg,rgba(c,a));nvgStroke(R.vg) end
function R.ellipse(x,y,rx,ry,c,a) nvgBeginPath(R.vg);nvgEllipse(R.vg,x,y,rx,ry);nvgFillColor(R.vg,rgba(c,a));nvgFill(R.vg) end
function R.poly(p,c,a) nvgBeginPath(R.vg);nvgMoveTo(R.vg,p[1],p[2]);for i=3,#p,2 do nvgLineTo(R.vg,p[i],p[i+1]) end;nvgClosePath(R.vg);nvgFillColor(R.vg,rgba(c,a));nvgFill(R.vg) end
function R.text(x,y,text,size,c,align) nvgFontFaceId(R.vg,R.font);nvgFontSize(R.vg,size or 12);nvgTextAlign(R.vg,(align or NVG_ALIGN_CENTER)+NVG_ALIGN_MIDDLE);nvgFillColor(R.vg,rgba(c or {218,211,184}));nvgText(R.vg,x,y,text,nil) end
function R.init()
 R.vg=nvgCreate(1);R.font=nvgCreateFont(R.vg,"ink","Fonts/MiSans-Regular.ttf")
 for key,path in pairs(require("war.Assets")) do R.images[key]=nvgCreateImage(R.vg,path,0) end
 print("[Render] graphics ready")
end
function R.close() if R.vg then for _,img in pairs(R.images) do if img>0 then nvgDeleteImage(R.vg,img) end end;nvgDelete(R.vg);R.vg=nil end end
function R.project(g,x,y)
 local scale=32*g.zoom;return R.w*.5+(x-y-g.camera.x+g.camera.y)*scale,R.h*.47+(x+y-g.camera.x-g.camera.y)*scale*.5
end
function R.unproject(g,x,y)
 local scale=32*g.zoom;local a=(x-R.w*.5)/scale;local b=(y-R.h*.47)/(scale*.5)
 return g.camera.x+(a+b)*.5,g.camera.y+(b-a)*.5
end
function R.pan(g,dx,dy)
 local scale=32*g.zoom;local a=dx/scale;local b=dy/(scale*.5);g.camera.x=U.clamp(g.camera.x-(a+b)*.5,3,D.MAP-3);g.camera.y=U.clamp(g.camera.y-(b-a)*.5,3,D.MAP-3)
end
function R.zoom(g,factor,x,y)
 local wx,wy=R.unproject(g,x or R.w/2,y or R.h/2);g.zoom=U.clamp(g.zoom*factor,.24,2.8);local ax,ay=R.unproject(g,x or R.w/2,y or R.h/2);g.camera.x=U.clamp(g.camera.x+wx-ax,3,D.MAP-3);g.camera.y=U.clamp(g.camera.y+wy-ay,3,D.MAP-3)
end
function R.sprite(key,x,y,size,tint,alpha)
 local img=R.images[key];if not img or img<=0 then return false end
 local ox,oy=x-size*.5,y-size*.86
 nvgBeginPath(R.vg);nvgRect(R.vg,ox,oy,size,size)
 nvgFillPaint(R.vg,nvgImagePatternTinted(R.vg,ox,oy,size,size,0,img,rgba(tint or {255,255,255},alpha or 255)));nvgFill(R.vg);return true
end
local function diamond(g,x,y,c,a)
 local px,py=R.project(g,x+.5,y+.5);local w=32*g.zoom;local h=w*.5
 R.poly({px-w,py,px,py-h,px+w,py,px,py+h},c,a)
end
local function building(g,e,x,y) BodyArt.structure(R,g,e,x,y) end
local function unit(g,e,x,y)
 local scale=g.zoom;local d=D.units[e.kind];local color=e.faction>0 and D.factions[e.faction].color or {173,74,64}
 R.ellipse(x,y+2*scale,13*scale,5*scale,{13,19,17},110)
 if g.selection[e.id] then
  nvgBeginPath(R.vg);nvgEllipse(R.vg,x,y+3*scale,18*scale,8*scale);nvgStrokeWidth(R.vg,1.8);nvgStrokeColor(R.vg,nvgRGBA(204,217,155,255));nvgStroke(R.vg)
 end
 if e.faction>0 then local activity,angle=Motion.activity(g,e);Cells.draw(R.vg,e.kind,e.faction,x,y,scale,g.flowTime or e.age,e.id,activity,angle)
 else
  local c=e.kind=="shadow" and {136,105,173} or {179,103,124}
  R.ellipse(x,y-18*scale,18*scale,13*scale,c,190)
  for j=0,5 do local a=j*math.pi/3;R.line(x+math.cos(a)*17*scale,y-18*scale+math.sin(a)*11*scale,x+math.cos(a)*25*scale,y-18*scale+math.sin(a)*19*scale,c,2*scale,190) end
  R.ellipse(x,y-18*scale,6*scale,4*scale,{51,29,58})
 end
 R.ellipse(x,y+4*scale,3*scale,2*scale,color)
 if e.hp<e.maxHp or g.selection[e.id] then R.rect(x-15*scale,y-52*scale,30*scale,3*scale,{28,30,23});R.rect(x-15*scale,y-52*scale,30*scale*math.max(0,e.hp/e.maxHp),3*scale,color) end
 if e.satiety<20 then R.text(x,y-62*scale,"饥",10*scale,{229,183,100}) elseif e.sanity<25 then R.text(x,y-62*scale,"惧",10*scale,{199,155,211}) end
 if next(e.cargo) then R.ellipse(x+11*scale,y-12*scale,4*scale,5*scale,{177,150,97}) end
end
function R.draw(g)
 if not R.vg then return end
 local dpr=graphics:GetDPR();R.w,R.h=graphics:GetWidth()/dpr,graphics:GetHeight()/dpr
 nvgBeginFrame(R.vg,R.w,R.h,dpr)
 R.rect(0,0,R.w,R.h,{27,20,32})
 local s=g.state;local fa=s.factions[1];local cx,cy=g.camera.x,g.camera.y;local radius=math.ceil((R.w+R.h)/(64*g.zoom))+3
 local xmin,xmax=math.max(1,math.floor(cx-radius)),math.min(D.MAP,math.ceil(cx+radius));local ymin,ymax=math.max(1,math.floor(cy-radius)),math.min(D.MAP,math.ceil(cy+radius))
 local winter=select(3,V.clock(s))==2
 local sorted,details={},{}
 for cy=math.floor((ymin-1)/D.CHUNK),math.floor((ymax-1)/D.CHUNK) do for cx=math.floor((xmin-1)/D.CHUNK),math.floor((xmax-1)/D.CHUNK) do
 local chunk=s.chunks[cy*s.chunkStride+cx+1]
 for y=math.max(ymin,chunk.y1),math.min(ymax,chunk.y2) do for x=math.max(xmin,chunk.x1),math.min(xmax,chunk.x2) do
  local px,py=R.project(g,x+.5,y+.5)
  if px>-60 and py>-130 and px<R.w+60 and py<R.h+130 then
   local k=U.key(x,y);local seen=fa.seen[k];local visible=fa.visible[k]
   if seen then
    local biome=Art.ground(R,g,s,x,y,visible,winter)
    if visible then details[#details+1]={x=x,y=y,biome=biome} end
    local res=s.resources[k]
    if res and res.amount>0 then sorted[#sorted+1]={resource=res,x=px,y=py,sort=x+y} end
   end
  end
 end end end end
 for _,tile in ipairs(details) do Art.detail(R,g,s,tile.x,tile.y,tile.biome) end
 Bloodstream.draw(R,g,s,xmin,xmax,ymin,ymax)
 for _,e in pairs(s.entities) do if U.alive(e) and (e.faction==1 or fa.visible[U.key(e.x,e.y)]) then
  local wx,wy=Motion.position(g,e);local x,y=R.project(g,wx,wy);if x>-150 and y>-150 and x<R.w+150 and y<R.h+150 then sorted[#sorted+1]={entity=e,x=x,y=y,sort=wx+wy} end
 end end
 table.sort(sorted,function(a,b) if a.sort==b.sort then return a.resource~=nil and b.entity~=nil end return a.sort<b.sort end)
 for _,item in ipairs(sorted) do local x,y=item.x,item.y
  if item.entity then local e=item.entity;if e.category=="building" then building(g,e,x,y) else unit(g,e,x,y) end
  else local r=item.resource;local z=g.zoom;local visible=fa.visible[U.key(r.x,r.y)];local tint=visible and {255,255,255} or {100,108,99}
   BodyArt.resource(R,g,s,r,x,y,visible)
  end
 end
 local _,fraction,season=V.clock(s)
 local darkness=fraction>=.75 and 105 or fraction>.6 and math.floor((fraction-.6)/.15*45) or 0
 if darkness>0 then R.rect(0,0,R.w,R.h,{20,28,43},darkness) end
 -- Revival is expressed by tissue perfusion, rather than outdoor rainfall.
 for _,ef in ipairs(s.effects) do if fa.visible[U.key(ef.tx,ef.ty)] then local x,y=R.project(g,ef.x,ef.y);local tx,ty=R.project(g,ef.tx,ef.ty);R.line(x,y-25*g.zoom,tx,ty-25*g.zoom,{231,215,150},ef.kind=="hit" and 3 or 1.5,200) end end
 if g.placement then
  local offset=D.buildings[g.placement].size%2==0 and 0 or .5;local bx,by=math.floor(g.pointer.wx)+offset,math.floor(g.pointer.wy)+offset;local x,y=R.project(g,bx,by);local valid=W.canBuild(s,g.placement,bx,by,1);local size=D.buildings[g.placement].size*32*g.zoom
  R.poly({x-size,y,x,y-size*.5,x+size,y,x,y+size*.5},valid and {113,181,157} or {204,93,72},100)
  R.text(x,y-28*g.zoom,D.buildings[g.placement].name,13,{237,224,185})
 end
 if g.drag and g.drag.box then local a=g.drag;local x,y=math.min(a.x,a.tx),math.min(a.y,a.ty);local w,h=math.abs(a.tx-a.x),math.abs(a.ty-a.y);R.rect(x,y,w,h,{123,179,157},35);R.line(x,y,x+w,y,{176,212,167},1);R.line(x+w,y,x+w,y+h,{176,212,167},1);R.line(x+w,y+h,x,y+h,{176,212,167},1);R.line(x,y+h,x,y,{176,212,167},1) end
 if g.marker then local x,y=R.project(g,g.marker.x,g.marker.y);local r=12+math.sin(g.realTime*5)*4;nvgBeginPath(R.vg);nvgEllipse(R.vg,x,y,r,r*.5);nvgStrokeWidth(R.vg,1.5);nvgStrokeColor(R.vg,nvgRGBA(225,210,153,220));nvgStroke(R.vg) end
 -- Soft etched vignette; keeps scene edges quieter than the command area.
 nvgBeginPath(R.vg);nvgRect(R.vg,0,0,R.w,R.h);nvgFillPaint(R.vg,nvgRadialGradient(R.vg,R.w*.5,R.h*.45,R.h*.25,R.w*.7,nvgRGBA(40,12,31,0),nvgRGBA(34,12,32,140)));nvgFill(R.vg)
 nvgEndFrame(R.vg)
end
function R.home(g)
 local e=U.nearest(g.state,D.factions[1].x,D.factions[1].y,function(v) return v.faction==1 and (v.kind=="core" or v.kind=="worker") end)
 g.camera.x,g.camera.y=e and e.x or D.factions[1].x,e and e.y or D.factions[1].y
end
function R.mapArea(l)
 local size=math.min(l.w,l.h);return l.x+(l.w-size)*.5,l.y+(l.h-size)*.5,size
end
function R.mapPoint(l,x,y)
 local px,py,size=R.mapArea(l)
 return U.clamp((x-px)/size*D.MAP,3,D.MAP-3),U.clamp((y-py)/size*D.MAP,3,D.MAP-3)
end
function R.minimap(vg,g,l,overview)
 local old=R.vg;R.vg=vg;local s=g.state;local px,py,size=R.mapArea(l)
 R.rect(l.x,l.y,l.w,l.h,{24,31,27})
 if overview then Art.overview(R,s,px,py,size);BodyArt.atlas(R,s,px,py,size)
 else for _,bin in pairs(s.factions[1].mapSeen) do
  local c=D.biomes[bin.terrain].color
  R.rect(px+(bin.x-1)*size/D.MAP,py+(bin.y-1)*size/D.MAP,D.MAP_BIN*size/D.MAP+.4,D.MAP_BIN*size/D.MAP+.4,c,s.factions[1].visible[bin.sample] and 220 or 125)
 end end
 for _,e in pairs(s.entities) do if U.alive(e) and (e.faction==1 or s.factions[1].visible[U.key(e.x,e.y)]) then
  local c=e.faction>0 and D.factions[e.faction].color or {202,124,88}
  local radius=e.category=="building" and (size>200 and 3 or 2) or 1.2
  R.ellipse(px+e.x*size/D.MAP,py+e.y*size/D.MAP,radius,radius,c)
 end end
 local a,b=R.unproject(g,0,0);local c,d=R.unproject(g,R.w,R.h)
 local bx,by,bw,bh=math.min(a,c),math.min(b,d),math.abs(a-c),math.abs(b-d)
 local camx,camy=px+g.camera.x*size/D.MAP,py+g.camera.y*size/D.MAP
 R.ellipse(camx,camy,5,3,{241,226,171},150)
 R.line(px+bx*size/D.MAP,py+by*size/D.MAP,px+(bx+bw)*size/D.MAP,py+by*size/D.MAP,{225,213,171},1,150)
 R.line(px+(bx+bw)*size/D.MAP,py+by*size/D.MAP,px+(bx+bw)*size/D.MAP,py+(by+bh)*size/D.MAP,{225,213,171},1,150)
 R.line(px+(bx+bw)*size/D.MAP,py+(by+bh)*size/D.MAP,px+bx*size/D.MAP,py+(by+bh)*size/D.MAP,{225,213,171},1,150)
 R.line(px+bx*size/D.MAP,py+(by+bh)*size/D.MAP,px+bx*size/D.MAP,py+by*size/D.MAP,{225,213,171},1,150)
 R.line(px,py,px+size,py,{92,107,80},1);R.line(px+size,py,px+size,py+size,{92,107,80},1)
 R.line(px+size,py+size,px,py+size,{92,107,80},1);R.line(px,py+size,px,py,{92,107,80},1)
 R.vg=old
end
return R
