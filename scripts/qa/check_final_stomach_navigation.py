"""Final user-authored gastric geometry: exact-source isolated Lua movement proof."""
from pathlib import Path
import json,hashlib,math,os
from lupa.lua54 import LuaRuntime
from shapely.geometry import Polygon,LineString
from shapely.ops import unary_union
from check_stomach_connectivity import lua,convert
R=Path(__file__).resolve().parents[2];os.chdir(R);D=R/'docs/body-life/vascular-art-study';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
source=D/'final-reference-data.json';draft=D/'user-drafts/stomach-20261010-original.json';data=json.loads(source.read_text());original=json.loads(draft.read_text());world=lambda p:[p[0]*2,p[1]*2+512]
# Both documents encode named nodes as edge endpoints; validate every incidence.
node_points={};draft_nodes={}
for e in original['edges']:
 for end,index in [('a',0),('b',-1)]:
  p=e['points'][index]
  if e[end] in draft_nodes:assert math.dist(p,draft_nodes[e[end]])<1e-6
  draft_nodes[e[end]]=p
for e in data['edges']:
 for end,index in [('a',0),('b',-1)]:
  p=e['samples'][index]
  if e[end] in node_points:assert math.dist(p,node_points[e[end]])<1e-6
  node_points[e[end]]=p
  assert e[end] in draft_nodes and math.dist(p,draft_nodes[e[end]])<1e-6,(e['id'],e[end])
ids={id:i+1 for i,id in enumerate(node_points)}
layout={'version':4,'optInOnly':True,'explicitGates':True,'sourceSha256':sha(source),'draftSha256':sha(draft),'nodes':[],'edges':[],'gates':[],'organs':[],'nodeIndexById':ids,'edgeIndexById':{}}
for id,p in node_points.items():x,y=world(p);layout['nodes'].append(dict(id=id,name=id,x=x,y=y,heart=False))
for e in data['edges']:
 layout['edgeIndexById'][e['id']]=len(layout['edges'])+1
 layout['edges'].append(dict(a=ids[e['a']],b=ids[e['b']],stableId=e['id'],name=e['id'],system=e['system'],oxygen=e['oxygen'],width=2*e['lumenWidthSource'],points=[world(p) for p in e['samples']],curved=False,layer=e['layer']))
for g in data['gates']:
 x,y=world(g['pipeCenterSource']);layout['gates'].append(dict(edge=layout['edgeIndexById'][g['edgeId']],x=x,y=y,nx=g['nx'],ny=g['ny'],name=g['id']))
organ=next(o for o in data['organs'] if o['id']=='stomach')
passages=[p for p in data['protectedPassages'] if p['id'] in ['food.esophagus','food.stomach','food.duodenum']]
footprint=unary_union([Polygon(r) for r in data['stomachFoodUnion']]+[LineString(p['points']).buffer(p['width']/2,quad_segs=12) for p in passages])
food=[[list(c) for c in p.exterior.coords] for p in getattr(footprint,'geoms',[footprint])]
layout['geometry']={'foodUnion':food,'zones':[organ],'edges':data['protectedPassages']}
layout['stomachBounds']=organ['bounds'];layout['stomachWallEdges']=[e['id'] for e in data['edges'] if e['a'].startswith('stomach.') and e['b'].startswith('stomach.')]
layout['fixedGates']=data['gates'];layout['targets']={'inner':[562,538],'outer':[614,528]};layout['footprintSources']=[p['id'] for p in passages]
fixture=R/'scripts/war/FinalVascularStudyData.lua';fixture.write_text('-- Generated solely for final stomach isolation QA; exact final samples, no runtime installation.\nreturn '+lua(layout)+'\n')
modules=['FinalVascularStudyData.lua','FinalStomachNavigationStudy.lua','OrganSortieNavigationStudy.lua','OrganRouteNavigationStudy.lua','PassageNavigationStudy.lua','OrganRouteCollisionStudy.lua','PassageCollisionStudy.lua','TissueGeometry.lua','Path.lua','Commands.lua','Workers.lua','CellCollision.lua','Vessels.lua','World.lua','OrganGateTrafficStudy.lua']
hashes={f:sha(R/'scripts/war'/f) for f in modules};source_hash=sha(source);script_hash=sha(Path(__file__))
l=LuaRuntime(unpack_returned_tuples=True);l.execute("package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={};print=function()end;package.loaded['war.ReferenceVessels']=require('war.FinalVascularStudyData')")
l.globals().progress=lambda s:print(s,flush=True)
out=convert(l.execute(r'''
local F=require('war.FinalVascularStudyData');local W,P,C,K=require('war.World'),require('war.Path'),require('war.Commands'),require('war.CellCollision')
local s=W.generate(73,nil,nil,nil,4);W.rebuild(s)
local uninstall,A=require('war.FinalStomachNavigationStudy').attachForTest(s,W,P,C)
local function world(p)return{x=p[1]*2,y=p[2]*2+512}end
local gates={};local gateChecks={};for i,g in ipairs(F.fixedGates)do
 local real=A.net.gates[i];local wall=world(g.wallSource);local center=world(g.pipeCenterSource)
 gateChecks[#gateChecks+1]={id=g.id,wallError=math.sqrt((real.x-wall.x)^2+(real.y-wall.y)^2),lumenError=math.sqrt((real.px-center.x)^2+(real.py-center.y)^2),radius=real.radius,expectedRadius=g.radius*2}
 gates[g.id:match('%.([^%.]+)$')]={inside=center,outside=world(g.tissueTargetSource),lane=real.edge,id=g.id}
end
local result={routes={},gateChecks=gateChecks,adapterStats=A.stats,foodNegatives={},targetChecks={},meeting={}}
for id,p in pairs(F.targets)do result.targetChecks[#result.targetChecks+1]={id=id,source=p,clearanceSource=A.clearance(p[1],p[2])}end
local Motion=require('war.Motion');local record=Motion.record;local segments={}
Motion.record=function(e)segments[#segments+1]={id=e.id,x=e.x,y=e.y,lane=e.vesselLane};return record(e)end
local function stage(e,target,lane,label,route)
 C.execute(s,{kind='move',faction=1,ids={e.id},x=target.x,y=target.y});e.orders[1].vesselLane=lane
 local q={id=label,targetSource={target.x/2,(target.y-512)/2},endLane=lane,invalidSteps=0,radiusViolations=0,actualSubsteps=0,arrived=false,pass=false};local began=os.clock()
 for frame=1,8000 do
  local x,y,oldLane=e.x,e.y,e.vesselLane;segments={};s.time=s.time+.05;P.update(s,500,.003);require('war.Workers').update(s,e,.05);W.rebuild(s)
  for _,p in ipairs(segments)do
   q.actualSubsteps=q.actualSubsteps+1
   if not A.geometry.sweep(s,e,x,y,p.x,p.y,oldLane,p.lane)then q.invalidSteps=q.invalidSteps+1 end
   if not A.geometry.pointAllowed(s,e,p.x,p.y,p.lane)then q.radiusViolations=q.radiusViolations+1 end
   x,y,oldLane=p.x,p.y,p.lane
  end
  if x~=e.x or y~=e.y or oldLane~=e.vesselLane then q.unrecordedMovement=true end
  route.seconds=route.seconds+.05
  if frame%5==0 or oldLane~=e.vesselLane then route.trace[#route.trace+1]={x=e.x,y=e.y,lane=e.vesselLane,t=route.seconds,stage=label}end
  if (e.x-target.x)^2+(e.y-target.y)^2<.8^2 and e.vesselLane==lane then q.arrived=true;break end
  if e.pathFailed then q.reason=A.diagnostics(e)and A.diagnostics(e).reason or 'PATH_FAILED';break end
 end
 q.cpuSeconds=os.clock()-began;q.navigation=A.diagnostics(e);q.pass=q.arrived and q.invalidSteps==0 and q.radiusViolations==0 and not q.unrecordedMovement
 if not q.pass and not q.reason then q.reason=q.arrived and 'ILLEGAL_ACTUAL_MOVEMENT' or '400_SIM_SECONDS_EXHAUSTED'end
 route.stages[#route.stages+1]=q;progress(route.kind..' '..label..' '..tostring(q.pass)..' '..(q.reason or ''));return q.pass
end
for _,kind in ipairs({'scout','siege'})do
 P.reset();s.entities={};s.nextId=1;W.rebuild(s)
 local g,h=gates.inner,gates.outer;local first=F.nodes[F.nodeIndexById['stomach.a']];local last=F.nodes[F.nodeIndexById['stomach.v']];local e=C.spawn(s,'unit',kind,1,first.x,first.y,true);e.vesselLane=g.lane;W.rebuild(s)
 local r={id='final-stomach-'..kind,kind=kind,cellRadiusWorld=K.radius(e),seconds=0,trace={{x=e.x,y=e.y,lane=e.vesselLane,t=0}},stages={}}
 local stages={{h.inside,h.lane,'supply-to-outer-gate'},{h.outside,0,'outer-outward'},{world(F.targets.outer),0,'outer-fixed-target'},{h.outside,0,'outer-return-to-gate'},{h.inside,h.lane,'outer-inward'},{g.inside,g.lane,'forward-vascular-transfer'},{g.outside,0,'inner-outward'},{world(F.targets.inner),0,'inner-fixed-target'},{g.outside,0,'inner-return-to-gate'},{g.inside,g.lane,'inner-inward'},{{x=last.x,y=last.y},g.lane,'gate-to-venous-junction'}}
 for _,z in ipairs(stages)do if not stage(e,z[1],z[2],z[3],r)then break end end
 r.pass=#r.stages==#stages and r.stages[#stages].pass;result.routes[#result.routes+1]=r
 -- Same-plane food lumen remains unavailable even if a vessel projects over it.
 for _,p in ipairs({{540,475},{580,483},{599,506},{580,550},{501,552},{500,568}})do local w=world(p);result.foodNegatives[#result.foodNegatives+1]={kind=kind,source=p,rejected=not A.geometry.pointAllowed(s,e,w.x,w.y,0)}end
end

-- The same narrow lumen cannot support mixed side-by-side passing. Test a
-- bounded membrane queue instead, using physically swept holding positions.
P.reset();s.entities={};s.nextId=1;W.rebuild(s)
local T=require('war.OrganGateTrafficStudy');local precision=T.attachPrecision(C);local g=gates.inner
local fixtures={};for i,kind in ipairs({'scout','siege'})do
 local p=i==1 and g.inside or g.outside;local lane=i==1 and g.lane or 0
 local e=C.spawn(s,'unit',kind,1,p.x,p.y,true);assert(e and e.x==p.x and e.y==p.y);e.vesselLane=lane;W.rebuild(s)
 fixtures[i]={entity=e,kind=kind,side=i==1 and 'blood'or'tissue',start={x=p.x,y=p.y,lane=lane},goals=i==1 and {{x=g.outside.x,y=g.outside.y,lane=0},{x=g.inside.x,y=g.inside.y,lane=g.lane}}or{{x=g.inside.x,y=g.inside.y,lane=g.lane},{x=g.outside.x,y=g.outside.y,lane=0}}}
end
local gate;for _,q in ipairs(A.net.gates)do if q.name==g.id then gate=q end end
local control=T.create{state=s,W=W,P=P,C=C,K=K,net=A.net,geometry=A.geometry,gate=gate,outside={x=g.outside.x,y=g.outside.y,lane=0},units=fixtures}
local meet={scenario='two opposing requests at the existing inner membrane, physically queued',trace={},illegalSubsteps=0,radiusViolations=0,overlaps=0,actualSubsteps=0,minimumSeparation=math.huge};local started=os.clock()
for frame=1,10000 do
 local now=frame*.05;s.time=s.time+.05;control:tick(now);meet.seconds=now
 if control.state=='complete'or control.state=='failed'then break end
 if os.clock()-started>35 then meet.reason='35_CPU_SECONDS_BUDGET';control:abort(meet.reason);break end
 P.update(s,500,.003)
 for _,u in ipairs(fixtures)do
  local e=u.entity;local x,y,lane=e.x,e.y,e.vesselLane;segments={};require('war.Workers').update(s,e,.05);W.rebuild(s)
  for _,p in ipairs(segments)do
   meet.actualSubsteps=meet.actualSubsteps+1
   if not A.geometry.sweep(s,e,x,y,p.x,p.y,lane,p.lane)then meet.illegalSubsteps=meet.illegalSubsteps+1 end
   if not A.geometry.pointAllowed(s,e,p.x,p.y,p.lane)then meet.radiusViolations=meet.radiusViolations+1 end
   x,y,lane=p.x,p.y,p.lane
  end
  if x~=e.x or y~=e.y or lane~=e.vesselLane then meet.illegalSubsteps=meet.illegalSubsteps+1 end
  local a,b=fixtures[1].entity,fixtures[2].entity;local margin=math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)-K.radius(a)-K.radius(b)-K.gap
  meet.minimumSeparation=math.min(meet.minimumSeparation,margin);if margin< -1e-5 then meet.overlaps=meet.overlaps+1 end
 end
 if frame%5==0 then local t={t=now,units={}};for _,u in ipairs(fixtures)do local e=u.entity;t.units[#t.units+1]={id=e.id,x=e.x,y=e.y,lane=e.vesselLane}end;meet.trace[#meet.trace+1]=t end
end
meet.state=control.state;meet.reason=meet.reason or control.reason;meet.events=control.events;meet.units={};meet.stagesPassed=0
for _,u in ipairs(fixtures)do local e=u.entity;local target=u.goals[2];local returned=(e.x-target.x)^2+(e.y-target.y)^2<.07^2 and e.vesselLane==target.lane;meet.units[#meet.units+1]={kind=u.kind,originalStages=u.originalStages,returned=returned};meet.stagesPassed=meet.stagesPassed+u.originalStages end
meet.pass=control.state=='complete'and meet.stagesPassed==4 and meet.illegalSubsteps==0 and meet.radiusViolations==0 and meet.overlaps==0
meet.sideBySide={lumenWidthWorld=A.net.edges[g.lane].width,requiredMixedWidthWorld=2*(K.radius('scout')+K.radius('siege'))+K.gap,possible=2*(K.radius('scout')+K.radius('siege'))+K.gap<=A.net.edges[g.lane].width}
result.meeting=meet;result.rasterCorrections=A.rasterCorrections()

precision();P.reset();s.entities={};s.nextId=1;W.rebuild(s)
local negatives={foodCommands={},sealedWalls={},buildings={},rejectedOldTarget={source={612,527},kind='siege',expectedReason='same-layer vessel wall clearance deficit'}}
local edge=A.net.edges[g.lane]
for _,kind in ipairs({'scout','siege'})do
 local p=world(F.targets.inner);local e=C.spawn(s,'unit',kind,1,p.x,p.y,true);e.vesselLane=0;W.rebuild(s)
 local sx,sy=e.x,e.y;C.execute(s,{kind='move',faction=1,ids={e.id},x=1198,y=1524});e.orders[1].vesselLane=0;P.request(s,e,1198,1524)
 for _=1,1000 do P.update(s,500,.003);if not e.pathPending then break end end
 negatives.foodCommands[#negatives.foodCommands+1]={kind=kind,targetSource={599,506},rejected=e.pathFailed and e.x==sx and e.y==sy,reason=A.diagnostics(e)and A.diagnostics(e).reason}
 C.execute(s,{kind='stop',faction=1,ids={e.id}})
 local found=0
 for i=20,#edge.points-20,17 do
  local a,b=edge.points[i],edge.points[i+1];local dx,dy=b[1]-a[1],b[2]-a[2];local len=math.sqrt(dx*dx+dy*dy)
  if len>1e-9 then for _,sign in ipairs({-1,1})do
   local x,y=a[1]-dy/len*5*sign,a[2]+dx/len*5*sign;local near=false
   for _,door in ipairs(A.net.gates)do if (a[1]-door.x)^2+(a[2]-door.y)^2<8^2 then near=true end end
   if not near and A.geometry.pointAllowed(s,e,a[1],a[2],g.lane)and A.geometry.pointAllowed(s,e,x,y,0)then
    negatives.sealedWalls[#negatives.sealedWalls+1]={kind=kind,fromSource={a[1]/2,(a[2]-512)/2},toSource={x/2,(y-512)/2},rejected=not A.geometry.sweep(s,e,a[1],a[2],x,y,g.lane,0)};found=found+1
   end
   if found>=2 then break end
  end end
  if found>=2 then break end
 end
 local ax,ay=p.x-.5,p.y+.5;local bx,by=p.x+1.5,p.y+.5
 local clearBefore=A.geometry.sweep(s,e,ax,ay,bx,by,0,0)
 local blocker=C.spawn(s,'building','wall',1,p.x+.5,p.y+.5,true);W.rebuild(s)
 negatives.buildings[#negatives.buildings+1]={kind=kind,clearBefore=clearBefore,rejected=not A.geometry.sweep(s,e,ax,ay,bx,by,0,0)}
 s.entities[blocker.id]=nil;W.rebuild(s)
 if kind=='siege'then
  negatives.rejectedOldTarget.rejected=not A.geometry.pointAllowed(s,e,1224,1566,0)
  negatives.rejectedOldTarget.wallMarginSource=A.net.distance(g.lane,1224,1566)/2-(edge.width/4+.7+K.radius(e)/2+.01)
 end
 s.entities={};W.rebuild(s)
end
result.negativeControls=negatives
Motion.record=record;uninstall();return result
'''))
assert all(r['trace'][0]['x']==node_points['stomach.a'][0]*2 and r['trace'][0]['y']==node_points['stomach.a'][1]*2+512 for r in out['routes']),'supply spawn moved'
assert all(p['rejected'] for p in out['negativeControls']['foodCommands'])
assert all(g['wallError']<1e-8 and g['lumenError']<1e-8 and g['radius']==g['expectedRadius'] for g in out['gateChecks'])
assert len(out['negativeControls']['sealedWalls'])==4 and all(x['rejected'] for x in out['negativeControls']['sealedWalls'])
assert all(x['clearBefore'] and x['rejected'] for x in out['negativeControls']['buildings'])
assert out['negativeControls']['rejectedOldTarget']['rejected']
assert sha(source)==source_hash and sha(Path(__file__))==script_hash
assert all(sha(R/'scripts/war'/f)==h for f,h in hashes.items())
out.update(sourceSha256=source_hash,draftSha256=sha(draft),qaScriptSha256=script_hash,testedModuleHashes=hashes,productionInstalled=False,nativeEvidence=False,coordinateSystem=data['coordinates'],fixedGates=data['gates'],targets=layout['targets'],foodFootprint={'rings':food,'sourcePassages':layout['footprintSources'],'basis':'exact final stomachFoodUnion union exact protected passage half-width buffers'},graph={'nodes':len(layout['nodes']),'edges':len(layout['edges']),'samples':sum(len(e['samples']) for e in data['edges']),'namedEndpointsValidated':True})
out['summary']={'routes':len(out['routes']),'passed':sum(r['pass'] for r in out['routes']),'stages':sum(len(r['stages']) for r in out['routes']),'stagesPassed':sum(s['pass'] for r in out['routes'] for s in r['stages']),'foodNegativesPassed':sum(p['rejected'] for p in out['foodNegatives']),'meetingPassed':out['meeting']['pass']}
p=D/'final-stomach-navigation-evidence';p.mkdir(exist_ok=True);(p/'report.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n');print(out['summary'])
