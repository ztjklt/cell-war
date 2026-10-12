-- Opt-in multi-organ facade. Existing gastric saves still delegate unchanged.
local Gastric=require('war.GastricBattlefield')
local Factory=require('war.OrganBattlefieldCore')
---@type table|nil
local Data=nil
local O={data=Gastric.data,maxRadiusSource=.53125}
local engines,proxies,traffic={},setmetatable({},{__mode='k'}),{}
local contexts=setmetatable({},{__mode='k'})
local jobs=setmetatable({},{__mode='k'})
local counters={requests=0,failures=0,yields=0,maxResumeSeconds=0}
local frozenState={anatomyVersion=4,gastricBattlefieldVersion=1}
local function opted(s)return s and s.anatomyVersion==4 and (s.organBattlefieldVersion==1 or s.fullbodyBattlefieldVersion==1) end
local function proxy(s)
 local p=proxies[s]
 if not p then p=setmetatable({gastricBattlefieldVersion=1},{__index=s});proxies[s]=p end
 return p
end
function O.enabled(s)return opted(s)or Gastric.enabled(s)end
function O.radius(e)return Gastric.radius(e)end
function O.net(s)
 if not opted(s)then return Gastric.net(s)end
 return require('war.Vessels').forState(frozenState)
end
function O.organ(id)
 if id=='stomach'then return Gastric.data end
 if not Data then Data=require('war.OrganBattlefieldData')end
 return Data.organs and Data.organs[id]
end
function O.activeOrgans(s)
 if not opted(s)then return Gastric.enabled(s)and{'stomach'}or{}end
 local cached=contexts[s]
 if cached and cached.ids==s.organBattlefieldIds then return cached.active end
 local out,seen={},{}
 for _,id in ipairs(s.organBattlefieldIds or {})do
  local d=O.organ(id)
  if d and d.available~=false and not seen[id]then out[#out+1]=id;seen[id]=true end
 end
 table.sort(out);contexts[s]={ids=s.organBattlefieldIds,active=out};return out
end
local function engine(id)
 if id=='stomach'then return Gastric end
 if not engines[id]then
  local d=O.organ(id);if not d or d.available==false then return nil end
  engines[id]=Factory.create(d,{enabled=opted,net=O.net})
 end
 return engines[id]
end
local function stateFor(s,id)return id=='stomach'and proxy(s)or s end
function O.enable(s,ids)
 if not s or s.anatomyVersion~=4 or s.campaign then return false,'UNSUPPORTED_STATE'end
 local copy,seen={},{}
 for _,id in ipairs(ids or {'stomach'})do
  local d=O.organ(id)
  if not d or d.available==false then return false,'ORGAN_UNAVAILABLE:'..tostring(id)end
  if not seen[id]then copy[#copy+1]=id;seen[id]=true end
 end
 if #copy==0 then return false,'EMPTY_ORGAN_SET'end
 table.sort(copy);s.organBattlefieldVersion=1;s.organBattlefieldIds=copy
 for _,id in ipairs(copy)do engine(id).enable(stateFor(s,id))end
 O.net(s);return true
end
local function activeEngine(s,id)
 for _,name in ipairs(O.activeOrgans(s))do if name==id then return engine(id)end end
end
local function transitOwner(s,e)
 local t=e and e.gastricTransit;if not t then return nil end
 for _,id in ipairs(O.activeOrgans(s))do
  for _,g in ipairs(O.organ(id).gateContracts.siege)do if g.id==t.gateId then return id end end
 end
end
local function bloodOwner(s,lane)
 for _,id in ipairs(O.activeOrgans(s))do
  if O.organ(id).bloodLanes.siege[lane]then return id end
 end
 return O.activeOrgans(s)[1]
end
function O.organAt(s,e,x,y)
 if not opted(s)then return Gastric.pointAllowed(s,e,x,y,0)and'stomach'or nil end
 local owner=transitOwner(s,e)
 if owner and engine(owner).pointAllowed(stateFor(s,owner),e,x,y,0)then return owner end
 local found
 for _,id in ipairs(O.activeOrgans(s))do
  if engine(id).pointAllowed(stateFor(s,id),e,x,y,0)then
   -- Overlapping organization floors require an explicit layer contract.
   if found then return nil,'AMBIGUOUS_TISSUE_LAYER'end;found=id
  end
 end
 return found
end
function O.pointAllowed(s,e,x,y,lane)
 if not opted(s)then return Gastric.pointAllowed(s,e,x,y,lane)end
 lane=lane==nil and(e.vesselLane or 0)or lane
 if lane==0 then return O.organAt(s,e,x,y)~=nil end
 local id=transitOwner(s,e)or bloodOwner(s,lane)
 return id and engine(id).pointAllowed(stateFor(s,id),e,x,y,lane)or false
end
function O.sweep(s,e,x,y,tx,ty,fromLane,toLane)
 if not opted(s)then return Gastric.sweep(s,e,x,y,tx,ty,fromLane,toLane)end
 local from=fromLane==nil and(e.vesselLane or 0)or fromLane
 local to=toLane==nil and from or toLane
 local owner=transitOwner(s,e)
 if not owner and from==0 then owner=O.organAt(s,e,x,y)end
 if from==0 and to==0 and not owner then return false end
 if owner then return engine(owner).sweep(stateFor(s,owner),e,x,y,tx,ty,from,to)end
 if to==0 then
  -- A blood lane can serve multiple organs; only a named intersected throat
  -- may change compartments. Never union their organization floors.
  for _,id in ipairs(O.activeOrgans(s))do
   if O.organ(id).bloodLanes.siege[from]then
    local ok,lane,t=engine(id).sweep(stateFor(s,id),e,x,y,tx,ty,from,to)
    if ok and(lane==0 or t)then return ok,lane,t end
   end
  end
  local id=bloodOwner(s,from)
  if id then return engine(id).sweep(stateFor(s,id),e,x,y,tx,ty,from,from)end
  return false
 end
 local id=bloodOwner(s,from)
 if id then return engine(id).sweep(stateFor(s,id),e,x,y,tx,ty,from,to)end
 return false
end
function O.lane(s,e,x,y,preferred)
 if not opted(s)then return Gastric.lane(s,e,x,y,preferred)end
 if preferred~=nil and O.pointAllowed(s,e,x,y,preferred)then return preferred end
 if O.pointAllowed(s,e,x,y,0)then return 0 end
 local net=O.net(s)
 for lane=1,#net.edges do if O.pointAllowed(s,e,x,y,lane)then return lane end end
end
function O.handles(s,x,y,tx,ty)
 if not opted(s)then return Gastric.handles(s,x,y,tx,ty)end
 for _,id in ipairs(O.activeOrgans(s))do
  if engine(id).handles(stateFor(s,id),x,y,tx,ty)then return true end
 end
 return false
end
function O.trafficData(s)
 if not opted(s)then return Gastric.data end
 local ids=O.activeOrgans(s);local key=table.concat(ids,'|')
 if traffic[key]then return traffic[key]end
 local d={bloodLanes={scout={},siege={}},gateContracts={scout={},siege={}}}
 for _,id in ipairs(ids)do for _,kind in ipairs({'scout','siege'})do
  for lane,b in pairs(O.organ(id).bloodLanes[kind])do d.bloodLanes[kind][lane]=b end
  for _,g in ipairs(O.organ(id).gateContracts[kind])do d.gateContracts[kind][#d.gateContracts[kind]+1]=g end
 end end
 traffic[key]=d;return d
end
local function targetEngine(s,e,x,y,lane)
 return lane==0 and O.organAt(s,e,x,y)or bloodOwner(s,lane)
end
local function selectedNear(s,e,x,y,lane)
 local id=targetEngine(s,e,x,y,lane)
 if id then return id end
 local sx,sy=x*.5,(y-512)*.5
 for _,name in ipairs(O.activeOrgans(s))do local b=O.organ(name).sourceBox
  if sx>=b[1]and sx<=b[3]and sy>=b[2]and sy<=b[4]then return name end
 end
end
function O.projectTarget(s,e,x,y,lane,limit)
 if not opted(s)then return Gastric.projectTarget(s,e,x,y,lane,limit)end
 local id=selectedNear(s,e,x,y,lane or 0)
 if id then return engine(id).projectTarget(stateFor(s,id),e,x,y,lane,limit)end
end
function O.formation(s,units,x,y,lane)
 if not opted(s)then return Gastric.formation(s,units,x,y,lane)end
 local id=units[1]and selectedNear(s,units[1],x,y,lane or 0)
 if id then return engine(id).formation(stateFor(s,id),units,x,y,lane)end
 local out={};for _,e in ipairs(units)do out[#out+1]={id=e.id,failed=true,radiusSource=O.radius(e)}end;return out
end
local function copyUnit(e)
 local u={id=e.id,kind=e.kind,x=e.x,y=e.y,vesselLane=e.vesselLane,faction=e.faction}
 if e.gastricTransit then local t=e.gastricTransit;u.gastricTransit={gateId=t.gateId,fromLane=t.fromLane,toLane=t.toLane}end
 return u
end
local function checkpoint()
 local j=jobs[coroutine.running()]
 if j and os.clock()>=j.deadline then counters.yields=counters.yields+1;coroutine.yield()end
end
local function localRoute(s,e,id,x,y,lane)
 local core=engine(id);local job=core.beginRoute(stateFor(s,id),e,x,y,lane)
 local outer=jobs[coroutine.running()];if outer then outer.child,outer.childEngine=job,core end
 while true do
  local done,path,reason=core.resumeRoute(job,.0005)
  if done then
   if outer then outer.child=nil;outer.childEngine=nil end
   if type(path)=='table'then for _,p in ipairs(path)do if p.lane==0 then p.organId=id end end end
   return path,reason
  end
  if outer then checkpoint()end
 end
end
local function length(e,path)
 local x,y,total=e.x,e.y,0
 for _,p in ipairs(path)do total=total+math.sqrt((p.x-x)^2+(p.y-y)^2);x,y=p.x,p.y end
 return total
end
local function verify(s,e,path)
 local probe=copyUnit(e)
 for _,p in ipairs(path)do
  checkpoint()
  local ok,lane,t=O.sweep(s,probe,probe.x,probe.y,p.x,p.y,probe.vesselLane,p.lane)
  if not ok or lane~=p.lane then return false end
  probe.x,probe.y,probe.vesselLane,probe.gastricTransit=p.x,p.y,lane,t
 end
 return true
end
local function solve(s,e,x,y,lane)
 counters.requests=counters.requests+1
 local startLane=e.vesselLane or O.lane(s,e,e.x,e.y)or 0
 lane=lane==nil and O.lane(s,e,x,y,startLane)or lane
 if lane==nil or not O.pointAllowed(s,e,x,y,lane)then return false,'EXACT_TARGET_INVALID'end
 local source=transitOwner(s,e)or targetEngine(s,e,e.x,e.y,startLane)
 local target=targetEngine(s,e,x,y,lane)
 if not source or not target then return false,'NO_ACTIVE_ORGAN_LAYER'end
 if e.gastricTransit and source~=target then
  local profile=O.radius(e)<=.21875 and'scout'or'siege'
  for _,gate in ipairs(O.organ(source).gateContracts[profile])do if gate.id==e.gastricTransit.gateId then
   local gx,gy=gate.pipeAnchorSource[1]*2,gate.pipeAnchorSource[2]*2+512
   local prefix=localRoute(s,e,source,gx,gy,gate.laneIndex)
   if type(prefix)~='table'then return false,'SOURCE_TRANSIT_NOT_REACHABLE'end
   local unit=copyUnit(e);unit.x,unit.y,unit.vesselLane,unit.gastricTransit=gx,gy,gate.laneIndex,nil
   local tail,why=localRoute(s,unit,target,x,y,lane)
   if type(tail)~='table'then return false,why end
   for _,point in ipairs(tail)do prefix[#prefix+1]=point end
   if not verify(s,e,prefix)then return false,'TRANSIT_COMPOSITION_REJECTED'end
   return prefix
  end end
  return false,'UNKNOWN_SOURCE_TRANSIT'
 end
 if source==target or startLane>0 or lane>0 then
  local id=lane==0 and target or source
  local path,why=localRoute(s,e,id,x,y,lane)
  if type(path)=='table'and not verify(s,e,path)then return false,'COMPOSED_SWEEP_REJECTED'end
  return path,why
 end
 -- Organ tissue domains never connect directly. The only inter-organ legs are
 -- named destination gates reached through the frozen blood graph.
 local profile=O.radius(e)<=.21875 and'scout'or'siege'
 local best,bestCost=nil,math.huge
 for _,g in ipairs(O.organ(target).gateContracts[profile])do
  checkpoint()
  local gx,gy=g.pipeAnchorSource[1]*2,g.pipeAnchorSource[2]*2+512
  local first=localRoute(s,e,source,gx,gy,g.laneIndex)
  if type(first)=='table'then
   local unit=copyUnit(e);unit.x,unit.y,unit.vesselLane,unit.gastricTransit=gx,gy,g.laneIndex,nil
   local last=localRoute(s,unit,target,x,y,0)
   if type(last)=='table'then
    local all={};for _,p in ipairs(first)do all[#all+1]=p end;for _,p in ipairs(last)do all[#all+1]=p end
    local cost=length(e,all)
    if cost<bestCost and verify(s,e,all)then best,bestCost=all,cost end
   end
  end
 end
 if best then return best end
 return false,'NO_VERIFIED_CROSS_ORGAN_ROUTE'
end
function O.beginRoute(s,e,x,y,lane)
 if not opted(s)then return {delegate=Gastric,job=Gastric.beginRoute(s,e,x,y,lane)}end
 local unit=copyUnit(e);local j={deadline=0,done=false,startX=e.x,startY=e.y,orderToken=e.orderToken}
 j.thread=coroutine.create(function()return solve(s,unit,x,y,lane)end);jobs[j.thread]=j;return j
end
function O.resumeRoute(j,seconds)
 if not j then return true,false,'NO_JOB'end
 if j.delegate then return j.delegate.resumeRoute(j.job,seconds)end
 if j.done then return true,j.path,j.reason end
 local budget=math.max(0,math.min(seconds or .003,.003));if budget==0 then return false end
 local began=os.clock();j.deadline=began+budget
 local ok,path,reason=coroutine.resume(j.thread)
 counters.maxResumeSeconds=math.max(counters.maxResumeSeconds,os.clock()-began)
 if not ok then j.done,j.path,j.reason=true,false,'ORGAN_ROUTE_ERROR:'..tostring(path)
 elseif coroutine.status(j.thread)=='dead'then j.done,j.path,j.reason=true,path,reason end
 if j.done then jobs[j.thread]=nil;if not j.path then counters.failures=counters.failures+1 end;return true,j.path,j.reason end
 return false
end
function O.cancelRoute(j)
 if not j then return end
 if j.delegate then return j.delegate.cancelRoute(j.job)end
 if j.done then return end
 if j.child then j.childEngine.cancelRoute(j.child)end
 jobs[j.thread]=nil;j.done,j.path,j.reason=true,false,'CANCELLED'
 if coroutine.close then coroutine.close(j.thread)end
end
function O.route(s,e,x,y,lane)
 if not opted(s)then return Gastric.route(s,e,x,y,lane)end
 local j=O.beginRoute(s,e,x,y,lane)
 while true do local done,path,reason=O.resumeRoute(j,.003);if done then return path,reason end end
end
function O.reset()
 for _,j in pairs(jobs)do O.cancelRoute(j)end
 for _,g in pairs(engines)do g.reset()end
 Gastric.reset();traffic={}
end
function O.stats()
 local out={};for k,v in pairs(counters)do out[k]=v end;return out
end
return O
