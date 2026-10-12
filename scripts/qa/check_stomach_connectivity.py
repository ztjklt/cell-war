"""Test explicit local gastric access additions using unchanged real game navigation.

No production module, reviewed network, food geometry or previous report is edited.
"""
from pathlib import Path
import hashlib,json,math,os
from lupa.lua54 import LuaRuntime,lua_type
ROOT=Path(__file__).resolve().parents[2];os.chdir(ROOT)
DOC=ROOT/'docs/body-life/vascular-art-study';OUT=DOC/'connectivity-evidence'

def lua(v):
 if isinstance(v,bool):return str(v).lower()
 if isinstance(v,(int,float)):return repr(v)
 if isinstance(v,str):return json.dumps(v,ensure_ascii=False)
 if isinstance(v,list):return '{'+','.join(map(lua,v))+'}'
 return '{'+','.join('['+lua(k)+']='+lua(x) for k,x in v.items())+'}'
def convert(v):
 if lua_type(v)!='table':return v
 keys=list(v.keys())
 if keys and all(isinstance(k,int) for k in keys):return [convert(v[i]) for i in range(1,len(keys)+1)]
 return {k:convert(x) for k,x in v.items()}
def inside(p,poly):
 x,y=p;hit=False
 for a,b in zip(poly,poly[1:]+poly[:1]):
  if (a[1]>y)!=(b[1]>y) and x<(b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0]:hit=not hit
 return hit

def render_and_project(out,gates):
 import render_body_life as r
 b=r.b
 b.l.execute("package.loaded['war.ReferenceVessels']=require('war.StomachConnectivityStudy')")
 r.initialise()
 b.l.execute("""
 local A=require('war.ReferenceArt');local original=A.draw
 local Study=require('war.StomachBattlefieldStudy');local Connectivity=require('war.StomachConnectivityStudy')
 A.draw=function(...) original(...);Study.draw(...);Connectivity.drawStudy(...) end
 local C=require('war.Commands');local W=require('war.World')
 for _,p in ipairs({{'scout',550,518},{'worker',557,533},{'scout',578,515},{'worker',612,523},{'spear',563,507}})do
  local e=C.spawn(state,'unit',p[1],1,p[2]*2,p[3]*2+512,true);assert(e,'render cell spawn rejected')
 end
 W.rebuild(state);qaSave=require('war.Save').snapshot(state);qaVisible={}
 for i,f in ipairs(state.factions)do qaVisible[i]=require('war.Util').copy(f.visible)end
 function qaSame(a,b)
  if type(a)~=type(b)then return false end;if type(a)~='table'then return a==b end
  for k,v in pairs(a)do if not qaSame(v,b[k])then return false end end
  for k in pairs(b)do if a[k]==nil then return false end end;return true
 end
 """)
 b.l.execute('qaPorts='+lua([p for g in gates for p in [g['source'],g['insideSource'],g['outsideSource']]]))
 z=.15;w,h=1100,800;sx,sy=577.5,517.5
 b.reset();b.l.execute(f"graphics={{GetWidth=function()return {w} end,GetHeight=function()return {h} end,GetDPR=function()return 1 end}};game.zoom={z};game.camera={{x={sx*2},y={sy*2+512-.03*h/(32*z)}}};game.realTime=1.92;R.draw(game);assert(qaSame(qaSave,require('war.Save').snapshot(state)))")
 name='stomach-connectivity-0.15.png';(out/name).write_bytes(b.png(w,h))
 records=[]
 for w,h in [(1440,900),(1024,768),(844,390),(430,932),(360,780)]:
  for dpr in [1,2,3]:
   for z in [.085,.12,.149,.15,.151]:
    b.reset();b.l.execute(f"""graphics={{GetWidth=function()return {w*dpr} end,GetHeight=function()return {h*dpr} end,GetDPR=function()return {dpr} end}};game.zoom={z};game.camera={{x={sx*2},y={sy*2+512}}};R.draw(game)
    assert(R.w=={w} and R.h=={h});assert(qaSame(qaSave,require('war.Save').snapshot(state)))
    for i,f in ipairs(state.factions)do assert(qaSame(qaVisible[i],f.visible),'draw changed visibility')end
    qaError=0;for _,p in ipairs(qaPorts)do local wx,wy=p[1]*2,p[2]*2+512;local x,y=R.project(game,wx,wy);local xx,yy=R.unproject(game,x,y)
     qaError=math.max(qaError,math.abs(xx-wx),math.abs(yy-wy))
     local expectedX={w}*.5+(wx-game.camera.x)*32*game.zoom;local expectedY={h}*.47+(wy-game.camera.y)*32*game.zoom
     qaError=math.max(qaError,math.abs(x-expectedX),math.abs(y-expectedY))
    end;assert(qaError<1e-8)
    """)
    records.append(dict(size=[w,h],dpr=dpr,zoom=z,ports=12,maxError=b.G.qaError,saveUnchanged=True,visibilityUnchanged=True))
 return dict(previewFiles=[name],projection=records,renderBackend='Actual Lua Render + stomach study + connectivity additions evaluated by SVG/Cairo; not native GPU',renderedUnitCount=5)

def main():
 pilotPath=DOC/'stomach-pilot.json';pilot=json.loads(pilotPath.read_text());old=json.loads((DOC/'stomach-evidence/report.json').read_text())
 assert pilot['sourceNetworkSha256']==hashlib.sha256((ROOT/'docs/body-life/vascular-sketch/whole-body/network.json').read_bytes()).hexdigest(),'network baseline stale'
 assert old['sourcePilotSha256']==hashlib.sha256(pilotPath.read_bytes()).hexdigest(),'pilot baseline stale'
 oldCases=[dict(id=t['id'],label=t['label'],fromSource=t['fromSource'],toSource=t['toSource'],expected=t['expected'],lane=t['trace'][0]['lane'],goalLane=t['trace'][-1]['lane'],regression=True) for t in old['movementTests']]
 new=[]
 for id,label,a,b in [('wall-left','左右胃组织通过受控门互通',[550,518],[557,533]),('cavity-detour','胃腔两侧经深层血管连接',[578,515],[612,523])]:
  for direction,aa,bb in [('forward',a,b),('reverse',b,a)]:new.append(dict(id=id+'.'+direction,label=label+(' · 去程' if direction=='forward' else ' · 回程'),fromSource=aa,toSource=bb,expected='arrived',lane=0,goalLane=0,regression=False))
 for t in old['movementTests']:
  if t['arrived']:
   oldCases.append(dict(id=t['id']+'.reverse-regression',label=t['label']+' · 反向回归',fromSource=t['toSource'],toSource=t['fromSource'],expected=t['expected'],lane=t['trace'][-1]['lane'],goalLane=t['trace'][0]['lane'],regression=True))
 rt=LuaRuntime(unpack_returned_tuples=True)
 rt.execute("package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={};print=function()end;package.loaded['war.ReferenceVessels']=require('war.StomachConnectivityStudy')")
 rt.execute('qaCases='+lua(new+oldCases));rt.globals().qaPilotHash=hashlib.sha256(pilotPath.read_bytes()).hexdigest()
 report=convert(rt.execute(r'''
 local L=require('war.StomachConnectivityStudy');local Base=require('war.ReviewedVascularLayout')
 local W,P,C,U=require('war.World'),require('war.Path'),require('war.Commands'),require('war.Util')
 local Study=require('war.StomachBattlefieldStudy');assert(Study.data.sourcePilotSha256==qaPilotHash,'study data stale');local s=W.generate(73,nil,nil,nil,4);W.rebuild(s);local net=W.vessels(s)
 local function same(a,b)
  if type(a)~=type(b)then return false end;if type(a)~='table'then return a==b end
  for k,v in pairs(a)do if not same(v,b[k])then return false end end
  for k in pairs(b)do if a[k]==nil then return false end end;return true
 end
 for i,n in ipairs(Base.nodes)do assert(same(n,L.nodes[i]),'base node changed')end
 for i,e in ipairs(Base.edges)do assert(same(e,L.edges[i]),'base edge changed')end
 for i,g in ipairs(Base.gates)do assert(same(g,L.gates[i]),'base gate changed')end
 local originalLand=W.land;local foodGrid={}
 W.land=function(state,x,y)
  if not originalLand(state,x,y)then return false end
  local key=x..':'..y;local food=foodGrid[key]
  if food==nil then food=Study.containsFoodSource((x+.5)/2,(y+.5-512)/2);foodGrid[key]=food end
  if not food then return true end
  return #W.vessels(state).sample(x+.5,y+.5).lanes>0
 end
 local report={additions={gates={},edges=L.studyAdditions.edges},movementTests={},gateChecks={},sealedWallChecks={},endpointChecks={},basePreserved=true}
 local function food(x,y)return Study.containsFoodSource(x/2,(y-512)/2)end
 local function endpoint(p)
  local x,y=p[1]*2,p[2]*2+512;local sample=net.sample(x,y)
  return {source=p,tissue=Study.containsTissueSource(p[1],p[2]),food=food(x,y),land=W.land(s,math.floor(x),math.floor(y)),lane0Legal=P.clear(s,x,y,x,y,1,0,0),lanes=sample.lanes}
 end
 for _,p in ipairs({{550,518},{557,533},{578,515},{612,523}})do report.endpointChecks[#report.endpointChecks+1]=endpoint(p)end
 for _,spec in ipairs(L.studyAdditions.gates)do
  local g=net.gates[spec.gateIndex];local e=net.edges[g.edge]
  local ox,oy=g.px+g.nx*(e.width*.5+6),g.py+g.ny*(e.width*.5+6)
  local entry,entryLane=P.clear(s,ox,oy,g.px,g.py,1,0,g.edge)
  local exit,exitLane=P.clear(s,g.px,g.py,ox,oy,1,g.edge,0)
  report.additions.gates[#report.additions.gates+1]={id=spec.id,edgeId=spec.edgeId,source={g.x/2,(g.y-512)/2},insideSource={g.px/2,(g.py-512)/2},outsideSource={ox/2,(oy-512)/2},normal={g.nx,g.ny},radiusSource=g.radius/2,experimental=true,reason=spec.reason}
  report.gateChecks[#report.gateChecks+1]={id=spec.id,entry=entry and entryLane==g.edge,exit=exit and exitLane==0,membraneOutsideFood=not food(g.x,g.y),tissueOutsideFood=not food(ox,oy)}
 end
 local function test(case)
  P.reset();s.entities={};s.nextId=1;W.rebuild(s)
  local ax,ay=case.fromSource[1]*2,case.fromSource[2]*2+512;local bx,by=case.toSource[1]*2,case.toSource[2]*2+512
  local e=C.spawn(s,'unit','scout',1,ax,ay,true)
  assert(e,'spawn rejected '..case.id);assert(math.abs(e.x-ax)<1e-8 and math.abs(e.y-ay)<1e-8,'spawn relocated '..case.id);e.vesselLane=case.lane;W.rebuild(s)
  local direct=P.clear(s,ax,ay,bx,by,1,e.vesselLane)
  assert(C.execute(s,{kind='move',faction=1,ids={e.id},x=bx,y=by}),'move rejected')
  local trace={{t=0,x=e.x,y=e.y,lane=e.vesselLane}};local invalid,foodSteps,foodVesselSteps,frames,travel,transitions=0,0,0,0,0,{}
  for frame=1,4800 do
   local x,y,lane=e.x,e.y,e.vesselLane;s.time=s.time+.05;P.update(s,1000);require('war.Workers').update(s,e,.05);W.rebuild(s);frames=frame
   if not P.clear(s,x,y,e.x,e.y,1,lane,e.vesselLane)then invalid=invalid+1 end
   if food(e.x,e.y)then if e.vesselLane==0 then foodSteps=foodSteps+1 else foodVesselSteps=foodVesselSteps+1 end end
   if lane~=e.vesselLane then transitions[#transitions+1]={t=frame*.05,from=lane,to=e.vesselLane,source={e.x/2,(e.y-512)/2}}end
   travel=travel+math.sqrt((e.x-x)^2+(e.y-y)^2)
   if frame%4==0 or lane~=e.vesselLane then trace[#trace+1]={t=frame*.05,x=e.x,y=e.y,lane=e.vesselLane}end
   if (e.x-bx)^2+(e.y-by)^2<.8*.8 or e.pathFailed then break end
  end
  trace[#trace+1]={t=frames*.05,x=e.x,y=e.y,lane=e.vesselLane}
  local arrived=(e.x-bx)^2+(e.y-by)^2<.8*.8 and e.vesselLane==case.goalLane
  local expected=case.expected;local pass=invalid==0 and foodSteps==0
  if expected=='blocked'then pass=pass and not arrived and e.pathFailed else pass=pass and arrived end
  if expected=='detour'then pass=pass and not direct end
  if case.id:find('cavity%-detour')then pass=pass and foodVesselSteps>0 end
  return {id=case.id,label=case.label,expected=expected,regression=case.regression,fromSource=case.fromSource,toSource=case.toSource,arrived=arrived,pass=pass,directClear=direct,invalidSteps=invalid,foodTissueSteps=foodSteps,foodVesselSteps=foodVesselSteps,pathFailed=e.pathFailed or false,trace=trace,transitions=transitions,seconds=frames*.05,travel=travel,finalLane=e.vesselLane}
 end
 for _,case in ipairs(qaCases)do report.movementTests[#report.movementTests+1]=test(case)end
 -- Cross a tube away from any declared membrane; no global wall relaxation.
 for _,q in ipairs({{id='portal-wall-away-from-door',edge='e184',p={549.752,525.561},n={15/math.sqrt(1066),-29/math.sqrt(1066)}},{id='service-wall-away-from-door',edge='study.stomach.wall_service',p={581,530.375},n={0,-1}}})do
  local id=L.edgeIndexById[q.edge];local e=net.edges[id];local _,x,y=net.distance(id,q.p[1]*2,q.p[2]*2+512)
  local ox,oy=x+q.n[1]*(e.width*.5+6),y+q.n[2]*(e.width*.5+6)
  local enter=P.clear(s,ox,oy,x,y,1,0,id);local leave=P.clear(s,x,y,ox,oy,1,id,0)
  report.sealedWallChecks[#report.sealedWallChecks+1]={id=q.id,source={x/2,(y-512)/2},outsideSource={ox/2,(oy-512)/2},outsideFood=food(ox,oy),outsideLand=W.land(s,math.floor(ox),math.floor(oy)),entryBlocked=not enter,exitBlocked=not leave}
 end
 report.laneIdToEdgeId={};for i,e in ipairs(net.edges)do report.laneIdToEdgeId[i]=e.stableId end
 return report
 '''))
 for t in report['movementTests']:
  pts=[(p['x']/2,(p['y']-512)/2) for p in t['trace']]
  t['sourceBounds']=[min(p[0] for p in pts),min(p[1] for p in pts),max(p[0] for p in pts),max(p[1] for p in pts)]
  t['maxDistanceToTargetSource']=max(math.dist(p,t['toSource']) for p in pts)
  t['insideLocalStudyBounds']=all(535<=p[0]<=620 and 490<=p[1]<=545 for p in pts)
  if not t['regression']:t['pass']=t['pass'] and t['insideLocalStudyBounds']
 report.update(sourcePilotSha256=hashlib.sha256(pilotPath.read_bytes()).hexdigest(),sourceNetworkSha256=pilot['sourceNetworkSha256'],nativeEvidence=False,productionInstalled=False)
 report['testedModuleHashes']={name:hashlib.sha256((ROOT/'scripts/war'/name).read_bytes()).hexdigest() for name in ['StomachConnectivityStudy.lua','StomachBattlefieldStudy.lua','StomachBattlefieldData.lua','ReviewedVascularLayout.lua','World.lua','Vessels.lua','Path.lua','Commands.lua','Workers.lua','CellCollision.lua','ReferenceArt.lua','Render.lua','View.lua','Cells.lua','Save.lua']}
 OUT.mkdir(exist_ok=True);report.update(render_and_project(OUT,report['additions']['gates']))
 report['limitations']=['Isolated layout only; production World/Vessels/Path and canonical map are not installed or modified.', 'Food exclusion is injected only in this test runtime; tissue lane 0 is forbidden inside food, declared vessel lanes may pass underneath its projection.', 'Successful cases confirm these local routes and gates only; arbitrary whole-stomach tissue connectivity and multi-unit crowd throughput are not proven.', 'Sealed-wall negatives use actual Path.clear directly; Commands may legitimately detour through a declared gate.', 'SVG/Cairo screenshots evaluate actual Lua drawing calls but do not prove native NanoVG antialiasing, frame time or mobile performance.']
 report['baselineRejectedCases']=[dict(id=t['id'],arrived=t['arrived'],reason=t['rejectionReason']) for t in old['rejectedDesignCases']]
 report['qaScriptSha256']=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
 report['referenceSha256']=hashlib.sha256((ROOT/'assets/image/anatomy-reference/reference.png').read_bytes()).hexdigest()
 report['checks']=[dict(id=t['id'],passed=t['pass']) for t in report['movementTests']]
 for g in report['gateChecks']:report['checks'].append(dict(id=g['id']+'.gate',passed=all(g[k] for k in ['entry','exit','membraneOutsideFood','tissueOutsideFood'])))
 for g in report['sealedWallChecks']:report['checks'].append(dict(id=g['id'],passed=g['entryBlocked'] and g['exitBlocked'] and g['outsideLand'] and not g['outsideFood']))
 for i,p in enumerate(report['endpointChecks']):report['checks'].append(dict(id='endpoint.'+str(i),passed=p['tissue'] and not p['food'] and p['land'] and p['lane0Legal']))
 report['checks'].append(dict(id='new-gate-projection-save-75',passed=len(report['projection'])==75 and all(p['maxError']<1e-8 and p['saveUnchanged'] for p in report['projection'])))
 report['status']='PASS_ISOLATED_STOMACH_CONNECTIVITY' if all(c['passed'] for c in report['checks']) else 'FAIL_ISOLATED_STOMACH_CONNECTIVITY'
 report['displaySummary']=f"局部连通试验 {sum(c['passed'] for c in report['checks'])}/{len(report['checks'])} 项符合预期；新增4个受控膜口、1条胃壁深层服务支管，正式地图未接入。"
 OUT.mkdir(exist_ok=True);(OUT/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
 print(json.dumps({'status':report['status'],'checks':report['checks']},ensure_ascii=False),flush=True)
 assert all(c['passed'] for c in report['checks']),'connectivity checks failed'
if __name__=='__main__':main()
