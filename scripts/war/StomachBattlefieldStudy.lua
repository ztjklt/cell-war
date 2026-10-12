-- Opt-in stomach cutaway. This module never changes production geometry or state.
-- All drawing and obstacle queries use the same source-coordinate study data.
local D=require('war.StomachBattlefieldData')
local S={data=D}
local orderedVessels={};for _,e in ipairs(D.vessels) do orderedVessels[#orderedVessels+1]=e end
table.sort(orderedVessels,function(a,b)return a.layer<b.layer end)
local function contains(poly,x,y)
 local inside=false;local a=poly[#poly]
 for _,b in ipairs(poly) do
  if (a[2]>y)~=(b[2]>y) and x<(b[1]-a[1])*(y-a[2])/(b[2]-a[2])+a[1] then inside=not inside end
  a=b
 end
 return inside
end
function S.containsFoodSource(x,y)
 return contains(D.food.cavity,x,y) or contains(D.food.inlet,x,y) or contains(D.food.outlet,x,y)
end
function S.containsTissueSource(x,y) return contains(D.organ.outline,x,y) and not S.containsFoodSource(x,y) end
function S.alpha(zoom)
 local t=math.max(0,math.min(1,(zoom-.085)/.065));return t*t*(3-2*t)
end
local function point(R,g,p)
 return R.project(g,p[1]*D.transform.scale,p[2]*D.transform.scale+D.transform.offsetY)
end
local function path(R,g,points,closed)
 for i,p in ipairs(points) do local x,y=point(R,g,p);if i==1 then nvgMoveTo(R.vg,x,y) else nvgLineTo(R.vg,x,y) end end
 if closed then nvgClosePath(R.vg);nvgPathWinding(R.vg,NVG_SOLID) end
end
local function color(c,alpha) return nvgRGBA(c[1],c[2],c[3],math.floor(255*alpha+.5)) end
local function stroke(R,g,points,c,width,alpha,closed)
 nvgBeginPath(R.vg);path(R,g,points,closed);nvgStrokeColor(R.vg,color(c,alpha));nvgStrokeWidth(R.vg,width*D.transform.scale*32*g.zoom);nvgStroke(R.vg)
end
function S.draw(R,g,state,x1,x2,y1,y2)
 local alpha=S.alpha(g.zoom);if alpha<=0 or state.anatomyVersion~=4 then return end
 local crop=D.study.crop;local wx=crop[1]*2;local wy=crop[2]*2+512
 if x1 and (wx+crop[3]*2<x1 or wx>x2 or wy+crop[4]*2<y1 or wy>y2) then return end
 nvgSave(R.vg);nvgLineCap(R.vg,NVG_ROUND);nvgLineJoin(R.vg,NVG_ROUND)
 nvgBeginPath(R.vg);path(R,g,D.organ.outline,true);nvgFillColor(R.vg,color(D.organ.tissueColor,alpha));nvgFill(R.vg)
 stroke(R,g,D.organ.outline,D.organ.boundaryColor,D.organ.boundaryWidthSource,alpha,true)
 for _,fold in ipairs(D.folds) do stroke(R,g,fold.points,fold.color,fold.widthSource,alpha*(fold.alpha or 1),false) end
 -- The exact polygon union avoids both dark overlaps and even-odd backend holes.
 nvgBeginPath(R.vg);for _,p in ipairs(D.food.unionPaths) do path(R,g,p,true) end
 nvgFillColor(R.vg,color(D.food.fillColor,alpha));nvgFill(R.vg)
 -- Union-only boundary segments are generated from these exact polygons.
 nvgBeginPath(R.vg);for _,segment in ipairs(D.food.boundarySegments) do path(R,g,segment,false) end
 nvgStrokeColor(R.vg,color(D.food.boundaryColor,alpha));nvgStrokeWidth(R.vg,D.food.boundaryWidthSource*64*g.zoom);nvgStroke(R.vg)
 for _,vessel in ipairs(orderedVessels) do
  local c=vessel.kind=='portal' and {141,113,141} or vessel.kind=='exchange' and {153,139,112} or {166,104,100}
  for _,segment in ipairs(vessel.visibleSegments or {vessel.points}) do stroke(R,g,segment,c,vessel.lumenWidthSource,alpha,false) end
 end
 nvgRestore(R.vg)
end
return S
