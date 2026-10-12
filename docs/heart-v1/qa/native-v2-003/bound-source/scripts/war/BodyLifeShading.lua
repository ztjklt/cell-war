-- Fixed-pixel biological shading. All paths are pigment-derived interior masks;
-- outlines, attachment points, blue branches and bone stay on the static layer.
local Regions=require('war.BodyLifeRegions')
local LightingRegions=require('war.BodyLifeLightingRegions')
local Motion=require('war.BodyLifeMotion')
local S={}
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
local function smooth(x) x=clamp(x,0,1);return x*x*(3-2*x) end
local order={'heart'}
local limbPhase={arm_r=.23,arm_l=.49,forearm_r=.35,forearm_l=.61,thigh_r=.67,thigh_l=.83,calf_r=.78,calf_l=.94}
local cache={}
local function addPath(out,path,hole)
 local points=path.points or path
 if #points<3 then return end
 out.paths[#out.paths+1]={points=points,hole=path.hole or hole or false}
 for _,p in ipairs(points) do
  out.x1=math.min(out.x1,p[1]);out.x2=math.max(out.x2,p[1])
  out.y1=math.min(out.y1,p[2]);out.y2=math.max(out.y2,p[2])
 end
 for _,p in ipairs(path.holes or {}) do addPath(out,p,true) end
end
-- Only numerical contour bounds are cached; no image resources or simulation data.
for _,id in ipairs(order) do
 local r={paths={},x1=math.huge,x2=-math.huge,y1=math.huge,y2=-math.huge}
 for _,path in ipairs(LightingRegions[id] or Regions[id] or {}) do addPath(r,path,false) end
 if #r.paths>0 then r.w=r.x2-r.x1;r.h=r.y2-r.y1;cache[id]=r end
end
local function mask(vg,r)
 nvgBeginPath(vg)
 for _,path in ipairs(r.paths) do
  local p=path.points
  nvgMoveTo(vg,p[1][1],p[1][2])
  for i=2,#p do nvgLineTo(vg,p[i][1],p[i][2]) end
  nvgClosePath(vg)
  nvgPathWinding(vg,path.hole and NVG_HOLE or NVG_SOLID)
 end
end
local function color(light,alpha)
 -- Black/white overlays bound fractional luminance changes without adding a
 -- coloured aura. Float alpha is essential at the lowest detail intensities.
 local c=light and 1 or 0
 return nvgRGBAf(c,c,c,clamp(alpha,0,1))
end
local function radial(vg,r,x,y,inner,outer,light,alpha)
 if alpha<=1e-7 then return false end
 if not r.pathReady then mask(vg,r);r.pathReady=true end
 nvgFillPaint(vg,nvgRadialGradient(vg,x,y,inner,outer,color(light,alpha),color(light,0)))
 nvgFill(vg);return true
end
local function linear(vg,r,x1,y1,x2,y2,light,alpha)
 if alpha<=1e-7 then return false end
 if not r.pathReady then mask(vg,r);r.pathReady=true end
 nvgFillPaint(vg,nvgLinearGradient(vg,x1,y1,x2,y2,color(light,0),color(light,alpha)))
 nvgFill(vg);return true
end
local function visible(r,b)
 return not b or (r.x1*2<=b.x2 and r.x2*2>=b.x1 and r.y1*2+512<=b.y2 and r.y2*2+512>=b.y1)
end
-- bounds are world coordinates: {x1=...,x2=...,y1=...,y2=...}, or {x1,x2,y1,y2}.
-- bodyScale overrides source-pixel -> logical-screen-pixel scaling, never DPR.
function S.draw(R,g,state,bounds,options)
 options=options or {}
 if state.anatomyVersion~=4 or g.bodyLifeEnabled==false then return 0 end
 local intensity=clamp(options.intensity or 1,0,1)
 local scale=options.bodyScale or 64*g.zoom
 if intensity==0 or scale<=0 then return 0 end
 local b=bounds and {x1=bounds.x1 or bounds[1],x2=bounds.x2 or bounds[2],y1=bounds.y1 or bounds[3],y2=bounds.y2 or bounds[4]}
 local vg=R.vg;local ox,oy=R.project(g,0,512);local time=g.realTime or 0;local drawn=0
 nvgSave(vg)
 if b then
  local x1,y1=R.project(g,b.x1,b.y1);local x2,y2=R.project(g,b.x2,b.y2)
  nvgIntersectScissor(vg,math.min(x1,x2),math.min(y1,y2),math.abs(x2-x1),math.abs(y2-y1))
 end
 nvgTranslate(vg,ox,oy);nvgScale(vg,scale,scale)
 for _,id in ipairs(order) do
  local r=cache[id]
  local primary=id=='heart' or id=='lung_r' or id=='lung_l'
  if r and visible(r,b) and (primary or not options.mini) then
   -- Digestive waves are a whole-body cue, not a microscopy-only detail.
   -- Secondary perfusion enters more softly to avoid synchronous body flashing.
   local digestive=Motion.paths[id]~=nil
   local detail=primary and 1 or digestive and smooth((r.h*scale-10)/26)
    or smooth((r.h*scale-16)/44)
   local tissueFade=smooth((g.zoom-.08)/.07)
   local amount=intensity*detail*(options.mini and .6 or 1)*(1-tissueFade)
   if amount>0 then
    -- Consecutive paints reuse this organ path, including its hole windings.
    -- Reset every draw: another organ/context may have replaced NanoVG state.
    r.pathReady=false
    local q=Motion.sample(time,id);local changed=false
    if id=='heart' then
     local contraction=math.max(0,-q.beat);local rebound=math.max(0,q.beat)/.32
     changed=radial(vg,r,r.x1+r.w*.66,r.y1+r.h*.7,r.w*.2,r.w*.85,false,contraction*Motion.visual.heartShadow*amount) or changed
     changed=radial(vg,r,r.x1+r.w*.3,r.y1+r.h*.38,0,r.w*.65,true,rebound*Motion.visual.heartRebound*amount) or changed
    elseif id=='lung_r' or id=='lung_l' then
     -- Two asymmetric soft gradients suggest tissue opening from the hilum
     -- towards the base, with the strongest response in the lower lung.
     local inhale=q.breath
     changed=linear(vg,r,r.x1+r.w*.5,r.y1+r.h*.18,r.x1+r.w*.65,r.y2,true,inhale*Motion.visual.lungLight*amount) or changed
     changed=radial(vg,r,r.x1+r.w*(id=='lung_r' and .75 or .25),r.y1+r.h*.78,r.w*.12,r.h*.5,false,(1-inhale)*Motion.visual.lungShadow*amount) or changed
    elseif Motion.paths[id] then
     -- Each active node shades a broad patch of existing tissue. There are no
     -- discs or new outlines, and the same masks retain the source highlights.
     local radius=id=='stomach' and 34 or 24
     local gain=id=='large_intestine' and Motion.visual.largeGutWave
      or id=='stomach' and Motion.visual.stomachWave or Motion.visual.smallGutWave
     for _,active in ipairs(q.segments) do
      local p=Motion.paths[id][active.index]
      changed=radial(vg,r,p[1],p[2],0,radius,false,active.weight*gain*amount) or changed
     end
    elseif limbPhase[id] then
     -- A soft local tissue response travels along the limb rather than changing
     -- the entire muscle's brightness at once. End fades prevent wrap jumps.
     local travel=(time/7+limbPhase[id])%1
     local envelope=math.sin(math.pi*travel)^2
     changed=radial(vg,r,r.x1+r.w*.5,r.y1+r.h*travel,0,
      math.max(r.w*.65,r.h*.28),false,envelope*Motion.visual.limbPerfusion*amount) or changed
    else
     local alpha=math.min(.03,math.abs(q.perfusion))*amount
     changed=radial(vg,r,r.x1+r.w*.55,r.y1+r.h*.56,0,math.max(r.w,r.h)*.65,q.perfusion>0,alpha) or changed
    end
    if changed then drawn=drawn+1 end
   end
  end
 end
 nvgRestore(vg)
 return drawn
end
return S
