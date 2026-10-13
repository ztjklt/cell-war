"""Independent full-disk movement and common-lumen pigment checks at v10."""
from pathlib import Path
import sys,json,hashlib
import numpy as np
from PIL import Image
from shapely.geometry import Point,LineString,box
from shapely.ops import unary_union
sys.path.insert(0,str(Path(__file__).parent))
import check_heart_battlefield as q
from check_regional_vascular_refinement import convert

def main():
 out=q.ROOT/'docs/heart-simple-20261012/cava-junction-v10';q.CANDIDATE=out;q.GEOMETRY_ROOT=out
 oracle=q.Oracle();l=q.runtime()
 l.execute('''
  F=require('war.FullBodyBattlefield');O=require('war.OrganBattlefield');C=require('war.Commands');W=require('war.World')
  S=F.new(913);N=O.net(S);H=require('war.HeartVisualData')
  local Motion=require('war.Motion');local original=Motion.record
  trace={};Motion.record=function(e)original(e);if e.id==traceId then trace[#trace+1]={x=e.x,y=e.y,lane=e.vesselLane}end end
  function move(kind,a,b)
   S.entities={};S.commands={};S.effects={};require('war.OrganTraffic').reset(S);require('war.Path').reset();W.rebuild(S)
   local e=assert(C.spawn(S,'unit',kind,1,a[1]*2,a[2]*2+512));e.vesselLane=a[3];traceId=e.id;trace={{x=e.x,y=e.y,lane=a[3]}}
   W.rebuild(S);assert(C.execute(S,{kind='move',faction=1,ids={e.id},x=b[1]*2,y=b[2]*2+512,lane=b[3]}))
   local steps=0;while steps<6000 and #e.orders>0 do F.step(S,.1);steps=steps+1 end
   local err=math.sqrt((e.x-b[1]*2)^2+(e.y-b[2]*2-512)^2)
   return {arrived=err<.03 and e.vesselLane==b[3]and #e.orders==0,errorWorld=err,steps=steps,trace=trace,cellId=e.id,finalLane=e.vesselLane}
  end
 ''')
 lines={i:LineString([(p[1]*.5,(p[2]-512)*.5)for _,p in e.points.items()])for i,e in l.globals().N.edges.items()}
 def in_box(i,region):
  part=lines[i].intersection(region);parts=[part]if part.geom_type=='LineString'else list(part.geoms)
  part=max(parts,key=lambda p:p.length);p=part.interpolate(.25,normalized=True);return[p.x,p.y,i]
 cases=[(f'vein-{i}-to-right-atrium',in_box(i,box(464,332,491,347)),[497,382,203])for i in [17,22,67,72]]
 cases.append(('pulmonary-artery-open-join',in_box(3,box(479,346,493,362)),in_box(172,box(460,350,472,373))))
 rows=[]
 for kind in ['scout','siege']:
  for name,a,b in cases:
   for reverse in [False,True]:
    aa,bb=(b,a)if reverse else(a,b);result=convert(l.globals().move(kind,l.table_from(aa),l.table_from(bb)));trace=result.pop('trace')
    failures=[(p,n)for p,n in zip(trace,trace[1:])if not oracle.allowed(p,n,kind)]
    assert result['arrived']and not failures,(kind,name,reverse,result,len(failures))
    result.update(connection=name,kind=kind,reverse=reverse,fullDiskSweepFailures=0);rows.append(result)
    print(name,kind,reverse,'PASS',flush=True)
 # Artery/vein silhouettes can cross but cannot add a common gameplay node.
 junctions=l.globals().O.organ('heart').junctionContracts.siege
 for _,j in junctions.items():assert not(j.aLane in [3,172]and j.bLane in [15,17,22,67,72])and not(j.bLane in [3,172]and j.aLane in [15,17,22,67,72])
 pixels=np.array(Image.open(q.ROOT/'assets'/l.globals().H.resource).convert('RGBA'))
 counts={}
 for system,ids,region,clearance in [('vein',[1,15,17,22,67,72],box(470,342,480,354),.8),('artery',[3,172],Point(475.1613941018767,374.0150134048257).buffer(2.5),.6)]:
  shape=unary_union([lines[i].buffer(l.globals().N.edges[i].width*.25)for i in ids]).buffer(-clearance).intersection(region)
  count=0
  for sy in np.arange(shape.bounds[1],shape.bounds[3],.15):
   for sx in np.arange(shape.bounds[0],shape.bounds[2],.15):
    if not shape.covers(Point(sx,sy)):continue
    rgb=pixels[int((sy-306)*1692/174),int((sx-460)*10),:3].astype(float)
    assert rgb.mean()>124,(system,sx,sy,rgb)
    assert rgb[2]>rgb[0]+15 if system=='vein'else rgb[0]>rgb[2]+20,(system,sx,sy,rgb)
    count+=1
  assert count>30;counts[system]=count
 frozen=json.loads((out/'frozen-runtime-hashes.json').read_text())
 assert all(hashlib.sha256((q.ROOT/p).read_bytes()).hexdigest()==h for p,h in frozen.items())
 report={'status':'PASS_PRODUCTION_LUA_OFFLINE','nativeEvidence':False,'routes':rows,'fullDiskSweepFailures':0,'openFloorPigmentSamples':counts,'redBlueAccidentalJunctions':0,'simulationGeometryUnchanged':True,'runtimeSha256':hashlib.sha256((q.ROOT/'scripts/war/HeartVisualData.lua').read_bytes()).hexdigest(),'candidateSha256':hashlib.sha256((out/'HeartVisualData.lua').read_bytes()).hexdigest()}
 (out/'junction-check.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps({'status':report['status'],'routes':len(rows),'openFloorSamples':counts}))

if __name__=='__main__':main()
