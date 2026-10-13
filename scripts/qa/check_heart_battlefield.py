"""Production Lua 5.4 heart navigation/combat QA with independent disk geometry.

No native preview, renderer or engine is substituted for movement. Only the
engine-independent Lua modules run offline; native visual evidence is separate.
"""
from pathlib import Path
import hashlib,json,sys,time
sys.path.insert(0,'/tmp/heart-v1-deps')
from lupa.lua54 import LuaRuntime
from shapely.geometry import Polygon,Point,LineString
from shapely.ops import unary_union
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'docs/heart-v1/qa'
CANDIDATE=None
GEOMETRY_ROOT=ROOT/'docs/heart-v1/geometry'

def convert(v):
 if hasattr(v,'items'):
  d=dict(v.items())
  if d and set(d)==set(range(1,len(d)+1)):return [convert(d[i]) for i in range(1,len(d)+1)]
  return {str(k):convert(x) for k,x in d.items()}
 return v

def runtime():
 l=LuaRuntime(unpack_returned_tuples=True)
 l.execute("package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={};print=function()end")
 if CANDIDATE:
  for name in ['HeartBattlefieldData','HeartBattlefield','HeartVisualData','Save']:
   p=CANDIDATE/(name+'.lua')
   if p.exists():
    l.globals().qaModule=p.read_text();l.globals().qaName='war.'+name
    l.execute('package.loaded[qaName]=assert(load(qaModule))()')
 return l

def rings(rs):return unary_union([Polygon(r['outer'],r.get('holes',[])) for r in rs])

class Oracle:
 def __init__(self):
  self.g=json.loads((GEOMETRY_ROOT/'heart-four-chamber.json').read_text())
  self.d=json.loads((GEOMETRY_ROOT/'runtime-data.json').read_text())
  frozen=json.loads((ROOT/'docs/body-life/vascular-art-study/final-reference-data.json').read_text())
  self.domains={0:rings(self.g['tissueRings'])}
  for i,e in enumerate(frozen['edges'],1):self.domains[i]=LineString(e['samples']).buffer(e['lumenWidthSource']/2,quad_segs=32)
  for key,rs in self.g['rawBloodDomains'].items():self.domains[int(key)]=rings(rs)
  self.throat=LineString([self.d['gates'][0]['pipeAnchorSource'],self.d['gates'][0]['tissueAnchorSource']]).buffer(1.9,quad_segs=48)
 def point(self,q):return q['x']*.5,(q['y']-512)*.5
 def allowed(self,a,b,kind):
  radius={'scout':.21875,'siege':.53125}[kind]
  domain=self.domains[a['lane']].union(self.domains[b['lane']])
  if a.get('transit') or b.get('transit'):domain=domain.union(self.throat).union(self.domains[145]).union(self.domains[0])
  return domain.covers(LineString([self.point(a),self.point(b)]).buffer(radius,quad_segs=16))

def main():
 OUT.mkdir(parents=True,exist_ok=True)
 bound=[]
 for name in ['HeartBattlefieldData','HeartBattlefield','OrganBattlefield','OrganBattlefieldCore','Save']:
  p=CANDIDATE/(name+'.lua')if CANDIDATE else None
  bound.append(p if p and p.exists()else ROOT/'scripts/war'/(name+'.lua'))
 bound+=[GEOMETRY_ROOT/'runtime-data.json',GEOMETRY_ROOT/'heart-four-chamber.json']
 binding={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in bound}
 oracle=Oracle();l=runtime()
 l.execute("""
 local T,O,C,W,H=require('war.OrganTrial'),require('war.OrganBattlefield'),require('war.Commands'),require('war.World'),require('war.HeartBattlefield')
 qaState=T.new(73,{'heart'})
 local Motion=require('war.Motion');local original=Motion.record
 qaTrace={};Motion.record=function(e)
  original(e);if e.id==qaTraceId then qaTrace[#qaTrace+1]={x=e.x,y=e.y,lane=e.vesselLane,transit=e.gastricTransit and {gateId=e.gastricTransit.gateId}or nil}end
 end
 function qaMove(kind,ax,ay,al,bx,by,bl)
  local s=qaState;s.entities={};s.commands={};s.effects={};require('war.OrganTraffic').reset(s);require('war.Path').reset();W.rebuild(s)
  local e=assert(C.spawn(s,'unit',kind,1,ax*2,ay*2+512));e.vesselLane=al;qaTraceId=e.id;qaTrace={{x=e.x,y=e.y,lane=al}}
  assert(O.pointAllowed(s,e,e.x,e.y,al),'invalid test start')
  W.rebuild(s);local accepted=C.execute(s,{kind='move',faction=1,ids={e.id},x=bx*2,y=by*2+512,lane=bl})
  local steps=0;while steps<5000 and #e.orders>0 do T.step(s,.1);steps=steps+1 end
  local err=math.sqrt((e.x-bx*2)^2+(e.y-by*2-512)^2)
  return {accepted=accepted,arrived=err<.03 and e.vesselLane==bl and #e.orders==0,steps=steps,errorWorld=err,lane=e.vesselLane,pathFailed=e.pathFailed,trace=qaTrace}
 end
 """)
 centers={c['id']:(*c['centerSource'],c['laneIndex']) for c in oracle.g['chambers']}
 sections={s['id']:(*s['source'],{'systemic_return':1,'pulmonary_outflow':2,'pulmonary_return_r':5,'pulmonary_return_l':8,'aortic_outflow':150}[s['id']])for s in oracle.g['externalSections']}
 pairs=[('tricuspid',centers['right_atrium'],centers['right_ventricle']),('pulmonary',centers['right_ventricle'],sections['pulmonary_outflow']),('mitral',centers['left_atrium'],centers['left_ventricle']),('aortic',centers['left_ventricle'],sections['aortic_outflow']),('systemic',sections['systemic_return'],centers['right_atrium']),('pulmonary_return_r',sections['pulmonary_return_r'],centers['left_atrium']),('pulmonary_return_l',sections['pulmonary_return_l'],centers['left_atrium'])]
 g=oracle.d['gates'][0];pairs+=[('coronary_myocardium',(*g['pipeAnchorSource'],145),(*g['tissueAnchorSource'],0))]
 report={'schema':'heart-battlefield-production-qa/v1','nativeEvidence':False,'productionNavigationSubstituted':False,'navigation':[],'checks':[]}
 started=time.perf_counter()
 for kind in ['scout','siege']:
  for name,a,b in pairs:
   for reverse in [False,True]:
    aa,bb=(b,a)if reverse else(a,b);row=convert(l.globals().qaMove(kind,*aa,*bb));trace=row.pop('trace');trace=trace if isinstance(trace,list)else []
    failures=[];lanes=[]
    for q in trace:
     if q['lane'] not in lanes:lanes.append(q['lane'])
    for first,second in zip(trace,trace[1:]):
     if not oracle.allowed(first,second,kind):
      if len(failures)<3:failures.append({'a':first,'b':second})
    row.update({'kind':kind,'connection':name,'reverse':reverse,'tracePoints':len(trace),'visitedLanes':lanes,'fullDiskSweepFailures':failures,'pass':row['arrived']and not failures})
    report['navigation'].append(row);print(kind,name,'reverse'if reverse else'forward',row['pass'],row['steps'],flush=True)
 report['checks']=convert(l.execute("""
  local T,O,C,W,F,H,P=require('war.OrganTrial'),require('war.OrganBattlefield'),require('war.Commands'),require('war.World'),require('war.Combat'),require('war.HeartBattlefield'),require('war.Path')
  local rows={};local function check(name,pass,detail)rows[#rows+1]={name=name,pass=pass,detail=detail}end
  for _,c in ipairs(H.data.chambers)do
   local s=T.new(73,{'heart'});s.entities={};W.rebuild(s)
   local x,y=c.centerSource[1]*2,c.centerSource[2]*2+512
   local a=assert(C.spawn(s,'unit','siege',1,x,y));local b=assert(C.spawn(s,'unit','virus',0,x+2.5,y));W.rebuild(s)
   local hp=b.hp;F.fight(s,a,b,.1,false);check('combat_'..c.id,b.hp<hp,{damage=hp-b.hp,aLane=a.vesselLane,bLane=b.vesselLane})
  end
  local s=T.new(73,{'heart'});s.entities={};W.rebuild(s)
  local a=assert(C.spawn(s,'unit','siege',1,522.0149020570162*2,449.7082166306879*2+512));a.vesselLane=204
  local b=assert(C.spawn(s,'unit','virus',0,524.4432717476649*2,448.1353226323538*2+512));b.vesselLane=206;W.rebuild(s)
  check('septum_attack_fixture_is_legal_and_in_range',O.pointAllowed(s,a,a.x,a.y,204)and O.pointAllowed(s,b,b.x,b.y,206)and require('war.Util').dist(a,b)<9)
  local hp=b.hp;local blocked=H.combatClear(s,a,b)==false;F.fight(s,a,b,.1,false)
  check('ventricular_septum_attack',blocked and b.hp==hp,{before=hp,after=b.hp})
  local ok=O.sweep(s,a,499*2,426*2+512,536*2,426*2+512,204,206);check('ventricular_septum_sweep',not ok)
  ok=O.sweep(s,a,497*2,382*2+512,538*2,382*2+512,203,205);check('atrial_septum_sweep',not ok)
  local clear,nextLane=O.sweep(s,a,536*2,426*2+512,536*2,426*2+512,206,0);check('blood_myocardium_independent',not clear or nextLane~=0)
  local snap=require('war.Save').snapshot(T.new(73,{'heart'}));local r=require('war.Save').restore(snap)
  local all=true;for _,e in pairs(r.entities)do all=all and O.pointAllowed(r,e,e.x,e.y,e.vesselLane)end
  check('four_chamber_save_restore',all,{edgeCount=#O.net(r).edges,version=r.heartBattlefieldVersion})
  local old=T.new(73,{'heart'});local q=require('war.Save').snapshot(old);q.heartBattlefieldVersion=nil
  for _,e in pairs(q.entities)do if e.faction==1 then e.x,e.y,e.vesselLane=538*2,422*2+512,0 end end
  local restored=require('war.Save').restore(q);all=true
  for _,e in pairs(restored.entities)do all=all and O.pointAllowed(restored,e,e.x,e.y,e.vesselLane)end
  check('legacy_myocardial_bay_migration',all)
  local normal=require('war.Simulation').new(73,'sandbox',4);check('legacy_anatomy_optout',#W.vessels(normal).edges==131 and not H.enabled(normal))
  local encounter=T.new(73,{'heart'});local enemies,friendlies=0,0;for _,e in pairs(encounter.entities)do if e.faction==0 then enemies=enemies+1 else friendlies=friendlies+1 end end
  check('four_playable_encounters',enemies==4 and friendlies==4,{enemies=enemies,friendlies=friendlies})
  local count=0;for _,e in pairs(encounter.entities)do if e.faction==0 then e.hp=0;count=count+1 end end;encounter.effects={{ttl=.02}}
  H.afterStep(encounter,.1);local remaining=0;for _ in pairs(encounter.entities)do remaining=remaining+1 end
  check('dead_units_and_effects_pruned',remaining==4 and #encounter.effects==0)
  return rows
 """))
 report['elapsedOfflineSeconds']=round(time.perf_counter()-started,3)
 report['passed']=sum(r['pass']for r in report['navigation'])+sum(r['pass']for r in report['checks'])
 report['total']=len(report['navigation'])+len(report['checks'])
 report['sourceGraphSha256']=hashlib.sha256((ROOT/'docs/body-life/vascular-art-study/final-reference-data.json').read_bytes()).hexdigest()
 report['inputHashes']=binding
 report['inputsStable']=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in binding.items())
 assert report['inputsStable'],'Heart navigation inputs changed during checks'
 (OUT/'production-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
 print('PASS',report['passed'],'/',report['total'],flush=True)
 if report['passed']!=report['total']:raise SystemExit(1)
if __name__=='__main__':main()
