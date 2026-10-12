"""Render an opt-in shared-data stomach study with actual Lua NanoVG calls.

This does not install the study or its food collision in production.
"""
from pathlib import Path
import hashlib,json,math,os,sys
ROOT=Path(__file__).resolve().parents[2]
os.chdir(ROOT)
DOC=ROOT/'docs/body-life/vascular-art-study';INPUT=DOC/'stomach-pilot.json'
def lua(v):
 if v is None:return 'nil'
 if isinstance(v,bool):return str(v).lower()
 if isinstance(v,(int,float)):return repr(v)
 if isinstance(v,str):return json.dumps(v,ensure_ascii=False)
 if isinstance(v,list):return '{'+','.join(map(lua,v))+'}'
 return '{'+','.join('['+lua(k)+']='+lua(x) for k,x in v.items())+'}'
def inside(p,poly):
 x,y=p;hit=False
 for a,b in zip(poly,poly[1:]+poly[:1]):
  if (a[1]>y)!=(b[1]>y) and x<(b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0]:hit=not hit
 return hit
def crossing(a,b,c,d):
 vx,vy=b[0]-a[0],b[1]-a[1];wx,wy=d[0]-c[0],d[1]-c[1];det=vx*wy-vy*wx
 if abs(det)<1e-12:return None
 dx,dy=c[0]-a[0],c[1]-a[1];t=(dx*wy-dy*wx)/det;u=(dx*vy-dy*vx)/det
 return t if 0<=t<=1 and 0<=u<=1 else None
def union_boundary(polys):
 result=[]
 for i,poly in enumerate(polys):
  others=[p for j,p in enumerate(polys) if j!=i]
  for a,b in zip(poly,poly[1:]+poly[:1]):
   ts=[0,1]
   for other in others:
    for c,d in zip(other,other[1:]+other[:1]):
     t=crossing(a,b,c,d)
     if t is not None:ts.append(t)
   ts=sorted(set(ts))
   def at(t):return [a[k]+t*(b[k]-a[k]) for k in range(2)]
   for left,right in zip(ts,ts[1:]):
    if right-left>1e-10 and not any(inside(at((left+right)/2),other) for other in others):result.append([at(left),at(right)])
 return result
def boundary_rings(segments):
 def key(p):return tuple(round(v,7) for v in p)
 graph={};coords={}
 for a,b in segments:
  ka,kb=key(a),key(b)
  if ka==kb:continue
  coords[ka]=a;coords[kb]=b;graph.setdefault(ka,set()).add(kb);graph.setdefault(kb,set()).add(ka)
 assert all(len(row)==2 for row in graph.values()),'food union boundary is not manifold'
 rings=[]
 while graph:
  start=next(iter(graph));current=start;previous=None;ring=[]
  while True:
   ring.append(coords[current]);neighbors=graph[current];nxt=next(p for p in neighbors if p!=previous)
   if previous is not None:del graph[previous]
   previous,current=current,nxt
   if current==start:del graph[previous];break
  rings.append(ring)
 return rings
def export():
 data=json.loads(INPUT.read_text());assert data['transform']=={'scale':2,'offsetY':512},'unsupported pilot transform'
 networkPath=ROOT/'docs/body-life/vascular-sketch/whole-body/network.json'
 assert data['sourceNetworkSha256']==hashlib.sha256(networkPath.read_bytes()).hexdigest(),'stale pilot network'
 network=json.loads(networkPath.read_text());edges={e['id']:e for e in network['edges']}
 for e in data['vessels']:
  source=edges[e['edgeId']];assert e['points']==source['points'] and e['lumenWidthSource']==source['lumenWidthSource'],'pilot vessel drift'
 data['food']['boundarySegments']=union_boundary([data['food'][k] for k in ['cavity','inlet','outlet']])
 data['food']['unionPaths']=boundary_rings(data['food']['boundarySegments'])
 assert len(data['food']['unionPaths'])==1,'food inlet, chamber and outlet must remain connected'
 crop=data['study']['crop'];polys=[data['food'][k] for k in ['cavity','inlet','outlet']]
 for y in range(int(crop[1]),int(crop[1]+crop[3]),4):
  for x in range(int(crop[0]),int(crop[0]+crop[2]),4):
   assert any(inside((x+.13,y+.17),p) for p in polys)==any(inside((x+.13,y+.17),p) for p in data['food']['unionPaths']),'food union differs from collision geometry'
 data['sourcePilotSha256']=hashlib.sha256(INPUT.read_bytes()).hexdigest()
 (ROOT/'scripts/war/StomachBattlefieldData.lua').write_text('-- Generated from stomach-pilot.json by check_stomach_battlefield.py; opt-in only.\nreturn '+lua(data)+'\n')
 return data

def render(data,out):
 import render_body_life as r
 b=r.b
 b.l.execute("package.loaded['war.ReferenceVessels']=require('war.ReviewedVascularLayout')")
 r.initialise()
 b.l.execute("""
 local A=require('war.ReferenceArt');local original=A.draw;local Study=require('war.StomachBattlefieldStudy')
 qaOriginalArtDraw=original;A.draw=function(...) original(...);Study.draw(...) end
 local C=require('war.Commands')
 for _,p in ipairs({{'scout',563,507},{'worker',560,514},{'spear',555,509},{'worker',576,510},{'scout',580,525},{'spear',555,540}}) do
  local unit=C.spawn(state,'unit',p[1],1,p[2]*2,p[3]*2+512,true);assert(unit,'render study cell spawn failed')
 end
 require('war.World').rebuild(state)
 qaSave=require('war.Save').snapshot(state)
 function qaSame(a,b)
  if type(a)~=type(b) then return false end;if type(a)~='table' then return a==b end
  for k,v in pairs(a) do if not qaSame(v,b[k]) then return false end end
  for k in pairs(b) do if a[k]==nil then return false end end;return true
 end
 """)
 frames=[];crop=data['study']['crop'];sx,sy=crop[0]+crop[2]/2,crop[1]+crop[3]/2
 for z in [.085,.12,.149,.15,.151]:
  w,h=1920,1728;cy=2*sy+512-.03*h/(32*z)
  b.reset();b.l.execute(f"graphics={{GetWidth=function()return {w} end,GetHeight=function()return {h} end,GetDPR=function()return 1 end}};game.zoom={z};game.camera={{x={2*sx},y={cy}}};game.realTime=1.92;R.draw(game);assert(qaSame(qaSave,require('war.Save').snapshot(state)),'study draw changed save')")
  image=b.png(w,h)
  if z==.085:
   b.reset();b.l.execute("local A=require('war.ReferenceArt');qaStudyDraw=A.draw;A.draw=qaOriginalArtDraw;R.draw(game);A.draw=qaStudyDraw")
   assert image==b.png(w,h),'study changed overview at .085'
  path=out/f'stomach-{z}.png';path.write_bytes(image);frames.append(dict(zoom=z,path=str(path.relative_to(ROOT)),logicalSize=[w,h],studyAlpha=float(b.l.eval("require('war.StomachBattlefieldStudy').alpha")(z))))
 samples=[]
 for w,h in [(1440,900),(1024,768),(844,390),(430,932),(360,780)]:
  for dpr in [1,2,3]:
   for z in [.085,.12,.149,.15,.151]:
    b.reset();b.l.execute(f"""graphics={{GetWidth=function()return {w*dpr} end,GetHeight=function()return {h*dpr} end,GetDPR=function()return {dpr} end}};game.zoom={z};game.camera={{x={2*sx},y={2*sy+512}}};R.draw(game)
    assert(R.w=={w} and R.h=={h});assert(qaSame(qaSave,require('war.Save').snapshot(state)))
    qaError=0;for _,p in ipairs(require('war.StomachBattlefieldData').ports) do local x,y=R.project(game,p.world[1],p.world[2]);local wx,wy=R.unproject(game,x,y);qaError=math.max(qaError,math.abs(wx-p.world[1]),math.abs(wy-p.world[2])) end
    assert(qaError<1e-8)
    """)
    samples.append(dict(size=[w,h],dpr=dpr,zoom=z,maxWorldError=b.G.qaError,saveUnchanged=True))
 import numpy as np
 from PIL import Image
 near=[np.asarray(Image.open(out/f'stomach-{z}.png').convert('RGB'),dtype=np.int16) for z in [.149,.15,.151]]
 differences=[float(np.abs(a-c).mean()) for a,c in zip(near,near[1:])]
 assert max(differences)<6,('study fill jump',differences)
 return dict(frames=frames,projection=samples,overviewUnchangedAt085=True,newFillPixelDifferences=differences)

def navigation(data):
 from lupa.lua54 import LuaRuntime,lua_type
 rt=LuaRuntime(unpack_returned_tuples=True)
 rt.execute("package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={};print=function()end;package.loaded['war.ReferenceVessels']=require('war.ReviewedVascularLayout')")
 rt.globals().qaCandidateCases='--candidate-cases' in sys.argv
 result=rt.execute(r"""
 local W,P,C,U=require('war.World'),require('war.Path'),require('war.Commands'),require('war.Util')
 local Study=require('war.StomachBattlefieldStudy');local Data=Study.data
 local s=W.generate(73,nil,nil,nil,4);W.rebuild(s);local net=W.vessels(s)
 local originalLand=W.land;local foodGrid={}
 W.land=function(state,x,y)
  if not originalLand(state,x,y) then return false end
  local key=x..':'..y;local food=foodGrid[key]
  if food==nil then food=Study.containsFoodSource((x+.5)/2,(y+.5-512)/2);foodGrid[key]=food end
  if not food then return true end
  -- Tissue cannot occupy food. A vessel remains on its independent logical layer.
  return #W.vessels(state).sample(x+.5,y+.5).lanes>0
 end
 local report={tests={},productionInstalled=false,collisionScope='isolated W.land food exclusion plus actual lane-aware Path/Commands; no production change'}
 local function test(case)
  P.reset();s.entities={};s.nextId=1;W.rebuild(s)
  local ax,ay=case.fromSource[1]*2,case.fromSource[2]*2+512
  local bx,by=case.toSource[1]*2,case.toSource[2]*2+512
  local e=C.spawn(s,'unit','scout',1,ax,ay,true)
  if not e then return {id=case.id,label=case.id,arrived=false,error='spawn rejected',trace={}} end
  e.vesselLane=case.lane or 0;W.rebuild(s)
  local direct=P.clear(s,ax,ay,bx,by,1,e.vesselLane)
  C.execute(s,{kind='move',faction=1,ids={e.id},x=bx,y=by})
  local trace={{t=0,x=e.x,y=e.y,lane=e.vesselLane}};local invalid,foodSteps,foodVesselSteps,frames,travel=0,0,0,0,0
  for frame=1,2400 do local x,y,lane=e.x,e.y,e.vesselLane
   s.time=s.time+.05;P.update(s,1000);require('war.Workers').update(s,e,.05);W.rebuild(s);frames=frame
   if not P.clear(s,x,y,e.x,e.y,1,lane,e.vesselLane) then invalid=invalid+1 end
   if Study.containsFoodSource(e.x/2,(e.y-512)/2) then
    if e.vesselLane==0 then foodSteps=foodSteps+1 else foodVesselSteps=foodVesselSteps+1 end
   end
   travel=travel+math.sqrt((e.x-x)^2+(e.y-y)^2)
   if frame%4==0 then trace[#trace+1]={t=frame*.05,x=e.x,y=e.y,lane=e.vesselLane} end
   if (e.x-bx)^2+(e.y-by)^2<.8*.8 or e.pathFailed then break end
  end
  trace[#trace+1]={t=frames*.05,x=e.x,y=e.y,lane=e.vesselLane}
  local arrived=(e.x-bx)^2+(e.y-by)^2<.8*.8
  return {id=case.id,label=case.id,expected=case.expected,fromSource=case.fromSource,toSource=case.toSource,arrived=arrived,directClear=direct,invalidSteps=invalid,foodTissueSteps=foodSteps,foodVesselSteps=foodVesselSteps,pathFailed=e.pathFailed or false,trace=trace,seconds=frames*.05,travel=travel,straightDistance=math.sqrt((ax-bx)^2+(ay-by)^2)}
 end
 local cases=Data.study.navigationCases
 if qaCandidateCases then cases={{id='membrane-tissue-clear',fromSource={563,507},toSource={563,515},expected='clear',lane=0},{id='cavity-rim-detour',fromSource={583,491},toSource={584,502},expected='detour',lane=0}} end
 for _,case in ipairs(cases) do report.tests[#report.tests+1]=test(case) end
 report.rejectedDesignCases={}
 for _,case in ipairs({{id='wall-left',fromSource={550,518},toSource={557,533},expected='clear',lane=0},{id='cavity-detour',fromSource={578,515},toSource={612,523},expected='detour',lane=0}}) do
  local result=test(case);result.rejectionReason=case.id=='wall-left' and 'sealed internal vascular walls separate these tissue points; no legal route in current fixture' or 'food passage and vascular walls separate the two tissue regions; a whole-stomach tissue ring is not implemented'
  report.rejectedDesignCases[#report.rejectedDesignCases+1]=result
 end
 local port=Data.ports[#Data.ports]
 report.tests[#report.tests+1]=test({id='membrane-to-battlefield',fromSource={port.outsideWorld[1]/2,(port.outsideWorld[2]-512)/2},toSource={563,515},lane=0,expected='clear'})
 report.tests[#report.tests+1]=test({id='actual-membrane-enter',fromSource={port.outsideWorld[1]/2,(port.outsideWorld[2]-512)/2},toSource={port.insideWorld[1]/2,(port.insideWorld[2]-512)/2},lane=0,expected='clear'})
 local edge=require('war.ReviewedVascularLayout').edgeIndexById[port.edge]
 report.tests[#report.tests+1]=test({id='actual-membrane-exit',toSource={port.outsideWorld[1]/2,(port.outsideWorld[2]-512)/2},fromSource={port.insideWorld[1]/2,(port.insideWorld[2]-512)/2},lane=edge,expected='clear'})
 report.tests[#report.tests+1]=test({id='deep-portal-under-food',fromSource={541,551.4},toSource={527,558.7142857142857},lane=require('war.ReviewedVascularLayout').edgeIndexById['e164'],expected='clear'})
 report.tests[#report.tests+1]=test({id='food-centre-blocked',fromSource={578,515},toSource={598,523},lane=0,expected='blocked'})
 return report
 """)
 def convert(v):
  if lua_type(v)!='table':return v
  keys=list(v.keys())
  if keys and all(isinstance(k,int) for k in keys):return [convert(v[i]) for i in range(1,len(keys)+1)]
  return {k:convert(x) for k,x in v.items()}
 return convert(result)

def main():
 data=export();out=DOC/'stomach-evidence';out.mkdir(exist_ok=True)
 report=dict(sourcePilotSha256=data['sourcePilotSha256'],sourceNetworkSha256=data['sourceNetworkSha256'],nativeEvidence=False,productionInstalled=False)
 if '--navigation-only' in sys.argv:
  previous=json.loads((out/'report.json').read_text());assert previous['sourcePilotSha256']==data['sourcePilotSha256'],'render evidence stale'
  report.update(previous)
 else:report.update(render(data,out))
 report['navigation']=navigation(data)
 report['movementTests']=report['navigation']['tests']
 labels={'membrane-tissue-clear':'膜口附近组织直行','cavity-rim-detour':'同侧绕过食物腔凸缘','membrane-to-battlefield':'真实膜口通向战场区域','actual-membrane-enter':'组织进入血管','actual-membrane-exit':'血管返回组织','deep-portal-under-food':'深层门静脉从食物腔投影下通过','food-centre-blocked':'食物腔目标禁止组织细胞进入'}
 for case in report['movementTests']:case['label']=labels.get(case['id'],case['id'])
 report['previewFiles']=[Path(f['path']).name for f in report['frames']]
 report['rejectedDesignCases']=report['navigation']['rejectedDesignCases']
 (DOC/'stomach-food-union.json').write_text(json.dumps({'sourcePilotSha256':data['sourcePilotSha256'],'paths':data['food']['unionPaths']},ensure_ascii=False,separators=(',',':'))+'\n')
 report['displaySummary']=f"新胃图层：{len(report['frames'])}档实际Lua渲染、{len(report['projection'])}组DPR投影；独立食物障碍移动记录见下方。"
 report['testedModuleHashes']={name:hashlib.sha256((ROOT/'scripts/war'/name).read_bytes()).hexdigest() for name in ['StomachBattlefieldData.lua','StomachBattlefieldStudy.lua','ReviewedVascularLayout.lua','Path.lua','Commands.lua','Vessels.lua','ReferenceArt.lua','Render.lua','View.lua','World.lua','Cells.lua','CellCollision.lua','Save.lua']}
 report['qaScriptSha256']=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
 report['referenceSha256']=hashlib.sha256((ROOT/'assets/image/anatomy-reference/reference.png').read_bytes()).hexdigest()
 report['checks']=[]
 for case in report['movementTests']:
  success=case.get('invalidSteps')==0 and case.get('foodTissueSteps')==0
  if case['expected']=='blocked':success=success and not case['arrived'] and case['pathFailed']
  else:success=success and case['arrived']
  if case['expected']=='detour':success=success and not case['directClear']
  if case['id']=='deep-portal-under-food':success=success and case['foodVesselSteps']>0
  case['pass']=success;report['checks'].append(dict(id=case['id'],passed=success))
 report['status']='PASS_ISOLATED_LOCAL_STOMACH_CONTRACT' if all(c['passed'] for c in report['checks']) else 'FAIL_ISOLATED_LOCAL_STOMACH_CONTRACT'
 report['displaySummary']=f"5档新图层渲染、75组DPR与存档校验；{sum(c['passed'] for c in report['checks'])}/{len(report['checks'])}项局部试验符合预期。2个原设计目标仍不连通，正式地图未接入。"
 report['limitations']=['Only the tested local tissue region is reachable; the two rejected design cases remain disconnected.','Food collision is an isolated test-process W.land overlay. The production game, saves and organ campaigns are unchanged.','Images use actual Lua draw calls through SVG/Cairo, not native GPU evidence.','Six actual game units were spawned before Save baselines; decorative food/cell particles were not substituted for movement tests.']
 (out/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
 (out/'stomach-contract.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
 print(json.dumps({'frames':len(report['frames']),'projectionCases':len(report['projection']),'checks':report['checks'],'status':report['status']}))
 assert all(c['passed'] for c in report['checks']),'stomach local movement contract failed'
 assert hashlib.sha256(INPUT.read_bytes()).hexdigest()==report['sourcePilotSha256'],'pilot changed during QA'
if __name__=='__main__':main()
