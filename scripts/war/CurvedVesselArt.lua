-- Stroke the exact sampled curves used by collision; image materials add fine detail.
local V,D,U,C=require('war.Vessels'),require('war.Data'),require('war.Util'),require('war.VesselCurves')
local Organs=require('war.Organs')
local Images=require('war.OrganArt')
local A={}
local function known(g,s,x,y) return g.fogDisabled or g.vesselSurvey or s.factions[1].seen[U.key(x,y)] end
local function palette(e)
 if e.system=='portal' then return {177,147,197},{158,129,191},'portal' end
 if e.oxygen=='low' then return {151,149,211},{130,132,189},'vein' end
 if e.oxygen=='exchange' then return {219,143,177},{197,120,162},'artery' end
 return {241,147,161},{205,113,142},'artery'
end
local function curve(R,e,ox,oy,scale,x1,x2,y1,y2,append)
 if not append then nvgBeginPath(R.vg) end;local open=false;local any=false;local r=e.width*.5+6
 for _,c in ipairs(e.cubics) do
  local left,right,top,bottom=math.huge,-math.huge,math.huge,-math.huge
  for _,p in ipairs(c) do left=math.min(left,p[1]);right=math.max(right,p[1]);top=math.min(top,p[2]);bottom=math.max(bottom,p[2]) end
  if left-r<=x2 and right+r>=x1 and top-r<=y2 and bottom+r>=y1 then
   if not open then nvgMoveTo(R.vg,ox+c[1][1]*scale,oy+c[1][2]*scale);open=true end
   nvgBezierTo(R.vg,ox+c[2][1]*scale,oy+c[2][2]*scale,ox+c[3][1]*scale,oy+c[3][2]*scale,ox+c[4][1]*scale,oy+c[4][2]*scale);any=true
  else open=false end
 end
 return any
end
local function stroke(R,c,width,alpha)
 nvgLineCap(R.vg,NVG_ROUND);nvgLineJoin(R.vg,NVG_ROUND);nvgStrokeWidth(R.vg,width);nvgStrokeColor(R.vg,nvgRGBA(c[1],c[2],c[3],alpha));nvgStroke(R.vg)
end
function A.draw(R,g,s,x1,x2,y1,y2)
 local net=V.forDisplay(s);local scale=32*g.zoom;local ox,oy=R.project(g,0,0)
 local heartBlend=Organs.blend(2*math.max(Organs.byId.heart.rx,Organs.byId.heart.ry)*net.scale*scale)
 -- Chamber lumens use exactly the ellipses in the collision geometry.
 for i,n in ipairs(net.nodes) do if heartBlend>0 and n.heart and n.x+(n.rx or 0)*net.scale>=x1 and n.x-(n.rx or 0)*net.scale<=x2 and n.y+(n.ry or 0)*net.scale>=y1 and n.y-(n.ry or 0)*net.scale<=y2 then
  local x,y=R.project(g,n.x,n.y);local rx,ry=n.rx*net.scale*scale,n.ry*net.scale*scale
  local wall,lumen=palette({oxygen=i<=2 and 'low' or 'high'})
  R.ellipse(x,y,rx+4*scale,ry+4*scale,{111,60,91},math.floor(255*heartBlend));R.ellipse(x,y,rx+2*scale,ry+2*scale,wall,math.floor(255*heartBlend));R.ellipse(x,y,rx,ry,lumen,math.floor(255*heartBlend))
 end end
 -- Deterministic depth order makes a crossing an overpass, not a visual junction.
 local materialCount=0
 local function paint(e)
  local alpha=e.system=="valve" and heartBlend or 1;if alpha<=0 then return end
  local wall,lumen,kind=palette(e);local width=math.max(.75,e.width*scale)
  stroke(R,{148,116,155},width+math.max(.8,6*scale),math.floor(255*alpha));stroke(R,wall,width+2*scale,math.floor(245*alpha))
  if g.zoom>=.25 and Images.hasVessel(kind) and materialCount<96 then
   local candidates={};local tile=math.max(8,e.width*1.5)
   for by=math.floor(y1/128),math.floor(y2/128) do for bx=math.floor(x1/128),math.floor(x2/128) do for _,i in ipairs(e.segments[bx..':'..by] or {}) do
    local p=e.points[i];if p[1]>=x1-e.width and p[1]<=x2+e.width and p[2]>=y1-e.width and p[2]<=y2+e.width then candidates[math.floor(e.arc[i]/tile)]=true end
   end end end
   local ordered={};for index in pairs(candidates) do ordered[#ordered+1]=index end;table.sort(ordered)
   for _,index in ipairs(ordered) do if materialCount<96 then
    local first,last=index*tile,math.min(e.length,(index+1)*tile)
    if last>first and Images.vesselFill(R.vg,kind,ox,oy,scale,e,first,last) then materialCount=materialCount+1 end
   end end
   curve(R,e,ox,oy,scale,x1,x2,y1,y2)
  end
  stroke(R,lumen,math.max(.4,width-2*scale),math.floor(255*alpha))
  if g.zoom>.05 then stroke(R,wall,math.max(.5,.65*scale),90) end
 end
 for layer=1,3 do
  local groups={};local order={}
  for _,e in ipairs(net.edges) do
   local depth=e.oxygen=='low' and 1 or e.system=='capillary' and 3 or 2
   if layer==depth then
    if g.zoom<=.05 then
     local key=(e.system=='portal' and 'portal' or e.oxygen)..':'..e.width
     if not groups[key] then groups[key]={};order[#order+1]=key end
     local group=groups[key];group[#group+1]=e
    elseif curve(R,e,ox,oy,scale,x1,x2,y1,y2) then paint(e) end
   end
  end
  -- Batch matching far-view materials without changing curve or lane geometry.
  for _,key in ipairs(order) do local group=groups[key];local any=false;nvgBeginPath(R.vg)
   for _,e in ipairs(group) do any=curve(R,e,ox,oy,scale,x1,x2,y1,y2,true) or any end
   if any then paint(group[1]) end
  end
 end
 for _,gate in ipairs(net.gates) do
  if gate.x>=x1 and gate.x<=x2 and gate.y>=y1 and gate.y<=y2 and known(g,s,gate.x,gate.y) then
   local x,y=R.project(g,gate.x,gate.y);local radius=math.max(2,gate.radius*scale*.4)
   R.ellipse(x,y,radius+math.max(1,scale),radius+math.max(1,scale),{130,92,100},220)
   R.ellipse(x,y,radius,radius,{255,214,141},240)
  end
 end
end
function A.details(R,g,s,x1,x2,y1,y2)
 if g.zoom<.3 then return end
 local net=V.forDisplay(s);local z=g.zoom;local scale=32*z;local t=g.flowTime or s.time;local count=0
 for id,e in ipairs(net.edges) do
  local spacing=math.max(8,100/scale);local phase=(t*9+id*13)%spacing
  ---@type number?
  local first
  ---@type number?
  local last
  -- Find the visible arc span before considering particles on a long vessel.
  local candidates={}
  for by=math.floor(y1/128),math.floor(y2/128) do for bx=math.floor(x1/128),math.floor(x2/128) do for _,i in ipairs(e.segments[bx..':'..by] or {}) do candidates[i]=true end end end
  for i in pairs(candidates) do local p,q=e.points[i-1],e.points[i]
   if math.min(p[1],q[1])<=x2 and math.max(p[1],q[1])>=x1 and math.min(p[2],q[2])<=y2 and math.max(p[2],q[2])>=y1 then first=math.min(first or math.huge,e.arc[i-1]);last=math.max(last or 0,e.arc[i]) end
  end
  if first then for d=math.ceil((first-phase)/spacing)*spacing+phase,last,spacing do
   local wx,wy,vx,vy=C.at(e,d)
   if wx>=x1 and wx<=x2 and wy>=y1 and wy<=y2 and known(g,s,wx,wy) and count<48 then
    local x,y=R.project(g,wx,wy);local wall=palette(e);local a=math.max(3,5*z)
    R.poly({x+vx*a,y+vy*a,x-vx*a-vy*a*.5,y-vy*a+vx*a*.5,x-vx*a+vy*a*.5,y-vy*a-vx*a*.5},wall,140)
    local offset=math.sin(id+d*.2)*e.width*.18;local rx,ry=R.project(g,wx-vy*offset,wy+vx*offset)
    nvgSave(R.vg);nvgTranslate(R.vg,rx,ry);nvgRotate(R.vg,math.atan(vy,vx))
    R.ellipse(0,0,9*z,7*z,{225,107,133},210);R.ellipse(0,0,4*z,3*z,{133,48,78},180)
    R.ellipse(-2*z,2*z,z,z,{51,26,47});R.ellipse(2*z,2*z,z,z,{51,26,47});nvgRestore(R.vg);count=count+1
   end
  end end
 end
 for _,gate in ipairs(net.gates) do if gate.x>=x1 and gate.x<=x2 and gate.y>=y1 and gate.y<=y2 and known(g,s,gate.x,gate.y) then
  local x,y=R.project(g,gate.x,gate.y);R.text(x,y-19,'膜通行口',11,{144,99,40})
 end end
 for _,n in ipairs(net.nodes) do if n.heart and n.x>=x1 and n.x<=x2 and n.y>=y1 and n.y<=y2 and known(g,s,n.x,n.y) then
  local x,y=R.project(g,n.x,n.y);R.text(x,y,n.name,13,{98,61,93})
 end end
end
function A.atlas(R,s,x,y,scale,all)
 local g={state=s,zoom=scale/32,fogDisabled=all,vesselSurvey=all,camera={x=0,y=0}}
 -- Atlas origin is explicit and doesn't change the real gameplay camera.
 local proxy=setmetatable({project=function(_,wx,wy) return x+wx*scale,y+wy*scale end},{__index=R})
 nvgSave(R.vg);nvgIntersectScissor(R.vg,x,y,D.width(s)*scale,D.height(s)*scale)
 A.draw(proxy,g,s,1,D.width(s),1,D.height(s))
 if not all then
  local oldW,oldH=R.w,R.h;proxy.w,proxy.h=D.width(s)*scale,D.height(s)*scale
  nvgTranslate(R.vg,x,y);proxy.project=function(_,wx,wy) return wx*scale,wy*scale end
  require("war.SmoothTerrain").fog(proxy,g,s,1,D.width(s),1,D.height(s));R.w,R.h=oldW,oldH
 end
 nvgRestore(R.vg)
end
return A
