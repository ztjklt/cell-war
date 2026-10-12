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
network=json.loads((D/'network.json').read_text())
for region in c['regions']:
 zone=mapping.get(region['id'],region['id'])
 if zone not in [z['id'] for z in data['zones']]:continue
 gate=next(p for p in region['ports'] if p.get('exitToTissue'))
 for kind in ['scout','worker','siege']:
  target=next(t['fromSource'] for t in previous['tissueTests'] if t.get('zone')==zone and t['kind']==kind and t['id'].endswith('.forward'))
  portEdges={p['id']:sorted([e for e in network['edges'] if p['id'] in [e['a'],e['b']]],key=lambda e:(e['group']!='organ_internal',e['id']))[0]['id'] for p in region['ports'] if p['role'] in ['supply','return']}
  fixtures.append(dict(portEdges=portEdges,id=region['id'],name=region['name'],zone=zone,kind=kind,ports=region['ports'],gate=gate,target=target))
layers=json.loads((D/'organ-layers.json').read_text())
for f in fixtures:f['tissueEdgeIds']=next(z['tissueWallEdges']+z['extraStudyEdges'] for z in layers['zones'] if z['id']==f['zone'])
modules=['BodyRegionAccessStudy.lua',*previous['testedModuleHashes'],'OrganRouteNavigationStudy.lua','OrganRouteCollisionStudy.lua','OrganSortieNavigationStudy.lua','OrganAccessStudy.lua','TissueGeometry.lua']
moduleHashes={f:sha(R/'scripts/war'/f) for f in modules}
scriptHash=sha(Path(__file__))
inputFiles=['interface-contract.json','passages-data.json','navigation-fix-evidence/report.json','organ-layers.json']
inputHashes={f:sha(D/f) for f in inputFiles}
l=LuaRuntime(unpack_returned_tuples=True);l.execute("package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={};print=function()end;package.loaded['war.ReferenceVessels']=require('war.BodyRegionAccessStudy').create(require('war.OrganAccessStudy').create(require('war.StomachConnectivityStudy')))")
selected=os.environ.get('QA_REGIONS');fixtures=[f for f in fixtures if not selected or f['id'] in selected.split(',')]
kinds=os.environ.get('QA_KINDS');fixtures=[f for f in fixtures if not kinds or f['kind'] in kinds.split(',')]
l.execute('qaData='+lua(data)+';qaFixtures='+lua(fixtures))
l.globals().progress=lambda s:print(s,flush=True)
out=convert(l.execute(r'''
local W,P,C,K=require('war.World'),require('war.Path'),require('war.Commands'),require('war.CellCollision')
local Base=require('war.PassageCollisionStudy')
local L=require('war.StomachConnectivityStudy');local M=require('war.OrganRouteCollisionStudy');local N=require('war.OrganSortieNavigationStudy')
local s=W.generate(73,nil,nil,nil,4);W.rebuild(s);local net=W.vessels(s);local context={radius=0};local model=M.prepare(qaData)
local unGeometry=require('war.TissueGeometry').attachForTest(Base,M,model)
local unRadius=M.attachForTest(model,context,net,W);local raw=P.clear
local function unitContext(e)context.radius=K.radius(e.kind);context.zone=e.sortieZone;context.tissueEdges=e.sortieEdges end
local geom={
 activate=function(st,e)unitContext(e)end,
 pointAllowed=function(st,e,x,y,lane)unitContext(e);return M.allowed(model,context,net,x,y,lane)end,
 sweep=function(st,e,x,y,tx,ty,lane,desired)unitContext(e);return raw(st,x,y,tx,ty,e.faction,lane,desired)end,
 bounds=function(st,e)local b={minX=math.huge,minY=math.huge,maxX=-math.huge,maxY=-math.huge};for _,r in ipairs(model.zones[e.sortieZone].outlines)do for _,p in ipairs(r.points)do b.minX=math.min(b.minX,p[1]*2);b.maxX=math.max(b.maxX,p[1]*2);b.minY=math.min(b.minY,p[2]*2+512);b.maxY=math.max(b.maxY,p[2]*2+512)end end;return b end,
 portals=function(st,e)local list={};for _,g in ipairs(net.gates)do if e.sortieEdges[g.edge]then list[#list+1]=g end end;return list end,
}
local unNav,stats=N.attachForTest(P,C,W,geom,{nodeBudget=180000,searchNodeBudget=24000,cpuBudgetSeconds=15,frameSeconds=.003})
local Motion=require('war.Motion');local record=Motion.record;local segments={}
Motion.record=function(e)segments[#segments+1]={x=e.x,y=e.y,lane=e.vesselLane};return record(e)end
local result={routes={},adapterStats=stats}
for _,f in ipairs(qaFixtures)do
 context.zone=f.zone;context.tissueEdges={};for _,id in ipairs(f.tissueEdgeIds)do assert(L.edgeIndexById[id],id);context.tissueEdges[L.edgeIndexById[id]]=true end;context.radius=K.radius(f.kind);P.reset();s.entities={};s.nextId=1;W.rebuild(s)
 local supply,returnPort
 for _,p in ipairs(f.ports)do if p.role=='supply'then supply=p elseif p.role=='return'then returnPort=p end end
 local lane=L.edgeIndexById[f.gate.edge]
 local stages={{id='vascular-entry-to-gate',world=f.gate.insideWorld,lane=lane},{id='gate-to-tissue',world=f.gate.outsideWorld,lane=0},{id='tissue-to-objective',world={f.target[1]*2,f.target[2]*2+512},lane=0},{id='objective-to-gate',world=f.gate.outsideWorld,lane=0},{id='tissue-to-blood',world=f.gate.insideWorld,lane=lane},{id='gate-to-vascular-return',world=returnPort.world}}
 local sx,sy=supply.world[1],supply.world[2];local startLane=L.edgeIndexById[f.portEdges[supply.id]];stages[#stages].lane=L.edgeIndexById[f.portEdges[returnPort.id]]
 local r={id=f.id,kind=f.kind,name=f.name,zone=f.zone,targetSource=f.target,pass=false,stages={},trace={},startSource={sx/2,(sy-512)/2}}
 local e=C.spawn(s,'unit',f.kind,1,sx,sy,true)
 if not e or math.abs(e.x-sx)>1e-8 or math.abs(e.y-sy)>1e-8 then r.reason='supply spawn invalid or relocated'
 else
  e.vesselLane=startLane;e.sortieZone=f.zone;e.sortieEdges=context.tissueEdges;W.rebuild(s);r.trace={{x=e.x,y=e.y,lane=e.vesselLane,t=0}};local elapsed=0
  for _,stage in ipairs(stages)do
   local x,y=stage.world[1],stage.world[2];local startX,startY,startLane=e.x,e.y,e.vesselLane
   local q={id=stage.id,fromSource={startX/2,(startY-512)/2},toSource={x/2,(y-512)/2},startLane=startLane,endLane=stage.lane,arrived=false,pass=false,invalidSteps=0,radiusViolations=0,frameChordRejections=0,actualSubsteps=0}
   q.startLegal=M.allowed(model,context,net,startX,startY,startLane) and raw(s,startX,startY,startX,startY,1,startLane,startLane)
   q.endLegal=M.allowed(model,context,net,x,y,stage.lane) and raw(s,x,y,x,y,1,stage.lane,stage.lane)
   if not q.startLegal or not q.endLegal then q.reason='endpoint fails radius/zone/terrain'
   else
    C.execute(s,{kind='move',faction=1,ids={e.id},x=x,y=y});e.orders[1].vesselLane=stage.lane
    local idle=0;local stageCpu=os.clock()
    for frame=1,6000 do
     local px,py,oldLane=e.x,e.y,e.vesselLane;segments={};s.time=s.time+.05;P.update(s,1000,.003);require('war.Workers').update(s,e,.05);W.rebuild(s);elapsed=elapsed+.05;q.seconds=frame*.05
     if not raw(s,px,py,e.x,e.y,1,oldLane,e.vesselLane)then q.frameChordRejections=q.frameChordRejections+1 end
     local ax,ay,al=px,py,oldLane
     for _,segment in ipairs(segments)do
      q.actualSubsteps=q.actualSubsteps+1
      if not raw(s,ax,ay,segment.x,segment.y,1,al,segment.lane)then q.invalidSteps=q.invalidSteps+1 end
      if not M.allowed(model,context,net,segment.x,segment.y,segment.lane)then q.radiusViolations=q.radiusViolations+1 end
      ax,ay,al=segment.x,segment.y,segment.lane
     end
     if ax~=e.x or ay~=e.y or al~=e.vesselLane then q.invalidSteps=q.invalidSteps+1;q.unrecordedMovement=true end
     if not M.allowed(model,context,net,e.x,e.y,e.vesselLane)then q.radiusViolations=q.radiusViolations+1 end
     if frame%10==0 or oldLane~=e.vesselLane then r.trace[#r.trace+1]={x=e.x,y=e.y,lane=e.vesselLane,t=elapsed,stage=stage.id}end
     if (e.x-x)^2+(e.y-y)^2<.8*.8 and e.vesselLane==stage.lane then q.arrived=true;break end
     if e.pathFailed then q.reason=N.diagnostics(e) and N.diagnostics(e).reason or 'actual A* failed';break end
     if (e.x-px)^2+(e.y-py)^2<1e-10 and not e.pathPending then idle=idle+1 else idle=0 end
     if idle>=300 then q.reason='15s stationary with no pending path';break end
    end
    q.cpuSeconds=os.clock()-stageCpu;q.navigation=N.diagnostics(e)
    q.pass=q.arrived and q.invalidSteps==0 and q.radiusViolations==0
    if not q.pass and not q.reason then q.reason=q.arrived and 'ACTUAL_SUBSTEP_OR_RADIUS_REJECTION' or '300s timeout or wrong compartment'end
   end
   progress(f.id..' '..f.kind..' '..q.id..' '..tostring(q.pass)..' '..tostring(q.reason));r.stages[#r.stages+1]=q
   if not q.pass then r.reason=q.reason;r.failedStage=q.id;break end
  end
  r.pass=#r.stages==#stages and r.stages[#stages].pass;r.seconds=elapsed
  r.trace[#r.trace+1]={x=e.x,y=e.y,lane=e.vesselLane,t=elapsed}
 end
 result.routes[#result.routes+1]=r;progress(f.id..' '..f.kind..' '..tostring(r.pass)..' '..(r.failedStage or r.reason or ''))
end
Motion.record=record;unNav();unRadius();unGeometry();return result
'''))
out.update(productionInstalled=False,nativeEvidence=False,fixtureBasis='Original vascular supply/return and controlled tissue gates; internal objectives frozen from prior short-probe report',qaScriptSha256=scriptHash,inputHashes=inputHashes,testedModuleHashes=moduleHashes)
assert all(sha(R/'scripts/war'/f)==h for f,h in moduleHashes.items()),'Modules changed during test; rerun'
assert all(sha(D/f)==h for f,h in inputHashes.items()),'Inputs changed during test; rerun'
assert sha(Path(__file__))==scriptHash,'Test script changed during test; rerun'
out['summary']={'routes':len(out['routes']),'passed':sum(r['pass'] for r in out['routes']),'stages':sum(len(r['stages']) for r in out['routes']),'stagesPassed':sum(t['pass'] for r in out['routes'] for t in r['stages'])}
p=D/'organ-sortie-evidence';p.mkdir(exist_ok=True);(p/'report.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n');print(out['summary'])
