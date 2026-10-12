"""Replay frozen radius fixtures against opt-in navigation fixes, not new endpoints."""
from pathlib import Path
import json,hashlib,os
from lupa.lua54 import LuaRuntime
from check_stomach_connectivity import lua,convert
ROOT=Path(__file__).resolve().parents[2];os.chdir(ROOT);D=ROOT/'docs/body-life/vascular-art-study'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
base=json.loads((D/'clearance-evidence/report.json').read_text());data=json.loads((D/'passages-data.json').read_text())
assert base['sourcePassagesSha256']==sha(D/'passages-data.json')
for f,h in base['testedModuleHashes'].items():assert sha(ROOT/'scripts/war'/f)==h,'baseline module drift '+f
for f,h in json.loads((D/'round5-baseline.json').read_text()).items():assert sha(ROOT/f)==h,'production drift '+f
fixtures=[dict(t,group=g) for g in ['portTests','tissueTests'] for t in base[g]]
rt=LuaRuntime(unpack_returned_tuples=True);rt.execute("package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={};print=function()end;package.loaded['war.ReferenceVessels']=require('war.StomachConnectivityStudy')")
walls=json.loads((D/'connectivity-evidence/report.json').read_text())['sealedWallChecks']
rt.execute('qaData='+lua(data)+';qaFixtures='+lua(fixtures)+';qaWalls='+lua(walls))
r=convert(rt.execute(r'''
 local W,P,C,K=require('war.World'),require('war.Path'),require('war.Commands'),require('war.CellCollision')
 local M=require('war.PassageCollisionStudy');local N=require('war.PassageNavigationStudy')
 local s=W.generate(73,nil,nil,nil,4);W.rebuild(s);local net=W.vessels(s)
 local context={radius=0};local restoreRadius=M.attachForTest(M.prepare(qaData),context,net)
 local model=M.prepare(qaData);local rawClear=P.clear;local rawRequest=P.request;local rawGo=C.go
 local result={controlTests={},portTests={},tissueTests={},timingTests={},sealedWallTests={}}
 local function test(t,dt)
  P.reset();s.entities={};s.nextId=1;W.rebuild(s);context.zone=t.zone;context.radius=K.radius(t.kind)
  local ax,ay=t.fromSource[1]*2,t.fromSource[2]*2+512;local bx,by=t.toSource[1]*2,t.toSource[2]*2+512
  local e=C.spawn(s,'unit',t.kind,1,ax,ay,true);assert(e and math.abs(e.x-ax)<1e-8 and math.abs(e.y-ay)<1e-8,'fixture relocated')
  e.vesselLane=t.startLane;W.rebuild(s);assert(C.execute(s,{kind='move',faction=1,ids={e.id},x=bx,y=by}))
  local out={id=t.id,kind=t.kind,port=t.port,passage=t.passage,zone=t.zone,name=t.name,fromSource=t.fromSource,toSource=t.toSource,startLane=t.startLane,endLane=t.endLane,arrived=false,pass=false,trace={{x=e.x,y=e.y,lane=e.vesselLane,t=0}},invalidSteps=0,radiusViolations=0,dt=dt,baselinePass=t.pass}
  for frame=1,math.ceil(70/dt)do
   local x,y,lane=e.x,e.y,e.vesselLane;s.time=s.time+dt;P.update(s,700);require('war.Workers').update(s,e,dt);W.rebuild(s)
   if not rawClear(s,x,y,e.x,e.y,1,lane,e.vesselLane)then out.invalidSteps=out.invalidSteps+1 end
   if not M.allowed(model,context,net,e.x,e.y,e.vesselLane)then out.radiusViolations=out.radiusViolations+1 end
   if frame%math.max(1,math.floor(.2/dt+.5))==0 or lane~=e.vesselLane then out.trace[#out.trace+1]={x=e.x,y=e.y,lane=e.vesselLane,t=frame*dt}end
   out.seconds=frame*dt
   if (e.x-bx)^2+(e.y-by)^2<.8*.8 and e.vesselLane==t.endLane then out.arrived=true;break end
   if e.pathFailed then out.reason='actual A* failed';break end
  end
  out.trace[#out.trace+1]={x=e.x,y=e.y,lane=e.vesselLane,t=out.seconds}
  out.pass=out.arrived and out.invalidSteps==0 and out.radiusViolations==0
  if not out.pass and not out.reason then out.reason='movement did not arrive within 70 seconds' end
  return out
 end
 for _,t in ipairs(qaFixtures)do if not t.pass then result.controlTests[#result.controlTests+1]=test(t,.05)end end
 local restore,stats=N.attachForTest(P,C,W)
 for _,t in ipairs(qaFixtures)do result[t.group][#result[t.group]+1]=test(t,.05)end
 for _,t in ipairs(qaFixtures)do if not t.pass then for _,fps in ipairs({30,60,120})do result.timingTests[#result.timingTests+1]=test(t,1/fps)end end end
 -- Doorless walls must remain closed, including after the request fast path.
 context.zone=nil
 local L=require('war.StomachConnectivityStudy')
 for i,q in ipairs(qaWalls)do for _,kind in ipairs({'scout','worker','siege'})do
  context.radius=K.radius(kind)
  local lane=L.edgeIndexById[i==1 and 'e184' or 'study.stomach.wall_service']
  local a,b=q.outsideSource,q.source
  local ax,ay,bx,by=a[1]*2,a[2]*2+512,b[1]*2,b[2]*2+512
  local enter=P.clear(s,ax,ay,bx,by,1,0,lane)
  local leave=P.clear(s,bx,by,ax,ay,1,lane,0)
  result.sealedWallTests[#result.sealedWallTests+1]={id=q.id,kind=kind,pass=not enter and not leave,entryBlocked=not enter,exitBlocked=not leave}
 end end
 result.adapterStats=stats
 restore();result.restored=P.clear==rawClear and P.request==rawRequest and C.go==rawGo
 restoreRadius();return result
'''))
r.update(sourceBaselineSha256=sha(D/'clearance-evidence/report.json'),sourcePassagesSha256=sha(D/'passages-data.json'),qaScriptSha256=sha(Path(__file__)),testedModuleHashes={f:sha(ROOT/'scripts/war'/f) for f in list(base['testedModuleHashes'])+['PassageNavigationStudy.lua']},nativeEvidence=False,productionInstalled=False,sizes=base['sizes'],clearanceSurveys=base['clearanceSurveys'],radiusNegativeTests=base['radiusNegativeTests'],portBaseline=base['portTests'],tissueBaseline=base['tissueTests'],repairTests=[],baselineArrivals=35)
r['summary']={g:dict(total=len(r[g]),passed=sum(bool(t.get('pass')) for t in r[g])) for g in ['portTests','tissueTests','timingTests','radiusNegativeTests','sealedWallTests']}
r['scope']='Frozen 108 local fixtures. Radius filter unchanged. Exact short routes and legal lane selection only. Not full-organ or native acceptance.'
out=D/'navigation-fix-evidence';out.mkdir(exist_ok=True);(out/'report.json').write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(r['summary']),flush=True)
for g in ['portTests','tissueTests','timingTests']:
 for t in r[g]:
  if not t['pass']:print(g,t['id'],t['kind'],t['dt'],t.get('reason'))
assert r['restored']
assert all(not t['arrived'] for t in r['controlTests']),'original failures did not reproduce'
assert all(t['pass'] for g in ['portTests','tissueTests','timingTests','sealedWallTests'] for t in r[g]),'retained failure'
