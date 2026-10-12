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
local function route(s,e,x,y,lane)
 local co=coroutine.running();local p=planning[co]
 assert(p,'traffic routing must run inside the bounded planner')
 local job=G.beginRoute(s,e,x,y,lane);p.routeJob=job
 while true do
  local done,path=G.resumeRoute(job,.0005)
  if done then p.routeJob=nil;return path end
  coroutine.yield()
 end
end
local function cancelPlan(p)
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
local function clearUnits(s,e,path)
 local x,y=e.x,e.y
 for _,p in ipairs(path)do
  checkpoint()
  for _,other in pairs(s.entities or {})do if alive(other)and other.id~=e.id then
   if segmentDistance(other.x,other.y,x,y,p.x,p.y)<K.radius(e)+K.radius(other)+.015 then return false end
  end end
  x,y=p.x,p.y
 end
 return true
end
local function clearsReserved(x,y,e,other,path,goal)
 if not other then return true end
 local clearance=K.radius(e)+K.radius(other)+.12
 if goal and dist(x,y,goal.x,goal.y)<clearance then return false end
 local px,py=other.x,other.y
 for _,point in ipairs(type(path)=='table'and path or {})do
  checkpoint()
  if segmentDistance(x,y,px,py,point.x,point.y)<clearance then return false end
  px,py=point.x,point.y
 end
 return true
end
local function bay(s,q,e,reservedUnit,reservedPath,reservedGoal)
 local profile=G.radius(e)<=.21875 and 'scout'or'siege';local candidates={}
 -- Up to two valid holding points per declared gate; no pixel-derived spaces.
 for _,g in ipairs(G.trafficData(s).gateContracts[profile])do
  local localCandidates={};local ox,oy=g.tissueAnchorSource[1]*2,g.tissueAnchorSource[2]*2+512
  for _,radius in ipairs({3,5,8})do for i=0,15 do
   checkpoint()
   local angle=i*math.pi/8;local x,y=ox+math.cos(angle)*radius,oy+math.sin(angle)*radius
   if G.pointAllowed(s,e,x,y,0)and G.sweep(s,e,ox,oy,x,y,0,0)then
    local available=true
    for _,u in pairs(s.entities or {})do if alive(u)and u.id~=e.id and dist(x,y,u.x,u.y)<K.radius(e)+K.radius(u)+.5 then available=false;break end end
    if available and clearsReserved(x,y,e,reservedUnit,reservedPath,reservedGoal)then localCandidates[#localCandidates+1]={x=x,y=y,score=dist(e.x,e.y,x,y),gate=g.id}end
   end
  end end
  table.sort(localCandidates,function(a,b)if a.score==b.score then if a.x==b.x then return a.y<b.y end;return a.x<b.x end;return a.score<b.score end)
  for i=1,math.min(2,#localCandidates)do candidates[#candidates+1]=localCandidates[i]end
 end
 table.sort(candidates,function(a,b)if a.score==b.score then return a.gate<b.gate end;return a.score<b.score end)
 for _,target in ipairs(candidates)do
  q.stats.routeRequests=q.stats.routeRequests+1
  local path=route(s,e,target.x,target.y,0)
  if type(path)=='table'and clearUnits(s,e,path)then return target,path end
 end
 return nil,nil
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
 local target,path=bay(s,q,a,y,resumePath,{x=p.goalX,y=p.goalY})
 if target then
  p.phase='clearPriority';p.priorityOrder=nil;p.priorityBay=target;target.lane=0
  install(a,path,target.x,target.y);q.stats.secondaryYields=(q.stats.secondaryYields or 0)+1
 else p.phase='passing';p.retryAt=s.time+1 end
end
local function abandon(s,q,p)
 cancelPlan(p)
 -- Original Commands order remains untouched; invalidate only the temporary
 -- path so the normal incremental Path queue resumes the player's command.
 local e=s.entities[p.yielder]
 if alive(e)and order(e)==p.yieldOrder then
  install(e,{},p.goalX,p.goalY);e.pathGoal=nil
 end
 remove(q,p)
end
function T.cancel(s,e)
 if not states[s]then return end
 local q=state(s);local p=q.byId[e.id]
 if p then q.stats.cancelled=q.stats.cancelled+1;abandon(s,q,p)end
end
local function reached(e,target)
 return dist(e.x,e.y,target.x,target.y)<=.75 and(target.lane==nil or e.vesselLane==target.lane)
end
local function cleanup(s,q)
 for id in pairs(q.arrivals)do local e=s.entities[id];if not alive(e)or not order(e)then q.arrivals[id]=nil end end
 for id,t in pairs(q.retry)do if not alive(s.entities[id])or t<s.time then q.retry[id]=nil end end
 for i=#q.pairs,1,-1 do local p=q.pairs[i];local a,b=s.entities[p.yielder],s.entities[p.priority]
  if alive(a)and alive(b)then
   if not p.progress or dist(a.x,a.y,p.progress[1],p.progress[2])+dist(b.x,b.y,p.progress[3],p.progress[4])>.25 then
    p.progress={a.x,a.y,b.x,b.y};p.progressAt=s.time
   end
  end
  if not alive(a)or not alive(b)then q.stats.deadReleased=q.stats.deadReleased+1;abandon(s,q,p)
  elseif s.time-p.started>600 or s.time-(p.progressAt or p.started)>120 then q.stats.expired=q.stats.expired+1;abandon(s,q,p)
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
 local began=os.clock();local deadline=began+PLAN_BUDGET
 -- One shared traffic planning slice per simulation frame, never per actor.
 for _,p in ipairs(q.pairs)do
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
 local yielder,priority=s.entities[p.yielder],s.entities[p.priority]
 local a,b=yielder,priority
 schedule(p,function()
  local priorityPath=route(s,priority,p.priorityGoal.x,p.priorityGoal.y,p.priorityGoal.lane)
  local target,path=bay(s,q,yielder,priority,priorityPath,p.priorityGoal)
  if not target then
   local yieldPath=route(s,yielder,p.goalX,p.goalY,p.goalLane)
   target,path=bay(s,q,priority,yielder,yieldPath,{x=p.goalX,y=p.goalY})
   if target then
    priority,yielder=yielder,priority
    p.priority,p.yielder=priority.id,yielder.id
    p.priorityOrder,p.yieldOrder=order(priority),order(yielder)
    local yo,po=order(yielder),order(priority)
    p.goalX,p.goalY,p.goalLane=yo.x,yo.y,yo.lane or yo.vesselLane
    p.priorityGoal={x=po.x,y=po.y,lane=po.lane or po.vesselLane or priority.vesselLane}
   end
  end
  if not target then
   q.stats.noBay=q.stats.noBay+1;q.retry[a.id]=s.time+1;q.retry[b.id]=s.time+1;remove(q,p);return
  end
  p.target=target;p.phase='retreat';install(yielder,path,target.x,target.y)
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
  return t and{x=t.x,y=t.y,lane=t.lane,gate=t.gate,score=t.score}or nil
 end
 for _,p in ipairs(q.pairs)do
  out.pairs[#out.pairs+1]={yielder=p.yielder,priority=p.priority,
   hasYieldOrder=p.yieldOrder~=nil,hasPriorityOrder=p.priorityOrder~=nil,
   goalX=p.goalX,goalY=p.goalY,goalLane=p.goalLane,
   priorityGoal=target(p.priorityGoal),target=target(p.target),priorityBay=target(p.priorityBay),
   phase=p.phase,planKind=p.planKind,started=p.started,progressAt=p.progressAt}
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
   else abandon(s,q,p)end
  end,phase)
 end
 for i,src in ipairs(data.pairs or {})do
  if i>MAX_PAIRS then break end
  local a,b=s.entities[src.yielder],s.entities[src.priority]
  if alive(a)and alive(b)and not q.byId[a.id]and not q.byId[b.id]then
   local p={};for k,v in pairs(src)do p[k]=v end
   p.yieldOrder=src.hasYieldOrder and order(a)or nil
   p.priorityOrder=src.hasPriorityOrder and order(b)or nil
   if (not src.hasYieldOrder or p.yieldOrder)and(not src.hasPriorityOrder or p.priorityOrder)then
    q.pairs[#q.pairs+1]=p;q.byId[a.id]=p;q.byId[b.id]=p
    local phase=p.phase=='planning'and p.planKind or p.phase
    if phase=='initial'then planRetreat(s,q,p)
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
  if e.vesselLane==0 and dist(e.x,e.y,p.target.x,p.target.y)<.055 then p.phase='passing';q.stats.waits=q.stats.waits+1;return true end
  guards[e]=true
  local ok,err=pcall(require('war.Commands').go,s,e,p.target.x,p.target.y,dt,.025,0)
  guards[e]=nil
  if not ok then error(err)end
  return true
 end
 q.stats.waits=q.stats.waits+1
 return true
end
return T
