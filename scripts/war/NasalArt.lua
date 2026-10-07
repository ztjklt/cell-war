-- Stylized mucosal relief; every solid ridge and vessel matches navigation geometry.
local G,T,U,W=require('war.NasalTerrain'),require('war.Territory'),require('war.Util'),require('war.World')
local A={colors={{30,132,133},{189,64,91},{157,105,36}}}
local View=require('war.View')
local decoration=setmetatable({},{__mode='k'})
local function path(R,g,p,rounded)
 nvgBeginPath(R.vg)
 if rounded then
  local x,y=R.project(g,(p[#p-1]+p[1])*.5,(p[#p]+p[2])*.5);nvgMoveTo(R.vg,x,y)
  for i=1,#p,2 do local j=i+2;if j>#p then j=1 end
   local ax,ay=R.project(g,p[i],p[i+1]);local bx,by=R.project(g,(p[i]+p[j])*.5,(p[i+1]+p[j+1])*.5)
   nvgQuadTo(R.vg,ax,ay,bx,by)
  end
 else
  for i=1,#p,2 do local x,y=R.project(g,p[i],p[i+1]);if i==1 then nvgMoveTo(R.vg,x,y) else nvgLineTo(R.vg,x,y) end end
 end
 nvgClosePath(R.vg)
end
local function stroke(R,color,width,alpha)
 nvgStrokeWidth(R.vg,width);nvgStrokeColor(R.vg,nvgRGBA(color[1],color[2],color[3],alpha or 255));nvgStroke(R.vg)
end
local function ownership(z) return z.contested and A.colors[3] or z.owner==2 and A.colors[2] or z.owner==1 and A.colors[1] or {177,162,195} end
local function ribbon(R,g,e,color,width,alpha)
 nvgBeginPath(R.vg)
 for i,p in ipairs(e.points) do local x,y=R.project(g,p[1],p[2]);if i==1 then nvgMoveTo(R.vg,x,y) else nvgLineTo(R.vg,x,y) end end
 nvgLineCap(R.vg,NVG_ROUND);nvgLineJoin(R.vg,NVG_ROUND);stroke(R,color,width,alpha)
end
local function vessel(R,g,e)
 local scale=32*g.zoom;local color=e.system=='vein' and {150,119,181} or {225,124,144}
 ribbon(R,g,e,{159,128,163},(e.width+2.8)*scale,240)
 ribbon(R,g,e,color,(e.width+1)*scale,240)
 ribbon(R,g,e,e.system=='vein' and {155,143,199} or {213,136,162},e.width*scale,255)
 ribbon(R,g,e,e.system=='vein' and {175,146,199} or {248,157,172},.55*scale,80)
 -- Flow decoration does not count toward army selection or territorial presence.
 local time=g.flowTime or g.state.time
 if g.zoom>=.12 then
  local distance=(time*7+e.id*11)%23;local count=0
  for i=2,#e.points do local p,q=e.points[i-1],e.points[i]
   local dx,dy=q[1]-p[1],q[2]-p[2];local length=math.sqrt(dx*dx+dy*dy)
   while distance<length and count<12 do
    local wx,wy=p[1]+dx*distance/length,p[2]+dy*distance/length;local x,y=R.project(g,wx,wy)
    if x>-12 and x<R.w+12 and y>-12 and y<R.h+12 then
     nvgSave(R.vg);nvgTranslate(R.vg,x,y);nvgRotate(R.vg,math.atan(dy,dx))
     R.ellipse(0,0,1.0*scale,.65*scale,{224,110,138},190);R.ellipse(0,0,.47*scale,.31*scale,{127,47,80},220);nvgRestore(R.vg)
    end
    distance=distance+23;count=count+1
   end;distance=distance-length
  end
 end
end
function A.draw(R,g)
 local c=g.state.campaign;if not c then return end
 if c.terrainVersion~=2 then require('war.NasalArtLegacy').draw(R,g);return end
 local left,top=R.project(g,G.bounds.x,G.bounds.y);local right,bottom=R.project(g,G.bounds.x+G.bounds.w,G.bounds.y+G.bounds.h)
 if right<0 or left>R.w or bottom<0 or top>R.h then return end
 local scale=32*g.zoom
 path(R,g,G.outline,true);stroke(R,{168,149,192},math.max(6,5*scale),235)
 path(R,g,G.outline,true)
 nvgFillPaint(R.vg,nvgLinearGradient(R.vg,left,top,right,bottom,nvgRGBA(248,222,230,255),nvgRGBA(216,204,238,255)));nvgFill(R.vg)
 path(R,g,G.outline,true);stroke(R,{252,242,247},math.max(1.2,1.1*scale),220)
 -- Separate region tint from anatomical structures: routes stay legible while contested.
 for i,z in ipairs(G.zones) do
  local color=ownership(c.event.zones[i]);path(R,g,z.polygon,false)
  nvgFillColor(R.vg,nvgRGBA(color[1],color[2],color[3],c.event.zones[i].contested and 34 or 22));nvgFill(R.vg)
 end
 -- Etched mucosal cells, bounded to the battlefield and clipped by actual ridges.
 if g.zoom>=.1 then
  local x1,x2,y1,y2=View.bounds(g,R.w,R.h,8)
  local sx,sy=G.bounds.x+8,G.bounds.y+8
  local firstX=sx+math.max(0,math.ceil((x1-sx)/11))*11
  local firstY=sy+math.max(0,math.ceil((y1-sy)/9))*9
  local net=W.vessels(g.state);local cached=decoration[net];if not cached then cached={};decoration[net]=cached end
  for yy=firstY,math.min(G.bounds.y+G.bounds.h-8,y2),9 do for xx=firstX,math.min(G.bounds.x+G.bounds.w-8,x2),11 do
   local x=xx+(U.hash(xx,yy,17)-.5)*5;local y=yy+(U.hash(xx,yy,23)-.5)*4
   local key=U.key(xx,yy);local show=cached[key]
   if show==nil then show=G.allowed(x,y) and not G.blocked(x,y) and net.sample(x,y).biome==0;cached[key]=show end
   if show then
    local px,py=R.project(g,x,y)
    if px>-20 and px<R.w+20 and py>-20 and py<R.h+20 then
     R.ellipse(px,py,1.6*scale,1.15*scale,{235,189,185},13)
     R.ellipse(px+.3*scale,py,.35*scale,.27*scale,{94,65,109},60)
    end
   end
  end end
 end
 for _,o in ipairs(G.obstacles) do
  path(R,g,o.polygon,true);stroke(R,{181,143,178},1.5*scale,210)
  path(R,g,o.polygon,true)
  nvgFillPaint(R.vg,nvgLinearGradient(R.vg,left,top,left,bottom,nvgRGBA(255,238,230,255),nvgRGBA(229,186,215,255)));nvgFill(R.vg)
  path(R,g,o.polygon,true);stroke(R,{255,212,194},math.max(1,.4*scale),180)
  if o.kind=='concha' then
   local x,y=R.project(g,o.x,o.y);local a,b=R.project(g,o.x-17,o.y-1)
   nvgBeginPath(R.vg);nvgMoveTo(R.vg,a,b);nvgBezierTo(R.vg,x-6*scale,y-1.5*scale,x+8*scale,y+1.5*scale,x+17*scale,y)
   stroke(R,{127,79,114},math.max(1,.5*scale),145)
   if g.zoom>=.14 then R.text(x,y,o.name,10,{111,75,110}) end
  end
 end
 -- Small vestibular cilia are visual detail, leaving broad maneuvering room.
 if g.zoom>=.2 then for i=1,7 do
  local x,y=R.project(g,G.bounds.x+16+i*1.8,G.bounds.y+119+i*1.7)
  nvgBeginPath(R.vg);nvgMoveTo(R.vg,x,y);nvgBezierTo(R.vg,x+scale*2,y-scale*2,x+scale*4,y-scale*3,x+scale*4.5,y-scale*6)
  stroke(R,{75,55,89},math.max(1,.4*scale),190)
 end end
 local net=W.vessels(g.state)
 for _,e in ipairs(net.edges) do vessel(R,g,e) end
 for _,gate in ipairs(net.gates) do local x,y=R.project(g,gate.x,gate.y)
  R.ellipse(x,y,gate.radius*scale,gate.radius*scale,{242,201,136},100)
  nvgBeginPath(R.vg);nvgCircle(R.vg,x,y,math.max(3,gate.radius*.5*scale));stroke(R,{255,223,157},1.4,230)
  if g.zoom>=.23 then R.text(x,y-7*scale,"膜口",9,{144,99,40}) end
 end
 -- Dotted strategic boundaries never look like solid membrane walls.
 for _,x in ipairs({1140,1234}) do for y=G.bounds.y+7,G.bounds.y+G.bounds.h-4,5 do
  if G.allowed(x,y) and not G.blocked(x,y) and net.sample(x,y).biome==0 then
   local px,py=R.project(g,x,y);R.ellipse(px,py,1.1,1.1,{248,224,181},160)
  end
 end end
 if g.zoom>=.1 then
  for _,p in ipairs(G.landmarks) do local x,y=R.project(g,p.x,p.y);R.text(x,y,p.name,10,{108,87,127}) end
  local x,y=R.project(g,G.bounds.x+93,G.bounds.y+80);R.text(x,y,"鼻中隔",11,{110,78,122})
  for i,z in ipairs(G.zones) do
   local x,y=R.project(g,z.x,G.bounds.y+G.bounds.h+5)
   R.text(x,y,z.name,12,ownership(c.event.zones[i]));R.text(x,y+16,T.status(c.event.zones[i]),10,ownership(c.event.zones[i]))
  end
 end
 local x,y=R.project(g,G.home.x,G.home.y)
 nvgBeginPath(R.vg);nvgCircle(R.vg,x,y,math.max(5,2.2*scale));stroke(R,A.colors[1],1.8,235)
 if g.zoom>=.2 then R.text(x,y-12*scale,"免疫调入口",10,A.colors[1]) end
end
function A.atlas(R,g,px,py,scale)
 if not g.state.campaign then return end
 if g.state.campaign.terrainVersion~=2 then require('war.NasalArtLegacy').atlas(R,g,px,py,scale);return end
 for i,z in ipairs(G.zones) do local p={}
  local polygon=z.polygon
  ---@cast polygon number[]
  for j=1,#polygon,2 do p[#p+1]=px+polygon[j]*scale;p[#p+1]=py+polygon[j+1]*scale end
  R.poly(p,ownership(g.state.campaign.event.zones[i]),220)
 end
end
return A
