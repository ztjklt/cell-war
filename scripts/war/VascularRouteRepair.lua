-- Stable blood IDs with repaired approaches and digit endpoints.
local D=require('war.VascularRouteRepairData')
local V={data=D}
local cached=setmetatable({},{__mode='k'})
local function nearest(points,x,y)
 local best,px,py,index,t=math.huge,0,0,1,0
 for i=2,#points do
  local a,b=points[i-1],points[i];local dx,dy=b[1]-a[1],b[2]-a[2]
  local length=dx*dx+dy*dy
  local q=length>0 and math.max(0,math.min(1,((x-a[1])*dx+(y-a[2])*dy)/length))or 0
  local ax,ay=a[1]+q*dx,a[2]+q*dy;local distance=(x-ax)^2+(y-ay)^2
  if distance<best then best,px,py,index,t=distance,ax,ay,i-1,q end
 end
 return math.sqrt(best),px,py,index,t
end
function V.net(base)
 if cached[base]then return cached[base]end
 local net={nodes={},edges={},gates={},version=base.version,scale=base.scale}
 local ids={}
 for i,node in ipairs(base.nodes)do
  local q={};for k,v in pairs(node)do q[k]=v end;q.edges={};net.nodes[i]=q;ids[q.id]=i
  local p=D.nodePoints[q.id];if p then q.x,q.y=p[1]*2,p[2]*2+512 end
 end
 for i,edge in ipairs(base.edges)do
  local q={} --[[@as VesselEdge]]
  for k,v in pairs(edge)do q[k]=v end;net.edges[i]=q
  local spec=D.edgeUpdates[i]
  if spec then
   q.a,q.b=assert(ids[spec.a]),assert(ids[spec.b]);q.width=spec.widthSource*2
   ---@type number[]
   local distances={0}
   q.points={};q.arc=distances;q.length=0;q.curved=false;q.cubics=nil
   for index,p in ipairs(spec.points)do
    q.points[index]={p[1]*2,p[2]*2+512}
    if index>1 then local a,b=q.points[index-1],q.points[index]
     q.length=q.length+math.sqrt((a[1]-b[1])^2+(a[2]-b[2])^2);q.arc[index]=q.length
    end
   end
  end
  net.nodes[q.a].edges[#net.nodes[q.a].edges+1]=i
  net.nodes[q.b].edges[#net.nodes[q.b].edges+1]=i
 end
 function net.distance(lane,x,y,near)
  if not D.edgeUpdates[lane]then return base.distance(lane,x,y,near)end
  return nearest(net.edges[lane].points,x,y)
 end
 for i,gate in ipairs(base.gates or{})do
  local g={};for k,v in pairs(gate)do g[k]=v end;net.gates[i]=g
  if D.edgeUpdates[g.edge]then
   local old=D.oldEdges[g.edge];local _,_,_,segment,t=nearest(old.points,(g.px or g.x)*.5,((g.py or g.y)-512)*.5)
   local fraction=(segment-1+t)/math.max(1,#old.points-1)
   local e=net.edges[g.edge];local index=math.min(#e.points-1,math.max(1,math.floor(fraction*(#e.points-1))+1))
   local a,b=e.points[index],e.points[index+1];local localT=fraction*(#e.points-1)-(index-1)
   g.px,g.py=a[1]+(b[1]-a[1])*localT,a[2]+(b[2]-a[2])*localT
   local offset=e.width*.5+.8;g.x,g.y=g.px+g.nx*offset,g.py+g.ny*offset
  end
 end
 cached[base]=net;return net
end
local function arc(points,index,t)
 local total,at=0,0
 for i=2,#points do
  local a,b=points[i-1],points[i];local length=math.sqrt((a[1]-b[1])^2+(a[2]-b[2])^2)
  if i-1<index then at=at+length elseif i-1==index then at=at+length*t end
  total=total+length
 end
 return total>0 and at/total or 0
end
local function along(edge,fraction)
 local left=edge.length*math.max(0,math.min(1,fraction))
 for i=2,#edge.points do local a,b=edge.points[i-1],edge.points[i]
  local length=math.sqrt((a[1]-b[1])^2+(a[2]-b[2])^2)
  if left<=length or i==#edge.points then local t=length>0 and left/length or 0
   return a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t
  end;left=left-length
 end
end
local function remap(net,lane,x,y)
 local old=D.oldEdges[lane]
 local _,_,_,segment,t=nearest(old.points,x*.5,(y-512)*.5)
 return along(net.edges[lane],arc(old.points,segment,t))
end
---@class VascularRepairCollisionFacade
---@field net fun(s:table):table
---@field pointAllowed fun(s:table,e:table,x:number,y:number,lane:number):boolean
function V.migrate(s)
 local O=require('war.OrganBattlefield') --[[@as VascularRepairCollisionFacade]]
 local net=O.net(s);local migrated=0
 for _,e in pairs(s.entities)do
  local lane=e.vesselLane or 0
  if e.category=='unit'and D.edgeUpdates[lane]then
   if not O.pointAllowed(s,e,e.x,e.y,lane)then
    local x,y=remap(net,lane,e.x,e.y)
    assert(O.pointAllowed(s,e,x,y,lane),'repaired blood lane has no legal save position')
    e.x,e.y=x,y;e.gastricTransit=nil;migrated=migrated+1
   end
   e.path={};e.longRoute=nil;e.pathGoal=nil;e.pathResolved=nil;e.routeEnd=nil
   e.pathPending=false;e.pathFailed=false;e.pathIndex=1;e.orderToken=(e.orderToken or 0)+1
  end
  for _,order in ipairs(e.orders or{})do
   if order.x and order.y and D.edgeUpdates[order.lane]then order.x,order.y=remap(net,order.lane,order.x,order.y)end
  end
 end
 for _,command in ipairs(s.commands or{})do
  if command.x and command.y and D.edgeUpdates[command.lane]then command.x,command.y=remap(net,command.lane,command.x,command.y)end
 end
 return migrated
end
return V
