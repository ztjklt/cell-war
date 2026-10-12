-- Isolated final-art geometry trial. Never required by production or save code.
local S={}
function S.attachForTest(s,W,P,C)
 local F=require('war.FinalVascularStudyData');local Base=require('war.PassageCollisionStudy')
 local M=require('war.OrganRouteCollisionStudy');local K=require('war.CellCollision')
 local net=W.vessels(s);local model=M.prepare(F.geometry);local context={zone='stomach',radius=0,tissueEdges={}}
 for _,id in ipairs(F.stomachWallEdges)do context.tissueEdges[F.edgeIndexById[id]]=true end
 local owned=context.tissueEdges
 local unGeometry=require('war.TissueGeometry').attachForTest(Base,M,model)
 local unRadius=M.attachForTest(model,context,net,W);local raw=P.clear
 local rasterLand=W.land;local rasterCorrections=0
 -- The final 3-world-unit tube is narrower than the legacy centre-sampled
 -- raster near diagonal cell corners. Exact swept disk clearance still decides
 -- passage; only a vessel-wall raster cell intersecting this explicit lane may
 -- defer to that continuous geometry. Bones/body/buildings remain authoritative.
 W.land=function(st,x,y)
  if rasterLand(st,x,y)then return true end
  local lane=context.activeLane
  if not lane or lane<=0 or W.terrain(st,x,y)~=17 or not require('war.Campaign').allowed(st,x+.5,y+.5)then return false end
  local edge=net.edges[lane]
  if edge and net.distance(lane,x+.5,y+.5,true)<=edge.width*.5+math.sqrt(.5)then rasterCorrections=rasterCorrections+1;return true end
  return false
 end
 local function activate(_,e)context.zone='stomach';context.radius=K.radius(e);context.tissueEdges=owned;context.activeLane=e.vesselLane end
 local b=F.stomachBounds
 local geometry={activate=activate,cacheIdentity=function()return F.sourceSha256..':stomach-final'end,
  pointAllowed=function(st,e,x,y,lane)activate(st,e);return M.allowed(model,context,net,x,y,lane)end,
  sweep=function(st,e,x,y,tx,ty,lane,target)activate(st,e);context.activeLane=lane;return raw(st,x,y,tx,ty,e.faction,lane,target)end,
  bounds=function()return{minX=2*b[1],minY=2*b[2]+512,maxX=2*b[3],maxY=2*b[4]+512}end,
  portals=function()return net.gates end,
 }
 local N=require('war.OrganSortieNavigationStudy')
 local unNav,stats=N.attachForTest(P,C,W,geometry,{frameSeconds=.003,cpuBudgetSeconds=12,nodeBudget=160000,searchNodeBudget=16000})
 return function()unNav();W.land=rasterLand;unRadius();unGeometry()end,{geometry=geometry,model=model,context=context,net=net,stats=stats,rasterCorrections=function()return rasterCorrections end,diagnostics=N.diagnostics,clearance=function(x,y)return M.clearance(model,'stomach',x,y)end}
end
return S
