"""Freeze a simple, layered art reference without installing a gameplay graph."""
from pathlib import Path
import base64
import collections
import hashlib
import heapq
import json
import math
import subprocess
from html import escape

import numpy as np
import shapely
from shapely import make_valid, union_all
from shapely.geometry import LineString, Point, Polygon
from shapely.ops import substring

ROOT = Path(__file__).resolve().parents[2]
D = ROOT / 'docs/body-life/vascular-art-study'
read = lambda name: json.loads((D / name).read_text())
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
review = read('vascular-organ-overlap-data.json')
draft = read(review['draft'])
central = read('central-vessel-connections.json')
contract = read('interface-contract.json')
nav = read('navigation-review-data.json')['network']
layers = read('organ-layers.json')
edges = json.loads(json.dumps(draft['edges']))
original = {e['id']: e for e in draft['edges']}
by_id = {e['id']: e for e in edges}
protected = set(central['preservedEdges'])
names = {o['id']: o['name'] for o in review['organs']}
ownership = {z['id']: z for z in layers['zones']}


def polygon_set(rings):
    positive = union_all([make_valid(Polygon(r['points'])) for r in rings if not r.get('hole')])
    negative = union_all([make_valid(Polygon(r['points'])) for r in rings if r.get('hole')])
    return positive.difference(negative)


masks = {o['id']: polygon_set(o['outlines']) for o in review['organs']}
food = union_all([Polygon(p) for p in review['stomachFoodUnion']])


def belongs(e, oid):
    prefixes = ownership[oid]['nodeNamespaces']
    return any(n == p or (n or '').startswith(p + '.') for n in [e.get('a'), e.get('b')] for p in prefixes)


NODE = r"""
const fs=require('node:fs'),C=require('./docs/body-life/vascular-art-study/vascular-editor-core.js');
const edges=JSON.parse(fs.readFileSync(0,'utf8'));const curves=C.curvedNetwork(edges,.8),out=[];
for(const e of edges){const c=curves.get(e.id),samples=[];
 for(const s of c.segments){const l=C.distance(s[0],s[1])+C.distance(s[1],s[2])+C.distance(s[2],s[3]),n=Math.max(8,Math.ceil(l/.15));
 for(let i=0;i<n;i++){const t=i/n,u=1-t;samples.push(s[0].map((_,j)=>u*u*u*s[0][j]+3*u*u*t*s[1][j]+3*u*t*t*s[2][j]+t*t*t*s[3][j]));}}
 samples.push(c.samples.at(-1));out.push({id:e.id,d:c.d,segments:c.segments,samples});}
process.stdout.write(JSON.stringify(out));
"""


def curves_for(items):
    return {c['id']: c for c in json.loads(subprocess.run(['node', '-e', NODE], cwd=ROOT,
        input=json.dumps(items), text=True, check=True, capture_output=True).stdout)}


old_curves = curves_for(draft['edges'])
reroute_ids = sorted({r['edgeId'] for r in review['records'] if r['category'] == 'reroute'})
route_choices = {}


def exterior_route(e, obstacles):
    """Small grid only finds a simple outer detour. Endpoints stay exact, including deep roots."""
    obstacle = union_all(obstacles).buffer(e['lumenWidthSource'] / 2 + 4)
    xs = np.arange(372., 634., 2.)
    ys = np.arange(464., 790., 2.)
    xx, yy = np.meshgrid(xs, ys)
    free = ~shapely.intersects_xy(obstacle, xx, yy)
    points = np.column_stack([xx[free], yy[free]])
    indices = np.column_stack(np.where(free))
    if not len(points):
        return None
    def nearest(p):
        k = np.argmin(np.sum((points - p) ** 2, axis=1))
        return tuple(indices[k])
    start, goal = nearest(e['points'][0]), nearest(e['points'][-1])
    def coordinate(index):
        return [float(xs[index[1]]), float(ys[index[0]])]
    q = [(0., start)]
    cost = {start: 0.}
    previous = {}
    while q:
        _, here = heapq.heappop(q)
        if here == goal:
            break
        for dy, dx in [(0, 1), (0, -1), (1, 0), (-1, 0), (1, 1), (1, -1), (-1, 1), (-1, -1)]:
            nxt = here[0] + dy, here[1] + dx
            if not (0 <= nxt[0] < len(ys) and 0 <= nxt[1] < len(xs)) or not free[nxt]:
                continue
            if dx and dy and (not free[here[0], nxt[1]] or not free[nxt[0], here[1]]):
                continue
            value = cost[here] + math.hypot(dx, dy)
            if value >= cost.get(nxt, float('inf')):
                continue
            cost[nxt] = value
            previous[nxt] = here
            heapq.heappush(q, (value + math.hypot(nxt[0]-goal[0], nxt[1]-goal[1]), nxt))
    if goal not in cost:
        return None
    path, at = [goal], goal
    while at != start:
        at = previous[at]
        path.append(at)
    path = [coordinate(p) for p in reversed(path)]
    # Greedy line-of-sight simplification; the safety buffer accommodates cubic rounding.
    simple, index = [path[0]], 0
    while index < len(path)-1:
        end = len(path)-1
        while end > index+1 and LineString([path[index], path[end]]).intersects(obstacle):
            end -= 1
        simple.append(path[end])
        index = end
    result = [e['points'][0]] + simple + [e['points'][-1]]
    result = [p for i, p in enumerate(result) if i == 0 or math.dist(p, result[i-1]) > .01]
    # Grid snap points immediately beside a fixed node are not authoring bends.
    while len(result)>2 and math.dist(result[0],result[1])<3:
        result.pop(1)
    while len(result)>2 and math.dist(result[-1],result[-2])<3:
        result.pop(-2)
    for i in range(len(result)-3,0,-1):
        if math.dist(result[i],result[i+1])<3:
            result.pop(i)
    return result


for eid in reroute_ids:
    e = by_id[eid]
    foreign = [r['organ'] for r in review['records'] if r['edgeId'] == eid and r['category'] == 'reroute']
    all_foreign = [mask for oid, mask in masks.items() if not belongs(e, oid)]
    proposed = exterior_route(e, all_foreign)
    old_length = LineString(old_curves[eid]['samples']).length
    # Avoid long loops and busy shapes solely to escape a 2D projection at a frozen port.
    border_only = all(lines_length <= 2 for lines_length in
        [LineString(old_curves[eid]['samples']).intersection(masks[oid]).length for oid in foreign])
    accepted = not border_only and old_length>=35 and proposed is not None and len(proposed) <= 8 and LineString(proposed).length <= max(old_length * 2.1, old_length + 45)
    if accepted:
        e['points'] = proposed
    route_choices[eid] = {'edgeId': eid, 'organs': foreign,
        'mode': 'outer_detour_with_fixed_approaches' if accepted else 'fixed_deep_connector',
        'sourcePoints': original[eid]['points'], 'sourceD': old_curves[eid]['d'], 'finalPoints': e['points'],
        'reason': '外侧以少量弧线绕行；冻结口附近仍保留明确的深层接续。' if accepted else
                  '固定接口位于其他器官投影内或贴边；采用已定位的独立深层接续，避免长绕路和额外分支。'}

# Keep the user-authored contour exactly, while supplying the correct directed named connection.
wall = by_id['study.stomach.wall_service']
wall['points'] = list(reversed(wall['points']))
wall['a'], wall['b'] = 'stomach.a', 'stomach.v'
wall['system'], wall['oxygen'], wall['flowSign'] = 'capillary', 'exchange', 1
curves = curves_for(edges)
for eid in protected:
    curves[eid] = old_curves[eid]
# The user wall curve is frozen too: reverse cubic controls instead of refitting its silhouette.
segments = [[s[3], s[2], s[1], s[0]] for s in reversed(old_curves[wall['id']]['segments'])]
curves[wall['id']] = {'id': wall['id'], 'segments': segments,
    'samples': list(reversed(old_curves[wall['id']]['samples'])),
    'd': 'M ' + ' '.join(map(str, segments[0][0])) + ' ' + ' '.join('C ' + ' '.join(str(v) for p in s[1:] for v in p) for s in segments)}
lines = {eid: LineString(c['samples']) for eid, c in curves.items()}


def pieces(g):
    if g.is_empty:
        return []
    if g.geom_type == 'LineString':
        return [g] if g.length > .001 else []
    return [part for item in getattr(g, 'geoms', []) for part in pieces(item)]


def points(g):
    return [[round(x, 5), round(y, 5)] for x, y in g.coords]


def intervals(eid, geometry, reason, owner, kind):
    e, line = by_id[eid], lines[eid]
    sections = pieces(line.intersection(geometry.buffer(e['lumenWidthSource']/2 + .65)))
    result = []
    for part in sections:
        a, b = sorted([line.project(Point(part.coords[0])), line.project(Point(part.coords[-1]))])
        if b-a < .01:
            continue
        segment = substring(line, a, b)
        result.append({'edgeId': eid, 'owner': owner, 'kind': kind, 'reason': reason,
            'startSource': list(segment.coords[0]), 'endSource': list(segment.coords[-1]),
            'startDistance': a, 'endDistance': b, 'lengthSource': b-a,
            'startT': a/line.length, 'endT': b/line.length, 'points': points(segment),
            'foreground': owner, 'createsConnection': False})
    return result


occlusions = []
for oid, mask in masks.items():
    for e in edges:
        own = belongs(e, oid) or (oid == 'heart' and
            (e['a'] in {'heart.v','right_heart','left_heart','aortic_root','pulmonary_trunk'} or
             e['b'] in {'heart.v','right_heart','left_heart','aortic_root','pulmonary_trunk'} or
             e['id'] in {'e003','e005','e006','e008','e172','e173','e174','e175'}))
        if own:
            continue
        occlusions.extend(intervals(e['id'], mask, '独立深层血管；由该器官前景遮住此精确段，两端不建立器官连接。', oid, 'organ'))
for p in review['protectedPassages']:
    geo = food if p['id'] == 'food.stomach' else LineString(p['points']).buffer(p['width']/2)
    for e in edges:
        # Brain and limbs are kept exactly as previously accepted; projected passage contacts remain explicit.
        occlusions.extend(intervals(e['id'], geo, '食物／气道／尿路前景优先；血管独立接续，禁止在交叉处开口。', p['id'], 'passage'))
crossings=[]
changed={e['id'] for e in edges if e['id']!=wall['id'] and e['points']!=original[e['id']]['points']}
for index,a in enumerate(edges):
    for b in edges[index+1:]:
        if a['id'] not in changed and b['id'] not in changed:continue
        contact=lines[a['id']].intersection(lines[b['id']])
        if contact.is_empty:continue
        candidates=[contact] if contact.geom_type=='Point' else list(getattr(contact,'geoms',[]))
        for point in candidates:
            if point.geom_type!='Point':continue
            shared=set([a['a'],a['b']])&set([b['a'],b['b']])
            if any(point.distance(Point(a['points'][0] if a['a']==node else a['points'][-1]))<3 for node in shared):continue
            top,bottom=sorted([a,b],key=lambda e:(e['id'] in protected,e['layer'],e['id']),reverse=True)
            owner='crossing:'+top['id']
            geo=lines[top['id']].buffer(top['lumenWidthSource']/2)
            spans=intervals(bottom['id'],geo,'此处是上下层血管交叉，保持各自命名连接，不新增分叉。',owner,'vascular_crossing')
            spans=[h for h in spans if LineString(h['points']).distance(point)<.01]
            occlusions.extend(spans)
            crossings.append({'id':f'X{len(crossings)+1:02}','source':list(point.coords[0]),
                'over':top['id'],'under':bottom['id'],'createsConnection':False})
for i, hidden in enumerate(occlusions):
    hidden['id'] = f'H{i+1:03}'

for e in edges:
    line = lines[e['id']]
    spans = sorted((h['startDistance'], h['endDistance']) for h in occlusions if h['edgeId'] == e['id'])
    merged = []
    for a, b in spans:
        if merged and a <= merged[-1][1] + .01:
            merged[-1][1] = max(b, merged[-1][1])
        else:
            merged.append([a, b])
    e['hiddenIntervals'] = merged
    visible, cursor = [], 0.
    for a, b in merged + [[line.length, line.length]]:
        if a-cursor > .01:
            visible.append(points(substring(line, cursor, a)))
        cursor = max(cursor, b)
    e['visibleSegments'], e['d'] = visible, curves[e['id']]['d']
    e['samples'] = curves[e['id']]['samples']

decisions = []
for r in review['records']:
    if r['category'] not in {'reroute', 'occlude'}:
        continue
    spans = [h for h in occlusions if h['edgeId'] == r['edgeId'] and h['owner'] == r['organ']]
    changed = by_id[r['edgeId']]['points'] != original[r['edgeId']]['points']
    resolution = ('outer_detour' if changed else 'fixed_deep_connector') if r['category'] == 'reroute' else 'foreground_occlusion'
    decisions.append({'id': r['id'], 'edgeId': r['edgeId'], 'organ': r['organ'], 'organName': r['organName'],
        'originalCategory': r['category'], 'resolution': resolution, 'positionChanged': changed,
        'hiddenSegments': [h['id'] for h in spans], 'remainingHiddenLengthSource': sum(h['lengthSource'] for h in spans),
        'reason': route_choices[r['edgeId']]['reason'] if r['category']=='reroute' else
                  '保留原主干及命名连接；只遮住下列精确投影段，0.15 指挥层保留单位位置与选择提示。',
        'resolved': True})

# Re-seat the two authoring exits on the same user curve, clear of the junction and food lumen.
wall_line = lines[wall['id']]
gates = []
for old in nav['gates']:
    if old['edgeId'] != wall['id']:
        continue
    old_p = Point(old['px'], old['py'])
    target = wall_line.project(old_p)
    candidates = []
    for distance in np.arange(6., wall_line.length-6., .2):
        p = wall_line.interpolate(float(distance))
        prev, nxt = wall_line.interpolate(distance-.3), wall_line.interpolate(distance+.3)
        dx, dy = nxt.x-prev.x, nxt.y-prev.y
        length = math.hypot(dx, dy)
        for sign in [-1, 1]:
            normal = [-dy/length*sign, dx/length*sign]
            surface = [p.x+normal[0]*1.15, p.y+normal[1]*1.15]
            tissue = [p.x+normal[0]*4.2, p.y+normal[1]*4.2]
            area = Point(surface).buffer(old['radius'])
            if not masks['stomach'].covers(Point(tissue)) or area.intersects(food) or Point(tissue).distance(food) < 2.5:
                continue
            score = abs(distance-target) + p.distance(old_p)*.1
            candidates.append((score, float(distance), [p.x,p.y], normal, surface, tissue))
    assert candidates, old['id']
    _, distance, p, normal, surface, tissue = min(candidates)
    gates.append({**old, 'px':p[0], 'py':p[1], 'x':surface[0], 'y':surface[1],
        'nx':normal[0], 'ny':normal[1], 'pipeCenterSource':p, 'wallSource':surface,
        'tissueTargetSource':tissue, 'oldPipeCenterSource':[old['px'],old['py']],
        'sourceOffset':math.dist(p,[old['px'],old['py']]), 'distanceAlongSource':distance,
        'distanceToJunctionSource':min(distance,wall_line.length-distance),
        'foodClearanceSource':Point(surface).distance(food),
        'role':'controlled_blood_tissue_exit', 'newNamedBloodJunction':False,
        'status':'ART_REFERENCE_FIXED_MOVEMENT_NOT_INSTALLED'})

result = {'version':'vascular-final-reference/v1','status':'FINAL_ART_REFERENCE_NOT_RUNTIME_MAP',
    'coordinates':review['coordinates'],'reference':'coverage-reference.png','referenceSha256':review['referenceSha256'],
    'sourceHashes':{name:sha(D/name) for name in [review['draft'],'vascular-organ-overlap-data.json','interface-contract.json','central-vessel-connections.json','navigation-review-data.json','organ-layers.json']},
    'edges':edges,'organs':review['organs'],'ports':review['ports'],'protectedPassages':review['protectedPassages'],
    'stomachFoodUnion':review['stomachFoodUnion'],'occlusions':occlusions,'decisions':decisions,'crossings':crossings,
    'routeChoices':list(route_choices.values()),'protectedEdges':sorted(protected),'gates':gates,
    'stomachWall':{'edgeId':wall['id'],'a':wall['a'],'b':wall['b'],'flow':'supply_to_return',
        'userShapePreserved':True,'pointOrderReversed':True,'geometryRefitted':False,
        'gatePositionsChanged':True,'namedInterfaceCoordinatesChanged':False},
    'counts':{'vessels':202,'protectedEdges':len(protected),'rerouteEdges':len(reroute_ids),'rerouteDecisions':18,'occlusionDecisions':30,
        'routedEdges':sum(e['points']!=original[e['id']]['points'] for e in edges if e['id']!=wall['id']),
        'hiddenSegments':len(occlusions),'newRouteCrossings':len(crossings),'stomachExits':len(gates)},
    'limits':['这是供生图与局部美术使用的固定分层参考，尚未替换生产地图或寻路。',
        '遮挡起止由管腔半径加0.65原图像素柔边计算；后续栅格图仍须按这些坐标校正。',
        '固定接口落在其他器官投影内的短段以独立深层通道接续，不因投影相交建立连接。',
        '0.15 显示管腔内单位与选择提示；组织进出只使用指定膜口。',
        '脑与膀胱沿用当前已接受的简化定位轮廓；本轮不添加脑回细血管。',
        '胃壁新出口已定位，实际混合细胞通行和会车须在接入游戏时重新验收。'],
    'productionInstalled':False,'imageGenerated':False,'newMovementCertified':False}
(D/'final-reference-data.json').write_text(json.dumps(result,ensure_ascii=False,separators=(',',':'))+'\n')

def svg_path(items):
    return 'M ' + ' L '.join(' '.join(map(str,p)) for p in items)

palette={'artery':'#b85350','vein':'#3b77a6','capillary':'#726877'}
image=base64.b64encode((ROOT/'assets/image/anatomy-reference/reference.png').read_bytes()).decode()
svg=['<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1536" viewBox="0 0 1024 1536">',
    '<title>定稿血管参考：供回连接、可见段及前景遮挡</title>',
    '<rect width="1024" height="1536" fill="#f6f4ed"/>',
    f'<image width="1024" height="1536" href="data:image/png;base64,{image}" opacity=".42"/>']
for e in edges:
    for segment in e['visibleSegments']:
        svg.append(f'<path data-edge="{e["id"]}" d="{svg_path(segment)}" fill="none" stroke="{palette[e["system"]]}" stroke-width="{max(e["lumenWidthSource"],2.5)}" stroke-linecap="round"/>')
for p in result['ports']:
    if p['kind']!='named_port': continue
    x,y=p['source'];svg.append(f'<circle cx="{x}" cy="{y}" r="2" fill="#f5efdb" stroke="#386b51" stroke-width=".8"/>')
for g in gates:
    p,t=g['wallSource'],g['tissueTargetSource'];svg.append(f'<path d="{svg_path([g["pipeCenterSource"],t])}" fill="none" stroke="#447151" stroke-width=".7"/><circle cx="{p[0]}" cy="{p[1]}" r="1.6" fill="#d9ead2" stroke="#447151" stroke-width=".7"/>')
svg.append('</svg>')
(D/'final-reference-guide.svg').write_text('\n'.join(svg)+'\n')
print(json.dumps(result['counts'],ensure_ascii=False))
for c in route_choices.values():print(c['edgeId'],c['mode'],len(c['finalPoints']),c['finalPoints'])
print('stomach gates:',[(g['id'],g['pipeCenterSource'],g['distanceToJunctionSource'],g['foodClearanceSource']) for g in gates])
