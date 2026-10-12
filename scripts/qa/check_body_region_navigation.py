"""Fixed body objectives, controlled access and real coarse tissue movement."""
from pathlib import Path
import json,hashlib,os
from lupa.lua54 import LuaRuntime
from check_stomach_connectivity import lua,convert
ROOT=Path(__file__).resolve().parents[2];os.chdir(ROOT);DOC=ROOT/'docs/body-life/vascular-art-study'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
files=['body-region-candidates.json','interface-contract.json','passages-data.json','network.json']
hashes={f:sha(DOC/f)for f in files};body,contract,data,network=[json.loads((DOC/f).read_text())for f in files]
fixtures=[]
for r in body['regions']:
 data['zones'].append(dict(id=r['id'],outlines=r['boundaryRings'],forbiddenEdges=[]))
 gate=next(p for x in contract['regions'] if x['id']==r['id'] for p in x['ports'] if p.get('exitToTissue'))
 edges=sorted(set([e['id']for e in network['edges']if e['a'].startswith(r['id']+'.')or e['b'].startswith(r['id']+'.')]+[gate['edge']]))
 target=next(t for t in r['fixedTargets']if all(s['geometryDiskLegal']for s in t['sizes']))
 for kind in ('scout','worker','siege'):fixtures.append(dict(id=r['id']+'.'+kind,region=r['id'],kind=kind,gate=gate,target=target,tissueEdgeIds=edges))
mods=['BodyRegionAccessStudy.lua','OrganAccessStudy.lua','BodyRegionNavigationStudy.lua','TissueGeometry.lua','OrganRouteNavigationStudy.lua','OrganRouteCollisionStudy.lua','PassageCollisionStudy.lua','PassageNavigationStudy.lua','Path.lua','Commands.lua','World.lua','Workers.lua','CellCollision.lua','Data.lua','StomachConnectivityStudy.lua','ReviewedVascularLayout.lua','ReferenceMap.lua']
mh={f:sha(ROOT/'scripts/war'/f)for f in mods};script=sha(Path(__file__));outdir=DOC/'body-region-navigation-evidence';outdir.mkdir(exist_ok=True)
rt=LuaRuntime(unpack_returned_tuples=True);rt.execute("package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={};print=function()end;package.loaded['war.ReferenceVessels']=require('war.BodyRegionAccessStudy').create(require('war.OrganAccessStudy').create(require('war.StomachConnectivityStudy')))")
rt.execute('qaData='+lua(data)+';qaFixtures='+lua(fixtures));rt.globals().progress=lambda s:print(s,flush=True)
def checkpoint(x):(outdir/'partial.json').write_text(json.dumps(convert(x),ensure_ascii=False,indent=2)+'\n')
rt.globals().checkpoint=checkpoint
result=convert(rt.execute(r'''
local W,P,C,K=require('war.World'),require('war.Path'),require('war.Commands'),require('war.CellCollision')
local L=require('war.ReferenceVessels');local M=require('war.OrganRouteCollisionStudy');local N=require('war.OrganRouteNavigationStudy');local B=require('war.BodyRegionNavigationStudy')
local s=W.generate(73,nil,nil,nil,4);W.rebuild(s);local net=W.vessels(s);local model=M.prepare(qaData);local context={radius=0}
local unG=require('war.TissueGeometry').attachForTest(require('war.PassageCollisionStudy'),M,model)
local unMemo,memoStats=B.cacheGeometry(require('war.PassageCollisionStudy'),M,model)
local unRadius=M.attachForTest(model,context,net,W);local raw=P.clear;local unN,ns=N.attachForTest(P,C,W);local unB,bs,jobs=B.attachForTest(P,C,W,context)
local base=require('war.StomachConnectivityStudy')
local function same(a,b)if type(a)~=type(b)then return false end;if type(a)~='table'then return a==b end;for k,v in pairs(a)do if not same(v,b[k])then return false end end;for k in pairs(b)do if a[k]==nil then return false end end;return true end
for _,key in ipairs({'nodes','edges','gates'})do for i,v in ipairs(base[key])do assert(same(v,L[key][i]),'base '..key..' changed')end end
assert(#L.gates==#base.gates+6,'combined graph must append six controlled gates')
local out={baseGeometryPreserved=true,combinedGateAdditions=6,routes={},oldExitNegatives={},accessAdditions=L.bodyRegionAccessAdditions,macroStats=bs,memoStats=memoStats}
for _,f in ipairs(qaFixtures)do
 progress('start '..f.id);context.zone=f.region;context.radius=K.radius(f.kind);context.tissueEdges={};for _,id in ipairs(f.tissueEdgeIds)do context.tissueEdges[assert(L.edgeIndexById[id])]=true end
 P.reset();s.entities={};s.nextId=1;W.rebuild(s)
 local oldx,oldy=f.gate.outsideWorld[1],f.gate.outsideWorld[2]
 local oldLegal=M.allowed(model,context,net,oldx,oldy,0) and raw(s,oldx,oldy,oldx,oldy,1,0,0)
 local r={id=f.id,region=f.region,kind=f.kind,targetSource=f.target.source,oldOutsideSource={oldx/2,(oldy-512)/2},oldOutsideLegal=not not oldLegal,pass=false,trace={},stages={},invalidSteps=0,radiusViolations=0,seconds=0}
 local planCpuStart=bs.planningCpu
 local stages={};local sx,sy,lane=oldx,oldy,0
 if not oldLegal then
  out.oldExitNegatives[#out.oldExitNegatives+1]={id=f.id,source=r.oldOutsideSource,rejected=true}
  local name=f.region=='arm_r' and 'body.arm_r.clear_bank' or f.region=='leg_r' and 'body.leg_r.clear_bank'
  local gate;for _,g in ipairs(net.gates)do if g.name==name then gate=g end end
  assert(gate,'no controlled replacement for '..f.id);sx,sy=f.gate.insideWorld[1],f.gate.insideWorld[2];lane=L.edgeIndexById[f.gate.edge]
  stages[#stages+1]={id='same-lumen-to-safe-gate',x=gate.px,y=gate.py,lane=gate.edge}
  stages[#stages+1]={id='safe-gate-to-tissue',x=gate.x+gate.nx*5.2,y=gate.y+gate.ny*5.2,lane=0}
  r.accessGate=name
 end
 stages[#stages+1]={id='fixed-tissue-objective',x=f.target.world[1],y=f.target.world[2],lane=0}
 local e=C.spawn(s,'unit',f.kind,1,sx,sy,true);assert(e and math.abs(e.x-sx)<1e-8 and math.abs(e.y-sy)<1e-8,'spawn moved');e.vesselLane=lane;W.rebuild(s)
 r.trace={{x=sx,y=sy,lane=lane,t=0}};local cpu=os.clock();local deadline=cpu+30
 debug.sethook(function()if os.clock()>deadline then error('CPU_BUDGET_EXCEEDED')end end,'',20000)
 local ok,err=pcall(function()
 for _,stage in ipairs(stages)do
  local q={id=stage.id,pass=false,fromSource={e.x/2,(e.y-512)/2},toSource={stage.x/2,(stage.y-512)/2},fromLane=e.vesselLane,toLane=stage.lane,seconds=0}
  q.startLegal=not not (M.allowed(model,context,net,e.x,e.y,e.vesselLane) and raw(s,e.x,e.y,e.x,e.y,1,e.vesselLane,e.vesselLane))
  q.endLegal=not not (M.allowed(model,context,net,stage.x,stage.y,stage.lane) and raw(s,stage.x,stage.y,stage.x,stage.y,1,stage.lane,stage.lane))
  r.stages[#r.stages+1]=q
  if not q.startLegal or not q.endLegal then q.reason='endpoint rejected';r.reason=q.reason;break end
  B.clearDiagnostics(e)
  C.execute(s,{kind='move',faction=1,ids={e.id},x=stage.x,y=stage.y});e.orders[1].vesselLane=stage.lane
  local D=require('war.Data');local minMove=1;for _,b in pairs(D.biomes)do if not b.blocked then minMove=math.min(minMove,b.move or 1)end end
  local speed=D.units[e.kind].speed*minMove*.65
  q.motionLimitSeconds=math.sqrt((e.x-stage.x)^2+(e.y-stage.y)^2)/speed*1.25+15
  for frame=1,100000 do
   if e.pathPending then q.planningFrames=(q.planningFrames or 0)+1 else q.movementFrames=(q.movementFrames or 0)+1 end
   local x,y,oldLane=e.x,e.y,e.vesselLane;s.time=s.time+.05;P.update(s,500,.003);require('war.Workers').update(s,e,.05);W.rebuild(s);q.seconds=frame*.05;r.seconds=r.seconds+.05
   if not raw(s,x,y,e.x,e.y,1,oldLane,e.vesselLane)then r.invalidSteps=r.invalidSteps+1 end
   if not M.allowed(model,context,net,e.x,e.y,e.vesselLane)then r.radiusViolations=r.radiusViolations+1 end
   if frame%10==0 or oldLane~=e.vesselLane then r.trace[#r.trace+1]={x=e.x,y=e.y,lane=e.vesselLane,t=r.seconds,stage=stage.id}end
   if B.getPlan(e) and not q.plan then q.plan=B.getPlan(e);q.motionLimitSeconds=q.plan.lengthWorld/speed*1.25+15 end
   if (q.movementFrames or 0)*.05>q.motionLimitSeconds then q.reason='movement exceeded route-length/speed budget';break end
   if (e.x-stage.x)^2+(e.y-stage.y)^2<.8*.8 and e.vesselLane==stage.lane then q.pass=true;break end
   if e.pathFailed then q.reason=B.getFailure(e) or 'planner exhausted';break end
  end
  if not q.pass then r.reason=q.reason or 'simulation budget';break end
 end
 end);debug.sethook();r.cpuSeconds=os.clock()-cpu;r.planningCpuSeconds=bs.planningCpu-planCpuStart;r.movementAndVerificationCpuSeconds=r.cpuSeconds-r.planningCpuSeconds
 if not ok then if tostring(err):find('CPU_BUDGET_EXCEEDED',1,true)then r.reason='CPU_BUDGET_EXCEEDED'else error(err)end end
 r.pass=#r.stages==#stages and r.stages[#stages].pass and r.invalidSteps==0 and r.radiusViolations==0
 r.finalSource={e.x/2,(e.y-512)/2};r.trace[#r.trace+1]={x=e.x,y=e.y,lane=e.vesselLane,t=r.seconds}
 out.routes[#out.routes+1]=r;checkpoint(out);progress(f.id..' '..tostring(r.pass)..' '..(r.reason or 'arrived')..' cpu='..r.cpuSeconds)
end
-- Independent scheduler safety: two kinds/zones, poisoned ambient context,
-- cancellation by identity replacement, token cancellation and uninstall cleanup.
P.reset();s.entities={};s.nextId=1;W.rebuild(s)
local aFixture,bFixture=qaFixtures[1],qaFixtures[5];local probes={}
for _,f in ipairs({aFixture,bFixture})do
 context.zone=f.region;context.radius=K.radius(f.kind);context.tissueEdges={};for _,id in ipairs(f.tissueEdgeIds)do context.tissueEdges[L.edgeIndexById[id]]=true end
 local p=f.gate.outsideWorld;local e=C.spawn(s,'unit',f.kind,1,p[1],p[2],true);e.vesselLane=0;B.setContext(e,context)
 e.orders={{kind='move',x=f.target.world[1],y=f.target.world[2],vesselLane=0}}
 P.request(s,e,f.target.world[1],f.target.world[2]);probes[#probes+1]=e
end
local records={};for _,j in ipairs(jobs)do records[#records+1]={zone=j.context.zone,radius=j.context.radius,id=j.id}end
context.zone='intentionally-invalid';context.radius=999;context.tissueEdges={}
P.update(s,10,.003);local preserved=context.zone=='intentionally-invalid' and context.radius==999
local old=probes[1];s.entities[old.id]={id=old.id,orderToken=old.orderToken};probes[2].orderToken=probes[2].orderToken+1
P.update(s,500,.003)
local cancelled=#jobs==0
out.contextSafety={captured=records,ambientContextRestored=preserved,identityAndTokenCancellation=cancelled,pass=preserved and cancelled and records[1].zone~=records[2].zone and records[1].radius~=records[2].radius}
assert(out.contextSafety.pass,'job context/cancellation regression')
unB();unN();unRadius();unMemo();unG();return out
'''))
assert all(sha(ROOT/'scripts/war'/f)==h for f,h in mh.items()),'module changed during run'
assert all(sha(DOC/f)==h for f,h in hashes.items()),'inputs changed'
assert sha(Path(__file__))==script,'script changed'
result.update(testedModuleHashes=mh,sourceInputHashes=hashes,qaScriptSha256=script,productionInstalled=False,nativeEvidence=False,pathBudget={'expansions':500,'seconds':.003,'routeCpuLimit':30},fixedTargetBaseline='body-region-route-evidence/report.json')
result['summary']={'routes':len(result['routes']),'passed':sum(r['pass']for r in result['routes']),'oldExitNegatives':len(result['oldExitNegatives']),'invalidSteps':sum(r['invalidSteps']for r in result['routes']),'radiusViolations':sum(r['radiusViolations']for r in result['routes']),'maxRouteCpu':max(r['cpuSeconds']for r in result['routes'])}
(outdir/'report.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(result['summary'])
