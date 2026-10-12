"""Annotate the original reference with graph-owned and projected vessel overlaps.

No raster generation, runtime installation, authoring-point edits or save migration.
Requires the existing local Shapely QA environment; node computes the editor's exact curves.
"""
from pathlib import Path
import base64
import collections
import hashlib
import json
import math
import subprocess
from html import escape

from shapely import make_valid, union_all
from shapely.geometry import LineString, Point, Polygon
from shapely.ops import nearest_points

ROOT = Path(__file__).resolve().parents[2]
D = ROOT / 'docs/body-life/vascular-art-study'
read = lambda name: json.loads((D / name).read_text())
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
draft_path = D / 'user-drafts/stomach-20261010-original.json'
baseline = read('navigation-review-data.json')['network']
draft = read('user-drafts/stomach-20261010-original.json')
canonical = read('network.json')
passages = read('passages-data.json')
contract = read('interface-contract.json')
ownership = read('organ-layers.json')
central = read('central-vessel-connections.json')
before_hash = sha(draft_path)

NODE = r"""
const fs=require('node:fs'),C=require('./docs/body-life/vascular-art-study/vascular-editor-core.js');
const b=JSON.parse(fs.readFileSync('docs/body-life/vascular-art-study/navigation-review-data.json')).network;
let h=2166136261;for(const ch of JSON.stringify(b.edges))h=Math.imul(h^ch.charCodeAt(0),16777619);
const doc=C.validate(JSON.parse(fs.readFileSync(process.argv[1])),`navigation-${(h>>>0).toString(16)}`);
const curves=C.curvedNetwork(doc.edges,.8),out=[];
for(const e of doc.edges){const curve=curves.get(e.id),samples=[];
 for(const s of curve.segments){const l=C.distance(s[0],s[1])+C.distance(s[1],s[2])+C.distance(s[2],s[3]),n=Math.max(8,Math.ceil(l/.15));
  for(let i=0;i<n;i++){const t=i/n,u=1-t;samples.push(s[0].map((_,j)=>u*u*u*s[0][j]+3*u*u*t*s[1][j]+3*u*t*t*s[2][j]+t*t*t*s[3][j]));}}
 samples.push(curve.samples.at(-1));out.push({id:e.id,d:curve.d,samples});}
process.stdout.write(JSON.stringify({curves:out,audit:C.inspectDraft(doc.edges,b.edges,b.gates,curves),changes:C.changes(doc.edges,b.edges)}));
"""
native = json.loads(subprocess.run(['node', '-e', NODE, str(draft_path)], cwd=ROOT,
                                 check=True, capture_output=True, text=True).stdout)
assert native['changes'] == {'added': [], 'deleted': [], 'modified': ['study.stomach.wall_service']}
assert len(draft['edges']) == len(native['curves']) == 202
for eid in central['preservedEdges']:
    assert next(e for e in draft['edges'] if e['id'] == eid) == next(e for e in baseline['edges'] if e['id'] == eid)

def polygon_set(rings):
    positive = [make_valid(Polygon(r['points'])) for r in rings if not r.get('hole')]
    negative = [make_valid(Polygon(r['points'])) for r in rings if r.get('hole')]
    result = union_all(positive)
    return result.difference(union_all(negative)) if negative else result

def pieces(geometry):
    if geometry.is_empty:
        return []
    if geometry.geom_type == 'LineString':
        return [list(map(list, geometry.coords))] if geometry.length > .001 else []
    if geometry.geom_type in ('MultiLineString', 'GeometryCollection'):
        return [p for item in geometry.geoms for p in pieces(item)]
    return []

def display_pieces(geometry):
    return [[[round(x, 4), round(y, 4)] for x, y in p] for p in pieces(geometry)]

organs = {z['id']: z for z in passages['zones']}
masks = {oid: polygon_set(z['outlines']) for oid, z in organs.items()}
layers = {z['id']: z for z in ownership['zones']}
old = {e['id']: e for e in canonical['edges']}
edges = {e['id']: e for e in draft['edges']}
curve = {c['id']: c for c in native['curves']}
lines = {eid: LineString(c['samples']) for eid, c in curve.items()}
aliases = {'coronary': 'heart', 'colon_proximal': 'large_intestine', 'colon_distal': 'large_intestine',
           'brain_r': 'brain', 'brain_l': 'brain'}
heart_nodes = {'heart.v', 'right_heart', 'left_heart', 'aortic_root', 'pulmonary_trunk'}
heart_pulmonary_edges = {'e003', 'e005', 'e006', 'e008', 'e172', 'e173', 'e174', 'e175'}

def belongs(node, oid):
    return any(node == prefix or (node or '').startswith(prefix + '.') for prefix in layers[oid]['nodeNamespaces'])

def affiliation(e, oid):
    if oid == 'heart' and (e.get('a') in heart_nodes or e.get('b') in heart_nodes or e['id'] in heart_pulmonary_edges):
        return 'heart_hub', '心脏循环枢纽／心肺接续；不自动开放心肌组织入口'
    if e['id'] in layers[oid]['extraStudyEdges']:
        return 'pending', '胃壁所属草稿；新末端贴合供血节点，但命名连接及两个出口仍待重配'
    a, b = belongs(e.get('a'), oid), belongs(e.get('b'), oid)
    if a and b:
        return 'internal', '该器官所属内部血管；组织进出仍限于指定膜口'
    if a or b:
        return 'port_branch', '以命名节点接到该器官的供血／回流支线'
    return None, None

records = []
for oid, mask in masks.items():
    for eid, e in edges.items():
        radius = e['lumenWidthSource'] / 2
        pipe = lines[eid].buffer(radius, quad_segs=8)
        overlap = pipe.intersection(mask)
        if overlap.is_empty or overlap.area < 1e-5:
            continue
        clipped = lines[eid].intersection(mask.buffer(radius, quad_segs=8))
        shown = display_pieces(clipped)
        if not shown:
            continue
        relation, basis = affiliation(e, oid)
        group = old.get(eid, {}).get('group', 'study')
        if relation:
            category = 'pending' if relation == 'pending' else 'connect'
            decision = basis
        elif group in {'systemic', 'portal', 'head', 'limbs', 'heart', 'pulmonary'} or eid in central['preservedEdges']:
            category = 'occlude'
            decision = '无该器官命名接入口；保留贯通主干／既定头四肢坐标，器官前景遮挡此投影段'
        else:
            category = 'reroute'
            decision = '无该器官命名接入口；局部供回支线建议沿器官外侧绕开，保持原分叉和目标接口'
        label = f'{organs[oid]["name"]} · {eid}'
        if relation == 'heart_hub':
            decision += '；0.15 保持血管通道与心肌战场分开'
        if category == 'occlude':
            decision += '；指挥层需保留单位位置提示，不能把部队完全藏掉'
        records.append({'id': f'O{len(records)+1:03}', 'organ': oid, 'organName': organs[oid]['name'],
                        'edgeId': eid, 'category': category, 'relation': relation,
                        'label': label, 'reason': decision, 'segments': shown,
                        'sourceMidpoint': list(clipped.interpolate(.5, normalized=True).coords)[0],
                        'centerlineInsideLengthSource': round(lines[eid].intersection(mask).length, 3),
                        'contactAreaSource': round(overlap.area, 3), 'group': group,
                        'confidence': 'existing_named_graph' if category == 'connect' else 'design_proposal',
                        'boundaryKind': organs[oid]['boundaryKind'], 'movementCertified': False})

food_geometries = {}
for p in passages['edges']:
    food_geometries[p['id']] = (union_all([Polygon(poly) for poly in passages['foodUnion']])
                                if p['id'] == 'food.stomach'
                                else LineString(p['points']).buffer(p['width']/2, quad_segs=12))
passage_conflicts = []
for p in passages['edges']:
    mask = food_geometries[p['id']]
    for eid, e in edges.items():
        radius = e['lumenWidthSource']/2
        contact = lines[eid].buffer(radius, quad_segs=8).intersection(mask)
        if contact.is_empty or contact.area < 1e-5:
            continue
        clipped = lines[eid].intersection(mask.buffer(radius, quad_segs=8))
        shown = display_pieces(clipped)
        if not shown:
            continue
        owned = [oid for oid in p['owners'] if affiliation(e, oid)[0]]
        trunk = old.get(eid, {}).get('group') in {'systemic', 'portal', 'head', 'limbs', 'heart', 'pulmonary'}
        resolution = 'separate_depth' if trunk and not owned else 'reserve_visible_corridor'
        if eid in heart_pulmonary_edges and p['system'] == 'air':
            resolution = 'separate_depth'
        passage_conflicts.append({'id': f'P{len(passage_conflicts)+1:03}', 'edgeId': eid,
                                 'passageId': p['id'], 'passageName': p['name'], 'system': p['system'],
                                 'owners': p['owners'], 'organOwners': owned,
                                 'segments': shown, 'sourceMidpoint': list(clipped.interpolate(.5, normalized=True).coords)[0],
                                 'resolution': resolution,
                                 'reason': ('主干保持深层独立通路，前景遮挡；此交叉不能创建食物／气道／尿路入口'
                                            if resolution == 'separate_depth' else
                                            '0.15 可玩血管通道须与此腔道分开；优先沿壁另留走廊，无法避开的短段再采用独立深度'),
                                 'movementCertified': False})

def port_edge(port, rid):
    candidates = [e for e in edges.values() if e.get('a') == port['id'] or e.get('b') == port['id']]
    own = [e for e in candidates if belongs(e.get('a'), aliases.get(rid, rid)) and belongs(e.get('b'), aliases.get(rid, rid))]
    assert len(own) == 1, (port['id'], [e['id'] for e in own])
    return own[0]

ports, channels = [], []
for region in contract['regions']:
    oid = aliases.get(region['id'], region['id'])
    if oid not in masks:
        continue
    for p in region['ports']:
        ports.append({**p, 'organ': oid, 'organName': organs[oid]['name'], 'region': region['id'],
                      'kind': 'tissue_exit' if p['role'] == 'controlledTissueAccess' else 'named_port',
                      'insideVisualOutline': bool(masks[oid].covers(Point(p['source']))),
                      'distanceToOutlineSource': round(masks[oid].distance(Point(p['source'])), 3)})
        if p['role'] == 'controlledTissueAccess':
            continue
        e = port_edge(p, region['id'])
        samples = curve[e['id']]['samples']
        if e['b'] == p['id']:
            samples = list(reversed(samples))
        assert math.dist(samples[0], p['source']) < 1e-6
        start_inside = masks[oid].covers(Point(samples[0]))
        chosen, entered, length = [p['source']], False, 0.
        inside_run = 0.
        for index, point in enumerate(samples[1:], 1):
            step = math.dist(samples[index-1], point)
            length += step
            chosen.append(point)
            if masks[oid].covers(Point(point)):
                entered = True
                inside_run += step
                if inside_run >= 3 and length >= 4:
                    break
            else:
                inside_run = 0
        assert entered, (oid, e['id'], 'never enters its own organ')
        line = LineString(chosen)
        foreign = [{'organ': other, 'name': organs[other]['name'],
                    'lengthSource': round(line.intersection(mask).length, 3)}
                   for other, mask in masks.items() if other != oid and line.intersection(mask).length > .05]
        special = [{'id': pid, 'name': next(p['name'] for p in passages['edges'] if p['id'] == pid),
                    'lengthSource': round(line.intersection(mask).length, 3)}
                   for pid, mask in food_geometries.items() if line.intersection(mask).length > .05]
        channels.append({'id': f'C{len(channels)+1:02}', 'organ': oid, 'organName': organs[oid]['name'],
                         'region': region['id'], 'portId': p['id'], 'role': p['role'], 'edgeId': e['id'],
                         'frozenSource': p['source'], 'targetSource': chosen[-1], 'points': chosen,
                         'startsInsideOutline': bool(start_inside), 'lengthSource': round(line.length, 3),
                         'crossedOrgans': foreign, 'crossedPassages': special,
                         'status': '0.15_CHANNEL_PROPOSAL_ON_EXISTING_EDGE', 'movementCertified': False,
                         'newBloodGraphConnection': False,
                         'reason': '冻结供回口沿原血管进入本器官；0.15 时将该短段画成可读的血管通道，组织入口仍使用独立膜口'})

for oid in organs:
    assert any(r['organ'] == oid for r in records), ('no organ coverage', oid)
    assert any(p['organ'] == oid and p['kind'] == 'named_port' for p in ports)
assert sum(c['organ'] == 'liver' for c in channels) == 3
assert sha(draft_path) == before_hash
categories = dict(collections.Counter(r['category'] for r in records))
result = {'version': 1, 'status': 'WHOLE_BODY_OVERLAP_DESIGN_REVIEW_NOT_RUNTIME',
          'coordinates': {'width': 1024, 'height': 1536, 'worldScale': 2, 'worldOffset': [0,512],
                          'logicalPixelsPerSourceAtZoom015': 9.6},
          'reference': 'coverage-reference.png', 'referenceSha256': sha(ROOT/'assets/image/anatomy-reference/reference.png'),
          'draft': 'user-drafts/stomach-20261010-original.json', 'curveStrength': .8,
          'sourceHashes': {name: sha(D/name) for name in ['user-drafts/stomach-20261010-original.json',
                           'navigation-review-data.json', 'passages-data.json', 'interface-contract.json', 'organ-layers.json']},
          'organs': [{**z, 'bounds': list(masks[z['id']].bounds)} for z in passages['zones']],
          'edges': [{**e, 'd': curve[e['id']]['d']} for e in draft['edges']],
          'records': records, 'ports': ports, 'channels': channels, 'passageConflicts': passage_conflicts,
          'protectedPassages': passages['edges'], 'stomachFoodUnion': passages['foodUnion'],
          'draftAudit': native['audit'], 'changes': native['changes'],
          'counts': {'organs': len(organs), 'vessels': len(edges), 'organVesselPairs': len(records),
                     'categories': categories, 'namedPorts': sum(p['kind']=='named_port' for p in ports),
                     'tissueExits': sum(p['kind']=='tissue_exit' for p in ports), 'channels015': len(channels),
                     'passageConflictPairs': len(passage_conflicts)},
          'checks': {'everyOrganRepresented': True, 'everyInterfaceChannelKeepsFrozenStart': True,
                     'sourceDraftBytesUnchanged': True, 'headAndLimbEdgesUnchanged': 116,
                     'all202CurvesExaminedAgainstAll12OrganMasks': True,
                     'centerlineMaxSampleStepSource': .15, 'pipeRadiusIncluded': True,
                     'onlyNamedNodesCreateConnections': True, 'clinicalDepthCertified': False,
                     'nativeConfirmed': False, 'newMovementCertified': False, 'productionInstalled': False},
          'limitations': ['原图中未编码的细小装饰血管不作自动拓扑判定；本图覆盖当前202条设计线。',
                          '脑与膀胱沿用定位轮廓，边缘附近标记需进一步精细复核。',
                          '遮挡与绕开是游戏切面设计建议，不是已证实的解剖深度。',
                          '绿色表示现有命名接入关系，不表示食物净空或细胞通行已通过。',
                          '0.15接入通道沿现有曲线提出；需独立确定管壁、半径、膜口与混合细胞通行。']}
(D/'vascular-organ-overlap-data.json').write_text(json.dumps(result, ensure_ascii=False, separators=(',',':'))+'\n')
# A standalone vector annotation, with the unchanged original raster embedded.
def svg_path(points):
    return 'M ' + ' L '.join(f'{x:.4f} {y:.4f}' for x, y in points)

palette = {'connect': '#288665', 'reroute': '#dc852e', 'occlude': '#467ab8', 'pending': '#9e61ba'}
encoded = base64.b64encode((ROOT/'assets/image/anatomy-reference/reference.png').read_bytes()).decode()
svg = ['<svg xmlns="http://www.w3.org/2000/svg" width="1064" height="1630" viewBox="-20 -80 1064 1630">',
       '<title>全身血管与器官重合标注 · 1024×1536原图坐标</title>',
       '<rect x="-20" y="-80" width="1064" height="1630" fill="#f7f7f1"/>',
       '<text x="20" y="-58" font-family="sans-serif" font-size="24" fill="#263f32">全身血管与器官重合 · 设计审查稿</text>',
       '<text x="20" y="-33" font-family="sans-serif" font-size="17" fill="#4d5f51">绿：已有连接　橙：建议绕开　蓝虚线：可以遮挡　紫：待接入</text>',
       '<text x="20" y="-10" font-family="sans-serif" font-size="16" fill="#4d5f51">完整血管底线：红色供血　蓝色回流　灰紫色交换</text>',
       f'<image width="1024" height="1536" href="data:image/png;base64,{encoded}" opacity=".72"/>']
for z in passages['zones']:
    d = ' '.join(svg_path(r['points'])+' Z' for r in z['outlines'])
    svg.append(f'<path d="{d}" fill="none" stroke="#636c60" stroke-width="1.2" stroke-dasharray="4 3"/>')
vessel_palette = {'artery': '#b85350', 'vein': '#3b77a6', 'capillary': '#726877'}
for edge in result['edges']:
    color = vessel_palette.get(edge['system'], vessel_palette['capillary'])
    svg.append(f'<path data-base-edge="{edge["id"]}" d="{edge["d"]}" fill="none" stroke="{color}" stroke-width="{max(edge["lumenWidthSource"], 2.5)}" stroke-opacity=".88" stroke-linecap="round" stroke-linejoin="round"/>')
for r in records:
    dash = ' stroke-dasharray="6 4"' if r['category']=='occlude' else ' stroke-dasharray="3 2"' if r['category']=='pending' else ''
    for segment in r['segments']:
        svg.append(f'<path data-record="{r["id"]}" d="{svg_path(segment)}" fill="none" stroke="{palette[r["category"]]}" stroke-width="3.2" stroke-linecap="round"{dash}><title>{escape(r["id"]+" "+r["label"]+" "+r["reason"])}</title></path>')
for p in ports:
    if p['kind']!='named_port':
        continue
    x, y = p['source']
    svg.append(f'<circle cx="{x}" cy="{y}" r="3.2" fill="#edf3db" stroke="#27624e" stroke-width="1.4"/>')
callouts={'brain':[640,65],'lung_r':[245,340],'lung_l':[755,343],'heart':[755,417],
          'liver':[228,500],'stomach':[755,520],'pancreas':[755,585],'kidney_r':[228,600],
          'kidney_l':[755,635],'large_intestine':[755,690],'small_intestine':[228,697],'bladder':[755,781]}
for z in result['organs']:
    anchor=callouts[z['id']]; b=z['bounds'];mid=[(b[0]+b[2])/2,(b[1]+b[3])/2]
    svg.append(f'<path d="{svg_path([mid,anchor])}" fill="none" stroke="#526d5b" stroke-width=".9"/>')
    svg.append(f'<text x="{anchor[0]}" y="{anchor[1]}" font-family="sans-serif" font-size="18" text-anchor="{"end" if anchor[0]<512 else "start"}" fill="#263f32">{escape(z["name"])}</text>')
svg.append('</svg>')
(D/'vascular-organ-overlap-overview.svg').write_text('\n'.join(svg)+'\n')
print(json.dumps(result['counts'], ensure_ascii=False))
print('foreign channel approaches:', [(c['portId'], c['crossedOrgans']) for c in channels if c['crossedOrgans']])
