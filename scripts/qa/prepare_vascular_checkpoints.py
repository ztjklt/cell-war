"""Two small, explicitly registered membrane apertures per in-organ capillary.

Approved organ floors, vessels, grids and outlines are immutable. Only the new
local throat capsules and the gate contract lists are authored here.
"""
from pathlib import Path
import sys,json,math
sys.path.insert(0,str(Path(__file__).parent))
from check_gastric_battlefield import runtime,convert
from prepare_vessel_channels_runtime import rings,lua
from build_fullbody_vascular_material import svg_geometry
from shapely.geometry import Polygon,Point,LineString
from shapely.ops import unary_union
ROOT=Path(__file__).resolve().parents[2]
DOC=ROOT/'docs/vascular-checkpoints-20261015'

def shape(rows):
    return unary_union([Polygon(r['outer'],r.get('holes')or[])for r in rows])

def main():
    DOC.mkdir(exist_ok=True)
    source_path=DOC/'source.json'
    if not source_path.exists():
        l=runtime()
        source=convert(l.execute('''
local O=require('war.OrganBattlefield');local s=require('war.FullBodyBattlefield').new(73)
local net=O.net(s);local out={organs={},edges={}}
local visible=require('war.VesselChannelsData').bloodLanes
for lane,e in ipairs(net.edges)do
 if e.system=='capillary'and visible[lane]then out.edges[tostring(lane)]={lane=lane,width=e.width,points=e.points,name=e.name}end
end
for _,id in ipairs(O.activeOrgans(s))do
 local d=O.organ(id);local q={tissue={},blood={}}
 for _,kind in ipairs({'scout','siege'})do
  q.tissue[kind]=d.grids[kind].safeRings;q.blood[kind]={}
  for lane,b in pairs(d.bloodLanes[kind])do
   if out.edges[tostring(lane)]then q.blood[kind][tostring(lane)]=b.safeRings end
  end
 end
 out.organs[id]=q
end
return out
'''))
        source_path.write_text(json.dumps(source,separators=(',',':')))
    else:source=json.loads(source_path.read_text())
    outlines={q['id']:svg_geometry(q['outlinePath'])for q in json.loads((ROOT/'docs/organ-style-20261015/source-manifest.json').read_text())['organs']}
    obstacle_file=ROOT/'docs/styled-organ-obstacles-20261015/obstacles.json'
    obstacles={q['id']:shape(q['obstacleRings'])for q in json.loads(obstacle_file.read_text())}if obstacle_file.exists()else{}
    organs={};ports=[];proof=[];missing=[]
    for oid,d in sorted(source['organs'].items()):
        tissue={k:shape(d['tissue'][k])for k in ('scout','siege')}
        props=obstacles.get(oid,Polygon())
        for k,radius in [('scout',.21875),('siege',.53125)]:
            tissue[k]=tissue[k].difference(props.buffer(radius+.025))
        blood={k:{int(lane):shape(v)for lane,v in d['blood'][k].items()}for k in tissue}
        contracts={k:[]for k in tissue}
        for lane,domain in sorted(blood['siege'].items()):
            # Heart's engine borrows these lung lanes for pulmonary routing;
            # their membrane interfaces belong to the lungs, not myocardium.
            if oid=='heart'and lane in (4,7):continue
            # The old gastric capillary is superseded by the registered wall-service lane.
            if oid=='stomach'and lane==124 and 202 in blood['siege']:continue
            edge=source['edges'][str(lane)]
            line=LineString([(p[0]/2,(p[1]-512)/2)for p in edge['points']])
            candidates=[]
            for step in range(1,max(2,int(line.length*2))):
                distance=step*.5;a=line.interpolate(distance)
                near=line.interpolate(max(0,distance-.15));far=line.interpolate(min(line.length,distance+.15))
                dx,dy=far.x-near.x,far.y-near.y;length=math.hypot(dx,dy)
                if length<1e-8 or not domain.contains(a):continue
                for sign in (-1,1):
                    nx,ny=-dy/length*sign,dx/length*sign
                    for gap in (edge['width']/4+1.0,edge['width']/4+1.6,edge['width']/4+2.2,edge['width']/4+3):
                        b=Point(a.x+nx*gap,a.y+ny*gap)
                        corridor=LineString([a,b]);raw=corridor.buffer(1.3,quad_segs=8)
                        if raw.intersects(props.buffer(.025)):continue
                        if not outlines[oid].covers(raw):continue
                        if any(not tissue[k].buffer(-.06).contains(b)or not blood[k][lane].contains(a)for k in tissue):continue
                        # Keep the connector short, with both endpoints in the same organ.
                        if oid=='liver'and any(not outlines[oid].contains(p)for p in (a,b)):continue
                        candidates.append(dict(a=list(a.coords[0]),b=list(b.coords[0]),raw=raw,along=distance,gap=gap,tangent=[dx/length,dy/length]))
                        break
            if not candidates:
                missing.append([oid,lane,'no safe candidates']);continue
            # Maximise separation on this purple segment, rather than placing two adjacent doors.
            low=min(c['along']for c in candidates);high=max(c['along']for c in candidates)
            chosen=[]
            for preferred in (low+(high-low)*.18,low+(high-low)*.82):
                options=[c for c in candidates if all(Point(c['a']).distance(Point(q['a']))>=4 for q in chosen)]
                if not options:break
                chosen.append(min(options,key=lambda c:(abs(c['along']-preferred),c['gap'])))
            if len(chosen)!=2:
                missing.append([oid,lane,'cannot separate two gates']);continue
            for i,c in enumerate(chosen,1):
                gid=f'{oid}.capillary.{lane}.checkpoint.{i}'
                for kind,radius in [('scout',.21875),('siege',.53125)]:
                    safe=c['raw'].buffer(-radius-.02)
                    assert safe.covers(LineString([c['a'],c['b']]))
                    contracts[kind].append(dict(id=gid,organId=oid,laneIndex=lane,
                        pipeAnchorSource=c['a'],tissueAnchorSource=c['b'],throatRings=rings(safe),
                        rawThroatRings=rings(c['raw']),radiusSource=1.3,openingWidthSource=2.6))
                ports.append(dict(id=gid,organId=oid,lane=lane,a=c['a'],b=c['b'],tangent=c['tangent'],width=2.6))
            proof.append(dict(organ=oid,lane=lane,count=2,availableArc=high-low))
        organs[oid]=contracts
    (DOC/'geometry-checks.json').write_text(json.dumps(dict(segments=proof,missing=missing,count=len(ports)),indent=2)+'\n')
    print(json.dumps(dict(segments=len(proof),gates=len(ports),missing=missing)),flush=True)
    assert not missing,missing
    assert all(organs[oid]['siege']for oid in organs),'organ without a checkpoint'
    data=dict(version=1,organs=organs,ports=ports)
    (ROOT/'scripts/war/VascularCheckpointsData.lua').write_text('-- Generated by prepare_vascular_checkpoints.py; two fixed apertures per organ capillary.\nreturn '+lua(data)+'\n')
    (DOC/'ports.json').write_text(json.dumps(ports,indent=2)+'\n')

if __name__=='__main__':main()
