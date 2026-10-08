-- Layered puppet built from production-pack parts plus a matched anatomy texture.
-- This is a procedural rig, not a Cubism .moc3 model. Never changes simulation state.
local D=require("war.BrainRigData")
local R={contexts=setmetatable({},{__mode="k"})}
local function clamp(v,a,b) return math.max(a,math.min(b,v)) end
local function portraitScale(l) return math.min(l.w/D.width,l.h/D.height)*.93 end
function R.init(vg)
 if R.contexts[vg] then return end
 local ctx={};local count=0
 for key,asset in pairs(D.assets) do
  ctx[key]=nvgCreateImage(vg,asset.path,NVG_IMAGE_GENERATE_MIPMAPS)
  if ctx[key]>0 then count=count+1 end
 end
 R.contexts[vg]=ctx
 print("[BrainRig] layered portrait textures | "..count.."/"..(function() local n=0;for _ in pairs(D.assets) do n=n+1 end;return n end)())
end
function R.release(vg)
 for _,handle in pairs(R.contexts[vg] or {}) do if handle>0 then nvgDeleteImage(vg,handle) end end
 R.contexts[vg]=nil
end
function R.update(g,H,dt)
 if not g.brainAnim then g.brainAnim={time=0,lookX=0,lookY=0} end
 local a=g.brainAnim;a.time=a.time+math.max(0,dt)
 local x,y=0,0
 ---@type number?,number?
 local mouseX,mouseY
 local widget=H.refs.brainDialogue and H.refs.brainDialogue.character or H.refs.brainCharacter
 if widget and input and input.GetMousePosition then
  local p=input:GetMousePosition();local l=widget:GetAbsoluteLayout()
  if l.w>0 and l.h>0 then
   local scale=require("urhox-libs/UI").GetScale()
   mouseX,mouseY=p.x/scale,p.y/scale
   x=clamp((mouseX-l.x-l.w*.5)/math.max(l.w*.7,1),-1,1)
   y=clamp((mouseY-l.y-l.h*.5)/math.max(l.h*.7,1),-1,1)
  end
 end
 local blend=1-math.exp(-10*math.max(0,dt))
 a.lookX=a.lookX+(x-a.lookX)*blend;a.lookY=a.lookY+(y-a.lookY)*blend
 if mouseX and mouseY then
  a.mouseX=a.mouseX and a.mouseX+(mouseX-a.mouseX)*blend or mouseX
  a.mouseY=a.mouseY and a.mouseY+(mouseY-a.mouseY)*blend or mouseY
 else a.mouseX=nil;a.mouseY=nil end
end
function R.pose(time,lookX,lookY,speaking,mood,pointer)
 local t=time or 0;local cycle=(t+2.3)%4.7
 local blink=cycle<.2 and 1-math.sin(cycle/.2*math.pi) or 1
 local x,y=clamp(lookX or 0,-1,1),clamp(lookY or 0,-1,1)
 local breath=math.sin(t*1.8)*.012
 return {time=t,bob=math.sin(t*1.25)*9,rotation=math.sin(t*.8)*.009+x*.008,
  sx=1+breath,sy=1-breath*.7,lookX=x,lookY=y,blink=blink,
  mouseX=pointer and pointer.mouseX,mouseY=pointer and pointer.mouseY,
  mouth=speaking and ({"talkA","talkB","talkO","neutral"})[math.floor(t*8)%4+1] or mood=="happy" and "happy" or "neutral",
  mood=mood or "idle",speaking=speaking or false}
end
-- Transform the smoothed cursor back into the moving face's coordinates.
-- Each pupil aims from its own lens centre, with a soft elliptical travel limit.
function R.gaze(l,p)
 local scale=portraitScale(l)
 if not p.mouseX or not p.mouseY or scale<=0 then return 212,234,285.5,223.5 end
 local x=(p.mouseX-l.x-l.w*.5)/scale
 local y=(p.mouseY-l.y-l.h*.5)/scale-p.bob
 local c,s=math.cos(p.rotation),math.sin(p.rotation)
 local mx=(c*x+s*y)/p.sx+D.width*.5-p.lookX*1.2
 local my=(-s*x+c*y)/p.sy+D.height*.5-p.lookY*.8
 local function focus(cx,cy,travelX,travelY)
  local dx,dy=mx-cx,my-cy
  local length=math.sqrt(dx*dx+dy*dy+80*80)
  return cx+dx/length*travelX,cy+dy/length*travelY
 end
 local lx,ly=focus(205.5,232.5,13,9)
 local rx,ry=focus(291,221,8,8)
 return lx,ly,rx,ry
end
local function texture(vg,key,x,y,w,h,alpha,ellipse)
 local ctx=R.contexts[vg];local handle=ctx and ctx[key]
 if not handle or handle<=0 then return end
 local a=D.assets[key]
 ---@type number[]
 local c=a.crop
 local sx,sy=w/c[3],h/c[4]
 nvgBeginPath(vg)
 if ellipse then nvgEllipse(vg,x+w*.5,y+h*.5,w*.5,h*.5) else nvgRect(vg,x,y,w,h) end
 nvgFillPaint(vg,nvgImagePatternTinted(vg,x-c[1]*sx,y-c[2]*sy,a.w*sx,a.h*sy,0,handle,nvgRGBA(255,255,255,math.floor((alpha or 1)*255))))
 nvgFill(vg)
end
local function polygon(vg,points)
 nvgBeginPath(vg)
 for i,point in ipairs(points) do
  if i==1 then nvgMoveTo(vg,point[1],point[2]) else nvgLineTo(vg,point[1],point[2]) end
 end
 nvgClosePath(vg)
end
local function anatomy(vg,points)
 polygon(vg,points)
 nvgFillPaint(vg,nvgImagePatternTinted(vg,0,0,D.width,D.height,0,R.contexts[vg].anatomy,nvgRGBA(255,255,255,255)))
 nvgFill(vg)
end
-- Warp each triangle of a pack tablet into the reference perspective.
local function triangle(vg,key,source,target,alpha)
 local ctx=R.contexts[vg];local id=ctx and ctx[key];if not id or id<=0 then return end
 local x,y=source[1][1],source[1][2]
 local u,v=source[2][1]-x,source[2][2]-y
 local w,z=source[3][1]-x,source[3][2]-y;local det=u*z-v*w
 if math.abs(det)<.001 then return end
 local tx,ty=target[1][1],target[1][2]
 local du,dv=target[2][1]-tx,target[2][2]-ty
 local dw,dz=target[3][1]-tx,target[3][2]-ty
 local aa,cc=(du*z-dw*v)/det,(dw*u-du*w)/det
 local bb,dd=(dv*z-dz*v)/det,(dz*u-dv*w)/det
 nvgSave(vg);nvgTransform(vg,aa,bb,cc,dd,tx-aa*x-cc*y,ty-bb*x-dd*y)
 polygon(vg,source)
 local a=D.assets[key]
 nvgFillPaint(vg,nvgImagePatternTinted(vg,0,0,a.w,a.h,0,id,nvgRGBA(255,255,255,math.floor(alpha*255))))
 nvgFill(vg);nvgRestore(vg)
end
local function quad(vg,key,source,target,alpha)
 triangle(vg,key,{source[1],source[2],source[3]},{target[1],target[2],target[3]},alpha)
 triangle(vg,key,{source[1],source[3],source[4]},{target[1],target[3],target[4]},alpha)
end
local function eye(vg,cx,cy,rx,ry,p,px,py,pw,ph)
 nvgBeginPath(vg);nvgEllipse(vg,cx,cy,rx,ry)
 nvgFillPaint(vg,nvgLinearGradient(vg,cx,cy-ry,cx,cy+ry,nvgRGBA(255,248,240,255),nvgRGBA(247,224,211,255)));nvgFill(vg)
 if p.blink>.25 then
  nvgSave(vg);nvgTranslate(vg,px,py)
  nvgScale(vg,1,math.max(.05,p.blink))
  texture(vg,"pupil",-pw*.5,-ph*.5,pw,ph,1,true);nvgRestore(vg)
 else
  -- Full closed eye sampled only inside its lens, never as a rectangular patch.
  texture(vg,"closed",cx-rx,cy-ry,rx*2,ry*2,1,true)
 end
end
function R.draw(vg,l,p,_tablet)
 local ctx=R.contexts[vg]
 if not ctx or not ctx.anatomy or ctx.anatomy<=0 then return false end
 local scale=portraitScale(l)
 if scale<=0 then return true end
 nvgSave(vg);nvgIntersectScissor(vg,l.x,l.y,l.w,l.h)
 nvgTranslate(vg,l.x+l.w*.5,l.y+l.h*.5);nvgScale(vg,scale,scale)
 nvgTranslate(vg,0,p.bob);nvgRotate(vg,p.rotation);nvgScale(vg,p.sx,p.sy)
 nvgTranslate(vg,-D.width*.5,-D.height*.5)
 for _,part in ipairs(D.arms) do
  local pivot=part.pivot
  local angle=(math.sin(p.time*1.45+part.phase)-math.sin(part.phase))*.023
  nvgSave(vg);nvgTranslate(vg,pivot[1],pivot[2]);nvgRotate(vg,angle);nvgTranslate(vg,-pivot[1],-pivot[2])
  anatomy(vg,part.polygon);nvgRestore(vg)
 end
 anatomy(vg,D.core)
 nvgSave(vg);nvgTranslate(vg,p.lookX*1.2,p.lookY*.8)
 local lx,ly,rx,ry=R.gaze(l,p)
 eye(vg,205.5,232.5,35.5,39,p,lx,ly,22,42)
 eye(vg,291,221,22.5,34,p,rx,ry,16,37)
 texture(vg,"glasses",165,179,154,98)
 if p.speaking or p.mood=="happy" then texture(vg,p.mouth,232,273,23,p.mouth=="neutral" and 10 or 23) end
 nvgRestore(vg)
 nvgSave(vg);nvgTranslate(vg,285,310)
 nvgRotate(vg,math.sin(p.time*1.4)*.012);nvgTranslate(vg,-285,-310+math.sin(p.time*1.7)*1.1)
 local corners={{264,276},{384,244},{345,330},{207,359}}
 quad(vg,"tabletBase",{{21,22},{127,0},{109,74},{2,104}},corners,1)
 quad(vg,"tabletOutline",{{28,24},{123,0},{105,79},{12,101}},corners,.78)
 quad(vg,"tablet",{{4,24},{109,0},{102,76},{0,108}},{{265,277},{381,248},{343,328},{211,355}},.94+math.sin(p.time*2.1)*.04)
 -- Soft edge restores the complete casing where the original atlas was cut.
 nvgBeginPath(vg);nvgMoveTo(vg,267,275)
 nvgLineTo(vg,380,245);nvgQuadTo(vg,384,244,382,248)
 nvgLineTo(vg,347,326);nvgQuadTo(vg,345,330,341,331)
 nvgLineTo(vg,212,358);nvgQuadTo(vg,207,359,210,354)
 nvgLineTo(vg,261,280);nvgQuadTo(vg,264,276,267,275);nvgClosePath(vg)
 nvgStrokeWidth(vg,2);nvgStrokeColor(vg,nvgRGBA(210,248,255,220));nvgStroke(vg)
 nvgRestore(vg)
 if p.mood=="alert" then texture(vg,"alert",336,44,20,31,.86+math.sin(p.time*4)*.08)
 elseif p.mood=="thinking" then texture(vg,"question",335,44,22,30,.9) end
 nvgRestore(vg)
 return true
end
function R.mood(g,H)
 local d=H.refs.brainDialogue;local ev=g.state.campaign and g.state.campaign.event
 if ev and ev.status=="completed" then return "happy" end
 if ev and ev.status=="active" then
  local data=require("war.CampaignData").forState(g.state)
  for _,index in ipairs(data.failureZones or {#ev.zones}) do
   local z=ev.zones[index]
   if z and (z.hostile>0 or z.control<60) then return "alert" end
  end
 end
 if d and d.topic=="defense" then return "thinking" end
 return "idle"
end
return R
