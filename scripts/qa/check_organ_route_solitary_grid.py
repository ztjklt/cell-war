"""Frozen left-lung solitary controls with the opt-in exact-grid connector."""
from pathlib import Path
import json,hashlib,os
from lupa.lua54 import LuaRuntime
from check_stomach_connectivity import lua,convert
ROOT=Path(__file__).resolve().parents[2];os.chdir(ROOT)
DOC=ROOT/'docs/body-life/vascular-art-study';OUT=DOC/'organ-route-crowd-evidence'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
crowd=json.loads((OUT/'report.json').read_text());assert crowd['sourceStable']
for f,h in crowd['sourceHashesAfter'].items():assert sha(ROOT/f)==h,'crowd source changed: '+f
contract=json.loads((DOC/'interface-contract.json').read_text());data=json.loads((DOC/'passages-data.json').read_text());layers=json.loads((DOC/'organ-layers.json').read_text())
regions={r['id']:r for r in contract['regions']};fixtures=[]
for scenario in crowd['scenarios']:
 for unit in scenario['units']:
  if scenario['id']=='lung_l' and not unit['pass']:
   fixtures.append(dict(scenario=scenario['id'],zone=scenario['zone'],name=scenario['name'],kind=unit['kind'],side=unit['side'],start=unit['start'],goals=unit['goals'],originalUnitId=unit['endState']['id'],gate=next(p for p in regions[scenario['id']]['ports'] if p.get('exitToTissue')),crowdCompletedStages=unit['completedStages']))
paths=[ROOT/f for f in crowd['sourceHashesAfter']]+[Path(__file__),ROOT/'scripts/war/OrganRouteGridConnectorStudy.lua',OUT/'report.json',OUT/'solitary-control.json']
before={str(p.relative_to(ROOT)):sha(p) for p in paths}
r=LuaRuntime(unpack_returned_tuples=True);r.execute("package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={};print=function()end;package.loaded['war.ReferenceVessels']=require('war.StomachConnectivityStudy')")
r.execute('qaData='+lua(data)+';qaLayers='+lua(layers)+';qaFixtures='+lua(fixtures));r.globals().progress=lambda s:print(s,flush=True)
result=convert(r.execute(r'''
local W,P,C,K=require('war.World'),require('war.Path'),require('war.Commands'),require('war.CellCollision')
local Worker=require('war.Workers');local L=require('war.StomachConnectivityStudy')
local M,N=require('war.OrganRouteCollisionStudy'),require('war.OrganRouteNavigationStudy')
local s=W.generate(73,nil,nil,nil,4);W.rebuild(s);local net=W.vessels(s);local context={radius=0};local model=M.prepare(qaData)
local unRadius=M.attachForTest(model,context,net,W);local raw=P.clear;local unNav,stats=N.attachForTest(P,C,W)
local unGrid,gridStats=require('war.OrganRouteGridConnectorStudy').attachForTest(P,C,W)
local out={tests={},adapterStats=stats,gridConnectorStats=gridStats}
local function gridClear(p)return raw(s,math.floor(p.x)+.5,math.floor(p.y)+.5,math.floor(p.x)+.5,math.floor(p.y)+.5,1,p.lane,p.lane)end
local function point(p)return {x=p[1],y=p[2]}end
for _,f in ipairs(qaFixtures)do
 local cpuStart=os.clock();P.reset();s.entities={};s.nextId=f.originalUnitId;W.rebuild(s)
 context.zone=f.zone;context.radius=K.radius(f.kind);context.tissueEdges={}
 for _,z in ipairs(qaLayers.zones)do if z.id==f.zone then for _,id in ipairs(z.tissueWallEdges)do context.tissueEdges[assert(L.edgeIndexById[id])]=true end;for _,id in ipairs(z.extraStudyEdges)do context.tissueEdges[assert(L.edgeIndexById[id])]=true end end end
 local t={id=f.scenario..'.'..f.side..'.'..f.kind,scenario=f.scenario,zone=f.zone,kind=f.kind,side=f.side,originalUnitId=f.originalUnitId,start=f.start,goals=f.goals,radiusWorld=context.radius,crowdCompletedStages=f.crowdCompletedStages,pass=false,completedStages=0,stages={},trace={},cpuBudgetSeconds=10,timeoutSeconds=90,invalidNetSteps=0,radiusViolations=0,maxQueuedJobs=0}
 t.exactStartLegal=not not (M.allowed(model,context,net,f.start.x,f.start.y,f.start.lane)and raw(s,f.start.x,f.start.y,f.start.x,f.start.y,1,f.start.lane,f.start.lane));t.gridStartLegal=not not gridClear(f.start)
 t.directFirstGoalClear=not not raw(s,f.start.x,f.start.y,f.goals[1].x,f.goals[1].y,1,f.start.lane,f.goals[1].lane)
 -- Diagnostic only: assess explicit old gate anchors without adding waypoints to
 -- the actual control order. Every start/goal remains byte-identical to crowd.
 local inside=point(f.gate.insideWorld);inside.lane=L.edgeIndexById[f.gate.edge];local outside=point(f.gate.outsideWorld);outside.lane=0
 local via=f.side=='blood' and {f.start,inside,outside,f.goals[1]} or {f.start,outside,inside,f.goals[1]}
 t.originalGateSegments={};t.originalGatePolylineClear=true
 for n=2,#via do local a,b=via[n-1],via[n];local ok=not not raw(s,a.x,a.y,b.x,b.y,1,a.lane,b.lane);t.originalGateSegments[#t.originalGateSegments+1]={from=a,to=b,clear=ok};if not ok then t.originalGatePolylineClear=false end end
 local e=C.spawn(s,'unit',f.kind,1,f.start.x,f.start.y,true)
 if not e or math.abs(e.x-f.start.x)>1e-8 or math.abs(e.y-f.start.y)>1e-8 then t.reason='SPAWN_REJECTED_OR_RELOCATED'
 else
  assert(e.id==f.originalUnitId);e.vesselLane=f.start.lane;W.rebuild(s);t.trace={{t=0,x=e.x,y=e.y,lane=e.vesselLane,stage=1}};local elapsed=0
  for index,g in ipairs(f.goals)do
   local stage={index=index,from={x=e.x,y=e.y,lane=e.vesselLane},goal=g,arrived=false,gridGoalLegal=not not gridClear(g),exactGoalLegal=not not (M.allowed(model,context,net,g.x,g.y,g.lane)and raw(s,g.x,g.y,g.x,g.y,1,g.lane,g.lane))}
   C.execute(s,{kind='move',faction=1,ids={e.id},x=g.x,y=g.y});e.orders[1].vesselLane=g.lane
   for frame=1,1800 do
    if os.clock()-cpuStart>10 then t.reason='CPU_BUDGET_EXCEEDED';t.cpuBudgetExceeded=true;break end
    if elapsed>=90 then t.reason='SIMULATION_TIMEOUT';break end
    local x,y,lane=e.x,e.y,e.vesselLane;s.time=s.time+.05;elapsed=elapsed+.05
    P.update(s,500,.003);t.maxQueuedJobs=math.max(t.maxQueuedJobs,#P.jobs)
    Worker.update(s,e,.05);W.rebuild(s);K.resolve(s);W.rebuild(s)
    if not raw(s,x,y,e.x,e.y,1,lane,e.vesselLane)then t.invalidNetSteps=t.invalidNetSteps+1 end
    if not M.allowed(model,context,net,e.x,e.y,e.vesselLane)then t.radiusViolations=t.radiusViolations+1 end
    if frame%10==0 or lane~=e.vesselLane then t.trace[#t.trace+1]={t=elapsed,x=e.x,y=e.y,lane=e.vesselLane,stage=index}end
    if (e.x-g.x)^2+(e.y-g.y)^2<.8*.8 and e.vesselLane==g.lane then stage.arrived=true;t.completedStages=t.completedStages+1;break end
    if e.pathFailed then t.reason='ACTUAL_ASTAR_FAILED';break end
   end
   stage.endSource={e.x/2,(e.y-512)/2};stage.seconds=elapsed;t.stages[#t.stages+1]=stage
   if not stage.arrived then break end
  end
  t.seconds=elapsed;t.endQueuedJobs=#P.jobs;t.endState={x=e.x,y=e.y,lane=e.vesselLane,pathFailed=e.pathFailed or false,pathPending=e.pathPending or false}
  t.trace[#t.trace+1]={t=elapsed,x=e.x,y=e.y,lane=e.vesselLane,stage=#t.stages}
  t.pass=t.completedStages==#f.goals and t.invalidNetSteps==0 and t.radiusViolations==0
  if not t.pass and not t.reason then t.reason='NET_STEP_RECHECK_OR_RADIUS_FAILURE'end
 end
 t.cpuSeconds=os.clock()-cpuStart;out.tests[#out.tests+1]=t
 progress(t.id..' pass='..tostring(t.pass)..' stages='..t.completedStages..' cpu='..string.format('%.3f',t.cpuSeconds)..' '..(t.reason or '')..' direct='..tostring(t.directFirstGoalClear)..' viaGate='..tostring(t.originalGatePolylineClear))
end
unGrid();unNav();unRadius();return out
'''))
after={str(p.relative_to(ROOT)):sha(p) for p in paths}
result.update(scope='Exact two failed left-lung mixed-crowd unit starts/goals tested individually with opt-in grid connector installed after navigation; zero neighbors; original IDs, coordinates, kinds and lanes preserved',sourceHashesBefore=before,sourceHashesAfter=after,sourceStable=before==after,productionInstalled=False,nativeEvidence=False,qaScriptSha256=sha(Path(__file__)),fixtureCount=len(fixtures),runtimePlanner={'expansions':500,'seconds':.003},limitations=['Only the same two failed left-lung crowd units selected, not all 42 units.','10 CPU seconds per unit and 90 simulated seconds for both stages combined. CPU exceeded is unconfirmed, not evidence of disconnected topology.','Original gate polyline is a read-only geometric diagnostic, not a modified control order or actual movement acceptance.','Planner deadline depends on offline CPU; this is not a native frame benchmark.','Whole-frame raw Path.clear checks endpoint chord, which can be stricter than collision slide substeps.'])
result['summary']={'tests':len(result['tests']),'passed':sum(t['pass'] for t in result['tests']),'cpuUnconfirmed':sum(bool(t.get('cpuBudgetExceeded')) for t in result['tests']),'actualAStarFailed':sum(t.get('reason')=='ACTUAL_ASTAR_FAILED' for t in result['tests']),'simulationTimeouts':sum(t.get('reason')=='SIMULATION_TIMEOUT' for t in result['tests']),'netStepRejections':sum(t['invalidNetSteps'] for t in result['tests']),'radiusViolations':sum(t['radiusViolations'] for t in result['tests'])}
result['status']='STALE_SOURCE_DO_NOT_ACCEPT' if not result['sourceStable'] else 'SOLITARY_CONTROL_COMPLETE_WITH_RETAINED_FAILURES'
(OUT/'solitary-grid-control.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(result['status'],result['summary'])
