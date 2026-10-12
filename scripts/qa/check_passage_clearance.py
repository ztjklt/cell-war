"""Actual Lua movement with an isolated disk-clearance filter; no production switch."""
from pathlib import Path
import json,os,hashlib,math
from lupa.lua54 import LuaRuntime
from check_stomach_connectivity import lua,convert
ROOT=Path(__file__).resolve().parents[2];os.chdir(ROOT);DOC=ROOT/'docs/body-life/vascular-art-study';OUT=DOC/'clearance-evidence';OUT.mkdir(exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();data=json.loads((DOC/'passages-data.json').read_text())
for f,h in data['sourceHashes'].items():assert sha(DOC/f)==h,'stale '+f
net=data['network'];nodes={n['id']:[n['x'],n['y']] for n in net['nodes']}
def from_node(e,id,d=3):
 pts=e['points'] if e['a']==id else e['points'][::-1];left=d
 for a,b in zip(pts,pts[1:]):
  length=math.dist(a,b)
  if length>=left:return [a[i]+(b[i]-a[i])*left/length for i in range(2)]
  left-=length
 return pts[-1]
cases=[]
for conflict in data['portConflicts']:
 port=conflict['port'];incident=[e for e in net['edges'] if port in [e['a'],e['b']]]
 assert len(incident)==2,(port,len(incident))
 a,b=incident;cases.append(dict(id=port,passage=conflict['passage'],source=conflict['source'],a=from_node(a,port),b=from_node(b,port),edgeA=a['id'],edgeB=b['id']))
rt=LuaRuntime(unpack_returned_tuples=True);rt.execute("package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={};print=function()end;package.loaded['war.ReferenceVessels']=require('war.StomachConnectivityStudy')")
rt.execute('qaData='+lua(data)+';qaCases='+lua(cases))
result=convert(rt.execute(r'''
 local M=require('war.PassageCollisionStudy');local model=M.prepare(qaData)
 local W,P,C,K=require('war.World'),require('war.Path'),require('war.Commands'),require('war.CellCollision')
 local L=require('war.StomachConnectivityStudy');local s=W.generate(73,nil,nil,nil,4);W.rebuild(s);local net=W.vessels(s)
 local context={radius=0};local restore=M.attachForTest(model,context,net)
 local out={portTests={},tissueTests={},radiusNegativeTests={},clearanceSurveys={},sizes={},portBaseline={},repairTests={},cellSystemsUnchanged=true}
 local kinds={'scout','worker','siege'}
 for _,kind in ipairs(kinds)do out.sizes[#out.sizes+1]={kind=kind,radiusWorld=K.radius(kind),radiusSource=K.radius(kind)/2}end
 local function reset()P.reset();s.entities={};s.nextId=1;W.rebuild(s)end
 local function move(id,kind,a,b,la,lb,allowReplan)
  reset();context.radius=K.radius(kind)
  local ax,ay,bx,by=a[1]*2,a[2]*2+512,b[1]*2,b[2]*2+512
  local startLegal=M.allowed(model,context,net,ax,ay,la) and P.clear(s,ax,ay,ax,ay,1,la,la)
  local endLegal=M.allowed(model,context,net,bx,by,lb) and P.clear(s,bx,by,bx,by,1,lb,lb)
  local result={id=id,kind=kind,fromSource=a,toSource=b,startLane=la,endLane=lb,startLegal=not not startLegal,endLegal=not not endLegal,arrived=false,invalidSteps=0,trace={},radiusViolations=0}
  if not startLegal or not endLegal then result.reason='endpoint fails disk/terrain clearance';return result end
  result.directSegmentClear=not not P.clear(s,ax,ay,bx,by,1,la,lb)
  result.gridStartClear=not not P.clear(s,math.floor(ax)+.5,math.floor(ay)+.5,math.floor(ax)+.5,math.floor(ay)+.5,1,la,la)
  result.gridGoalClear=not not P.clear(s,math.floor(bx)+.5,math.floor(by)+.5,math.floor(bx)+.5,math.floor(by)+.5,1,lb,lb)
  local e=C.spawn(s,'unit',kind,1,ax,ay,true)
  if not e or math.abs(e.x-ax)>1e-8 or math.abs(e.y-ay)>1e-8 then result.reason='spawn rejected or relocated';return result end
  e.vesselLane=la;W.rebuild(s);C.execute(s,{kind='move',faction=1,ids={e.id},x=bx,y=by})
  result.trace={{t=0,x=e.x,y=e.y,lane=la}};result.replans={};local stalled=0
  for frame=1,1400 do
   local x,y,lane=e.x,e.y,e.vesselLane;s.time=s.time+.05;P.update(s,700);require('war.Workers').update(s,e,.05);W.rebuild(s)
   if not P.clear(s,x,y,e.x,e.y,1,lane,e.vesselLane) then result.invalidSteps=result.invalidSteps+1 end
   if not M.allowed(model,context,net,e.x,e.y,e.vesselLane)then result.radiusViolations=result.radiusViolations+1 end
   if frame%4==0 or lane~=e.vesselLane then result.trace[#result.trace+1]={t=frame*.05,x=e.x,y=e.y,lane=e.vesselLane}end
   result.seconds=frame*.05
   if (e.x-x)^2+(e.y-y)^2<1e-10 then stalled=stalled+1 else stalled=0 end
   if allowReplan and stalled>=30 and #result.replans<2 then
    P.reset();C.execute(s,{kind='move',faction=1,ids={e.id},x=bx,y=by});result.replans[#result.replans+1]={t=frame*.05,x=e.x,y=e.y};stalled=0
   end
   if (e.x-bx)^2+(e.y-by)^2<.8*.8 and e.vesselLane==lb then result.arrived=true;break end
   if e.pathFailed then result.reason='actual A* failed';break end
  end
  result.trace[#result.trace+1]={t=result.seconds,x=e.x,y=e.y,lane=e.vesselLane}
  result.pass=result.arrived and result.invalidSteps==0 and result.radiusViolations==0
  if not result.pass and not result.reason then result.reason='movement did not arrive within 70 seconds';result.stalledPath=e.path;result.stalledPathIndex=e.pathIndex end
  return result
 end
 for _,c in ipairs(qaCases)do context.zone=nil
  for _,kind in ipairs(kinds)do
   for _,rev in ipairs({false,true})do
    local a,b,la,lb=c.a,c.b,L.edgeIndexById[c.edgeA],L.edgeIndexById[c.edgeB]
    if rev then a,b,la,lb=b,a,lb,la end
    local t=move(c.id..(rev and '.reverse' or '.forward'),kind,a,b,la,lb);t.port=c.id;t.passage=c.passage;out.portTests[#out.portTests+1]=t
   end
  end
 end
 -- Control uses unmodified real options. Disk violations remain visible in its report.
 restore()
 for _,t in ipairs(out.portTests)do
  local control=move(t.id,t.kind,t.fromSource,t.toSource,t.startLane,t.endLane)
  out.portBaseline[#out.portBaseline+1]=control
 end
 restore=M.attachForTest(model,context,net)
 for _,t in ipairs(out.portTests)do if not t.pass then
  local repair=move(t.id,t.kind,t.fromSource,t.toSource,t.startLane,t.endLane,true)
  repair.port=t.port;repair.passage=t.passage;repair.policy='at most two real move-order replans after 1.5 seconds without progress; no relocation or wall relaxation'
  out.repairTests[#out.repairTests+1]=repair
 end end
 for _,z in ipairs(qaData.zones)do
  context.zone=z.id;local x0,y0,x1,y1=math.huge,math.huge,-math.huge,-math.huge
  for _,ring in ipairs(z.outlines)do for _,p in ipairs(ring.points)do x0=math.min(x0,p[1]);y0=math.min(y0,p[2]);x1=math.max(x1,p[1]);y1=math.max(y1,p[2])end end
  local samples={};local counts={0,0,0};local narrow
  for y=math.ceil(y0),math.floor(y1),2 do for x=math.ceil(x0),math.floor(x1),2 do
   local margin=M.clearance(model,z.id,x,y)
   if margin>=0 then
    samples[#samples+1]={x=x,y=y,clearance=margin}
    for i,kind in ipairs(kinds)do if margin>=K.radius(kind)/2+math.sqrt(2)/16+.02 then counts[i]=counts[i]+1 end end
    if not narrow and margin>.09 and margin<K.radius('siege')/2+.02 then narrow={x,y,margin}end
   end
  end end
  table.sort(samples,function(a,b)return a.clearance>b.clearance end)
  out.clearanceSurveys[#out.clearanceSurveys+1]={id=z.id,name=z.name,gridSource=2,tissueSamples=#samples,scoutFit=counts[1],workerFit=counts[2],siegeFit=counts[3],note='geometric candidate only; not connected-component or crowd acceptance'}
  if narrow then
   context.radius=0;local point=M.allowed(model,context,net,narrow[1]*2,narrow[2]*2+512,0)
   context.radius=K.radius('siege');local disk=M.allowed(model,context,net,narrow[1]*2,narrow[2]*2+512,0)
   out.radiusNegativeTests[#out.radiusNegativeTests+1]={id=z.id,source={narrow[1],narrow[2]},clearanceSource=narrow[3],pointFits=point,siegeBlocked=not disk,geometricPointFits=narrow[3]>=.02,geometricSiegeBlocked=narrow[3]<K.radius('siege')/2+.02,pass=narrow[3]>=.02 and narrow[3]<K.radius('siege')/2+.02,note='geometry-only negative; pointFits separately includes existing vessel walls'}
  end
  for _,kind in ipairs(kinds)do
   context.radius=K.radius(kind);local pair
   for i=1,math.min(500,#samples)do local p=samples[i];local a={p.x,p.y}
    if #net.sample(a[1]*2,a[2]*2+512).lanes==0 and M.allowed(model,context,net,a[1]*2,a[2]*2+512,0) and P.clear(s,a[1]*2,a[2]*2+512,a[1]*2,a[2]*2+512,1,0,0) then
     for _,offset in ipairs({{4,0},{0,4},{-4,0},{0,-4}})do local b={a[1]+offset[1],a[2]+offset[2]}
      if M.allowed(model,context,net,b[1]*2,b[2]*2+512,0) and P.clear(s,a[1]*2,a[2]*2+512,b[1]*2,b[2]*2+512,1,0,0)then pair={a,b};break end
     end
    end
    if pair then break end
   end
   if pair then for _,rev in ipairs({false,true})do local a,b=pair[1],pair[2];if rev then a,b=b,a end
    local t=move(z.id..(rev and '.reverse' or '.forward'),kind,a,b,0,0);t.zone=z.id;t.name=z.name;out.tissueTests[#out.tissueTests+1]=t
   end else out.tissueTests[#out.tissueTests+1]={id=z.id,zone=z.id,kind=kind,arrived=false,pass=false,reason='no short direct tissue sample in first 500 high-clearance grid points'}end
  end
 end
 restore();return out
'''))
result.update(sourcePassagesSha256=sha(DOC/'passages-data.json'),nativeEvidence=False,productionInstalled=False,scope='Actual Lua path/movement with opt-in radius filter; local samples only')
def distance(p,a,b):
 dx,dy=b[0]-a[0],b[1]-a[1];t=max(0,min(1,((p[0]-a[0])*dx+(p[1]-a[1])*dy)/(dx*dx+dy*dy or 1)))
 return math.dist(p,[a[0]+dx*t,a[1]+dy*t])
edges={e['id']:e for e in data['edges']};radii={r['kind']:r['radiusSource'] for r in result['sizes']}
for t in result['portTests']:
 e=edges[t['passage']];t['projectedDiskOverlapSamples']=sum(min(distance([p['x']/2,(p['y']-512)/2],a,b) for a,b in zip(e['points'],e['points'][1:]))<=e['width']/2+radii[t['kind']] for p in t['trace'])
result['summary']={k:dict(total=len(result[k]),passed=sum(bool(t.get('pass')) for t in result[k])) for k in ['portTests','tissueTests','radiusNegativeTests']}
result['baselineArrivals']=sum(t['arrived'] for t in result['portBaseline'])
result['repairSummary']=dict(total=len(result['repairTests']),passed=sum(bool(t.get('pass')) for t in result['repairTests']))
result['qaScriptSha256']=sha(Path(__file__))
result['testedModuleHashes']={f:sha(ROOT/'scripts/war'/f) for f in ['PassageCollisionStudy.lua','World.lua','Path.lua','Vessels.lua','Workers.lua','Commands.lua','CellCollision.lua','Data.lua','StomachConnectivityStudy.lua']}
result['limitations']=['Radius sweeps reserve sqrt(2)/8 world for Path.trace sampling; tissue also respects existing vessel walls and eroded gate apertures.','Only six selected blood port neighborhoods and short organ tissue samples; not complete organ-to-organ routes.','Each test has one cell and one radius context; this filter is not a mixed-unit production integration.','Candidate tissue excludes owned passage disks and organ exterior; missing bones and cells on other depth planes remain out of scope.','Failures are retained. Geometric grid sample counts are not navigable area percentages or connectivity proof.','No native visual, GPU performance or crowd acceptance.']
result['status']='ISOLATED_RADIUS_REVIEW_WITH_RETAINED_FAILURES' if any(v['passed']<v['total'] for v in result['summary'].values()) else 'PASS_SCOPED_ISOLATED_RADIUS_TESTS'
(OUT/'report.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(json.dumps(result['summary']),flush=True)
print('baseline',result['baselineArrivals'],'repairs',result['repairSummary'])
for group in ['portTests','tissueTests','repairTests']:
 for t in result[group]:
  if not t.get('pass'):print(group,t['id'],t['kind'],t.get('reason'))
assert not any(t.get('invalidSteps',0) or t.get('radiusViolations',0) for group in ['portTests','tissueTests'] for t in result[group]),'illegal actual movement'
