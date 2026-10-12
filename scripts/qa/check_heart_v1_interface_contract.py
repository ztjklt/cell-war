"""Independent registration/geometry checks for the isolated heart revision.

This proves frozen external registration and geometric connectivity, not
anatomical appearance or native rendering. Missing generated art or native
evidence is reported as UNDETERMINED rather than inferred from static code.
"""
from __future__ import annotations

import argparse
from collections import defaultdict, deque
import hashlib
import json
import math
from pathlib import Path
import re
import sys

sys.path.insert(0, '/tmp/reference-map-tools')
from PIL import Image
from shapely.geometry import LineString, Point, Polygon, box
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CONTRACT = ROOT / 'docs/heart-v1/interface-contract.json'
DEFAULT_GEOMETRY = ROOT / 'docs/heart-v1/geometry/heart-four-chamber.json'
DEFAULT_DELIVERY = ROOT / 'docs/heart-v1/delivery.json'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def canonical_sha(value):
    data = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False)
    return hashlib.sha256(data.encode()).hexdigest()


def geometry(rings):
    return unary_union([Polygon(p['outer'], p.get('holes', [])) for p in rings])


def reachable(graph, start, end):
    queue, seen = deque([start]), {start}
    while queue:
        current = queue.popleft()
        if current == end:
            return True
        for node in graph[current]:
            if node not in seen:
                seen.add(node)
                queue.append(node)
    return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--contract', type=Path, default=DEFAULT_CONTRACT)
    parser.add_argument('--geometry', type=Path, default=DEFAULT_GEOMETRY)
    parser.add_argument('--delivery', type=Path, default=DEFAULT_DELIVERY)
    parser.add_argument('--report', type=Path, default=ROOT / 'docs/heart-v1/qa/interface-report.json')
    parser.add_argument('--require-delivery', action='store_true')
    args = parser.parse_args()
    records = []

    def check(name, passed, detail=None):
        records.append(dict(name=name, status='PASS' if passed else 'FAIL', detail=detail))

    def pending(name, detail):
        records.append(dict(name=name, status='UNDETERMINED', detail=detail))

    contract = json.loads(args.contract.read_text())
    baseline_path = ROOT / contract['baseline']['path']
    baseline = json.loads(baseline_path.read_text())
    check('baseline snapshot integrity', sha(baseline_path) == contract['baseline']['sha256'])
    captured_manifest_path = ROOT / contract['baseline']['manifestPath']
    check('captured manifest integrity', sha(captured_manifest_path) == contract['baseline']['manifestSha256'])
    reference_path = ROOT / contract['baseline']['referenceDataPath']
    reference = json.loads(reference_path.read_text())
    frozen = {edge['id']: edge for edge in reference['edges']}
    check('202 unique global reference routes', len(frozen) == 202)
    frozen_hashes = {row['id']: row['sha256'] for row in baseline['globalEdges']}
    changed = [eid for eid, digest in frozen_hashes.items() if eid not in frozen or canonical_sha(frozen[eid]) != digest]
    check('global frozen route source unchanged', not changed, dict(changedEdges=changed))
    roi = box(*contract['coordinates']['sourceBox'])
    check('fixed source/world coordinate contract', contract['coordinates']['sourceBox'] == [468, 326, 568, 467]
          and contract['coordinates']['worldFromSource'] == dict(scale=[2, 2], offset=[0, 512]))
    registered_ports = contract['externalInterfaces']['allCrossBoxPorts']
    check('registered port inventory complete', len(registered_ports) == contract['externalInterfaces']['crossBoxPortCount'])
    for port in registered_ports:
        edge = frozen[port['edgeId']]
        center = Point(port['source'])
        section = LineString(port['crossSectionSource'])
        tangent = port['tangentAB']
        dx, dy = section.coords[-1][0] - section.coords[0][0], section.coords[-1][1] - section.coords[0][1]
        check(port['id'] + ' pinned exact route section',
              LineString(edge['samples']).distance(center) < 1e-7
              and roi.boundary.distance(center) < 1e-7
              and abs(section.length - edge['lumenWidthSource']) < 1e-7
              and abs(dx * tangent[0] + dy * tangent[1]) < 1e-7
              and port['pinDisplacementSource'] == 0)
    check('four anatomical systems independent from four screen strokes',
          len(contract['physiologicalSystems']) == 4
          and contract['visualFourCoarseTrunks']['physiologicalSystemsAreNotFourScreenStrokes'] is True)
    for record in contract['imageGenerationContext'].values():
        if isinstance(record, dict) and record.get('path'):
            path = ROOT / record['path']
            check('context ' + path.name + ' bound to baseline', path.exists() and sha(path) == record['sha256']
                  and list(Image.open(path).size) == record['pixelSize'])

    if args.geometry.exists():
        heart = json.loads(args.geometry.read_text())
        expected_chambers = {'right_atrium', 'right_ventricle', 'left_atrium', 'left_ventricle'}
        expected_valves = {'tricuspid', 'pulmonary', 'mitral', 'aortic'}
        chambers = {row['id']: row for row in heart['chambers']}
        valves = {row['id']: row for row in heart['valves']}
        check('four physical chamber domains', set(chambers) == expected_chambers)
        check('four physical valve domains', set(valves) == expected_valves)
        check('candidate sourceBox matches fixed frame', heart['sourceBox'] == contract['coordinates']['sourceBox'])
        outer = geometry(heart['outerRings'])
        domains = {key: geometry(row['rings']) for key, row in chambers.items()}
        valve_domains = {key: geometry(row['rings']) for key, row in valves.items()}
        raw = {int(key): geometry(rings) for key, rings in heart['rawBloodDomains'].items()}
        for key, chamber in chambers.items():
            domain = domains[key]
            center = Point(chamber['centerSource'])
            nodes = [Point(heart['nodePoints'][chamber[node]]) for node in ('a', 'b')]
            check(key + ' valid nonempty domain', domain.is_valid and domain.area > 100)
            check(key + ' playable center has largest-cell clearance', domain.buffer(-.53125).covers(center))
            check(key + ' domain within organ silhouette', domain.difference(outer).area < 1e-6)
            check(key + ' connection anchors in physical domain', all(domain.covers(point) for point in nodes))
            check(key + ' authoritative raw blood domain matches chamber',
                  raw[int(chamber['laneIndex'])].symmetric_difference(domain).area < 1e-7)
        check('atria visibly above ventricles',
              chambers['right_atrium']['centerSource'][1] < chambers['right_ventricle']['centerSource'][1]
              and chambers['left_atrium']['centerSource'][1] < chambers['left_ventricle']['centerSource'][1])
        for a, b in [('right_atrium', 'left_atrium'), ('right_ventricle', 'left_ventricle')]:
            check(a + '/' + b + ' intact separating septum', domains[a].distance(domains[b]) > 1.0625)
        connections = {
            'tricuspid': ('right_atrium', 'right_ventricle'),
            'mitral': ('left_atrium', 'left_ventricle'),
        }
        for key, (a, b) in connections.items():
            combined = unary_union([domains[a], domains[b], valve_domains[key]]).buffer(-.53125)
            points = [Point(chambers[c]['centerSource']) for c in (a, b)]
            pieces = [combined] if combined.geom_type == 'Polygon' else list(combined.geoms)
            check(key + ' connects chambers with largest-cell clearance',
                  any(piece.covers(points[0]) and piece.covers(points[1]) for piece in pieces))
        for key, valve in valves.items():
            domain = valve_domains[key]
            line = LineString(valve['points'])
            check(key + ' passable static valve throat', domain.is_valid
                  and domain.covers(line.buffer(.53125, cap_style=1)))
            check(key + ' registered raw domain', raw[int(valve['laneIndex'])].symmetric_difference(domain).area < 1e-7)
        graph = defaultdict(set)
        all_local = list(heart['edgeUpdates'].values()) + heart['edgeAdditions']
        for edge in all_local:
            graph[edge['a']].add(edge['b'])
            graph[edge['b']].add(edge['a'])
        check('local right-heart circulation connected', reachable(graph, 'heart.v', 'pulmonary_trunk'))
        check('local left-heart circulation connected', reachable(graph, 'lung_r.exit', 'aortic_root')
              and reachable(graph, 'lung_l.exit', 'aortic_root'))
        check('no direct local right-left blood shortcut', not reachable(graph, 'heart.v', 'aortic_root'))
        check('eight new domains with unique reserved lane IDs',
              {row['laneIndex'] for row in heart['edgeAdditions']} == set(range(203, 211)))
        for index, update in heart['edgeUpdates'].items():
            original = frozen[f'e{int(index):03d}']
            check('local edge ' + index + ' stays within authorized heart sourceBox',
                  roi.covers(LineString(update['points']))
                  and abs(update['widthSource'] - original['lumenWidthSource']) < 1e-7)
        anchor_sources = {
            'heart.v': [483, 379], 'pulmonary_trunk': [510, 355],
            'lung_r.exit': [471.6707317073171, 410.9634146341464],
            'lung_l.exit': [545, 414], 'aortic_root': [533, 375],
        }
        for section in heart['externalSections']:
            check(section['id'] + ' external named anchor retained',
                  math.dist(section['source'], anchor_sources[section['nodeId']]) < 1e-7)
        check('physics remains static and valves allow tactical transit',
              heart['navigationPolicy']['dynamicWalls'] is False
              and heart['navigationPolicy']['leftRightShortcut'] is False)
    else:
        pending('new chamber geometry', 'No candidate geometry saved yet.')

    if args.delivery.exists():
        delivery = json.loads(args.delivery.read_text())
        check('candidate delivery exists and uses same source frame',
              delivery.get('sourceBox', delivery.get('coordinates', {}).get('sourceBox')) == contract['coordinates']['sourceBox'])
        # Unknown fields are preserved for root's runtime integration report;
        # existence of a delivery manifest does not prove its renderer masks.
        pending('native no-legacy-layer-mixing and visual seam evidence',
                'Requires current production/native output, not only delivery metadata.')
    else:
        if args.require_delivery:
            check('candidate delivery available', False, str(args.delivery))
        else:
            pending('candidate GPT art and runtime layer delivery', 'No delivery.json saved yet.')
    pending('anatomical art appearance and heartbeat-native evidence',
            'Independently inspect generated composite and native heartbeat frames before visual acceptance.')
    failures = [row for row in records if row['status'] == 'FAIL']
    report = dict(schema='heart-v1-independent-interface-qa/v1',
                  status='FAIL' if failures else 'PASS_REGISTERED_GEOMETRY_ONLY',
                  contractSha256=sha(args.contract),
                  geometrySha256=sha(args.geometry) if args.geometry.exists() else None,
                  deliverySha256=sha(args.delivery) if args.delivery.exists() else None,
                  nativeEvidence=False, checks=records,
                  counts={status: sum(row['status'] == status for row in records) for status in ['PASS', 'FAIL', 'UNDETERMINED']})
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False) + '\n')
    print(json.dumps(dict(status=report['status'], counts=report['counts'], failures=failures,
                         report=str(args.report.relative_to(ROOT))), ensure_ascii=False))
    return 1 if failures else 0


if __name__ == '__main__':
    raise SystemExit(main())
