"""Five fixed distal tissue routes, using real isolated Lua collision/navigation.
PYTHONPATH=/tmp/passage-tools314 python3 scripts/qa/check_body_region_routes.py
All failures are retained; no fixture relocation, new gate, or production edit.
"""
from pathlib import Path
import time
import json,hashlib,os
from lupa.lua54 import LuaRuntime
from check_stomach_connectivity import lua,convert
ROOT=Path(__file__).resolve().parents[2];os.chdir(ROOT);DOC=ROOT/'docs/body-life/vascular-art-study'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
inputs=['body-region-candidates.json','interface-contract.json','passages-data.json','network.json']
input_hashes={f:sha(DOC/f) for f in inputs}
body,contract,data,network=[json.loads((DOC/f).read_text()) for f in inputs]
# Only add isolated zones, no gates/lanes or changes to the source boundary arrays.
fixtures=[];negative=[]
for r in body['regions']:
 data['zones'].append({'id':r['id'],'name':r['name'],'outlines':r['boundaryRings'],'forbiddenEdges':[]})
 port=next(p for x in contract['regions'] if x['id']==r['id'] for p in x['ports'] if p.get('exitToTissue'))
 ids=[e['id'] for e in network['edges'] if e['a'].startswith(r['id']+'.') or e['b'].startswith(r['id']+'.')]
 ids=sorted(set(ids+[port['edge']]))
 target=next(t for t in r['fixedTargets'] if all(s['geometryDiskLegal'] for s in t['sizes']))
 for kind in ('scout','worker','siege'):
  fixtures.append({'id':r['id']+'.'+kind,'region':r['id'],'name':r['name'],'kind':kind,'gate':port,'target':target,'tissueEdgeIds':ids})
 for t in r['fixedTargets']:
  if not all(s['geometryDiskLegal'] for s in t['sizes']):negative.append({'region':r['id'],'target':t,'tissueEdgeIds':ids})
modules=['OrganRouteNavigationStudy.lua','OrganRouteCollisionStudy.lua','PassageCollisionStudy.lua','PassageNavigationStudy.lua','Path.lua','Commands.lua','World.lua','Workers.lua','CellCollision.lua','Data.lua','StomachConnectivityStudy.lua','ReviewedVascularLayout.lua','ReferenceMap.lua','ReferenceTrace.lua']
modules=[f for f in modules if (ROOT/'scripts/war'/f).exists()]
hashes={f:sha(ROOT/'scripts/war'/f) for f in modules};script_hash=sha(Path(__file__))
rt=LuaRuntime(unpack_returned_tuples=True)
rt.execute("package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={};print=function()end;package.loaded['war.ReferenceVessels']=require('war.StomachConnectivityStudy')")
rt.execute('qaData='+lua(data)+';qaFixtures='+lua(fixtures)+';qaNegative='+lua(negative))
rt.globals().progress=lambda s:print(s,flush=True)
partial=DOC/'body-region-route-evidence';partial.mkdir(exist_ok=True)
def checkpoint(value):
 out=convert(value);out.update(status='IN_PROGRESS_PARTIAL',productionInstalled=False,nativeEvidence=False,pathBudget={'expansionsPerFrame':500,'secondsPerFrame':.003,'cpuSecondsPerRoute':30,'maxSimulatedSeconds':300},sourceInputHashes=input_hashes,testedModuleHashes=hashes,qaScriptSha256=script_hash)
 (partial/'partial.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n')
rt.globals().checkpoint=checkpoint
result=convert(rt.execute(r'''
local W,P,C,K=require('war.World'),require('war.Path'),require('war.Commands'),require('war.CellCollision')
local L=require('war.StomachConnectivityStudy');local M=require('war.OrganRouteCollisionStudy');local N=require('war.OrganRouteNavigationStudy')
local Base=require('war.PassageCollisionStudy');local originalClearance=Base.clearance
local memo,count={},0;local cacheStats={hits=0,misses=0,clears=0,maxEntries=200000}
Base.clearance=function(model,zone,x,y)
 local key=zone..':'..string.format('%.17g:%.17g',x,y);local hit=memo[key]
 if hit~=nil then cacheStats.hits=cacheStats.hits+1;return hit end
 local value=originalClearance(model,zone,x,y);cacheStats.misses=cacheStats.misses+1
 if count>=200000 then memo={};count=0;cacheStats.clears=cacheStats.clears+1 end
 memo[key]=value;count=count+1;return value
end
M.clearance=Base.clearance
local s=W.generate(73,nil,nil,nil,4);W.rebuild(s);local net=W.vessels(s);local context={radius=0};local model=M.prepare(qaData)
local unRadius=M.attachForTest(model,context,net,W);local raw=P.clear;local unNav,stats=N.attachForTest(P,C,W)
local out={routes={},negativeTests={},adapterStats=stats,clearanceCacheStats=cacheStats}
local function choose(region,kind,ids)
 context.zone=region;context.radius=K.radius(kind);context.tissueEdges={}
 local numeric={};for _,id in ipairs(ids)do local n=assert(L.edgeIndexById[id],id);context.tissueEdges[n]=true;numeric[#numeric+1]={id=id,index=n}end
 return numeric
end
for _,f in ipairs(qaFixtures)do
 progress('start '..f.id);local layers=choose(f.region,f.kind,f.tissueEdgeIds);P.reset();s.entities={};s.nextId=1;W.rebuild(s)
 local sx,sy=f.gate.outsideWorld[1],f.gate.outsideWorld[2];local tx,ty=f.target.world[1],f.target.world[2]
 local r={id=f.id,region=f.region,name=f.name,kind=f.kind,startSource={sx/2,(sy-512)/2},targetSource=f.target.source,targetId=f.target.id,gateId=f.gate.id,gateEdge=f.gate.edge,layerEdges=layers,radiusWorld=context.radius,trace={},pass=false,arrived=false,invalidSteps=0,radiusViolations=0,seconds=0}
 r.startRadiusLegal=not not M.allowed(model,context,net,sx,sy,0);r.targetRadiusLegal=not not M.allowed(model,context,net,tx,ty,0)
 r.startTerrainLegal=not not raw(s,sx,sy,sx,sy,1,0,0);r.targetTerrainLegal=not not raw(s,tx,ty,tx,ty,1,0,0)
 r.startClearanceSource=M.clearance(model,f.region,sx/2,(sy-512)/2);r.targetClearanceSource=M.clearance(model,f.region,tx/2,(ty-512)/2)
 local cpuStart=os.clock();local deadline=cpuStart+30;local e
 debug.sethook(function()if os.clock()>deadline then error('CPU_BUDGET_EXCEEDED')end end,'',20000)
 local okay,err=pcall(function()
 if not r.startRadiusLegal or not r.targetRadiusLegal or not r.startTerrainLegal or not r.targetTerrainLegal then r.reason='fixed endpoint fails radius/zone/terrain'
 else
  e=C.spawn(s,'unit',f.kind,1,sx,sy,true)
  if not e or math.abs(e.x-sx)>1e-8 or math.abs(e.y-sy)>1e-8 then r.reason='spawn rejected or relocated'
  else
   e.vesselLane=0;W.rebuild(s);r.trace={{x=e.x,y=e.y,lane=0,t=0}}
   C.execute(s,{kind='move',faction=1,ids={e.id},x=tx,y=ty});e.orders[1].vesselLane=0
   local idle=0
   for frame=1,6000 do
    local px,py,lane=e.x,e.y,e.vesselLane;s.time=s.time+.05;P.update(s,500,.003);require('war.Workers').update(s,e,.05);W.rebuild(s);r.seconds=frame*.05
    if not raw(s,px,py,e.x,e.y,1,lane,e.vesselLane)then r.invalidSteps=r.invalidSteps+1 end
    if not M.allowed(model,context,net,e.x,e.y,e.vesselLane)then r.radiusViolations=r.radiusViolations+1 end
    if frame%10==0 or lane~=e.vesselLane then r.trace[#r.trace+1]={x=e.x,y=e.y,lane=e.vesselLane,t=r.seconds}end
    if (e.x-tx)^2+(e.y-ty)^2<.8*.8 and e.vesselLane==0 then r.arrived=true;break end
    if e.pathFailed then r.reason='actual A* failed';break end
    if (e.x-px)^2+(e.y-py)^2<1e-10 and not e.pathPending then idle=idle+1 else idle=0 end
    if idle>=300 then r.reason='15s stationary without pending path';break end
   end
   r.pass=r.arrived and r.invalidSteps==0 and r.radiusViolations==0
   if not r.pass and not r.reason then r.reason=e.pathPending and 'SIMULATION_BUDGET_EXCEEDED_PENDING_SEARCH' or 'SIMULATION_BUDGET_EXCEEDED'end
   r.trace[#r.trace+1]={x=e.x,y=e.y,lane=e.vesselLane,t=r.seconds};r.finalSource={e.x/2,(e.y-512)/2}
  end
 end
 end);debug.sethook();r.cpuSeconds=os.clock()-cpuStart;r.cpuLimitSeconds=30;r.pendingJobs={}
 for _,job in ipairs(P.jobs)do r.pendingJobs[#r.pendingJobs+1]={visits=job.visits,phase=job.phase,limit=job.limit,open=job.open and #job.open or 0,smoothing=not not job.smoothing}end
 if not okay then
  if tostring(err):find('CPU_BUDGET_EXCEEDED',1,true)then r.pass=false;r.reason='CPU_BUDGET_EXCEEDED';r.connectivityConclusion='UNDETERMINED_CPU_LIMIT'
  else error(err)end
 end
 if r.reason and r.reason:find('BUDGET_EXCEEDED',1,true)then r.connectivityConclusion='UNDETERMINED_RESOURCE_LIMIT'end
 if e then r.finalSource={e.x/2,(e.y-512)/2};r.trace[#r.trace+1]={x=e.x,y=e.y,lane=e.vesselLane,t=r.seconds}end
 out.routes[#out.routes+1]=r;checkpoint(out);progress(f.id..' '..tostring(r.pass)..' '..(r.reason or 'arrived'))
end
for _,f in ipairs(qaNegative)do
 for _,kind in ipairs({'scout','worker','siege'})do
  choose(f.region,kind,f.tissueEdgeIds);local p=f.target.world
  local allowed=M.allowed(model,context,net,p[1],p[2],0)
  out.negativeTests[#out.negativeTests+1]={id=f.target.id,region=f.region,kind=kind,source=f.target.source,rejected=not allowed,pass=not allowed,scope='original failed fixed target rejected by actual geometry/radius helper'}
 end
end
unNav();unRadius();Base.clearance=originalClearance;M.clearance=originalClearance;return out
'''))
assert all(sha(ROOT/'scripts/war'/f)==h for f,h in hashes.items()),'shared module changed during run; rerun'
assert all(sha(DOC/f)==h for f,h in input_hashes.items()),'input changed during run; rerun'
assert sha(Path(__file__))==script_hash,'script changed during run; rerun'
result.update(version=1,status='ISOLATED_FIXED_BODY_TISSUE_ROUTES',productionInstalled=False,nativeEvidence=False,pathBudget={'expansionsPerFrame':500,'secondsPerFrame':.003,'cpuSecondsPerRoute':30,'maxSimulatedSeconds':300},sourceInputHashes=input_hashes,testedModuleHashes=hashes,qaScriptSha256=script_hash,fixtures=fixtures,layerContract='Only existing edges incident to corresponding region namespace, plus that region controlled gate edge; no new physical gates. Numeric IDs recorded per route.',limitations=['Candidate tissue boundaries retain known missing joint/pelvis silhouettes.','No crossing of gate or supply/return chain is claimed; test starts at original outsideWorld.','Special passages not applied to these 5 body-region zones; torso layer contract remains a conservative design candidate.','Exact coordinate memoization of pure clearance, 17-digit x/y keys, maximum 200000 entries; no coordinate snapping or geometry changes.','Single cells only; no crowd or native performance claim.','Zero endpoint legality or route failures are hidden by relocation or substituted targets.'])
result['summary']={'routes':len(result['routes']),'passed':sum(r['pass'] for r in result['routes']),'cpuBudgetExceeded':sum(r.get('reason')=='CPU_BUDGET_EXCEEDED' for r in result['routes']),'simulationBudgetExceeded':sum('SIMULATION_BUDGET' in r.get('reason','') for r in result['routes']),'endpointFailures':sum(r.get('reason')=='fixed endpoint fails radius/zone/terrain' for r in result['routes']),'invalidSteps':sum(r['invalidSteps'] for r in result['routes']),'radiusViolations':sum(r['radiusViolations'] for r in result['routes']),'negativeTests':len(result['negativeTests']),'negativePassed':sum(r['pass'] for r in result['negativeTests'])}
out=DOC/'body-region-route-evidence';out.mkdir(exist_ok=True);(out/'report.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(json.dumps(result['summary']))
