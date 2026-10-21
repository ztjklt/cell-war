"""Offline authoring of infection preview zones from certified Godot geometry.

Run with .tmp/godot-tools/venv/bin/python. No runtime Python dependency.
Distances are stored in map/world units, not display pixels.
"""
import base64
import hashlib
import json
from pathlib import Path

import numpy as np
from scipy.sparse import csr_matrix
from scipy.sparse.csgraph import dijkstra
from scipy.spatial import cKDTree
from shapely.geometry import Point, Polygon, box
from shapely.ops import triangulate, unary_union
from shapely import contains_xy

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / 'godot/data'
OUT = DATA / 'infection_zones.json'
NAMES = dict(brain='大脑', heart='心脏', lung_r='右肺', lung_l='左肺', liver='肝脏',
             stomach='胃', pancreas='胰腺', kidney_r='右肾', kidney_l='左肾',
             small_intestine='小肠', large_intestine='大肠', bladder='膀胱')
DIRS = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]
PATCH_SIDE = 14.0
GATE_GAP = 24.0
MIN_ROUTE = 36.0


def read(name):
    return json.loads((DATA / f'{name}.json').read_text())


def world(p):
    return [round(float(p[0]) * 2, 5), round(float(p[1]) * 2 + 512, 5)]


def rings(shape):
    return [{'outer': [world(p) for p in poly.exterior.coords],
             'holes': [[world(p) for p in ring.coords] for ring in poly.interiors]}
            for poly in polygons(shape)]


def polygons(shape):
    return [shape] if shape.geom_type == 'Polygon' else [p for p in shape.geoms if p.geom_type == 'Polygon']


def graph(grid,land):
    w, h = grid['width'], grid['height']
    valid = np.frombuffer(base64.b64decode(grid['validBase64']), dtype=np.uint8)
    adj = np.frombuffer(base64.b64decode(grid['adjacencyBase64']), dtype=np.uint8)
    indices = np.flatnonzero(valid)
    coordinates = np.column_stack((indices % w, indices // w)) * grid['step'] + grid['origin']
    # Native Vector2 is float32. Keep exact-boundary lattice vertices out of
    # this new route subset; preserve every remaining certified adjacency.
    indices = indices[contains_xy(land.buffer(-.05),coordinates[:,0],coordinates[:,1])]
    mapping = np.full(w * h, -1, np.int32)
    mapping[indices] = np.arange(len(indices))
    coords = np.column_stack((indices % w, indices // w)) * grid['step'] + grid['origin']
    rows, cols, weights = [], [], []
    for bit, (dx, dy) in enumerate(DIRS):
        start = indices[(adj[indices] & (1 << bit)) != 0]
        end = start + dy * w + dx
        keep = mapping[end] >= 0
        start, end = start[keep], end[keep]
        rows.append(mapping[start]); cols.append(mapping[end])
        weights.append(np.full(len(start), grid['step'] * np.hypot(dx, dy)))
    matrix = csr_matrix((np.concatenate(weights), (np.concatenate(rows), np.concatenate(cols))),
                        shape=(len(indices), len(indices)))
    return coords, matrix


def main():
    organs, ports = read('organs'), read('checkpoints')['ports']
    all_gate_points = [Point(p[k]) for p in ports for k in ['a', 'b']]
    forbidden = unary_union([p.buffer(GATE_GAP / 2, quad_segs=24) for p in all_gate_points])
    hb = organs['heart']['sourceBox']
    heart_box = box(*hb)
    obstacles = []
    for mode in ['fullbody', 'systemic']:
        entities = read('starts/' + mode)['entities']
        for e in (entities.values() if isinstance(entities, dict) else entities):
            if e.get('checkpointId'): continue
            obstacles.append(Point(e['x'] / 2, (e['y'] - 512) / 2).buffer(2))
    occupied = unary_union(obstacles)
    blood_domains = read('blood_scout')['domains']
    # Vessels retain their own higher render plane. Ground patches must also
    # have a visible footprint, not merely valid tissue hidden behind a pipe.
    visible_blood = unary_union([Polygon(r['outer'],r.get('holes') or []).buffer(0)
                                for domain in blood_domains.values() for r in domain]).buffer(.8)
    zones = []
    deferred = []
    for oid in organs:
        path = DATA / f'navigation/{oid}_siege.json'
        g = json.loads(path.read_text())
        land = unary_union([Polygon(r['outer'], r.get('holes') or []) for r in g['safeRings']]).buffer(0)
        eligible = land.buffer(-.4).difference(forbidden).difference(occupied)
        if oid != 'heart': eligible = eligible.difference(heart_box)
        coords, matrix = graph(g,land)
        tree = cKDTree(coords)
        component_bytes = np.frombuffer(base64.b64decode(g['componentBase64']),dtype=np.uint8)
        cell_x = np.rint((coords[:,0]-g['origin'][0])/g['step']).astype(int)
        cell_y = np.rint((coords[:,1]-g['origin'][1])/g['step']).astype(int)
        components = component_bytes[cell_y*g['width']+cell_x]
        own_ports = [p for p in ports if p['organId'] == oid]
        route_maps = []
        for p in own_ports:
            nearby = tree.query_ball_point(p['b'], r=3.0)
            attachments = []
            for idx in nearby:
                distance = np.linalg.norm(coords[idx] - p['b'])
                from shapely.geometry import LineString
                if land.covers(LineString([p['b'], coords[idx]])):
                    attachments.append((int(idx), float(distance)))
            if attachments:
                # Match WarGrid's exact attachment to the destination component,
                # including authored narrow corridors omitted by the lattice.
                # Each source's connector cost is added before choosing its map.
                maps = []
                for component in sorted(set(int(components[i]) for i,_ in attachments)):
                    group = [(i,d) for i,d in attachments if components[i] == component]
                    idx, distance = min(group, key=lambda row:row[1])
                    distances, predecessors = dijkstra(matrix.T.tocsr(), directed=True, indices=idx, return_predecessors=True)
                    maps.append((distances+distance,predecessors,idx))
                route_maps.extend((p,*m) for m in maps)
        candidates = []
        # Large polygon components form potential zones. Only keep components
        # with multiple certified small footprints, never tiny leftover slivers.
        for poly in sorted(polygons(eligible), key=lambda p: p.area, reverse=True):
            if poly.area < 100: continue
            minx, miny, maxx, maxy = poly.bounds
            chosen = []
            # Narrow tissue corridors receive smaller patches, with unchanged
            # gate exclusion and advance-distance requirements.
            for patch_side in [PATCH_SIDE,10.0,8.0,6.0]:
                candidates_here = []
                step = min(4,patch_side*.3)
                for y in np.arange(miny + patch_side / 4, maxy, step):
                    for x in np.arange(minx + patch_side / 4, maxx, step):
                        half = patch_side / 4
                        footprint = box(x-half, y-half, x+half, y+half)
                        if not poly.covers(footprint): continue
                        if footprint.intersects(visible_blood): continue
                        gap = min(footprint.distance(p) * 2 for p in all_gate_points)
                        if gap < GATE_GAP: continue
                        attachment_distance, idx = tree.query([x, y])
                        from shapely.geometry import LineString
                        if not land.covers(LineString([[x, y], coords[idx]])): continue
                        viable = [(float(d[idx] + attachment_distance) * 2, p, pred, start)
                                  for p, d, pred, start in route_maps if np.isfinite(d[idx])]
                        if not viable: continue
                        route_length, port, pred, start = min(viable, key=lambda row: row[0])
                        if route_length < MIN_ROUTE: continue
                        clearance = Point(x,y).distance(poly.boundary)
                        path_points = [[x,y]]
                        at = int(idx)
                        while True:
                            path_points.append(coords[at].tolist())
                            if at == start: break
                            at = int(pred[at]); assert at >= 0
                        path_points.append(port['b'])
                        line = LineString(path_points).simplify(.02)
                        if not land.covers(line): line = LineString(path_points)
                        candidates_here.append((clearance, x, y, gap, route_length, port['id'],list(line.coords)))
                if len(candidates_here) < 2: continue
                candidates_here.sort(key=lambda c:c[0],reverse=True)
                chosen = []
                for candidate in candidates_here:
                    if all(np.hypot(candidate[1]-c[1], candidate[2]-c[2]) >= patch_side*.6 for c in chosen):
                        chosen.append(candidate)
                    if len(chosen) == 8: break
                if len(chosen) >= 2: break
            if len(chosen) < 2: continue
            candidates.extend(chosen)
            # Keep the full large playable component, not a tiny rectangle
            # wrapped around each currently selected small patch.
            shape = poly.simplify(.04, preserve_topology=True)
            mesh = []
            for triangle in triangulate(shape):
                if shape.covers(triangle): mesh.append([world(p) for p in list(triangle.exterior.coords)[:3]])
            placements = [{'id': f'{oid}.patch.{i+1}', 'center': world((c[1],c[2])), 'side': patch_side,
                           'gateGap': round(c[3],3), 'routeLength': round(c[4],3), 'targetGate': c[5],
                           'route': [world(p) for p in c[6]]}
                          for i,c in enumerate(chosen)]
            zones.append({'id': oid+'.potential.1', 'organ': oid, 'name': NAMES[oid],
                          'area': round(shape.area*4,2), 'rings': rings(shape), 'triangles': mesh,
                          'placements': placements, 'geometrySha256': hashlib.sha256(path.read_bytes()).hexdigest()})
            break
        print(oid, 'placements', len(candidates), flush=True)
        if not candidates:
            deferred.append({'organ':oid,'name':NAMES[oid],
                             'reason':'No multiple full-size footprints with both gate clearance and certified ground route; requires separate chamber/space authoring review.'})
    assert any(z['organ'] == 'lung_r' for z in zones)
    result = {'version': 1, 'purpose': 'layout-and-art-preview', 'units': 'map-world',
              'gateGap': GATE_GAP, 'minimumRoute': MIN_ROUTE, 'patchSide': PATCH_SIDE,
              'checkpointSha256':hashlib.sha256((DATA/'checkpoints.json').read_bytes()).hexdigest(),
              'bloodGeometrySha256':hashlib.sha256((DATA/'blood_scout.json').read_bytes()).hexdigest(),
              'visibleBloodBufferSource':.8,
              'texture': 'image/infection-ground-20261020/v2-flat/ground-tile.png',
              'edgeTexture':'image/infection-ground-20261020/v2-flat/edge-brush-detail-v21.png',
              'surfaceStyle':'flat-modular','pavingWorldSize':3.5,'pavingOpacity':.42,
              'pavingDetailMidpoint':.36543,'pavingDetailStrength':.75,
              'zones': zones, 'deferredOrgans':deferred,
              'limbs': 'pending-authored-ground-and-gate-contracts'}
    OUT.write_text(json.dumps(result, ensure_ascii=False, separators=(',', ':'), allow_nan=False)+'\n')
    print('WROTE', OUT, 'zones', len(zones), 'placements', sum(len(z['placements']) for z in zones))


if __name__ == '__main__': main()
