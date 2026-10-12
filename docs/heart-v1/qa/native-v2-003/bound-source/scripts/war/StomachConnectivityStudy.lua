-- Opt-in connectivity experiment. No canonical edge, saved lane or production entry changes.
local U=require('war.Util')
local base=require('war.ReviewedVascularLayout')
local L=U.copy(base)
L.connectivityStudy=true
L.studyAdditions={gates={},edges={}}
local function world(p)return p[1]*2,p[2]*2+512 end
local function gate(id,edgeId,p,nx,ny,reason)
 local edge=L.edgeIndexById[edgeId];assert(edge,'missing reviewed gastric edge')
 local x,y=world(p)
 L.gates[#L.gates+1]={edge=edge,x=x,y=y,nx=nx,ny=ny,name=id}
 L.studyAdditions.gates[#L.studyAdditions.gates+1]={id=id,edgeId=edgeId,gateIndex=#L.gates,lumenAnchorSource=p,normal={nx,ny},reason=reason,experimental=true}
end
-- One controlled passage on each bank of the unchanged portal return e184.
-- Adjacent tissue compartments communicate through the lumen, never through a wall.
local portal={555,535-(568-555)*15/29};local length=math.sqrt(29*29+15*15)
gate('study.stomach.portal_bank.inner','e184',portal,15/length,-29/length,'inner tissue to reviewed portal return')
gate('study.stomach.portal_bank.lower','e184',portal,-15/length,29/length,'reviewed portal return to lower tissue')
-- The outer wall requires a local vascular service branch on a distinct depth layer.
-- It joins the existing stomach.v node; its projection under food is visually occluded.
local id='study.stomach.wall_service';local tipId=id..'.outer'
local points={{568,535},{576,531},{584,530},{598,531},{611,533}}
local x,y=world(points[#points]);local node=#L.nodes+1
L.nodes[node]={id=tipId,name='胃外壁局部服务支管端',x=x,y=y,heart=false};L.nodeIndexById[tipId]=node
local wp={};for _,p in ipairs(points) do local a,b=world(p);wp[#wp+1]={a,b} end
local edge=#L.edges+1
L.edges[edge]={a=L.nodeIndexById['stomach.v'],b=node,stableId=id,name='胃壁深层服务微血管（试验）',system='capillary',oxygen='exchange',width=3,points=wp,curved=false,layer=35,adapterOnly=true}
L.edgeIndexById[id]=edge
L.studyAdditions.edges[1]={id=id,points=points,widthSource=1.5,depth='deep',kind='exchange',layer=35,a='stomach.v',b=tipId,experimental=true}
gate('study.stomach.wall_service.inner',id,{576,531},0,-1,'inner tissue to deep gastric wall service branch')
gate('study.stomach.wall_service.outer',id,{611,533},0,-1,'deep gastric wall service branch to outer tissue')
-- Shared visible geometry for both the browser and actual NanoVG study rendering.
local Study=require('war.StomachBattlefieldStudy')
local function distance(p,a,b)
 local dx,dy=b[1]-a[1],b[2]-a[2];local length=dx*dx+dy*dy
 local t=length>0 and math.max(0,math.min(1,((p[1]-a[1])*dx+(p[2]-a[2])*dy)/length)) or 0
 return math.sqrt((p[1]-a[1]-t*dx)^2+(p[2]-a[2]-t*dy)^2)
end
local margin=.75+Study.data.food.boundaryWidthSource+.25
local function hidden(p)
 if Study.containsFoodSource(p[1],p[2])then return true end
 for _,poly in ipairs({Study.data.food.cavity,Study.data.food.inlet,Study.data.food.outlet})do
  for i,a in ipairs(poly)do if distance(p,a,poly[i%#poly+1])<margin then return true end end
 end
 return false
end
local samples={}
for i=2,#points do local a,b=points[i-1],points[i];local steps=math.ceil(math.sqrt((a[1]-b[1])^2+(a[2]-b[2])^2)/.15)
 for j=0,steps-1 do samples[#samples+1]={a[1]+(b[1]-a[1])*j/steps,a[2]+(b[2]-a[2])*j/steps}end
end
samples[#samples+1]=points[#points]
local visible,current,previous,wasHidden={},{},nil,nil
for _,p in ipairs(samples)do local h=hidden(p)
 if previous and h~=wasHidden then local lo,hi=previous,p
  for _=1,18 do local middle={(lo[1]+hi[1])/2,(lo[2]+hi[2])/2};if hidden(middle)==wasHidden then lo=middle else hi=middle end end
  local boundary={(lo[1]+hi[1])/2,(lo[2]+hi[2])/2}
  if h then current[#current+1]=boundary;visible[#visible+1]=current;current={}else current={boundary}end
 end
 if not h then current[#current+1]=p end;previous,wasHidden=p,h
end
if #current>0 then visible[#visible+1]=current end
L.studyAdditions.edges[1].visibleSegments=visible
L.studyAdditions.edges[1].occlusion='Under food projection: independent vessel lane, never a food-to-tissue opening.'
function L.drawStudy(R,g,state)
 local alpha=Study.alpha(g.zoom);if alpha<=0 then return end
 nvgSave(R.vg);nvgLineCap(R.vg,NVG_ROUND);nvgLineJoin(R.vg,NVG_ROUND)
 nvgStrokeColor(R.vg,nvgRGBA(153,139,112,math.floor(alpha*255)))
 nvgStrokeWidth(R.vg,1.5*64*g.zoom)
 for _,segment in ipairs(visible)do nvgBeginPath(R.vg)
  for i,p in ipairs(segment)do local x,y=R.project(g,world(p));if i==1 then nvgMoveTo(R.vg,x,y)else nvgLineTo(R.vg,x,y)end end
  nvgStroke(R.vg)
 end
 local net=require('war.Vessels').forDisplay(state)
 for _,spec in ipairs(L.studyAdditions.gates)do local gate=net.gates[spec.gateIndex];local x,y=R.project(g,gate.x,gate.y)
  nvgBeginPath(R.vg);nvgCircle(R.vg,x,y,.5*64*g.zoom)
  nvgFillColor(R.vg,nvgRGBA(220,232,210,math.floor(alpha*255)));nvgFill(R.vg)
  nvgStrokeColor(R.vg,nvgRGBA(61,112,87,math.floor(alpha*255)));nvgStrokeWidth(R.vg,.18*64*g.zoom);nvgStroke(R.vg)
 end
 nvgRestore(R.vg)
end
return L
