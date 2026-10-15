"""Export complete blood geometry without organ/depth clips for art review.

This is an offline export, not a runtime installation. Existing GPT strip
pixels are sampled using the project's established material mapper. Geometry
comes from the current live Lua network, including the latest route repairs.
"""
from collections import Counter, defaultdict
from pathlib import Path
from types import SimpleNamespace
import hashlib
import json
import math
import sys

import numpy as np
from PIL import Image
from lupa.lua54 import LuaRuntime
from scipy.ndimage import map_coordinates
from shapely.geometry import LineString, Point, Polygon, box
from shapely.ops import unary_union

sys.path.insert(0, str(Path(__file__).parent))
from build_fullbody_vascular_material import Bake, mask, geometry_path

ROOT = Path(__file__).resolve().parents[2]
ASSET = ROOT / 'assets/image/anatomy-reference/vascular-study/standalone-vessels-20261015'
OUT = ROOT / 'docs/standalone-vessels-20261015'
SCALE = 4
FRAME = [0, 0, 1024, 1536]


def convert(v):
    if hasattr(v, 'items'):
        pairs = list(v.items())
        if pairs and all(isinstance(k, int) for k, _ in pairs) and sorted(k for k, _ in pairs) == list(range(1, len(pairs)+1)):
            return [convert(v[i]) for i in range(1, len(pairs)+1)]
        return {k: convert(q) for k, q in pairs}
    return v


def shape(rings):
    values = rings.values() if isinstance(rings, dict) else rings
    return unary_union([Polygon(r['outer'], r.get('holes', []) or []) for r in values]).buffer(0)


def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def main():
    ASSET.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("package.path='scripts/?.lua;'..package.path;print=function()end")

    def module(name):
        result = lua.eval("require('war."+name+"')")
        return result[0] if isinstance(result, tuple) else result

    organ = module('OrganBattlefield')
    net = organ.net(lua.table_from({'anatomyVersion': 4, 'fullbodyBattlefieldVersion': 1}))
    raw = {}
    for name in ['HeartBattlefieldData', 'BowelBattlefieldData', 'VascularRouteRepairData']:
        for lane, rings in convert(module(name))['rawBloodDomains'].items():
            raw[int(lane)] = shape(rings)
    nodes = {i: dict(id=n.id, source=[n.x*.5, (n.y-512)*.5]) for i, n in net.nodes.items()}
    records, edges = [], []
    for lane, e in net.edges.items():
        if e.system not in ('artery', 'vein', 'capillary'):
            continue  # Cardiac chambers/valves belong to the heart organ layer.
        points = [[p[1]*.5, (p[2]-512)*.5] for _, p in e.points.items()]
        a, b = nodes[e.a], nodes[e.b]
        assert math.dist(points[0], a['source']) < 1e-6
        assert math.dist(points[-1], b['source']) < 1e-6
        record = dict(lane=lane, id=e.name, a=a['id'], b=b['id'], system=e.system,
                      widthSource=e.width*.5, samples=points, layer={'capillary':20,'vein':30,'artery':40}[e.system])
        records.append(record)
        line = LineString(points)
        physical = raw.get(lane, line.buffer(e.width*.25, quad_segs=12))
        assert physical.buffer(1e-6).covers(line), ('centerline outside physical domain', lane)
        edges.append(dict(record, line=line, materialFootprint=physical,
                          continuousMaterialFootprint=physical, full=physical))

    node_edges = defaultdict(list)
    for e in edges:
        node_edges[e['a']].append((e,e['samples'][0]))
        node_edges[e['b']].append((e,e['samples'][-1]))
    # The same complete incident union owns material banks at real joins.
    # Projected crossings without a shared node remain separate pipes.
    for e in edges:
        additions = [e['full']]
        for node, p in [(e['a'],e['samples'][0]),(e['b'],e['samples'][-1])]:
            incident=node_edges[node]
            radius=max(q['widthSource'] for q,_ in incident)*2
            zone=Point(p).buffer(radius)
            additions.extend(q['full'].intersection(zone) for q,_ in incident)
        e['continuousMaterialFootprint']=unary_union(additions)

    baker = Bake.__new__(Bake)
    baker.args=SimpleNamespace(cyclic_pipe=True)
    baker.edges=edges
    baker.node_edges=node_edges
    baker.boundary_uv_cache={}
    baker.pipe_sources={}
    manifest=json.loads((ROOT/'docs/body-life/vascular-art-study/fullbody-015/bake/manifest.json').read_text())
    for system, item in manifest['pipeMaterials']['materials'].items():
        source_path=ROOT/item['path']
        assert digest(source_path)==item['sha256']
        source=np.asarray(Image.open(source_path).convert('RGBA'))
        x0,y0,x1,y1=item['crop'];source=source[y0:y1,x0:x1]
        opaque=source[:,:,3]>=248
        assert opaque.any(axis=0).all()
        top=opaque.argmax(axis=0);bottom=source.shape[0]-1-opaque[::-1].argmax(axis=0)
        ny,nx=np.mgrid[:source.shape[0],:source.shape[1]]
        mapped_y=top[None,:]+.75+ny/(source.shape[0]-1)*np.maximum(0,bottom-top-1.5)[None,:]
        normalized=np.stack([map_coordinates(source[:,:,c].astype(np.float32),[mapped_y,nx],order=1,mode='nearest') for c in range(3)],axis=2)
        n=max(2,round(normalized.shape[1]*.05))
        for offset in range(n):
            t=1-offset/(n-1);t=t*t*(3-2*t)
            left=normalized[:,offset].copy();right=normalized[:,-1-offset].copy();mid=(left+right)*.5
            normalized[:,offset]=left*(1-t)+mid*t;normalized[:,-1-offset]=right*(1-t)+mid*t
        baker.pipe_sources[system]=dict(item,normalized=np.clip(np.rint(normalized),0,255).astype(np.uint8),filtered={})
    baker.assign_pipe_phases()
    canvas=Image.new('RGBA',(FRAME[2]*SCALE,FRAME[3]*SCALE))

    def render(shape_, material_shape, e):
        if shape_.is_empty:
            return
        x0,y0,x1,y1=shape_.bounds
        bounds=[max(0,math.floor(x0-1)),max(0,math.floor(y0-1)),min(1024,math.ceil(x1+1)),min(1536,math.ceil(y1+1))]
        size=[(bounds[2]-bounds[0])*SCALE,(bounds[3]-bounds[1])*SCALE]
        if min(size)<=0:
            return
        pixels=baker.material(material_shape,bounds,size,e['system'],e['widthSource'],edge=e)
        pixels[:,:,3]=mask(shape_,bounds,size)
        canvas.alpha_composite(Image.fromarray(pixels),(bounds[0]*SCALE,bounds[1]*SCALE))

    for index,e in enumerate(sorted(edges,key=lambda q:(q['layer'],q['lane']))):
        render(e['full'],e['continuousMaterialFootprint'],e)
        if index%35==0:
            print('Vessel material',index+1,'/',len(edges),flush=True)
    # Open each genuine node with a single common floor. Never join crossings.
    for node,incident in node_edges.items():
        if len(incident)<2:
            continue
        p=Point(incident[0][1]);radius=max(e['widthSource']for e,_ in incident)*1.35
        dominant=max(incident,key=lambda ep:(ep[0]['widthSource'],ep[0]['layer']))[0]
        physical=unary_union([e['full']for e,_ in incident])
        patch=physical.intersection(p.buffer(radius))
        ids={e['lane']for e,_ in incident}
        for foreign in edges:
            if foreign['lane']not in ids and foreign['layer']>dominant['layer'] and foreign['full'].intersects(patch):
                patch=patch.difference(foreign['full'])
        render(patch,physical,dict(dominant,flatUnionFloor=True))

    canvas.save(ASSET/'vessels-only.png')
    def preview(image,path,size=None):
        if size:
            image=image.resize(size,Image.Resampling.LANCZOS)
        bg=Image.new('RGBA',image.size,'#faf6f0');bg.alpha_composite(image)
        bg.convert('RGB').save(path)
    preview(canvas,OUT/'vessels-overview.png',(1024,1536))
    torso=[330,250,690,835]
    crop=canvas.crop(tuple(v*SCALE for v in torso))
    preview(crop,OUT/'vessels-torso.png')
    palette={'artery':'#d88783','vein':'#8d94c2','capillary':'#c7909b'}
    svg='<svg xmlns="http://www.w3.org/2000/svg" width="4096" height="6144" viewBox="0 0 1024 1536">'
    for e in sorted(edges,key=lambda q:(q['layer'],q['lane'])):
        svg+=f'<path id="lane-{e["lane"]}" data-edge="{e["id"]}" d="{geometry_path(e["full"])}" fill="{palette[e["system"]]}" fill-rule="evenodd"/>'
    svg+='</svg>'
    (ASSET/'vessels-geometry.svg').write_text(svg)
    adjacency=defaultdict(set)
    for e in records:
        adjacency[e['a']].add(e['b']);adjacency[e['b']].add(e['a'])
    unseen=set(adjacency);components=[]
    while unseen:
        todo=[min(unseen)];seen=set()
        while todo:
            node=todo.pop()
            if node in seen:continue
            seen.add(node);todo.extend(adjacency[node]-seen)
        unseen-=seen;components.append(sorted(seen))
    endpoints=[dict(node=node,source=incident[0][1],lanes=[e['lane']for e,_ in incident]) for node,incident in node_edges.items()if len(incident)==1]
    ports=[]
    order=convert(module('OrganAtlasArtData').order)
    for oid in ['stomach']+order:
        data=convert(organ.organ(oid))
        for gate in data['gateContracts']['scout']:
            ports.append(dict(organ=oid,id=gate['id'],lane=gate['laneIndex'],pipeAnchorSource=gate['pipeAnchorSource'],wallSource=gate.get('wallSource'),role='organ-interface-reference'))
    record=dict(schema='standalone-vessels-review/v1',sourceSize=[1024,1536],pixelSize=list(canvas.size),sourceToPixels=SCALE,
                worldFromSource=dict(scale=2,offset=[0,512]),vesselCount=len(edges),systems=dict(Counter(e['system']for e in records)),
                excludedHeartChamberValveLanes=[i for i,e in net.edges.items()if e.system not in palette],
                organOcclusionApplied=False,foodAirUrineOcclusionApplied=False,sourceGeometryEdited=False,
                runtimeInstalled=False,newGPTGeneration=False,materialProvenance=manifest['pipeMaterials'],
                edges=records,organInterfaces=ports,bloodOnlyComponents=components,terminalNodes=endpoints,
                checks=dict(allVesselEndpointsAligned=True,allCenterlinesInsidePhysicalDomains=True),
                limitations=['Unconnected projected crossings retain separate identity and priority.','Heart chamber and valve paths are excluded; their vessel ports are intentionally left for the separate heart layer.','Organ interfaces are recorded, not cut into the export before visual review.','This exports continuous registered geometry with existing GPT strip material; it is not a pixel-exact extraction of the flattened map or a newly GPT-beautified asset.'],
                sourceHashes={name:digest(ROOT/'scripts/war'/f'{name}.lua')for name in ['OrganBattlefield','HeartBattlefieldData','BowelBattlefieldData','VascularRouteRepairData']})
    (OUT/'manifest.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
    html='''<!doctype html><html lang="zh"><meta charset="utf-8"><title>血管独立图层</title><style>body{margin:0;background:#ece8e1;color:#29252c;font:16px system-ui}header{padding:22px 32px;background:#fff;position:sticky;top:0;z-index:1}h1{font-size:24px;margin:0 0 8px}p{margin:5px 0}a{color:#5d5689}main{display:flex;gap:24px;align-items:flex-start;padding:24px}figure{margin:0;background:repeating-conic-gradient(#eee 0% 25%,#fff 0% 50%) 0/24px 24px}img{display:block;width:100%;height:auto}.whole{width:43%}.torso{width:57%}figcaption{padding:14px;background:#fff}</style><header><h1>血管独立图层 · 初始导出</h1><p>完整管路，无器官、身体底图或器官遮挡截断；保留现有红／蓝／紫血管材质。</p><p>血管端口与器官接口仍需在后续美化时逐处审查。心腔与瓣膜单列，不属于本图层。</p><p><a href="../../assets/image/anatomy-reference/vascular-study/standalone-vessels-20261015/vessels-only.png">4096 × 6144 透明原图</a> · <a href="../../assets/image/anatomy-reference/vascular-study/standalone-vessels-20261015/vessels-geometry.svg">可编辑几何图层 SVG</a> · <a href="manifest.json">坐标与连通记录</a></p></header><main><figure class="whole"><img src="../../assets/image/anatomy-reference/vascular-study/standalone-vessels-20261015/vessels-only.png"><figcaption>全身血管 · 棋盘格仅表示透明背景</figcaption></figure><figure class="torso"><img src="vessels-torso.png"><figcaption>胸腹局部 · 不再随器官遮挡截断</figcaption></figure></main></html>'''
    (OUT/'review.html').write_text(html)
    print(json.dumps(dict(vessels=len(edges),components=len(components),terminalNodes=len(endpoints),interfaces=len(ports),image=str(ASSET/'vessels-only.png')),ensure_ascii=False),flush=True)


if __name__=='__main__':
    main()
