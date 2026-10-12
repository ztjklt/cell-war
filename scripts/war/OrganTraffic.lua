-- Simulation-time right-of-way for the registered organ atlas. Orders remain owned by Commands.
-- Yielding uses incremental G routing and ordinary C.go / CellCollision movement.
local G=require('war.OrganBattlefield')
local K=require('war.CellCollision')
local T={}
local states=setmetatable({},{__mode='k'})
local guards=setmetatable({},{__mode='k'})
local MAX_PAIRS=16
local PLAN_BUDGET=.0015
local planning=setmetatable({},{__mode='k'})
local function checkpoint()
 local co=coroutine.running();if planning[co]then coroutine.yield()end
end
local pathArcs=setmetatable({},{__mode='k'})
local function prepareArc(path)
 local n=#path;local last=path[n]
 local cached=pathArcs[path]
 if cached and cached.count==n and(not last or cached.endX==last.x and cached.endY==last.y)then return cached end
 local arc={count=n,suffix={}}
 if last then arc.endX,arc.endY=last.x,last.y;arc.suffix[n]=0 end
 for i=n-1,1,-1 do
  checkpoint()
  local a,b=path[i],path[i+1];local dx,dy=b.x-a.x,b.y-a.y
  arc.suffix[i]=arc.suffix[i+1]+math.sqrt(dx*dx+dy*dy)
 end
 pathArcs[path]=arc;return arc
end
local function route(s,e,x,y,lane)
 local co=coroutine.running();local p=planning[co]
 assert(p,'traffic routing must run inside the bounded planner')
 local job=G.beginRoute(s,e,x,y,lane);p.routeJob=job
 while true do
  local done,path=G.resumeRoute(job,.0005)
  if done then p.routeJob=nil;if type(path)=='table'then prepareArc(path)end;return path end
  coroutine.yield()
 end
end
local function cancelPlan(p)
 if p.arcPlan then planning[p.arcPlan]=nil;if coroutine.close then coroutine.close(p.arcPlan)end;p.arcPlan=nil end
 if p.routeJob then G.cancelRoute(p.routeJob);p.routeJob=nil end
 if p.plan then planning[p.plan]=nil;if coroutine.close then coroutine.close(p.plan)end;p.plan=nil end
end
local function schedule(p,fn,kind)
 cancelPlan(p);p.planKind=kind;p.phase='planning';p.plan=coroutine.create(fn);planning[p.plan]=p
end
local function alive(e)return e and (e.hp or 1)>0 and e.category=='unit'end
local function state(s)
 local q=states[s];if not q then q={pairs={},byId={},arrivals={},retry={},stats={conflicts=0,yields=0,waits=0,resumed=0,cancelled=0,deadReleased=0,noBay=0,expired=0,routeRequests=0,maxPairs=0}};states[s]=q end;return q
end
function T.reset(s)
 for ss,q in pairs(states)do if not s or ss==s then for _,p in ipairs(q.pairs)do cancelPlan(p)end;states[ss]=nil end end
 if not s then guards=setmetatable({},{__mode='k'})end
end
function T.stats(s)local q=states[s];local out={activePairs=0};if not q then return out end;for k,v in pairs(q.stats)do out[k]=v end;out.activePairs=#q.pairs;return out end
function T.inspect(s)
 local out={};local q=states[s];if not q then return out end
 for _,p in ipairs(q.pairs)do out[#out+1]={yielder=p.yielder,priority=p.priority,phase=p.phase,target=p.target,priorityBay=p.priorityBay,started=p.started}end;return out
end
local function order(e)return e.orders and e.orders[1]end
local function dist(x,y,a,b)return math.sqrt((x-a)^2+(y-b)^2)end
local function segmentDistance(px,py,x,y,tx,ty)
 local dx,dy=tx-x,ty-y;local l=dx*dx+dy*dy;local t=l>0 and math.max(0,math.min(1,((px-x)*dx+(py-y)*dy)/l))or 0
 return dist(px,py,x+dx*t,y+dy*t)
end
local function laneAhead(e)
 if (e.vesselLane or 0)>0 then return e.vesselLane end
 local x,y=e.x,e.y;local total=0
 for i=e.pathIndex or 1,math.min(#(e.path or {}),(e.pathIndex or 1)+12)do
  local p=e.path[i];total=total+dist(x,y,p.x,p.y);if total>20 then break end
  if (p.lane or 0)>0 then return p.lane end;x,y=p.x,p.y
 end
 return nil
end
local function heading(e)
 for i=e.pathIndex or 1,math.min(#(e.path or {}),(e.pathIndex or 1)+8)do
  local p=e.path[i];local d=dist(e.x,e.y,p.x,p.y);if d>.08 then return (p.x-e.x)/d,(p.y-e.y)/d end
 end
 local o=order(e);if o and o.x and o.y then local d=dist(e.x,e.y,o.x,o.y);if d>.08 then return(o.x-e.x)/d,(o.y-e.y)/d end end
 return nil,nil
end
local function owns(s,lane)return G.trafficData(s).bloodLanes.siege[lane]~=nil end
local function conflict(s,a,b)
 local lane=laneAhead(a);if not lane or lane~=laneAhead(b)or not owns(s,lane)then return false end
 local blood=G.trafficData(s).bloodLanes.siege[lane]
 -- Width is source-space; K.radius is world-space. Passing needs both diameters.
 if blood.lumenWidthSource*2>=2*(K.radius(a)+K.radius(b))+.1 then return false end
 if dist(a.x,a.y,b.x,b.y)>32 then return false end
 local ax,ay=heading(a);local bx,by=heading(b);if not ax or not bx then return false end
 if ax*bx+ay*by>-.15 then return false end
 local vx,vy=b.x-a.x,b.y-a.y
 return ax*vx+ay*vy>-.1 and bx*vx+by*vy<.1
end
local function sameSegmentPlane(s,e,x,y,lane,other,transition)
 local probe=setmetatable({x=x,y=y,vesselLane=lane,gastricTransit=transition or false},{__index=e})
 local heart=require('war.HeartBattlefield').samePlane(s,probe,other)
 if heart~=nil then return heart end
 if transition or other.gastricTransit then return true end
 return (lane or 0)==(other.vesselLane or 0)
end
local function clearUnits(s,e,path,anticipated)
 local x,y,lane=e.x,e.y,e.vesselLane or 0
 for _,p in ipairs(path)do
  checkpoint()
  local nextLane=p.lane or 0
  local transition=lane~=nextLane or p.gateId or p.gate or p.transition
  for _,actual in pairs(s.entities or {})do local other=anticipated and actual.id==anticipated.id and anticipated or actual
  if alive(other)and other.id~=e.id and sameSegmentPlane(s,e,x,y,lane,other,transition)then
   if segmentDistance(other.x,other.y,x,y,p.x,p.y)<K.radius(e)+K.radius(other)+.015 then return false end
  end end
  x,y,lane=p.x,p.y,nextLane
 end
 return true
end
local function clearsReserved(s,x,y,e,other,path,goal,holdingLane)
 holdingLane=holdingLane or 0
 if not other then return true end
 local clearance=K.radius(e)+K.radius(other)+.12
 if goal and sameSegmentPlane(s,other,goal.x,goal.y,goal.lane or 0,{id=e.id,vesselLane=holdingLane},false)and dist(x,y,goal.x,goal.y)<clearance then return false end
 local px,py,lane=other.x,other.y,other.vesselLane or 0
 for _,point in ipairs(type(path)=='table'and path or {})do
  checkpoint()
  local nextLane=point.lane or 0
  local transition=lane~=nextLane or point.gateId or point.gate or point.transition
  if sameSegmentPlane(s,other,px,py,lane,{id=e.id,vesselLane=holdingLane},transition)and segmentDistance(x,y,px,py,point.x,point.y)<clearance then return false end
  px,py,lane=point.x,point.y,nextLane
 end
 return true
end
local function at(e,target)
 -- This immutable planning probe is not installed into s.entities.
 return setmetatable({x=target.x,y=target.y,vesselLane=target.lane or 0,gastricTransit=false},{__index=e})
end
local function clearsFutureGoal(s,e,path,other,goal)
 if not other or not goal then return true end
 local parked=at(other,goal);local x,y,lane=e.x,e.y,e.vesselLane or 0
 for _,point in ipairs(path)do
  checkpoint()
  local nextLane=point.lane or 0;local transition=lane~=nextLane or point.gateId or point.gate or point.transition
  if sameSegmentPlane(s,e,x,y,lane,parked,transition)and
   segmentDistance(goal.x,goal.y,x,y,point.x,point.y)<K.radius(e)+K.radius(other)+.12 then return false end
  x,y,lane=point.x,point.y,nextLane
 end
 return true
end
local function pathLength(e,path)
 local arc=prepareArc(path)
 return #path>0 and dist(e.x,e.y,path[1].x,path[1].y)+(arc.suffix[1]or 0)or 0
end
local function bay(s,q,e,reservedUnit,reservedPath,reservedGoal,returnGoal,localOnly,acceptCycle,maxCycleCost,cycleLowerBound,bodyFloorOnly)
 local best,bestPath=nil,nil
 local function floorOwned(x,y)
  if bodyFloorOnly~=true then return true end
  local H=require('war.HeartBattlefield')
  if H.insideOuter(x,y)then return false end
  local owner,reason=G.organAt(s,e,x,y)
  return reason==nil and type(owner)=='string'and owner~='heart'and owner~='lung_r'and owner~='lung_l'
 end
 local function candidateCost(target)
  return target.cycleWorldLength or (target.pathWorldLength or 0)+(target.returnWorldLength or 0)
 end
 local function canImprove(target,currentBest)
  local bound=cycleLowerBound and cycleLowerBound(target)or target.score+
   (returnGoal and dist(target.x,target.y,returnGoal.x,returnGoal.y)or 0)
  return(not currentBest or bound<candidateCost(currentBest)-.01)and
   (not maxCycleCost or bound<maxCycleCost-.01)
 end
 local function recoverable(target)
  if not returnGoal then return true end
  local probe=at(e,target)
  q.stats.routeRequests=q.stats.routeRequests+1
  local path=route(s,probe,returnGoal.x,returnGoal.y,returnGoal.lane)
  if type(path)~='table'or not clearsFutureGoal(s,probe,path,reservedUnit,reservedGoal)or
   not clearUnits(s,probe,path,reservedUnit and reservedGoal and at(reservedUnit,reservedGoal))then return false end
  target.returnWorldLength=pathLength(probe,path);return true
 end
 local profile=G.radius(e)<=.21875 and 'scout'or'siege'
 local currentLane=laneAhead(e)
 -- A cell already waiting on legal tissue can hold its actual position. The
 -- priority's real path/gate clearance is checked before accepting zero motion.
 if (e.vesselLane or 0)==0 and not e.gastricTransit and floorOwned(e.x,e.y)and G.pointAllowed(s,e,e.x,e.y,0)and
  G.sweep(s,e,e.x,e.y,e.x,e.y,0,0)and clearsReserved(s,e.x,e.y,e,reservedUnit,reservedPath,reservedGoal)then
  local clear=true
  for _,actual in pairs(s.entities or{})do
   checkpoint();local u=reservedUnit and actual.id==reservedUnit.id and reservedUnit or actual
   if alive(u)and u.id~=e.id and sameSegmentPlane(s,e,e.x,e.y,0,u,false)and
    dist(e.x,e.y,u.x,u.y)<K.radius(e)+K.radius(u)+K.gap-1e-8 then clear=false;break end
  end
  local target={x=e.x,y=e.y,score=0,lane=0,pathWorldLength=0,currentLegalHold=true}
  if clear and canImprove(target,best)and recoverable(target)and(not acceptCycle or acceptCycle(target,{}))then return target,{} end
 end
 local net=G.net(s);local near={[currentLane or 0]=true}
 local edge=currentLane and net.edges[currentLane]
 if edge then for _,ni in ipairs({edge.a,edge.b})do for _,lane in ipairs(net.nodes[ni].edges or{})do near[lane]=true end end end
 local function bloodBays()
  local H=require('war.HeartBattlefield')
  if not edge or H.insideOuter(e.x,e.y)or H.isLocalLane(currentLane)then return nil,nil end
  local owner=G.organAt(s,e,e.x,e.y)
  if owner=='heart'or owner=='lung_r'or owner=='lung_l'then return nil,nil end
  local choices,seen={},{}
  for _,ni in ipairs({edge.a,edge.b})do
   local node=net.nodes[ni]
   for _,lane in ipairs(node.edges or{})do if lane~=currentLane and lane<=202 and not H.isLocalLane(lane)then
    local branch=net.edges[lane];local points=branch.points
    local fromFirst=branch.a==ni;local first=fromFirst and 1 or #points;local step=fromFirst and 1 or -1
    local x,y,along=points[first][1],points[first][2],0;local wanted={6,10,14};local wi=1
    for i=first+step,fromFirst and #points or 1,step do
     checkpoint();local point=points[i];local segment=dist(x,y,point[1],point[2])
     while wanted[wi]and wanted[wi]<=along+segment do
      checkpoint();local requested=wanted[wi];local ratio=segment>0 and(requested-along)/segment or 0
      local sx,sy=x+(point[1]-x)*ratio,y+(point[2]-y)*ratio;local key=lane..'/'..requested
      if not seen[key]and not H.insideOuter(sx,sy)and G.pointAllowed(s,e,sx,sy,lane)then
       seen[key]=true;local available=true
       for _,actual in pairs(s.entities or{})do
        checkpoint();local u=reservedUnit and actual.id==reservedUnit.id and reservedUnit or actual
        if alive(u)and u.id~=e.id and sameSegmentPlane(s,e,sx,sy,lane,u,false)and dist(sx,sy,u.x,u.y)<K.radius(e)+K.radius(u)+.12 then available=false;break end
       end
       if available and clearsReserved(s,sx,sy,e,reservedUnit,reservedPath,reservedGoal,lane)then
        choices[#choices+1]={x=sx,y=sy,lane=lane,score=dist(e.x,e.y,sx,sy),bloodBranch=true,node=ni,sampleIndex=wi,arcWorld=requested}
       end
      end
      wi=wi+1
     end
     along=along+segment;x,y=point[1],point[2]
     if not wanted[wi]then break end
    end
   end end
  end
  table.sort(choices,function(a,b)if a.score==b.score then if a.lane==b.lane then return a.sampleIndex<b.sampleIndex end;return a.lane<b.lane end;return a.score<b.score end)
  local branchBest,branchPath=best,bestPath
  for _,target in ipairs(choices)do
   if maxCycleCost and target.score>=maxCycleCost then return branchBest,branchPath end
   if branchBest and target.score>=candidateCost(branchBest) then return branchBest,branchPath end
   if canImprove(target,branchBest)then
    q.stats.routeRequests=q.stats.routeRequests+1
    local path=route(s,e,target.x,target.y,target.lane)
    if type(path)=='table'and clearUnits(s,e,path,reservedUnit)then
     local cost=pathLength(e,path);target.pathWorldLength=cost
     if recoverable(target)and(not acceptCycle or acceptCycle(target,path))then return target,path end
    end
   end
  end
  return branchBest,branchPath
 end
 local bloodTarget,bloodPath=nil,nil
 if localOnly~='floor'and localOnly~='floor-local'then bloodTarget,bloodPath=bloodBays()end
 if bloodTarget then best,bestPath=bloodTarget,bloodPath end
 if localOnly=='blood'then return best,bestPath end
 local gates=G.trafficData(s).gateContracts[profile]
 local function candidates(preferred)
  local result={}
  for _,g in ipairs(gates)do if (near[g.laneIndex]==true)==preferred then
   local localCandidates={};local ox,oy=g.tissueAnchorSource[1]*2,g.tissueAnchorSource[2]*2+512
   for _,radius in ipairs({3,5,8})do for i=0,15 do
    checkpoint()
    local angle=i*math.pi/8;local x,y=ox+math.cos(angle)*radius,oy+math.sin(angle)*radius
    if floorOwned(x,y)and G.pointAllowed(s,e,x,y,0)and G.sweep(s,e,ox,oy,x,y,0,0)then
     local available=true
     for _,actual in pairs(s.entities or{})do local u=reservedUnit and actual.id==reservedUnit.id and reservedUnit or actual
     if alive(u)and u.id~=e.id and sameSegmentPlane(s,e,x,y,0,u,false)and dist(x,y,u.x,u.y)<K.radius(e)+K.radius(u)+.5 then available=false;break end end
     if available and clearsReserved(s,x,y,e,reservedUnit,reservedPath,reservedGoal)then localCandidates[#localCandidates+1]={x=x,y=y,score=dist(e.x,e.y,x,y),gate=g.id,laneIndex=g.laneIndex}end
    end
   end end
   table.sort(localCandidates,function(a,b)if a.score==b.score then if a.x==b.x then return a.y<b.y end;return a.x<b.x end;return a.score<b.score end)
   for i=1,math.min(2,#localCandidates)do result[#result+1]=localCandidates[i]end
  end end
  table.sort(result,function(a,b)if a.score==b.score then return a.gate<b.gate end;return a.score<b.score end)
  return result
 end
 for _,preferred in ipairs((localOnly==true or localOnly=='floor-local')and{true}or{true,false})do
  for _,target in ipairs(candidates(preferred))do
   -- Euclidean distance is a lower bound for every remaining real route.
   if maxCycleCost and target.score>=maxCycleCost then return best,bestPath end
   if best and target.score>=candidateCost(best) then return best,bestPath end
   if canImprove(target,best)then
    q.stats.routeRequests=q.stats.routeRequests+1
    local path=route(s,e,target.x,target.y,0)
    if type(path)=='table'and clearUnits(s,e,path,reservedUnit)then
     local cost=pathLength(e,path);target.pathWorldLength=cost;target.preferredSameLane=preferred
     if recoverable(target)and(not acceptCycle or acceptCycle(target,path))then return target,path end
    end
   end
  end
 end
 return best,bestPath
end
local function install(e,path,x,y)
 e.path=path;e.pathIndex=1;e.pathGoal={x=x,y=y};e.pathResolved=nil;e.pathPending=false;e.pathFailed=false;e.longRoute=nil;e.cellDetour=nil;e.contactStall=0;e.stuck=0
end
local function restore(s,q,p)
 local e=s.entities[p.yielder]
 if alive(e)and order(e)==p.yieldOrder then
  -- Resume the original command from the actual parked position, never teleport.
  local path=route(s,e,p.goalX,p.goalY,p.goalLane)
  install(e,type(path)=='table'and path or {},p.goalX,p.goalY)
  if type(path)~='table'then e.pathFailed=false end
  q.stats.resumed=q.stats.resumed+1
 end
end
local function remove(q,p)
 if p.plan~=coroutine.running()then cancelPlan(p)end
 q.byId[p.yielder]=nil;q.byId[p.priority]=nil
 for i=#q.pairs,1,-1 do if q.pairs[i]==p then table.remove(q.pairs,i);break end end
end
local function drive(s,e,target,dt)
 guards[e]=true
 local ok,err=pcall(require('war.Commands').go,s,e,target.x,target.y,dt,.025,target.lane or 0)
 guards[e]=nil
 if not ok then error(err)end
 return dist(e.x,e.y,target.x,target.y)<.055 and (target.lane==nil or e.vesselLane==target.lane)
end
local function priorityComplete(s,q,p)
 local y,a=s.entities[p.yielder],s.entities[p.priority]
 local resumePath=route(s,y,p.goalX,p.goalY,p.goalLane)
 if type(resumePath)=='table'and clearUnits(s,y,resumePath)then install(y,resumePath,p.goalX,p.goalY);q.stats.resumed=q.stats.resumed+1;remove(q,p);return end
 -- A completed blood target can still obstruct the other disk. Temporarily
 -- park that completed unit too, then restore its exact commanded destination.
 local target,path=bay(s,q,a,y,resumePath,{x=p.goalX,y=p.goalY,lane=p.goalLane},p.priorityGoal,nil,nil,nil,nil,p.target and p.target.bodyFloorOnly)
 if target then
  p.phase='clearPriority';p.priorityOrder=nil;p.priorityBay=target;target.lane=target.lane or 0
  install(a,path,target.x,target.y);q.stats.secondaryYields=(q.stats.secondaryYields or 0)+1
 else p.phase='passing';p.retryAt=s.time+1 end
end
local function abandon(s,q,p,cancelledId)
 cancelPlan(p)
 local e=s.entities[p.yielder]
 if alive(e)and order(e)==p.yieldOrder then install(e,{},p.goalX,p.goalY);e.pathGoal=nil end
 local priority=s.entities[p.priority]
 local returnNeeded=not p.returnOnly and p.priorityBay and p.priorityGoal and alive(priority)and
  cancelledId~=priority.id and order(priority)==nil and p.priorityOrder==nil and
  (dist(priority.x,priority.y,p.priorityGoal.x,p.priorityGoal.y)>.055 or
   p.priorityGoal.lane~=nil and priority.vesselLane~=p.priorityGoal.lane)
 remove(q,p)
 if returnNeeded then
  local goal={x=p.priorityGoal.x,y=p.priorityGoal.y,lane=p.priorityGoal.lane}
  local recovery={yielder=priority.id,priority=priority.id,yieldOrder=nil,priorityOrder=nil,
   goalX=goal.x,goalY=goal.y,goalLane=goal.lane,priorityGoal=goal,returnOnly=true,
   started=s.time,progressAt=s.time,phase='planning'}
  q.pairs[#q.pairs+1]=recovery;q.byId[priority.id]=recovery
  schedule(recovery,function()
   local path=route(s,priority,goal.x,goal.y,goal.lane)
   install(priority,type(path)=='table'and path or{},goal.x,goal.y)
   if type(path)~='table'then priority.pathGoal=nil end
   recovery.phase='restorePriority'
  end,'restorePriority')
 end
end
function T.cancel(s,e)
 if not states[s]then return end
 local q=state(s);local p=q.byId[e.id]
 if p then q.stats.cancelled=q.stats.cancelled+1;abandon(s,q,p,e.id)end
end
local function reached(e,target)
 return dist(e.x,e.y,target.x,target.y)<=.75 and(target.lane==nil or e.vesselLane==target.lane)
end
local function cleanup(s,q)
 for id in pairs(q.arrivals)do local e=s.entities[id];if not alive(e)or not order(e)then q.arrivals[id]=nil end end
 for id,t in pairs(q.retry)do if not alive(s.entities[id])or t<s.time then q.retry[id]=nil end end
 for i=#q.pairs,1,-1 do local p=q.pairs[i];local a,b=s.entities[p.yielder],s.entities[p.priority]
  if alive(a)and alive(b)then
   local unit,target=nil,nil
   if p.phase=='retreat'then unit,target=a,p.target
   elseif p.phase=='passing'then unit,target=b,p.priorityGoal
   elseif p.phase=='clearPriority'then unit,target=b,p.priorityBay
   elseif p.phase=='resumeYielder'then unit,target=a,{x=p.goalX,y=p.goalY,lane=p.goalLane}
   elseif p.phase=='restorePriority'then unit,target=b,p.priorityGoal end
   if unit and target then
    local key=unit.id..'/'..target.x..'/'..target.y..'/'..tostring(target.lane)
    local path=unit.path or{};local n=#path;local last=path[n];local arc=pathArcs[path]
    if not arc or arc.count~=n or last and(arc.endX~=last.x or arc.endY~=last.y)then
     if not p.arcPlan then p.arcPlan=coroutine.create(function()prepareArc(path)end);planning[p.arcPlan]=p end
    else
     local index=unit.pathIndex or 1;local nextPoint=path[index]
     local distance=nextPoint and dist(unit.x,unit.y,nextPoint.x,nextPoint.y)+(arc.suffix[index]or 0)+dist(arc.endX,arc.endY,target.x,target.y)or dist(unit.x,unit.y,target.x,target.y)
     if p.progressKey~=key or not p.progressBest then p.progressKey=key;p.progressBest=distance;p.progressAt=s.time
     elseif distance<p.progressBest-.25 then p.progressBest=distance;p.progressAt=s.time end
    end
   end
  end
  local yieldNatural=alive(a)and p.phase=='resumeYielder'and order(a)==nil and reached(a,{x=p.goalX,y=p.goalY,lane=p.goalLane})
  local priorityNatural=alive(b)and p.phase=='passing'and order(b)==nil and reached(b,p.priorityGoal)
  if not alive(a)or not alive(b)then q.stats.deadReleased=q.stats.deadReleased+1;abandon(s,q,p)
  elseif order(a)~=p.yieldOrder and not yieldNatural or order(b)~=p.priorityOrder and not priorityNatural then
   q.stats.cancelled=q.stats.cancelled+1
   abandon(s,q,p,order(b)~=p.priorityOrder and not priorityNatural and b.id or a.id)
  elseif p.returnOnly and p.phase=='returnBlocked'then
   -- The finite token waits; T.update may schedule one bounded retry.
  elseif (p.returnOnly and p.phase=='planning'and s.time-(p.returnAttemptStarted or p.started)>120 or
   not(p.returnOnly and p.phase=='planning')and s.time-(p.progressAt or p.started)>120)and not yieldNatural and not priorityNatural then
   if p.returnOnly then
    cancelPlan(p);p.phase='returnBlocked';p.retryAt=s.time+1
    q.stats.returnStalls=(q.stats.returnStalls or 0)+1
   else q.stats.expired=q.stats.expired+1;abandon(s,q,p)end
  elseif p.phase=='passing'and order(b)==nil and reached(b,p.priorityGoal)and s.time>=(p.retryAt or 0)then
   p.priorityOrder=nil;schedule(p,function()priorityComplete(s,q,p)end,'priorityComplete')
  elseif p.phase=='resumeYielder'and order(a)==nil and reached(a,{x=p.goalX,y=p.goalY,lane=p.goalLane})then
   p.yieldOrder=nil
   schedule(p,function()
    local path=route(s,b,p.priorityGoal.x,p.priorityGoal.y,p.priorityGoal.lane)
    if type(path)=='table'then install(b,path,p.priorityGoal.x,p.priorityGoal.y);p.phase='restorePriority'
    else p.phase='resumeYielder' end
   end,'restorePriority')
  elseif order(a)~=p.yieldOrder or order(b)~=p.priorityOrder then
   q.stats.cancelled=q.stats.cancelled+1;abandon(s,q,p)
  end
 end
end
function T.update(s,dt)
 if not G.enabled(s)or not dt or dt<=0 then return end
 local q=states[s];if not q then return end;cleanup(s,q)
 for _,p in ipairs(q.pairs)do
  local e=s.entities[p.priority]
  if p.returnOnly and p.phase=='returnBlocked'and alive(e)and not order(e)and s.time>=(p.retryAt or 0)then
   p.returnAttemptStarted=s.time
   schedule(p,function()
    local target=p.priorityGoal
    local path=route(s,e,target.x,target.y,target.lane)
    if type(path)=='table'and clearUnits(s,e,path)then
     install(e,path,target.x,target.y);p.phase='restorePriority'
     -- Only a newly verified free corridor restarts this bounded attempt.
     p.progressAt=s.time;p.progressKey=nil;p.progressBest=nil
    else p.phase='returnBlocked';p.retryAt=s.time+1 end
   end,'restorePriority')
  end
 end
 local began=os.clock();local deadline=began+PLAN_BUDGET
 -- One shared traffic planning slice per simulation frame, never per actor.
 for _,p in ipairs(q.pairs)do
  while p.arcPlan and os.clock()<deadline do
   local co=p.arcPlan;local ok,err=coroutine.resume(co)
   if not ok then planning[co]=nil;p.arcPlan=nil;error(err)end
   if coroutine.status(co)=='dead'then planning[co]=nil;p.arcPlan=nil end
  end
  while p.plan and os.clock()<deadline do
   local co=p.plan;local ok,err=coroutine.resume(co)
   if not ok then cancelPlan(p);error(err)end
   if coroutine.status(co)=='dead'then planning[co]=nil;p.plan=nil end
  end
  if os.clock()>=deadline then break end
 end
 q.stats.maxPlanningSlice=math.max(q.stats.maxPlanningSlice or 0,os.clock()-began)
 for i=#q.pairs,1,-1 do local p=q.pairs[i];local a=s.entities[p.priority]
  if alive(a)and p.lastDriven~=s.time then
   if p.phase=='clearPriority'then
    p.lastDriven=s.time
    if drive(s,a,p.priorityBay,dt)then schedule(p,function()restore(s,q,p);p.phase='resumeYielder'end,'resume')end
   elseif p.phase=='restorePriority'then
    p.lastDriven=s.time
    if drive(s,a,p.priorityGoal,dt)then remove(q,p)end
   end
  end
 end
end
local function planRetreat(s,q,p)
 local originalY,originalA=s.entities[p.yielder],s.entities[p.priority]
 local originalYG={x=p.goalX,y=p.goalY,lane=p.goalLane};local originalAG=p.priorityGoal
 schedule(p,function()
  local function option(y,a,yg,ag,mode,maxCost,bodyFloorOnly)
   local priorityPath=route(s,a,ag.x,ag.y,ag.lane)
   if type(priorityPath)~='table'then return nil end
   local priorityCost=pathLength(a,priorityPath)
   local function lowerBound(target)
    return target.score+priorityCost+dist(target.x,target.y,yg.x,yg.y)
   end
   local function cycle(target,path)
    local parkedY=at(y,target)
    q.stats.routeRequests=q.stats.routeRequests+1
    local resumePath=route(s,parkedY,yg.x,yg.y,yg.lane)
    if type(resumePath)~='table'then return false end
    local cost=target.pathWorldLength+priorityCost+pathLength(parkedY,resumePath)
    if maxCost and cost>=maxCost-.01 then return false end
    if not clearsFutureGoal(s,parkedY,resumePath,a,ag)or not clearUnits(s,parkedY,resumePath,at(a,ag))then
     local completedA=at(a,ag)
     local second=bay(s,q,completedA,parkedY,resumePath,yg,ag,mode,nil,nil,nil,bodyFloorOnly)
     if not second then return false end
     cost=cost+second.pathWorldLength+(second.returnWorldLength or 0)
    end
    if maxCost and cost>=maxCost-.01 then return false end
    target.cycleWorldLength=cost;return true
   end
   -- Every enumerated candidate, including actual current-floor holds, is
   -- checked for a complete two-goal cycle before accepting this orientation.
   local target,path=bay(s,q,y,a,priorityPath,ag,nil,mode,cycle,maxCost,lowerBound,bodyFloorOnly)
   if not target then return nil end
   target.bodyFloorOnly=bodyFloorOnly==true or nil
   return{y=y,a=a,yg=yg,ag=ag,target=target,path=path,cost=target.cycleWorldLength}
  end
  local chosen=nil
  local function consider(y,a,yg,ag,mode,bodyFloorOnly)
   local nextChoice=option(y,a,yg,ag,mode,chosen and chosen.cost,bodyFloorOnly)
   if nextChoice and(not chosen or nextChoice.cost<chosen.cost-.01)then chosen=nextChoice end
  end
  -- Commit the first fully validated nearby cycle instead of exhausting
  -- globally cheaper candidates while both cells remain stationary. Existing
  -- connected-gate floor bays also serve non-cardiac body blood exchanges.
  local yl,al=originalY.vesselLane or 0,originalA.vesselLane or 0
  local H=require('war.HeartBattlefield')
  local function bodyBlood(e,lane)
   if lane<=0 or lane>202 or H.isLocalLane(lane)or H.insideOuter(e.x,e.y)then return false end
   local owner=G.organAt(s,e,e.x,e.y)
   return owner~='heart'and owner~='lung_r'and owner~='lung_l'
  end
  local addedBodyBlood=bodyBlood(originalY,yl)and bodyBlood(originalA,al)
  if yl==0 and al>0 or al==0 and yl>0 or addedBodyBlood then
   consider(originalY,originalA,originalYG,originalAG,'floor-local',addedBodyBlood)
   if not chosen then consider(originalA,originalY,originalAG,originalYG,'floor-local',addedBodyBlood)end
  end
  if not chosen then consider(originalY,originalA,originalYG,originalAG,'blood')end
  if not chosen then consider(originalA,originalY,originalAG,originalYG,'blood')end
  -- At most one global floor fallback. Equivalent local costs retain arrival/ID fairness.
  if not chosen then chosen=option(originalY,originalA,originalYG,originalAG,'floor')end
  if not chosen then
   q.stats.noBay=q.stats.noBay+1;q.retry[originalY.id]=s.time+1;q.retry[originalA.id]=s.time+1;remove(q,p);return
  end
  p.yielder,p.priority=chosen.y.id,chosen.a.id
  p.yieldOrder,p.priorityOrder=order(chosen.y),order(chosen.a)
  p.goalX,p.goalY,p.goalLane=chosen.yg.x,chosen.yg.y,chosen.yg.lane;p.priorityGoal=chosen.ag
  p.target=chosen.target;p.phase='retreat';install(chosen.y,chosen.path,chosen.target.x,chosen.target.y)
 end,'initial')
end
local function begin(s,q,a,b,x,y)
 if #q.pairs>=MAX_PAIRS then return false end
 local aa,bb=q.arrivals[a.id]or s.time,q.arrivals[b.id]or s.time
 local priority,yielder=a,b
 if bb<aa or bb==aa and b.id<a.id then priority,yielder=b,a end
 local o=order(yielder);local gx,gy=o and o.x,o and o.y
 if yielder==a then gx,gy=x,y end
 if not gx or not gy then return false end
 local po=order(priority);local priorityGoal={x=po and po.x or priority.x,y=po and po.y or priority.y,lane=po and(po.lane or po.vesselLane)or priority.vesselLane}
 local p={priorityGoal=priorityGoal,yielder=yielder.id,priority=priority.id,yieldOrder=order(yielder),priorityOrder=order(priority),goalX=gx,goalY=gy,goalLane=o and(o.lane or o.vesselLane),started=s.time,phase='planning'}
 q.pairs[#q.pairs+1]=p;q.byId[yielder.id]=p;q.byId[priority.id]=p;q.stats.conflicts=q.stats.conflicts+1;q.stats.yields=q.stats.yields+1;q.stats.maxPairs=math.max(q.stats.maxPairs,#q.pairs)
 planRetreat(s,q,p)
 return true
end
-- Only serializable intent is saved. Lua coroutines, route caches and order
-- table identities are reconstructed against the restored state's real units.
function T.snapshot(s)
 if not G.enabled(s)then return nil end
 local q=states[s];local out={version=1,pairs={}}
 if not q then return out end
 local function target(t)
  return t and{x=t.x,y=t.y,lane=t.lane,gate=t.gate,score=t.score,bodyFloorOnly=t.bodyFloorOnly==true or nil}or nil
 end
 for _,p in ipairs(q.pairs)do
  local y,a=s.entities[p.yielder],s.entities[p.priority]
  if not p.returnOnly and not alive(y)and alive(a)and not order(a)and
   p.priorityOrder==nil and p.priorityBay and p.priorityGoal and
   (dist(a.x,a.y,p.priorityGoal.x,p.priorityGoal.y)>.055 or p.priorityGoal.lane~=nil and a.vesselLane~=p.priorityGoal.lane)then
   -- Pure serialization: a death can be saved before the next cleanup. Keep
   -- only the living completed unit's old-goal obligation, never a new order.
   out.pairs[#out.pairs+1]={yielder=a.id,priority=a.id,hasYieldOrder=false,hasPriorityOrder=false,
    goalX=p.priorityGoal.x,goalY=p.priorityGoal.y,goalLane=p.priorityGoal.lane,
    priorityGoal=target(p.priorityGoal),returnOnly=true,phase='planning',planKind='restorePriority',
    started=s.time,progressAt=s.time}
  else
  out.pairs[#out.pairs+1]={yielder=p.yielder,priority=p.priority,
   hasYieldOrder=p.yieldOrder~=nil,hasPriorityOrder=p.priorityOrder~=nil,
   goalX=p.goalX,goalY=p.goalY,goalLane=p.goalLane,
   priorityGoal=target(p.priorityGoal),target=target(p.target),priorityBay=target(p.priorityBay),
   phase=p.phase,planKind=p.planKind,started=p.started,progressAt=p.progressAt,
   progressKey=p.progressKey,progressBest=p.progressBest,returnOnly=p.returnOnly,retryAt=p.retryAt,returnAttemptStarted=p.returnAttemptStarted}
  end
 end
 return out
end
function T.restore(s,data)
 T.reset(s)
 if not G.enabled(s)or type(data)~='table'or data.version~=1 then return false end
 local q=state(s)
 local function replan(p,e,target,phase)
  schedule(p,function()
   local path=route(s,e,target.x,target.y,target.lane or 0)
   if type(path)=='table'then install(e,path,target.x,target.y);p.phase=phase
   else if p.returnOnly then p.phase='returnBlocked';p.retryAt=s.time+1 else abandon(s,q,p)end end
  end,phase)
 end
 for i,src in ipairs(data.pairs or {})do
  if i>MAX_PAIRS then break end
  local a,b=s.entities[src.yielder],s.entities[src.priority]
  -- Older version1 snapshots can contain the same pre-cleanup death window.
  -- Read their intent without mutating the snapshot or any real unit/order.
  if not src.returnOnly and not alive(a)and alive(b)and not order(b)and
   src.hasPriorityOrder==false and src.priorityBay and src.priorityGoal and
   (dist(b.x,b.y,src.priorityGoal.x,src.priorityGoal.y)>.055 or src.priorityGoal.lane~=nil and b.vesselLane~=src.priorityGoal.lane)then
   src={yielder=b.id,priority=b.id,hasYieldOrder=false,hasPriorityOrder=false,
    goalX=src.priorityGoal.x,goalY=src.priorityGoal.y,goalLane=src.priorityGoal.lane,
    priorityGoal={x=src.priorityGoal.x,y=src.priorityGoal.y,lane=src.priorityGoal.lane},
    returnOnly=true,phase='planning',planKind='restorePriority',started=s.time,progressAt=s.time}
   a=b
  end
  if alive(a)and alive(b)and not q.byId[a.id]and not q.byId[b.id]and
   (not src.returnOnly or not order(b))then
   local p={};for k,v in pairs(src)do p[k]=v end
   p.yieldOrder=src.hasYieldOrder and order(a)or nil
   p.priorityOrder=src.hasPriorityOrder and order(b)or nil
   if (not src.hasYieldOrder or p.yieldOrder)and(not src.hasPriorityOrder or p.priorityOrder)then
    q.pairs[#q.pairs+1]=p;q.byId[a.id]=p;q.byId[b.id]=p
    local phase=p.phase=='planning'and p.planKind or p.phase
    if p.returnOnly and phase=='returnBlocked'then p.phase=phase;p.retryAt=s.time+1
    elseif phase=='initial'then planRetreat(s,q,p)
    elseif phase=='retreat'and p.target then replan(p,a,p.target,'retreat')
    elseif phase=='priorityComplete'then schedule(p,function()priorityComplete(s,q,p)end,'priorityComplete')
    elseif phase=='clearPriority'and p.priorityBay then replan(p,b,p.priorityBay,'clearPriority')
    elseif phase=='resume'then schedule(p,function()restore(s,q,p);p.phase='resumeYielder'end,'resume')
    elseif phase=='resumeYielder'then install(a,{},p.goalX,p.goalY);a.pathGoal=nil;p.phase=phase
    elseif phase=='restorePriority'and p.priorityGoal then replan(p,b,p.priorityGoal,'restorePriority')
    elseif phase=='passing'then install(b,{},p.priorityGoal.x,p.priorityGoal.y);b.pathGoal=nil;p.phase=phase
    else abandon(s,q,p)end
   end
  end
 end
 return true
end
function T.beforeMove(s,e,x,y,dt)
 if guards[e]or not G.enabled(s)or not alive(e)or not dt or dt<=0 then return false end
 local q=state(s);cleanup(s,q)
 local lane=laneAhead(e)
 if lane and owns(s,lane)then q.arrivals[e.id]=q.arrivals[e.id]or s.time elseif not q.byId[e.id]then q.arrivals[e.id]=nil end
 local p=q.byId[e.id]
 if not p and(not q.retry[e.id]or s.time>=q.retry[e.id])then
  local candidates={}
  for _,other in pairs(s.entities or {})do if alive(other)and other.id~=e.id and other.faction==e.faction and order(other)and not q.byId[other.id]and conflict(s,e,other)then candidates[#candidates+1]=other end end
  table.sort(candidates,function(a,b)return a.id<b.id end)
  if candidates[1]then begin(s,q,e,candidates[1],x,y);p=q.byId[e.id]end
 end
 if not p then return false end
 if e.id==p.priority then
  if p.phase~='passing'then q.stats.waits=q.stats.waits+1;return true end
  return false
 end
 if p.phase=='resumeYielder'then return false end
 if p.phase=='retreat'then
  if (e.vesselLane or 0)==(p.target.lane or 0)and dist(e.x,e.y,p.target.x,p.target.y)<.055 then p.phase='passing';q.stats.waits=q.stats.waits+1;return true end
  guards[e]=true
  local ok,err=pcall(require('war.Commands').go,s,e,p.target.x,p.target.y,dt,.025,p.target.lane or 0)
  guards[e]=nil
  if not ok then error(err)end
  return true
 end
 q.stats.waits=q.stats.waits+1
 return true
end
return T
