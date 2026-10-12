"""Independent multi-organ acceptance using frozen authoring geometry.

Owns organ-atlas/qa only. No runtime patching, attachForTest, synthetic movement,
native preview start, or modification of the accepted stomach evidence.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import importlib.util
import json
import math

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'docs/body-life/vascular-art-study'
OUT = BASE / 'organ-atlas/qa'
GRAPH = BASE / 'final-reference-data.json'
CONTRACT = BASE / 'organ-atlas/contract.json'
FROZEN_GRAPH = '3890744e2fcaf9e9907c85513e170e479f67b7fbb1fbf06385ac02bd80e8550c'
ORGANS = ['brain', 'lung_r', 'lung_l', 'liver', 'stomach', 'pancreas',
          'kidney_r', 'kidney_l', 'large_intestine', 'small_intestine', 'bladder', 'heart']
SPECIAL_SYSTEMS = {'lung_r': ['air'], 'lung_l': ['air'], 'stomach': ['food'],
                  'pancreas': ['digestive-secretion'], 'kidney_r': ['urine'],
                  'kidney_l': ['urine'], 'large_intestine': ['food'],
                  'small_intestine': ['food'], 'bladder': ['urine']}
MODULES = ['World', 'Path', 'Commands', 'Workers', 'CellCollision', 'Save',
           'Render', 'View', 'Vessels', 'Simulation', 'ReferenceMap',
           'ReferenceVessels', 'GastricTrial', 'GastricTraffic', 'GastricArt',
           'ReferenceArt', 'GastricBattlefield', 'GastricBattlefieldData',
           'OrganBattlefield', 'OrganBattlefieldCore', 'OrganBattlefieldData',
           'OrganTrial', 'OrganTraffic', 'OrganArt', 'OrganBoundariesData',
           'FinalVascularStudyData', 'OrganAtlasArt', 'OrganAtlasArtData', 'Motion', 'Data', 'Util', 'HUD']
DRAW_ONLY_MODULES={'Render.lua','View.lua','ReferenceArt.lua','GastricArt.lua',
                   'OrganArt.lua','OrganAtlasArt.lua','OrganAtlasArtData.lua','HUD.lua','main.lua'}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(path):
    return json.loads(path.read_text())


def write(name, value):
    path = OUT / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2,
                                      sort_keys=True) + '\n')


def hashes():
    result={name + '.lua': sha(ROOT / 'scripts/war' / (name + '.lua'))
            for name in MODULES if (ROOT / 'scripts/war' / (name + '.lua')).is_file()}
    result['main.lua']=sha(ROOT/'scripts/main.lua')
    return result


def gastric_qa():
    spec = importlib.util.spec_from_file_location('accepted_gastric_qa',
                         ROOT / 'scripts/qa/check_gastric_battlefield.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def contract_records():
    if not CONTRACT.is_file():
        return None, {}
    c = load(CONTRACT)
    records = {r['organId']: load(ROOT / r['geometryPath']) for r in c['organs']}
    return c, records


def inherited_stomach_status():
    path = BASE / 'stomach-playable/qa/summary.json'
    s = load(path)
    changed = {n: {'tested': v, 'current': sha(ROOT / 'scripts/war' / n)}
               for n, v in s['testedModuleHashes'].items()
               if sha(ROOT / 'scripts/war' / n) != v}
    return {'status': 'PASS' if not changed and sha(GRAPH) == FROZEN_GRAPH else 'UNDETERMINED',
            'evidence': str(path.relative_to(ROOT)), 'summarySha256': sha(path),
            'changedSinceAccepted': changed,
            'previousActualLuaCases': s['actualMotionVerification']['cases'],
            'nativeEvidence': False,
            'limitation': 'Existing stomach evidence applies only to its tested hashes; the new facade needs integration checks.'}


def interface_requirements():
    d = {'schema': 'organ-atlas-independent-qa-interfaces/v1',
         'production': {'factory': 'war.OrganTrial.new(seed, organIds)',
                        'activation': {'anatomyVersion': 4, 'organBattlefieldVersion': 1,
                                       'organBattlefieldIds': ORGANS},
                        'movement': ['war.Commands.spawn', 'war.Commands.execute',
                                     'war.Simulation.step', 'war.Motion.record (read-only observation)'],
                        'facade': 'war.OrganBattlefield',
                        'requiredExports': ['enabled', 'enable', 'pointAllowed', 'sweep',
                                            'lane', 'beginRoute', 'resumeRoute', 'cancelRoute',
                                            'projectTarget', 'formation', 'organAt',
                                            'activeOrgans', 'trafficData'],
                        'transit': 'e.gastricTransit={gateId,fromLane,toLane}; no implicit layer change'},
         'authoring': {'rawDomains': ['outerRings', 'tissueRings', 'foodAirUrineRings',
                                     'wallRings', 'reservedLocalFeatures[].rawRings'],
                       'sourceTransform': {'sx': 2, 'sy': 2, 'oy': 512},
                       'ports': 'All frozen ports, exact original source coordinates, original edge IDs',
                       'membranes': ['id', 'organId', 'edgeId', 'laneIndex',
                                     'pipeAnchorSource', 'tissueAnchorSource',
                                     'rawThroatRings', 'throatRings'],
                       'unavailable': 'Missing safe access is explicitly unavailable, never accepted from artwork alone'},
         'render': {'entry': 'Actual war.Render.draw',
                    'artLifecycle': ['prepare(vg)', 'release(vg)'],
                    'resources': 'Per-context image handles and exact crop source bounds; separate image/mask hashes',
                    'zooms': [.085, .115, .149, .15, .18], 'dprs': [1, 2, 3]},
         'evidence': {'pass': 'Exact independent geometry or actual named production API succeeded',
                      'fail': 'An observed production behavior violates its explicit contract',
                      'undetermined': 'Interface/input/native evidence missing or tested hashes changed',
                      'nativeEvidence': False},
         'forbiddenQaSubstitutions': ['attachForTest', 'package.loaded ReferenceVessels replacement',
                                     'JS movement', 'QA-only route/controller', 'teleport completion']}
    write('interface-requirements.json', d)
    return d


def matrix():
    graph = load(GRAPH)
    c, records = contract_records()
    rows = []
    for organ_id in ORGANS:
        source = next(o for o in graph['organs'] if o['id'] == organ_id)
        geometry = records.get(organ_id)
        ports = [p for p in graph['ports'] if p['organ'] == organ_id]
        row = {'organId': organ_id, 'name': source['name'],
               'frozenSourceBounds': source['bounds'],
               'originalBoundaryKind': source['boundaryKind'],
               'frozenPorts': ports,
               'reservedSystemsRequired': SPECIAL_SYSTEMS.get(organ_id, []),
               'globalProtectedPassages': [p for p in graph['protectedPassages']
                                          if organ_id in p['owners']],
               'authoringStatus': geometry['status'] if geometry else 'MISSING',
               'nativeStatus': 'UNDETERMINED',
               'actualProductionMovementStatus': 'UNDETERMINED',
               'requiredCases': ['scout/siege rally↔each available doorway',
                                 'full cell circles and every actual swept capsule',
                                 'ordinary wall crossing rejected', 'small/large reciprocal meeting',
                                 'food/air/urine/duct target rejected when present',
                                 'state and RNG unchanged by rendering; DPR 1/2/3',
                                 'real Save.snapshot/restore preserves planes and coordinates']}
        if geometry:
            row['sourceBox'] = geometry['sourceBox']
            row['geometryPath'] = next(x['geometryPath'] for x in c['organs']
                                       if x['organId'] == organ_id)
            row['geometrySha256'] = sha(ROOT / row['geometryPath'])
            row['proposedAccessByProfile'] = {
                profile: {'rooms': len(p['rooms']), 'gates': len(p['gateContracts']),
                          'unavailableRooms': [r['id'] for r in p['rooms'] if not r['accessGateId']]}
                for profile, p in geometry.get('profiles', {}).items()}
            if organ_id == 'stomach':
                row['proposedAccessByProfile'] = {
                    'delegated': {'rooms': len(geometry.get('rooms', [])),
                                  'gateProfiles': list(geometry.get('gateContracts', {})),
                                  'unavailableRooms': []}}
        if organ_id == 'stomach':
            row['inheritedAcceptedEvidence'] = inherited_stomach_status()
        rows.append(row)
    result = {'schema': 'organ-atlas-acceptance-matrix/v1', 'status': 'UNDETERMINED',
              'sourceGraphSha256': sha(GRAPH), 'sourceGraphUnchanged': sha(GRAPH) == FROZEN_GRAPH,
              'sourceReferenceSha256': sha(ROOT / 'assets/image/anatomy-reference/reference.png'),
              'sourceTransform': graph['coordinates'], 'organs': rows,
              'nativeEvidence': False, 'runtimeHashes': hashes()}
    write('acceptance-matrix.json', result)
    return result


class RawOracle:
    """No eroded safe domain or production grid is used to certify itself."""
    def __init__(self, records):
        from shapely.geometry import Point, LineString, Polygon
        from shapely.ops import unary_union
        self.Point, self.LineString, self.Polygon = Point, LineString, Polygon
        self.union = unary_union
        self.records = records
        self.tissues = {k: self.rings(v['tissueRings']) for k, v in records.items()}
        self.reserves = {k: self.rings(v['foodAirUrineRings']) for k, v in records.items()}
        self.blood = {i + 1: LineString(e['samples']).buffer(e['lumenWidthSource'] / 2,
                       quad_segs=32) for i, e in enumerate(load(GRAPH)['edges'])}

    def rings(self, rings):
        return self.union([self.Polygon(p['outer'], p.get('holes', [])) for p in rings])

    def full_disk(self, domain, p, radius):
        center = self.Point(p)
        return domain.covers(center) and domain.boundary.distance(center) >= radius - 2e-6

    def full_capsule(self, domain, a, b, radius):
        if a == b:
            return self.full_disk(domain, a, radius)
        return domain.buffer(2e-6).covers(self.LineString([a, b]).buffer(radius, quad_segs=32))


def geometry_checks():
    c, records = contract_records()
    if not c or set(records) != set(ORGANS):
        result = {'status': 'UNDETERMINED', 'reason': 'Incomplete 12-organ authoring contract',
                  'nativeEvidence': False}
        write('geometry-authoring-report.json', result)
        return result
    oracle = RawOracle(records)
    graph = load(GRAPH)
    cases, unavailable = [], []
    for organ_id in ORGANS:
        rec = records[organ_id]
        if organ_id == 'stomach':
            cases.append({'id': 'stomach/delegated-existing-geometry', 'status': 'UNDETERMINED',
                          'reason': 'Atlas stomach is an illustration guide; production must delegate the previously accepted GastricBattlefieldData.'})
            continue
        original_ports = [p for p in graph['ports'] if p['organ'] == organ_id]
        cases.append({'id': organ_id + '/frozen-ports', 'status': 'PASS'
                      if rec['frozenPorts'] == original_ports else 'FAIL'})
        cases.append({'id': organ_id + '/separate-reserved-plane', 'status': 'PASS'
                      if oracle.tissues[organ_id].intersection(oracle.reserves[organ_id]).area < 1e-7
                      and all(x.get('cellEntry') is False for x in rec['reservedLocalFeatures']) else 'FAIL'})
        for profile, p in rec['profiles'].items():
            radius = p['radiusSource']
            gates = {g['id']: g for g in p['gateContracts']}
            for room in p['rooms']:
                allowed = oracle.full_disk(oracle.tissues[organ_id], room['rallySource'], radius)
                cases.append({'id': room['id'] + '/raw-full-disk',
                              'status': 'PASS' if allowed else 'FAIL'})
                if not room['accessGateId']:
                    unavailable.append({'organId': organ_id, 'profile': profile, 'roomId': room['id'],
                                        'reason': 'No safe frozen blood approach supplied'})
                    continue
                gate = gates[room['accessGateId']]
                pipe, tissue = gate['pipeAnchorSource'], gate['tissueAnchorSource']
                raw = oracle.rings(gate['rawThroatRings'])
                domain = oracle.union([oracle.tissues[organ_id], oracle.blood[gate['laneIndex']], raw])
                edge = graph['edges'][gate['laneIndex'] - 1]
                ok = (gate['edgeId'] == edge['id'] and
                      oracle.full_disk(oracle.blood[gate['laneIndex']], pipe, radius) and
                      oracle.full_disk(oracle.tissues[organ_id], tissue, radius) and
                      oracle.full_capsule(domain, pipe, tissue, radius))
                cases.append({'id': room['id'] + '/gate-raw-full-capsule',
                              'status': 'PASS' if ok else 'FAIL', 'gateId': gate['id']})
    failures = [x for x in cases if x['status'] == 'FAIL']
    result = {'schema': 'organ-atlas-independent-authoring-geometry/v1',
              'status': 'FAIL' if failures else 'PASS', 'cases': cases,
              'passed': sum(x['status'] == 'PASS' for x in cases),
              'failed': len(failures), 'undetermined': sum(x['status'] == 'UNDETERMINED' for x in cases),
              'unavailableRooms': unavailable, 'sourceGraphUnchanged': sha(GRAPH) == FROZEN_GRAPH,
              'contractSha256': sha(CONTRACT), 'nativeEvidence': False,
              'actualProductionMovementAccepted': False,
              'limitations': ['Authoring geometry PASS is not actual production movement acceptance.',
                              'Unconnected rooms remain explicitly unavailable.',
                              'Native preview is stopped; native rendering and performance are UNDETERMINED.']}
    write('geometry-authoring-report.json', result)
    return result


def interface_status():
    required = ['OrganBattlefield', 'OrganBattlefieldCore', 'OrganBattlefieldData', 'OrganTrial', 'OrganTraffic']
    missing = [n for n in required if not (ROOT / 'scripts/war' / (n + '.lua')).is_file()]
    hooks = {n: ('war.OrganBattlefield' in (ROOT / 'scripts/war' / (n + '.lua')).read_text())
             for n in ['Commands', 'Path', 'World', 'CellCollision', 'Save', 'Simulation']}
    hooks['Simulation'] = 'war.OrganTrial' in (ROOT / 'scripts/war/Simulation.lua').read_text()
    exports, organ_count, error = {}, 0, None
    if not missing:
        try:
            qa = gastric_qa()
            l = qa.runtime()
            exports = qa.convert(l.execute("local out={};for k,v in pairs(require('war.OrganBattlefield'))do out[k]=type(v)end;return out"))
            organ_count = l.execute("local n=0;for _ in pairs(require('war.OrganBattlefieldData').organs or {})do n=n+1 end;return n")
        except Exception as e:
            error = str(e)
    r = {'schema': 'organ-atlas-production-interface-status/v1',
         'status': 'UNDETERMINED', 'missingModules': missing,
         'integrationHooksObserved': hooks, 'runtimeOrganCount': organ_count,
         'exports': exports, 'loadError': error,
         'testedModuleHashes': hashes(), 'nativeEvidence': False,
         'reason': 'Interfaces are inventoried here; only actual production cases can accept navigation.'}
    write('interface-status.json', r)
    return r


LUA_SCENARIO = r'''
local T,S,C,W,K,Save,M,O,Traffic=require('war.OrganTrial'),require('war.Simulation'),
 require('war.Commands'),require('war.World'),require('war.CellCollision'),
 require('war.Save'),require('war.Motion'),require('war.OrganBattlefield'),require('war.OrganTraffic')
return function(config)
 local s=T.new(73,config.organs)
 assert(s.organBattlefieldVersion==1,'production organ trial did not enable')
 s.entities={};s.commands={};W.rebuild(s)
 local actors={};local result={id=config.id,starts={},trace={},frames={},commands={},goals={},spawnErrors={}}
 local function position(e,phase)
  return {id=e.id,kind=e.kind,x=e.x,y=e.y,lane=e.vesselLane or 0,phase=phase,
   organId=O.organAt(s,e,e.x,e.y),time=s.time,tick=s.tick,
   transit=e.gastricTransit and {gateId=e.gastricTransit.gateId,
    fromLane=e.gastricTransit.fromLane,toLane=e.gastricTransit.toLane}or nil}
 end
 for i,a in ipairs(config.actors)do
  local spawn=a.setupSource
  local e=C.spawn(s,'unit',a.kind,1,spawn and spawn[1]*2 or a.x,
   spawn and spawn[2]*2+512 or a.y)
  if not e then result.spawnErrors[#result.spawnErrors+1]={index=i,reason='rejected'}
  else
   actors[i]=e;result.starts[#result.starts+1]=position(e,'spawn')
   local initialLane=spawn and 0 or a.lane
   if initialLane~=nil and initialLane~=e.vesselLane then
    result.spawnErrors[#result.spawnErrors+1]={index=i,expectedLane=initialLane,actualLane=e.vesselLane}
   end
  end
 end
 W.rebuild(s)
 local original=M.record
 M.record=function(e)
  if s.entities[e.id]==e then result.trace[#result.trace+1]=position(e,'substep')end
  original(e)
 end
 -- Overlapping blood and tissue projections need an explicit plane command.
 -- Prepare a blood start by actual movement; never edit its lane or teleport.
 result.setupElapsed=0;result.setupCommands={}
 for i,a in ipairs(config.actors)do if a.setupSource and actors[i]then
  local e=actors[i]
  local accepted=C.execute(s,{kind='move',faction=1,ids={e.id},x=a.x,y=a.y,lane=a.lane})
  result.setupCommands[#result.setupCommands+1]={id=e.id,accepted=accepted==true,lane=a.lane}
  local budget=0
  while #e.orders>0 and budget<300 do
   S.step(s,require('war.Data').STEP);budget=budget+require('war.Data').STEP
  end
  result.setupElapsed=result.setupElapsed+budget
  if #e.orders>0 or e.vesselLane~=a.lane or e.gastricTransit or
   math.sqrt((e.x-a.x)^2+(e.y-a.y)^2)>.075 then
   result.spawnErrors[#result.spawnErrors+1]={index=i,reason='real-blood-start-preparation-failed',
    expectedLane=a.lane,actualLane=e.vesselLane,x=e.x,y=e.y}
  end
 end end
 local function recordCommand(e,a,accepted)
  local o=e.orders[1]
  result.commands[#result.commands+1]={id=e.id,accepted=accepted==true,
   requested={x=a.tx,y=a.ty},order=o and{x=o.x,y=o.y,lane=o.lane}or nil}
  if o then result.goals[#result.goals+1]={id=e.id,x=o.x,y=o.y,lane=a.targetLane,
   organId=a.targetOrgan}end
 end
 if config.group then
  local ids={};for _,e in ipairs(actors)do ids[#ids+1]=e.id end
  local g=config.group
  local accepted=C.execute(s,{kind='move',faction=1,ids=ids,x=g.x,y=g.y,lane=g.lane})
  for _,e in ipairs(actors)do recordCommand(e,{tx=g.x,ty=g.y,targetLane=g.lane,
   targetOrgan=g.organId},accepted)end
 else
  for i,a in ipairs(config.actors)do if actors[i]and a.tx then
   local wanted=a.targetLane;if a.implicitTargetLane then wanted=nil end
   recordCommand(actors[i],a,C.execute(s,{kind='move',faction=1,ids={actors[i].id},x=a.tx,y=a.ty,lane=wanted}))
  end end
 end
 local elapsed,completed,minGap=0,false,math.huge
 local lastLanes={};for _,e in ipairs(actors)do lastLanes[e.id]=e.vesselLane end
 while elapsed<(config.maxTime or 300)and #result.spawnErrors==0 do
  S.step(s,require('war.Data').STEP);elapsed=elapsed+require('war.Data').STEP
  local frame={time=s.time,points={}}
  for _,e in ipairs(actors)do frame.points[#frame.points+1]=position(e,'frame')end
  result.frames[#result.frames+1]=frame
  if (config.restoreOnTransit or config.restoreTrafficPair)and not result.midTransitSave then
   for _,e in ipairs(actors)do if e.gastricTransit or lastLanes[e.id]~=e.vesselLane or
    config.restoreTrafficPair and Traffic.stats(s).activePairs>0 then
    local old=position(e,'before-save');local snap=Save.snapshot(s)
    local restored=Save.restore(snap);local newer=restored.entities[e.id]
    local stable=math.abs(e.x-newer.x)+math.abs(e.y-newer.y)
    result.midTransitSave={before=old,positionError=stable,version=snap.version,
     captureStage=config.restoreTrafficPair and 'active-traffic-protocol' or e.gastricTransit and 'active-throat-transit' or 'explicit-plane-handoff',
     trafficBefore=Traffic.stats(s),
     organFlag=snap.organBattlefieldVersion,ids=snap.organBattlefieldIds,
     laneMatches=e.vesselLane==newer.vesselLane,
     gateMatches=not e.gastricTransit or newer.gastricTransit and newer.gastricTransit.gateId==e.gastricTransit.gateId,
     originalSnapshotUnchanged=s.time==snap.time and s.tick==snap.tick and s.rng==snap.rng}
    s=restored;for i,a in ipairs(actors)do actors[i]=s.entities[a.id]end
    result.midTransitSave.after=position(newer,'after-restore')
    result.midTransitSave.trafficAfter=Traffic.stats(s)
    break
   end end
  end
  for _,e in ipairs(actors)do lastLanes[e.id]=e.vesselLane end
  for i,e in ipairs(actors)do for j=i+1,#actors do local b=actors[j]
   if e.gastricTransit or b.gastricTransit or e.vesselLane==b.vesselLane then
   minGap=math.min(minGap,math.sqrt((e.x-b.x)^2+(e.y-b.y)^2)-K.radius(e)-K.radius(b))
   end
  end end
  completed=true;for _,e in ipairs(actors)do if #e.orders>0 then completed=false end end
  if Traffic.stats(s).activePairs>0 then completed=false end
  if completed and not config.observeIdle then break end
 end
 M.record=original
 result.completed,result.elapsed=completed,elapsed
 result.minimumFrameDiskGapWorld=minGap<math.huge and minGap or nil
 result.endpoints={};for _,e in ipairs(actors)do
  local p=position(e,'end');p.ordersRemaining=#e.orders;p.pathFailed=e.pathFailed or false
  p.routeReason=e.gastricRouteReason;result.endpoints[#result.endpoints+1]=p
 end
 result.trafficStats=Traffic.stats(s);result.activeOrgans=O.activeOrgans(s)
 result.networkEdges=#W.vessels(s).edges
 local snap=Save.snapshot(s);local ok,restored=pcall(Save.restore,snap)
 result.save={version=snap.version,flag=snap.organBattlefieldVersion,
  ids=snap.organBattlefieldIds,restored=ok,positionErrors=0,laneErrors=0,
  error=not ok and tostring(restored)or nil}
 if ok then
  result.save.restoredFlag=restored.organBattlefieldVersion
  result.save.restoredIds=restored.organBattlefieldIds
  result.save.restoredNetworkEdges=#W.vessels(restored).edges
  for _,e in ipairs(actors)do local f=restored.entities[e.id]
   if not f then result.save.positionErrors=result.save.positionErrors+1
   else result.save.positionErrors=result.save.positionErrors+math.abs(e.x-f.x)+math.abs(e.y-f.y)
    if e.vesselLane~=f.vesselLane then result.save.laneErrors=result.save.laneErrors+1 end
   end
  end
 end
 return result
end
'''


class MotionOracle(RawOracle):
    def __init__(self, records):
        super().__init__(records)
        self.gates = {}
        for organ_id, r in records.items():
            for p in r.get('profiles', {}).values():
                for g in p['gateContracts']:
                    self.gates[g['id']] = (organ_id, g)
        # The delegated stomach uses its accepted raw layout, never the atlas guide.
        if 'stomach' in records:
            g = load(BASE / 'stomach-playable/layout.json')
            self.tissues['stomach'] = self.rings(g['tissueWalkableRings'])
            for gate in g['gateContracts']['siege']:
                self.gates[gate['id']] = ('stomach', gate)
        self.edges = load(GRAPH)['edges']

    @staticmethod
    def radius(kind):
        return {'scout': 14, 'siege': 34, 'worker': 19, 'virus': 18,
                'spear': 22, 'archer': 22, 'heavy': 27, 'wolf': 19, 'shadow': 17}[kind] / 64

    @staticmethod
    def source(p):
        return [p['x'] * .5, (p['y'] - 512) * .5]

    def transit_domain(self, transit):
        pair = self.gates.get(transit['gateId'])
        if not pair:
            return None
        owner, gate = pair
        blood = self.blood[gate['laneIndex']]
        raw = gate.get('rawThroatRings')
        if raw:
            throat = self.rings(raw)
        else:
            # Original stomach full gate circle, as independently accepted before.
            throat = self.Point(gate['wallSource']).buffer(1.9, quad_segs=32)
        return self.union([self.tissues[owner], blood, throat])

    def disk(self, p, kind):
        domain = (self.transit_domain(p['transit']) if p.get('transit') else
                  self.blood.get(p['lane']) if p['lane'] else self.tissues.get(p.get('organId')))
        if domain is None:
            return None
        return self.full_disk(domain, self.source(p), self.radius(kind))

    def capsule(self, a, b, kind):
        start, end, radius = self.source(a), self.source(b), self.radius(kind)
        transit = b.get('transit') or a.get('transit')
        if transit:
            domain = self.transit_domain(transit)
            return None if domain is None else self.full_capsule(domain, start, end, radius)
        if a['lane'] == b['lane']:
            if a['lane']:
                domain = self.blood.get(a['lane'])
            elif a.get('organId') == b.get('organId'):
                domain = self.tissues.get(a.get('organId'))
            else:
                return False  # No tissue shortcuts between projected organ layers.
            return None if domain is None else self.full_capsule(domain, start, end, radius)
        segment = self.LineString([start, end])
        if a['lane'] and b['lane']:
            left, right = self.edges[a['lane'] - 1], self.edges[b['lane'] - 1]
            shared = set([left['a'], left['b']]) & set([right['a'], right['b']])
            nodes = [left['points'][0 if name == left['a'] else -1] for name in shared]
            near = any(segment.distance(self.Point(p)) <=
                       min(left['lumenWidthSource'], right['lumenWidthSource']) / 2 + radius
                       for p in nodes)
            domain = self.union([self.blood[a['lane']], self.blood[b['lane']]])
            return near and self.full_capsule(domain, start, end, radius)
        lane = a['lane'] or b['lane']
        tissue_owner = a.get('organId') if not a['lane'] else b.get('organId')
        for owner, gate in self.gates.values():
            if gate['laneIndex'] != lane or owner != tissue_owner:
                continue
            domain = self.transit_domain({'gateId': gate['id']})
            throat = self.rings(gate['rawThroatRings']) if gate.get('rawThroatRings') else self.Point(gate['wallSource']).buffer(1.9)
            if segment.intersects(throat) and self.full_capsule(domain, start, end, radius):
                return True
        return False


def scenario_configs(records):
    out = []
    def actor(kind, a, b, owner, lane=0, target_lane=0, target_owner=None):
        return {'kind': kind, 'x': 2 * a[0], 'y': 2 * a[1] + 512,
                'tx': 2 * b[0], 'ty': 2 * b[1] + 512, 'lane': lane,
                'targetLane': target_lane, 'targetOrgan': target_owner or owner}
    for owner in ORGANS:
        if owner == 'stomach':
            continue
        rec = records[owner]
        for kind in ['scout', 'siege']:
            profile = rec['profiles'][kind]
            gates = {g['id']: g for g in profile['gateContracts']}
            for room in profile['rooms']:
                gate = gates.get(room['accessGateId'])
                if not gate:
                    continue
                rally, tissue, pipe = room['rallySource'], gate['tissueAnchorSource'], gate['pipeAnchorSource']
                for name, a, b, source_lane, target_lane in [
                    ('rally-to-door', rally, tissue, 0, 0),
                    ('door-to-rally', tissue, rally, 0, 0),
                    ('enter-from-blood', pipe, rally, gate['laneIndex'], 0),
                    ('exit-to-blood', rally, pipe, 0, gate['laneIndex'])]:
                    unit = actor(kind, a, b, owner, source_lane, target_lane)
                    if source_lane:
                        unit['setupSource'] = rally
                    out.append({'id': f'{owner}/{kind}/{room["id"]}/{name}', 'organs': [owner],
                                'actors': [unit]})
        for feature in rec['reservedLocalFeatures']:
            domain = RawOracle({owner: rec}).rings(feature['rawRings'])
            if domain.is_empty:
                continue
            target = domain.representative_point()
            rally = rec['profiles']['scout']['rooms'][0]['rallySource']
            out.append({'id': f'{owner}/negative/{feature["id"]}', 'organs': [owner],
                        'actors': [actor('scout', rally, [target.x, target.y], owner)],
                        'negative': True, 'observeIdle': True, 'maxTime': 1})
        # Broad reserved food passages may not be represented by a local feature.
        if owner in ['small_intestine', 'large_intestine']:
            oracle = RawOracle({owner: rec})
            target = oracle.reserves[owner].representative_point()
            rally = rec['profiles']['scout']['rooms'][0]['rallySource']
            out.append({'id': f'{owner}/negative/food', 'organs': [owner],
                        'actors': [actor('scout', rally, [target.x, target.y], owner)],
                        'negative': True, 'observeIdle': True, 'maxTime': 1})
        if owner=='bladder':
            passage=next(p for p in rec['protectedPassages'] if p['id']=='urine.urethra')
            target=passage['points'][1]
            for kind in ['scout','siege']:
                rally=rec['profiles'][kind]['rooms'][0]['rallySource']
                out.append({'id':f'{owner}/negative/urine.urethra/{kind}','organs':[owner],
                    'actors':[actor(kind,rally,target,owner)],'negative':True,
                    'observeIdle':True,'maxTime':1})
        # A real reciprocal tissue order, not a pre-scripted visual replay.
        p = rec['profiles']['siege']
        room = next((r for r in p['rooms'] if r['accessGateId']), None)
        if room:
            gate = next(g for g in p['gateContracts'] if g['id'] == room['accessGateId'])
            out.append({'id': f'{owner}/meeting/scout-siege', 'organs': [owner],
                        'actors': [actor('scout', room['rallySource'], gate['tissueAnchorSource'], owner),
                                   actor('siege', gate['tissueAnchorSource'], room['rallySource'], owner)]})
    for left, right in [('liver', 'kidney_r'), ('lung_r', 'lung_l'),
                        ('kidney_l', 'bladder'), ('pancreas', 'small_intestine')]:
        for kind in ['scout', 'siege']:
            a = records[left]['profiles'][kind]['rooms'][0]['rallySource']
            b = records[right]['profiles'][kind]['rooms'][0]['rallySource']
            out.append({'id': f'cross-organ/{left}-to-{right}/{kind}', 'organs': [left, right],
                        'actors': [actor(kind, a, b, left, target_owner=right)], 'maxTime': 600})
    # Restore a genuinely moving actor inside an exchange throat. Cover air,
    # solid tissue, the short outer vestibule, and the urine exclusion system.
    for owner in ['lung_r', 'liver', 'large_intestine', 'bladder']:
        for kind in ['scout', 'siege']:
            p=records[owner]['profiles'][kind]
            room=next(r for r in p['rooms'] if r['accessGateId'])
            gate=next(g for g in p['gateContracts'] if g['id']==room['accessGateId'])
            out.append({'id':f'restore-in-transit/{owner}/{kind}', 'organs':[owner],
                        'actors':[actor(kind,room['rallySource'],gate['pipeAnchorSource'],
                                        owner,target_lane=gate['laneIndex'])],
                        'restoreOnTransit':True})
    # A narrow real liver vessel requires the new state-aware traffic module.
    # Both initial blood positions are reached through real tissue-to-blood orders.
    from shapely.geometry import LineString
    owner='liver';profile=records[owner]['profiles']['siege']
    gate=profile['gateContracts'][0];lane=gate['laneIndex']
    line=LineString(load(GRAPH)['edges'][lane-1]['samples'])
    a,b=line.interpolate(line.length*.2),line.interpolate(line.length*.8)
    for kinds in [('scout','siege'),('siege','siege')]:
        units=[]
        for kind,start,target in [(kinds[0],a,b),(kinds[1],b,a)]:
            unit=actor(kind,[start.x,start.y],[target.x,target.y],owner,lane,lane)
            unit['setupSource']=records[owner]['profiles'][kind]['rooms'][0]['rallySource']
            units.append(unit)
        out.append({'id':f'blood-meeting/liver/{kinds[0]}-{kinds[1]}',
                    'organs':[owner],'actors':units,'maxTime':600})
    # A narrow but valid scout destination must not inherit the siege radius.
    owner='bladder';target=[511.33,798];oracle=RawOracle({owner:records[owner]})
    if not oracle.full_disk(oracle.tissues[owner],target,MotionOracle.radius('scout')) or oracle.full_disk(oracle.tissues[owner],target,MotionOracle.radius('siege')):
        raise AssertionError('scout-only boundary fixture no longer matches raw tissue')
    rally=records[owner]['profiles']['scout']['rooms'][0]['rallySource']
    unit=actor('scout',rally,target,owner);unit['implicitTargetLane']=True
    out.append({'id':'bladder/positive/scout-only-urethra-edge-default-plane','organs':[owner],
                'actors':[unit]})
    return out


def production_checks(case_filter=None):
    status = interface_status()
    if (status['loadError'] or status['runtimeOrganCount'] < 11 or
        not all(status['integrationHooksObserved'].values())):
        r = {'schema': 'organ-atlas-production-motion/v1', 'status': 'UNDETERMINED',
             'reason': 'Production data or actual existing-entry hooks are incomplete',
             'interface': status, 'nativeEvidence': False, 'cases': []}
        write('production-report.json', r)
        return r
    qa = gastric_qa()
    _, records = contract_records()
    oracle = MotionOracle(records)
    before = hashes()
    l = qa.runtime()
    run = l.execute(LUA_SCENARIO)
    cases = []
    for config in scenario_configs(records):
        if case_filter and case_filter not in config['id']:
            continue
        config['caseOrgans'] = config['organs']
        config['organs'] = list(ORGANS)  # Validate concurrent layers, not one-organ-only shortcuts.
        try:
            actual = qa.convert(run(qa.lua_table(l, config)))
        except Exception as e:
            row = {'id': config['id'], 'status': 'FAIL', 'runnerError': str(e),
                   'scope': 'actual production factory / command / Simulation entry'}
            cases.append(row)
            print(config['id'], 'FAIL', row['runnerError'], flush=True)
            continue
        failures, disks, capsules, unknown = [], 0, 0, 0
        previous = {p['id']: p for p in actual['starts']}
        for p in actual['trace']:
            result = oracle.disk(p, p['kind']);disks += 1
            if result is None: unknown += 1
            elif not result: failures.append({'type': 'full-disk', 'point': p})
            a = previous.get(p['id'])
            if a:
                result = oracle.capsule(a, p, p['kind']);capsules += 1
                if result is None: unknown += 1
                elif not result: failures.append({'type': 'swept-capsule', 'from': a, 'to': p})
            previous[p['id']] = p
        for frame in actual['frames']:
            for p in frame['points']:
                result = oracle.disk(p, p['kind']);disks += 1
                if result is None: unknown += 1
                elif not result: failures.append({'type': 'frame-full-disk', 'point': p})
        goals = {g['id']: g for g in actual['goals']}
        arrivals = []
        for p in actual['endpoints']:
            g = goals.get(p['id'])
            if g:
                arrivals.append({'id': p['id'], 'distanceWorld': math.hypot(p['x']-g['x'], p['y']-g['y']),
                                 'laneMatches': g['lane'] == p['lane'],
                                 'organMatches': g['lane'] != 0 or g['organId'] == p.get('organId')})
        save = actual['save']
        save_ok = (save['restored'] and save.get('restoredFlag') == 1 and
                   save.get('restoredIds') == save['ids'] and save.get('restoredNetworkEdges') == 202 and
                   save['positionErrors'] < 1e-8 and save['laneErrors'] == 0 and save['version'] == 9)
        mid=actual.get('midTransitSave')
        if config.get('restoreOnTransit'):
            save_ok=save_ok and bool(mid and mid['positionError']<1e-8 and
                mid['version']==9 and mid['organFlag']==1 and mid['laneMatches'] and
                mid['gateMatches'] and mid['originalSnapshotUnchanged'] and mid['ids']==sorted(ORGANS))
        commands_ok = all(not c['accepted'] and not c.get('order') for c in actual['commands']) if config.get('negative') else all(c['accepted'] and c.get('order') for c in actual['commands'])
        arrived = all(a['distanceWorld'] <= .075 and a['laneMatches'] and a['organMatches'] for a in arrivals)
        passed = (actual['completed'] and not actual['spawnErrors'] and not failures and not unknown and
                  commands_ok and arrived and save_ok and
                  actual['trafficStats'].get('expired', 0) == 0 and
                  (actual.get('minimumFrameDiskGapWorld') is None or actual['minimumFrameDiskGapWorld'] >= -1e-6))
        row = {'id': config['id'], 'status': 'PASS' if passed else 'FAIL',
               'elapsedSimulationSeconds': actual['elapsed']+actual.get('setupElapsed',0),
               'setupSimulationSeconds': actual.get('setupElapsed',0), 'disksChecked': disks,
               'capsulesChecked': capsules, 'geometryFailures': len(failures),
               'unverifiedDomainPoints': unknown, 'firstGeometryFailures': failures[:12],
               'commandsValid': commands_ok, 'completed': actual['completed'],
               'spawnErrors': actual['spawnErrors'], 'assignedTargetArrivals': arrivals,
               'savePassed': save_ok, 'trafficStats': actual['trafficStats']}
        if mid:row['midTransitSave']=mid
        cases.append(row)
        name = config['id'].replace('/', '__') + '.json'
        write('traces/' + name, {'schema': 'organ-atlas-actual-lua-trace/v1',
                                'nativeEvidence': False, 'navigationSubstituted': False,
                                'config': config, 'result': actual})
        print(config['id'], row['status'], flush=True)
    after = hashes()
    changed_all = [k for k, v in before.items() if v != after.get(k)]
    changed = [k for k in changed_all if k not in DRAW_ONLY_MODULES]
    result = {'schema': 'organ-atlas-production-motion/v1',
              'status': 'UNDETERMINED' if changed else 'PASS' if cases and all(c['status'] == 'PASS' for c in cases) else 'FAIL',
              'passed': sum(c['status'] == 'PASS' for c in cases), 'total': len(cases),
              'cases': cases, 'testedModuleHashes': before, 'modulesChangedDuringCapture': changed,
              'drawOnlyModulesChangedDuringCapture':[k for k in changed_all if k in DRAW_ONLY_MODULES],
              'acceptedHashScope':'Movement, geometry, state, commands, collision, traffic, save and observed Motion. Draw-only changes are recorded separately and need render/resource recapture.',
              'sourceGraphUnchanged': sha(GRAPH) == FROZEN_GRAPH,
              'nativeEvidence': False, 'navigationSubstituted': False,
              'runtimeScope': 'Actual OrganTrial / Commands / Path / Workers / CellCollision / Simulation / Save',
              'limitations': ['Native preview is stopped; native graphics and frame timing are UNDETERMINED.']}
    suffix = '-filtered' if case_filter else ''
    write('production' + suffix + '-report.json', result)
    return result


def collision_checks():
    qa=gastric_qa();l=qa.runtime();_,records=contract_records()
    oracle=MotionOracle(records);before=hashes()
    probe=l.execute(r'''
      local T,W,C,P,K,O=require('war.OrganTrial'),require('war.World'),require('war.Commands'),
       require('war.Path'),require('war.CellCollision'),require('war.OrganBattlefield')
      local s=T.new(73,...)
      return function(kind,x,y,tx,ty)
       s.entities={};s.commands={};W.rebuild(s)
       local e=C.spawn(s,'unit',kind,1,x,y)
       if not e then return{spawned=false}end
       W.rebuild(s)
       local clear=P.clear(s,e.x,e.y,tx,ty,1,e.vesselLane,0,e)
       local nx,ny,lane,transit=K.move(s,e,tx,ty,0)
       return{spawned=true,spawn={x=e.x,y=e.y,lane=e.vesselLane,organId=O.organAt(s,e,e.x,e.y)},
        directClear=clear,movement={x=nx,y=ny,lane=lane,transit=transit,
         organId=O.organAt(s,e,nx,ny)}}
      end
    ''',qa.lua_table(l,ORGANS))
    rows=[];missing=[]
    for owner in ORGANS:
        if owner=='stomach':continue
        rec=records[owner];domain=oracle.tissues[owner]
        outer=oracle.rings(rec['outerRings'])
        domains=[('outer-membrane',outer)]
        if rec['wallRings']:domains.append(('internal-wall',oracle.rings(rec['wallRings'])))
        for name,boundary_domain in domains:
            candidate=None
            polygons=list(boundary_domain.geoms) if boundary_domain.geom_type=='MultiPolygon' else [boundary_domain]
            for polygon in polygons:
                line=polygon.exterior
                for i in range(1,129):
                    d=line.length*i/129;mid=line.interpolate(d)
                    a=line.interpolate(max(0,d-.15));b=line.interpolate(min(line.length,d+.15))
                    dx,dy=b.x-a.x,b.y-a.y;length=math.hypot(dx,dy)
                    if not length:continue
                    for sign in [-1,1]:
                        start=[mid.x-sign*dy/length*1.4,mid.y+sign*dx/length*1.4]
                        end=[mid.x+sign*dy/length*1.4,mid.y-sign*dx/length*1.4]
                        if oracle.full_disk(domain,start,oracle.radius('siege')) and not oracle.full_capsule(domain,start,end,oracle.radius('scout')):
                            candidate=(start,end);break
                    if candidate:break
                if candidate:break
            if not candidate:
                missing.append(owner+'/'+name);continue
            a,b=candidate
            for kind in ['scout','siege']:
                actual=qa.convert(probe(kind,2*a[0],2*a[1]+512,2*b[0],2*b[1]+512))
                moved=actual.get('movement')
                covered=bool(moved and oracle.capsule(actual['spawn'],moved,kind))
                passed=actual['spawned'] and not actual['directClear'] and covered
                rows.append({'id':owner+'/'+name+'/'+kind,'status':'PASS' if passed else 'FAIL',
                    'sourceStart':a,'attemptedSourceTarget':b,'actual':actual,
                    'actualReturnedCapsuleCovered':covered})
    changed=[k for k,v in before.items() if hashes().get(k)!=v]
    r={'schema':'organ-atlas-production-collision-contracts/v1',
       'status':'UNDETERMINED' if changed or missing else 'PASS' if rows and all(x['status']=='PASS' for x in rows) else 'FAIL',
       'passed':sum(x['status']=='PASS' for x in rows),'total':len(rows),'cases':rows,
       'missingDerivedProbes':missing,'nativeEvidence':False,'testedModuleHashes':before,
       'modulesChangedDuringCapture':changed,'sourceGraphUnchanged':sha(GRAPH)==FROZEN_GRAPH,
       'runtimeScope':'Actual all-active OrganTrial, Commands.spawn, Path.clear, CellCollision.move; isolated large-displacement API contract.'}
    write('collision-contract-report.json',r)
    return r


def command_preservation_checks():
    qa=gastric_qa();l=qa.runtime();_,records=contract_records();before=hashes()
    run=l.execute(r'''
      local T,C,W,S,U=require('war.OrganTrial'),require('war.Commands'),require('war.World'),
       require('war.Simulation'),require('war.Util')
      return function(ids,kind,a,b)
       local s=T.new(73,ids);s.entities={};s.commands={};W.rebuild(s)
       local e=assert(C.spawn(s,'unit',kind,1,a[1]*2,a[2]*2+512));W.rebuild(s)
       local positive=C.execute(s,{kind='move',faction=1,ids={e.id},x=b[1]*2,y=b[2]*2+512,lane=0})
       S.step(s,require('war.Data').STEP)
       local old={x=e.x,y=e.y,lane=e.vesselLane,token=e.orderToken,orders=U.copy(e.orders),
        path=U.copy(e.path),pathIndex=e.pathIndex,pathPending=e.pathPending,
        pathGoal=U.copy(e.pathGoal),pathFailed=e.pathFailed}
       local accepted=C.execute(s,{kind='move',faction=1,ids={e.id},x=1018,y=2108,lane=0})
       local newer={x=e.x,y=e.y,lane=e.vesselLane,token=e.orderToken,orders=U.copy(e.orders),
        path=U.copy(e.path),pathIndex=e.pathIndex,pathPending=e.pathPending,
        pathGoal=U.copy(e.pathGoal),pathFailed=e.pathFailed}
       return{kind=kind,validCommandAccepted=positive,invalidCommandAccepted=accepted,
        before=old,after=newer}
      end
    ''')
    rows=[]
    for kind in ['scout','siege']:
        p=records['bladder']['profiles'][kind];room=p['rooms'][0]
        gate=next(g for g in p['gateContracts'] if g['id']==room['accessGateId'])
        actual=qa.convert(run(qa.lua_table(l,ORGANS),kind,qa.lua_table(l,room['rallySource']),qa.lua_table(l,gate['tissueAnchorSource'])))
        passed=actual['validCommandAccepted'] and not actual['invalidCommandAccepted'] and actual['before']==actual['after']
        rows.append({'status':'PASS' if passed else 'FAIL','actual':actual})
    changed=[k for k,v in before.items() if hashes().get(k)!=v and k not in DRAW_ONLY_MODULES]
    r={'schema':'organ-atlas-invalid-target-preserves-real-order/v1','status':'UNDETERMINED' if changed else 'PASS' if all(x['status']=='PASS' for x in rows) else 'FAIL',
       'cases':rows,'passed':sum(x['status']=='PASS' for x in rows),'total':len(rows),
       'testedModuleHashes':before,'modulesChangedDuringCapture':changed,'nativeEvidence':False}
    write('command-preservation-report.json',r)
    return r


def traffic_save_checks():
    qa=gastric_qa();l=qa.runtime();_,records=contract_records();oracle=MotionOracle(records)
    before=hashes();config=next(c for c in scenario_configs(records) if c['id']=='blood-meeting/liver/siege-siege')
    config['organs']=list(ORGANS);config['restoreTrafficPair']=True
    actual=qa.convert(l.execute(LUA_SCENARIO)(qa.lua_table(l,config)))
    previous={p['id']:p for p in actual['starts']};failures=[];disks=capsules=0
    for p in actual['trace']:
        disks+=1
        if oracle.disk(p,p['kind']) is not True:failures.append({'type':'disk','point':p})
        if p['id'] in previous:
            capsules+=1
            if oracle.capsule(previous[p['id']],p,p['kind']) is not True:failures.append({'type':'capsule','point':p})
        previous[p['id']]=p
    mid=actual.get('midTransitSave');goals={g['id']:g for g in actual['goals']}
    arrivals=[{'id':p['id'],'distanceWorld':math.hypot(p['x']-goals[p['id']]['x'],p['y']-goals[p['id']]['y']),
               'laneMatches':p['lane']==goals[p['id']]['lane']} for p in actual['endpoints']]
    mid_ok=bool(mid and mid['captureStage']=='active-traffic-protocol' and mid['positionError']==0 and
        mid['laneMatches'] and mid['gateMatches'] and mid['ids']==sorted(ORGANS) and
        mid['trafficBefore']['activePairs']>0 and mid['trafficAfter']['activePairs']==mid['trafficBefore']['activePairs'])
    ok=(mid_ok and actual['completed'] and not failures and not actual['spawnErrors'] and
        actual['trafficStats']['activePairs']==0 and actual['trafficStats'].get('expired',0)==0 and
        all(a['distanceWorld']<=.075 and a['laneMatches'] for a in arrivals) and
        actual['save']['positionErrors']==0 and actual['save']['laneErrors']==0)
    changed=[k for k,v in before.items() if hashes().get(k)!=v and k not in DRAW_ONLY_MODULES]
    r={'schema':'organ-atlas-actual-traffic-save-restore/v1','status':'UNDETERMINED' if changed else 'PASS' if ok else 'FAIL',
       'midProtocolSnapshot':mid,'assignedArrivals':arrivals,'geometryFailures':len(failures),
       'firstGeometryFailures':failures[:12],'disksChecked':disks,'capsulesChecked':capsules,
       'completed':actual['completed'],'trafficStats':actual['trafficStats'],
       'nativeEvidence':False,'testedModuleHashes':before,'modulesChangedDuringCapture':changed}
    write('traffic-save-report.json',r)
    write('traces/liver-traffic-save.json',{'config':config,'result':actual,'nativeEvidence':False})
    return r


def urethra_checks():
    qa=gastric_qa();l=qa.runtime();_,records=contract_records();oracle=MotionOracle(records)
    before=hashes();rows=[]
    probe=l.execute(r'''
      local T,W,C,P,K,O=require('war.OrganTrial'),require('war.World'),require('war.Commands'),
       require('war.Path'),require('war.CellCollision'),require('war.OrganBattlefield')
      local s=T.new(73,...)
      return function(kind,x,y,tx,ty)
       s.entities={};s.commands={};W.rebuild(s)
       local e=C.spawn(s,'unit',kind,1,x,y);assert(e,'real bladder rally spawn rejected')
       W.rebuild(s)
       local allowed=O.pointAllowed(s,e,tx,ty,0)
       local direct=P.clear(s,e.x,e.y,tx,ty,1,e.vesselLane,0,e)
       local nx,ny,lane,transit=K.move(s,e,tx,ty,0)
       return{pointAllowed=allowed,directClear=direct,
        start={x=e.x,y=e.y,lane=e.vesselLane,organId=O.organAt(s,e,e.x,e.y)},
        returned={x=nx,y=ny,lane=lane,transit=transit,organId=O.organAt(s,e,nx,ny)}}
      end
    ''',qa.lua_table(l,ORGANS))
    rec=records['bladder'];passage=next(p for p in rec['protectedPassages'] if p['id']=='urine.urethra')
    raw=oracle.LineString(passage['points']).buffer(passage['width']/2,quad_segs=32)
    for kind in ['scout','siege']:
        rally=rec['profiles'][kind]['rooms'][0]['rallySource'];radius=oracle.radius(kind)
        for y in [787,791,795,799,803,807,810]:
            for target_name,target in [('center',[509,y]),('center-outside-radius-overlap',[511+radius/2,y])]:
                actual=qa.convert(probe(kind,2*rally[0],2*rally[1]+512,2*target[0],2*target[1]+512))
                raw_rejected=not oracle.full_disk(oracle.tissues['bladder'],target,radius)
                outside_control=target_name=='center' or (not raw.covers(oracle.Point(target)) and
                                                       oracle.tissues['bladder'].covers(oracle.Point(target)))
                safe=oracle.capsule(actual['start'],actual['returned'],kind)
                passed=raw_rejected and outside_control and safe and not actual['pointAllowed'] and not actual['directClear']
                rows.append({'id':f'{kind}/{target_name}/{y}','status':'PASS' if passed else 'FAIL',
                    'sourceTarget':target,'radiusSource':radius,'actual':actual,
                    'rawFullDiskRejected':raw_rejected,'outsideCenterControlValid':outside_control,
                    'returnedFullCapsuleCovered':safe})
    changed=[k for k,v in before.items() if hashes().get(k)!=v]
    r={'schema':'organ-atlas-urethra-full-disk-rejection/v1',
       'status':'UNDETERMINED' if changed else 'PASS' if all(x['status']=='PASS' for x in rows) else 'FAIL',
       'passed':sum(x['status']=='PASS' for x in rows),'total':len(rows),'cases':rows,
       'testedModuleHashes':before,'modulesChangedDuringCapture':changed,'nativeEvidence':False,
       'sourceGraphUnchanged':sha(GRAPH)==FROZEN_GRAPH,
       'runtimeScope':'Actual all-active OrganTrial + O.pointAllowed / Path.clear / CellCollision.move, exact original urethra centerline and raw tissue.'}
    write('urethra-contract-report.json',r)
    return r


def gastric_delegate_checks():
    qa=gastric_qa();l=qa.runtime();layout=qa.layout_data();oracle=qa.Oracle(layout)
    before=hashes();run=l.execute(qa.LUA_SCENARIO)
    selected=['gate/siege/study.stomach.wall_service.outer/enter',
              'membrane-meeting/study.stomach.wall_service.outer/siege-siege',
              'group/mixed-six-to-central',
              'blood-meeting/study.stomach.wall_service/scout-siege']
    rows=[]
    for c in qa.scenario_configs(layout):
        if c['id'] not in selected:continue
        actual=qa.convert(run(qa.lua_table(l,c)))
        summary=qa.check_actual_trace(actual,oracle);traffic=actual['trafficStats']
        passed=(summary['completed'] and not summary['spawnErrors'] and
            not summary['geometryFailures'] and not summary['exteriorDomainUnverified'] and
            (summary['minimumFrameDiskGapWorld'] is None or summary['minimumFrameDiskGapWorld']>=-1e-6) and
            all(a['distanceToAssignedTargetWorld']<=.075 and a['laneMatchesTarget'] for a in summary['assignedTargetArrivals']) and
            summary['savePassed'] and traffic.get('activePairs',0)==0 and traffic.get('expired',0)==0)
        rows.append({'id':c['id'],'status':'PASS' if passed else 'FAIL',**summary,'trafficStats':traffic})
        write('gastric-delegate-traces/'+c['id'].replace('/','__')+'.json',
              {'nativeEvidence':False,'navigationSubstituted':False,'config':c,'result':actual})
        print(c['id'],rows[-1]['status'],flush=True)
    regressions=qa.regressions();legacy=qa.legacy_signatures()
    baseline=load(BASE/'stomach-playable/qa/baseline.json')
    regression_equal=all(regressions[k]['passed']==v['passed'] and regressions[k]['total']==v['total']
                         for k,v in baseline['regressions'].items())
    legacy_equal=legacy==baseline['legacySignatures']
    # Default/legacy creation must not load the large opt-in dataset.
    no_opt_in_data=l.execute("return package.loaded['war.OrganBattlefieldData']==nil")
    changed=[k for k,v in before.items() if hashes().get(k)!=v]
    r={'schema':'organ-atlas-existing-stomach-delegate/v1',
       'status':'UNDETERMINED' if changed else 'PASS' if len(rows)==len(selected) and all(x['status']=='PASS' for x in rows) and regression_equal and legacy_equal and no_opt_in_data else 'FAIL',
       'cases':rows,'passed':sum(x['status']=='PASS' for x in rows),'total':len(rows),
       'regressions':regressions,'regressionsMatchBaseline':regression_equal,
       'legacySignatures':legacy,'legacySignaturesMatchBaseline':legacy_equal,
       'gastricModeDoesNotLoadOrganDataset':no_opt_in_data,'testedModuleHashes':before,
       'modulesChangedDuringCapture':changed,'nativeEvidence':False,
       'runtimeScope':'Actual accepted GastricTrial / Simulation / Commands / GastricTraffic through new facade hooks; no old evidence overwritten.'}
    write('gastric-delegate-report.json',r)
    return r


def factory_checks():
    qa = gastric_qa();l = qa.runtime();_, records = contract_records()
    oracle = MotionOracle(records)
    before = hashes()
    run = l.execute(r'''
      return function(ids)
       local T,O,W,K,Data=require('war.OrganTrial'),require('war.OrganBattlefield'),
        require('war.World'),require('war.CellCollision'),require('war.OrganBattlefieldData')
       local s=T.new(73,ids);local out={active=O.activeOrgans(s),points={},expected=0,minimumGap=math.huge,
        flag=s.organBattlefieldVersion,edges=#W.vessels(s).edges}
       for _,id in ipairs(out.active)do out.expected=out.expected+math.min(4,#O.organ(id).rooms)end
       local units=K.units(s)
       for i,e in ipairs(units)do out.points[#out.points+1]={id=e.id,kind=e.kind,x=e.x,y=e.y,
        lane=e.vesselLane,organId=O.organAt(s,e,e.x,e.y),productionAllowed=O.pointAllowed(s,e,e.x,e.y,e.vesselLane)}
        for j=i+1,#units do local b=units[j]
         out.minimumGap=math.min(out.minimumGap,math.sqrt((e.x-b.x)^2+(e.y-b.y)^2)-K.radius(e)-K.radius(b))
        end
       end
       out.actual=#units;return out
      end
    ''')
    actual = qa.convert(run(qa.lua_table(l, ORGANS)))
    rows = [{'id': p['id'], 'organId': p.get('organId'),
             'productionAllowed': p['productionAllowed'], 'rawFullDiskAllowed': oracle.disk(p, p['kind'])}
            for p in actual['points']]
    passed = (actual['active'] == sorted(ORGANS) and actual['actual'] == actual['expected'] and
              actual['flag'] == 1 and actual['edges'] == 202 and
              all(r['productionAllowed'] and r['rawFullDiskAllowed'] for r in rows) and
              actual['minimumGap'] >= -1e-6)
    r = {'schema': 'organ-atlas-all-active-factory/v1', 'status': 'PASS' if passed else 'FAIL',
         'nativeEvidence': False, 'actual': actual, 'checks': rows,
         'testedModuleHashes': before, 'modulesChangedDuringCapture':
         [k for k,v in before.items() if hashes().get(k) != v]}
    if r['modulesChangedDuringCapture']: r['status'] = 'UNDETERMINED'
    write('factory-report.json', r)
    return r


def read_only_checks():
    qa = gastric_qa();l = qa.runtime(True);before = hashes()
    run = l.execute(r'''
      return function(ids)
       local T,R,M,Save,A=require('war.OrganTrial'),require('war.Render'),require('war.Motion'),
        require('war.Save'),require('war.OrganAtlasArt')
       local s=T.new(73,ids);local game={state=s,camera={x=1140,y=1580},zoom=.15,
        selection={},fogDisabled=true,started=true,realTime=0,accumulator=0}
       for _,e in ipairs(require('war.CellCollision').units(s))do game.selection[e.id]=true end
       M.reset(game);M.capture(game);R.vg=1;R.font=0
       NVG_CCW=1;NVG_CW=2;NVG_ALIGN_LEFT=1;NVG_ALIGN_RIGHT=2
       local physicalW,physicalH,dpr=1440,900,1
       graphics={GetDPR=function()return dpr end,GetWidth=function()return physicalW end,
        GetHeight=function()return physicalH end}
       local frames={};nvgBeginFrame=function(vg,w,h,ratio)
        frames[#frames+1]={logicalWidth=w,logicalHeight=h,dpr=ratio}
       end
       local snap=Save.snapshot(s);local points={}
       for _,size in ipairs({{1440,900},{1024,768},{844,390},{430,932},{360,780}})do
        for _,ratio in ipairs({1,2,3})do
         dpr=ratio;physicalW,physicalH=size[1]*ratio,size[2]*ratio
         for _,z in ipairs({.085,.115,.149,.15,.18})do
          game.zoom=z;game.realTime=game.realTime+.13
          local cx,cy=game.camera.x,game.camera.y;R.draw(game)
          local px,py=R.project(game,1138.125,1564.875);local x,y=R.unproject(game,px,py)
          points[#points+1]={zoom=z,alpha=A.alpha(z),roundtripError=math.abs(x-1138.125)+math.abs(y-1564.875),
           cameraUnchanged=cx==game.camera.x and cy==game.camera.y}
         end
        end
       end
       return {before=snap,after=Save.snapshot(s),frames=frames,points=points}
      end
    ''')
    try:
        q = qa.convert(run(qa.lua_table(l, ORGANS)))
        frames = [{'logicalWidth':w, 'logicalHeight':h, 'dpr':dpr}
                  for w,h in [(1440,900),(1024,768),(844,390),(430,932),(360,780)]
                  for dpr in [1,2,3] for zoom in [.085,.115,.149,.15,.18]]
        passed = q['before'] == q['after'] and q['frames'] == frames and all(
            p['cameraUnchanged'] and p['roundtripError'] < 1e-8 for p in q['points'])
        r = {'schema':'organ-atlas-render-read-only/v1', 'status':'PASS' if passed else 'FAIL',
             'frames':len(q['frames']), 'exactSnapshotUnchanged':q['before']==q['after'],
             'frameArgumentsMatchLogicalPixelsDpr':q['frames']==frames,
             'projectionChecks':q['points'], 'testedModuleHashes':before,
             'nativeEvidence':False, 'graphicsAPIsMocked':True, 'imageLoadingMocked':True,
             'visualQualityAccepted':False}
    except Exception as e:
        r = {'status':'FAIL','runnerError':str(e),'testedModuleHashes':before,'nativeEvidence':False}
    changed=[k for k,v in before.items() if hashes().get(k)!=v]
    r['modulesChangedDuringCapture']=changed
    if changed:r['status']='UNDETERMINED'
    write('render-read-only-report.json',r)
    return r


def render_compatibility_checks():
    qa=gastric_qa();archived=OUT/'render-before-command-marker.lua'
    expected='d89d60fd435aa0092d49a0b5aa92730beb37607352e43673405b51d32a7747e8'
    candidates=[archived,Path('/tmp/organ-atlas-render-before-readability.lua')]
    baseline=next((p for p in candidates if p.is_file() and sha(p)==expected),None)
    if baseline is None:
        r={'status':'UNDETERMINED','reason':'Exact previously accepted Render source is missing or hash mismatched','nativeEvidence':False}
        write('render-compatibility-report.json',r);return r
    if baseline!=archived:archived.write_bytes(baseline.read_bytes())
    before=hashes()
    def capture(source,mode):
        l=qa.runtime(True)
        R=l.execute(source) if source else l.execute("local r=require('war.Render');return r")
        l.globals().QA_RENDER=R
        l.execute("package.loaded['war.Render']=QA_RENDER")
        run=l.execute(r'''
          return function(mode)
           local R,S,T,K,Save,M=require('war.Render'),require('war.Simulation'),
            require('war.GastricTrial'),require('war.CellCollision'),require('war.Save'),require('war.Motion')
           local s=mode=='gastric'and T.new(73)or S.new(73,'sandbox',4)
           local units=K.units(s);local selected={};local focus
           for _,e in ipairs(units)do if e.faction==1 then selected[e.id]=true;focus=focus or e end end
           assert(focus,'production state has no player cell')
           local game={state=s,camera={x=focus.x,y=focus.y},zoom=.15,selection=selected,
            fogDisabled=true,started=true,realTime=2.125,accumulator=0}
           M.reset(game);M.capture(game);R.vg=1;R.font=0
           NVG_CCW=1;NVG_CW=2;NVG_ALIGN_LEFT=1;NVG_ALIGN_RIGHT=2
           local pw,ph,dpr=1440,900,1
           graphics={GetDPR=function()return dpr end,GetWidth=function()return pw end,GetHeight=function()return ph end}
           local calls={};local names={'nvgPathWinding','nvgLineCap','nvgLineJoin','nvgIntersectScissor',
            'nvgBeginPath','nvgMoveTo','nvgLineTo','nvgBezierTo','nvgQuadTo','nvgClosePath','nvgCircle',
            'nvgArc','nvgEllipse','nvgRect','nvgStrokeWidth','nvgFillColor','nvgStrokeColor','nvgFillPaint',
            'nvgFontFaceId','nvgFontSize','nvgTextAlign','nvgText','nvgSave','nvgRestore','nvgTranslate',
            'nvgRotate','nvgScale','nvgTransform','nvgBeginFrame','nvgEndFrame','nvgFill','nvgStroke',
            'nvgGlobalAlpha','nvgShapeAntiAlias','nvgScissor'}
           for _,name in ipairs(names)do local label=name;_G[name]=function(...)
            calls[#calls+1]={name=label,args={...}}
           end end
           local rows={};local snap=Save.snapshot(s)
           for _,size in ipairs({{1440,900},{430,932}})do for _,ratio in ipairs({1,2,3})do
            dpr=ratio;pw,ph=size[1]*ratio,size[2]*ratio
            for _,z in ipairs({.085,.115,.149,.15,.18})do
             game.zoom=z;calls={};R.draw(game)
             rows[#rows+1]={mode=mode,width=size[1],height=size[2],dpr=dpr,zoom=z,calls=calls}
            end
           end end
           return{rows=rows,before=snap,after=Save.snapshot(s)}
          end
        ''')
        return qa.convert(run(mode))
    rows=[]
    for mode in ['default','gastric']:
        old,new=capture(archived.read_text(),mode),capture(None,mode)
        for a,b in zip(old['rows'],new['rows']):
            old_bytes=json.dumps(a['calls'],sort_keys=True,separators=(',',':')).encode()
            new_bytes=json.dumps(b['calls'],sort_keys=True,separators=(',',':')).encode()
            rows.append({'mode':mode,'logicalSize':[a['width'],a['height']],'dpr':a['dpr'],'zoom':a['zoom'],
                'oldCallsSha256':hashlib.sha256(old_bytes).hexdigest(),'currentCallsSha256':hashlib.sha256(new_bytes).hexdigest(),
                'actualDrawCallsEqual':a['calls']==b['calls'],'callCount':len(b['calls']),
                'oldSnapshotUnchanged':old['before']==old['after'],'currentSnapshotUnchanged':new['before']==new['after']})
    changed=[k for k,v in before.items() if hashes().get(k)!=v]
    passed=all(x['actualDrawCallsEqual'] and x['oldSnapshotUnchanged'] and x['currentSnapshotUnchanged'] for x in rows)
    r={'schema':'organ-atlas-render-legacy-selected-cell-compatibility/v1',
       'status':'UNDETERMINED' if changed else 'PASS' if passed else 'FAIL',
       'previousRenderSha256':expected,'currentRenderSha256':before['Render.lua'],
       'passed':sum(x['actualDrawCallsEqual'] for x in rows),'total':len(rows),'frames':rows,
       'testedModuleHashes':before,'modulesChangedDuringCapture':changed,'nativeEvidence':False,
       'scope':'Actual complete Render.draw from hash-verified previous source versus current module, selected production player cells in default and old gastric mode; only graphics APIs mocked. No navigation module replaced.'}
    write('render-compatibility-report.json',r);return r


def resource_checks():
    qa = gastric_qa();l = qa.runtime(True);before=hashes()
    q = qa.convert(l.execute(r'''
      local A,Data,G=require('war.OrganAtlasArt'),require('war.OrganAtlasArtData'),require('war.GastricArt')
      local counter,alive,errors,created=0,{}, {},0
      local function count()local n=0;for _ in pairs(alive)do n=n+1 end;return n end
      nvgCreateImage=function(vg,path,flags)
       counter=counter+1;created=created+1;alive[counter]={context=vg,path=path};return counter
      end
      nvgDeleteImage=function(vg,id)
       if not alive[id]then errors[#errors+1]='deleted missing handle'
       elseif alive[id].context~=vg then errors[#errors+1]='deleted wrong context handle'
       else alive[id]=nil end
      end
      local maxAlive,rows=0,{}
      for i=1,25 do
       local world,ui={},{}
       A.prepare(world);A.prepare(ui);G.prepare(world);G.prepare(ui)
       local n=count();maxAlive=math.max(maxAlive,n)
       A.prepare(world);A.prepare(ui);G.prepare(world);G.prepare(ui)
       if count()~=n then errors[#errors+1]='prepare duplicated cached image'end
       A.release(world);A.release(world);G.release(world);G.release(world)
       if count()~=#Data.order+1 then errors[#errors+1]='world release changed UI handles'end
       A.release(ui);A.release(ui);G.release(ui);G.release(ui)
       if count()~=0 then errors[#errors+1]='cycle leaked image'end
       rows[#rows+1]={cycle=i,remaining=count(),stats=A.stats()}
      end
      -- Exercise the real mode-entry hooks, not only the image module itself.
      local R,H,Sim=require('war.Render'),require('war.HUD'),require('war.Simulation')
      local world,ui={},{};R.vg=world
      require('urhox-libs/UI').GetNVGContext=function()return ui end
      local ordinary=Sim.new(73,'sandbox',4)
      R.prepare(ordinary);H.prepareBattlefield(ordinary)
      local defaultAllocatesNoTrialImages=count()==0
      local defaultDoesNotLoadLargeDataset=package.loaded['war.OrganBattlefieldData']==nil
      local gastric=require('war.GastricTrial').new(73)
      local ids={};for _,id in ipairs(Data.order)do ids[#ids+1]=id end;ids[#ids+1]='stomach'
      local organ=require('war.OrganTrial').new(73,ids)
      local modeRows={}
      for i=1,25 do
       R.prepare(ordinary);H.prepareBattlefield(ordinary)
       local ordinaryCount=count()
       R.prepare(gastric);H.prepareBattlefield(gastric)
       local gastricCount=count()
       R.prepare(organ);H.prepareBattlefield(organ)
       local organCount=count();maxAlive=math.max(maxAlive,organCount)
       local oldCreated=created;R.prepare(organ);H.prepareBattlefield(organ)
       local idempotent=oldCreated==created
       R.prepare(ordinary);H.prepareBattlefield(ordinary)
       local released=count()
       if ordinaryCount~=0 or gastricCount~=2 or organCount~=2*(#Data.order+1)or released~=0 or not idempotent then errors[#errors+1]='actual mode lifecycle contract failed'end
       modeRows[#modeRows+1]={cycle=i,ordinary=ordinaryCount,gastric=gastricCount,
        organ=organCount,afterReturnToOrdinary=released,idempotent=idempotent}
      end
      local context={};local missing=Data.order[1];local draws=0
      nvgCreateImage=function(vg,path)
       if path==Data.organs[missing].resource then return 0 end
       counter=counter+1;alive[counter]={context=vg,path=path};return counter
      end
      nvgFill=function()draws=draws+1 end
      A.prepare(context)
      local R={vg=context,project=function(g,x,y)return x,y end}
      local result=A.draw(R,{zoom=.15},{anatomyVersion=4,organBattlefieldVersion=1,
       organBattlefieldIds=Data.order})
      A.release(context)
      return {cycles=rows,manifest=Data,created=created,maxAlive=maxAlive,errors=errors,
       actualModeCycles=modeRows,defaultAllocatesNoTrialImages=defaultAllocatesNoTrialImages,
       defaultDoesNotLoadLargeDataset=defaultDoesNotLoadLargeDataset,
       remaining=count(),partialFailureFallsBack=result==false and draws==0,
       alpha={low=A.alpha(.085),half=A.alpha(.115),before=A.alpha(.149999),full=A.alpha(.15),high=A.alpha(.18)}}
    '''))
    resources=[];_,records=contract_records()
    for name,d in q['manifest']['organs'].items():
        p=ROOT/'assets'/d['resource']
        resources.append({'organId':name,'resource':d['resource'],'sourceBox':d['sourceBox'],
                          'sourceBoxMatchesGeometry':d['sourceBox']==records[name]['sourceBox'],
                          'exists':p.is_file(),'sha256':sha(p) if p.is_file() else None})
    gastric_path=ROOT/'assets/image/anatomy-reference/vascular-study/stomach-playable/battlefield.png'
    resources.append({'organId':'stomach','resource':str(gastric_path.relative_to(ROOT/'assets')),
        'sourceBox':[464,448,644,628],'exists':gastric_path.is_file(),
        'sourceBoxMatchesGeometry':True,
        'sha256':sha(gastric_path) if gastric_path.is_file() else None})
    from PIL import Image
    for row in resources:
        path=ROOT/'assets'/row['resource']
        try:
            with Image.open(path) as im:
                im.load();w,h=im.size;b=row['sourceBox']
                row.update({'pixelWidth':w,'pixelHeight':h,'decodedPng':im.format=='PNG',
                    'registeredAspectRatioMatches':abs(w*(b[3]-b[1])-h*(b[2]-b[0]))<=1,
                    'rgbaBaseBytesPerContext':w*h*4})
        except Exception as error:
            row.update({'decodedPng':False,'decodeError':str(error)})
    ok=(not q['errors'] and q['remaining']==0 and q['partialFailureFallsBack'] and
        q['defaultAllocatesNoTrialImages'] and q['defaultDoesNotLoadLargeDataset'] and
        q['maxAlive']==2*(len(q['manifest']['order'])+1) and
        all(x['exists'] and x['decodedPng'] and x['registeredAspectRatioMatches'] and x['sourceBoxMatchesGeometry'] for x in resources) and
        q['alpha']['low']==0 and q['alpha']['full']==1 and q['alpha']['high']==1)
    r={'schema':'organ-atlas-image-lifecycle-contract/v1','status':'PASS' if ok else 'FAIL',
       'nativeEvidence':False,'imageLoadingMocked':True,'offlinePillowAssetDecodeVerified':True,
       'nativeAssetDecodeVerified':False,
       'actualAPI':'war.OrganAtlasArt + delegated war.GastricArt prepare/release; actual OrganAtlasArt draw/alpha fallback',
       'resources':resources,'registryEvidence':q,'testedModuleHashes':before,
       'modulesChangedDuringCapture':[k for k,v in before.items() if hashes().get(k)!=v],
       'decodedRgbaBaseBytesPerContext':sum(x.get('rgbaBaseBytesPerContext',0) for x in resources),
       'limitations':['Mock image handles and Pillow decoding do not prove native GPU memory, NanoVG image loading or frame timing. RGBA byte totals are a theoretical base level, not measured GPU allocation.']}
    if r['modulesChangedDuringCapture']:r['status']='UNDETERMINED'
    write('resource-contract-report.json',r)
    return r


def summary_report():
    names=['production-report.json','collision-contract-report.json','urethra-contract-report.json',
           'gastric-delegate-report.json','factory-report.json','traffic-save-report.json',
           'command-preservation-report.json',
           'render-read-only-report.json','render-compatibility-report.json','resource-contract-report.json']
    current=hashes();items=[];evidence={}
    for name in names:
        path=OUT/name
        if not path.is_file():
            items.append({'file':name,'status':'UNDETERMINED','reason':'Missing evidence'});continue
        d=load(path);evidence[name]=d
        tested=d.get('testedModuleHashes',{})
        skip=set() if name in ['render-read-only-report.json','render-compatibility-report.json','resource-contract-report.json'] else DRAW_ONLY_MODULES
        stale=[k for k,v in tested.items() if k not in skip and current.get(k)!=v]
        items.append({'file':name,'sha256':sha(path),'status':'UNDETERMINED' if stale else d['status'],
            'passed':d.get('passed'),'total':d.get('total'),'staleDependencyHashes':stale,
            'nativeEvidence':False})
    m=matrix();production=evidence.get('production-report.json',{});delegate=evidence.get('gastric-delegate-report.json',{})
    for organ in m['organs']:
        owner=organ['organId']
        cases=[c for c in production.get('cases',[]) if c['id'].startswith(owner+'/')]
        if owner=='stomach':organ['actualProductionMovementStatus']=delegate.get('status','UNDETERMINED')
        else:organ['actualProductionMovementStatus']='PASS' if cases and all(c['status']=='PASS' for c in cases) and production.get('status')=='PASS' else 'UNDETERMINED'
        organ['actualCases']=len(cases);organ['nativeStatus']='UNDETERMINED'
    m['status']='PASS' if all(o['actualProductionMovementStatus']=='PASS' for o in m['organs']) else 'UNDETERMINED'
    m['acceptanceScope']='Actual production geometry and movement only; native/art quality remains separately unconfirmed.'
    write('acceptance-matrix.json',m)
    actual_pass=all(x['status']=='PASS' for x in items)
    r={'schema':'organ-atlas-independent-qa-summary/v1','status':'PASS' if actual_pass else 'FAIL' if any(x['status']=='FAIL' for x in items) else 'UNDETERMINED',
       'acceptanceScope':'Independent raw geometry + actual offline production Lua APIs; no native acceptance.',
       'nativeStatus':'UNDETERMINED','nativeEvidence':False,'navigationSubstituted':False,
       'sourceGraphSha256':sha(GRAPH),'sourceGraphUnchanged':sha(GRAPH)==FROZEN_GRAPH,
       'sourceReferenceSha256':sha(ROOT/'assets/image/anatomy-reference/reference.png'),
       'contractSha256':sha(CONTRACT),'runtimeDataSha256':sha(BASE/'organ-atlas/runtime-data.json'),
       'testedModuleHashes':current,'qaScriptSha256':sha(Path(__file__)),'reports':items,
       'evidenceVersionScope':{
           'productionMovementEvidencePreserved':True,
           'productionMovementReportSha256':sha(OUT/'production-report.json') if (OUT/'production-report.json').is_file() else None,
           'productionMovementRenderSha256':production.get('testedModuleHashes',{}).get('Render.lua'),
           'currentDisplayRenderSha256':current.get('Render.lua'),
           'drawOnlyDifferencesFromMovementCapture':[
               {'module':k,'movementCaptureSha256':v,'currentSha256':current.get(k)}
               for k,v in production.get('testedModuleHashes',{}).items()
               if k in DRAW_ONLY_MODULES and current.get(k)!=v],
           'movementDependencyHashesUnchanged':all(current.get(k)==v for k,v in production.get('testedModuleHashes',{}).items() if k not in DRAW_ONLY_MODULES),
           'currentDisplayReports':['render-read-only-report.json','render-compatibility-report.json','resource-contract-report.json'],
           'currentReadOnlyRenderFrames':evidence.get('render-read-only-report.json',{}).get('frames'),
           'legacyDrawComparisonsPassed':evidence.get('render-compatibility-report.json',{}).get('passed'),
           'legacyDrawComparisonsTotal':evidence.get('render-compatibility-report.json',{}).get('total'),
           'interpretation':'The 140 movement captures keep their original module hashes. Display-only command markers and decoded-texture readiness/size metadata are checked by fresh actual Render readonly/DPR, exact legacy draw-call comparison, loading guards and mode/resource checks. Navigation dependency hashes remain unchanged; old captures are not relabeled.'},
       'movement':{'passed':production.get('passed'),'total':production.get('total'),
                   'fullDisksChecked':sum(c.get('disksChecked',0) for c in production.get('cases',[])),
                   'fullCapsulesChecked':sum(c.get('capsulesChecked',0) for c in production.get('cases',[])),
                   'geometryFailures':sum(c.get('geometryFailures',0) for c in production.get('cases',[])),
                   'unverifiedDomainPoints':sum(c.get('unverifiedDomainPoints',0) for c in production.get('cases',[]))},
       'resolvedObservedDefects':[{'issue':'Liver siege/siege reciprocal yield ended at the correct XY in tissue instead of its commanded blood lane.',
           'control':'liver-blood-meeting-control-failure.json','verification':'production-report.json + traffic-save-report.json'},
           {'issue':'Bladder lower neck urethra must be excluded even if the cell center is outside but its radius overlaps the lumen.',
            'verification':'urethra-contract-report.json + actual urine.urethra negative commands'}],
       'previewPolicyEvidence':{'statusCommand':'python3 /tmp/body-life-preview.py',
           'nativeRunEvidence':'../native/summary.json',
           'scope':'This suite neither starts nor controls preview; separately authorized native measurements keep their own input hashes.'},
       'limitations':['This offline suite does not verify native edge seams, image decoding by NanoVG, real GPU allocation or P95 full-frame timing; native asset dimensions have separate run-004 evidence.',
           'Pillow image decoding and bounded mock handle ownership certify file/logic contracts only.',
           'Authoring 72 checks do not independently replace the stomach delegate or actual movement evidence.',
           'The opt-in atlas never migrates existing positions or changes Save version 9.']}
    if not r['sourceGraphUnchanged']:r['status']='FAIL'
    write('summary.json',r)
    return r


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--geometry', action='store_true')
    parser.add_argument('--matrix', action='store_true')
    parser.add_argument('--production', action='store_true')
    parser.add_argument('--case')
    parser.add_argument('--factory',action='store_true')
    parser.add_argument('--read-only',action='store_true')
    parser.add_argument('--resources',action='store_true')
    parser.add_argument('--collision',action='store_true')
    parser.add_argument('--gastric-delegate',action='store_true')
    parser.add_argument('--urethra',action='store_true')
    parser.add_argument('--traffic-save',action='store_true')
    parser.add_argument('--summary',action='store_true')
    parser.add_argument('--command-preservation',action='store_true')
    parser.add_argument('--render-compatibility',action='store_true')
    args = parser.parse_args()
    interface_requirements()
    m = matrix()
    for enabled,check in [(args.factory,factory_checks),(args.read_only,read_only_checks),
                          (args.resources,resource_checks),(args.collision,collision_checks),
                          (args.gastric_delegate,gastric_delegate_checks),(args.urethra,urethra_checks),
                          (args.traffic_save,traffic_save_checks),(args.summary,summary_report),
                          (args.command_preservation,command_preservation_checks),
                          (args.render_compatibility,render_compatibility_checks)]:
        if enabled:
            r=check();print(r['status'],flush=True);return 1 if r['status']=='FAIL' else 0
    if args.production:
        r = production_checks(args.case)
        print(r['status'], r.get('passed'), '/', r.get('total'), flush=True)
        return 1 if r['status'] == 'FAIL' else 0
    if args.geometry:
        r = geometry_checks()
        print(r['status'], r.get('passed'), '/', len(r.get('cases', [])),
              'unavailable', len(r.get('unavailableRooms', [])), flush=True)
        return 1 if r['status'] == 'FAIL' else 0
    r = interface_status()
    print(json.dumps({'status': r['status'], 'organsInMatrix': len(m['organs']),
                      'runtimeOrganCount': r['runtimeOrganCount'],
                      'hooks': r['integrationHooksObserved']}, ensure_ascii=False), flush=True)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
