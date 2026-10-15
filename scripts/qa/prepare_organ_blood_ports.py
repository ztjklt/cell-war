"""Register short organ/blood apertures without moving any existing geometry.

Only added membrane capsules change walkability. Both cell profiles are checked
against their existing tissue and blood domains before a candidate is selected.
"""
from pathlib import Path
import json, math, sys, statistics
from PIL import Image
from shapely.geometry import Polygon, LineString, Point
from shapely.ops import unary_union
sys.path.insert(0,str(Path(__file__).parent))
from prepare_vessel_channels_runtime import lua, rings
from build_fullbody_vascular_material import svg_geometry
from lupa.lua54 import LuaRuntime

ROOT=Path(__file__).resolve().parents[2]
DOC=ROOT/'docs/organ-blood-ports-20261015'
ASSET=ROOT/'assets/image/anatomy-reference/organ-blood-ports-20261015'

def shape(rows):
    return unary_union([Polygon(r['outer'],r.get('holes')or[])for r in rows])

def main():
    source=json.loads((DOC/'geometry-input.json').read_text())
    families={e['lane']:e['system']for e in json.loads((ROOT/'docs/standalone-vessels-20261015/manifest.json').read_text())['edges']}
    outlines={q['id']:svg_geometry(q['outlinePath'])for q in json.loads((ROOT/'docs/organ-style-20261015/source-manifest.json').read_text())['organs']}
    runtime=LuaRuntime(unpack_returned_tuples=True)
    runtime.execute("package.path='scripts/?.lua;'..package.path")
    region=runtime.eval("function(x,y)return require('war.OrganRegions').at({anatomyVersion=4},x*2,y*2+512)end")
    additions={};visual=[];proof=[]
    for oid,d in sorted(source['organs'].items()):
        tissue={k:shape(d['grids'][k]['safeRings'])for k in ('scout','siege')}
        blood={k:{int(lane):shape(b['safeRings'])for lane,b in d['bloodLanes'][k].items()}for k in tissue}
        existing=d['gateContracts']['siege'];chosen=list(existing)
        if len(existing)<2:
            candidates=[]
            for lane,domain in blood['siege'].items():
                if lane>202:continue # Cardiac chambers retain their valve contracts.
                edge=source['edges'][lane-1]
                points=[(p[0]/2,(p[1]-512)/2)for p in edge['points']]
                line=LineString(points)
                for distance in range(2,max(3,int(line.length)-1),2):
                    a=line.interpolate(distance);near=line.interpolate(max(0,distance-.2));far=line.interpolate(min(line.length,distance+.2))
                    dx,dy=far.x-near.x,far.y-near.y;length=math.hypot(dx,dy)
                    if length<1e-8 or not domain.contains(a):continue
                    for sign in (-1,1):
                        nx,ny=-dy/length*sign,dx/length*sign
                        for gap in (edge['width']/4+1.2,edge['width']/4+2,edge['width']/4+3):
                            b=Point(a.x+nx*gap,a.y+ny*gap)
                            separation=min(b.distance(Point(g['tissueAnchorSource']))for g in chosen)
                            if separation<10 or not tissue['siege'].buffer(-.2).contains(b):continue
                            corridor=LineString([a,b]);raw=corridor.buffer(1.9,quad_segs=8)
                            if not outlines[oid].covers(raw):continue
                            # A siege cell in the liver retains its existing heart-first
                            # travel rule. Both local test anchors must remain in liver.
                            if oid=='liver'and any(region(p.x,p.y)!='liver'for p in (a,b)):continue
                            # Require a short direct crossing with no second blood lane.
                            if any(corridor.buffer(.65).intersects(q)for n,q in blood['siege'].items()if n!=lane):continue
                            if any(not blood[k][lane].contains(a)or not tissue[k].contains(b)for k in tissue):continue
                            profiles={}
                            for k,radius in [('scout',.21875),('siege',.53125)]:
                                safe=raw.buffer(-radius-.02)
                                if not safe.covers(corridor):break
                                profiles[k]=dict(id=oid+'.blood_connector.2',organId=oid,laneIndex=lane,
                                    pipeAnchorSource=list(a.coords[0]),tissueAnchorSource=list(b.coords[0]),
                                    throatRings=rings(safe),rawThroatRings=rings(raw),radiusSource=1.9,
                                    openingWidthSource=3.8,bidirectionalSweepCovered=True,
                                    status='REGISTERED_SHORT_CONNECTOR',changesBloodTopology=False)
                            if len(profiles)!=2:continue
                            otherFamily=not any(families.get(g['laneIndex'])==families.get(lane)for g in chosen)
                            score=min(separation,60)+20*otherFamily-gap
                            candidates.append((score,profiles))
                            break
            assert candidates,('no safe second aperture',oid)
            _,selected=max(candidates,key=lambda q:q[0]);additions[oid]={k:[g]for k,g in selected.items()}
            chosen.append(selected['siege'])
            proof.append(dict(organ=oid,id=selected['siege']['id'],profiles=list(selected),unchangedBloodLane=selected['siege']['laneIndex']))
        # The five established gastric interfaces remain functional and marked.
        for g in chosen:
            a,b=g['pipeAnchorSource'],g['tissueAnchorSource'];dx,dy=b[0]-a[0],b[1]-a[1];length=math.hypot(dx,dy)
            nx,ny=dx/length,dy/length
            # A short landing extends onto legal organ floor, never through cover.
            landing=list(b)
            for extra in (1.8,1.2,.6):
                p=Point(b[0]+nx*extra,b[1]+ny*extra)
                if tissue['siege'].covers(LineString([b,p])):landing=list(p.coords[0]);break
            visual.append(dict(id=g['id'],organId=oid,lane=g['laneIndex'],family=families.get(g['laneIndex'],'artery'),
                a=a,b=landing,tissueAnchor=b,width=g.get('openingWidthSource',3.8),added=g['id'].endswith('.blood_connector.2')))
    ASSET.mkdir(parents=True,exist_ok=True)
    # Match the pigment at the actual join, including the existing red/blue
    # exchange gradient. A capillary mouth must not suddenly become scarlet.
    pigment=ROOT/'assets/image/anatomy-reference/vascular-study/standalone-vessels-20261015/channels-v3/l32'
    images={}
    for p in visual:
        x,y=p['a'];tx,ty=int(x//64)*64,int(y//64)*64
        key=f'{tx:04}-{ty:04}.png'
        if key not in images:images[key]=Image.open(pigment/key).convert('RGBA')
        im=images[key];px,py=round((x-tx)*32),round((y-ty)*32)
        sample=[im.getpixel((min(im.width-1,max(0,px+dx)),min(im.height-1,max(0,py+dy))))[:3]for dx in range(-2,3)for dy in range(-2,3)]
        floor=[int(statistics.median(q[i]for q in sample))for i in range(3)]
        p['colors']=dict(floor=floor,rim=[round(c+(255-c)*.24)for c in floor],edge=[round(c*.70)for c in floor])
    data=dict(version=1,additions=additions,ports=visual)
    (ROOT/'scripts/war/OrganBloodPortsData.lua').write_text('-- Generated by prepare_organ_blood_ports.py; registered short membrane passages.\nreturn '+lua(data)+'\n')
    (DOC/'ports.json').write_text(json.dumps(dict(ports=visual,additions=proof,counts={oid:sum(v['organId']==oid for v in visual)for oid in source['organs']}),indent=2)+'\n')
    content=[]
    for p in visual:
        a,b=p['a'],p['b'];dx,dy=b[0]-a[0],b[1]-a[1];length=math.hypot(dx,dy);nx,ny=-dy/length,dx/length
        edge,rim,floor=['#'+''.join(f'{c:02x}'for c in p['colors'][k])for k in ('edge','rim','floor')]
        w=p['width'];path=f'M{a[0]} {a[1]} L{b[0]} {b[1]}'
        # Flat open floor; two side rails, no transverse cap blocking either end.
        art=f'<path d="{path}" fill="none" stroke="{rim}" stroke-width="{w+.65}" stroke-linecap="butt"/><path d="{path}" fill="none" stroke="{floor}" stroke-width="{w-1}"/>'
        for sign in (-1,1):
            offset=sign*(w/2-.15);aa=[a[0]+nx*offset,a[1]+ny*offset];bb=[b[0]+nx*offset,b[1]+ny*offset]
            art+=f'<path d="M{aa[0]} {aa[1]} L{bb[0]} {bb[1]}" fill="none" stroke="{edge}" stroke-width=".48" stroke-linecap="round"/>'
        content.append(f'<g id="{p["id"]}" data-organ="{p["organId"]}">{art}</g>')
    (ASSET/'blood-ports.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1536" width="1024" height="1536">'+''.join(content)+'</svg>')
    (ASSET/'manifest.json').write_text(json.dumps(dict(count=len(visual),nativeVector=True,ports=visual),indent=2)+'\n')
    print('Registered',len(visual),'ports;',len(additions),'new apertures',flush=True)

if __name__=='__main__':main()
