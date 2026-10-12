"""End-to-end organ sorties using fixed vascular ports and previous tissue targets."""
from pathlib import Path
import json,hashlib,os
from lupa.lua54 import LuaRuntime
from check_stomach_connectivity import lua,convert
R=Path(__file__).resolve().parents[2];os.chdir(R);D=R/'docs/body-life/vascular-art-study';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
c=json.loads((D/'interface-contract.json').read_text());data=json.loads((D/'passages-data.json').read_text());previous=json.loads((D/'navigation-fix-evidence/report.json').read_text())
for f,h in previous['testedModuleHashes'].items():assert sha(R/'scripts/war'/f)==h,f
mapping={'brain_r':'brain','brain_l':'brain','colon_proximal':'large_intestine','colon_distal':'large_intestine','coronary':'heart'}
fixtures=[]
for region in c['regions']:
 zone=mapping.get(region['id'],region['id'])
 if zone not in [z['id'] for z in data['zones']]:continue
 gate=next(p for p in region['ports'] if p.get('exitToTissue'))
 for kind in ['scout','worker','siege']:
  target=next(t['fromSource'] for t in previous['tissueTests'] if t.get('zone')==zone and t['kind']==kind and t['id'].endswith('.forward'))
  fixtures.append(dict(id=region['id'],name=region['name'],zone=zone,kind=kind,ports=region['ports'],gate=gate,target=target))
l=LuaRuntime(unpack_returned_tuples=True);l.execute("package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={};print=function()end;package.loaded['war.ReferenceVessels']=require('war.StomachConnectivityStudy')")
l.execute('qaData='+lua(data)+';qaFixtures='+lua(fixtures))
l.globals().progress=lambda s:print(s,flush=True)
out=convert(l.execute(r'''
local W,P,C,K=require('war.World'),require('war.Path'),require('war.Commands'),require('war.CellCollision')
local L=require('war.StomachConnectivityStudy');local M=require('war.OrganRouteCollisionStudy');local N=require('war.OrganRouteNavigationStudy')
local s=W.generate(73,nil,nil,nil,4);W.rebuild(s);local net=W.vessels(s);local context={radius=0};local model=M.prepare(qaData)
local unRadius=M.attachForTest(model,context,net);local raw=P.clear;local unNav,stats=N.attachForTest(P,C,W)
local result={routes={},adapterStats=stats}
for _,f in ipairs(qaFixtures)do for _,reverse in ipairs({false,true})do
 context.zone=f.zone;context.radius=K.radius(f.kind);P.reset();s.entities={};s.nextId=1;W.rebuild(s)
 local supply,returnPort
 for _,p in ipairs(f.ports)do if p.role=='supply'then supply=p elseif p.role=='return'then returnPort=p end end
 local lane=L.edgeIndexById[f.gate.edge]
 local stages={{id='vascular-entry-to-gate',world=f.gate.insideWorld,lane=lane},{id='gate-to-tissue',world=f.gate.outsideWorld,lane=0},{id='tissue-to-objective',world={f.target[1]*2,f.target[2]*2+512},lane=0},{id='objective-to-gate',world=f.gate.outsideWorld,lane=0},{id='tissue-to-blood',world=f.gate.insideWorld,lane=lane},{id='gate-to-vascular-return',world=returnPort.world}}
 local start=reverse and f.gate.outsideWorld or f.gate.insideWorld;local sx,sy=start[1],start[2];local startLane=reverse and 0 or lane;stages={reverse and stages[5] or stages[2]}
 local r={id=f.id..(reverse and '.inward' or '.outward'),kind=f.kind,name=f.name,zone=f.zone,targetSource=f.target,pass=false,stages={},trace={},startSource={sx/2,(sy-512)/2}}
 local e=C.spawn(s,'unit',f.kind,1,sx,sy,true)
 if not e or math.abs(e.x-sx)>1e-8 or math.abs(e.y-sy)>1e-8 then r.reason='supply spawn invalid or relocated'
 else
  e.vesselLane=startLane;W.rebuild(s);r.trace={{x=e.x,y=e.y,lane=e.vesselLane,t=0}};local elapsed=0
  for _,stage in ipairs(stages)do
   local x,y=stage.world[1],stage.world[2];local startX,startY,startLane=e.x,e.y,e.vesselLane
   local q={id=stage.id,fromSource={startX/2,(startY-512)/2},toSource={x/2,(y-512)/2},startLane=startLane,endLane=stage.lane,arrived=false,pass=false,invalidSteps=0,radiusViolations=0}
   q.startLegal=M.allowed(model,context,net,startX,startY,startLane) and raw(s,startX,startY,startX,startY,1,startLane,startLane)
   q.endLegal=M.allowed(model,context,net,x,y,stage.lane) and raw(s,x,y,x,y,1,stage.lane,stage.lane)
   if not q.startLegal or not q.endLegal then q.reason='endpoint fails radius/zone/terrain'
   else
    C.execute(s,{kind='move',faction=1,ids={e.id},x=x,y=y});e.orders[1].vesselLane=stage.lane
    for frame=1,400 do
     local px,py,oldLane=e.x,e.y,e.vesselLane;s.time=s.time+.05;P.update(s,100);require('war.Workers').update(s,e,.05);W.rebuild(s);elapsed=elapsed+.05;q.seconds=frame*.05
     if not raw(s,px,py,e.x,e.y,1,oldLane,e.vesselLane)then q.invalidSteps=q.invalidSteps+1 end
     if not M.allowed(model,context,net,e.x,e.y,e.vesselLane)then q.radiusViolations=q.radiusViolations+1 end
     if frame%10==0 or oldLane~=e.vesselLane then r.trace[#r.trace+1]={x=e.x,y=e.y,lane=e.vesselLane,t=elapsed,stage=stage.id}end
     if (e.x-x)^2+(e.y-y)^2<.8*.8 and e.vesselLane==stage.lane then q.arrived=true;break end
     if e.pathFailed then q.reason='actual A* failed';break end
    end
    q.pass=q.arrived and q.invalidSteps==0 and q.radiusViolations==0
    if not q.pass and not q.reason then q.reason='20s timeout or wrong compartment'end
   end
   r.stages[#r.stages+1]=q
   if not q.pass then r.reason=q.reason;r.failedStage=q.id;break end
  end
  r.pass=#r.stages==#stages and r.stages[#stages].pass;r.seconds=elapsed
  r.trace[#r.trace+1]={x=e.x,y=e.y,lane=e.vesselLane,t=elapsed}
 end
 result.routes[#result.routes+1]=r;progress(f.id..' '..f.kind..' '..tostring(r.pass)..' '..(r.failedStage or '')..' '..(r.reason or ''))
end end
unNav();unRadius();return result
'''))
out.update(productionInstalled=False,nativeEvidence=False,fixtureBasis='Original vascular supply/return and controlled tissue gates; internal objectives frozen from prior short-probe report',qaScriptSha256=sha(Path(__file__)),inputHashes={f:sha(D/f) for f in ['interface-contract.json','passages-data.json','navigation-fix-evidence/report.json']},testedModuleHashes={f:sha(R/'scripts/war'/f) for f in [*previous['testedModuleHashes'],'OrganRouteNavigationStudy.lua','OrganRouteCollisionStudy.lua']})
out['summary']={'routes':len(out['routes']),'passed':sum(r['pass'] for r in out['routes']),'stages':sum(len(r['stages']) for r in out['routes']),'stagesPassed':sum(t['pass'] for r in out['routes'] for t in r['stages'])}
p=D/'organ-route-membrane-probe';p.mkdir(exist_ok=True);(p/'report.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n');print(out['summary'])
