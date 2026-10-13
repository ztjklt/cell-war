"""Whole-body .15 acceptance, using production Lua commands and geometry.

Owns only fullbody-015/qa. Never changes routes, artwork, collision, or save data.
The default motion matrix covers every registered organ gate/room, frozen blood
port, all 202 blood edges, and every directed organ pair for scout and siege.
Native filtering, continuous native movement and P95 remain separate evidence.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import io
import json
import math
import os
import re
import shutil
import subprocess
import sys
import time

for dependency in ['/tmp/reference-map-tools', '/tmp/passage-tools314']:
    if Path(dependency).is_dir():
        sys.path.insert(0, dependency)
import numpy as np
from PIL import Image
from lupa.lua54 import LuaRuntime
import check_gastric_battlefield as gastric
import check_organ_battlefield_atlas as atlas

ROOT = Path(__file__).resolve().parents[2]
DOC = ROOT / 'docs/body-life/vascular-art-study/fullbody-015'
OUT = DOC / 'qa'
ORGANS = list(atlas.ORGANS)
KINDS = ['scout', 'siege']
GRAPH = atlas.GRAPH
FROZEN_GRAPH_SHA = atlas.FROZEN_GRAPH
MODULES = ['FullBodyBattlefield', 'FullBodyMapArt', 'FullBodyMapArtData',
           'OrganBattlefield', 'OrganBattlefieldCore', 'OrganBattlefieldData',
           'GastricBattlefield', 'GastricBattlefieldData', 'OrganTrial',
           'OrganTraffic', 'GastricTraffic', 'Commands', 'Path', 'Simulation',
           'CellCollision', 'Motion', 'Save', 'World', 'Vessels', 'Data', 'Util']
FROZEN_FILES = ['assets/image/anatomy-reference/reference.png',
                'assets/image/anatomy-reference/vascular-study/stomach-playable/battlefield.png',
                'docs/body-life/vascular-art-study/final-reference-data.json',
                'scripts/war/FinalVascularStudyData.lua',
                'scripts/war/GastricBattlefieldData.lua',
                'scripts/war/OrganBattlefieldData.lua']


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2,
                               allow_nan=False) + '\n')


def read(path):
    return json.loads(path.read_text())


def hashes(names=MODULES):
    paths = [ROOT / 'scripts/war' / (n + '.lua') for n in names]
    return {str(p.relative_to(ROOT)): sha(p) for p in paths if p.is_file()}


def navigation_hashes():
    # Artwork readiness changes during compilation must not erase a valid
    # movement observation. Rendering and resource checks bind those separately.
    return hashes([n for n in MODULES if n not in ['FullBodyMapArt', 'FullBodyMapArtData']])


def baseline():
    path = OUT / 'baseline.json'
    if path.exists():
        return read(path)
    os.chdir(ROOT)
    lua = gastric.runtime()
    capture = lua.execute(r'''
      local Sim,Save,U=require('war.Simulation'),require('war.Save'),require('war.Util')
      return function(version,mode)
        local s=Sim.new(73,mode,version);local snap=Save.snapshot(s)
        return snap
      end
    ''')
    fixtures = []
    for version in [1, 2, 3, 4]:
        snapshot = gastric.convert(capture(version, 'sandbox'))
        p = OUT / 'legacy-fixtures' / f'sandbox-anatomy-{version}.json'
        write(p, snapshot)
        fixtures.append({'mode': 'sandbox', 'anatomyVersion': version,
                         'file': str(p.relative_to(OUT)), 'sha256': sha(p)})
    # Campaign is kept in its own event runtime. Do not infer whole-body access
    # from a fullbody flag injected into a campaign snapshot.
    snapshot = gastric.convert(capture(4, 'campaign'))
    p = OUT / 'legacy-fixtures/campaign-anatomy-4.json'; write(p, snapshot)
    fixtures.append({'mode': 'campaign', 'anatomyVersion': 4,
                     'file': str(p.relative_to(OUT)), 'sha256': sha(p)})
    historical = []
    for p in [atlas.BASE / 'organ-atlas/qa/production-report.json',
              atlas.BASE / 'organ-atlas/qa/production-filtered-report.json',
              atlas.BASE / 'stomach-playable/qa/summary.json']:
        if p.is_file():
            d = read(p)
            historical.append({'file': str(p.relative_to(ROOT)), 'sha256': sha(p),
                               'status': d.get('status'), 'passed': d.get('passed'),
                               'total': d.get('total'), 'scope': 'Historical evidence; current hashes require rerun.'})
    result = {'schema': 'fullbody-015-baseline/v1', 'createdAt': now(),
              'nativeEvidence': False, 'frozenHashes': {p: sha(ROOT / p) for p in FROZEN_FILES},
              'runtimeHashes': hashes(), 'legacyFixtures': fixtures,
              'historicalEvidence': historical}
    assert result['frozenHashes'][str(GRAPH.relative_to(ROOT))] == FROZEN_GRAPH_SHA
    write(path, result); return result


def now():
    return datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat()


def freeze_check():
    b = baseline()
    rows = [{'path': p, 'before': expected, 'after': sha(ROOT / p),
             'unchanged': expected == sha(ROOT / p)} for p, expected in b['frozenHashes'].items()]
    return {'rows': rows, 'unchanged': all(r['unchanged'] for r in rows)}


def point_actor(kind, start, target, owner, lane=0, target_lane=0, target_owner=None):
    return {'kind': kind, 'x': start[0] * 2, 'y': start[1] * 2 + 512,
            'tx': target[0] * 2, 'ty': target[1] * 2 + 512, 'lane': lane,
            'targetLane': target_lane, 'targetOrgan': target_owner or owner}


def runtime_layout():
    lua = gastric.runtime()
    data = gastric.convert(lua.execute(r'''
      local O=require('war.OrganBattlefield');local out={}
      for _,id in ipairs(...)do out[id]=O.organ(id)end
      return out
    ''', gastric.lua_table(lua, ORGANS)))
    return data


def rally(layout, owner, kind, gate_id=None):
    data = layout[owner]
    if owner != 'stomach':
        rooms = data['profileRooms'][kind]
        if gate_id:
            rooms = [r for r in rooms if gate_id in r['reachableGateIds']]
        return rooms[0]['rallySource'] if rooms else None
    rooms = data['rooms']
    if gate_id:
        rooms = [r for r in rooms if gate_id in r['navigation'][kind]['reachableGateIds']]
    return rooms[0]['centerSource'] if rooms else None


def fixture_matrix():
    from shapely.geometry import LineString, Point
    _, records = atlas.contract_records()
    layout = runtime_layout(); graph = read(GRAPH)
    cases = []
    # Include all existing independently specified organ rooms and reserved
    # food/air/urine negatives, not only the last filtered baseline.
    for c in atlas.scenario_configs(records):
        if c['id'].startswith(('cross-organ/', 'blood-meeting/')):
            continue
        c['family'] = 'inherited-organ'; cases.append(c)
    # Every actual runtime gate is checked in both directions for both radii.
    # This includes the five accepted stomach exchanges and all large-colon gates.
    for owner in ORGANS:
        data = layout[owner]
        for kind in KINDS:
            for gate in data['gateContracts'][kind]:
                center = rally(layout, owner, kind, gate['id'])
                if center is None:
                    # The accepted stomach outer exchange leads to its named
                    # outer vestibule, not one of the six internal rooms.
                    # Its authored tissue anchor is a real, independently
                    # covered tissue point; no new room or coordinate is made.
                    if owner == 'stomach' and gate['id'] == 'study.stomach.wall_service.outer':
                        center = gate['tissueAnchorSource']
                if center is None:
                    cases.append({'id': f'gate/{owner}/{kind}/{gate["id"]}/unavailable',
                                  'family': 'gate', 'owner': owner, 'gateId': gate['id'],
                                  'fixtureFailure': 'NO_DECLARED_ROOM_REACHES_GATE'}); continue
                pipe = gate['pipeAnchorSource']; lane = gate['laneIndex']
                for direction in ['exit', 'enter']:
                    actor = point_actor(kind, center if direction == 'exit' else pipe,
                                        pipe if direction == 'exit' else center,
                                        owner, 0 if direction == 'exit' else lane,
                                        lane if direction == 'exit' else 0)
                    if direction == 'enter': actor['setupSource'] = center
                    cases.append({'id': f'gate/{owner}/{kind}/{gate["id"]}/{direction}',
                                  'family': 'gate', 'owner': owner, 'gateId': gate['id'],
                                  'direction': direction, 'actors': [actor], 'maxTime': 600})
                # Scout and siege use real opposing commands. Initial blood
                # state is reached through the same production entry order.
                if kind == 'siege':
                    a = point_actor('scout', center, pipe, owner, target_lane=lane)
                    b = point_actor('siege', pipe, center, owner, lane=lane)
                    b['setupSource'] = [center[0] + 2, center[1]]
                    cases.append({'id': f'meeting/{owner}/{gate["id"]}/scout-siege',
                                  'family': 'meeting', 'owner': owner, 'gateId': gate['id'],
                                  'actors': [a, b], 'maxTime': 900})
            center = rally(layout, owner, kind)
            actors = [point_actor(kind, [center[0] + x, center[1] + y], center, owner)
                      for x, y in [(-2, -2), (2, -2), (-2, 2), (2, 2)]]
            cases.append({'id': f'formation/{owner}/{kind}/four-units', 'family': 'formation',
                          'owner': owner, 'actors': actors,
                          'group': {'x': center[0] * 2, 'y': center[1] * 2 + 512,
                                    'lane': 0, 'organId': owner}, 'maxTime': 600})
    # All directed pairs, not a single convenient adjacent-organ example.
    for left in ORGANS:
        for right in ORGANS:
            if left == right: continue
            for kind in KINDS:
                a, b = rally(layout, left, kind), rally(layout, right, kind)
                cases.append({'id': f'cross/{left}/{right}/{kind}', 'family': 'cross',
                              'fromOrgan': left, 'toOrgan': right,
                              'actors': [point_actor(kind, a, b, left, target_owner=right)],
                              'maxTime': 1800})
    # A frozen supply/return port is a blood point, not a new tissue opening.
    # Keep exact coordinates; failures are retained rather than snapping ports.
    for port in graph['ports']:
        if port['role'] not in ['supply', 'return', 'portalSupply']: continue
        owner = port['organ']
        if owner not in ORGANS: continue
        system = 'artery' if port['role'] == 'supply' else 'vein'
        point = port['source']
        candidate = min([(LineString(e['samples']).distance(Point(point)), i + 1)
                         for i, e in enumerate(graph['edges']) if e['system'] == system])
        lane = candidate[1]
        for kind in KINDS:
            center = rally(layout, owner, kind)
            cases.append({'id': f'port/{port["id"]}/{kind}', 'family': 'port',
                          'owner': owner, 'portId': port['id'], 'role': port['role'],
                          'exactFrozenSource': point, 'laneIndex': lane,
                          'actors': [point_actor(kind, center, point, owner, target_lane=lane)],
                          'maxTime': 1800})
    # Every graph edge, including head, arms, hands, legs and feet. Explicit
    # source lanes are prepared through real movement if spawn defaults to
    # an overlapping tissue plane; never assign e.vesselLane in this harness.
    lua = gastric.runtime()
    probe = lua.execute(r'''
      local O,T,W=require('war.OrganBattlefield'),require('war.OrganTrial'),require('war.World')
      local s=T.new(73,...);s.entities={};W.rebuild(s)
      return function(kind,x,y,lane)
        return W.lane(s,x,y),O.pointAllowed(s,{kind=kind},x,y,lane)
      end
    ''', gastric.lua_table(lua, ORGANS))
    for lane, edge in enumerate(graph['edges'], 1):
        line = LineString(edge['samples'])
        for kind in KINDS:
            points = []
            for fraction in [.15, .25, .4, .6, .75, .85]:
                p = line.interpolate(line.length * fraction); xy = [p.x, p.y]
                default, legal = probe(kind, p.x * 2, p.y * 2 + 512, lane)
                if legal: points.append((fraction, xy, default))
            if len(points) < 2:
                cases.append({'id': f'edge/{edge["id"]}/{kind}', 'family': 'edge',
                              'edgeId': edge['id'], 'laneIndex': lane,
                              'fixtureFailure': 'NO_TWO_RADIUS_LEGAL_EDGE_POINTS'}); continue
            a = next((p for p in points if p[2] == lane), points[0]); b = points[-1]
            if b[0] == a[0]: b = points[0]
            owner = min(ORGANS, key=lambda o: math.dist(rally(layout, o, kind), a[1]))
            actor = point_actor(kind, a[1], b[1], owner, lane, lane)
            if a[2] != lane: actor['setupSource'] = rally(layout, owner, kind)
            cases.append({'id': f'edge/{edge["id"]}/{kind}', 'family': 'edge',
                          'edgeId': edge['id'], 'laneIndex': lane, 'system': edge['system'],
                          'sourceFractions': [a[0], b[0]], 'actors': [actor], 'maxTime': 1800})
    ids = [c['id'] for c in cases]; assert len(ids) == len(set(ids))
    for c in cases:
        c['caseOrgans'] = c.get('organs', [c.get('owner')] if c.get('owner') else [])
        c['organs'] = list(ORGANS)
    result = {'schema': 'fullbody-015-motion-matrix/v1', 'organs': ORGANS,
              'graphEdges': len(graph['edges']), 'frozenPorts': len(graph['ports']),
              'families': {family: sum(c['family'] == family for c in cases)
                           for family in sorted({c['family'] for c in cases})}, 'cases': cases,
              'limitations': ['Peripheral tissue domains are deliberately not added; all peripheral blood edges are checked.',
                              'Named supply/return ports remain blood points; actual tissue exchange uses declared runtime gates.']}
    write(OUT / 'matrix.json', result); return result


def check_actual(config, actual, oracle):
    failures, unknown, disks, capsules = [], 0, 0, 0
    previous = {p['id']: p for p in actual['starts']}
    for point in actual['trace']:
        result = oracle.disk(point, point['kind']); disks += 1
        if result is None: unknown += 1
        elif not result: failures.append({'type': 'disk', 'point': point})
        before = previous.get(point['id'])
        if before:
            result = oracle.capsule(before, point, point['kind']); capsules += 1
            if result is None: unknown += 1
            elif not result: failures.append({'type': 'capsule', 'from': before, 'to': point})
        previous[point['id']] = point
    for frame in actual['frames']:
        for point in frame['points']:
            result = oracle.disk(point, point['kind']); disks += 1
            if result is None: unknown += 1
            elif not result: failures.append({'type': 'frame-disk', 'point': point})
    goals = {g['id']: g for g in actual['goals']}; arrivals = []
    for p in actual['endpoints']:
        goal = goals.get(p['id'])
        if goal:
            arrivals.append({'id': p['id'], 'distanceWorld': math.hypot(p['x'] - goal['x'], p['y'] - goal['y']),
                             'laneMatches': p['lane'] == goal['lane'],
                             'organMatches': goal['lane'] != 0 or p.get('organId') == goal['organId']})
    commands = actual['commands']
    command_ok = (all(not c['accepted'] and not c.get('order') for c in commands)
                  if config.get('negative') else all(c['accepted'] and c.get('order') for c in commands))
    save = actual['save']; save_ok = (save['restored'] and save['positionErrors'] < 1e-8 and
                                     save['laneErrors'] == 0 and save['version'] == 9 and
                                     save.get('restoredNetworkEdges') == 202)
    passed = (actual['completed'] and not actual['spawnErrors'] and command_ok and
              not failures and not unknown and save_ok and
              all(a['distanceWorld'] <= .075 and a['laneMatches'] and a['organMatches'] for a in arrivals) and
              actual['trafficStats'].get('expired', 0) == 0 and
              (actual.get('minimumFrameDiskGapWorld') is None or actual['minimumFrameDiskGapWorld'] >= -1e-6))
    return {'id': config['id'], 'family': config['family'], 'status': 'PASS' if passed else 'FAIL',
            'completed': actual['completed'], 'commandsValid': command_ok, 'spawnErrors': actual['spawnErrors'],
            'arrivals': arrivals, 'savePassed': save_ok, 'elapsedSimulationSeconds': actual['elapsed'],
            'setupSimulationSeconds': actual.get('setupElapsed', 0), 'disksChecked': disks,
            'capsulesChecked': capsules, 'geometryFailures': len(failures), 'firstGeometryFailures': failures[:8],
            'unverifiedDomainPoints': unknown, 'trafficStats': actual['trafficStats'],
            'visitedLanes': sorted({p['lane'] for p in actual['trace'] if p['lane'] > 0}),
            'minimumFrameDiskGapWorld': actual.get('minimumFrameDiskGapWorld'),
            'endpointFailures': [p for p in actual['endpoints'] if p['ordersRemaining'] or p['pathFailed']]}


class FullBodyMotionOracle(atlas.MotionOracle):
    def __init__(self,records):
        super().__init__(records)
        self._domains={};self._disks={};self._transit={}

    def _domain_parts(self,domain):
        key=id(domain)
        if key not in self._domains:
            if len(self._domains)>4096:
                self._domains.clear();self._disks.clear()
            # Keep the original object alive alongside the cached results so
            # Python object IDs cannot alias a newly allocated domain.
            self._domains[key]=(domain,domain.boundary,domain.buffer(2e-6))
        return self._domains[key]

    def full_disk(self,domain,p,radius):
        _,boundary,_=self._domain_parts(domain);key=(id(domain),p[0],p[1],radius)
        if key not in self._disks:
            if len(self._disks)>8192:self._disks.clear()
            center=self.Point(p)
            self._disks[key]=bool(domain.covers(center)and boundary.distance(center)>=radius-2e-6)
        return self._disks[key]

    def full_capsule(self,domain,a,b,radius):
        if a==b:return self.full_disk(domain,a,radius)
        _,_,expanded=self._domain_parts(domain)
        return expanded.covers(self.LineString([a,b]).buffer(radius,quad_segs=32))

    def transit_domain(self,transit):
        key=transit['gateId']
        if key not in self._transit:self._transit[key]=super().transit_domain(transit)
        return self._transit[key]

    def capsule(self,a,b,kind):
        answer=super().capsule(a,b,kind)
        if answer is not False or a.get('transit')or b.get('transit')or bool(a['lane'])==bool(b['lane']):
            return answer
        # Motion.record observes swept movement. It does not observe a zero
        # distance lane handoff at a graph node. The next moved sample may
        # therefore join blood N directly to tissue after N->M->tissue in the
        # same tick. Accept only an exact shared named endpoint, an existing M
        # gate pipe anchor at that endpoint, and the complete raw swept disk.
        blood=a if a['lane']else b;tissue=b if a['lane']else a
        lane=blood['lane'];owner=tissue.get('organId');point=self.source(blood)
        incoming=self.edges[lane-1]
        for gate_owner,gate in self.gates.values():
            if gate_owner!=owner or gate['laneIndex']==lane:continue
            outgoing=self.edges[gate['laneIndex']-1]
            shared=set([incoming['a'],incoming['b']])&set([outgoing['a'],outgoing['b']])
            for node in shared:
                p=incoming['points'][0 if node==incoming['a']else-1]
                q=outgoing['points'][0 if node==outgoing['a']else-1]
                if (math.dist(point,p)>1e-6 or math.dist(p,q)>1e-6 or
                    math.dist(p,gate['pipeAnchorSource'])>1e-6):continue
                domain=self.union([self.blood[lane],self.transit_domain({'gateId':gate['id']})])
                if self.full_capsule(domain,self.source(a),self.source(b),self.radius(kind)):
                    return True
        return False


def motion_worker(shard_path, factory):
    os.chdir(ROOT); shard = read(shard_path)
    _, records = atlas.contract_records(); oracle = FullBodyMotionOracle(records)
    lua = gastric.runtime(); source = atlas.LUA_SCENARIO
    if factory == 'fullbody':
        source = source.replace("require('war.OrganTrial'),require('war.Simulation')",
                                "require('war.FullBodyBattlefield'),require('war.Simulation')")
        source = source.replace("assert(s.organBattlefieldVersion==1,'production organ trial did not enable')",
                                "assert(s.fullbodyBattlefieldVersion==1 and not s.organBattlefieldVersion,'production fullbody factory did not enable')")
        # Preserve the actual new flag in capture/restore evidence, rather than
        # making a fullbody save appear to have the old trial flag.
        source = source.replace('snap.organBattlefieldVersion', 'snap.fullbodyBattlefieldVersion')
        source = source.replace('restored.organBattlefieldVersion', 'restored.fullbodyBattlefieldVersion')
    # Time the original calls at their invocation boundaries. These wrappers
    # forward every argument and return value and do not substitute planning,
    # timestep, geometry, or movement. A budget interruption preserves partial
    # observations so slow planning can be distinguished from a long journey.
    source=source.replace('C.execute(', 'qExecute(').replace('S.step(', 'qStep(')
    source=source.replace('budget<300 do','budget<(qaSetupObservationBudget or 300)do')
    source=source.replace("elapsed<(config.maxTime or 300)","elapsed<(qaObservationBudget or config.maxTime or 300)")
    source=source.replace("local actors={};local result={id=config.id,starts={},trace={},frames={},commands={},goals={},spawnErrors={}}",r'''
 local actors={};local result={id=config.id,starts={},trace={},frames={},commands={},goals={},spawnErrors={}}
 local timings={executeCalls=0,executeTotalCpuSeconds=0,executeMaxCpuSeconds=0,
  simulationStepCalls=0,simulationTotalCpuSeconds=0,simulationMaxStepCpuSeconds=0,
  simulationStepCpuSeconds={},slowSteps={},progress={}}
 result.invocationTiming=timings
 result.observationBudget={simulationMaxTime=qaObservationBudget or config.maxTime or 300,
  setupMaxTime=qaSetupObservationBudget or 300,changesProductionTimestep=false}
 qaPartialState=s;qaPartialActors=actors;qaPartialResult=result;qaPartialTimers=timings
 local function qExecute(...)
  local begun=os.clock();timings.inflight={operation='Commands.execute',begunCpuSeconds=begun}
  local values=table.pack(C.execute(...));local elapsed=os.clock()-begun
  timings.executeCalls=timings.executeCalls+1;timings.executeTotalCpuSeconds=timings.executeTotalCpuSeconds+elapsed
  timings.executeMaxCpuSeconds=math.max(timings.executeMaxCpuSeconds,elapsed);timings.inflight=nil
  return table.unpack(values,1,values.n)
 end
 local function qStep(...)
  local begun=os.clock();timings.inflight={operation='Simulation.step',begunCpuSeconds=begun}
  local values=table.pack(S.step(...));local elapsed=os.clock()-begun
  timings.simulationStepCalls=timings.simulationStepCalls+1
  timings.simulationTotalCpuSeconds=timings.simulationTotalCpuSeconds+elapsed
  timings.simulationMaxStepCpuSeconds=math.max(timings.simulationMaxStepCpuSeconds,elapsed);timings.inflight=nil
  timings.simulationStepCpuSeconds[#timings.simulationStepCpuSeconds+1]=elapsed
  if elapsed>.006 then timings.slowSteps[#timings.slowSteps+1]={simulationTime=s.time,tick=s.tick,cpuSeconds=elapsed}end
  if timings.simulationStepCalls%100==0 then
   local points={};for i,e in ipairs(actors)do points[i]={id=e.id,x=e.x,y=e.y,lane=e.vesselLane,orders=#e.orders,
    distanceToRequested=math.sqrt((e.x-config.actors[i].tx)^2+(e.y-config.actors[i].ty)^2)}end
   timings.progress[#timings.progress+1]={simulationTime=s.time,tick=s.tick,points=points}
  end
  return table.unpack(values,1,values.n)
 end
''')
    source=source.replace("s=restored;for i,a in ipairs(actors)","s=restored;qaPartialState=s;for i,a in ipairs(actors)")
    run = lua.execute(source); loaded_hashes = navigation_hashes()
    for config in shard['cases']:
        path = OUT / shard.get('caseDirectory', factory + '/cases') / (config['id'].replace('/', '__') + '.json')
        if config.get('fixtureFailure'):
            row = {'id': config['id'], 'family': config['family'], 'status': 'FAIL',
                   'fixtureFailure': config['fixtureFailure']}; write(path, {'config': config, 'row': row}); continue
        begun = time.perf_counter()
        before = navigation_hashes()
        if before != loaded_hashes:
            lua = gastric.runtime(); run = lua.execute(source); loaded_hashes = before
        try:
            lua.globals().qaObservationBudget=shard.get('observationMaxTime')
            lua.globals().qaSetupObservationBudget=shard.get('setupMaxTime')
            lua.globals().qaCpuDeadline = lua.eval('os.clock()') + shard['cpuLimitSeconds']
            lua.execute("debug.sethook(function()if os.clock()>qaCpuDeadline then error('QA_CPU_BUDGET_EXCEEDED')end end,'',20000)")
            actual = gastric.convert(run(gastric.lua_table(lua, config)))
            lua.execute('debug.sethook()')
            row = check_actual(config, actual, oracle)
            # Store real complete trajectories, not an illustrative JS replay.
            write(path, {'schema': 'fullbody-015-production-motion-case/v1', 'nativeEvidence': False,
                         'productionNavigationSubstituted': False, 'config': config, 'row': row,
                         'actual': actual, 'inputHashes': before, 'loadedRuntimeHashes': loaded_hashes})
        except Exception as error:
            lua.execute('debug.sethook()')
            row = {'id': config['id'], 'family': config['family'], 'status': 'FAIL', 'runnerError': str(error)}
            partial=None
            if lua.globals().qaPartialState is not None:
                partial=gastric.convert(lua.execute(r'''
                  local result=qaPartialResult
                  result.interrupted=true;result.partialSimulationTime=qaPartialState.time
                  result.partialEndpoints={}
                  for _,e in ipairs(qaPartialActors)do
                   result.partialEndpoints[#result.partialEndpoints+1]={id=e.id,x=e.x,y=e.y,lane=e.vesselLane,
                    orders=e.orders,path=e.path,pathFailed=e.pathFailed,alive=require('war.Util').alive(e)}
                  end
                  if qaPartialTimers.inflight then
                   qaPartialTimers.inflight.elapsedCpuSeconds=os.clock()-qaPartialTimers.inflight.begunCpuSeconds
                  end
                  return result
                '''))
            write(path, {'config': config, 'row': row, 'inputHashes': before,
                         'loadedRuntimeHashes':loaded_hashes,'partialActual':partial})
            # A hook timeout may interrupt the observer cleanup. A fresh actual
            # runtime isolates the next case; no production behavior is patched.
            lua = gastric.runtime(); run = lua.execute(source); loaded_hashes = navigation_hashes()
        row['wallSeconds'] = round(time.perf_counter() - begun, 3)
        if navigation_hashes() != before:
            result = read(path); result['row']['status'] = 'UNDETERMINED_INPUT_CHANGED';
            result['changedHashes'] = {p: navigation_hashes().get(p) for p, h in before.items() if navigation_hashes().get(p) != h}; write(path, result)
        print(config['id'], row['status'], row['wallSeconds'], flush=True)


def motion(args):
    matrix = fixture_matrix(); cases = matrix['cases']
    if args.family: cases = [c for c in cases if c['family'] in args.family.split(',')]
    if args.match: cases = [c for c in cases if args.match in c['id']]
    if args.factory == 'fullbody' and not (ROOT / 'scripts/war/FullBodyBattlefield.lua').is_file():
        result = {'schema': 'fullbody-015-production-motion/v1', 'status': 'UNDETERMINED_INTERFACE_MISSING',
                  'total': len(cases), 'passed': 0, 'missing': 'war.FullBodyBattlefield', 'nativeEvidence': False}
        write(OUT / 'motion-report.json', result); return result
    before = navigation_hashes(); processes = []
    run_id = str(time.time_ns())
    case_directory = args.factory + '/runs/' + run_id + '/cases'
    reused=[];pending=[]
    candidates={}
    if not args.no_resume:
        previous=list((OUT/args.factory/'cases').glob('*.json'))
        previous+=list((OUT/args.factory/'runs').glob('*/cases/*.json'))
        previous+=list((OUT/'diagnostics').glob('long-run-*/cases/*.json'))
        for path in previous:
            candidates.setdefault(path.name,[]).append(path)
    for config in cases:
        name=config['id'].replace('/','__')+'.json';cached=None
        for candidate in reversed(candidates.get(name,[])):
            try:record=read(candidate)
            except (json.JSONDecodeError,OSError):continue
            captured=record.get('inputHashes',{})
            if (record.get('row',{}).get('status')=='PASS'and record.get('config')==config and
                all(captured.get(p)==h for p,h in before.items())and
                all(record.get('loadedRuntimeHashes',{}).get(p)==h for p,h in before.items())):
                cached=(candidate,record);break
        if cached:
            candidate,record=cached
            destination=OUT/case_directory/name;destination.parent.mkdir(parents=True,exist_ok=True)
            # Reuse the complete immutable actual observation byte-for-byte.
            # A hardlink keeps repeated acceptance runs from copying gigabytes
            # of identical substep trajectories; no capture fields are relabeled.
            try:os.link(candidate,destination)
            except OSError:shutil.copyfile(candidate,destination)
            reused.append({'id':config['id'],'from':str(candidate.relative_to(OUT)),
                           'sha256':sha(candidate),'currentHashesMatch':True})
        else:pending.append(config)
    for index in range(args.workers):
        batch = pending[index::args.workers]
        if not batch: continue
        shard = OUT / args.factory / f'shard-{index}.json'
        write(shard, {'cases': batch, 'cpuLimitSeconds': args.cpu_limit, 'caseDirectory': case_directory,
                      'observationMaxTime':args.observation_max_time,'setupMaxTime':args.setup_max_time})
        log = OUT / args.factory / f'shard-{index}.log'
        stream = log.open('w')
        process = subprocess.Popen([sys.executable, str(Path(__file__).resolve()),
                                    '--worker', str(shard), '--factory', args.factory],
                                   cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT)
        processes.append((process, stream, log))
    last = -1
    while any(p.poll() is None for p, _, _ in processes):
        done = sum((OUT / case_directory / (c['id'].replace('/', '__') + '.json')).is_file() for c in cases)
        if done != last: print(f'Production cases recorded: {done}/{len(cases)}', flush=True); last = done
        time.sleep(2)
    for process, stream, log in processes:
        stream.close()
        if process.returncode: print('Worker failure:', process.returncode, log, flush=True)
    rows = [];_,records=atlas.contract_records();oracle=FullBodyMotionOracle(records)
    for c in cases:
        p = OUT / case_directory / (c['id'].replace('/', '__') + '.json')
        if p.is_file():
            observed=read(p);row=observed['row']
            if row.get('geometryFailures')and observed.get('actual'):
                reviewed=check_actual(c,observed['actual'],oracle)
                if reviewed!=row:
                    observed['firstOracleReview']=row;observed['row']=reviewed
                    observed['reviewNote']='Exact shared-node zero-distance lane handoffs absent from Motion.record are certified against existing named gate domains; no trajectory changed.'
                    observed['oracleReviewScriptSha256']=sha(Path(__file__))
                    write(p,observed);row=reviewed
            rows.append(row)
        else: rows.append({'id': c['id'], 'family': c['family'], 'status': 'UNDETERMINED_NO_CASE_OUTPUT'})
    after = navigation_hashes(); changed = [p for p, value in before.items() if value != after.get(p)]
    families = {f: {'total': sum(c['family'] == f for c in cases),
                    'passed': sum(r['family'] == f and r['status'] == 'PASS' for r in rows)} for f in matrix['families']}
    result = {'schema': 'fullbody-015-production-motion/v1', 'nativeEvidence': False,
              'productionNavigationSubstituted': False, 'factory': args.factory,
              'runId': run_id, 'caseDirectory': case_directory,
              'reusedCurrentHashVerifiedCases':reused,
              'status': 'UNDETERMINED_INPUT_CHANGED' if changed else 'PASS' if all(r['status'] == 'PASS' for r in rows) else 'RETAINED_FAILURES',
              'total': len(rows), 'passed': sum(r['status'] == 'PASS' for r in rows), 'families': families,
              'cases': rows, 'inputHashes': before, 'afterHashes': after, 'changedDuringChecks': changed,
              'matrixSha256': sha(OUT / 'matrix.json'), 'frozenInputs': freeze_check(),
              'coverage': {'organsExpected': ORGANS, 'graphEdgesExpected': 202,
                           'visitedLanes': sorted({lane for r in rows for lane in r.get('visitedLanes', [])}),
                           'directedOrganPairsExpected': 132, 'wholeBodyAccepted': not args.family and not args.match and all(r['status'] == 'PASS' for r in rows)},
              'limits': ['Actual Lua, offline. No native movement/P95 inference.',
                         'CPU/timeouts and invalid starts remain failures; no QA controller, teleport or route patch.',
                         'Only the locked 12 organ tissues are active; peripheral tissue regions are not added.']}
    write(OUT / f'{args.factory}-motion-report.json', result)
    print(result['status'], result['passed'], '/', result['total'], flush=True); return result


def compatibility():
    lua = gastric.runtime()
    restore = lua.execute(r'''
      local Save,W,U,O,F=require('war.Save'),require('war.World'),require('war.Util'),
        require('war.OrganBattlefield'),require('war.FullBodyBattlefield')
      return function(snapshot)
        local s=Save.restore(snapshot);local now=Save.snapshot(s)
        local errors={position=0,lane=0};local count=0
        for _,e in ipairs(snapshot.entities)do
          local q=s.entities[e.id];count=count+1
          errors.position=errors.position+(q and math.abs(e.x-q.x)+math.abs(e.y-q.y)or 1)
          errors.lane=errors.lane+(q and (e.vesselLane or 0)==(q.vesselLane or 0)and 0 or 1)
        end
        return {positionErrors=errors.position,laneErrors=errors.lane,entities=count,
          anatomyVersion=s.anatomyVersion,fullbodyFlag=s.fullbodyBattlefieldVersion,
          organFlag=s.organBattlefieldVersion,gastricFlag=s.gastricBattlefieldVersion,
          enabled=F.enabled(s),organEnabled=O.enabled(s),mode=s.campaign and 'campaign'or'sandbox',
          rngUnchanged=s.rng==snapshot.rng,saveVersion=now.version,networkEdges=#W.vessels(s).edges}
      end
    ''')
    rows=[]
    for fixture in baseline()['legacyFixtures']:
        path=OUT/fixture['file'];assert sha(path)==fixture['sha256']
        result=gastric.convert(restore(gastric.lua_table(lua,read(path))))
        passed=(result['positionErrors']<1e-8 and result['laneErrors']==0 and result['rngUnchanged'] and
                not result.get('fullbodyFlag') and not result.get('enabled') and
                result['anatomyVersion']==fixture['anatomyVersion'] and result['mode']==fixture['mode'])
        rows.append({'id':fixture['file'],'status':'PASS'if passed else'FAIL',**result})
    new=gastric.convert(lua.execute(r'''
      local F,O,Save,S,W,U=require('war.FullBodyBattlefield'),require('war.OrganBattlefield'),
        require('war.Save'),require('war.Simulation'),require('war.World'),require('war.Util')
      local s=F.new(73);local original=Save.snapshot(s);local ids=O.activeOrgans(s)
      local restored=Save.restore(original);local errors=0;local lanes=0
      for id,e in pairs(s.entities)do local q=restored.entities[id]
        errors=errors+(q and math.abs(e.x-q.x)+math.abs(e.y-q.y)or 1)
        lanes=lanes+(q and e.vesselLane==q.vesselLane and 0 or 1)
      end
      for _=1,10 do S.step(restored,.1)end
      local old=require('war.Simulation').new(73,'sandbox',3)
      local accepted,reason=F.enable(old)
      local campaign=require('war.Simulation').new(73,'campaign',4)
      local cc,cr=F.enable(campaign)
      local subset=require('war.Simulation').new(73,'sandbox',4)
      local partial,pr=F.enable(subset,{'stomach'})
      local duplicate=require('war.Simulation').new(73,'sandbox',4)
      local twice={};for _,id in ipairs(ids)do twice[#twice+1]=id end
      twice[#twice+1]=ids[1];local dup,dr=F.enable(duplicate,twice)
      return {activeOrgans=ids,newFlag=s.fullbodyBattlefieldVersion,
        trialFlag=s.organBattlefieldVersion,gastricFlag=s.gastricBattlefieldVersion,
        snapshotFlag=original.fullbodyBattlefieldVersion,snapshotTrialFlag=original.organBattlefieldVersion,
        restoredFlag=restored.fullbodyBattlefieldVersion,saveVersion=original.version,
        positionErrors=errors,laneErrors=lanes,edges=#W.vessels(restored).edges,
        steppedTime=restored.time-original.time,steppedTick=restored.tick-original.tick,
        oldEnableRejected=accepted==false,oldReason=reason,
        campaignEnableRejected=cc==false,campaignReason=cr,campaignUnmodified=campaign.fullbodyBattlefieldVersion==nil,
        partialEnableRejected=partial==false,partialReason=pr,partialUnmodified=subset.fullbodyBattlefieldVersion==nil,
        duplicateEnableRejected=dup==false,duplicateReason=dr,duplicateUnmodified=duplicate.fullbodyBattlefieldVersion==nil}
    '''))
    passed=(set(new['activeOrgans'])==set(ORGANS)and new['newFlag']==new['snapshotFlag']==new['restoredFlag']==1 and
            not new.get('trialFlag')and not new.get('gastricFlag')and not new.get('snapshotTrialFlag')and
            new['saveVersion']==9 and new['positionErrors']<1e-8 and new['laneErrors']==0 and new['edges']==202 and
            abs(new['steppedTime']-1)<1e-8 and new['steppedTick']==10 and new['oldEnableRejected']and
            new['campaignEnableRejected']and new['campaignUnmodified']and
            new['partialEnableRejected']and new['partialUnmodified']and
            new['duplicateEnableRejected']and new['duplicateUnmodified'])
    rows.append({'id':'new-fullbody-factory-save-step','status':'PASS'if passed else'FAIL',**new})
    result={'schema':'fullbody-015-save-compatibility/v1','nativeEvidence':False,
            'status':'PASS'if all(r['status']=='PASS'for r in rows)else'FAIL','rows':rows,
            'saveVersion':9,'newFullbodyModeExplicitOptIn':True,'legacyFixtureHashes':baseline()['legacyFixtures'],
            'inputHashes':navigation_hashes()}
    write(OUT/'compatibility-report.json',result);print('Compatibility',result['status'],flush=True);return result


def motion_review():
    # A long-running worker may predate a pure observer/oracle repair. Recheck
    # its captured production data without re-simulating, changing a point or
    # lending current-code hashes to a formerly loaded runtime.
    path=OUT/'fullbody-motion-report.json';report=read(path);nav=navigation_hashes()
    archive=OUT/'fullbody'/'runs'/report['runId']/'first-motion-report.json'
    if not archive.exists():write(archive,report)
    _,records=atlas.contract_records();oracle=FullBodyMotionOracle(records)
    rows=[];reviewed=[];stale=[]
    for old in report['cases']:
        p=OUT/report['caseDirectory']/(old['id'].replace('/','__')+'.json')
        if not p.is_file():rows.append(old);continue
        d=read(p);row=d['row']
        if (any(d.get('inputHashes',{}).get(k)!=v for k,v in nav.items())or
            any(d.get('loadedRuntimeHashes',{}).get(k)!=v for k,v in nav.items())):
            stale.append(row['id']);rows.append({**row,'status':'UNDETERMINED_STALE_RUNTIME'});continue
        if row.get('geometryFailures')and d.get('actual'):
            newer=check_actual(d['config'],d['actual'],oracle)
            d.setdefault('firstOracleReview',row);d['row']=newer
            d['oracleReviewScriptSha256']=sha(Path(__file__))
            d['reviewNote']='Exact shared-node zero-distance lane handoffs absent from Motion.record are certified against existing named gate domains; no trajectory changed.'
            write(p,d);row=newer;reviewed.append(row['id'])
        rows.append(row)
    passed=sum(r['status']=='PASS'for r in rows)
    report['cases']=rows;report['passed']=passed
    report['status']='UNDETERMINED_STALE_RUNTIME'if stale else'PASS'if passed==len(rows)else'RETAINED_FAILURES'
    for family,c in report['families'].items():c['passed']=sum(r['family']==family and r['status']=='PASS'for r in rows)
    report['coverage']['wholeBodyAccepted']=len(rows)==len(fixture_matrix()['cases'])and passed==len(rows)and not stale
    report['independentPostCaptureReview']={'oracleScriptSha256':sha(Path(__file__)),'reviewedCases':reviewed,
                                          'staleRuntimeCases':stale,'originalReportPath':str(archive.relative_to(OUT)),
                                          'productionTrajectoriesModified':False}
    write(path,report);print('Independent motion review',report['status'],passed,'/',len(rows),flush=True);return report


def clearance():
    _,records=atlas.contract_records();oracle=FullBodyMotionOracle(records);layout=runtime_layout()
    rows=[]
    for owner in ORGANS:
        for kind in KINDS:
            for g in layout[owner]['gateContracts'][kind]:
                domain=oracle.transit_domain({'gateId':g['id']})
                radius=oracle.radius(kind)
                margins=[]
                for name in ['pipeAnchorSource','tissueAnchorSource']:
                    point=oracle.Point(g[name]);margins.append(domain.boundary.distance(point)-radius if domain.covers(point) else -radius)
                passed=all(m>=-2e-6 for m in margins)
                rows.append({'organId':owner,'gateId':g['id'],'kind':kind,'laneIndex':g['laneIndex'],
                             'status':'PASS'if passed else'FAIL','anchorRadiusMarginsSource':margins,
                             'singleFileBloodDeclared':g.get('requiresSingleFileInBlood'),
                             'minimumTwoSiegePassingWidthSource':2.375,
                             'nominalOpeningWidthSource':g.get('openingWidthSource')})
    result={'schema':'fullbody-015-independent-entry-clearance/v1','nativeEvidence':False,
            'status':'PASS'if all(r['status']=='PASS'for r in rows)else'FAIL','rows':rows,
            'passed':sum(r['status']=='PASS'for r in rows),'total':len(rows),
            'inputHashes':navigation_hashes(),
            'limits':['Un-eroded raw geometry certifies full-circle anchors. Actual reciprocal commands are separately tested for every gate.',
                      'Blood width below the two-siege reserve requires production traffic yielding, not artificial widening.']}
    write(OUT/'clearance-report.json',result);print('Entry clearance',result['status'],result['passed'],'/',result['total'],flush=True);return result


def asset_specs():
    lua=gastric.runtime()
    data=gastric.convert(lua.execute("local D=require('war.FullBodyMapArtData');return D"))
    specs=[]
    if data.get('quietBase'):
        specs.append({'layer':'quietBase',**data['quietBase']})
    for layer in ['surfaceTiles','organs','deepTiles','junctions','foregroundPatches']:
        for spec in data.get(layer,[]): specs.append({'layer':layer,**spec})
    assert specs and len({s['id']for s in specs})==len(specs)
    return data,specs



NARROW_MOUTH_LIP_ID='fixed-four-mouths-roof-lip-n'

def narrow_mouth_lip_contract(spec,asset,manifest,rgba):
    """One explicit N foreground extension; generation cannot define geometry."""
    from scipy.ndimage import distance_transform_edt
    rows=[];binding={}
    def check(name,pass_,**facts):rows.append({'id':name,'status':'PASS'if pass_ else'FAIL',**facts})
    def bind(path):binding[str(path.relative_to(ROOT))]=sha(path);return binding[str(path.relative_to(ROOT))]
    contract_path=DOC/'bake/fifth-candidate-n/local-rim-uv-contract.json'
    contract=read(contract_path);baseline_path=DOC/'bake/fourth-candidate-k/manifest.json';baseline=read(baseline_path)
    check('N lip exact independently reviewed contract SHA',bind(contract_path)=='9a43c2096dc4759d14363291a5808c8e8ee3fc92cc39398ad4d0210e7757309d')
    check('N lip exact K baseline provenance SHA',bind(baseline_path)=='f2dd7bb5757576e37d18e78154730b1a106a18afed3837d95b2c400cc79a1750')
    check('N lip exact existing registered four-mouth source crop',spec['id']==asset['id']==NARROW_MOUTH_LIP_ID and
          spec['sourceBox']==asset['sourceBox']==contract['sourceBox']==[507,545,532,561]and
          spec['pixelSize']==asset['pixelSize']==[400,256]and asset['edgeIds']==['e010','e119']and
          asset['generatedGeometryAccepted']is False and contract['materialMappingIsMapCoordinateRefit']is False)
    check('N lip exact accepted PNG SHA',asset['sha256']==bind(ROOT/asset['path'])==
          '68fabc460d271e96711a787982d23fcd6b9bd69e905983dfeb9d0edb95fab15e')
    old={a['id']:a for a in baseline['assets']};now={a['id']:a for a in manifest['assets']}
    check('N lip is only appended resource; original41K records unchanged',set(now)-set(old)=={NARROW_MOUTH_LIP_ID}and
          all(now.get(id)==a for id,a in old.items()))
    check('N lip keeps all K geometry widths logical135 visual107 byte-value',all(manifest[k]==baseline[k]for k in
          ['edges','coordinates','actualArtForeground','displayAlphaContract']))
    check('N lip is final foreground layer and K42 originalruntime slots unchanged',
          all(manifest['runtimeSpec'][k]==baseline['runtimeSpec'][k]for k in
          ['surfaceTiles','organs','deepTiles','junctions'])and
          manifest['runtimeSpec']['foregroundPatches'][:-1]==baseline['runtimeSpec']['foregroundPatches']and
          manifest['runtimeSpec']['foregroundPatches'][-1]['id']==NARROW_MOUTH_LIP_ID)
    # M is a rejected material trial, but its independently accepted fixed
    # geometric alpha is the immutable maximum allowed lip support.
    mask_path=ROOT/'assets/image/anatomy-reference/vascular-study/fullbody-015-candidate-v5m/foreground/fixed-four-mouths-roof-lip.png'
    fixed=np.asarray(Image.open(mask_path).convert('RGBA'))[:,:,3]
    check('N lip freezes independently accepted M support source SHA',bind(mask_path)==
          '560d9340d6d4b79f65b28e45356b8c01d913b8c0fb580b2e41dc848bc4b73db7')
    check('N lip alpha remains subset and no stronger than fixedM6573',rgba.shape==(256,400,4)and
          fixed.shape==rgba.shape[:2]and np.all(rgba[:,:,3]<=fixed)and
          int((fixed>0).sum())==6573 and int((rgba[:,:,3]>0).sum())==6404,
          positiveAlphaPixels=int((rgba[:,:,3]>0).sum()))
    check('N lip introduces no visible green blood/food paint',int(green_candidates(rgba).sum())==0)
    alpha=rgba[:,:,3];zero=alpha==0
    _,nearest=distance_transform_edt(zero,return_indices=True)
    expected=rgba[nearest[0],nearest[1],:3]
    check('N lip alpha0 RGB padded from nearest existing positive support',np.array_equal(rgba[:,:,:3][zero],expected[zero]))
    check('N lip adds bounded 409600 decoded bytes',asset['pixelSize'][0]*asset['pixelSize'][1]*4==409600)
    return rows,binding


def effective_asset_specs():
    """Match the registered heart and bowel substitutions without adding slots."""
    lua=gastric.runtime();data,_=asset_specs()
    effective=gastric.convert(lua.execute("""
      local D,H=require('war.FullBodyMapArtData'),require('war.HeartVisualData')
      local B=require('war.BowelVisual');local out={}
      if D.quietBase then local q={};for k,v in pairs(H.replaceQuiet(D.quietBase))do q[k]=v end;q.layer='quietBase';out[#out+1]=q end
      for _,layer in ipairs({'surfaceTiles','organs','deepTiles','junctions','foregroundPatches'})do
       for _,spec in ipairs(D[layer]or{})do
        local current=layer=='organs'and H.replace(spec)or spec
        if layer=='foregroundPatches'and H.replacePatch then current=H.replacePatch(current)end
        current=B.replace(current)
        local q={};for k,v in pairs(current)do q[k]=v end
        q.layer=layer;out[#out+1]=q
       end
      end
      return out
    """))
    return data,effective

def green_candidates(rgba):
    # Preserve the previously accepted visible palette boundary. Blue veins
    # remain blue; teal/green blood is inspected regardless of collision role.
    rgb=rgba[:,:,:3].astype(np.float32);high=rgb.max(axis=2);low=rgb.min(axis=2)
    chroma=high-low;den=np.where(chroma>0,chroma,1);hue=np.zeros(high.shape,dtype=np.float32)
    red=(rgb[:,:,0]==high)&(chroma>0);green=(rgb[:,:,1]==high)&~red&(chroma>0);blue=(chroma>0)&~red&~green
    hue[red]=((rgb[:,:,1]-rgb[:,:,2])/den)[red]%6
    hue[green]=((rgb[:,:,2]-rgb[:,:,0])/den)[green]+2
    hue[blue]=((rgb[:,:,0]-rgb[:,:,1])/den)[blue]+4;hue*=60
    alpha=rgba[:,:,3].astype(np.float32)/255
    return ((rgba[:,:,3]>0)&(hue>=70)&(hue<=202)&(chroma/np.where(high>0,high,1)>=25/255)
            &(high>=40)&(chroma>=12)&(chroma*alpha>=8))


def raw_ring_mask(rings,bounds,size):
    # Independent direct SVG from declared source polygons, without compiler
    # sliver cleanup, vascular footprint construction or simplification.
    import cairosvg
    paths=[]
    for polygon in rings:
        rings_path=[]
        for ring in [polygon['outer'],*polygon.get('holes',[])]:
            rings_path.append('M '+' L '.join(f'{x},{y}'for x,y in ring)+' Z')
        paths.append('<path d="'+' '.join(rings_path)+'" fill="white" fill-rule="evenodd"/>')
    x,y,xx,yy=bounds
    svg=(f'<svg xmlns="http://www.w3.org/2000/svg" width="{size[0]}" height="{size[1]}" '
         f'viewBox="{x} {y} {xx-x} {yy-y}">'+''.join(paths)+'</svg>')
    return np.asarray(Image.open(io.BytesIO(cairosvg.svg2png(bytestring=svg.encode()))).convert('RGBA'))[:,:,3]


def visual_geometry_mask(geometry,bounds,size):
    """Rasterize a registered independent geometry, never a baked RGB mask."""
    import cairosvg
    from shapely.geometry import box
    geometry=geometry.intersection(box(*bounds)).simplify(.008,preserve_topology=True)
    def polygons(g):
        if g.geom_type=='Polygon':return[g]
        return[p for item in getattr(g,'geoms',[])for p in polygons(item)]
    paths=[]
    for p in polygons(geometry):
        paths.append(' '.join('M '+' L '.join(f'{x:.5f},{y:.5f}'for x,y in ring.coords)+' Z'
                              for ring in [p.exterior,*p.interiors]))
    x,y,xx,yy=bounds
    svg=(f'<svg xmlns="http://www.w3.org/2000/svg" width="{size[0]}" height="{size[1]}" '
         f'viewBox="{x} {y} {xx-x} {yy-y}"><path d="'+' '.join(paths)+'" fill="white" fill-rule="evenodd"/></svg>')
    return np.asarray(Image.open(io.BytesIO(cairosvg.svg2png(bytestring=svg.encode()))).convert('RGBA'))[:,:,3]


def foreground_contract_path(manifest):
    contract=manifest.get('actualArtForeground')
    if contract is None:return None
    if contract.get('schema')=='fullbody-actual-foreground/v3':
        return DOC/'bake/third-repair/actual-art-foreground-v3.json'
    if contract.get('schema')=='fullbody-actual-foreground/v4':
        # Fourth candidates must declare their independent metadata artifact.
        # A private candidate path is never silently substituted for delivery.
        name=manifest.get('actualArtForegroundContractPath')
        if not name:raise ValueError('v4 requires actualArtForegroundContractPath')
        return ROOT/name
    raise ValueError('Unknown actual-art foreground schema')


def actual_foreground_contract_v4(manifest):
    import check_fullbody_foreground_semantics as semantic
    contract=manifest['actualArtForeground'];path=foreground_contract_path(manifest)
    geometry,rows,binding,_=semantic.analyze(ROOT/contract['guideContractPath'],contract,manifest)
    def check(name,passed,**facts):rows.append({'id':name,'status':'PASS'if passed else'FAIL',**facts})
    binding[str(path.relative_to(ROOT))]=sha(path)
    check('independent v4 metadata artifact matches compiler manifest',
          read(path)==contract and sha(path)==manifest.get('actualArtForegroundContractSha256'))
    actual_path=ROOT/contract['path'];binding[contract['path']]=sha(actual_path)
    with Image.open(actual_path)as image:
        mode=image.mode;size=list(image.size);actual=np.asarray(image)
    check('foreground mask is explicit grayscale not RGBA alpha',
          mode=='L'and size==contract['pixelSize']and actual.ndim==2 and
          actual.size>0 and int(actual.max())>0 and int(actual.min())<255,
          storedMode=mode,pixelSize=size,grayMinimum=int(actual.min()),grayMaximum=int(actual.max()))
    rebuilt=visual_geometry_mask(geometry,contract['sourceBox'],contract['pixelSize'])
    check('sixteen-density foreground independently rasterized from accepted SVG',
          size==contract['pixelSize']and np.array_equal(rebuilt,actual)and
          sha(actual_path)==contract['sha256'],differingMaskPixels=int((rebuilt!=actual).sum()),
          sourceArea=geometry.area,sourceBox=contract['sourceBox'],registrationScale=contract['registrationScale'])
    guide=read(ROOT/contract['guideContractPath'])
    proof_guide=guide;proof_geometry=geometry
    if guide.get('portalReflectionExclusion'):
        portal=guide['portalReflectionExclusion']
        proof_guide=read(ROOT/portal['inputManifestPath'])
        proof_geometry=semantic.svg_geometry(ROOT/proof_guide['sharedForegroundSvgPath'])
        portal_rows,portal_bindings=portal_reflection_foreground_contract(guide,geometry)
        rows.extend(portal_rows);binding.update(portal_bindings)
    exterior_rows,exterior_bindings=gastric_exterior_foreground_contract(proof_guide,proof_geometry)
    rows.extend(exterior_rows);binding.update(exterior_bindings)
    return geometry,rows,binding


def portal_reflection_foreground_contract(guide,geometry):
    """Verify the one reviewed v7 reflection exclusion, never a broad repaint."""
    import check_fullbody_foreground_semantics as semantic
    from shapely.geometry import Point,LineString,box
    from shapely.ops import unary_union
    rows=[];binding={};q=guide['portalReflectionExclusion']
    def check(name,passed,**facts):rows.append({'id':name,'status':'PASS'if passed else'FAIL',**facts})
    def bind(path):binding[path]=sha(ROOT/path);return binding[path]
    proposal_path=OUT/'fourth-repair/semantic-details/portal-reflection-bounded-exclusion.json'
    proposal=read(proposal_path);binding[str(proposal_path.relative_to(ROOT))]=sha(proposal_path)
    proposed=semantic.ring_geometry(proposal['sourcePolygons'])
    check('portal exclusion binds independent exact reviewed proposal',
          sha(proposal_path)=='d741c7905ea6a3335ab03eb577759a40de9737ee8f2b78e5be4823a8deb05e2e'and
          q['sourceProbe']==[476.625,556.56875]and q['sourceBox']==[469.75,551.5,484.25,567.1]and
          q.get('actualOrganInteriorChanged')is False and q.get('canonicalAirYChanged')is False and
          q.get('routeChanged')is False and q.get('legacy135Changed')is False)
    check('portal repair binds accepted v7 source history',
          bind(q['inputManifestPath'])==q['inputManifestSha256']==
          '672bcd9942fe50c4f7117e021a4a270c894271688af8b64fc813178bd53c01cb'and
          bind(q['inputGeometryPath'])==q['inputGeometrySha256']and
          bind(q['removedGeometryPath'])==q['removedGeometrySha256'])
    previous=read(ROOT/q['inputManifestPath'])
    check('portal input geometry matches its own previous guide',
          previous['sharedForegroundSvgPath']==q['inputGeometryPath']and
          previous['sharedForegroundSvgSha256']==q['inputGeometrySha256'])
    original=semantic.svg_geometry(ROOT/q['inputGeometryPath'],normalize=False)
    point=Point(q['sourceProbe']);component=next(p for p in semantic.polygons(original)if p.covers(point))
    declared=semantic.svg_geometry(ROOT/q['removedGeometryPath'],normalize=False)
    check('portal removed component is exact bounded reviewed surface reflection',
          component.symmetric_difference(proposed).area<1e-9 and
          declared.symmetric_difference(component).area<1e-9 and
          abs(component.area-q['removedAreaSource'])<1e-8,
          removedAreaSource=component.area,sourceBox=list(component.bounds))
    for organ in ORGANS:
        p=atlas.BASE/('stomach-playable/layout.json'if organ=='stomach'else'organ-atlas/geometry/'+organ+'.json')
        g=read(p);binding[str(p.relative_to(ROOT))]=sha(p)
        outer=semantic.ring_geometry(g['outerRings'])
        lumen=semantic.ring_geometry(g['foodRings'if organ=='stomach'else'foodAirUrineRings'])
        actual=lumen.intersection(outer)if organ=='stomach'else lumen
        area=component.intersection(outer.union(actual)).area
        check('portal exclusion preserves actual organ and lumen:'+organ,area==0,
              protectedSemanticAreaChangedSource=area)
    airway=unary_union([LineString(p['points']).buffer(p['width']/2,cap_style=1,join_style=1,quad_segs=24)
                       for p in guide['airwayRoofRepair']['passages']]).intersection(box(*guide['airwayRoofRepair']['sourceBox']))
    check('portal exclusion preserves canonical airway Y',component.intersection(airway).area==0)
    rebuilt=semantic.normalize_source_geometry(original.difference(component))
    check('v8 geometry only subtracts the exact reviewed portal component',
          rebuilt.symmetric_difference(geometry).area<1e-9,
          unexpectedGeometryDifferenceSource=rebuilt.symmetric_difference(geometry).area)
    return rows,binding


def gastric_exterior_foreground_contract(guide,geometry):
    """Rebuild the actual visible gastric-exterior roof from accepted inputs.

    This image classifier verifies artwork only. Frozen semantic routes, lane
    ownership, collision and the original logical135 are never inferred here.
    """
    import check_fullbody_foreground_semantics as semantic
    from shapely import set_precision
    from shapely.geometry import box,LineString
    from shapely.ops import unary_union
    rows=[];binding={};q=guide.get('gastricOutsideForegroundException')
    def check(name,passed,**facts):rows.append({'id':name,'status':'PASS'if passed else'FAIL',**facts})
    check('gastric exterior visible foreground has explicit independent proof',q is not None)
    if q is None:return rows,binding
    def bind(name):
        binding[name]=sha(ROOT/name);return binding[name]
    expected_classifier={'redMinimum':155,'greenMinimum':140,'redMinusGreenMaximum':48,
        'greenMinusBlueMinimum':17,'redMinusBlueMinimum':30,'comparisons':'strict > and <'}
    bounds=q['candidateSourceBox'];size=q['candidatePixelSize'];scale=q['registrationScale']
    check('gastric exterior proof declares exact image and source rules',
          q['creamClassifier']==expected_classifier and scale==4 and
          size==[(bounds[2]-bounds[0])*scale,(bounds[3]-bounds[1])*scale]and
          q['rowRunSimplifySource']==.06 and q['coverageBufferSource']==.10 and
          q.get('navigationEdited')is False and q.get('logical135Unchanged')is True)
    art_path=atlas.BASE/'organ-atlas/art.json';art=read(art_path)
    binding[str(art_path.relative_to(ROOT))]=sha(art_path)
    accepted_registration={o['organId']:o for o in art['organs']}
    check('gastric exterior source layers are complete and ordered',
          len(q['acceptedOrganInputs'])==12 and {o['id']for o in q['acceptedOrganInputs']}==set(ORGANS)and
          q['compositionOrder']==['quiet-base',*[o['id']for o in q['acceptedOrganInputs']]])
    check('gastric exterior uses accepted quiet body',bind(q['quietBasePath'])==q['quietBaseSha256']==
          'ef4cb61f0a4013a5f23ddbc8a23a3de54f43a333d664c5397349e6d45c8c3a47')
    canvas=Image.open(ROOT/q['quietBasePath']).convert('RGBA').transform(tuple(size),Image.Transform.AFFINE,
           (1/scale,0,bounds[0],0,1/scale,bounds[1]),resample=Image.Resampling.BILINEAR)
    independent_lumens=[]
    for entry in q['acceptedOrganInputs']:
        name=entry['id'];check('gastric exterior accepted image:'+name,
            bind(entry['path'])==entry['sha256']and entry['sourceBox']==accepted_registration[name]['sourceBox'])
        im=Image.open(ROOT/entry['path']).convert('RGBA');b=entry['sourceBox']
        sx,sy=im.width/(b[2]-b[0]),im.height/(b[3]-b[1])
        layer=im.transform(tuple(size),Image.Transform.AFFINE,
              (sx/scale,0,(bounds[0]-b[0])*sx,0,sy/scale,(bounds[1]-b[1])*sy),resample=Image.Resampling.BILINEAR)
        canvas=Image.alpha_composite(canvas,layer)
        gp=atlas.BASE/('stomach-playable/layout.json'if name=='stomach'else'organ-atlas/geometry/'+name+'.json')
        binding[str(gp.relative_to(ROOT))]=sha(gp);g=read(gp)
        if name!='stomach':independent_lumens.append(semantic.ring_geometry(g['foodAirUrineRings']))
    stomach_path=ROOT/q['stomachGeometryPath'];stomach=read(stomach_path)
    check('gastric exterior proof keeps original stomach',sha(stomach_path)==q['stomachGeometrySha256'])
    outside=semantic.ring_geometry(stomach['foodRings']).difference(semantic.ring_geometry(stomach['outerRings']))
    candidate=visual_geometry_mask(outside,bounds,size)>127
    rgb=np.asarray(canvas)[:,:,:3].astype(np.int16);red,green,blue=rgb[:,:,0],rgb[:,:,1],rgb[:,:,2]
    cream=(red>155)&(green>140)&(red-green<48)&(green-blue>17)&(red-blue>30)&candidate
    with Image.open(ROOT/q['creamMaskPath'])as image:
        mask_mode=image.mode;actual=np.asarray(image)
    check('gastric exterior gray cream selection independently rebuilt',
          bind(q['creamMaskPath'])==q['creamMaskSha256']and mask_mode=='L'and
          actual.shape==cream.shape and np.array_equal(actual,cream.astype(np.uint8)*255),
          storedMode=mask_mode,differingMaskPixels=int((actual!=cream.astype(np.uint8)*255).sum()))
    rectangles=[];active={}
    for row in range(cream.shape[0]+1):
        spans=[]
        if row<cream.shape[0]:
            change=np.diff(np.pad(cream[row].astype(np.int8),(1,1)))
            spans=list(zip(np.flatnonzero(change==1),np.flatnonzero(change==-1)))
        now=set(spans)
        for span,start in list(active.items()):
            if span not in now:
                rectangles.append(box(bounds[0]+span[0]/scale,bounds[1]+start/scale,
                                      bounds[0]+span[1]/scale,bounds[1]+row/scale));del active[span]
        for span in spans:active.setdefault(span,row)
    cream_geometry=unary_union(rectangles).simplify(.06,preserve_topology=True).buffer(.10,join_style=1).intersection(outside)
    repair=guide['airwayRoofRepair']
    airway=unary_union([LineString(p['points']).buffer(p['width']/2,cap_style=1,join_style=1,quad_segs=24)
                       for p in repair['passages']]).intersection(box(*repair['sourceBox']))
    keep=cream_geometry.union(unary_union(independent_lumens)).union(airway)
    previous_path=ROOT/guide['previousAcceptedForegroundContractPath'];previous=read(previous_path)
    check('gastric repair history SHA binds original accepted source',
          bind(guide['previousAcceptedForegroundContractPath'])==guide['previousAcceptedForegroundContractSha256']and
          bind(previous['sharedForegroundSvgPath'])==previous['sharedForegroundSvgSha256'])
    original=semantic.svg_geometry(ROOT/previous['sharedForegroundSvgPath'],normalize=False)
    removed=original.intersection(outside).difference(keep)
    raw_revision=original.difference(removed)
    rebuilt=semantic.normalize_source_geometry(raw_revision)
    difference=rebuilt.symmetric_difference(geometry)
    check('gastric exterior roof revision independently reconstructed',
          difference.buffer(-.0001).area<1e-10 and
          abs(removed.area-q['removedFalseRoofAreaSource'])<1e-7,
          differingAreaSource=difference.area,differingCoreAreaSource=difference.buffer(-.0001).area,
          removedFalseRoofAreaSource=removed.area,maximumSVGPrecisionCoreGuardSource=.0001,
          numericFragmentMinimumAreaSource=.0001,
          normalizedNumericFragmentAreaSource=raw_revision.symmetric_difference(rebuilt).area)
    return rows,binding


def actual_foreground_contract(manifest):
    """Reconstruct the third repair from accepted images and frozen semantics.

    The logical underpass table is a separate contract. Ordinary pink tissue
    within its broad candidate domain is not automatically a painted roof.
    """
    if manifest.get('actualArtForeground',{}).get('schema')=='fullbody-actual-foreground/v4':
        return actual_foreground_contract_v4(manifest)
    from scipy.ndimage import binary_closing
    from shapely import set_precision
    from shapely.geometry import Polygon,LineString,GeometryCollection,box
    from shapely.ops import unary_union
    contract=manifest.get('actualArtForeground')
    if not contract:return None,[],{}
    rows=[];binding={}
    def check(name,passed,**facts):rows.append({'id':name,'status':'PASS'if passed else'FAIL',**facts})
    path=foreground_contract_path(manifest)
    binding[str(path.relative_to(ROOT))]=sha(path)
    check('art foreground metadata matches compiler manifest',read(path)==contract)
    check('art mask keeps fixed source coordinates',contract['schema']=='fullbody-actual-foreground/v3'and
          contract['sourceBox']==[0,0,1024,1536]and contract['pixelSize']==[4096,6144]and
          contract['registrationScale']==4 and contract['generatedColorsDefineCollision']is False)
    final=read(GRAPH);binding[str(GRAPH.relative_to(ROOT))]=sha(GRAPH)
    check('art foreground frozen graph input',sha(GRAPH)==contract['logicalGeometrySha256']==FROZEN_GRAPH_SHA)
    art={o['organId']:o for o in read(atlas.BASE/'organ-atlas/art.json')['organs']}
    check('art foreground has all twelve unique accepted inputs',
          len(contract['acceptedOrganInputs'])==12 and {o['id']for o in contract['acceptedOrganInputs']}==set(ORGANS))
    shapes=[LineString(p['points']).buffer(p['width']/2+.15,cap_style=2)
            for p in final['protectedPassages']if len(p['points'])>1]
    stomach=None
    for o in contract['acceptedOrganInputs']:
        p=ROOT/o['path'];binding[o['path']]=sha(p)
        check('art mask accepted image:'+o['id'],sha(p)==o['sha256']and o['sourceBox']==art[o['id']]['sourceBox'])
        gp=atlas.BASE/('stomach-playable/layout.json'if o['id']=='stomach'else'organ-atlas/geometry/'+o['id']+'.json')
        binding[str(gp.relative_to(ROOT))]=sha(gp);g=read(gp)
        reserved=unary_union([Polygon(r['outer'],r.get('holes',[]))
            for r in g['foodRings'if o['id']=='stomach'else'foodAirUrineRings']])
        shapes.append(reserved)
        if o['id']=='stomach':stomach=reserved
    registered_path=atlas.BASE/'registered-vessels/geometry.json';registered=read(registered_path)
    binding[str(registered_path.relative_to(ROOT))]=sha(registered_path)
    airway=GeometryCollection()
    for ring in re.findall(r'M\s*([^M]+)',registered['airwayForegroundPath']):
        values=[float(v)for v in re.findall(r'[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?',ring)]
        coordinates=list(zip(values[::2],values[1::2]))
        if len(coordinates)>2:
            p=Polygon(coordinates);airway=airway.symmetric_difference(p if p.is_valid else p.buffer(0))
    candidate=unary_union([*shapes,airway]);x,y,xx,yy=candidate.bounds
    bounds=[math.floor(x-1),math.floor(y-1),math.ceil(xx+1),math.ceil(yy+1)]
    scale=4;size=[(bounds[2]-bounds[0])*scale,(bounds[3]-bounds[1])*scale]
    check('art classifier and registration are explicit',contract.get('creamClassifier')=={
          'redMinimum':155,'greenMinimum':140,'redMinusGreenMaximum':48,
          'greenMinusBlueMinimum':17,'redMinusBlueMinimum':30,'comparisons':'strict > and <'}and
          contract.get('compositionOrder')==['quiet-base',*[o['id']for o in contract['acceptedOrganInputs']]]and
          contract.get('candidateSourceBox')==bounds and contract.get('candidatePixelSize')==size and
          contract.get('binaryClosingIterations')==2 and contract.get('rowRunSimplifySource')==.06 and
          contract.get('foregroundBufferSource')==.10 and contract.get('maskSimplifySource')==.008 and
          contract.get('precisionSource')==.00001 and contract.get('visualUnitDepthGuardSource')==.025)
    quiet=ROOT/contract['quietBasePath'];binding[contract['quietBasePath']]=sha(quiet)
    check('art foreground quiet input retained',sha(quiet)==contract['quietBaseSha256']==
          'ef4cb61f0a4013a5f23ddbc8a23a3de54f43a333d664c5397349e6d45c8c3a47')
    canvas=Image.open(quiet).convert('RGBA').transform(tuple(size),Image.Transform.AFFINE,
           (1/scale,0,bounds[0],0,1/scale,bounds[1]),resample=Image.Resampling.BILINEAR)
    for o in contract['acceptedOrganInputs']:
        im=Image.open(ROOT/o['path']).convert('RGBA');b=o['sourceBox']
        sx,sy=im.width/(b[2]-b[0]),im.height/(b[3]-b[1])
        layer=im.transform(tuple(size),Image.Transform.AFFINE,
              (sx/scale,0,(bounds[0]-b[0])*sx,0,sy/scale,(bounds[1]-b[1])*sy),resample=Image.Resampling.BILINEAR)
        canvas=Image.alpha_composite(canvas,layer)
    rgb=np.asarray(canvas)[:,:,:3].astype(np.int16);red,green,blue=rgb[:,:,0],rgb[:,:,1],rgb[:,:,2]
    candidate_mask=visual_geometry_mask(candidate,bounds,size)>127
    cream=(red>155)&(green>140)&(red-green<48)&(green-blue>17)&(red-blue>30)
    selected=binary_closing(candidate_mask&cream,iterations=contract.get('binaryClosingIterations',2))&candidate_mask
    check('art mask source cream count',int((candidate_mask&cream).sum())==contract['rawCreamPixels'],
          rawCreamPixels=int((candidate_mask&cream).sum()))
    # Register binary source cells with vertical run merging; these rectangles
    # derive solely from source colors, before any new vessel image is loaded.
    rectangles=[];active={}
    for row in range(selected.shape[0]+1):
        runs=[]
        if row<selected.shape[0]:
            changes=np.diff(np.pad(selected[row].astype(np.int8),(1,1)))
            runs=list(zip(np.flatnonzero(changes==1),np.flatnonzero(changes==-1)))
        current=set(runs)
        for span,start in list(active.items()):
            if span not in current:
                rectangles.append(box(bounds[0]+span[0]/scale,bounds[1]+start/scale,
                                      bounds[0]+span[1]/scale,bounds[1]+row/scale));del active[span]
        for span in runs:active.setdefault(span,row)
    surface=unary_union(rectangles).simplify(.06,preserve_topology=True)
    surface=surface.buffer(.10,join_style=1).intersection(candidate).union(stomach)
    def polygons(g):
        if g.geom_type=='Polygon':return[g]
        return[p for item in getattr(g,'geoms',[])for p in polygons(item)]
    geometry=set_precision(unary_union([p.buffer(0)for p in polygons(surface)if p.area>=.0001]),.00001)
    actual_path=ROOT/contract['path'];binding[contract['path']]=sha(actual_path)
    actual=np.asarray(Image.open(actual_path).convert('L'))
    rebuilt=visual_geometry_mask(geometry,contract['sourceBox'],contract['pixelSize'])
    check('actual art foreground independently rebuilt from frozen inputs',np.array_equal(rebuilt,actual)and
          sha(actual_path)==contract['sha256'],differingMaskPixels=int((rebuilt!=actual).sum()),
          sourceArea=geometry.area,logicalCandidateArea=candidate.area)
    stomach_difference=stomach.difference(geometry).area;outside_difference=geometry.difference(candidate).area
    precision_guard=contract['precisionSource']*math.sqrt(2)/2+1e-12
    # Fixed source precision rounds each coordinate by at most half a grid
    # cell. Prove containment outside that subpixel bound; report the raw area
    # differences rather than confusing a snap with a changed food boundary.
    check('complete stomach food cavity remains protected',
          geometry.covers(stomach.buffer(-precision_guard)),differingAreaSource=stomach_difference,
          maximumFixedPrecisionSourceGuard=precision_guard)
    check('art foreground remains in semantic candidate',
          candidate.buffer(precision_guard).covers(geometry),differingAreaSource=outside_difference,
          maximumFixedPrecisionSourceGuard=precision_guard)
    return geometry,rows,binding


def foreground_neighborhood(mask,contract,point):
    """Offset-aware source registration for either the legacy 4x or 16x ROI."""
    x,y,xx,yy=contract['sourceBox'];width,height=contract['pixelSize']
    ix=math.floor((point.x-x)*width/(xx-x));iy=math.floor((point.y-y)*height/(yy-y))
    radius=max(1,math.ceil(contract.get('visualUnitDepthGuardSource',.025)*
                           max(width/(xx-x),height/(yy-y))))
    if ix+radius<0 or iy+radius<0 or ix-radius>=width or iy-radius>=height:
        return np.empty((0,0),dtype=np.uint8)
    return mask[max(0,iy-radius):min(height,iy+radius+1),
                max(0,ix-radius):min(width,ix+radius+1)]


def foreground_sample(mask,contract,point):
    """Sample this exact registered source pixel; neighbors are other points."""
    x,y,xx,yy=contract['sourceBox'];width,height=contract['pixelSize']
    ix=math.floor((point.x-x)*width/(xx-x));iy=math.floor((point.y-y)*height/(yy-y))
    if ix<0 or iy<0 or ix>=width or iy>=height:return 0
    return int(mask[iy,ix])


def complete_pipe_material_contract(manifest):
    """Check source identity and full-width art domains against frozen systems.

    Source alpha only chooses a texture crop. These checks never infer a
    traversable lane, connection or collision from generated image colors.
    Actual banks at joins and overlapping layer visibility need read images.
    """
    rows=[];binding={};metadata=manifest.get('pipeMaterials',{})
    materials=metadata.get('materials',{});domains=manifest.get('pipeUVDomains',{})
    def check(name,passed,**facts):rows.append({'id':name,'status':'PASS'if passed else'FAIL',**facts})
    check('complete pipe sources are three frozen biological classes',
          metadata.get('schema')=='fullbody-complete-gpt-pipe-materials/v1'and
          set(materials)=={'artery','vein','capillary'}and set(domains)==set(materials)and
          metadata.get('sourceGeometryEdited')is False and metadata.get('greenAllowed')is False)
    frozen={e['id']:e for e in read(atlas.BASE/'final-reference-data.json')['edges']}
    counts={kind:sum(e['system']==kind for e in frozen.values())for kind in materials}
    for kind,m in materials.items():
        p=ROOT/m['path'];binding[m['path']]=sha(p)
        with Image.open(p)as image:size=list(image.size)
        crop=m['crop'];low,high=m['floorRangeNormalized'];d=domains.get(kind,{})
        check('complete pipe registered raw source:'+kind,
              sha(p)==m['sha256']and size==m['pixelSize']and len(crop)==4 and
              0<=crop[0]<crop[2]<=size[0]and 0<=crop[1]<crop[3]<=size[1]and
              m.get('alphaIsOnlyTextureBoundary')is True and
              m.get('normaliseTextureColumnsByAlpha')is True,
              path=m['path'],sha256=sha(p),pixelSize=size,crop=crop)
        check('complete pipe two banks surround an open lumen:'+kind,
              0<low<high<1 and d.get('leftBank')==[0,low]and
              d.get('lumen')==[low,high]and d.get('rightBank')==[high,1]and
              d.get('alphaOnlyTextureCrop')is True and d.get('alphaDefinesCollision')is False and
              math.isfinite(m['repeatSourceLength'])and m['repeatSourceLength']>0,
              normalizedDomains=d,frozenEdgeCount=counts[kind])
    for e in manifest['edges']:
        f=frozen[e['id']];kind=e.get('materialClass');m=materials.get(kind,{})
        uv=e.get('materialUV',{});phase=uv.get('phaseAnchorSource');direction=uv.get('phaseDirection')
        check('complete pipe frozen type and source:'+e['id'],
              kind==f['system']==e['system']and uv.get('sourceRawSha256')==m.get('sha256')and
              uv.get('repeatSourceLength')==m.get('repeatSourceLength')and uv.get('twoSidedBanks')is True and
              isinstance(phase,(int,float))and math.isfinite(phase)and direction in [-1,1],
              edgeId=e['id'],frozenSystem=f['system'],materialClass=kind,sourceRawSha256=uv.get('sourceRawSha256'))
    check('all complete pipe classes retain full frozen edge coverage',
          counts=={'artery':77,'vein':83,'capillary':42}and
          {kind:sum(e.get('materialClass')==kind for e in manifest['edges'])for kind in materials}==counts,
          frozenClassCounts=counts)
    return rows,binding


def fourth_display_continuity(manifest):
    """A display-only revision preserves the accepted a90 depth and topology."""
    path=OUT/'fourth-repair/candidates/a90d1edc-first-check/manifest.json'
    baseline=read(path);rows=[]
    def check(name,passed,**facts):rows.append({'id':name,'status':'PASS'if passed else'FAIL',**facts})
    check('display AA baseline is exact archived a90 candidate',
          sha(path)=='a90d1edccd8b1e14ab29fed03647c206430bef528d88985ac2e46dad0f3ffaaa')
    fields=['id','a','b','system','layer','widthSource','sourceSampleSha256','routeEdited',
            'protectedForegroundIntervals']
    old={e['id']:{k:e[k]for k in fields}for e in baseline['edges']}
    new={e['id']:{k:e[k]for k in fields}for e in manifest['edges']}
    check('display AA keeps all 202 routes widths layers and exact 135 logical intervals',
          len(new)==202 and new==old and
          sum(len(e['protectedForegroundIntervals'])for e in manifest['edges'])==135)
    guide=read(ROOT/manifest['actualArtForeground']['guideContractPath'])
    expected_visual={e['id']:e['visualForegroundIntervals']for e in baseline['edges']}
    geometry_fields=['geometrySvgSha256','guideContractSha256','logicalGeometrySha256','visualUnitDepthGuardSource']
    bindings={str(path.relative_to(ROOT)):sha(path)}
    if guide.get('portalReflectionExclusion'):
        proposal_path=OUT/'fourth-repair/semantic-details/portal-reflection-bounded-exclusion.json'
        proposal=read(proposal_path);bindings[str(proposal_path.relative_to(ROOT))]=sha(proposal_path)
        check('display revision uses exact independently reviewed portal scope',
              sha(proposal_path)=='d741c7905ea6a3335ab03eb577759a40de9737ee8f2b78e5be4823a8deb05e2e'and
              {e['edgeId']for e in proposal['affectedVisualEdges']}=={'e014','e125','e147'})
        for change in proposal['affectedVisualEdges']:
            expected_visual[change['edgeId']]=[interval for interval in expected_visual[change['edgeId']]
                if any(abs(interval['startDistance']-a)<1e-8 and abs(interval['endDistance']-b)<1e-8
                       for a,b in change['after'])]
        geometry_fields=['logicalGeometrySha256','visualUnitDepthGuardSource']
    actual_visual={e['id']:e['visualForegroundIntervals']for e in manifest['edges']}
    check('display intervals only change where reviewed false roof was removed',
          actual_visual==expected_visual,
          expectedVisualIntervalCount=sum(map(len,expected_visual.values())),
          actualVisualIntervalCount=sum(map(len,actual_visual.values())),
          allowedChangedEdges=['e014','e125','e147']if guide.get('portalReflectionExclusion')else[])
    check('display AA preserves canonical depth geometry except explicit reviewed portal exclusion',
          all(manifest['actualArtForeground'][k]==baseline['actualArtForeground'][k]for k in geometry_fields))
    return rows,bindings


def display_registered_alpha(image,contract,bounds,size):
    """Sample the declared shared display field in the original source frame."""
    b=contract['sourceBox'];scale=contract['registrationScale']
    return np.asarray(image.transform(tuple(size),Image.Transform.AFFINE,
        ((bounds[2]-bounds[0])*scale/size[0],0,(bounds[0]-b[0])*scale,
         0,(bounds[3]-bounds[1])*scale/size[1],(bounds[1]-b[1])*scale),
        resample=Image.Resampling.BILINEAR))


def display_alpha_contract(manifest,geometry):
    """Independent core/outside checks for the explicitly allowed AA band.

    The unchanged source SVG, not this filtered image, still defines depth.
    Exact old staircase pixels are deliberately not a display requirement.
    """
    from scipy.ndimage import gaussian_filter
    contract=manifest['displayAlphaContract'];rows=[];binding={}
    def check(name,passed,**facts):
        rows.append({'id':name,'status':'PASS'if passed else'FAIL',**facts})
    path=ROOT/contract['contractPath'];binding[contract['contractPath']]=sha(path)
    declared=read(path)
    check('display edge contract is separately bound',sha(path)==contract['contractSha256'] and
          declared=={k:v for k,v in contract.items()if k not in ['contractPath','contractSha256']})
    art=manifest['actualArtForeground']
    check('display AA uses the same canonical geometry and input field',
          contract['schema']=='fullbody-display-edge-alpha/v1'and
          contract['sourceBox']==art['sourceBox']and contract['pixelSize']==art['pixelSize']and
          contract['inputMaskPath']==art['path']and contract['inputMaskSha256']==art['sha256']and
          contract['geometrySvgPath']==art['geometrySvgPath']and
          contract['geometrySvgSha256']==art['geometrySvgSha256'])
    check('display filtering is confined to the locked source-space band',
          contract['registrationScale']==16 and contract['maskEncoding']=='gray-L'and
          contract['gaussianSigmaSource']==.14 and contract['gaussianTruncate']==2 and
          contract['interiorBufferSource']==.30 and contract['exteriorBufferSource']==.30 and
          contract['rasterGuardSource']==1/16 and contract['maximumSourceBoundaryBand']==.3625)
    check('display AA declares no gameplay or interval filtering',
          all(contract.get(name)is False for name in
              ['navigationChanged','geometryChangedByFiltering','legacy135Changed','visualIntervalsChangedByFiltering'])and
          contract['bloodClip']=='complement of this SAME gray field within fixed physical vessel footprint and original near-cut display domain')
    images={}
    for key in ['inputMask','outputMask','opaqueCore','exteriorGuard']:
        name=contract[key+'Path'];p=ROOT/name;binding[name]=sha(p)
        with Image.open(p)as im:
            mode=im.mode;size=list(im.size);pixels=np.asarray(im).copy()
        check('shared display field:'+key,mode=='L'and size==contract['pixelSize']and
              sha(p)==contract[key+'Sha256'],storedMode=mode,pixelSize=size,path=name)
        images[key]=pixels
    bounds,size=contract['sourceBox'],contract['pixelSize']
    independently_rasterized=visual_geometry_mask(geometry,bounds,size)
    check('display input remains exact canonical geometry',
          np.array_equal(images['inputMask'],independently_rasterized))
    core=visual_geometry_mask(geometry.buffer(-.30),bounds,size)
    exterior=visual_geometry_mask(geometry.buffer(.30),bounds,size)
    check('opaque core is independently bounded by source geometry',
          np.array_equal(core,images['opaqueCore']))
    check('exterior guard is independently bounded by source geometry',
          np.array_equal(exterior,images['exteriorGuard']))
    output=images['outputMask'];changed=output!=images['inputMask']
    check('display alpha never weakens the real foreground opaque core',
          not bool(((core==255)&(output!=255)).any()),
          opaqueCoreMismatchPixels=int(((core==255)&(output!=255)).sum()))
    check('display alpha never grows beyond its source exterior guard',
          not bool(((exterior==0)&(output!=0)).any()),
          exteriorGuardMismatchPixels=int(((exterior==0)&(output!=0)).sum()))
    check('every changed display pixel is in the permitted narrow boundary band',
          not bool((changed&((core==255)|(exterior==0))).any()),
          changedAlphaPixels=int(changed.sum()),maximumSourceBoundaryBand=.3625)
    filtered=gaussian_filter(images['inputMask'].astype(np.float32),sigma=.14*16,
                            truncate=2,mode='constant')
    filtered[core==255]=255;filtered[exterior==0]=0
    reconstructed=np.clip(np.rint(filtered),0,255).astype(np.uint8)
    check('registered display field matches declared bounded filtering',
          np.array_equal(output,reconstructed),
          reconstructedMismatchPixels=int((output!=reconstructed).sum()))
    reference={k:contract[k]for k in
               ['outputMaskPath','outputMaskSha256','contractPath','contractSha256']}
    check('all blood organ and foreground assets bind the same display field',
          all(a.get('displayAlphaReference')==reference for a in manifest['assets']))
    return Image.fromarray(output),rows,binding


def pixels():
    path=DOC/'bake/manifest.json';manifest=read(path);frozen=sha(path)
    assert manifest['schema']=='fullbody-015-vascular-material/v1'
    runtime,specs=asset_specs();assets={a['resource']:a for a in manifest['assets']}
    quiet_path=DOC/'quiet-base/visual-protection-v2.json';quiet=read(quiet_path)
    quiet_resource=str(Path(quiet['registeredPNG']).relative_to('assets'))
    # Compiled vascular and optional foreground assets plus the independently
    # registered whole-body background form one atomic runtime pack. The
    # accepted background stays independently hashed, regardless of pack size.
    complete_assets={**assets,quiet_resource:{'resource':quiet_resource,
        'sha256':quiet['registeredPNGSha256'],'sourceBox':quiet['sourceBox'],
        'pixelSize':quiet['sourcePixelSize']}}
    rows=[];organ_rows=[];edge_rows=[];art=read(atlas.BASE/'organ-atlas/art.json')
    expected={o['organId']:o for o in art['organs']}
    def check(name,passed,**facts):
        row={'id':name,'status':'PASS'if passed else'FAIL',**facts};rows.append(row);return row
    for name,value in manifest['inputs'].items():
        check('input:'+name,sha(ROOT/name)==value,path=name,sha256=sha(ROOT/name),expectedSha256=value)
    binding={str(path.relative_to(ROOT)):frozen,**manifest['inputs']}
    foreground,foreground_rows,foreground_inputs=actual_foreground_contract(manifest)
    rows.extend(foreground_rows);binding.update(foreground_inputs)
    if manifest.get('actualArtForeground',{}).get('schema')=='fullbody-actual-foreground/v4':
        pipe_rows,pipe_inputs=complete_pipe_material_contract(manifest)
        rows.extend(pipe_rows);binding.update(pipe_inputs)
    display_image=None
    if manifest.get('displayAlphaContract'):
        continuity_rows,continuity_inputs=fourth_display_continuity(manifest)
        rows.extend(continuity_rows);binding.update(continuity_inputs)
        display_image,display_rows,display_inputs=display_alpha_contract(manifest,foreground)
        rows.extend(display_rows);binding.update(display_inputs)
    baseline_path=OUT/'third-repair/logical-baseline.json'
    if foreground is not None:
        baseline_edges={e['id']:e for e in read(baseline_path)['edges']};binding[str(baseline_path.relative_to(ROOT))]=sha(baseline_path)
        fields=['id','a','b','system','widthSource','sourceSampleSha256','routeEdited','protectedForegroundIntervals']
        check('third repair keeps all 202 logical edges and original 135 depth intervals',
              len(manifest['edges'])==202 and sum(len(e['protectedForegroundIntervals'])for e in manifest['edges'])==135 and
              all({k:e[k]for k in fields}==baseline_edges[e['id']]for e in manifest['edges']))
    check('runtime complete resource identity',set(complete_assets)=={s['resource']for s in specs}and
          sha(ROOT/quiet['registeredPNG'])==quiet['registeredPNGSha256'],
          compiledAssetCount=len(assets),registeredBackgroundCount=1,runtimeAssetCount=len(specs),
          quietBackgroundContractSha256=sha(quiet_path))
    orgassets=[a for a in manifest['assets']if a['role']=='organ']
    check('twelve complete unique organ floors',len(orgassets)==12 and {a['organId']for a in orgassets}==set(ORGANS))
    for spec in specs:
        a=complete_assets.get(spec['resource'],{});p=ROOT/'assets'/spec['resource']
        with Image.open(p)as image:
            size=list(image.size);rgba=np.asarray(image.convert('RGBA'))
        check('asset:'+spec['id'],size==spec['pixelSize']==a.get('pixelSize')and
              sha(p)==a.get('sha256')and spec['sourceBox']==a.get('sourceBox')and
              spec.get('coreBox')==a.get('coreBox'),path=str(p.relative_to(ROOT)),sha256=sha(p),pixelSize=size)
        binding[str(p.relative_to(ROOT))]=sha(p)
        if spec['layer']=='quietBase':
            continue
        if spec['layer']=='foregroundPatches'and spec['id']==NARROW_MOUTH_LIP_ID:
            lip_rows,lip_bindings=narrow_mouth_lip_contract(spec,a,manifest,rgba)
            rows.extend(lip_rows);binding.update(lip_bindings);continue
        if spec['layer']=='foregroundPatches':
            assert foreground is not None,'foreground patch requires independent geometry'
            accepted_mask_path=ROOT/a['acceptedMaskPath']
            with Image.open(accepted_mask_path)as image:
                mask_mode=image.mode;accepted_mask=np.asarray(image)
            independent_mask=display_registered_alpha(display_image,manifest['displayAlphaContract'],spec['sourceBox'],size)if display_image is not None else visual_geometry_mask(foreground,spec['sourceBox'],size)
            binding[a['acceptedMaskPath']]=sha(accepted_mask_path)
            raw_path=ROOT/a['rawPath'];binding[a['rawPath']]=sha(raw_path)
            guide=read(ROOT/manifest['actualArtForeground']['guideContractPath'])
            expected_patch=next((p for p in guide['patches']if p['id']==spec['id']),None)
            check('foreground registered GPT source:'+spec['id'],expected_patch is not None and
                  expected_patch['sourceBox']==spec['sourceBox']==spec.get('coreBox')and
                  sha(raw_path)==a['rawSha256']and a['geometrySvgSha256']==manifest['actualArtForeground']['geometrySvgSha256']and
                  a.get('collisionEdited')is False and a.get('alphaBlend')is False,
                  rawPath=a['rawPath'],rawSha256=sha(raw_path),sourceBox=spec['sourceBox'])
            sx,sy=size[0]/(spec['sourceBox'][2]-spec['sourceBox'][0]),size[1]/(spec['sourceBox'][3]-spec['sourceBox'][1])
            check('foreground full alpha shares independent source lip:'+spec['id'],
                  mask_mode=='L'and accepted_mask.shape==rgba.shape[:2]and
                  np.array_equal(accepted_mask,independent_mask)and
                  np.array_equal(rgba[:,:,3],independent_mask)and
                  sha(accepted_mask_path)==a['acceptedMaskSha256']and min(sx,sy)>=16,
                  storedMaskMode=mask_mode,effectiveSourcePixelDensity=[sx,sy],
                  alphaMismatchPixels=int((rgba[:,:,3]!=independent_mask).sum()),
                  displayEdgeContract='bounded shared display field'if display_image is not None else'exact canonical raster alpha')
            allowed_green=np.zeros(rgba.shape[:2],dtype=bool)
            for organ in ['stomach','liver']:
                gp=atlas.BASE/('stomach-playable/layout.json'if organ=='stomach'else'organ-atlas/geometry/'+organ+'.json')
                allowed_green|=raw_ring_mask(read(gp)['outerRings'],spec['sourceBox'],size)>0
            green=green_candidates(rgba)
            check('foreground green limited to stomach and liver:'+spec['id'],
                  not bool((green&~allowed_green).any()),forbiddenGreenPixels=int((green&~allowed_green).sum()),
                  allowedGreenPixels=int((green&allowed_green).sum()))
            continue
        if spec['layer']!='organs':
            green=int(green_candidates(rgba).sum())
            check('blood-palette:'+spec['id'],green==0,greenPixels=green)
            paper=int(((rgba[:,:,:3]>220).all(axis=2)&(rgba[:,:,3]>0)).sum())
            check('blood-no-GPT-paper-edge:'+spec['id'],paper==0,opaqueOrTranslucentNearWhitePixels=paper)
            if foreground is not None:
                # A sub-source-pixel lip band may blend. True opaque interior
                # is never available to blood, regardless of that filtering.
                protection_geometry=foreground.buffer(-manifest['displayAlphaContract']['maximumSourceBoundaryBand'])if display_image is not None else foreground
                protected=visual_geometry_mask(protection_geometry,spec['sourceBox'],size)
                covered=int(((protected==255)&(rgba[:,:,3]>0)).sum())
                check('blood respects actual-art foreground:'+spec['id'],covered==0,
                      protectedForegroundPixelsCovered=covered)
            continue
        owner=a['organId'];base_path=ROOT/a['basePath'];base=np.asarray(Image.open(base_path).convert('RGBA'))
        mask_path=ROOT/a['replacementMaskPath'];mask=np.asarray(Image.open(mask_path).convert('RGBA'))[:,:,3]
        same_shape=base.shape==rgba.shape and list(base.shape[1::-1])==size
        check('source-registration:'+owner,same_shape and spec['sourceBox']==expected[owner]['sourceBox'],
              sourceBox=spec['sourceBox'],acceptedSourceBox=expected[owner]['sourceBox'],basePath=a['basePath'],baseSha256=sha(base_path))
        assert same_shape,owner
        changed=np.any(base!=rgba,axis=2);outside=int((changed&(mask==0)).sum())
        gp=atlas.BASE/('stomach-playable/layout.json'if owner=='stomach'else'organ-atlas/geometry/'+owner+'.json')
        geometry=read(gp)
        logical_protected=raw_ring_mask(geometry['foodRings'if owner=='stomach'else'foodAirUrineRings'],spec['sourceBox'],size)
        protection_geometry=foreground.buffer(-manifest['displayAlphaContract']['maximumSourceBoundaryBand'])if display_image is not None else foreground
        protected=visual_geometry_mask(protection_geometry,spec['sourceBox'],size)if foreground is not None else logical_protected
        protected_changes=int((changed&(protected==255)).sum())
        logical_changes=int((changed&(logical_protected==255)).sum())
        outer=raw_ring_mask(geometry['outerRings'],spec['sourceBox'],size)
        # Exact floor contour stays an input. Exterior supply tiles may meet a
        # boundary gate, but the organ floor cannot acquire a new silhouette.
        outside_outer_changes=int((changed&(outer==0)).sum())
        outside_pixels=(outer==0)
        premultiplied=np.abs(base[:,:,:3].astype(np.float32)-rgba[:,:,:3].astype(np.float32))*base[:,:,3,None]/255
        outside_premultiplied_max=float(premultiplied[outside_pixels].max())if outside_pixels.any()else 0
        introduced_green=int((green_candidates(rgba)&~green_candidates(base)).sum())
        total_green=int(green_candidates(rgba).sum())
        alpha_changes=int((base[:,:,3]!=rgba[:,:,3]).sum())
        row=check('floor-preservation:'+owner,outside==0 and protected_changes==0 and outside_premultiplied_max<=1 and alpha_changes==0 and
                  (owner in ['stomach','liver']or total_green==0),
                  organId=owner,changedPixels=int(changed.sum()),changedOutsideReplacementMask=outside,
                  changedProtectedLumenPixels=protected_changes,changedOutsideFrozenContourPixels=outside_outer_changes,
                  protectedPixelContract='opaque canonical core outside permitted display AA band'if display_image is not None else'actual accepted artwork foreground'if foreground is not None else'frozen abstract reserved lumen',
                  logicalReservedArtworkPixelsChanged=logical_changes,
                  outsideFrozenContourPremultipliedRgbMax8bit=outside_premultiplied_max,
                  contourRasterTolerance='Alpha exact; at most one 8-bit composited color quantum outside independently rasterized raw outline.',
                  introducedGreenPixels=introduced_green,visibleGreenPixels=total_green,
                  replacementMaskPath=a['replacementMaskPath'],replacementMaskSha256=sha(mask_path),
                  acceptedFloorSha256=sha(base_path),outputSha256=sha(p),geometrySha256=sha(gp),
                  actualAlphaChanges=alpha_changes)
        organ_rows.append(row)
    final=read(atlas.BASE/'final-reference-data.json');edges={e['id']:e for e in final['edges']}
    check('all 202 unique frozen edges',len(manifest['edges'])==202 and len(edges)==202 and
          {e['id']for e in manifest['edges']}==set(edges))
    from shapely.geometry import Polygon,LineString
    from shapely.ops import unary_union
    bladder=read(atlas.BASE/'organ-atlas/geometry/bladder.json')
    urine=unary_union([Polygon(p['outer'],p.get('holes',[]))for p in bladder['foodAirUrineRings']])
    pancreas=read(atlas.BASE/'organ-atlas/geometry/pancreas.json')
    duct=unary_union([Polygon(p['outer'],p.get('holes',[]))for p in pancreas['foodAirUrineRings']])
    for e in manifest['edges']:
        f=edges[e['id']];sample_sha=hashlib.sha256(json.dumps(f['samples'],separators=(',',':')).encode()).hexdigest()
        covered=bool(e.get('assets'))and all(x in assets for x in e['assets'])
        hidden=False;unprotected_length=None;unprotected_area=None;full_width_length=None
        if not covered and e['id']in ['e143','e126']:
            protected=foreground if foreground is not None else urine if e['id']=='e143'else duct
            line=LineString(f['samples'])
            unprotected_length=line.difference(protected).length
            unprotected_area=line.buffer(f['lumenWidthSource']/2,cap_style=2,quad_segs=8).difference(protected).area
            full_width_length=line.difference(protected.buffer(f['lumenWidthSource']/2)).length
            # Independently confirm that no full-width visible tube survives.
            # These two exchanges keep their original gameplay geometry below
            # their named foreground; no other omitted edge gets an exception.
            hidden=(full_width_length<1e-6 and e.get('visibilityStatus')=='fully-foreground-occluded'and
                    bool(e.get('visualForegroundIntervals'if foreground is not None else'protectedForegroundIntervals')))
        edge_rows.append(check('edge:'+e['id'],e['a']==f['a']and e['b']==f['b']and e['system']==f['system']and
                               e['widthSource']==f['lumenWidthSource']and e['sourceSampleSha256']==sample_sha and
                               not e.get('routeEdited')and (covered and e.get('covered')or hidden),
                               edgeId=e['id'],sourceSampleSha256=sample_sha,widthSource=e['widthSource'],assets=e['assets'],
                               visibleMaterialCovered=covered,fullyProtectedHiddenEdge=hidden,
                               unprotectedCenterlineLengthSource=unprotected_length,unprotectedFootprintAreaSource=unprotected_area,
                               fullWidthUnprotectedCenterlineLengthSource=full_width_length))
    check('frozen accepted source files remain byte-identical',freeze_check()['unchanged'])
    fourth=manifest.get('actualArtForeground',{}).get('schema')=='fullbody-actual-foreground/v4'
    expected_junctions={p['id']for p in read(ROOT/manifest['actualArtForeground']['guideContractPath'])['patches']}if fourth else None
    check('all accepted GPT junction regions actually applied',
          (len(manifest['junctions'])==9 and {j['id']for j in manifest['junctions']}==expected_junctions if fourth else len(manifest['junctions'])==7)and
          all(j.get('applied')and j.get('paintedPixelCount',0)>0 for j in manifest['junctions']),
          junctionRegions=[{'id':j['id'],'paintedPixelCount':j.get('paintedPixelCount'),
                            'sha256':j.get('sha256')}for j in manifest['junctions']])
    if fourth:
        foreground_assets=[a for a in manifest['assets']if a['role']=='foreground']
        check('all nine matching foreground lips are in atomic runtime pack',
              len(foreground_assets)==len(expected_junctions)+(NARROW_MOUTH_LIP_ID in assets) and
              {a['id']for a in foreground_assets}==expected_junctions|({NARROW_MOUTH_LIP_ID}if NARROW_MOUTH_LIP_ID in assets else set())and
              {s['id']for s in specs if s['layer']=='foregroundPatches'}=={a['id']for a in foreground_assets})
    changed_inputs=[p for p,h in binding.items()if sha(ROOT/p)!=h]
    changed=bool(changed_inputs)
    result={'schema':'fullbody-015-independent-pixel-qa/v1','nativeEvidence':False,
            'status':'UNDETERMINED_INPUT_CHANGED'if changed else'PASS'if all(r['status']=='PASS'for r in rows)else'FAIL',
            'manifestPath':str(path.relative_to(ROOT)),'manifestSha256':frozen,'runtimeDataSha256':sha(ROOT/'scripts/war/FullBodyMapArtData.lua'),
            'passed':sum(r['status']=='PASS'for r in rows),'total':len(rows),'rows':rows,'organs':organ_rows,'edges':edge_rows,
            'inputHashes':binding,'changedDuringChecks':changed_inputs,
            'allOriginalFloorsUnmodified':freeze_check()['unchanged'],
            'limits':['Pixels are compared independently against accepted whole-organ floors and explicit frozen masks; generation never defines path or collision.',
                      'Native filtering, foreign deep vessel occlusion of units and performance require separate actual native review.']}
    write(OUT/'pixel-report.json',result);print('Pixels',result['status'],result['passed'],'/',result['total'],flush=True);return result


RESOURCE_LUA=r'''
package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={}
NVG_IMAGE_GENERATE_MIPMAPS=1
local A=require('war.FullBodyMapArt');world={};ui={};live={}
serial,created,deleted,dimensionQueries,draws,coreClips=0,0,0,0,0,0
missing=false;badDecode=false;failureValue=0
function nvgCreateImage(vg,path,flags)
 created=created+1;if missing==path then return failureValue end
 serial=serial+1;local size=sizes[path]
 live[serial]={vg=vg,path=path,width=badDecode and 16 or size[1],height=badDecode and 16 or size[2]}
 return serial
end
function nvgImageSize(vg,id)dimensionQueries=dimensionQueries+1;local h=live[id];assert(h and h.vg==vg);return h.width,h.height end
function nvgDeleteImage(vg,id)assert(live[id]and live[id].vg==vg);live[id]=nil;deleted=deleted+1 end
for _,name in ipairs({'nvgSave','nvgRestore','nvgBeginPath','nvgRect','nvgFillPaint','nvgScissor','nvgIntersectScissor','nvgTranslate','nvgScale','nvgTransform','nvgShapeAntiAlias','nvgMoveTo','nvgLineTo','nvgClosePath','nvgPathWinding'})do _G[name]=function()end end
function nvgIntersectScissor(vg,x,y,w,h)assert(w>0 and h>0);coreClips=coreClips+1 end
function nvgImagePattern(vg,x,y,w,h,angle,id,alpha)assert(live[id]and live[id].vg==vg);return{}end
function nvgFill()draws=draws+1 end
R={vg=world,project=function(g,x,y)return x*32*g.zoom,y*32*g.zoom end}
full={anatomyVersion=4,fullbodyBattlefieldVersion=1};game={state=full,zoom=.15,realTime=1.92}
rows={};function check(name,pass)rows[#rows+1]={name=name,pass=not not pass}end
local function count()local n=0;for _ in pairs(live)do n=n+1 end;return n end
'''


RESOURCE_LUA += "\nlocal function copy(t)local out={};for k,v in pairs(t)do out[k]=type(v)=='table'and copy(v)or v end;return out end\nmatrix={1,0,0,1,0,0};clipList={};contextStack={};fillPaint=nil;clipFailures={};fillCounts={}\nfunction nvgSave(vg)contextStack[#contextStack+1]={matrix=copy(matrix),clips=copy(clipList),paint=fillPaint}end\nfunction nvgRestore(vg)local s=table.remove(contextStack);assert(s);matrix=s.matrix;clipList=s.clips;fillPaint=s.paint end\nlocal function multiply(a,b,c,d,e,f)\n local m=matrix;matrix={m[1]*a+m[3]*b,m[2]*a+m[4]*b,m[1]*c+m[3]*d,m[2]*c+m[4]*d,m[1]*e+m[3]*f+m[5],m[2]*e+m[4]*f+m[6]}\nend\nfunction nvgTranslate(vg,x,y)multiply(1,0,0,1,x,y)end\nfunction nvgScale(vg,x,y)multiply(x,0,0,y,0,0)end\nfunction nvgTransform(vg,...)multiply(...)end\nlocal function forward(x,y)local m=matrix;return m[1]*x+m[3]*y+m[5],m[2]*x+m[4]*y+m[6]end\nfunction nvgIntersectScissor(vg,x,y,w,h)\n assert(w>0 and h>0);coreClips=coreClips+1\n local a,b=forward(x,y);local c,d=forward(x+w,y+h);clipList[#clipList+1]={a,b,c-a,d-b}\nend\nfunction nvgImagePattern(vg,x,y,w,h,angle,id,alpha)assert(live[id]and live[id].vg==vg);return{id=id,alpha=alpha}end\nfunction nvgFillPaint(vg,paint)fillPaint=paint end\nfunction nvgFill(vg)\n draws=draws+1;assert(fillPaint and live[fillPaint.id]);local r=live[fillPaint.id].path;fillCounts[r]=(fillCounts[r]or 0)+1\n local c=specsByResource[r].coreBox;if not c then return end\n local x,y=R.project(game,c[1]*2,c[2]*2+512);local s=64*game.zoom;local expected={x,y,(c[3]-c[1])*s,(c[4]-c[2])*s}\n local found=false\n for _,actual in ipairs(clipList)do local equal=true;for i=1,4 do if math.abs(actual[i]-expected[i])>1e-7 then equal=false end end;if equal then found=true end end\n if not found then clipFailures[#clipFailures+1]={resource=r,actual=copy(clipList),expected=expected}end\nend\n\nfunction allCorePaintsQualified(minimum)\n if #clipFailures>0 then return false end\n for resource,spec in pairs(specsByResource)do\n  if spec.coreBox and (fillCounts[resource]or 0)<minimum then return false end\n end\n return true\nend\n"


def resource_case(specs,action):
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.globals().sizes=gastric.lua_table(lua,{s['resource']:s['pixelSize']for s in specs})
    lua.globals().specCount=len(specs)
    lua.globals().specsByResource=gastric.lua_table(lua,{s['resource']:s for s in specs})
    lua.globals().coreSpecCount=sum(bool(s.get('coreBox'))for s in specs)
    lua.globals().quietResource=next((s['resource']for s in specs if s['layer']=='quietBase'),None)
    lua.execute(RESOURCE_LUA+action)
    return gastric.convert(lua.globals().rows)


def resources():
    data,declared_specs=asset_specs();data,specs=effective_asset_specs();before=hashes(['FullBodyMapArt','FullBodyMapArtData','HeartVisualData','HeartArt','HeartDisplayTransform','HeartBattlefieldData','BowelVisual','BowelVisualData','BowelBattlefieldData'])
    manifest_path=DOC/'bake/manifest.json';manifest_hash=sha(manifest_path)
    before[str(manifest_path.relative_to(ROOT))]=manifest_hash
    files=[];bytes_rgba=0
    for spec in specs:
        path=ROOT/'assets'/spec['resource'];image=Image.open(path)
        assert list(image.size)==spec['pixelSize'],spec['id'];image.verify()
        box=spec['sourceBox'];assert len(box)==4 and box[2]>box[0]and box[3]>box[1]
        # A sparse tile crop can be smaller than its canonical grid core; its
        # filter gutter may extend beyond that core. Require a real intersection,
        # not containment in either direction, then clip in the production draw.
        core=spec.get('coreBox');assert not core or max(box[0],core[0])<min(box[2],core[2])and max(box[1],core[1])<min(box[3],core[3])
        bytes_rgba+=spec['pixelSize'][0]*spec['pixelSize'][1]*4
        files.append({'id':spec['id'],'layer':spec['layer'],'resource':spec['resource'],
                      'sha256':sha(path),'pixelSize':spec['pixelSize'],'sourceBox':box,'coreBox':core})
        before[str(path.relative_to(ROOT))]=sha(path)
    rows=[]
    declared=data.get('resourceBudget')
    if declared:
        rows.extend([
            {'name':'exported per-context caps match explicit 42 baseline or43 narrowlip and288MiB',
             'pass':declared['maxResourceSpecsPerContext']==(43 if any(s['id']==NARROW_MOUTH_LIP_ID for s in specs)else 42) and declared['maxDecodedRGBABytesPerContext']==301989888},
            {'name':'actual candidate spec count including foreground fits declared cap',
             'pass':len(specs)<=declared['maxResourceSpecsPerContext']},
            {'name':'actual decoded dimensions including foreground fit declared cap',
             'pass':bytes_rgba<=declared['maxDecodedRGBABytesPerContext']},
            {'name':'exported declared totals remain truthful and effective atlas size stays bounded',
             'pass':declared['resourceSpecsPerContext']==len(specs) and declared['decodedRGBABytesPerContext']==sum(s['pixelSize'][0]*s['pixelSize'][1]*4 for s in declared_specs)}])
    rows+=resource_case(specs,r'''
A.prepare(world);A.prepare(ui)
check('two independent contexts have dedicated pack handles',count()==2*specCount)
local n=created;A.prepare(world);A.prepare(ui);check('prepare caches handles',created==n)
check('whole pack decoded in both contexts',A.ready(world,full)and A.ready(ui,full))
if quietResource then
 local a,b=A.background(world,full),A.background(ui,full)
 check('registered GPT background has context-local handles',a and b and a~=b and live[a].vg==world and live[b].vg==ui and
  live[a].path==quietResource and live[b].path==quietResource)
end
local queries=dimensionQueries
for _=1,40 do A.ready(world,full);A.ready(ui,full);A.draw(R,game,full,0,2048,512,3584)end
check('decoded pack dimensions inspected once',dimensionQueries==queries)
check('draw never uploads resources',created==n)
check('every observed core-tile fill has its exact transformed fixed core clip',allCorePaintsQualified(40))
check('old anatomy is disabled',not A.ready(world,{anatomyVersion=3,fullbodyBattlefieldVersion=1}))
check('normal sandbox disabled',not A.ready(world,{anatomyVersion=4}))
check('old organ trial disabled',not A.ready(world,{anatomyVersion=4,organBattlefieldVersion=1}))
check('low zoom alpha reaches zero',A.alpha(.085)==0)
check('true .15 alpha reaches one',math.abs(A.alpha(.15)-1)<1e-12)
for _=1,25 do A.release(ui);A.prepare(ui);check('reopen pack count remains bounded',count()==2*specCount)end
A.release(world);A.release(world);check('world release preserves UI context',count()==specCount and A.ready(ui,full))
A.release(ui);A.release(ui);check('all pack handles released',count()==0)
''')
    rows+=resource_case(specs,r'''
badDecode=true;A.prepare(world);A.prepare(ui)
check('positive 16x16 DWP placeholders reject atomic pack',not A.ready(world,full)and not A.ready(ui,full))
local n=draws;check('placeholder draw keeps complete static fallback',not A.draw(R,game,full,0,2048,512,3584)and draws==n)
if quietResource then check('placeholder pack exposes no partial GPT background',A.background(world,full)==nil)end
for _,h in pairs(live)do if h.vg==world then local s=sizes[h.path];h.width,h.height=s[1],s[2]end end
check('world readiness does not activate UI resources',A.ready(world,full)and not A.ready(ui,full))
A.release(world);A.release(ui);check('placeholder handles release',count()==0)
''')
    for spec in specs:
        for failure in ['nil','0','-1']:
            action='missing='+json.dumps(spec['resource'])+';failureValue='+failure+'\n'+r'''
A.prepare(world);check('one missing tile disables complete pack',not A.ready(world,full))
local n=draws;check('missing tile does not draw partial organs',not A.draw(R,game,full,0,2048,512,3584)and draws==n)
if quietResource then check('missing asset exposes no partial GPT background',A.background(world,full)==nil)end
local c=created;for _=1,12 do A.prepare(world);A.draw(R,game,full,0,2048,512,3584)end
check('missing tile has no per-frame upload/retry',created==c)
A.release(world);A.release(world);check('partial pack success handles release',count()==0)
missing=false;A.prepare(world);check('explicit lifecycle restart can recover',A.ready(world,full))
A.release(world);check('recovered pack releases',count()==0)
'''
            result=resource_case(specs,action)
            rows.extend([{**r,'assetId':spec['id'],'failureValue':failure}for r in result])
    changed=[p for p,h in before.items()if sha(ROOT/p)!=h]
    result={'schema':'fullbody-015-resource-qa/v1','nativeEvidence':False,
            'status':'UNDETERMINED_INPUT_CHANGED'if changed else'PASS'if all(r['pass']for r in rows)else'FAIL','passed':sum(r['pass']for r in rows),
            'total':len(rows),'rows':rows,'assets':files,'inputHashes':before,
            'changedDuringChecks':changed,
            'texturesPerContext':len(specs),'dualContextHandlesPeak':len(specs)*2,
            'manifestSha256':manifest_hash,
            'handlesAfterRelease':0,'baseRgbaBytesPerContext':bytes_rgba,
            'declaredResourceBudget':declared,'legacyBudgetAbsent':declared is None,
            'estimatedDualContextBaseRgbaBytes':bytes_rgba*2,'reopenCycles':25,
            'limits':['RGBA estimate excludes mipmaps, duplicate driver storage, decoded CPU surfaces and other game resources.',
                      'Controlled NanoVG handle/dimension APIs certify lifetime behavior; native GPU memory and P95 remain unmeasured.']}
    write(OUT/'resource-report.json',result);print('Resources',result['status'],result['passed'],'/',result['total'],flush=True);return result


def quiet_base():
    path=DOC/'quiet-base/report.json';meta=read(path);frozen=sha(path)
    binding={str(path.relative_to(ROOT)):frozen,**meta['inputs'],**meta['outputs']}
    contract_path=DOC/'quiet-base/visual-protection-v2.json';contract=read(contract_path)
    binding[str(contract_path.relative_to(ROOT))]=sha(contract_path)
    binding.update(contract['inputs'])
    for item in contract['organMasks']:
        binding[item['alphaMaskPath']]=item['alphaMaskSha256']
    binding.update(hashes(['ReferenceArt','FullBodyBaseFillData','FullBodyMapArt','FullBodyMapArtData']))
    rows=[]
    def check(name,passed,**facts):rows.append({'id':name,'status':'PASS'if passed else'FAIL',**facts})
    for name,value in {**meta['inputs'],**meta['outputs']}.items():
        check('hash:'+name,sha(ROOT/name)==value,sha256=sha(ROOT/name),expectedSha256=value)
    original=np.asarray(Image.open(ROOT/'assets/image/anatomy-reference/reference.png').convert('RGBA'))
    output_path=ROOT/contract['registeredPNG']
    registered=np.asarray(Image.open(output_path).convert('RGBA'));changed=np.any(original!=registered,axis=2)
    check('full source registration',original.shape==registered.shape==(1536,1024,4)and meta['sourceBox']==[0,0,1024,1536])
    applied=np.asarray(Image.open(DOC/'quiet-base/applied-mask.png').convert('L'))>0
    check('changes stay inside explicit frozen mask',not bool((changed&~applied).any()),
          changedOutsideMask=int((changed&~applied).sum()),selectedPixels=int(applied.sum()))
    mask_root=ROOT/'assets/image/anatomy-reference/vascular-study/fullbody-015/masks'
    check('registered PNG matches explicit visual contract',sha(output_path)==contract['registeredPNGSha256'])
    check('all twelve independent accepted alpha masks',sorted(item['id']for item in contract['organMasks'])==sorted(ORGANS))
    art={o['organId']:o for o in read(atlas.BASE/'organ-atlas/art.json')['organs']}
    alpha_union=np.zeros((1536,1024),dtype=np.uint8)
    for item in contract['organMasks']:
        owner=item['id'];accepted_path=ROOT/item['acceptedBasePath'];accepted=Image.open(accepted_path).convert('RGBA')
        b=item['sourceBox'];sx,sy=accepted.width/(b[2]-b[0]),accepted.height/(b[3]-b[1])
        expected=np.asarray(accepted.getchannel('A').transform((1024,1536),Image.Transform.AFFINE,
            (sx,0,-b[0]*sx,0,sy,-b[1]*sy),resample=Image.Resampling.BILINEAR))
        mask_path=ROOT/item['alphaMaskPath'];actual=np.asarray(Image.open(mask_path).convert('L'))
        check('registered accepted alpha:'+owner,np.array_equal(actual,expected)and
              sha(accepted_path)==item['acceptedBaseSha256']and sha(mask_path)==item['alphaMaskSha256']and
              b==art[owner]['sourceBox']and list(accepted.size)==item['sourcePixelSize']and
              item['opaqueProtectionThreshold']==254,organId=owner,opaqueSourcePixels=int((expected>=254).sum()))
        n=int((changed&(expected>=254)).sum());check('actual opaque organ unchanged:'+owner,n==0,organId=owner,changedPixels=n)
        alpha_union=np.maximum(alpha_union,expected)
    actual_union=np.asarray(Image.open(ROOT/contract['actualOrganAlpha']['path']).convert('L'))
    check('actual organ union derived from frozen accepted artwork',np.array_equal(alpha_union,actual_union)and
          sha(ROOT/contract['actualOrganAlpha']['path'])==contract['actualOrganAlpha']['sha256'])
    interior=np.asarray(Image.open(mask_root/'body-interior-with-2px-guard.png').convert('L'))>0
    check('outer contour guard unchanged',not bool((changed&~interior).any()),changedPixels=int((changed&~interior).sum()))
    rgb=original[:,:,:3].astype(np.int16)
    bones=((rgb[:,:,0]>180)&(rgb[:,:,1]>170)&(rgb[:,:,0]>=rgb[:,:,1])&(rgb[:,:,1]>=rgb[:,:,2])&
           (rgb[:,:,0]-rgb[:,:,1]<30)&(rgb[:,:,1]-rgb[:,:,2]<75))
    check('source cream bones and joints unchanged',not bool((changed&bones).any()),changedPixels=int((changed&bones).sum()))
    check('accepted source alpha exact',np.array_equal(original[:,:,3],registered[:,:,3]))
    generated_path=next(ROOT/p for p in meta['inputs']if p.endswith('gpt-quiet-body-underlay-v2.png'))
    generated=np.asarray(Image.open(generated_path).convert('RGB')).astype(np.int16)
    abstract=np.asarray(Image.open(mask_root/'protected-foreground.png').convert('L'))>0
    old_blood=((rgb[:,:,2]-rgb[:,:,0]>16)&(rgb[:,:,2]-rgb[:,:,1]>-5))|\
              ((rgb[:,:,0]>100)&(rgb[:,:,0]-rgb[:,:,1]>45)&(rgb[:,:,0]-rgb[:,:,2]>40))
    actual_foreground=abstract&(np.max(np.abs(rgb-generated),axis=2)<=24)&~old_blood
    declared_foreground=np.asarray(Image.open(ROOT/contract['actualVisibleForeground']['path']).convert('L'))>0
    check('visible foreground derives from frozen source and GPT pair',np.array_equal(actual_foreground,declared_foreground)and
          sha(ROOT/contract['actualVisibleForeground']['path'])==contract['actualVisibleForeground']['sha256'])
    check('actual visible food air urine foreground unchanged',not bool((changed&actual_foreground).any()),
          changedPixels=int((changed&actual_foreground).sum()))
    expected_mask=interior&~(alpha_union>=254)&~actual_foreground&~bones
    check('background mask equals declared visual domains',np.array_equal(applied,expected_mask)and
          meta['scope']=='guarded-interior'and int(applied.sum())==meta['selectedPixels'])
    from scipy.ndimage import distance_transform_edt
    alpha=np.minimum(distance_transform_edt(expected_mask)/meta['featherSourcePixels'],1.0)*expected_mask
    expected_rgb=np.round(rgb*(1-alpha[:,:,None])+generated*alpha[:,:,None]).astype(np.uint8)
    declared_alpha=np.asarray(Image.open(DOC/'quiet-base/applied-alpha.png').convert('L'))
    check('registered pixels match constrained feather composition',np.array_equal(expected_rgb,registered[:,:,:3])and
          np.array_equal(np.round(alpha*255).astype(np.uint8),declared_alpha))
    abstract_changes=int((changed&abstract).sum())
    check('abstract route buffer edits are explicit and coordinates frozen',
          abstract_changes==meta['abstractReservedPixelsChanged']and meta['abstractReservedCoordinatesChanged']is False,
          changedArtworkPixels=abstract_changes,reason='Old vascular pigment in logical route buffers is cleared; collision/underpass domains stay frozen.')
    data,specs=asset_specs();base=data.get('quietBase')
    manifest_path=DOC/'bake/manifest.json';manifest=read(manifest_path)
    binding[str(manifest_path.relative_to(ROOT))]=sha(manifest_path)
    check('registered bitmap is the atomic runtime base',base is not None and
          base['sourceBox']==[0,0,1024,1536]and base['pixelSize']==[1024,1536]and
          ROOT/'assets'/base['resource']==output_path and
          base['sha256']==contract['registeredPNGSha256']and
          len(specs)==len(manifest['assets'])+1 and
          sum(s['layer']=='quietBase'for s in specs)==1,
          compiledAssetCount=len(manifest['assets']),runtimeAssetCount=len(specs))
    lua=gastric.runtime();data=gastric.convert(lua.execute("local d=require('war.FullBodyBaseFillData');return d"))
    regions=data['regions'];points=[p for r in regions for ring in r['paths']for p in ring['points']]
    check('source vector trace has finite declared regions and points',len(regions)==meta['regions']and len(points)==meta['points']and
          all(len(p)==2 and all(math.isfinite(x)for x in p)for p in points),regionCount=len(regions),pointCount=len(points))
    check('frozen navigation and accepted files unchanged',freeze_check()['unchanged'])
    changed_inputs=[p for p,h in binding.items()if sha(ROOT/p)!=h]
    result={'schema':'fullbody-015-quiet-base-independent-qa/v1','nativeEvidence':False,
            'status':'UNDETERMINED_INPUT_CHANGED'if changed_inputs else'PASS'if all(r['status']=='PASS'for r in rows)else'FAIL',
            'passed':sum(r['status']=='PASS'for r in rows),'total':len(rows),'rows':rows,'inputHashes':binding,
            'sourceBox':[0,0,1024,1536],'changedDuringChecks':changed_inputs,
            'manifestSha256':sha(DOC/'bake/manifest.json'),
            'limits':['The fullbody renderer uses the registered bitmap; the retained vector trace is diagnostic only.',
                      'Actual opaque accepted organ pixels, visible matching foreground, source cream bones and the outer guard are retained exactly.',
                      'Abstract reserved routes retain their frozen coordinates while old vascular pigment can be cleared inside them; navigation and unit-depth checks bind that geometry separately.']}
    write(OUT/'quiet-base-report.json',result);print('Quiet base',result['status'],result['passed'],'/',result['total'],flush=True);return result


def visibility():
    """Check display underpasses against the original sampled graph, not paint."""
    from shapely.geometry import LineString,Point
    path=DOC/'bake/manifest.json';manifest=read(path);frozen=sha(path)
    graph=read(GRAPH);edges={e['id']:e for e in graph['edges']}
    data,_=asset_specs();uses_visual=any('visualForegroundIntervals'in e for e in manifest['edges'])
    depth_field='visualForegroundIntervals'if uses_visual else'protectedForegroundIntervals'
    expected={e['id']:e.get(depth_field,[])for e in manifest['edges']if e.get(depth_field)}
    binding=hashes(['FullBodyMapArt','FullBodyMapArtData','FullBodyBattlefield','World','Vessels','Save'])
    binding[str(path.relative_to(ROOT))]=frozen;binding[str(GRAPH.relative_to(ROOT))]=sha(GRAPH)
    lua=gastric.runtime();lua.execute(r'''
      QA=require('war.FullBodyMapArt');QS=require('war.FullBodyBattlefield').new(702)
      QSave=require('war.Save');QU=require('war.Util');QN=require('war.World').vessels(QS)
      QBefore=QSave.snapshot(QS);QSeen=QU.copy(QS.factions[1].visible)
      function qsame(a,b)
       if type(a)~=type(b)then return false end;if type(a)~='table'then return a==b end
       for k,v in pairs(a)do if not qsame(v,b[k])then return false end end
       for k in pairs(b)do if a[k]==nil then return false end end;return true
      end
      function qdepth(lane,x,y,kind,mode)
       local state=QS
       if mode=='old' then state={anatomyVersion=4,terrainStyle='body-v4'}
       elseif mode=='trial' then state={anatomyVersion=4,organBattlefieldVersion=1,terrainStyle='body-v4'}
       elseif mode=='old-anatomy' then state={anatomyVersion=3,fullbodyBattlefieldVersion=1,terrainStyle='body-v4'}end
       return QA.unitDepth(state,{kind=kind,vesselLane=lane},x,y)
      end
    ''')
    net=gastric.convert(lua.eval('QN.edges'));by_name={e['name']:e for e in net}
    rows=[];samples=[]
    def check(name,passed,**facts):
        rows.append({'id':name,'status':'PASS'if passed else'FAIL',**facts})
    check('runtime underpass table equals current manifest',data.get('visibility')==expected)
    visual_mask=None;visual_geometry=None;hidden_above_open_floor=[]
    if uses_visual:
        baseline_path=OUT/'third-repair/logical-baseline.json';baseline=read(baseline_path)
        binding[str(baseline_path.relative_to(ROOT))]=sha(baseline_path)
        logical={e['id']:e['protectedForegroundIntervals']for e in manifest['edges']if e['protectedForegroundIntervals']}
        baseline_logical={e['id']:e['protectedForegroundIntervals']for e in baseline['edges']if e['protectedForegroundIntervals']}
        check('all 202 visual interval fields explicit',len(manifest['edges'])==202 and
              all('visualForegroundIntervals'in e for e in manifest['edges']))
        check('original 135 logical depth intervals byte-value unchanged',logical==baseline_logical and
              sum(len(v)for v in logical.values())==135)
        check('runtime separates visual and logical audit tables',data.get('visualVisibilityVersion')==1 and
              data.get('logicalVisibility')==baseline_logical)
        contract=manifest['actualArtForeground'];cp=foreground_contract_path(manifest)
        binding[str(cp.relative_to(ROOT))]=sha(cp);binding[contract['path']]=sha(ROOT/contract['path'])
        check('visibility binds independently authored foreground',read(cp)==contract and
              sha(ROOT/contract['path'])==contract['sha256'])
        visual_mask=np.asarray(Image.open(ROOT/contract['path']).convert('L'))
        visual_geometry,art_rows,art_inputs=actual_foreground_contract(manifest)
        rows.extend(art_rows);binding.update(art_inputs)
        if manifest.get('displayAlphaContract'):
            continuity_rows,continuity_inputs=fourth_display_continuity(manifest)
            rows.extend(continuity_rows);binding.update(continuity_inputs)
    check('exactly 202 runtime edges',len(by_name)==202 and set(by_name)==set(edges))
    count=0
    for eid,frozen_edge in edges.items():
        runtime_edge=by_name[eid];line=LineString(frozen_edge['samples'])
        points=np.asarray(runtime_edge['points'],dtype=float)
        source=np.column_stack((points[:,0]/2,(points[:,1]-512)/2))
        error=float(np.abs(source-np.asarray(frozen_edge['samples'],dtype=float)).max())
        check('source-curve:'+eid,source.shape==np.asarray(frozen_edge['samples']).shape and error<1e-9,
              edgeId=eid,maxSourceCoordinateError=error,curved=bool(runtime_edge.get('curved')))
        intervals=expected.get(eid,[]);ordered=sorted(intervals,key=lambda i:i['startDistance'])
        if visual_geometry is not None:
            def line_parts(g):
                if g.geom_type=='LineString':return[g]if g.length>1e-6 else[]
                return[p for part in getattr(g,'geoms',[])for p in line_parts(part)]
            independent=[]
            for part in line_parts(line.intersection(visual_geometry.buffer(.025))):
                a,b=sorted([line.project(Point(part.coords[0])),line.project(Point(part.coords[-1]))])
                if b-a>1e-5:independent.append((a,b))
            independent.sort()
            differences=[max(abs(a-i['startDistance']),abs(b-i['endDistance']))
                         for (a,b),i in zip(independent,ordered)]
            check('visual intervals match actual foreground geometry:'+eid,
                  len(independent)==len(ordered)and all(error<1e-8 for error in differences),
                  edgeId=eid,independentIntervalCount=len(independent),declaredIntervalCount=len(ordered),
                  maxSourceDistanceError=max(differences,default=0))
        previous=-1
        for index,interval in enumerate(ordered):
            count+=1;a,b=interval['startDistance'],interval['endDistance']
            endpoint_error=max(Point(interval['sourceStart']).distance(line.interpolate(a)),
                               Point(interval['sourceEnd']).distance(line.interpolate(b)))
            check(f'interval:{eid}:{index}',0<=a<b<=line.length+1e-8 and a>=previous-1e-8 and
                  endpoint_error<1e-8 and interval.get('unitDepth')=='under-foreground'and
                  interval.get('connectsToForeground')is False and bool(interval.get('foregroundIds')),
                  edgeId=eid,sourceStartDistance=a,sourceEndDistance=b,
                  endpointSourceError=endpoint_error,foregroundIds=interval.get('foregroundIds'))
            if visual_mask is not None:
                midpoint=line.interpolate((a+b)*.5)
                neighborhood=foreground_neighborhood(visual_mask,contract,midpoint)
                # Geometric depth adds only .025 source-px. Registered
                # neighbouring pixels cover that raster/AA boundary guard;
                # an empty neighbourhood is a definite open-floor mismatch.
                if not neighborhood.size or not bool(neighborhood.max()):
                    hidden_above_open_floor.append({'edgeId':eid,'intervalIndex':index,
                        'source':[midpoint.x,midpoint.y],'startDistance':a,'endDistance':b})
            previous=b
        distances={line.length*.5}
        for i in intervals:
            a,b=i['startDistance'],i['endDistance'];guard=min(.0001,(b-a)*.01)
            distances.update([a,b,(a+b)*.5,max(0,a-guard),min(line.length,a+guard),
                              max(0,b-guard),min(line.length,b+guard)])
        for along in sorted(distances):
            point=line.interpolate(along);x,y=point.x*2,point.y*2+512
            expected_depth='under-foreground'if any(i['startDistance']<=along<=i['endDistance']for i in intervals)else None
            at_boundary=any(abs(along-d)<1e-10 for i in intervals for d in [i['startDistance'],i['endDistance']])
            actual=lua.eval('qdepth')(runtime_edge['id'],x,y,'scout','fullbody')
            # At a mathematically exact mouth, reprojection can differ by a
            # subnanometre source epsilon. Both sides are allowed only at that
            # exact boundary; the 0.0001 source-pixel samples must be strict.
            check(f'depth:{eid}:{along:.12f}',actual==expected_depth or at_boundary,
                  edgeId=eid,sourceDistance=along,expected=expected_depth,actual=actual,
                  exactBoundaryNumericalTolerance=at_boundary)
            samples.append({'edgeId':eid,'sourceDistance':along,'source':[point.x,point.y],
                            'actual':actual,'expected':expected_depth,'exactBoundary':at_boundary})
            check(f'kind-independent:{eid}:{along:.12f}',
                  lua.eval('qdepth')(runtime_edge['id'],x,y,'siege','fullbody')==actual)
            check(f'tissue-visible:{eid}:{along:.12f}',lua.eval('qdepth')(0,x,y,'siege','fullbody')is None)
            for mode in ['old','trial','old-anatomy']:
                check(f'legacy-visible:{eid}:{along:.12f}:{mode}',
                      lua.eval('qdepth')(runtime_edge['id'],x,y,'scout',mode)is None)
        # Calling the display API at the same coordinate does not advance the
        # sample, phase, simulation time, or collision state at any frame rate.
        p=line.interpolate(line.length*.5);values=[]
        for fps in [30,60,120]:
            observed=[lua.eval('qdepth')(runtime_edge['id'],p.x*2,p.y*2+512,'scout','fullbody')for _ in range(fps)]
            values.append(observed)
        check('deterministic:'+eid,all(all(v==values[0][0]for v in observed)for observed in values))
    if uses_visual and contract['schema']=='fullbody-actual-foreground/v4':
        import check_fullbody_foreground_semantics as semantic
        guide=read(ROOT/contract['guideContractPath'])
        for probe in semantic.semantic_depth_probes(graph,bool(guide.get('portalReflectionExclusion'))):
            point=Point(probe['source']);edge=by_name[probe['edgeId']]
            expected_depth='under-foreground'if probe['expectedHidden']else None
            for kind in ['scout','siege']:
                actual=lua.eval('qdepth')(edge['id'],point.x*2,point.y*2+512,kind,'fullbody')
                check(f"independent semantic runtime:{probe['edgeId']}:{probe['sourceDistance']:.8f}:{kind}",
                      actual==expected_depth,**probe,kind=kind,actual=actual,expected=expected_depth)
            gray=foreground_sample(visual_mask,contract,point);has_mask=gray>0
            check(f"independent semantic mask:{probe['edgeId']}:{probe['sourceDistance']:.8f}",
                  has_mask==probe['expectedHidden'],**probe,maskPresent=has_mask,
                  exactRegisteredGray=gray,sampleDomain='exact registered center pixel')
    unchanged=lua.eval('qsame(QBefore,QSave.snapshot(QS))and qsame(QSeen,QS.factions[1].visible)')
    check('all display calls preserve Save RNG positions and enemy visibility',bool(unchanged))
    if uses_visual:
        check('no visual underpass midpoint lies above ordinary open floor',not hidden_above_open_floor,
              hiddenAboveOpenFloorCount=len(hidden_above_open_floor))
    changed=[p for p,h in binding.items()if sha(ROOT/p)!=h]
    result={'schema':'fullbody-015-display-underpass-qa/v1','nativeEvidence':False,
            'status':'UNDETERMINED_INPUT_CHANGED'if changed else'PASS'if all(r['status']=='PASS'for r in rows)else'FAIL',
            'passed':sum(r['status']=='PASS'for r in rows),'total':len(rows),'rows':rows,'samples':samples,
            'edgeCount':len(edges),'protectedIntervalCount':count,'fullyOccludedEdges':data.get('fullyOccludedEdges'),
            'runtimeDepthContract':depth_field,'logicalProtectedIntervalCount':135 if uses_visual else count,
            'hiddenAboveOpenFloor':hidden_above_open_floor,
            'inputHashes':binding,'manifestSha256':frozen,'changedDuringChecks':changed,
            'limits':['Synthetic lane descriptors test only the pure display API; actual movement is recorded separately in the 970-case matrix.',
                      'Exact interval mouths allow either adjacent classification solely for floating point reprojection; every nearby interior/exterior sample is strict.',
                      'Cell glyph suppression, tactical markers and native filtering require production Render/native evidence.']}
    write(OUT/'visibility-report.json',result);print('Visibility',result['status'],result['passed'],'/',result['total'],flush=True);return result


def render(animate=False):
    import body_life_backend as backend
    lua,G=backend.l,backend.G
    _,specs=effective_asset_specs()
    paths={s['resource']:ROOT/'assets'/s['resource']for s in specs}
    binding=hashes(['FullBodyBattlefield','FullBodyMapArt','FullBodyMapArtData','ReferenceArt','FullBodyBaseFillData','Render','View','Save','Commands','Path','Simulation','CellCollision'])
    quiet_path=DOC/'quiet-base/report.json'
    if quiet_path.is_file():
        quiet=read(quiet_path);binding[str(quiet_path.relative_to(ROOT))]=sha(quiet_path)
        binding.update({p:sha(ROOT/p)for p in {**quiet['inputs'],**quiet['outputs']}})
    binding.update({'assets/'+resource:sha(path)for resource,path in paths.items()})
    manifest_path=DOC/'bake/manifest.json';manifest_hash=sha(manifest_path)
    binding[str(manifest_path.relative_to(ROOT))]=manifest_hash
    lua.execute(r'''
      S=require('war.FullBodyBattlefield').new(72026)
      A=require('war.FullBodyMapArt');R=require('war.Render');Save=require('war.Save')
      O=require('war.OrganBattlefield');U=require('war.Util');C=require('war.Commands')
      Sim=require('war.Simulation');W=require('war.World')
      function qaSame(a,b)
       if type(a)~=type(b)then return false end;if type(a)~='table'then return a==b end
       for k,v in pairs(a)do if not qaSame(v,b[k])then return false end end
       for k in pairs(b)do if a[k]==nil then return false end end;return true
      end
      baseline=Save.snapshot(S);visibility=U.copy(S.factions[1].visible)
      worldContext={};uiContext={};R.vg=worldContext;R.font=1
      A.prepare(worldContext);A.prepare(uiContext)
      assert(A.ready(worldContext,S)and A.ready(uiContext,S))
      require('war.Cells').init(worldContext);R.prepare(S)
      function configure(w,h,z,dpr,x,y)
       graphics={GetWidth=function()return w*dpr end,GetHeight=function()return h*dpr end,GetDPR=function()return dpr end}
       game={state=S,zoom=z,camera={x=x,y=y},realTime=1.92,flowTime=S.time,
        selection={},accumulator=0,started=true,fogDisabled=true}
       R.w,R.h=w,h
      end
      function unchanged()
       return qaSame(baseline,Save.snapshot(S))and qaSame(visibility,S.factions[1].visible)
      end
    ''')
    assert lua.eval('A.stats().images')==len(specs)*2
    samples=[]
    for width,height in [(1440,900),(1024,768),(844,390),(430,932),(360,780)]:
        for dpr in [1,2,3]:
            for zoom in [.085,.12,.149,.15,.151]:
                backend.reset();G.qw=width;G.qh=height;G.qz=zoom;G.qdpr=dpr
                lua.execute(r'''
                  configure(qw,qh,qz,qdpr,1016,1512)
                  projectionError=0
                  for _,id in ipairs(O.activeOrgans(S))do
                   for _,gate in ipairs(O.organ(id).gateContracts.siege)do
                    for _,p in ipairs({gate.pipeAnchorSource,gate.tissueAnchorSource})do
                     local wx,wy=p[1]*2,p[2]*2+512;local x,y=R.project(game,wx,wy)
                     local xx,yy=R.unproject(game,x,y)
                     projectionError=math.max(projectionError,math.abs(wx-xx),math.abs(wy-yy))
                     assert(math.abs(x-(qw*.5+(wx-game.camera.x)*32*qz))<1e-8)
                     assert(math.abs(y-(qh*.47+(wy-game.camera.y)*32*qz))<1e-8)
                    end
                   end
                  end
                  assert(projectionError<1e-8);R.draw(game);assert(unchanged())
                ''')
                samples.append({'viewportLogical':[width,height],'dpr':dpr,'zoom':zoom,
                                'projectionError':float(G.projectionError),'saveRngVisibilityUnchanged':True})
    layout=runtime_layout();views=[]
    for owner in ORGANS:
        box=layout[owner]['sourceBox'];views.append((owner,[(box[0]+box[2])/2,(box[1]+box[3])/2]))
        for gate in layout[owner]['gateContracts']['siege']:
            views.append((owner+'-entry-'+gate['id'].replace('.','-'),gate['wallSource']if'wallSource'in gate else gate['tissueAnchorSource']))
    # Peripheral blood domains are included visually even though no new
    # peripheral tissue collision domains are created in this release.
    views += [('neck',[509,210]),('chest-trunks',[509,350]),('abdomen-trunks',[508,610]),
              ('pelvis',[509,782]),('arm-right',[285,590]),('arm-left',[735,590]),
              ('hand-right',[210,794]),('hand-left',[810,794]),('leg-right',[409,1100]),
              ('leg-left',[604,1100]),('foot-right',[367,1430]),('foot-left',[635,1430])]
    frames=[]
    for name,center in views:
        near=[]
        for zoom in ([.149,.15,.151]if name in ORGANS else[.15]):
            backend.reset();G.qx=center[0]*2;G.qy=center[1]*2+512;G.qz=zoom
            lua.execute('configure(1024,768,qz,1,qx,qy);R.draw(game);assert(unchanged())')
            raw=backend.png(1024,768);path=OUT/'render'/f'{name}-z{zoom}.png';path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(raw)
            frames.append({'name':name,'sourceCenter':center,'zoom':zoom,'file':str(path.relative_to(DOC)),
                           'sha256':sha(path),'sizeLogical':[1024,768],'logicalWidth':1024,'logicalHeight':768,'dpr':1,
                           'organId':next((o for o in ORGANS if name==o or name.startswith(o+'-entry-')),None)})
            near.append(np.asarray(Image.open(io.BytesIO(raw)).convert('RGB'),dtype=np.int16))
        if len(near)==3:
            frames[-1]['near015MeanRgbDifferences']=[float(np.abs(a-b).mean())for a,b in zip(near,near[1:])]
        print('Fullbody production Render:',name,flush=True)
    movements=[]
    if animate:
        for source,target in [('liver','stomach'),('brain','bladder')]:
            G.qfrom=source;G.qto=target
            lua.execute(r'''
              S=require('war.FullBodyBattlefield').new(72026);S.entities={};S.commands={};W.rebuild(S)
              local d=O.organ(qfrom);local p=d.profileRooms.scout[1].rallySource
              actor=assert(C.spawn(S,'unit','scout',1,p[1]*2,p[2]*2+512));W.rebuild(S)
              local t=O.organ(qto);targetSource=t.profileRooms and t.profileRooms.scout[1].rallySource or t.rooms[1].centerSource
              targetX,targetY=targetSource[1]*2,targetSource[2]*2+512
              assert(C.execute(S,{kind='move',ids={actor.id},faction=1,x=targetX,y=targetY,lane=0}))
              initialActor={x=actor.x,y=actor.y,lane=actor.vesselLane}
              configure(1024,768,.15,1,actor.x,actor.y);game.selection={[actor.id]=true}
            ''')
            # Determine the route duration through actual production movement,
            # then restart the same command for a complete 15-second timelapse.
            started=time.perf_counter()
            while lua.eval('#actor.orders')>0 and float(G.S.time)<1800 and time.perf_counter()-started<120:
                lua.execute('for _=1,10 do Sim.step(S,.1)end')
            duration=float(G.S.time)
            arrived=lua.eval('#actor.orders==0 and actor.vesselLane==0 and (actor.x-targetX)^2+(actor.y-targetY)^2<=.075^2')
            if not arrived:
                movements.append({'fromOrgan':source,'toOrgan':target,'status':'FAIL_PRODUCTION_MOVEMENT',
                                  'elapsedSimulationSeconds':duration});continue
            lua.execute(r'''
              S=require('war.FullBodyBattlefield').new(72026);S.entities={};S.commands={};W.rebuild(S)
              local p=O.organ(qfrom).profileRooms.scout[1].rallySource
              actor=assert(C.spawn(S,'unit','scout',1,p[1]*2,p[2]*2+512));W.rebuild(S)
              assert(C.execute(S,{kind='move',ids={actor.id},faction=1,x=targetX,y=targetY,lane=0}))
              configure(1024,768,.15,1,actor.x,actor.y);game.selection={[actor.id]=true}
            ''')
            sequence=[];trace=[]
            for index in range(60):
                until=duration*index/59
                while float(G.S.time)+1e-7<until:lua.execute('Sim.step(S,.1)')
                backend.reset();G.qaTime=index*.25
                lua.execute(r'''
                  local snap=Save.snapshot(S);local seen=U.copy(S.factions[1].visible)
                  game.camera={x=actor.x,y=actor.y};game.realTime=qaTime;game.flowTime=S.time
                  R.draw(game);assert(qaSame(snap,Save.snapshot(S))and qaSame(seen,S.factions[1].visible))
                ''')
                sequence.append(Image.open(io.BytesIO(backend.png(1024,768))).convert('RGB'))
                trace.append({'previewTime':index*.25,'simulationTime':float(G.S.time),
                              'source':[float(G.actor.x)/2,(float(G.actor.y)-512)/2],
                              'lane':int(G.actor.vesselLane or 0)})
            path=OUT/'render'/f'cross-{source}-to-{target}-complete-15s.webp'
            sequence[0].save(path,save_all=True,append_images=sequence[1:],duration=250,loop=0,quality=86)
            movements.append({'fromOrgan':source,'toOrgan':target,'status':'PASS_OFFLINE_COMPLETE_ROUTE',
                              'file':str(path.relative_to(DOC)),'sha256':sha(path),'durationMs':15000,
                              'frames':60,'fps':4,'zoom':.15,'simulationDurationSeconds':duration,
                              'timeCompression':duration/15,'trace':trace,'nativeEvidence':False,
                              'note':'完整生产命令路线的15秒缩时预览；不代表原生移动速度或连续原生验收。'})
    lua.execute('A.release(worldContext);A.release(uiContext)')
    assert lua.eval('A.stats().images')==0
    changed=[p for p,h in binding.items()if sha(ROOT/p)!=h]
    failed=[m for m in movements if m['status']!='PASS_OFFLINE_COMPLETE_ROUTE']
    result={'schema':'fullbody-015-production-render/v1','nativeEvidence':False,
            'status':'UNDETERMINED_INPUT_CHANGED'if changed else'FAIL_PRODUCTION_MOVEMENT'if failed else'PASS_OFFLINE_RENDER',
            'productionEntry':'war.Render.draw','actualAssetDecodeVerified':True,'samples':samples,'frames':frames,
            'movements':movements,'animations':[{'file':m['file'],'sha256':m['sha256'],
                'label':m['fromOrgan']+' → '+m['toOrgan']+' 完整实际命令缩时预览','seconds':15,'fps':4,
                'nativeEvidence':False,'timeCompression':m['timeCompression']}
                for m in movements if m['status']=='PASS_OFFLINE_COMPLETE_ROUTE'],
            'inputHashes':binding,'changedDuringCapture':changed,
            'manifestSha256':manifest_hash,
            'logicalSourceScale':'64*zoom','sourcePixelLogicalScaleAt015':9.6,
            'saveRngVisibilityUnchanged':True,'fullbodyHandlesAfterRelease':0,
            'limits':['SVG/Cairo approximates actual Lua draw calls; native antialiasing, filtering and frame time remain separate.',
                      'Complete cross-organ previews accelerate actual simulation time into 15 playback seconds; no positions are teleported.']}
    write(OUT/'render-report.json',result);print('Render',result['status'],'frames',len(frames),flush=True);return result


def summary():
    names={'motion':'fullbody-motion-report.json','compatibility':'compatibility-report.json',
           'clearance':'clearance-report.json','pixels':'pixel-report.json',
           'resources':'resource-report.json','quietBase':'quiet-base-report.json',
           'visibility':'visibility-report.json','render':'render-report.json'}
    records={};nav=navigation_hashes();current=hashes()
    manifest_path=DOC/'bake/manifest.json';manifest_sha=sha(manifest_path)if manifest_path.is_file()else None
    for phase,name in names.items():
        p=OUT/name
        if not p.is_file():records[phase]={'status':'UNDETERMINED_MISSING_REPORT'};continue
        d=read(p);bindings=d.get('inputHashes',{})
        changed=[f for f,h in bindings.items()if not(ROOT/f).is_file()or sha(ROOT/f)!=h]
        if phase=='motion':
            changed+=['incomplete production coverage']if not d.get('coverage',{}).get('wholeBodyAccepted')else[]
            changed += [f for f,h in nav.items()if bindings.get(f)!=h]
        if phase=='pixels':
            changed+=['bake manifest']if d.get('manifestSha256')!=manifest_sha else[]
            changed+=['runtime data']if d.get('runtimeDataSha256')!=current.get('scripts/war/FullBodyMapArtData.lua')else[]
        if phase=='resources':
            changed += [a['resource']for a in d.get('assets',[])if sha(ROOT/'assets'/a['resource'])!=a['sha256']]
        if phase=='render':
            changed+=['complete 15s previews missing']if len(d.get('movements',[]))<2 else[]
        passed=d.get('status')in ['PASS','PASS_OFFLINE_RENDER']and not changed
        records[phase]={'status':'PASS'if passed else'UNDETERMINED_STALE_BINDING'if changed else d.get('status'),
                        'file':'qa/'+name,'sha256':sha(p),'total':d.get('total'),'passed':d.get('passed'),
                        'changedOrMissing':changed}
    passed=all(r['status']=='PASS'for r in records.values())and freeze_check()['unchanged']
    result={'schema':'fullbody-015-offline-acceptance-summary/v1','createdAt':now(),
            'status':'PASS_OFFLINE_FULLBODY'if passed else'INCOMPLETE_OR_RETAINED_FAILURES',
            'scope':{'organs':ORGANS,'frozenVesselEdges':202,'peripheralTissueDomainsAdded':0,'trueZoom':.15},
            'manifestSha256':manifest_sha,'runtimeHashes':current,'phases':records,
            'nativeEvidence':False,'nativeMovement':'UNDETERMINED','nativeP95':'UNDETERMINED',
            'artworkScope':{'remainingOrgans':[o for o in ORGANS if o not in ['heart','lung_r','lung_l']],
                            'externallyOwnedDeferredOrgans':['heart','lung_r','lung_l'],
                            'peripheralVascularRegionsIncluded':['head','neck','arms','hands','legs','feet'],
                            'status':'AWAIT_CURRENT_NATIVE_NON_CARDIOPULMONARY_REVIEW',
                            'note':'All twelve organ runtime/resource/navigation contracts remain checked; current user scope assigns heart/lungs to another conversation and does not declare their artwork complete.'},
            'limits':['Passing offline movement and drawing does not establish native continuous movement, GPU memory or P95.',
                      'Heart and lung artwork is external work awaiting a separate merge; this mathematical offline result is not a whole-body visual completion claim.']}
    write(OUT/'summary.json',result);print('Summary',result['status'],flush=True);return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--phase', choices=['baseline', 'matrix', 'motion', 'motion-review', 'pixels', 'resources', 'quiet-base', 'visibility', 'render', 'compatibility', 'summary', 'all'], default='all')
    parser.add_argument('--factory', choices=['trial', 'fullbody'], default='fullbody')
    parser.add_argument('--workers', type=int, default=4)
    parser.add_argument('--cpu-limit', type=float, default=90)
    parser.add_argument('--observation-max-time',type=float,help='Extend only the passive case observation budget; production dt/speed/route remain unchanged.')
    parser.add_argument('--setup-max-time',type=float,help='Extend only actual Commands blood-start preparation observation.')
    parser.add_argument('--family', help='Optional diagnostic subset; never accepted as whole-body QA.')
    parser.add_argument('--match', help='Optional diagnostic substring; never accepted as whole-body QA.')
    parser.add_argument('--worker', type=Path)
    parser.add_argument('--animate', action='store_true')
    parser.add_argument('--no-resume',action='store_true',help='Repeat even identical current-hash completed production cases.')
    args = parser.parse_args(); os.chdir(ROOT); OUT.mkdir(parents=True, exist_ok=True)
    if args.worker: motion_worker(args.worker, args.factory); return
    baseline()
    if args.phase == 'matrix': fixture_matrix()
    elif args.phase == 'motion': motion(args)
    elif args.phase == 'motion-review': motion_review()
    elif args.phase == 'compatibility': compatibility();clearance()
    elif args.phase == 'resources': resources()
    elif args.phase == 'pixels': pixels()
    elif args.phase == 'visibility': visibility()
    elif args.phase == 'quiet-base': quiet_base()
    elif args.phase == 'render': render(args.animate)
    elif args.phase == 'summary': summary()
    elif args.phase == 'baseline': print('Frozen baseline preserved:', OUT / 'baseline.json')
    else:
        compatibility();clearance();pixels();resources();quiet_base();visibility();render(True);motion(args);summary()


if __name__ == '__main__':
    main()
