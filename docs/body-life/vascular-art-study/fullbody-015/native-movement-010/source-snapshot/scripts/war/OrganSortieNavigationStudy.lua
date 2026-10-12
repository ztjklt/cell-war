-- Isolated general organ sortie planner: exact endpoints, declared portals, real swept geometry.
local M={}
local diagnostics=setmetatable({},{__mode="k"})
function M.diagnostics(e)return diagnostics[e]end
local function centerRoute(net,x,y,tx,ty,lane,goalLane)
 local function connector(id,px,py)
  local _,cx,cy,index,t=net.distance(id,px,py)
  return {edge=id,x=cx,y=cy,index=index,t=t}
 end
 local a,b=connector(lane,x,y),connector(goalLane,tx,ty)
 local function portion(c,toEnd)
  local edge=net.edges[c.edge];local out={{x=c.x,y=c.y,lane=c.edge}};local length=0
  if toEnd then for i=c.index+1,#edge.points do out[#out+1]={x=edge.points[i][1],y=edge.points[i][2],lane=c.edge}end
  else for i=c.index,1,-1 do out[#out+1]={x=edge.points[i][1],y=edge.points[i][2],lane=c.edge}end end
  for i=2,#out do length=length+math.sqrt((out[i].x-out[i-1].x)^2+(out[i].y-out[i-1].y)^2)end
  return out,length
 end
 local ea,eb=net.edges[lane],net.edges[goalLane]
 if lane==goalLane then
  local out={{x=a.x,y=a.y,lane=lane}}
  local sa=ea.arc[a.index]+a.t*(ea.arc[a.index+1]-ea.arc[a.index])
  local sb=ea.arc[b.index]+b.t*(ea.arc[b.index+1]-ea.arc[b.index])
  if sb>=sa then for i=a.index+1,b.index do out[#out+1]={x=ea.points[i][1],y=ea.points[i][2],lane=lane}end
  else for i=a.index,b.index+1,-1 do out[#out+1]={x=ea.points[i][1],y=ea.points[i][2],lane=lane}end end
  out[#out+1]={x=b.x,y=b.y,lane=lane};out[#out+1]={x=tx,y=ty,lane=lane};return out
 end
 local ap,al=portion(a,false);local aq,ar=portion(a,true)
 local dist={[ea.a]=al,[ea.b]=ar};local prev={};local open={[ea.a]=true,[ea.b]=true}
 while next(open)do
  local current,dd=nil,math.huge
  for id in pairs(open)do if dist[id]<dd then current,dd=id,dist[id]end end
  open[current]=nil
  for _,id in ipairs(net.nodes[current].edges)do
   local edge=net.edges[id];local other=edge.a==current and edge.b or edge.a;local d=dd+edge.length
   if not dist[other] or d<dist[other] then dist[other]=d;prev[other]={from=current,edge=id};open[other]=true end
  end
 end
 local bp,bl=portion(b,false);local bq,br=portion(b,true)
 local finish=(dist[eb.a]or math.huge)+bl<(dist[eb.b]or math.huge)+br and eb.a or eb.b
 if not dist[finish]then return false end
 local chain={};local start=finish
 while prev[start]do chain[#chain+1]={from=prev[start].from,to=start,edge=prev[start].edge};start=prev[start].from end
 local out={};for _,p in ipairs(start==ea.a and ap or aq)do out[#out+1]=p end
 for i=#chain,1,-1 do
  local c=chain[i];local edge=net.edges[c.edge]
  if c.from==edge.a then for j=1,#edge.points do out[#out+1]={x=edge.points[j][1],y=edge.points[j][2],lane=c.edge}end
  else for j=#edge.points,1,-1 do out[#out+1]={x=edge.points[j][1],y=edge.points[j][2],lane=c.edge}end end
 end
 local tail=finish==eb.a and bp or bq
 for i=#tail,1,-1 do out[#out+1]=tail[i]end
 out[#out+1]={x=tx,y=ty,lane=goalLane};return out
end
local function push(heap,n)
 local i=#heap+1;while i>1 do local parent=math.floor(i/2);if heap[parent].f<=n.f then break end;heap[i]=heap[parent];i=parent end;heap[i]=n
end
local function pop(heap)
 local root=heap[1];local last=table.remove(heap)
 if #heap>0 then local i=1;while i*2<=#heap do local c=i*2;if c+1<=#heap and heap[c+1].f<heap[c].f then c=c+1 end;if last.f<=heap[c].f then break end;heap[i]=heap[c];i=c end;heap[i]=last end
 return root
end
local function dist(a,b)return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)end
local function append(a,b)for _,p in ipairs(b)do a[#a+1]=p end end
function M.attachForTest(P,C,W,geometry,options)
 options=options or {};local frameSeconds=options.frameSeconds or .002
 local unOld,oldStats=require('war.OrganRouteNavigationStudy').attachForTest(P,C,W)
 local oldRequest,oldUpdate,oldReset,oldGo=P.request,P.update,P.reset,C.go
 local routeCache,cacheOrder,cacheNodes={},{},0
 local jobs={};local stats={cacheHits=0,cacheEntries=0,cacheNodes=0,requested=0,completed=0,failed=0,cancelled=0,totalCpuSeconds=0,maxSliceSeconds=0,maxQueued=0,maxPrimitiveSeconds=0,old=oldStats}
 local function checkpoint(q)
  if q.expansions>=(options.nodeBudget or 120000)then error({kind='NODE_BUDGET_EXCEEDED'})end
  if q.cpu+os.clock()-q.resumed>(options.cpuBudgetSeconds or 10)then error({kind='CPU_BUDGET_EXCEEDED'})end
  if q.expansions%8==0 or os.clock()-q.yieldTime>.0008 then coroutine.yield();q.yieldTime=os.clock()end
 end
 local function solve(q)
  local s,e=q.s,q.e;local net=W.vessels(s)
  local edgeIds={};for id,owned in pairs(e.sortieEdges or {})do if owned then edgeIds[#edgeIds+1]=id end end;table.sort(edgeIds)
  local scope=table.concat({tostring(geometry),tostring(net),tostring(e.sortieZone),tostring(require('war.CellCollision').radius(e)),table.concat(edgeIds,','),tostring(e.faction),geometry.cacheIdentity and tostring(geometry.cacheIdentity(s,e))or ''},'|')
  local function key(a,b)return scope..string.format('|%.17g,%.17g,%d>%.17g,%.17g,%d',a.x,a.y,a.lane,b.x,b.y,b.lane)end
  local function put(a,b,route)
   local id=key(a,b);if routeCache[id] or #route>1024 then return end
   while #cacheOrder>=64 or cacheNodes+#route>8192 do local old=table.remove(cacheOrder,1);cacheNodes=cacheNodes-#routeCache[old];routeCache[old]=nil end
   routeCache[id]=route;cacheOrder[#cacheOrder+1]=id;cacheNodes=cacheNodes+#route;stats.cacheEntries=#cacheOrder;stats.cacheNodes=cacheNodes
  end
  local function clear(a,b)
   checkpoint(q);local began=os.clock();local ok=geometry.sweep(s,e,a.x,a.y,b.x,b.y,a.lane,b.lane)
   local elapsed=os.clock()-began;stats.maxPrimitiveSeconds=math.max(stats.maxPrimitiveSeconds,elapsed);q.maxPrimitiveSeconds=math.max(q.maxPrimitiveSeconds or 0,elapsed);return ok
  end
  local function cached(a,b)
   local route=routeCache[key(a,b)];if not route then return nil end
   local previous=a;for _,p in ipairs(route)do if not clear(previous,p)then return nil end;previous=p end
   stats.cacheHits=stats.cacheHits+1;local copy={};for _,p in ipairs(route)do copy[#copy+1]={x=p.x,y=p.y,lane=p.lane}end;return copy
  end
  local function allowed(p)
   checkpoint(q);local began=os.clock();local ok=geometry.pointAllowed(s,e,p.x,p.y,p.lane)
   stats.maxPrimitiveSeconds=math.max(stats.maxPrimitiveSeconds,os.clock()-began)
   return ok and clear(p,p)
  end
  local start={x=e.x,y=e.y,lane=e.vesselLane or 0};local goal={x=q.x,y=q.y,lane=q.lane}
  if not allowed(start) or not allowed(goal)then return nil,'EXACT_ENDPOINT_INVALID'end
  if clear(start,goal)then return {goal}end
  local saved=cached(start,goal);if saved then return saved end
  local function checkedBlood(a,b)
   if a.lane<=0 or b.lane<=0 then return nil end
   local route=centerRoute(net,a.x,a.y,b.x,b.y,a.lane,b.lane);if not route then return nil end
   local previous=a
   for _,p in ipairs(route)do checkpoint(q);if not clear(previous,p)then return nil end;previous=p end
   return route
  end
  if start.lane>0 and goal.lane>0 then
   local blood=checkedBlood(start,goal);if blood then return blood end
  end
  local bounds=geometry.bounds and geometry.bounds(s,e)or{minX=math.min(start.x,goal.x)-64,minY=math.min(start.y,goal.y)-64,maxX=math.max(start.x,goal.x)+64,maxY=math.max(start.y,goal.y)+64}
  -- Generic exact-to-lattice A*. Multiple visible initial lattice points are
  -- seeded; no fictional half-integer starting location is ever assumed.
  local function search(source,targets,step,lanes,box,limit,origin)
   origin=origin or {x=0,y=0}
   local open,g,closed,parent,points={},{},{},{},{};local expanded=0;local pointCache={};local began=q.expansions
   local function heuristic(p)local d=math.huge;for _,t in ipairs(targets)do d=math.min(d,dist(p,t))end;return d end
   local function key(ix,iy,lane)return ix..':'..iy..':'..lane end
   local function point(ix,iy,lane)
    local k=key(ix,iy,lane);local p=pointCache[k]
    if p==nil then p={x=origin.x+ix*step,y=origin.y+iy*step,lane=lane};if p.x<box.minX or p.y<box.minY or p.x>box.maxX or p.y>box.maxY or not allowed(p)then p=false end;pointCache[k]=p end
    return p,k
   end
   for dy=-2,2 do for dx=-2,2 do for _,lane in ipairs(lanes)do
    local p,k=point(math.floor((source.x-origin.x)/step+.5)+dx,math.floor((source.y-origin.y)/step+.5)+dy,lane)
    if p and clear(source,p)then local d=dist(source,p);g[k]=d;points[k]=p;push(open,{k=k,p=p,g=d,f=d+heuristic(p)})end
   end end end
   while #open>0 and expanded<(limit or 24000)do
    checkpoint(q);local n=pop(open)
    if not closed[n.k]then
     closed[n.k]=true;expanded=expanded+1;q.expansions=q.expansions+1
     for ti,t in ipairs(targets)do
      if dist(n.p,t)<=step*3 and clear(n.p,t)then
       local reversed={};local k=n.k;while k do reversed[#reversed+1]=points[k];k=parent[k]end
       local route={};for i=#reversed,1,-1 do route[#route+1]=reversed[i]end;route[#route+1]={x=t.x,y=t.y,lane=t.lane}
       -- Every smoothed chord is checked against the same strict geometry.
       local smooth={};local p=source;local i=1
       while i<=#route do local far=i
        for j=i+1,math.min(#route,i+12)do if clear(p,route[j])then far=j else break end end
        smooth[#smooth+1]=route[far];p=route[far];i=far+1
       end
       return smooth,ti,'FOUND'
      end
     end
     local ix,iy=math.floor((n.p.x-origin.x)/step+.5),math.floor((n.p.y-origin.y)/step+.5)
     for dy=-1,1 do for dx=-1,1 do for _,lane in ipairs(lanes)do
      if dx~=0 or dy~=0 or lane~=n.p.lane then
       local p,k=point(ix+dx,iy+dy,lane)
       if p and not closed[k]then local cost=n.g+dist(n.p,p)+(lane~=n.p.lane and .00001 or 0)
        if (not g[k]or cost<g[k])and clear(n.p,p)then g[k]=cost;points[k]=p;parent[k]=n.k;push(open,{k=k,p=p,g=cost,f=cost+heuristic(p)})end
       end
      end
     end end end
    end
   end
   q.lastSearch={step=step,expanded=q.expansions-began,exhausted=#open==0}
   return nil,nil,#open==0 and 'COMPONENT_EXHAUSTED' or 'SEARCH_LIMIT'
  end
  local function tissue(source,targets)
   local nearest,nearestDistance;for i,target in ipairs(targets)do local d=dist(source,target);if (not nearestDistance or d<nearestDistance)and clear(source,target)then nearest=i;nearestDistance=d end end;if nearest then return {targets[nearest]},nearest end
   for _,step in ipairs(options.resolutions or {1,.5,.25})do
    local route,id=search(source,targets,step,{0},bounds,options.searchNodeBudget or 24000)
    if route then return route,id end
   end
   return nil
  end
  -- Nearby tissue orders often only need to round a fixed membrane corner.
  -- Try bounded exact-endpoint local grids before constructing every organ portal.
  if start.lane==0 and goal.lane==0 and dist(start,goal)<32 then
   local localBounds={minX=math.min(start.x,goal.x)-5,minY=math.min(start.y,goal.y)-5,maxX=math.max(start.x,goal.x)+5,maxY=math.max(start.y,goal.y)+5}
   for _,step in ipairs({1,.5,.25,.125})do
    for _,origin in ipairs({start,goal})do
     local route=search(start,{goal},step,{0},localBounds,4000,origin)
     if route then return route end
    end
   end
  end
  if start.lane==0 and goal.lane==0 and dist(start,goal)>=32 then
   local route=search(start,{goal},1,{0},bounds,6000)
   if route then return route end
  end
  local gates=geometry.portals and geometry.portals(s,e)or net.gates
  -- A nearby explicit membrane command must not first tour unrelated portals.
  if (start.lane==0)~=(goal.lane==0) then
   local bloodLane=start.lane>0 and start.lane or goal.lane
   for _,gate in ipairs(gates)do
    if gate.edge==bloodLane and dist(start,{x=gate.x,y=gate.y})<12 and dist(goal,{x=gate.x,y=gate.y})<12 then
     local box={minX=math.min(start.x,goal.x)-5,minY=math.min(start.y,goal.y)-5,maxX=math.max(start.x,goal.x)+5,maxY=math.max(start.y,goal.y)+5}
     for _,step in ipairs({.5,.25,.125})do
      for _,origin in ipairs({start,goal})do
       local route=search(start,{goal},step,{bloodLane,0},box,2000,origin)
       if route then put(start,goal,route);return route end
      end
     end
    end
   end
  end
  local portals={}
  for _,gate in ipairs(gates)do
   checkpoint(q)
   local inner={x=gate.px,y=gate.py,lane=gate.edge}
   if allowed(inner)then
    local edge=net.edges[gate.edge];local radius=require('war.CellCollision').radius(e)
    local function addPortal(outside)
     if not allowed(outside)then return false end
     for _,p in ipairs(portals)do if p.id==gate.name and dist(p.outer,outside)<1e-8 then return true end end
     local box={minX=math.min(gate.x,outside.x)-8,minY=math.min(gate.y,outside.y)-8,maxX=math.max(gate.x,outside.x)+8,maxY=math.max(gate.y,outside.y)+8}
     local function crossing(a,b)
      local saved=cached(a,b);if saved then return saved end
      if clear(a,b)then return {b}end
      for _,step in ipairs({.5,.25,.125})do
       local route=search(a,{b},step,{gate.edge,0},box,step==.125 and 12000 or 4000)
       if route then put(a,b,route);return route end
      end
     end
     local before=q.expansions;local outward=crossing(inner,outside);q.portalAttempts=q.portalAttempts or {};local attempt={id=gate.name,x=outside.x,y=outside.y,outward=outward~=nil,search=q.lastSearch,expanded=q.expansions-before};q.portalAttempts[#q.portalAttempts+1]=attempt;if not outward then return false end
     local inward={};local previous=outside;local reversible=true
     for i=#outward-1,1,-1 do local p=outward[i];if not clear(previous,p)then reversible=false;break end;inward[#inward+1]=p;previous=p end
     if reversible and clear(previous,inner)then inward[#inward+1]=inner else inward=crossing(outside,inner)end
     attempt.inward=inward~=nil;if not inward then return false end
     portals[#portals+1]={inner=inner,outer=outside,outward=outward,inward=inward,id=gate.name};return true
    end
    -- Exact endpoint attachments are real paths through the declared aperture,
    -- not replacement destinations or a forced outside normal landing point.
    if start.lane==0 and dist(start,{x=gate.x,y=gate.y})<12 then addPortal(start)end
    if goal.lane==0 and dist(goal,{x=gate.x,y=gate.y})<12 then addPortal(goal)end
    for offset=0,8 do
     local distance=edge.width*.5+1.4+radius+.06+offset*.5
     if addPortal({x=gate.px+gate.nx*distance,y=gate.py+gate.ny*distance,lane=0})then break end
    end
   end
  end
  q.portals=#portals
  local targets={};for _,portal in ipairs(portals)do targets[#targets+1]=portal.outer end
  local aRoute,aPortal,bRoute,bPortal
  if start.lane==0 then
   local choices={};append(choices,targets);if goal.lane==0 then choices[#choices+1]=goal end
   if #choices==0 then return nil,'NO_VALID_PORTALS'end
   local selected;aRoute,selected=tissue(start,choices)
   if not aRoute then return nil,'START_COMPONENT_HAS_NO_REACHABLE_PORTAL'end
   if selected>#portals then return aRoute end
   aPortal=portals[selected]
  end
  if goal.lane==0 then
   if #targets==0 then return nil,'NO_VALID_PORTALS'end
   local selected;bRoute,selected=tissue(goal,targets)
   if not bRoute then return nil,'GOAL_COMPONENT_HAS_NO_REACHABLE_PORTAL'end
   bPortal=portals[selected]
  end
  local bloodStart=aPortal and aPortal.inner or start;local bloodGoal=bPortal and bPortal.inner or goal
  local blood=checkedBlood(bloodStart,bloodGoal)
  if not blood then return nil,'DECLARED_PORTALS_NOT_CONNECTED_BY_LEGAL_BLOOD_PATH'end
  local route={}
  if aPortal then append(route,aRoute);append(route,aPortal.inward)end
  append(route,blood)
  if bPortal then
   append(route,bPortal.outward);local previous=bPortal.outer
   for i=#bRoute-1,1,-1 do local p=bRoute[i];if not clear(previous,p)then return nil,'REVERSE_TISSUE_SEGMENT_REJECTED'end;route[#route+1]=p;previous=p end
   if not clear(previous,goal)then return nil,'EXACT_GOAL_CONNECTOR_REJECTED'end;route[#route+1]=goal
  end
  local previous=start
  for _,p in ipairs(route)do if not clear(previous,p)then return nil,'FINAL_PATH_RECHECK_REJECTED'end;previous=p end
  return route
 end
 P.request=function(s,e,x,y,forceFine)
  if geometry.activate then geometry.activate(s,e)end
  local order=e.orders and e.orders[1];local lane=order and order.vesselLane
  if lane==nil or not order.x or (order.x-x)^2+(order.y-y)^2>1e-6 then return oldRequest(s,e,x,y,forceFine)end
  if e.pathPending then
   for _,j in ipairs(jobs)do if j.e==e and j.token==e.orderToken then return end end
   for _,j in ipairs(P.jobs)do if j.id==e.id and j.token==e.orderToken then return end end
   e.pathPending=false
  end
  local q={s=s,e=e,x=x,y=y,lane=lane,token=e.orderToken,cpu=0,expansions=0,yieldTime=os.clock(),resumed=os.clock()}
  q.thread=coroutine.create(function()return solve(q)end);jobs[#jobs+1]=q
  e.path={};e.pathIndex=1;e.pathPending=true;e.pathFailed=false;e.longRoute=nil;e.pathGoal={x=x,y=y};e.pathResolved={x=x,y=y,adjusted=false}
  stats.requested=stats.requested+1;stats.maxQueued=math.max(stats.maxQueued,#jobs)
 end
 P.update=function(s,budget,seconds)
  local started=os.clock();local deadline=started+math.min(seconds or frameSeconds,frameSeconds)
  oldUpdate(s,budget,math.max(0,math.min(deadline-os.clock(),#jobs>0 and frameSeconds*.5 or frameSeconds)))
  while #jobs>0 and os.clock()<deadline do
   local q=table.remove(jobs,1);local e=q.e
   if not s.entities[e.id]or e.orderToken~=q.token then stats.cancelled=stats.cancelled+1
   else
    q.resumed=os.clock();local ok,route,reason=coroutine.resume(q.thread);local spent=os.clock()-q.resumed;q.cpu=q.cpu+spent;stats.totalCpuSeconds=stats.totalCpuSeconds+spent
    if not ok or coroutine.status(q.thread)=='dead'then
     e.pathPending=false;e.pathFailed=not ok or not route
     if ok and route then e.path=route;e.pathIndex=1;stats.completed=stats.completed+1
     else e.path={};stats.failed=stats.failed+1;reason=not ok and (type(route)=='table'and route.kind or tostring(route))or reason end
     diagnostics[e]={cpuSeconds=q.cpu,maxPrimitiveSeconds=q.maxPrimitiveSeconds,nodeExpansions=q.expansions,portals=q.portals,portalAttempts=q.portalAttempts,reason=reason,lastSearch=q.lastSearch,success=ok and route~=nil}
    else jobs[#jobs+1]=q end
   end
  end
  stats.maxSliceSeconds=math.max(stats.maxSliceSeconds,os.clock()-started)
 end
 P.reset=function()
  for _,q in ipairs(jobs)do
   if q.e.orderToken==q.token then q.e.pathPending=false;q.e.pathFailed=false;q.e.path={};q.e.pathIndex=1;diagnostics[q.e]={reason='CANCELLED_BY_RESET',success=false}end
   stats.cancelled=stats.cancelled+1
  end
  jobs={};oldReset()
 end
 C.go=function(s,e,x,y,dt,stopRange)
  if geometry.activate then geometry.activate(s,e)end
  local order=e.orders and e.orders[1]
  if order and order.vesselLane~=nil and e.vesselLane~=order.vesselLane then return oldGo(s,e,x,y,dt,-.001)end
  return oldGo(s,e,x,y,dt,stopRange)
 end
 return function()routeCache={};cacheOrder={};cacheNodes=0;P.request=oldRequest;P.update=oldUpdate;P.reset=oldReset;C.go=oldGo;unOld()end,stats
end
return M
