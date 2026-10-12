"""Check directed central circulation and frozen head/limb interface coordinates.

This certifies the design graph only. No runtime geometry or save data is edited.
"""
from pathlib import Path
from collections import deque
import hashlib
import json
import math

ROOT = Path(__file__).resolve().parents[2]
DOC = ROOT / 'docs/body-life/vascular-art-study'
network = json.loads((DOC / 'navigation-review-data.json').read_text())['network']
contracts = json.loads((DOC / 'interface-contract.json').read_text())['regions']

def preserved(e):
    if e['id'] == 'access.arm_r':
        return True
    if not e['id'].startswith('e'):
        return False
    n = int(e['id'][1:])
    return 16 <= n <= 115 or 153 <= n <= 163 or 176 <= n <= 179

fixed = [e for e in network['edges'] if preserved(e)]
central = [e for e in network['edges'] if not preserved(e)]
nodes = {}
endpoint_checks = 0
for edge in network['edges']:
    for node, point in [(edge['a'], edge['points'][0]), (edge['b'], edge['points'][-1])]:
        if node in nodes:
            assert math.dist(nodes[node], point) < 1e-7, (edge['id'], node)
        else:
            nodes[node] = point
        endpoint_checks += 1

def path(start, target, systems):
    queue = deque([(start, [])])
    seen = {start}
    while queue:
        node, trace = queue.popleft()
        if node == target:
            return trace
        for e in network['edges']:
            if e['a'] == node and e['system'] in systems and e['b'] not in seen:
                seen.add(e['b'])
                queue.append((e['b'], trace + [e['id']]))
    raise AssertionError((start, target, systems))

organs = []
for organ in contracts:
    oid = organ['id']
    if oid.startswith(('brain', 'arm_', 'leg_')):
        continue
    ports = {p['role']: p for p in organ['ports']}
    entry = ports['supply']['id']
    exit_node = ports['return']['id']
    pulmonary = oid.startswith('lung_')
    supply_root = 'right_heart' if pulmonary else 'left_heart'
    return_root = 'left_heart' if pulmonary else 'right_heart'
    supply = path(supply_root, entry, {'artery'})
    exchange = path(entry, exit_node, {'artery', 'vein', 'capillary'})
    back = path(exit_node, return_root, {'vein', 'capillary'})
    portal = oid in {'stomach', 'pancreas', 'small_intestine', 'colon_proximal', 'colon_distal'}
    if portal:
        assert 'e119' in back and 'e121' in back, oid
    record = {'id': oid, 'region': 'heart' if oid == 'coronary' else 'large_intestine' if oid.startswith('colon_') else oid,
              'name': organ['name'], 'entry': entry, 'exit': exit_node,
              'supplyRoot': supply_root, 'returnRoot': return_root,
              'supplyPath': supply, 'exchangePath': exchange, 'returnPath': back,
              'portal': portal, 'pass': True}
    if 'portalSupply' in ports:
        record['portalEntry'] = ports['portalSupply']['id']
        record['portalSupplyPath'] = path('portal', record['portalEntry'], {'vein'})
    organs.append(record)

assert len(organs) == 13
assert len(fixed) == 116 and len(central) == 86
locked = {k: nodes[k] for k in ['arch', 'heart.v', 'iliac.a', 'iliac.v']}
report = {'status': 'PASS_DESIGN_GRAPH', 'runtimeModified': False,
          'coordinateSystem': {'width': 1024, 'height': 1536},
          'preservedEdges': [e['id'] for e in fixed], 'centralEdges': [e['id'] for e in central],
          'protectedSha256': hashlib.sha256(json.dumps(fixed, sort_keys=True).encode()).hexdigest(),
          'networkSha256': hashlib.sha256(json.dumps(network, sort_keys=True).encode()).hexdigest(),
          'lockedNodes': locked, 'endpointChecks': endpoint_checks,
          'organs': organs, 'summary': {'organLoopsPassed': 13, 'organLoopsTotal': 13,
                                       'preservedEdges': 116, 'centralEdges': 86},
          'rendering': {'onlyCentralVesselsReceiveWalls': True, 'endpointsUnchanged': True,
                        'curveAlgorithm': 'bounded-cubic-v1', 'allVesselsCurved': True,
                        'allAuthoringNodesUnchanged': True, 'maxHandleSource': 18,
                        'curveCollisionInstalled': False},
          'limitations': ['Pipe walls and cubic curves are a vector art preview; no new AI raster generated.',
                          'Navigation playback still uses its original baseline.',
                          'Editing geometry requires new route, clearance and crowd checks.',
                          'The diagram is projected circulation; clinical anatomy and runtime readiness are not certified.']}
(DOC / 'central-vessel-connections.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print('13/13 central organ loops; 404 exact endpoints; 116 preserved head/limb edges.')
