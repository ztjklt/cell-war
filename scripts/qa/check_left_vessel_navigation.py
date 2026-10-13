"""Actual full-body traversal, ordinary clicks and layout-3 save migration."""
from pathlib import Path
import sys,json,hashlib,math
from shapely.geometry import LineString,Point,box
sys.path.insert(0,str(Path(__file__).parent))
import check_heart_battlefield as q
from left_vessels_support import runtime,OUT,to_lua
from check_regional_vascular_refinement import convert

def main():
 q.GEOMETRY_ROOT=OUT;oracle=q.Oracle();l=runtime()
 l.execute('''
  F=require('war.FullBodyBattlefield');O=require('war.OrganBattlefield');C=require('war.Commands');W=require('war.World');Save=require('war.Save')
  S=F.new(914);N=O.net(S);I=require('war.Input');R=require('war.Render');R.w,R.h=1480,900
  input={GetKeyDown=function()return false end}
  local M=require('war.Motion');local original=M.record;trace={}
  M.record=function(e)original(e);if e.id==traceId then trace[#trace+1]={x=e.x,y=e.y,lane=e.vesselLane}end end
  function prepare(kind,a)
   S.entities={};S.commands={};S.effects={};require('war.OrganTraffic').reset(S);require('war.Path').reset();W.rebuild(S)
   local e=assert(C.spawn(S,'unit',kind,1,a[1]*2,a[2]*2+512));e.vesselLane=a[3];traceId=e.id;trace={{x=e.x,y=e.y,lane=a[3]}}
   W.rebuild(S);assert(O.pointAllowed(S,e,e.x,e.y,a[3]));return e
  end
  function finish(e,b)
   local steps=0;while steps<6000 and(#e.orders>0 or #S.commands>0)do F.step(S,.1);steps=steps+1 end
   local error=math.sqrt((e.x-b[1]*2)^2+(e.y-b[2]*2-512)^2)
   return {arrived=error<.03 and e.vesselLane==b[3]and #e.orders==0,errorWorld=error,steps=steps,trace=trace,cellId=e.id,finalLane=e.vesselLane}
  end
  function move(kind,a,b)
   local e=prepare(kind,a);assert(C.execute(S,{kind='move',faction=1,ids={e.id},x=b[1]*2,y=b[2]*2+512,lane=b[3]}));return finish(e,b)
  end
  function clickStem(kind,a)
   local e=prepare(kind,a);local g={state=S,camera={x=1012,y=1270},zoom=.15,selection={[e.id]=true},pointer={},groups={{},{},{}},realTime=0,bodyLifeEnabled=false}
   local results={}
   for _,target in ipairs({{474,375,211},{497,382,203}})do
    local wx,wy=target[1]*2,target[2]*2+512;local key=require('war.Util').key(wx,wy)
    S.resources[key]={x=wx,y=wy,kind='wood',amount=140,max=140,regen=0};S.factions[1].seen[key]=true
    local sx,sy=R.project(g,wx,wy);I.tap(g,sx,sy,true);assert(S.commands[1].kind=='move')
    local hint=S.commands[1].lane;local r=finish(e,target);r.laneHint=hint;r.trace=nil;results[#results+1]=r
   end
   return results
  end
 ''')
 curves={i:LineString([(p[1]*.5,(p[2]-512)*.5)for _,p in e.points.items()])for i,e in l.globals().N.edges.items()}
 def inside(i):
  g=curves[i].intersection(box(465,330,513,347));g=g if g.geom_type=='LineString'else max(g.geoms,key=lambda p:p.length)
  p=g.interpolate(.2,normalized=True);return[p.x,p.y,i]
 def along(i,t):p=curves[i].interpolate(t,normalized=True);return[p.x,p.y,i]
 cases=[(f'upper-vein-{i}-through-single-cava',inside(i),[497,382,203])for i in [17,22,67,72]]
 cases.append(('whole-smooth-artery',along(3,.1),along(172,.8)))
 rows=[]
 for kind in ['scout','siege']:
  for name,a,b in cases:
   for reverse in [False,True]:
    aa,bb=(b,a)if reverse else(a,b);r=convert(l.globals().move(kind,l.table_from(aa),l.table_from(bb)));trace=r.pop('trace')
    failures=[(x,y)for x,y in zip(trace,trace[1:])if not oracle.allowed(x,y,kind)]
    assert r['arrived']and not failures,(kind,name,reverse,r,len(failures));r.update(name=name,kind=kind,reverse=reverse,fullDiskSweepFailures=0);rows.append(r)
    print(name,kind,reverse,'PASS',flush=True)
  clicks=convert(l.globals().clickStem(kind,l.table_from(inside(17))))
  assert len(clicks)==2 and all(r['arrived']for r in clicks),(kind,clicks)
  # Input can rely on the engine's direct lane inference where that blood
  # floor is already unambiguous; a supplemental display hint is optional.
  assert clicks[0]['finalLane']==211,(kind,clicks)
  rows.append({'name':'ordinary-click-new-stem-and-right-atrium','kind':kind,'legs':clicks,'passed':True})
 # The common superior node has exactly the four branches and one stem.
 svc=l.globals().N.nodes[l.globals().N.edges[211].a]
 assert sorted(v for _,v in svc.edges.items())==[17,22,67,72,211]
 assert l.globals().N.edges[211].b==l.globals().N.edges[1].a
 junctions=l.globals().O.organ('heart').junctionContracts.siege
 for _,j in junctions.items():assert {j.aLane,j.bLane}!={3,211}and {j.aLane,j.bLane}!={172,211}
 # Build a genuine previous-layout snapshot with units on the old overlapping
 # superior pipes and on both old arterial pieces, then restore in layout 4.
 old=runtime(baseline=True);old.execute("F=require('war.FullBodyBattlefield');O=require('war.OrganBattlefield');C=require('war.Commands');W=require('war.World');Save=require('war.Save');S=F.new(917);S.entities={};W.rebuild(S);N=O.net(S)")
 records=[]
 for kind in ['scout','siege']:
  for i in [17,22,67,72,3,172,8]:
   e=old.globals().N.edges[i];line=LineString([(p[1]*.5,(p[2]-512)*.5)for _,p in e.points.items()])
   if i in [17,22,67,72]:p=min([Point(c)for c in line.coords],key=lambda p:abs(p.y-372))
   else:p=line.interpolate(.3 if kind=='scout'else .65,normalized=True)
   entity=old.globals().C.spawn(old.globals().S,'unit',kind,1,p.x*2,p.y*2+512);assert entity
   entity.x,entity.y,entity.vesselLane=p.x*2,p.y*2+512,i
   assert old.globals().O.pointAllowed(old.globals().S,entity,entity.x,entity.y,i)
   records.append({'id':entity.id,'lane':i,'x':entity.x,'y':entity.y,'kind':kind})
 snapshot=convert(old.globals().Save.snapshot(old.globals().S));assert snapshot['heartLayoutRevision']==3
 restored=l.globals().Save.restore(to_lua(l,snapshot));migrations=[]
 for record in records:
  e=restored.entities[record['id']];expected=211 if record['lane']in [17,22,67,72]else record['lane']
  assert e.vesselLane==expected and l.globals().O.pointAllowed(restored,e,e.x,e.y,e.vesselLane),(record,e.vesselLane,e.x,e.y)
  if record['lane']==8:assert e.x==record['x']and e.y==record['y']
  migrations.append({'fromLane':record['lane'],'toLane':e.vesselLane,'kind':record['kind'],'legal':True})
 moved=[restored.entities[r['id']]for r in records if r['lane']in [17,22,67,72]]
 collision=l.eval("require('war.CellCollision')")
 for n,a in enumerate(moved):
  for b in moved[n+1:]:assert math.hypot(a.x-b.x,a.y-b.y)>=collision.radius(a)+collision.radius(b)+.079
 for kind in ['scout','siege']:
  e=l.globals().prepare(kind,l.table_from([474,375,211]));roundtrip=l.globals().Save.restore(l.globals().Save.snapshot(l.globals().S))
  assert roundtrip.entities[e.id].vesselLane==211
  assert l.globals().O.pointAllowed(roundtrip,roundtrip.entities[e.id],e.x,e.y,211)
 report={'status':'PASS_PRODUCTION_LUA_OFFLINE','nativeEvidence':False,'routes':rows,'fullDiskSweepFailures':0,'oneSuperiorTrunk':True,'superiorNodeDegree':5,'redBlueFalseJunctions':0,'layout3Migration':migrations,'new211SaveRoundtrips':2,'globalWorldEdges':len(l.globals().W.vessels(l.globals().S).edges),'optedGraphEdges':len(l.globals().N.edges)}
 assert report['globalWorldEdges']==202 and report['optedGraphEdges']==211
 (OUT/'navigation-check.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps({'status':report['status'],'routes':len(rows),'migrationFixtures':len(migrations),'graphEdges':211}))

if __name__=='__main__':main()
