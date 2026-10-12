-- Opt-in study traffic controller. Every relocation is a real move order.
-- Geometry, radii, original goals and saved state are never changed.
local T={}
local precise=setmetatable({},{__mode='k'})
function T.isPrecise(e)return precise[e]==true end
local function dist(a,b)return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)end
local function segmentDistance(p,a,b)
 local dx,dy=b.x-a.x,b.y-a.y;local q=dx*dx+dy*dy
 local f=q>0 and math.max(0,math.min(1,((p.x-a.x)*dx+(p.y-a.y)*dy)/q))or 0
 return math.sqrt((p.x-a.x-f*dx)^2+(p.y-a.y-f*dy)^2)
end
local function copy(p)return {x=p.x,y=p.y,lane=p.lane}end
function T.attachPrecision(C)
 local original=C.go
 C.go=function(s,e,x,y,dt,range)
  return original(s,e,x,y,dt,precise[e] and .025 or range)
 end
 return function()C.go=original end
end
function T.create(config)
 local self={config=config,state='prepare-tissue',events={},queue={},sequence=0,completedTickets=0,maxWait=0,units=config.units,tissuePrepared={},bloodPrepared={},restoreIndex=1,now=0}
 local W,P,C,K,net,geo=config.W,config.P,config.C,config.K,config.net,config.geometry
 self.tick=function()end
 local s,gate=config.state,config.gate
 local edge=net.edges[gate.edge]
 local largest={};for k,v in pairs(config.units[1].entity)do largest[k]=v end;largest.kind='siege';largest.radius=K.radius('siege')
 local function alive(u)return s.entities[u.entity.id]==u.entity and (u.entity.hp or 1)>0 end
 local function event(kind,fields)
  local e={kind=kind,t=self.now};for k,v in pairs(fields or {})do e[k]=v end;self.events[#self.events+1]=e
 end
 local function fail(reason)
  local m=self.motion;local stopped=false
  -- Commands.execute replaces the order object when ownership changes. Internal
  -- navigation may advance its token while preserving our exact move object.
  if m and alive(m.unit)then local e=m.unit.entity
   if e.orders and e.orders[1]==m.order then
    C.execute(s,{kind='stop',faction=e.faction,ids={e.id}});stopped=true
   end
  end
  self.motion=nil;self.owner=nil;self.queue={}
  for _,u in ipairs(self.units)do precise[u.entity]=u.previousPrecision end
  self.state='failed';self.reason=reason;event('failed',{reason=reason,stoppedOwnedMove=stopped})
 end
 function self:abort(reason)fail(reason or 'explicit traffic abort')end
 local function throat(e)
  local radius=K.radius(e)
  local d=net.distance(gate.edge,e.x,e.y)
  return dist(e,gate)<=gate.radius+radius+.04 and d>=edge.width*.5-radius-.04 and d<=edge.width*.5+1.4+radius+.04
 end
 self.inThroat=throat
 local function legal(u,p)return geo.pointAllowed(s,u.entity,p.x,p.y,p.lane)end
 local function swept(u,a,b)return geo.sweep(s,u.entity,a.x,a.y,b.x,b.y,a.lane,b.lane)end
 local function freeSegment(u,a,b)
  for _,other in ipairs(self.units)do if other~=u and alive(other) then
   if segmentDistance(other.entity,a,b)<K.radius(u.entity)+K.radius(other.entity)+.06 then return false end
  end end;return true
 end
 local function arcPoint(value)
  value=math.max(0,math.min(edge.length,value))
  for i=2,#edge.points do if value<=edge.arc[i]then
   local f=(value-edge.arc[i-1])/math.max(1e-12,edge.arc[i]-edge.arc[i-1]);local a,b=edge.points[i-1],edge.points[i]
   return {x=a[1]+(b[1]-a[1])*f,y=a[2]+(b[2]-a[2])*f,lane=gate.edge}
  end end
  local p=edge.points[#edge.points];return {x=p[1],y=p[2],lane=gate.edge}
 end
 local function arcOf(p)
  local _,_,_,i,t=net.distance(gate.edge,p.x,p.y)
  return edge.arc[i]+t*(edge.arc[i+1]-edge.arc[i])
 end
 local gateArc=arcOf({x=gate.px,y=gate.py});local direction=gateArc<edge.length*.5 and 1 or -1
 local blood,tissue={},{}
 for _,u in ipairs(self.units)do
  u.previousPrecision=precise[u.entity];u.originalStages=0
  if u.side=='blood'then blood[#blood+1]=u else tissue[#tissue+1]=u end
 end
 table.sort(blood,function(a,b)return direction*arcOf(a.start)>direction*arcOf(b.start)end)
 for i,u in ipairs(blood)do
  local spacing=K.maxRadius*2+K.gap+.3;local baseDistance=gate.radius+K.maxRadius+.5
  u.bloodHolding=arcPoint(gateArc+direction*(baseDistance+(#blood-i)*spacing))
  if not legal(u,u.bloodHolding)or throat({x=u.bloodHolding.x,y=u.bloodHolding.y,kind=u.kind})then u.bloodHolding=arcPoint(gateArc+direction*(9+(#blood-i)*3.4))end
  if not legal(u,u.bloodHolding)or throat({x=u.bloodHolding.x,y=u.bloodHolding.y,kind=u.kind})then fail('no legal blood holding on unchanged exchange edge');return self end
 end
 -- A star of tissue parking bays keeps every occupied bay outside all other
 -- access rays. It is not a tissue shortcut: every ray is swept by the geometry.
 local anchor=copy(config.outside);anchor.lane=0;self.anchor=anchor
 local candidates={}
 for radius=8,24,2 do for degrees=0,355,5 do
  local angle=math.rad(degrees);local p={x=anchor.x+math.cos(angle)*radius,y=anchor.y+math.sin(angle)*radius,lane=0}
  if geo.pointAllowed(s,largest,p.x,p.y,0)and not throat({x=p.x,y=p.y,kind='siege'})and
     geo.sweep(s,largest,anchor.x,anchor.y,p.x,p.y,0,0)then
   local okay=true
   for _,u in ipairs(self.units)do for _,g in ipairs(u.goals)do if dist(p,g)<K.maxRadius+K.radius(u.entity)+.4 then okay=false end end end
   if okay then candidates[#candidates+1]=p end
  end
 end end
 self.bays={}
 local function bayCompatible(p)
  for _,b in ipairs(self.bays)do
   if dist(p,b)<K.maxRadius*2+.35 or segmentDistance(p,anchor,b)<K.maxRadius*2+.25 or segmentDistance(b,anchor,p)<K.maxRadius*2+.25 then return false end
  end;return true
 end
 -- Prefer nearby independent rays; all pairs still clear each other.
 table.sort(candidates,function(a,b)return dist(a,anchor)<dist(b,anchor)end)
 for _,p in ipairs(candidates)do if bayCompatible(p)then self.bays[#self.bays+1]=p;if #self.bays==#self.units then break end end end
 if #self.bays<#self.units then fail('not enough independently swept tissue holding bays');return self end
 self.blood,self.tissue=blood,tissue
 local issue
 issue=function(u,target,label,done)
  local e=u.entity
  local tissuePoint=u.side=='blood'and u.goals[1]or u.goals[2]
  if label:sub(1,4)~='via-' and ((e.vesselLane>0 and target.lane==0 and dist(target,tissuePoint)>.1)or(e.vesselLane==0 and target.lane>0 and dist(e,tissuePoint)>.1))then
   issue(u,tissuePoint,'via-original-tissue-endpoint',function()issue(u,target,'via-'..label,done)end);return
  end
  if not legal(u,target)then fail('illegal traffic target: '..label);return end
  precise[u.entity]=true
  self.motion={unit=u,target=copy(target),label=label,done=done,started=self.now,pendingTime=0,lastTick=self.now,lastProgress=self.now,last={x=u.entity.x,y=u.entity.y},replans=0}
  C.execute(s,{kind='move',faction=u.entity.faction,ids={u.entity.id},x=target.x,y=target.y})
  u.entity.orders[1].vesselLane=target.lane;self.motion.order=u.entity.orders[1];self.motion.token=u.entity.orderToken
  event('move',{unit=u.entity.id,label=label,target=copy(target)})
 end
 local function enqueue(u)
  if u.cancelled or not alive(u)then return nil end
  self.sequence=self.sequence+1
  local ticket={sequence=self.sequence,unit=u,enqueued=self.now,stage=1,status='queued'}
  self.queue[#self.queue+1]=ticket;event('queued',{ticket=ticket.sequence,unit=u.entity.id});return ticket
 end
 self.enqueue=enqueue
 local function release(ticket,status)
  if throat(ticket.unit.entity)then fail('attempted release inside original membrane wall');return end
  ticket.status=status;event(status,{ticket=ticket.sequence,unit=ticket.unit.entity.id,clear=true,wait=ticket.admitted-ticket.enqueued})
  self.owner=nil;table.remove(self.queue,1)
  if status=='deferred'then enqueue(ticket.unit)elseif status=='completed'then self.completedTickets=self.completedTickets+1 else ticket.unit.cancelled=true end
 end
 local function perform(ticket)
  local u=ticket.unit
  if ticket.cancelRequested then issue(u,u.bay,'cancel-withdraw',function()release(ticket,ticket.retry and 'deferred' or 'cancelled')end);return end
  if ticket.stage<=2 then
   local stage=ticket.stage
   issue(u,u.goals[stage],'original-goal-'..stage,function()
    u.originalStages=math.max(u.originalStages,stage);event('original-goal',{unit=u.entity.id,stage=stage,target=copy(u.goals[stage])})
    ticket.stage=stage+1;perform(ticket)
   end)
  else issue(u,u.bay,'clear-to-tissue-buffer',function()release(ticket,'completed')end)end
 end
 function self:cancelActive(retry)
  local ticket=self.owner;if not ticket or ticket.cancelRequested then return false end
  ticket.cancelRequested=true;ticket.retry=retry==true;event('cancel-requested',{ticket=ticket.sequence,unit=ticket.unit.entity.id,inThroat=throat(ticket.unit.entity)})
  perform(ticket);return true
 end
 function self:cancelQueued(sequence,retry)
  for i,ticket in ipairs(self.queue)do if ticket.sequence==sequence and ticket~=self.owner then
   ticket.status='cancelled';table.remove(self.queue,i);event('cancelled-queued',{ticket=sequence,unit=ticket.unit.entity.id});if retry then enqueue(ticket.unit)else ticket.unit.cancelled=true;C.execute(s,{kind='stop',faction=ticket.unit.entity.faction,ids={ticket.unit.entity.id}});precise[ticket.unit.entity]=ticket.unit.previousPrecision end;return true
  end end;return false
 end
 function self:tick(now)
  self.now=now
  if self.state=='failed'or self.state=='complete'then return end
  -- Removed/dead bodies no longer own exclusion. Living cancellation withdraws first.
  for i=#self.queue,1,-1 do local ticket=self.queue[i] --[[@as any]]
   if not alive(ticket.unit)then
   precise[ticket.unit.entity]=ticket.unit.previousPrecision;event('removed',{unit=ticket.unit.entity.id,ticket=ticket.sequence});ticket.unit.cancelled=true
   if self.owner==ticket then self.owner=nil end
   if self.motion and self.motion.unit==ticket.unit then self.motion=nil end
   table.remove(self.queue,i)
  end end
  if self.motion and not alive(self.motion.unit)then self.motion.unit.cancelled=true;precise[self.motion.unit.entity]=self.motion.unit.previousPrecision;self.motion=nil end
  if self.motion then
   local m=self.motion;local e=m.unit.entity
   if not e.orders or e.orders[1]~=m.order then fail('traffic move replaced by external command');return end
   m.token=e.orderToken
   if dist(e,m.target)<.07 and e.vesselLane==m.target.lane then
    C.execute(s,{kind='stop',faction=e.faction,ids={e.id}});precise[e]=m.unit.previousPrecision;self.motion=nil;m.done();return
   end
   if dist(e,m.last)>.02 then m.last={x=e.x,y=e.y};m.lastProgress=now end
   if e.pathFailed then fail('actual navigation failed during '..m.label);return end
   if e.pathPending then m.pendingTime=m.pendingTime+math.max(0,now-m.lastTick)end;m.lastTick=now
   if now-m.started-m.pendingTime>90 then fail('motion timeout during '..m.label);return end
   if now-m.lastProgress>3 and not e.pathPending then
    if m.replans>=2 then fail('traffic motion stalled during '..m.label);return end
    m.replans=m.replans+1;m.lastProgress=now
    C.execute(s,{kind='move',faction=e.faction,ids={e.id},x=m.target.x,y=m.target.y});e.orders[1].vesselLane=m.target.lane;m.order=e.orders[1];m.token=e.orderToken
    event('replan',{unit=e.id,label=m.label,count=m.replans})
   end
   return
  end
  if self.state=='prepare-tissue'then
   local bestU,bestB,bestScore=nil,nil,math.huge
   for _,u in ipairs(tissue)do if alive(u)and not u.cancelled and not u.bay then for _,b in ipairs(self.bays)do if not b.assigned then
    local from={x=u.entity.x,y=u.entity.y,lane=0}
    if swept(u,from,b)and freeSegment(u,from,b)then local score=dist(from,b);if score<bestScore then bestU,bestB,bestScore=u,b,score end end
   end end end end
   if not bestU then
    for _,u in ipairs(tissue)do if alive(u)and not u.cancelled and not u.bay then for _,b in ipairs(self.bays)do if not b.assigned then
     local from={x=u.entity.x,y=u.entity.y,lane=0}
     if freeSegment(u,from,b)then local score=dist(from,b);if score<bestScore then bestU,bestB,bestScore=u,b,score end end
    end end end end
   end
   if bestU then
    bestB.assigned=bestU.entity.id;bestU.bay=copy(bestB)
    issue(bestU,bestU.bay,'initial-tissue-holding',function()self.tissuePrepared[bestU.entity.id]=true end);return
   end
   for _,u in ipairs(tissue)do if alive(u)and not u.cancelled and not u.bay then fail('no collision-free initial tissue evacuation ray');return end end
   for _,u in ipairs(blood)do for _,b in ipairs(self.bays)do if not b.assigned then b.assigned=u.entity.id;u.bay=copy(b);break end end end
   self.state='prepare-blood';return
  end
  if self.state=='prepare-blood'then
   for _,u in ipairs(blood)do if alive(u)and not u.cancelled and not self.bloodPrepared[u.entity.id]then
    issue(u,u.bloodHolding,'initial-blood-holding',function()self.bloodPrepared[u.entity.id]=true end);return
   end end
   -- Simultaneous initial requests use physical near-to-far order as a stable
   -- tie break; once enqueued, sequence order is strictly FIFO without bypass.
   for i=#blood,1,-1 do enqueue(blood[i])end
   for _,u in ipairs(tissue)do enqueue(u)end
   self.state='service';return
  end
  if self.state=='service'then
   local ticket=self.queue[1]
   if not ticket then self.state='restore-blood';self.restoreIndex=1;return end
   if now-ticket.enqueued>300 then fail('FIFO wait budget exceeded');return end
   ticket.status='admitted';ticket.admitted=now;self.maxWait=math.max(self.maxWait,now-ticket.enqueued);self.owner=ticket
   event('admitted',{ticket=ticket.sequence,unit=ticket.unit.entity.id,wait=now-ticket.enqueued})
   perform(ticket);return
  end
  if self.state=='restore-blood'then
   local u=blood[self.restoreIndex]
   if u and (u.cancelled or not alive(u))then self.restoreIndex=self.restoreIndex+1;return end
   if u then issue(u,u.goals[2],'final-blood-placement',function()self.restoreIndex=self.restoreIndex+1 end);return end
   table.sort(tissue,function(a,b)return dist(a.goals[2],gate)>dist(b.goals[2],gate)end)
   self.state='restore-tissue';self.restoreIndex=1;return
  end
  if self.state=='restore-tissue'then
   local u=tissue[self.restoreIndex]
   if u and (u.cancelled or not alive(u))then self.restoreIndex=self.restoreIndex+1;return end
   if u then issue(u,u.goals[2],'final-tissue-placement',function()self.restoreIndex=self.restoreIndex+1 end);return end
   for _,v in ipairs(self.units)do if not v.cancelled and alive(v)and (dist(v.entity,v.goals[2])>=.07 or v.entity.vesselLane~=v.goals[2].lane) then fail('final exact target not restored');return end end
   self.state='complete';event('all-original-goals-restored',{});return
  end
 end
 return self
end
return T
