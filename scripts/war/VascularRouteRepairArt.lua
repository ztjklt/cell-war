-- Draw repaired blood domains and clip obsolete tube pixels in source space.
---@class VascularRepairVisualData
---@field ownedLanes table<number,boolean>
---@field frontPipeRings table<number,table[]>
---@field replacements table<string,table>
---@field clippedSpecs table<string,table[]>
---@field patches table[]
---@field depthPatches table[]
local D=require('war.VascularRouteRepairVisualData') --[[@as VascularRepairVisualData]]
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
 local sx,sy=x*.5,(y-512)*.5
 local function contains(rings)
 for _,ring in ipairs(rings)do
  if inside(ring.outer,sx,sy)then
   local hole=false
   for _,points in ipairs(ring.holes)do if inside(points,sx,sy)then hole=true;break end end
   if not hole then return true end
  end
 end
 return false
 end
 for _,patch in ipairs(D.depthPatches)do
  if patch.lane==lane and contains(patch.rings)then return nil,true end
 end
 if not D.ownedLanes[lane]then return nil,false end
 if contains(D.frontPipeRings[lane])then return nil,true end
 return 'under-foreground',true
end
local function path(R,g,rings,cardiac)
 nvgBeginPath(R.vg)
 local function outline(points,winding)
  for i,p in ipairs(points)do
   local wx,wy=p[1]*2,p[2]*2+512
   if cardiac then wx,wy=require('war.HeartDisplayTransform').forwardWorld(g,wx,wy)end
   local x,y=R.project(g,wx,wy)
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
function V.replace(spec)return D.replacements[spec.id]or spec end
-- Keep all original pixels outside the obsolete physical tube footprints.
function V.drawSpec(R,g,s,spec,image,alpha,extraExclusions)
 local exclusions=D.clippedSpecs[spec.id]
 if not exclusions then return false end
 if extraExclusions then
  local combined={}
  for _,set in ipairs({exclusions,extraExclusions})do
   for _,ring in ipairs(set)do combined[#combined+1]=ring end
  end
  return require('war.HeartArt').drawOutsideSpec(R,g,s,spec,image,alpha,combined)
 end
 local b=spec.sourceBox;local vg=R.vg
 local ox,oy=R.project(g,0,512);local scale=64*g.zoom
 nvgSave(vg);nvgTranslate(vg,ox,oy);nvgScale(vg,scale,scale)
 nvgIntersectScissor(vg,b[1],b[2],b[3]-b[1],b[4]-b[2])
 if spec.coreBox then local c=spec.coreBox;nvgIntersectScissor(vg,c[1],c[2],c[3]-c[1],c[4]-c[2])end
 local function outline(points,winding)
  nvgMoveTo(vg,points[1][1],points[1][2])
  for i=2,#points do nvgLineTo(vg,points[i][1],points[i][2])end
  nvgClosePath(vg);nvgPathWinding(vg,winding)
 end
 nvgBeginPath(vg);nvgRect(vg,b[1],b[2],b[3]-b[1],b[4]-b[2]);nvgPathWinding(vg,NVG_SOLID)
 for _,set in ipairs({exclusions,extraExclusions or{}})do
  for _,ring in ipairs(set)do
   outline(ring.outer,NVG_HOLE)
   for _,hole in ipairs(ring.holes or{})do outline(hole,NVG_SOLID)end
  end
 end
 nvgFillPaint(vg,nvgImagePattern(vg,b[1],b[2],b[3]-b[1],b[4]-b[2],0,image,(alpha or 1)*(spec.opacity or 1)))
 nvgFill(vg);nvgRestore(vg);return true
end
function V.draw(R,g,s,x1,x2,y1,y2)
 if not require('war.FullBodyBattlefield').enabled(s)then return 0 end
 local count=0
 for _,patch in ipairs(D.patches)do
  local b=patch.sourceBox
  if not x1 or not(x1>b[3]*2 or x2<b[1]*2 or y1>b[4]*2+512 or y2<b[2]*2+512)then
   local c=colors[patch.system]
   nvgSave(R.vg)
   local cardiac=patch.lane==3 or patch.lane==15
   path(R,g,patch.outer,cardiac);nvgFillColor(R.vg,color(c.wall));nvgFill(R.vg)
   local ax,ay=R.project(g,b[1]*2,b[2]*2+512)
   local bx,by=R.project(g,b[3]*2,b[4]*2+512)
   path(R,g,patch.inner,cardiac)
   local paint=nvgLinearGradient(R.vg,ax,ay,bx,by,color(c.light),color(c.shade)) --[[@as NVGpaint]]
   nvgFillPaint(R.vg,paint)
   nvgFill(R.vg);nvgRestore(R.vg);count=count+1
  end
 end
 return count
end
return V
