"""Independent scheduler and added-junction contract checks for the isolated planner."""
from pathlib import Path
import os,json,hashlib
from lupa.lua54 import LuaRuntime
from check_stomach_connectivity import lua,convert
R=Path(__file__).resolve().parents[2];os.chdir(R);D=R/'docs/body-life/vascular-art-study'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
files=['OrganSortieNavigationStudy.lua','OrganAccessStudy.lua','BodyRegionAccessStudy.lua','OrganRouteCollisionStudy.lua','TissueGeometry.lua']
hashes={f:sha(R/'scripts/war'/f) for f in files}
data=json.loads((D/'passages-data.json').read_text());layers=json.loads((D/'organ-layers.json').read_text());contract=json.loads((D/'interface-contract.json').read_text())
setup=r'''
package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={};print=function()end
local A=require('war.OrganAccessStudy');local L=require('war.BodyRegionAccessStudy').create(A.create(require('war.StomachConnectivityStudy')))
if not qaAdded then for i=#L.gates,1,-1 do if L.gates[i].name=='study.colon_distal.junction_access'then table.remove(L.gates,i)end end end
package.loaded['war.ReferenceVessels']=L
local W,P,C,K=require('war.World'),require('war.Path'),require('war.Commands'),require('war.CellCollision')
local Base,M=require('war.PassageCollisionStudy'),require('war.OrganRouteCollisionStudy')
local s=W.generate(73,nil,nil,nil,4);W.rebuild(s);local net=W.vessels(s);local ctx={radius=0};local model=M.prepare(qaData)
local ug=require('war.TissueGeometry').attachForTest(Base,M,model);local ur=M.attachForTest(model,ctx,net,W);local raw=P.clear
local function edges(zone)local out={};for _,z in ipairs(qaLayers.zones)do if z.id==zone then for _,id in ipairs(z.tissueWallEdges)do out[L.edgeIndexById[id]]=true end;for _,id in ipairs(z.extraStudyEdges)do out[L.edgeIndexById[id]]=true end end end;return out end
local function activate(st,e)ctx.radius=K.radius(e);ctx.zone=e.sortieZone;ctx.tissueEdges=e.sortieEdges end
local calls={};local geo={activate=activate,
 pointAllowed=function(st,e,x,y,lane)activate(st,e);calls[#calls+1]={kind=e.kind,zone=ctx.zone,radius=ctx.radius};return M.allowed(model,ctx,net,x,y,lane)end,
 sweep=function(st,e,x,y,tx,ty,lane,target)activate(st,e);return raw(st,x,y,tx,ty,e.faction,lane,target)end,
 bounds=function(st,e)local b={minX=math.huge,minY=math.huge,maxX=-math.huge,maxY=-math.huge};for _,o in ipairs(model.zones[e.sortieZone].outlines)do for _,p in ipairs(o.points)do b.minX=math.min(b.minX,p[1]*2);b.maxX=math.max(b.maxX,p[1]*2);b.minY=math.min(b.minY,p[2]*2+512);b.maxY=math.max(b.maxY,p[2]*2+512)end end;return b end,
 portals=function(st,e)local out={};for _,g in ipairs(net.gates)do if e.sortieEdges[g.edge]then out[#out+1]=g end end;return out end}
local N=require('war.OrganSortieNavigationStudy');local un,stats=N.attachForTest(P,C,W,geo,{frameSeconds=.003,cpuBudgetSeconds=15,nodeBudget=180000})
local function spawn(zone,kind,x,y,lane)local e=C.spawn(s,'unit',kind,1,x,y,true);assert(e and e.x==x and e.y==y);e.vesselLane=lane;e.sortieZone=zone;e.sortieEdges=edges(zone);W.rebuild(s);return e end
local function request(e,x,y,lane)C.execute(s,{kind='move',faction=1,ids={e.id},x=x,y=y});e.orders[1].vesselLane=lane;P.request(s,e,x,y)end
local function drain()for _=1,20000 do P.update(s,500,.003);local pending=false;for _,e in pairs(s.entities)do if e.pathPending then pending=true end end;if not pending then return end end;error('bounded scheduler did not drain')end
local function valid(e)local x,y,lane=e.x,e.y,e.vesselLane;for _,p in ipairs(e.path)do if not geo.sweep(s,e,x,y,p.x,p.y,lane,p.lane)then return false end;x,y,lane=p.x,p.y,p.lane end;return #e.path>0 and not e.pathFailed end
'''
def runtime(added,body):
 l=LuaRuntime(unpack_returned_tuples=True);l.execute('qaData='+lua(data)+';qaLayers='+lua(layers)+';qaAdded='+lua(added));return convert(l.execute(setup+body))
proof_body=r'''
local gate;for _,g in ipairs(net.gates)do if g.name=='colon_distal.tissue_access'then gate=g end end
local extra;for _,a in ipairs(A.additions)do if a.edgeId=='e191'then extra=a end end
local id=L.edgeIndexById.e191;local radius=K.radius('siege');local centerDistance=net.distance(id,gate.x,gate.y,true)
local eroded=gate.radius-radius-.02;local wall=net.edges[id].width/2+1.4+radius+.02
local result={oldGate=gate,addedSpec=extra,gateCount=#net.gates,edgeCount=#net.edges,proof={centerDistance=centerDistance,erodedApertureRadius=eroded,wallExclusionRadius=wall,coverageMargin=wall-centerDistance-eroded,wholeOldApertureBlockedWithoutE191Gate=wall>centerDistance+eroded},tests={}}
local x,y=1128.3431457505076,1838.3431457505076
for _,kind in ipairs({'scout','worker','siege'})do
 local e=spawn('large_intestine',kind,extra.x,extra.y,id)
 result.tests[#result.tests+1]={kind=kind,direction='outward',clear=geo.sweep(s,e,extra.x,extra.y,x,y,id,0)}
 result.tests[#result.tests+1]={kind=kind,direction='inward',clear=geo.sweep(s,e,x,y,extra.x,extra.y,0,id)}
 s.entities={};W.rebuild(s)
end
un();ur();ug();return result
'''
without=runtime(False,proof_body);with_gate=runtime(True,proof_body)
assert all(not t['clear'] for t in without['tests']),'missing-gate wall leaked'
assert all(t['clear'] for t in with_gate['tests']),'new declared gate failed a radius/direction'
assert without['proof']['wholeOldApertureBlockedWithoutE191Gate']
assert with_gate['oldGate']==without['oldGate']
scheduler=runtime(True,r'''
local a=spawn('liver','scout',897.4430379746835,1541.9746835443038,L.edgeIndexById.e118)
local b=spawn('bladder','siege',1048.2564102564102,2045.4358974358975,L.edgeIndexById.e143)
-- Two incompatible contexts are queued and resumed interleaved.
request(a,888,1540,0);request(b,1054,2046,0);drain()
local mixedPathsLegal=valid(a) and valid(b)
local firstCalls=#calls;local switches=0;for i=2,firstCalls do if calls[i].kind~=calls[i-1].kind then switches=switches+1 end end
local Motion=require('war.Motion');local savedRecord=Motion.record;local substeps,violations=0,0;local previous={}
Motion.record=function(e)local p=previous[e];if p then substeps=substeps+1;if not geo.sweep(s,e,p.x,p.y,e.x,e.y,p.lane,e.vesselLane)then violations=violations+1 end end;previous[e]={x=e.x,y=e.y,lane=e.vesselLane};return savedRecord(e)end
for frame=1,300 do s.time=s.time+.05;for _,e in ipairs({a,b})do previous[e]={x=e.x,y=e.y,lane=e.vesselLane};activate(s,e==a and b or a);C.go(s,e,e==a and 888 or 1054,e==a and 1540 or 2046,.05,.025)end;W.rebuild(s);P.update(s,500,.003)end
Motion.record=savedRecord
local mixedMovesLegal=substeps>0 and violations==0
local mixedArrivals=(a.x-888)^2+(a.y-1540)^2<.03^2 and a.vesselLane==0 and (b.x-1054)^2+(b.y-2046)^2<.03^2 and b.vesselLane==0
request(a,897.4430379746835,1541.9746835443038,L.edgeIndexById.e118);request(b,1048.2564102564102,2045.4358974358975,L.edgeIndexById.e143);local oldToken=a.orderToken
P.update(s,1,.000001)
request(a,a.x,a.y,a.vesselLane);local newToken=a.orderToken;drain()
local replacementGoalPreserved=a.pathGoal.x==a.x and a.pathGoal.y==a.y and a.orderToken==newToken and newToken~=oldToken
local replacementPathLegal=valid(a);local otherCompleted=not b.pathPending
-- Explicitly contaminate context before C.go; activate must select this unit.
activate(s,b);C.go(s,a,a.x,a.y,.05,.025)
local motionContextCorrect=ctx.zone=='liver' and ctx.radius==K.radius('scout')
local privateDiagnostics=a.sortieDiagnostics==nil and N.diagnostics(a)~=nil
request(a,888,1540,0);request(b,1054,2046,0);assert(a.pathPending and b.pathPending);P.reset()
local resetClearsBoth=not a.pathPending and not b.pathPending and #a.path==0 and #b.path==0 and N.diagnostics(a).reason=='CANCELLED_BY_RESET' and N.diagnostics(b).reason=='CANCELLED_BY_RESET'
local kinds={};local callsCorrect=true;for _,call in ipairs(calls)do kinds[call.kind]=true;if call.radius~=K.radius(call.kind)or (call.kind=='scout'and call.zone~='liver')or(call.kind=='siege'and call.zone~='bladder')then callsCorrect=false end end
local out={mixedArrivals=mixedArrivals,mixedPathsLegal=mixedPathsLegal,mixedMovesLegal=mixedMovesLegal,interleavedSwitches=switches,actualSubsteps=substeps,invalidSubsteps=violations,replacementGoalPreserved=replacementGoalPreserved,replacementPathLegal=replacementPathLegal,otherJobCompleted=otherCompleted,motionContextCorrect=motionContextCorrect,privateDiagnostics=privateDiagnostics,resetClearsBoth=resetClearsBoth,callsCorrect=callsCorrect,bothRadiiQueried=kinds.scout and kinds.siege,stats=stats,calls=#calls}
un();ur();ug();return out
''')
assert all(scheduler[k] for k in ['mixedArrivals','mixedPathsLegal','mixedMovesLegal','replacementGoalPreserved','replacementPathLegal','otherJobCompleted','motionContextCorrect','privateDiagnostics','resetClearsBoth','callsCorrect','bothRadiiQueried']),scheduler
assert all(sha(R/'scripts/war'/f)==h for f,h in hashes.items())
out={'testedModuleHashes':hashes,'qaScriptSha256':sha(Path(__file__)),'withoutSixthGate':without,'withSixthGate':with_gate,'scheduler':scheduler,'notes':['The Lipschitz bound proves the original eroded e135 aperture is wholly covered by the same-layer e191 sealed wall for siege cells.','The added gate uses the fixed outside target projection onto unchanged e191 and its actual outward normal; original gate and target are unchanged.','Direct straight crossing negatives are not generic reachability proofs; full actual six-stage sorties are in organ-sortie-evidence/report.json.','Lua slice and primitive CPU measurements are offline evidence, not native frame-time acceptance.','sortieZone/sortieEdges are fixture-only entity tags; diagnostic state and path caches are private and not saved.']}
p=D/'organ-sortie-contract-evidence';p.mkdir(exist_ok=True);(p/'report.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n');print({k:v for k,v in scheduler.items() if k!='stats'});print('sealed-wall controls',len(without['tests']))
