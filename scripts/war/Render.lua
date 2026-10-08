-- Pure 2D top-down world: 2D scaffold + NanoVG mode B (logical pixels / DPR).
local D,U,V,W=require("war.Data"),require("war.Util"),require("war.Survival"),require("war.World")
local Cells,Art=require("war.Cells"),require("war.TerrainArt")
local BodyArt=require("war.BodyArt")
local Motion,Bloodstream=require("war.Motion"),require("war.Bloodstream")
local View=require("war.View")
local VesselArt=require("war.VesselArt")
local Smooth=require("war.SmoothTerrain")
local Generated=require("war.UIArt")
local Palette=require("war.MapPalette")
local R={
 ---@type NVGContextWrapper
 vg=nil,font=-1,w=1280,h=720}
local function rgba(c,a) return nvgRGBA(math.floor(c[1]),math.floor(c[2]),math.floor(c[3]),a or 255) end
function R.rect(x,y,w,h,c,a) nvgBeginPath(R.vg);nvgRect(R.vg,x,y,w,h);nvgFillColor(R.vg,rgba(c,a));nvgFill(R.vg) end
function R.line(x,y,tx,ty,c,w,a) nvgBeginPath(R.vg);nvgMoveTo(R.vg,x,y);nvgLineTo(R.vg,tx,ty);nvgStrokeWidth(R.vg,w or 1);nvgStrokeColor(R.vg,rgba(c,a));nvgStroke(R.vg) end
function R.ellipse(x,y,rx,ry,c,a) nvgBeginPath(R.vg);nvgEllipse(R.vg,x,y,rx,ry);nvgFillColor(R.vg,rgba(c,a));nvgFill(R.vg) end
function R.poly(p,c,a) nvgBeginPath(R.vg);nvgMoveTo(R.vg,p[1],p[2]);for i=3,#p,2 do nvgLineTo(R.vg,p[i],p[i+1]) end;nvgClosePath(R.vg);nvgFillColor(R.vg,rgba(c,a));nvgFill(R.vg) end
function R.text(x,y,text,size,c,align) nvgFontFaceId(R.vg,R.font);nvgFontSize(R.vg,size or 12);nvgTextAlign(R.vg,(align or NVG_ALIGN_CENTER)+NVG_ALIGN_MIDDLE);nvgFillColor(R.vg,rgba(c or {218,211,184}));nvgText(R.vg,x,y,text,nil) end
function R.init()
 R.vg=nvgCreate(1);R.font=nvgCreateFont(R.vg,"ink","Fonts/MiSans-Regular.ttf")
 Cells.init(R.vg)
 Generated.init(R.vg)
 print("[Render] graphics ready")
end
function R.prepare(s) Smooth.prepare(s) end
function R.close() if R.vg then require("war.ReferenceArt").release(R.vg); Cells.release(R.vg);Generated.release(R.vg);require('war.OrganArt').release(R.vg);nvgDelete(R.vg);R.vg=nil end end
function R.project(g,x,y) return View.project(g,R.w,R.h,x,y) end
function R.unproject(g,x,y) return View.unproject(g,R.w,R.h,x,y) end
function R.pan(g,dx,dy) View.pan(g,dx,dy) end
function R.zoom(g,factor,x,y)
 local wx,wy=R.unproject(g,x or R.w/2,y or R.h/2);g.zoom=U.clamp(g.zoom*factor,View.minZoom(g.state,R.w,R.h),2.8);local ax,ay=R.unproject(g,x or R.w/2,y or R.h/2);g.camera.x=U.clamp(g.camera.x+wx-ax,3,D.width(g.state)-3);g.camera.y=U.clamp(g.camera.y+wy-ay,3,D.height(g.state)-3)
end
local function building(g,e,x,y)
 BodyArt.structure(R,g,e,x,y)
 if g.selection[e.id] then
  nvgBeginPath(R.vg);nvgCircle(R.vg,x,y,BodyArt.radius(e.kind)*g.zoom+4*g.zoom)
  nvgStrokeWidth(R.vg,2);nvgStrokeColor(R.vg,nvgRGBA(105,235,203,240));nvgStroke(R.vg)
 end
end
local function unit(g,e,x,y)
 local z=g.zoom;local radius=Cells.radius(e.kind)*z
 if g.selection[e.id] then
  nvgBeginPath(R.vg);nvgCircle(R.vg,x,y,radius+5*z);nvgStrokeWidth(R.vg,1.7*z)
  nvgStrokeColor(R.vg,nvgRGBA(105,235,203,240));nvgStroke(R.vg)
 end
 local activity,angle=Motion.activity(g,e)
 Cells.draw(R.vg,e.kind,e.faction,x,y,z,g.flowTime or e.age,e.id,activity,angle)
 if e.hp<e.maxHp or g.selection[e.id] then
  local by=y-radius-9*z
  R.rect(x-15*z,by,30*z,3*z,{28,30,33});R.rect(x-15*z,by,30*z*math.max(0,e.hp/e.maxHp),3*z,{133,207,168})
 end
 if e.satiety<20 then R.text(x,y-radius-20*z,"饥",10*z,{229,183,100}) elseif e.sanity<25 then R.text(x,y-radius-20*z,"惧",10*z,{199,155,211}) end
 if next(e.cargo) then R.ellipse(x+radius*.65,y+radius*.6,3*z,3*z,{221,188,114}) end
end
function R.draw(g)
 if not R.vg then return end
 local dpr=graphics:GetDPR();R.w,R.h=graphics:GetWidth()/dpr,graphics:GetHeight()/dpr
 nvgBeginFrame(R.vg,R.w,R.h,dpr)
 R.rect(0,0,R.w,R.h,g.state.anatomyVersion==3 and {255,255,255} or Palette.background)
 -- The opaque menu artwork covers the world; do not tessellate a hidden map.
 if g.started==false then nvgEndFrame(R.vg);return end
 local s=g.state;local fa=s.factions[1];local reveal=g.fogDisabled and s.anatomyVersion~=3
 local xmin,xmax,ymin,ymax=View.bounds(g,R.w,R.h,4)
 local winter=select(3,V.clock(s))==2
 Art.beginFrame()
 require('war.OrganArt').beginFrame()
 local sorted,details={},{}
 local stride=Art.stride(g,xmin,xmax,ymin,ymax)
 R.terrainStride=stride
 if W.hasVessels(s) then
  Smooth.beginFrame();Smooth.draw(R,g,s,xmin,xmax,ymin,ymax)
  VesselArt.coarse(R,g,s,xmin,xmax,ymin,ymax)
  Smooth.detail(R,g,s,xmin,xmax,ymin,ymax)
  VesselArt.details(R,g,s,xmin,xmax,ymin,ymax)
  Smooth.fog(R,g,s,xmin,xmax,ymin,ymax)
  if g.zoom>=.8 then for k,res in pairs(s.resources) do if res.amount>0 and (reveal or fa.seen[k]) and res.x>=xmin and res.x<=xmax and res.y>=ymin and res.y<=ymax then
   local px,py=R.project(g,res.x+.5,res.y+.5);sorted[#sorted+1]={resource=res,x=px,y=py,layer=1,order=k}
  end end end
  if s.anatomyVersion~=3 and g.zoom<.035 and (g.fogDisabled or g.vesselSurvey) then local px,py=R.project(g,0,0);BodyArt.atlas(R,s,px,py,D.width(s)*32*g.zoom,D.height(s)*32*g.zoom) end
 elseif stride>1 then
  Art.coarse(R,g,s,xmin,xmax,ymin,ymax,stride)
  VesselArt.coarse(R,g,s,xmin,xmax,ymin,ymax)
  if s.anatomyVersion~=3 and g.zoom<.035 and (g.fogDisabled or g.vesselSurvey) then
   local px,py=R.project(g,0,0);BodyArt.atlas(R,s,px,py,D.width(s)*32*g.zoom,D.height(s)*32*g.zoom)
  end
 else
  for y=ymin,ymax do for x=xmin,xmax do
   local k=U.key(x,y);local seen=g.fogDisabled or fa.seen[k];local visible=reveal or fa.visible[k]
   if seen or g.vesselSurvey then
    local biome=Art.ground(R,g,s,x,y,visible or g.vesselSurvey,winter)
    if visible then details[#details+1]={x=x,y=y,biome=biome} end
    local res=s.resources[k]
    if seen and res and res.amount>0 then local px,py=R.project(g,x+.5,y+.5);sorted[#sorted+1]={resource=res,x=px,y=py,layer=1,order=k} end
   end
  end end
  for _,tile in ipairs(details) do Art.detail(R,g,s,tile.x,tile.y,tile.biome) end
  Bloodstream.draw(R,g,s,xmin,xmax,ymin,ymax)
  VesselArt.draw(R,g,s,xmin,xmax,ymin,ymax)
 end
 require("war.NasalArt").draw(R,g)
 for _,e in pairs(s.entities) do if U.alive(e) and (reveal or e.faction==1 or fa.visible[U.key(e.x,e.y)]) then
  local wx,wy=Motion.position(g,e);local x,y=R.project(g,wx,wy);if x>-150 and y>-150 and x<R.w+150 and y<R.h+150 then sorted[#sorted+1]={entity=e,x=x,y=y,layer=e.category=="building" and 2 or 3,order=e.id} end
 end end
 table.sort(sorted,function(a,b) if a.layer~=b.layer then return a.layer<b.layer end return a.order<b.order end)
 for _,item in ipairs(sorted) do local x,y=item.x,item.y
  if item.entity then local e=item.entity
   if g.zoom<.14 then
    local c=e.faction>0 and D.factions[e.faction].color or {202,124,88}
    local radius=e.category=="building" and 3 or 2
    if g.selection[e.id] then R.ellipse(x,y,radius+2,radius+2,{234,235,184}) end
    R.ellipse(x,y,radius,radius,c)
   elseif e.category=="building" then building(g,e,x,y) else unit(g,e,x,y) end
  else local r=item.resource;local z=g.zoom;local visible=reveal or fa.visible[U.key(r.x,r.y)];local tint=visible and {255,255,255} or {100,108,99}
   BodyArt.resource(R,g,s,r,x,y,visible)
  end
 end
 local _,fraction,season=V.clock(s)
 local darkness=not s.campaign and (fraction>=.75 and 105 or fraction>.6 and math.floor((fraction-.6)/.15*45) or 0) or 0
 if darkness>0 then R.rect(0,0,R.w,R.h,{20,28,43},darkness) end
 -- Revival is expressed by tissue perfusion, rather than outdoor rainfall.
 for _,ef in ipairs(s.effects) do if reveal or fa.visible[U.key(ef.tx,ef.ty)] then local x,y=R.project(g,ef.x,ef.y);local tx,ty=R.project(g,ef.tx,ef.ty);R.line(x,y,tx,ty,{231,215,150},ef.kind=="hit" and 3 or 1.5,200) end end
 if g.placement then
  local offset=D.buildings[g.placement].size%2==0 and 0 or .5;local bx,by=math.floor(g.pointer.wx)+offset,math.floor(g.pointer.wy)+offset;local x,y=R.project(g,bx,by);local valid=W.canBuild(s,g.placement,bx,by,1);local size=D.buildings[g.placement].size*32*g.zoom
  R.rect(x-size*.5,y-size*.5,size,size,valid and {113,181,157} or {204,93,72},100)
  R.text(x,y-size*.5-14*g.zoom,D.buildings[g.placement].name,13,{237,224,185})
 end
 if g.drag and g.drag.box then local a=g.drag;local x,y=math.min(a.x,a.tx),math.min(a.y,a.ty);local w,h=math.abs(a.tx-a.x),math.abs(a.ty-a.y);R.rect(x,y,w,h,{123,179,157},35);R.line(x,y,x+w,y,{176,212,167},1);R.line(x+w,y,x+w,y+h,{176,212,167},1);R.line(x+w,y+h,x,y+h,{176,212,167},1);R.line(x,y+h,x,y,{176,212,167},1) end
 if g.marker then
  local elapsed=g.realTime-(g.marker.born or g.realTime);local alpha=math.floor(240*math.max(0,1-elapsed/.9))
  local x,y=R.project(g,g.marker.x,g.marker.y);local radius=10+elapsed*24
  local c=g.marker.kind=="attackmove" and {255,141,151} or {105,235,203}
  nvgBeginPath(R.vg);nvgCircle(R.vg,x,y,radius);nvgStrokeWidth(R.vg,2);nvgStrokeColor(R.vg,nvgRGBA(c[1],c[2],c[3],alpha));nvgStroke(R.vg)
  R.line(x-4,y,x+4,y,c,1.5,alpha);R.line(x,y-4,x,y+4,c,1.5,alpha)
 end
 -- A faint cool edge wash keeps the map airy without obscuring the tissue.
 nvgBeginPath(R.vg);nvgRect(R.vg,0,0,R.w,R.h);nvgFillPaint(R.vg,nvgRadialGradient(R.vg,R.w*.5,R.h*.45,R.h*.25,R.w*.7,nvgRGBA(231,235,255,0),nvgRGBA(161,180,220,g.state.anatomyVersion==3 and 0 or 30)));nvgFill(R.vg)
 nvgEndFrame(R.vg)
end
function R.nasalOverview(g)
 if not g.state.campaign then return end
 local N=require("war.CampaignData").forState(g.state)
 local layout=require("war.UIModel").layout(R.w,R.h)
 local top=layout.narrow and 254 or layout.short and 148 or 180
 local availableH=math.max(64,R.h-layout.dock-20-top)
 g.zoom=math.min((R.w-40)/((N.bounds.w+14)*32),availableH/((N.bounds.h+28)*32))
 g.camera.x=N.bounds.x+N.bounds.w*.5
 -- Keep the battlefield between the HUD and command dock on portrait and landscape.
 local centerY=top+availableH*.5
 g.camera.y=N.bounds.y+N.bounds.h*.5+(R.h*.47-centerY)/(32*g.zoom)
end
function R.home(g)
 if g.state.campaign then
  if g.state.campaign.event.id=="trachea" then
   local home=require("war.TracheaTerrain").home;g.camera.x,g.camera.y=home.x,home.y-18;g.zoom=math.min(.4,math.max(.14,(R.w-48)/(36*32)));return
  end
  local N=require("war.CampaignData").forState(g.state);g.camera.x,g.camera.y=N.home.x-17,N.home.y
  g.zoom=math.min(.6,math.max(.24,math.min((R.w-32)/(76*32),math.max(160,R.h-270)/(72*32))))
  return
 end
 if g.zoom<.14 then g.zoom=1 end
 local home=W.starts(g.state)[1]
 local e=U.nearest(g.state,home.x,home.y,function(v) return v.faction==1 and (v.kind=="core" or v.kind=="worker") end)
 g.camera.x,g.camera.y=e and e.x or home.x,e and e.y or home.y
end
function R.mapArea(l,s)
 local scale=math.min(l.w/D.width(s),l.h/D.height(s))
 local width,height=D.width(s)*scale,D.height(s)*scale
 return l.x+(l.w-width)*.5,l.y+(l.h-height)*.5,width,height,scale
end
function R.mapPoint(l,x,y,s)
 local px,py,width,height,scale=R.mapArea(l,s)
 return U.clamp((x-px)/scale,3,D.width(s)-3),U.clamp((y-py)/scale,3,D.height(s)-3)
end
function R.minimap(vg,g,l,overview)
 local old=R.vg;R.vg=vg;local s=g.state;local reveal=g.fogDisabled and s.anatomyVersion~=3;local px,py,width,height,scale=R.mapArea(l,s)
 R.rect(l.x,l.y,l.w,l.h,s.anatomyVersion==3 and {255,255,255} or Palette.background)
 if W.hasVessels(s) then
  Smooth.overview(R,s,px,py,width,height,overview or g.fogDisabled)
  if s.anatomyVersion~=3 and (overview or g.fogDisabled) then BodyArt.atlas(R,s,px,py,width,height) end
 elseif overview or g.fogDisabled then Art.overview(R,s,px,py,width,height);BodyArt.atlas(R,s,px,py,width,height)
 else for _,bin in pairs(s.factions[1].mapSeen) do
  local c=D.biomes[bin.terrain].color
  R.rect(px+(bin.x-1)*scale,py+(bin.y-1)*scale,D.MAP_BIN*scale+.4,D.MAP_BIN*scale+.4,c,s.factions[1].visible[bin.sample] and 220 or 125)
 end end
 VesselArt.atlas(R,s,px,py,scale,overview or g.fogDisabled)
 if s.campaign and s.campaign.event.id=="trachea" then
  require("war.TracheaArt").atlas(R,g,px,py,scale)
  local home=require("war.CampaignData").forState(s).home
  R.text(px+home.x*scale+16,py+home.y*scale,"气管 · 已开放",11,{30,132,133})
 elseif s.campaign then
  -- The atlas shows the body's silhouette; locked tissue is not playable.
  R.rect(px,py,width,height,Palette.fog,150)
  require("war.NasalArt").atlas(R,g,px,py,scale)
  local home=require("war.CampaignData").forState(s).home;local nx,ny=home.x,home.y
  R.text(px+nx*scale,py+ny*scale-12,"鼻腔 · 已开放",11,{30,132,133})
  if height>180 then R.text(px+width*.5,py+height*.5,"其余组织尚未开放",11,{101,109,137}) end
 end
 for _,e in pairs(s.entities) do if U.alive(e) and (reveal or e.faction==1 or s.factions[1].visible[U.key(e.x,e.y)]) then
  local c=e.faction>0 and D.factions[e.faction].color or {202,124,88}
  local radius=e.category=="building" and (height>200 and 3 or 2) or 1.2
  R.ellipse(px+e.x*scale,py+e.y*scale,radius,radius,c)
 end end
 local a,b=R.unproject(g,0,0);local c,d=R.unproject(g,R.w,R.h)
 local x1,y1=U.clamp(math.min(a,c),1,D.width(s)),U.clamp(math.min(b,d),1,D.height(s))
 local x2,y2=U.clamp(math.max(a,c),1,D.width(s)),U.clamp(math.max(b,d),1,D.height(s))
 R.line(px+x1*scale,py+y1*scale,px+x2*scale,py+y1*scale,{113,140,184},1,190)
 R.line(px+x2*scale,py+y1*scale,px+x2*scale,py+y2*scale,{113,140,184},1,190)
 R.line(px+x2*scale,py+y2*scale,px+x1*scale,py+y2*scale,{113,140,184},1,190)
 R.line(px+x1*scale,py+y2*scale,px+x1*scale,py+y1*scale,{113,140,184},1,190)
 R.vg=old
end
return R
