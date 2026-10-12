"""Seven declared membrane crowds, using actual Lua commands and collision.

This is an isolated acceptance harness. It never installs adapters in production.
Each membrane has six mixed-radius cells moving in both directions and returning.
Failures and stale-source evidence remain visible in the report.
"""
from pathlib import Path
import hashlib,json,os
from lupa.lua54 import LuaRuntime
from check_stomach_connectivity import lua,convert
ROOT=Path(__file__).resolve().parents[2];os.chdir(ROOT)
DOC=ROOT/'docs/body-life/vascular-art-study';OUT=DOC/'organ-route-crowd-evidence';OUT.mkdir(exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
modules=['OrganRouteCollisionStudy.lua','OrganRouteNavigationStudy.lua','PassageCollisionStudy.lua','PassageNavigationStudy.lua','StomachConnectivityStudy.lua','ReviewedVascularLayout.lua','World.lua','Path.lua','Commands.lua','Workers.lua','CellCollision.lua','Data.lua','Vessels.lua']
paths=[Path(__file__), *[ROOT/'scripts/war'/f for f in modules], *[DOC/f for f in ['interface-contract.json','passages-data.json','organ-layers.json']]]
before={str(p.relative_to(ROOT)):sha(p) for p in paths}
data=json.loads((DOC/'passages-data.json').read_text());contract=json.loads((DOC/'interface-contract.json').read_text())
layers=json.loads((DOC/'organ-layers.json').read_text())
selected={'lung_r','lung_l','brain_r','brain_l','kidney_r','kidney_l','coronary'}
fixtures=[]
for region in contract['regions']:
 if region['id'] in selected:
  fixtures.append(dict(id=region['id'],name=region['name'],zone={'brain_r':'brain','brain_l':'brain','coronary':'heart'}.get(region['id'],region['id']),gate=next(p for p in region['ports'] if p.get('exitToTissue'))))
rt=LuaRuntime(unpack_returned_tuples=True)
rt.execute("package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={};print=function()end;package.loaded['war.ReferenceVessels']=require('war.StomachConnectivityStudy')")
rt.execute('qaData='+lua(data)+';qaFixtures='+lua(fixtures)+';qaLayers='+lua(layers))
rt.globals().progress=lambda s:print(s,flush=True)
result=convert(rt.execute(r'''
local W,P,C,K=require('war.World'),require('war.Path'),require('war.Commands'),require('war.CellCollision')
local Workers=require('war.Workers');local L=require('war.StomachConnectivityStudy')
local M,N=require('war.OrganRouteCollisionStudy'),require('war.OrganRouteNavigationStudy')
local s=W.generate(73,nil,nil,nil,4);W.rebuild(s);local net=W.vessels(s);local model=M.prepare(qaData);local context={radius=0}
local unRadius=M.attachForTest(model,context,net,W);local raw=P.clear;local unNav,stats=N.attachForTest(P,C,W)
local result={scenarios={},adapterStats=stats,radiusWorld={scout=K.radius('scout'),worker=K.radius('worker'),siege=K.radius('siege')}}
local function legal(x,y,lane,kind)
 context.radius=K.radius(kind)
 return M.allowed(model,context,net,x,y,lane) and raw(s,x,y,x,y,1,lane,lane)
end
local function distance(a,b)return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)end
for _,f in ipairs(qaFixtures)do
 context.zone=f.zone;context.tissueEdges={};for _,z in ipairs(qaLayers.zones)do if z.id==f.zone then for _,id in ipairs(z.tissueWallEdges)do context.tissueEdges[assert(L.edgeIndexById[id])]=true end;for _,id in ipairs(z.extraStudyEdges)do context.tissueEdges[assert(L.edgeIndexById[id])]=true end end end;P.reset();s.entities={};s.nextId=1;W.rebuild(s)
 local lane=L.edgeIndexById[f.gate.edge];local ix,iy=f.gate.insideWorld[1],f.gate.insideWorld[2];local ox,oy=f.gate.outsideWorld[1],f.gate.outsideWorld[2]
 local length=math.sqrt((ox-ix)^2+(oy-iy)^2);local nx,ny=(ox-ix)/length,(oy-iy)/length;local tx,ty=-ny,nx
 local r={id=f.id,name=f.name,zone=f.zone,originalGate=f.gate.id,edge=f.gate.edge,units={},pass=false,illegalMoves=0,radiusViolations=0,overlapObservations=0,maxOverlapWorld=0,minSeparationMarginWorld=math.huge,trace={},dt=.05,timeoutSeconds=90}
 local list={};local positions={blood={},tissue={}};local failed=false
 local function place(kind,side,index)
  local baseX,baseY=side=='blood' and ix or ox,side=='blood' and iy or oy;local desiredLane=side=='blood' and lane or 0
  local preferred=(index-2)*3;local candidates={}
  for along=-8,8,.5 do for depth=0,5,.5 do
   local x,y=baseX+tx*along+nx*depth,baseY+ty*along+ny*depth
   if side=='blood'then local _,px,py=net.distance(lane,x,y);x,y=px,py end
   candidates[#candidates+1]={x=x,y=y,score=(along-preferred)^2+depth*depth*2}
  end end
  table.sort(candidates,function(a,b)return a.score<b.score end)
  for _,p in ipairs(candidates)do
   if legal(p.x,p.y,desiredLane,kind) and K.free(list,{id=-1,kind=kind},p.x,p.y)then
    local e=C.spawn(s,'unit',kind,1,p.x,p.y,true)
    if not e or math.abs(e.x-p.x)>1e-8 or math.abs(e.y-p.y)>1e-8 then return nil,'actual spawn rejected or relocated'end
    e.vesselLane=desiredLane;list[#list+1]=e;W.rebuild(s)
    return {entity=e,start={x=p.x,y=p.y,lane=desiredLane},kind=kind,side=side,index=index,phase=1,completedStages=0,observedOutward=0,observedInward=0,invalidSteps=0,radiusViolations=0}
   end
  end
  return nil,'no nonoverlapping legal start among fixed local placement candidates'
 end
 local kinds={'siege','worker','scout'}
 for _,side in ipairs({'blood','tissue'})do for index,kind in ipairs(kinds)do
  local u,reason=place(kind,side,index)
  if not u then r.reason=side..' '..kind..': '..reason;failed=true;break end
  positions[side][index]=u;r.units[#r.units+1]=u
 end;if failed then break end end
 local function issue(u)
  local e=u.entity;local g=u.goals[u.phase];context.radius=K.radius(e)
  C.execute(s,{kind='move',faction=1,ids={e.id},x=g.x,y=g.y});e.orders[1].vesselLane=g.lane
 end
 local function checkMove(u,x,y,oldLane,tag)
  local e=u.entity;context.radius=K.radius(e)
  if not raw(s,x,y,e.x,e.y,1,oldLane,e.vesselLane)then r.illegalMoves=r.illegalMoves+1;u.invalidSteps=u.invalidSteps+1;if not r.firstIllegal then r.firstIllegal={unit=e.id,from={x,y,oldLane},to={e.x,e.y,e.vesselLane},tag=tag,time=r.seconds}end end
  if not M.allowed(model,context,net,e.x,e.y,e.vesselLane)then r.radiusViolations=r.radiusViolations+1;u.radiusViolations=u.radiusViolations+1 end
  if oldLane>0 and e.vesselLane==0 then u.observedOutward=u.observedOutward+1 end
  if oldLane==0 and e.vesselLane>0 then u.observedInward=u.observedInward+1 end
 end
 local function checkPairs()
  for a=1,#list do for b=a+1,#list do local margin=distance(list[a],list[b])-K.radius(list[a])-K.radius(list[b])-K.gap
   r.minSeparationMarginWorld=math.min(r.minSeparationMarginWorld,margin)
   if margin<-.00001 then r.overlapObservations=r.overlapObservations+1;r.maxOverlapWorld=math.max(r.maxOverlapWorld,-margin)end
  end end
 end
 local function trace(t)
  local frame={t=t,units={}};for _,u in ipairs(r.units)do local e=u.entity;frame.units[#frame.units+1]={id=e.id,x=e.x,y=e.y,lane=e.vesselLane,phase=u.phase}end;r.trace[#r.trace+1]=frame
 end
 if not failed then
  for _,u in ipairs(r.units)do local other=positions[u.side=='blood' and 'tissue' or 'blood'][u.index];u.goals={other.start,u.start};issue(u)end
  checkPairs();trace(0)
  for frame=1,1800 do
   s.time=s.time+.05;r.seconds=frame*.05
   -- One expansion at a time keeps each queued A* job on its own cell radius.
   for _=1,96 do if #P.jobs==0 then break end
    if P.cursor>#P.jobs then P.cursor=1 end;local job=P.jobs[P.cursor];local e=s.entities[job.id];context.radius=K.radius(e)
    P.update(s,1)
   end
   for _,u in ipairs(r.units)do local e=u.entity;local x,y,l=e.x,e.y,e.vesselLane
    context.radius=K.radius(e);if u.phase<=2 then Workers.update(s,e,.05)end
    W.rebuild(s);checkMove(u,x,y,l,'worker');checkPairs()
   end
   local before={};for _,u in ipairs(r.units)do local e=u.entity;before[e.id]={e.x,e.y,e.vesselLane}end
   -- CellCollision.resolve may process any pair; recover that specific body's
   -- radius at each real Path.clear call without changing collision behavior.
   local normalClear=P.clear
   P.clear=function(state,x,y,dx,dy,faction,oldLane,...)
    local found=false
    for _,e in ipairs(list)do if math.abs(e.x-x)<1e-8 and math.abs(e.y-y)<1e-8 and e.vesselLane==oldLane then context.radius=K.radius(e);found=true;break end end
    if not found then context.radius=K.maxRadius end
    return normalClear(state,x,y,dx,dy,faction,oldLane,...)
   end
   K.resolve(s,list);P.clear=normalClear;W.rebuild(s)
   for _,u in ipairs(r.units)do local p=before[u.entity.id];checkMove(u,p[1],p[2],p[3],'resolve')end
   checkPairs();local complete=0
   for _,u in ipairs(r.units)do if u.phase<=2 then local e=u.entity;local g=u.goals[u.phase]
    if (e.x-g.x)^2+(e.y-g.y)^2<.8*.8 and e.vesselLane==g.lane then u.completedStages=u.completedStages+1;u.phase=u.phase+1;if u.phase<=2 then issue(u)else e.orders={}end end
   end;if u.phase>2 then complete=complete+1 end end
   r.completedUnits=complete
   if frame%10==0 then trace(r.seconds)end
   if complete==6 then break end
  end
  trace(r.seconds)
  r.completedStages=0
  for _,u in ipairs(r.units)do u.pass=u.completedStages==2 and u.observedOutward>=1 and u.observedInward>=1 and u.invalidSteps==0 and u.radiusViolations==0;r.completedStages=r.completedStages+u.completedStages end
  r.pass=r.completedUnits==6 and r.illegalMoves==0 and r.radiusViolations==0 and r.overlapObservations==0
  if not r.pass then r.reason=r.completedUnits~=6 and 'mixed crowd did not finish return within 90s' or 'illegal step, radius violation or overlapping cell disks'end
 end
 for _,u in ipairs(r.units)do local e=u.entity;u.endState={id=e.id,x=e.x,y=e.y,lane=e.vesselLane,pathFailed=e.pathFailed or false,pathPending=e.pathPending or false};u.entity=nil end
 if r.minSeparationMarginWorld==math.huge then r.minSeparationMarginWorld=false end
 result.scenarios[#result.scenarios+1]=r;progress(f.id..' '..tostring(r.pass)..' completed='..tostring(r.completedUnits or 0)..' illegal='..r.illegalMoves..' radius='..r.radiusViolations..' overlap='..r.overlapObservations..' '..(r.reason or ''))
end
unNav();unRadius();return result
'''))
after={str(p.relative_to(ROOT)):sha(p) for p in paths}
result.update(productionInstalled=False,nativeEvidence=False,seed=73,sourceHashesBefore=before,sourceHashesAfter=after,sourceStable=before==after,qaScriptSha256=sha(Path(__file__)),scope='Seven original organ membrane gates only, six simultaneous mixed-radius cells per gate, opposite-side exchange and return, using explicit organ-layers tissue-wall contract; not whole-body crowd acceptance',limitations=['Placement samples legal fixed neighborhoods of original gates; it does not move gates or vessel points.','A* budget is deterministic 96 one-expansion calls per frame to bind per-unit radii; this is not a native performance test.','All six units share faction 1 and receive individual actual move commands; this tests bidirectional transit, not combat or formations.','Brain boundaries remain coarse locator; bone geometry is not added by this harness.','All failed starts, timeouts, overlap observations and illegal movements are retained.'])
result['summary']={'scenarios':len(result['scenarios']),'passed':sum(bool(r['pass']) for r in result['scenarios']),'spawnedUnits':sum(len(r['units']) for r in result['scenarios']),'completedUnits':sum(r.get('completedUnits',0) for r in result['scenarios']),'stagesCompleted':sum(r.get('completedStages',0) for r in result['scenarios']),'illegalMoves':sum(r['illegalMoves'] for r in result['scenarios']),'radiusViolations':sum(r['radiusViolations'] for r in result['scenarios']),'overlapObservations':sum(r['overlapObservations'] for r in result['scenarios'])}
result['status']='STALE_SOURCE_DO_NOT_ACCEPT' if not result['sourceStable'] else 'PASS_SCOPED_MIXED_CROWDS' if result['summary']['passed']==len(fixtures) else 'RETAINED_CROWD_FAILURES'
(OUT/'report.json').write_text(json.dumps(result,ensure_ascii=False,indent=2,allow_nan=False)+'\n')
print(result['status'],result['summary'],flush=True)
