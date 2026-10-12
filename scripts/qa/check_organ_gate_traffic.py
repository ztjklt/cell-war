"""Opt-in six-cell gate batches. Frozen original crowd endpoints; real movement only."""
from pathlib import Path
import json,hashlib,os
from lupa.lua54 import LuaRuntime
from check_stomach_connectivity import lua,convert
R=Path(__file__).resolve().parents[2];os.chdir(R);D=R/'docs/body-life/vascular-art-study';O=D/'organ-gate-traffic-evidence';O.mkdir(exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
base=json.loads((D/'organ-route-crowd-evidence/report.json').read_text());contract=json.loads((D/'interface-contract.json').read_text());layers=json.loads((D/'organ-layers.json').read_text());data=json.loads((D/'passages-data.json').read_text())
fixtures=[]
for f in base['scenarios']:
 g=next(p for r in contract['regions'] if r['id']==f['id'] for p in r['ports'] if p.get('exitToTissue'))
 z=next(z for z in layers['zones'] if z['id']==f['zone'])
 fixtures.append(dict(id=f['id'],zone=f['zone'],gate=g,units=[dict(kind=u['kind'],side=u['side'],start=u['start'],goals=u['goals'])for u in f['units']],tissueEdgeIds=z['tissueWallEdges']+z['extraStudyEdges']))
selection=os.environ.get('QA_REGIONS');fixtures=[f for f in fixtures if not selection or f['id'] in selection.split(',')]
files=[Path(__file__),*[R/'scripts/war'/p for p in ['OrganGateTrafficStudy.lua','OrganAccessStudy.lua','BodyRegionAccessStudy.lua','StomachConnectivityStudy.lua','OrganSortieNavigationStudy.lua','OrganRouteNavigationStudy.lua','OrganRouteCollisionStudy.lua','TissueGeometry.lua','PassageCollisionStudy.lua','World.lua','Commands.lua','CellCollision.lua','Workers.lua']],*[D/p for p in ['organ-route-crowd-evidence/report.json','interface-contract.json','organ-layers.json','passages-data.json']]]
before={str(p.relative_to(R)):sha(p)for p in files}
l=LuaRuntime(unpack_returned_tuples=True);l.execute("package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={};print=function()end;package.loaded['war.ReferenceVessels']=require('war.BodyRegionAccessStudy').create(require('war.OrganAccessStudy').create(require('war.StomachConnectivityStudy')))")
l.execute('qaData='+lua(data)+';qaFixtures='+lua(fixtures)+';qaProtocol='+lua(os.environ.get('QA_PROTOCOL','')));l.globals().progress=lambda s:print(s,flush=True)
out=convert(l.execute(r'''
local W,P,C,K=require('war.World'),require('war.Path'),require('war.Commands'),require('war.CellCollision')
local Workers=require('war.Workers');local L=require('war.StomachConnectivityStudy');local Base=require('war.PassageCollisionStudy');local M=require('war.OrganRouteCollisionStudy');local N=require('war.OrganSortieNavigationStudy');local T=require('war.OrganGateTrafficStudy')
local s=W.generate(73,nil,nil,nil,4);W.rebuild(s);local net=W.vessels(s);local context={radius=0};local model=M.prepare(qaData)
local ug=require('war.TissueGeometry').attachForTest(Base,M,model);local ur=M.attachForTest(model,context,net,W);local raw=P.clear
local function unitContext(e)context.radius=K.radius(e.kind);context.zone=e.sortieZone;context.tissueEdges=e.sortieEdges end
local geo={activate=function(st,e)unitContext(e)end,pointAllowed=function(st,e,x,y,lane)unitContext(e);return M.allowed(model,context,net,x,y,lane)end,sweep=function(st,e,x,y,tx,ty,lane,desired)unitContext(e);return raw(st,x,y,tx,ty,e.faction,lane,desired)end,
 bounds=function(st,e)local b={minX=math.huge,minY=math.huge,maxX=-math.huge,maxY=-math.huge};for _,r in ipairs(model.zones[e.sortieZone].outlines)do for _,p in ipairs(r.points)do b.minX=math.min(b.minX,p[1]*2);b.maxX=math.max(b.maxX,p[1]*2);b.minY=math.min(b.minY,p[2]*2+512);b.maxY=math.max(b.maxY,p[2]*2+512)end end;return b end,
 portals=function(st,e)local list={};for _,g in ipairs(net.gates)do if e.sortieEdges[g.edge]then list[#list+1]=g end end;return list end}
local un,stats=N.attachForTest(P,C,W,geo,{frameSeconds=.003,cpuBudgetSeconds=10,nodeBudget=180000});local up=T.attachPrecision(C)
local Motion=require('war.Motion');local originalRecord=Motion.record;local segments={};Motion.record=function(e)segments[#segments+1]={e=e,x=e.x,y=e.y,lane=e.vesselLane};return originalRecord(e)end
local result={cases={},navigationStats=stats};local find=K.find;local findCalls=0;K.find=function(...)findCalls=findCalls+1;return find(...)end
for _,f in ipairs(qaFixtures)do
 P.reset();s.entities={};s.nextId=1;W.rebuild(s);local edges={};for _,id in ipairs(f.tissueEdgeIds)do edges[assert(L.edgeIndexById[id])]=true end
 local lane=L.edgeIndexById[f.gate.edge];local gate;for _,g in ipairs(net.gates)do if g.edge==lane and (g.px-f.gate.insideWorld[1])^2+(g.py-f.gate.insideWorld[2])^2<4 then gate=g;break end end;assert(gate,'original gate missing')
 local r={protocol=qaProtocol,id=f.id,zone=f.zone,units=f.units,trace={},overlaps=0,illegalSubsteps=0,radiusViolations=0,frameChordRejections=0,pass=false,cpuBudgetSeconds=45};local list={}
 for _,u in ipairs(f.units)do context.zone=f.zone;context.tissueEdges=edges;context.radius=K.radius(u.kind)
  local e=assert(C.spawn(s,'unit',u.kind,1,u.start.x,u.start.y,true));assert(math.abs(e.x-u.start.x)<1e-9 and math.abs(e.y-u.start.y)<1e-9,'spawn relocated');e.vesselLane=u.start.lane;e.sortieZone=f.zone;e.sortieEdges=edges;u.entity=e;list[#list+1]=e;W.rebuild(s)
 end
 findCalls=0;local started=os.clock();local control=T.create{state=s,W=W,P=P,C=C,K=K,net=net,geometry=geo,gate=gate,outside={x=f.gate.outsideWorld[1],y=f.gate.outsideWorld[2],lane=0},units=f.units}
 local faultMode=qaProtocol:sub(1,6)=='fault-';local faultEntity;local timeline={};r.latency={planningSeconds=0,movingSeconds=0,idleSeconds=0}
 local protocol={cancelled={},removed={},liveThroatHeld=false};r.protocolEvidence=protocol
 local function pairsCheck()for a=1,#list do for b=a+1,#list do local e,v=list[a],list[b];local margin=math.sqrt((e.x-v.x)^2+(e.y-v.y)^2)-K.radius(e)-K.radius(v)-K.gap;if margin < -1e-5 then r.overlaps=r.overlaps+1 end end end end
 local function trace(t)local q={t=t,state=control.state,units={}};for _,e in ipairs(list)do q.units[#q.units+1]={id=e.id,x=e.x,y=e.y,lane=e.vesselLane}end;r.trace[#r.trace+1]=q end
 trace(0)
 for frame=1,10000 do
  r.seconds=frame*.05;s.time=s.time+.05
  if faultMode and control.owner and not protocol.faultTime and control.inThroat(control.owner.unit.entity)then
   faultEntity=control.owner.unit.entity;protocol.faultTime=r.seconds;protocol.faultStart={x=faultEntity.x,y=faultEntity.y};protocol.tokenBefore=faultEntity.orderToken
   if qaProtocol=='fault-foreign'then
    local target=control.owner.unit.bloodHolding;C.execute(s,{kind='move',faction=1,ids={faultEntity.id},x=target.x,y=target.y});faultEntity.orders[1].vesselLane=target.lane;protocol.foreignToken=faultEntity.orderToken
   end
   control:abort('injected failure for ownership cleanup verification')
   protocol.orderPreserved=qaProtocol=='fault-foreign'and faultEntity.orderToken==protocol.foreignToken and #faultEntity.orders==1
   protocol.ownedStopped=qaProtocol=='fault-owned'and #faultEntity.orders==0 and not faultEntity.pathPending
  end
  if qaProtocol~='' and not faultMode and control.state=='service' then
   if not protocol.queuedCancel and #control.queue>=6 then
    local ticket=control.queue[6];protocol.queuedCancel=ticket.unit.entity.id;protocol.cancelled[tostring(ticket.unit.entity.id)]=true;control:cancelQueued(ticket.sequence)
    ticket=control.queue[5];protocol.removed[tostring(ticket.unit.entity.id)]=true;s.entities[ticket.unit.entity.id]=nil
    for i=#list,1,-1 do if list[i].id==ticket.unit.entity.id then table.remove(list,i)end end;W.rebuild(s)
   end
   if qaProtocol=='active-delete'and control.owner and not protocol.activeRemoved and control.inThroat(control.owner.unit.entity)then
    local id=control.owner.unit.entity.id;protocol.activeRemoved=id;protocol.removed[tostring(id)]=true;s.entities[id]=nil
    for i=#list,1,-1 do if list[i].id==id then table.remove(list,i)end end;W.rebuild(s)
   elseif control.owner and not protocol.activeCancel and control.inThroat(control.owner.unit.entity)then
    local id=control.owner.unit.entity.id;protocol.activeCancel=id;protocol.cancelled[tostring(id)]=true;control:cancelActive();protocol.liveThroatHeld=control.owner~=nil
   end
  end
  control:tick(r.seconds)
  if control.state=='complete'or(control.state=='failed'and not faultMode)or(faultMode and protocol.faultTime and r.seconds-protocol.faultTime>=10)then break end
  if os.clock()-started>r.cpuBudgetSeconds then r.reason='CPU_BUDGET_EXCEEDED';break end
  local pending=control.motion and control.motion.unit.entity.pathPending;local frameMoved=false
  P.update(s,500,.003)
  for _,e in ipairs(list)do
   unitContext(e);local x,y,lane0=e.x,e.y,e.vesselLane;segments={};Workers.update(s,e,.05);W.rebuild(s)
   if (e.x-x)^2+(e.y-y)^2>1e-12 then frameMoved=true end
   local ax,ay,al=x,y,lane0
   for _,p in ipairs(segments)do
    if not geo.sweep(s,e,ax,ay,p.x,p.y,al,p.lane)then r.illegalSubsteps=r.illegalSubsteps+1;if not r.firstIllegal then r.firstIllegal={from={ax,ay,al},to={p.x,p.y,p.lane},unit=e.id,time=r.seconds}end end
    ax,ay,al=p.x,p.y,p.lane
   end
   if not geo.sweep(s,e,x,y,e.x,e.y,lane0,e.vesselLane)then r.frameChordRejections=r.frameChordRejections+1 end
   if not geo.pointAllowed(s,e,e.x,e.y,e.vesselLane)then r.radiusViolations=r.radiusViolations+1 end
   pairsCheck()
  end
  local resolveBefore={};for _,e in ipairs(list)do resolveBefore[e.id]={e.x,e.y,e.vesselLane}end
  local normal=P.clear;P.clear=function(st,x,y,tx,ty,faction,lane0,...)local found;for _,e in ipairs(list)do if math.abs(x-e.x)<1e-8 and math.abs(y-e.y)<1e-8 then found=e;break end end;if found then unitContext(found)else context.radius=K.maxRadius end;return normal(st,x,y,tx,ty,faction,lane0,...)end
  K.resolve(s,list);P.clear=normal;W.rebuild(s);pairsCheck();for _,e in ipairs(list)do local a=resolveBefore[e.id];if not geo.sweep(s,e,a[1],a[2],e.x,e.y,a[3],e.vesselLane)then r.illegalSubsteps=r.illegalSubsteps+1 end end
  for _,e in ipairs(list)do if not geo.pointAllowed(s,e,e.x,e.y,e.vesselLane)then r.radiusViolations=r.radiusViolations+1 end end
  local category=frameMoved and 'movingSeconds'or pending and 'planningSeconds'or 'idleSeconds';r.latency[category]=r.latency[category]+.05;timeline[frame]={planningSeconds=r.latency.planningSeconds,movingSeconds=r.latency.movingSeconds,idleSeconds=r.latency.idleSeconds}
  if frame%10==0 then trace(r.seconds)end
 end
 r.waitBreakdown={};local queuedAt={};for _,ev in ipairs(control.events)do
  if ev.kind=='queued'then queuedAt[ev.ticket]=ev.t end
  if ev.kind=='admitted'then local first=timeline[math.max(1,math.floor(queuedAt[ev.ticket]/.05+.5))]or{planningSeconds=0,movingSeconds=0,idleSeconds=0};local last=timeline[math.max(1,math.floor(ev.t/.05+.5))]or first;local q={ticket=ev.ticket,unit=ev.unit,seconds=ev.wait};for k,v in pairs(last)do q[k]=v-first[k]end;r.waitBreakdown[#r.waitBreakdown+1]=q end
 end
 if faultMode and faultEntity then protocol.movedAfterFault=math.sqrt((faultEntity.x-protocol.faultStart.x)^2+(faultEntity.y-protocol.faultStart.y)^2);protocol.motionCleared=control.motion==nil;protocol.queueCleared=#control.queue==0;protocol.ownerCleared=control.owner==nil;protocol.pass=protocol.motionCleared and protocol.queueCleared and protocol.ownerCleared and (qaProtocol=='fault-owned'and protocol.ownedStopped and protocol.movedAfterFault<1e-8 or qaProtocol=='fault-foreign'and protocol.orderPreserved and protocol.movedAfterFault>.5)end
 r.fallbackFindCalls=findCalls;findCalls=0;r.precisionLeaks=0;for _,u in ipairs(f.units)do if T.isPrecise(u.entity)then r.precisionLeaks=r.precisionLeaks+1 end end;r.reason=r.reason or control.reason;r.state=control.state;r.events=control.events;r.maxWait=control.maxWait;r.cpuSeconds=os.clock()-started;r.unitsReturned=0;r.stagesPassed=0
 for _,u in ipairs(f.units)do local e=u.entity;u.endState={id=e.id,x=e.x,y=e.y,lane=e.vesselLane,diagnostics=N.diagnostics(e),path=e.path,pathIndex=e.pathIndex,pathPending=e.pathPending};u.pass=u.originalStages==2 and (e.x-u.goals[2].x)^2+(e.y-u.goals[2].y)^2<.07^2 and e.vesselLane==u.goals[2].lane;u.entity=nil;r.stagesPassed=r.stagesPassed+u.originalStages;if (e.x-u.goals[2].x)^2+(e.y-u.goals[2].y)^2<.07^2 and e.vesselLane==u.goals[2].lane and u.originalStages==2 then r.unitsReturned=r.unitsReturned+1 end end
 trace(r.seconds);r.fifo=true;local previousTicket=0;for _,event in ipairs(control.events)do if event.kind=='admitted'then if event.ticket<=previousTicket then r.fifo=false end;previousTicket=event.ticket end end;r.expectedReturned=6;if qaProtocol~=''and not faultMode then for _ in pairs(protocol.cancelled)do r.expectedReturned=r.expectedReturned-1 end;for _ in pairs(protocol.removed)do r.expectedReturned=r.expectedReturned-1 end;protocol.noRequeuedCancelled=true;for _,event in ipairs(control.events)do if event.kind=='queued'and protocol.cancelled[tostring(event.unit)]and event.ticket>6 then protocol.noRequeuedCancelled=false end end;protocol.queueCleared=#control.queue==0;protocol.ownerCleared=control.owner==nil;protocol.pass=protocol.activeCancel~=nil and protocol.queuedCancel~=nil and protocol.liveThroatHeld and protocol.noRequeuedCancelled and control.owner==nil and #control.queue==0 end
 local safety=r.precisionLeaks==0 and r.fallbackFindCalls==0 and r.overlaps==0 and r.illegalSubsteps==0 and r.radiusViolations==0
 r.pass=r.fifo and control.maxWait<=300 and control.state=='complete'and r.unitsReturned==r.expectedReturned and (qaProtocol==''or protocol.pass) and r.precisionLeaks==0 and r.fallbackFindCalls==0 and r.overlaps==0 and r.illegalSubsteps==0 and r.radiusViolations==0;if faultMode then r.pass=protocol.pass and safety end;result.cases[#result.cases+1]=r;progress(f.id..' '..tostring(r.pass)..' '..control.state..' '..tostring(r.reason)..' returned='..r.unitsReturned..' stages='..r.stagesPassed..' overlap='..r.overlaps..' illegal='..r.illegalSubsteps)
end
K.find=find;Motion.record=originalRecord;up();un();ur();ug();return result
'''))
after={str(p.relative_to(R)):sha(p)for p in files};out.update(testedModuleHashes={p.name:before[str(p.relative_to(R))]for p in files if p.suffix=='.lua'},inputHashes={str(p.relative_to(D)):before[str(p.relative_to(R))]for p in files if p.suffix=='.json'},qaScriptSha256=before[str(Path(__file__).resolve().relative_to(R))],sourceHashesBefore=before,sourceHashesAfter=after,sourceStable=before==after,productionInstalled=False,nativeEvidence=False,budgetNote='45 CPU seconds per batch (baseline 30) includes additional actual staging and final restoration; unchanged 10 CPU seconds per navigation job, P.update 500/.003. Offline only.',scope='Isolated bounded six-cell original membrane batches; not arbitrary full-map crowd scheduling')
out['summary']={'cases':len(out['cases']),'casesPassed':sum(r['pass']for r in out['cases']),'unitsReturned':sum(r['unitsReturned']for r in out['cases']),'stagesPassed':sum(r['stagesPassed']for r in out['cases']),'overlaps':sum(r['overlaps']for r in out['cases']),'radiusViolations':sum(r['radiusViolations']for r in out['cases']),'illegalSubsteps':sum(r['illegalSubsteps']for r in out['cases'])}
out['status']='STALE_SOURCE'if not out['sourceStable']else 'PASS_SCOPED_BATCHES'if all(r['pass']for r in out['cases'])else 'RETAINED_FAILURES'
(O/('protocol-'+os.environ.get('QA_PROTOCOL','')+'.json'if os.environ.get('QA_PROTOCOL')else 'report.json')).write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n');print(out['status'],out['summary'])
if os.environ.get('QA_PROTOCOL'):
 protocol_files=[O/('protocol-'+mode+'.json')for mode in ['cancel-delete','active-delete','fault-owned','fault-foreign']]
 if all(p.exists() for p in protocol_files):
  reports=[json.loads(p.read_text())for p in protocol_files]
  combined=dict(out);combined['cases']=[c for report in reports for c in report['cases']]
  combined['sourceStable']=all(report['sourceStable'] and report['sourceHashesBefore']==before for report in reports)
  combined['summary']={'cases':len(combined['cases']),'casesPassed':sum(c['pass']for c in combined['cases'])}
  combined['status']='PASS_PROTOCOLS'if combined['sourceStable']and all(c['pass']for c in combined['cases'])else 'STALE_OR_FAILED_PROTOCOLS'
  (O/'protocol-report.json').write_text(json.dumps(combined,ensure_ascii=False,indent=2)+'\n')
