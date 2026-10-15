-- Paint missing registered vessel pieces; never supplies movement geometry.
---@class AbdominalVesselDisplayData
---@field ownedLanes table<number,boolean>
---@field frontPipeRings table<number,table[]>
---@field patches table[]
local D=require('war.AbdominalVesselDisplayData') --[[@as AbdominalVesselDisplayData]]
local V={data=D}
local colors={
 artery={wall={149,75,78},shade={212,116,115},light={226,138,134}},
 vein={wall={89,98,153},shade={130,139,187},light={155,159,201}},
 capillary={wall={154,109,116},shade={201,140,145},light={215,157,159}},
}
local function inside(points,x,y)
 local hit=false;local j=#points
 for i=1,#points do
  local a,b=points[i],points[j]
  if(a[2]>y)~=(b[2]>y)and x<(b[1]-a[1])*(y-a[2])/(b[2]-a[2])+a[1]then hit=not hit end
  j=i
 end
 return hit
end
function V.unitDepth(lane,x,y)
 if not D.ownedLanes[lane]then return nil,false end
 local sx,sy=x*.5,(y-512)*.5
 for _,ring in ipairs(D.frontPipeRings[lane])do
  if inside(ring.outer,sx,sy)then
   local hole=false
   for _,points in ipairs(ring.holes)do if inside(points,sx,sy)then hole=true;break end end
   if not hole then return nil,true end
  end
 end
 return 'under-foreground',true
end
local function path(R,g,rings)
 nvgBeginPath(R.vg)
 local function outline(points,winding)
  for i,p in ipairs(points)do
   local x,y=R.project(g,p[1]*2,p[2]*2+512)
   if i==1 then nvgMoveTo(R.vg,x,y)else nvgLineTo(R.vg,x,y)end
  end
  nvgClosePath(R.vg);nvgPathWinding(R.vg,winding)
 end
 for _,ring in ipairs(rings)do
  outline(ring.outer,NVG_SOLID)
  for _,hole in ipairs(ring.holes)do outline(hole,NVG_HOLE)end
 end
end
---@return NVGcolor
local function color(c)return nvgRGBA(c[1],c[2],c[3],255) --[[@as NVGcolor]]
end
function V.draw(R,g,s,x1,x2,y1,y2)
 if not require('war.FullBodyBattlefield').enabled(s)then return 0 end
 local count=0
 for _,patch in ipairs(D.patches)do
  local b=patch.sourceBox
  if not x1 or not(x1>b[3]*2 or x2<b[1]*2 or y1>b[4]*2+512 or y2<b[2]*2+512)then
   local c=colors[patch.system]
   nvgSave(R.vg)
   path(R,g,patch.outer);nvgFillColor(R.vg,color(c.wall));nvgFill(R.vg)
   local ax,ay=R.project(g,b[1]*2,b[2]*2+512)
   local bx,by=R.project(g,b[3]*2,b[4]*2+512)
   path(R,g,patch.inner)
   local paint=nvgLinearGradient(R.vg,ax,ay,bx,by,color(c.light),color(c.shade)) --[[@as NVGpaint]]
   nvgFillPaint(R.vg,paint)
   nvgFill(R.vg);nvgRestore(R.vg);count=count+1
  end
 end
 return count
end
return V
