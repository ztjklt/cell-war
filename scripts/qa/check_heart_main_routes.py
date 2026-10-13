"""Exercise the actual commands and full-disk movement along cardiac trunks."""
from pathlib import Path
import sys,json,hashlib
import numpy as np
from shapely.geometry import LineString,Point,box
from shapely.ops import unary_union
import check_heart_battlefield as support
from check_regional_vascular_refinement import convert

def main():
    out=Path(sys.argv[1]).resolve();support.CANDIDATE=out;support.GEOMETRY_ROOT=out
    oracle=support.Oracle();l=support.runtime()
    l.execute('''
      T=require('war.OrganTrial');O=require('war.OrganBattlefield');C=require('war.Commands');W=require('war.World')
      S=T.new(93,{'heart'});N=O.net(S)
      local Motion=require('war.Motion');local original=Motion.record
      trace={};Motion.record=function(e)original(e);if e.id==traceId then trace[#trace+1]={x=e.x,y=e.y,lane=e.vesselLane}end end
      function move(kind,ax,ay,al,bx,by,bl)
       S.entities={};S.commands={};S.effects={};require('war.OrganTraffic').reset(S);require('war.Path').reset();W.rebuild(S)
       local e=assert(C.spawn(S,'unit',kind,1,ax*2,ay*2+512));e.vesselLane=al;traceId=e.id;trace={{x=e.x,y=e.y,lane=al}}
       assert(O.pointAllowed(S,e,e.x,e.y,al))
       W.rebuild(S);local accepted=C.execute(S,{kind='move',faction=1,ids={e.id},x=bx*2,y=by*2+512,lane=bl})
       local steps=0;while steps<5000 and #e.orders>0 do T.step(S,.1);steps=steps+1 end
       local error=math.sqrt((e.x-bx*2)^2+(e.y-by*2-512)^2)
       return {accepted=accepted,arrived=error<.03 and e.vesselLane==bl,steps=steps,trace=trace,errorWorld=error,
        finalLane=e.vesselLane,targetLane=bl,remainingOrders=#e.orders,hp=e.hp}
      end
    ''')
    def point(lane,fraction):
        e=l.globals().N.edges[lane];p=LineString([(q[1]*.5,(q[2]-512)*.5)for _,q in e.points.items()]).interpolate(fraction,normalized=True)
        return p.x,p.y,lane
    pairs=[('lower-cava-to-right-atrium',point(15,.12),(497,382,203)),
      ('upper-cava-to-right-atrium',point(17,.82),(497,382,203)),
      ('left-ventricle-to-descending-aorta',(536,426,206),point(9,.95)),
      ('right-ventricle-to-left-lung',(499,426,204),point(174,.8)),
      ('left-lung-return-to-left-atrium',point(175,.2),(538,382,205)),
      ('right-lung-return-to-left-atrium',point(173,.8),(538,382,205))]
    rows=[]
    for kind in ['scout','siege']:
      for name,a,b in pairs:
       for reverse in [False,True]:
        aa,bb=(b,a)if reverse else(a,b);r=convert(l.globals().move(kind,*aa,*bb));trace=r.pop('trace')
        if isinstance(trace,dict):trace=[]
        failures=[(first,second)for first,second in zip(trace,trace[1:])if not oracle.allowed(first,second,kind)]
        r.update(connection=name,kind=kind,reverse=reverse,fullDiskSweepFailures=len(failures),passed=r['arrived']and not failures)
        assert r['passed'],r;rows.append(r);print(name,kind,reverse,r['steps'],flush=True)
    # A projected crossing is never an extra right/left blood connection.
    crossing_checks=[]
    for a,b in [(5,15),(6,9),(174,9),(175,9)]:
        assert not any({j['aLane'],j['bLane']}=={a,b}for _,j in l.globals().O.organ('heart').junctionContracts.siege.items())
        crossing_checks.append({'lanes':[a,b],'accidentalJunction':False})
    original=json.loads((support.ROOT/'docs/body-life/vascular-art-study/final-reference-data.json').read_text())
    data=json.loads((out/'runtime-data.json').read_text());roi=box(*data['sourceBox']);scope=[]
    for key,e in data['edgeUpdates'].items():
        old=LineString(original['edges'][int(key)-1]['samples']);new=LineString(e['points'])
        before,after=old.difference(roi),new.difference(roi)
        assert before.is_empty==after.is_empty,key
        difference=0 if before.is_empty else before.hausdorff_distance(after)
        assert difference<1e-7,(key,difference)
        scope.append({'lane':int(key),'outsideScopeHausdorffSource':difference})
    report={'status':'PASS','nativeEvidence':False,'routes':rows,'crossings':crossing_checks,'outsideScope':scope,
       'candidateHashes':{p.name:hashlib.sha256(p.read_bytes()).hexdigest()for p in out.glob('*.lua')if not p.name.startswith('baseline-')},
       'sourceGraphSha256':hashlib.sha256((support.ROOT/'docs/body-life/vascular-art-study/final-reference-data.json').read_bytes()).hexdigest()}
    (out/'main-trunk-navigation-report.json').write_text(json.dumps(report,indent=2)+'\n')
    print('PASS',len(rows),'full cardiac trunk routes')

if __name__=='__main__':main()
