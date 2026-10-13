-- Opted-in intestinal blood geometry. Stable lane IDs preserve save identity.
---@class BowelVesselEdge: VesselEdge
---@field stableId string?
local D=require('war.BowelBattlefieldData')
local B={data=D}
local cached=setmetatable({},{__mode='k'})
local organCopies=setmetatable({},{__mode='k'})
function B.enabled(s)
 return s and s.anatomyVersion==4 and(s.organBattlefieldVersion==1 or s.fullbodyBattlefieldVersion==1)or false
end
function B.isLocalLane(lane)return D.rawBloodDomains[lane]~=nil end
function B.replaceOrgan(original)
 local saved=organCopies[original];if saved then return saved end
 local d={};for k,v in pairs(original)do d[k]=v end
 d.bloodLanes={scout={},siege={}}
 for _,kind in ipairs({'scout','siege'})do
  for lane,blood in pairs(original.bloodLanes[kind])do d.bloodLanes[kind][lane]=D.bloodLanes[kind][lane]or blood end
 end
 organCopies[original]=d;return d
end
function B.net(base)
 local saved=cached[base];if saved then return saved end
 local net={nodes={},edges={},gates=base.gates,version=base.version,scale=base.scale}
 local ids={}
 for i,n in ipairs(base.nodes)do
  local q={};for k,v in pairs(n)do q[k]=v end;q.edges={};net.nodes[i]=q;ids[q.id]=i
  local p=D.nodePoints[q.id];if p then q.x,q.y=p[1]*2,p[2]*2+512 end
 end
 for i,e in ipairs(base.edges)do
  local q={} --[[@as BowelVesselEdge]];for k,v in pairs(e)do q[k]=v end;net.edges[i]=q
  local spec=D.edgeUpdates[i]
  if spec then
   q.a,q.b=assert(ids[spec.a]),assert(ids[spec.b]);q.width=spec.widthSource*2
   ---@type number[]
   local arc={0}
   q.points={};q.arc=arc
   q.length=0;q.curved=false;q.cubics=nil
   for index,p in ipairs(spec.points)do
    q.points[index]={p[1]*2,p[2]*2+512}
    if index>1 then
     local a,b=q.points[index-1],q.points[index]
     q.length=q.length+math.sqrt((a[1]-b[1])^2+(a[2]-b[2])^2);q.arc[index]=q.length
    end
   end
  end
  net.nodes[q.a].edges[#net.nodes[q.a].edges+1]=i
  net.nodes[q.b].edges[#net.nodes[q.b].edges+1]=i
 end
 function net.distance(lane,x,y,near)
  if not B.isLocalLane(lane)then return base.distance(lane,x,y,near)end
  local e=net.edges[lane] --[[@as BowelVesselEdge]];local best,px,py,index,t=math.huge,0,0,1,0
  for i=2,#e.points do
   local a,b=e.points[i-1],e.points[i];local dx,dy=b[1]-a[1],b[2]-a[2]
   local len=dx*dx+dy*dy
   local at=len>0 and math.max(0,math.min(1,((x-a[1])*dx+(y-a[2])*dy)/len))or 0
   local ax,ay=a[1]+at*dx,a[2]+at*dy;local dd=(x-ax)^2+(y-ay)^2
   if dd<best then best,px,py,index,t=dd,ax,ay,i-1,at end
  end
  return math.sqrt(best),px,py,index,t
 end
 cached[base]=net;return net
end
-- Old saved cells retain their own blood compartment; obsolete queued routes
-- are cleared even if their current point is still legal in the new vessel.
function B.migrateEntity(s,e)
 if not B.enabled(s)or e.category~='unit'or not B.isLocalLane(e.vesselLane or 0)then return false end
 local O=require('war.OrganBattlefield');local lane=e.vesselLane
 if not O.pointAllowed(s,e,e.x,e.y,lane)then
  local net=O.net(s);local _,px,py=net.distance(lane,e.x,e.y)
  local Collision=require('war.CellCollision')
  local function free(x,y)
   if not O.pointAllowed(s,e,x,y,lane)then return false end
   for _,other in pairs(s.entities)do
    if other.id~=e.id and other.category=='unit'and other.vesselLane==lane and other.hp>0 then
     local radius=Collision.radius(e)+Collision.radius(other)+.08
     if(x-other.x)^2+(y-other.y)^2<radius*radius then return false end
    end
   end
   return true
  end
  if not free(px,py)then
   local edge=net.edges[lane];local best,found=math.huge,false;local targetX,targetY=px,py
   for _,p in ipairs(edge.points)do
    local dd=(p[1]-targetX)^2+(p[2]-targetY)^2
    if dd<best and free(p[1],p[2])then best=dd;px,py=p[1],p[2];found=true end
   end
   assert(found,'旧肠道单位无法迁移到原血管通路')
  end
  e.x,e.y=px,py
 end
 e.gastricTransit=nil;e.orders={};e.path={};e.longRoute=nil;e.pathGoal=nil;e.pathResolved=nil;e.routeEnd=nil
 e.pathPending=false;e.pathFailed=false;e.pathIndex=1;e.orderToken=(e.orderToken or 0)+1
 return true
end
return B
