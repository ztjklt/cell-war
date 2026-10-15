"""Independent source-space probes outside all checkpoint throat footprints."""
from pathlib import Path
import sys,json,math
sys.path.insert(0,str(Path(__file__).parent))
from check_gastric_battlefield import runtime,convert
from shapely.geometry import Polygon,Point,LineString
from shapely.ops import unary_union
ROOT=Path(__file__).resolve().parents[2];DOC=ROOT/'docs/vascular-checkpoints-20261015'

def main():
    source=json.loads((DOC/'source.json').read_text());ports=json.loads((DOC/'ports.json').read_text());cases=[]
    props_path=ROOT/'docs/styled-organ-obstacles-20261015/obstacles.json'
    props={q['id']:q['obstacleRings']for q in json.loads(props_path.read_text())}if props_path.exists()else{}
    def shape(rows):return unary_union([Polygon(r['outer'],r.get('holes')or[])for r in rows])
    groups={}
    for p in ports:groups.setdefault((p['organId'],p['lane']),[]).append(p)
    for (oid,lane),gates in groups.items():
        d=source['organs'][oid];tissue=shape(d['tissue']['siege']);blood=shape(d['blood']['siege'][str(lane)])
        if oid in props:tissue=tissue.difference(shape(props[oid]).buffer(.53125+.025))
        e=source['edges'][str(lane)];line=LineString([(p[0]/2,(p[1]-512)/2)for p in e['points']])
        throats=[LineString([g['a'],g['b']]).buffer(1.3)for g in gates]
        count=0
        for step in range(1,max(2,int(line.length*2))):
            a=line.interpolate(step*.5)
            if not blood.contains(a):continue
            near=line.interpolate(max(0,step*.5-.15));far=line.interpolate(min(line.length,step*.5+.15))
            dx,dy=far.x-near.x,far.y-near.y;length=math.hypot(dx,dy)
            if length<1e-8:continue
            for sign in (-1,1):
                gap=e['width']/4+1.0;b=Point(a.x-dy/length*gap*sign,a.y+dx/length*gap*sign)
                if not tissue.contains(b):continue
                segment=LineString([a,b])
                if any(segment.intersects(t)for t in throats):continue
                cases.append(dict(organ=oid,lane=lane,a=list(a.coords[0]),b=list(b.coords[0])))
                count+=1;break
            if count>=12:break
    l=runtime();l.globals().cases=l.table_from([l.table_from({**q,'a':l.table_from(q['a']),'b':l.table_from(q['b'])})for q in cases])
    result=convert(l.execute('''
local s=require('war.FullBodyBattlefield').new(73);local O=require('war.OrganBattlefield')
local report={tested=0,blocked=0,skippedProjection=0,segments={}}
for _,q in ipairs(cases)do
 local e={id=-1,category='unit',kind='siege',faction=1,x=q.b[1]*2,y=q.b[2]*2+512,vesselLane=0}
 if O.pointAllowed(s,e,e.x,e.y,0)and O.pointAllowed(s,e,q.a[1]*2,q.a[2]*2+512,q.lane)then
  local ok,lane,t=O.sweep(s,e,e.x,e.y,q.a[1]*2,q.a[2]*2+512,0,q.lane)
  assert(not(ok and(lane==q.lane or t)),'off-checkpoint wall admitted a cell')
  report.tested=report.tested+1;report.blocked=report.blocked+1;report.segments[q.organ..':'..q.lane]=true
 else report.skippedProjection=report.skippedProjection+1 end
end
return report
'''))
    assert result['tested']>=100,result
    result['segmentCount']=len(result.pop('segments'));assert result['segmentCount']==len(groups),result
    result['status']='PASS';(DOC/'boundary-checks.json').write_text(json.dumps(result,indent=2)+'\n');print(result,flush=True)

if __name__=='__main__':main()
