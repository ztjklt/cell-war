-- Opt-in coarse tissue planner. Every edge is swept by the unchanged real P.clear.
-- No collision override, radius change, target relocation, or tile modification.
local M={maxExpandedPerJob=12000,maxCpuPerJob=8}
-- Diagnostic/context state is private; Save.snapshot copies entity tables.
local contexts=setmetatable({},{__mode="k"})
local plans=setmetatable({},{__mode="k"})
local failures=setmetatable({},{__mode="k"})
-- Model-only memo is exact and independent of time, entities and radius.
function M.cacheGeometry(Base,Collision,model)
 local original,prior=Base.clearance,Collision.clearance;local memo,ring={},{};local cursor=1
 local stats={hits=0,misses=0,capacity=50000,count=0,peak=0,evictions=0}
 local function query(m,zone,x,y)
  if m~=model then return original(m,zone,x,y)end
  local layer=memo[zone];local row=layer and layer[x];local value=row and row[y]
  if value~=nil then stats.hits=stats.hits+1;return value end
  value=original(m,zone,x,y);stats.misses=stats.misses+1
  local slot=ring[cursor]
  if slot then
   local oldLayer=memo[slot[1]];local oldRow=oldLayer[slot[2]]
   oldRow[slot[3]]=nil;oldRow.count=oldRow.count-1
   if oldRow.count==0 then oldLayer[slot[2]]=nil end
   stats.evictions=stats.evictions+1
  else slot={};ring[cursor]=slot;stats.count=stats.count+1;stats.peak=math.max(stats.peak,stats.count)end
  layer=memo[zone];if not layer then layer={};memo[zone]=layer end
  row=layer[x];if not row then row={count=0};layer[x]=row end
  row[y]=value;row.count=row.count+1;slot[1],slot[2],slot[3]=zone,x,y
  cursor=cursor%stats.capacity+1;return value
 end
 Base.clearance=query;Collision.clearance=query
 return function()Base.clearance=original;Collision.clearance=prior end,stats
end
local function push(q,n)
 local i=#q+1;q[i]=n
 while i>1 do local p=i//2;if q[p].f<=n.f then break end;q[i]=q[p];i=p;q[i]=n end
end
local function pop(q)
 local first=q[1];local last=table.remove(q);if #q==0 then return first end
 local i=1;q[1]=last
 while i*2<=#q do local c=i*2;if c+1<=#q and q[c+1].f<q[c].f then c=c+1 end;if q[c].f>=last.f then break end;q[i]=q[c];i=c;q[i]=last end
 return first
end
local function snapshot(context)
 local copy={zone=context.zone,radius=context.radius,tissueEdges={}}
 for k,v in pairs(context.tissueEdges or {})do copy.tissueEdges[k]=v end
 return copy
end
function M.setContext(e,context)contexts[e]=context and snapshot(context) or nil end
function M.getPlan(e)return plans[e]end
function M.getFailure(e)return failures[e]end
function M.clearDiagnostics(e)plans[e]=nil;failures[e]=nil end
function M.attachForTest(P,C,W,context)
 local request,update,reset=P.request,P.update,P.reset;local jobs={}
 local stats={routes=0,expanded=0,edgeSweeps=0,rejectedEdges=0,failed=0,budgetExceeded=0,cancelled=0,maxUpdateCpu=0,maxEdgeCpu=0,planningCpu=0}
 local function clear(s,a,b,f)
  local t=os.clock();stats.edgeSweeps=stats.edgeSweeps+1
  local okay=P.clear(s,a.x,a.y,b.x,b.y,f,0,0)
  stats.maxEdgeCpu=math.max(stats.maxEdgeCpu,os.clock()-t)
  if not okay then stats.rejectedEdges=stats.rejectedEdges+1 end;return okay
 end
 local function install(e,j,n)
  local path={{x=j.tx,y=j.ty,lane=0}};while n do path[#path+1]={x=n.x,y=n.y,lane=0};n=n.parent end
  local out={};for i=#path-1,1,-1 do out[#out+1]=path[i]end
  local length=0;local px,py=e.x,e.y
  for _,p in ipairs(out)do length=length+math.sqrt((p.x-px)^2+(p.y-py)^2);px,py=p.x,p.y end
  plans[e]={lengthWorld=length,expanded=j.expanded,zone=j.context.zone,radius=j.context.radius,cpuSeconds=j.cpuSeconds}
  e.path=out;e.pathIndex=1;e.pathPending=false;e.pathFailed=false;e.longRoute=nil;e.pathResolved={x=j.tx,y=j.ty,adjusted=false};stats.routes=stats.routes+1
 end
 P.request=function(s,e,x,y,...)
  local order=e.orders and e.orders[1];local selected=contexts[e] or context
  if not selected.zone or (e.vesselLane or 0)~=0 or not order or order.vesselLane~=0 then return request(s,e,x,y,...)end
  if e.pathPending then return end
  local start={x=e.x,y=e.y,g=0,f=math.sqrt((e.x-x)^2+(e.y-y)^2),key='start'}
  local selectedCopy=snapshot(selected);selectedCopy.radius=require('war.CellCollision').radius(e)
  local j={state=s,entity=e,id=e.id,token=e.orderToken,tx=x,ty=y,open={start},closed={},best={start=0},step=16,expanded=0,start=start,context=selectedCopy,cpuSeconds=0}
  e.pathGoal={x=x,y=y};e.pathResolved={x=x,y=y,adjusted=false};e.path={};e.pathIndex=1;e.pathPending=true;e.pathFailed=false;e.longRoute=nil;plans[e]=nil;failures[e]=nil
  jobs[#jobs+1]=j
 end
 P.reset=function()
  for _,j in ipairs(jobs)do if j.entity.orderToken==j.token then j.entity.pathPending=false end end
  for i=#jobs,1,-1 do jobs[i]=nil end;return reset()
 end
 P.update=function(s,budget,seconds)
  local cpu=os.clock();local deadline=cpu+(seconds or .003);local expansions=0
  local previous={zone=context.zone,radius=context.radius,tissueEdges=context.tissueEdges}
  while #jobs>0 and os.clock()<deadline and expansions<math.max(1,budget or 500)do
   local j=table.remove(jobs,1);local e=j.entity;local iteration=os.clock();local keep=true
   if s~=j.state or s.entities[j.id]~=e or e.orderToken~=j.token then keep=false;stats.cancelled=stats.cancelled+1
   else
    context.zone=j.context.zone;context.radius=j.context.radius;context.tissueEdges=j.context.tissueEdges
    if j.candidates then
     local v=j.activeCandidate or table.remove(j.candidates)
     if not v then j.candidates=nil
     elseif not v.goal and (j.closed[v.key] or j.best[v.key] and v.g>=j.best[v.key])then j.activeCandidate=nil
     else
      -- Split one macro edge into real lane-0 sweeps, yielding after each piece.
      -- Requiring lane 0 at all piece endpoints is conservative, never a shortcut
      -- through a vessel compartment, wall, bone or undeclared membrane.
      local a=v.parent;local count=math.max(1,math.ceil(math.max(math.abs(v.x-a.x),math.abs(v.y-a.y))/4))
      local index=v.sweepIndex or 0
      local from={x=a.x+(v.x-a.x)*index/count,y=a.y+(v.y-a.y)*index/count}
      local to={x=a.x+(v.x-a.x)*(index+1)/count,y=a.y+(v.y-a.y)*(index+1)/count}
      if clear(s,from,to,e.faction)then
       v.sweepIndex=index+1
       if v.sweepIndex==count then
        j.activeCandidate=nil
        if v.goal then install(e,j,v.parent);keep=false
        else j.best[v.key]=v.g;push(j.open,v)end
       else j.activeCandidate=v end
      else j.activeCandidate=nil end
     end
    else
     local n=pop(j.open)
     if not n then
      if j.step>4 then j.step=j.step/2;j.open={j.start};j.closed={};j.best={start=0}
      else e.pathPending=false;e.pathFailed=true;failures[e]='coarse tissue graph exhausted';stats.failed=stats.failed+1;keep=false end
     elseif not j.closed[n.key] then
      j.closed[n.key]=true;j.expanded=j.expanded+1;stats.expanded=stats.expanded+1;expansions=expansions+1
      local gx,gy=math.floor(n.x/j.step+.5),math.floor(n.y/j.step+.5);local reach=n.key=='start' and 2 or 1
      j.candidates={}
      for dx=-reach,reach do for dy=-reach,reach do if dx~=0 or dy~=0 then
       local x,y=(gx+dx)*j.step,(gy+dy)*j.step;local key=x..':'..y
       local g=n.g+math.sqrt((x-n.x)^2+(y-n.y)^2)
       if not j.closed[key] and (not j.best[key] or g<j.best[key]) then
        j.candidates[#j.candidates+1]={x=x,y=y,key=key,g=g,f=g+math.sqrt((x-j.tx)^2+(y-j.ty)^2),parent=n}
       end
      end end end
      if (n.x-j.tx)^2+(n.y-j.ty)^2<=32*32 then
       j.candidates[#j.candidates+1]={x=j.tx,y=j.ty,parent=n,goal=true}
      end
     end
    end
   end
   local elapsed=os.clock()-iteration;j.cpuSeconds=j.cpuSeconds+elapsed;stats.planningCpu=stats.planningCpu+elapsed
   if not keep and plans[e] and e.orderToken==j.token and s.entities[j.id]==e then plans[e].cpuSeconds=j.cpuSeconds end
   if keep and (j.expanded>=M.maxExpandedPerJob or j.cpuSeconds>=M.maxCpuPerJob)then
    keep=false;e.pathPending=false;e.pathFailed=true
    failures[e]=j.expanded>=M.maxExpandedPerJob and 'BODY_REGION_NODE_BUDGET_EXCEEDED' or 'BODY_REGION_CPU_BUDGET_EXCEEDED'
    stats.budgetExceeded=stats.budgetExceeded+1
   end
   if keep then jobs[#jobs+1]=j end
  end
  context.zone=previous.zone;context.radius=previous.radius;context.tissueEdges=previous.tissueEdges
  if os.clock()<deadline then update(s,budget,math.max(0,deadline-os.clock()))end
  stats.maxUpdateCpu=math.max(stats.maxUpdateCpu,os.clock()-cpu)
 end
 return function()for _,j in ipairs(jobs)do if j.entity.orderToken==j.token then j.entity.pathPending=false end end;for i=#jobs,1,-1 do jobs[i]=nil end;P.request=request;P.update=update;P.reset=reset end,stats,jobs
end
return M
