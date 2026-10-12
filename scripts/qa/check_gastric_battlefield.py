"""Independent QA of the production gastric battlefield, never attachForTest.

Baseline:
  PYTHONPATH=/tmp/reference-map-tools python3.13 scripts/qa/check_gastric_battlefield.py --baseline

Production checks are enabled only after the production module/data interfaces
are available. This script owns only stomach-playable/qa output files.
Native preview must remain stopped; no browser replay is a native gameplay PASS.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import time

from lupa.lua54 import LuaRuntime

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT/'docs/body-life/vascular-art-study/stomach-playable/qa'
GRAPH = ROOT/'docs/body-life/vascular-art-study/final-reference-data.json'
FROZEN_GRAPH_SHA = '3890744e2fcaf9e9907c85513e170e479f67b7fbb1fbf06385ac02bd80e8550c'
REGRESSIONS = ['ReferenceAcceptance', 'BattleHUDAcceptance', 'ZoomAcceptance']


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def convert(value):
    if hasattr(value, 'items'):
        fields = dict(value.items())
        if fields and set(fields) == set(range(1, len(fields)+1)):
            return [convert(fields[i]) for i in range(1, len(fields)+1)]
        return {str(k): convert(v) for k, v in fields.items()}
    return value


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True)+'\n')


def runtime(render_mocks=False):
    l = LuaRuntime(unpack_returned_tuples=True)
    l.execute("package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={};print=function()end")
    if render_mocks:
        # Only image loading and graphics APIs are mocked. Production geometry,
        # spawning, movement, commands, collision and pathfinding are unchanged.
        l.execute("""
          for _,name in ipairs({'nvgPathWinding','nvgLineCap','nvgLineJoin',
            'nvgIntersectScissor','nvgBeginPath','nvgMoveTo','nvgLineTo','nvgBezierTo',
            'nvgQuadTo','nvgClosePath','nvgCircle','nvgArc','nvgEllipse','nvgRect',
            'nvgStrokeWidth','nvgFillColor','nvgStrokeColor','nvgFillPaint',
            'nvgFontFaceId','nvgFontSize','nvgTextAlign','nvgText','nvgSave',
            'nvgRestore','nvgTranslate','nvgRotate','nvgScale','nvgTransform',
            'nvgBeginFrame','nvgEndFrame','nvgFill','nvgStroke','nvgGlobalAlpha',
            'nvgShapeAntiAlias','nvgDeleteImage','nvgScissor'})do _G[name]=function()end end
          nvgRGBA=function(r,g,b,a)return{r,g,b,a}end
          nvgCreateImage=function()return 0 end
          nvgLinearGradient=function()return{}end;nvgRadialGradient=function()return{}end
          nvgImagePattern=function()return{}end;nvgImagePatternTinted=function()return{}end
          NVG_SOLID=1;NVG_HOLE=2;NVG_ROUND=1;NVG_IMAGE_GENERATE_MIPMAPS=1
          NVG_ALIGN_CENTER=1;NVG_ALIGN_MIDDLE=2
        """)
    return l


def module_hashes():
    names = ['World', 'Path', 'Commands', 'Workers', 'CellCollision', 'Save',
        'Render', 'View', 'Vessels', 'Simulation', 'ReferenceMap', 'ReferenceVessels',
        'GastricTrial', 'GastricTraffic', 'GastricArt', 'ReferenceArt']
    names += ['GastricBattlefield', 'GastricBattlefieldData']
    return {name+'.lua': sha(ROOT/'scripts/war'/f'{name}.lua') for name in names
        if (ROOT/'scripts/war'/f'{name}.lua').is_file()}


def regressions():
    reports = {}
    for name in REGRESSIONS:
        started = time.perf_counter()
        l = runtime(True)
        try:
            result = convert(l.execute("return require('war."+name+"').run()"))
        except Exception as error:
            result = {'passed': 0, 'total': None, 'runnerError': str(error), 'results': []}
        result['elapsedOfflineSeconds'] = round(time.perf_counter()-started, 3)
        reports[name] = result
        print(name, result['passed'], '/', result['total'], flush=True)
    return reports


def legacy_signatures():
    l = runtime()
    return convert(l.execute("""
      local S,W,P,Save,U,D=require('war.Simulation'),require('war.World'),
        require('war.Path'),require('war.Save'),require('war.Util'),require('war.Data')
      local out={}
      for _,version in ipairs({1,2,3,4})do
        local s=S.new(73,'sandbox',version)
        local snap=Save.snapshot(s);local restored=Save.restore(snap)
        local q={anatomyVersion=s.anatomyVersion,saveVersion=snap.version,
          mapWidth=D.width(s),mapHeight=D.height(s),rng=s.rng,
          sourceStarts=U.copy(W.starts(s)),netVersion=W.vessels(s).version,
          edges=#W.vessels(s).edges,gates=#W.vessels(s).gates,entities={},
          restorePositionErrors=0,restoreLaneErrors=0,restoreVersion=restored.anatomyVersion}
        local ids={};for id in pairs(s.entities)do ids[#ids+1]=id end;table.sort(ids)
        for _,id in ipairs(ids)do local e=s.entities[id];local f=restored.entities[id]
          q.entities[#q.entities+1]={id=id,kind=e.kind,x=e.x,y=e.y,lane=e.vesselLane}
          q.restorePositionErrors=q.restorePositionErrors+
            (not f and 1 or math.abs(e.x-f.x)+math.abs(e.y-f.y))
          q.restoreLaneErrors=q.restoreLaneErrors+(f and f.vesselLane==e.vesselLane and 0 or 1)
        end
        out[#out+1]=q
      end
      return out
    """))


def baseline():
    assert sha(GRAPH) == FROZEN_GRAPH_SHA
    before = module_hashes()
    report = {'schema': 'gastric-battlefield-baseline/v1', 'nativeEvidence': False,
        'productionNavigationSubstituted': False, 'sourceGraphSha256': sha(GRAPH),
        'testedModuleHashes': before, 'regressions': regressions(),
        'legacySignatures': legacy_signatures()}
    after = module_hashes()
    report['modulesChangedDuringCapture'] = [k for k in before if before[k] != after.get(k)]
    report['sourceGraphUnchanged'] = sha(GRAPH) == FROZEN_GRAPH_SHA
    report['limitations'] = ['Regression renderer APIs are no-op mocks; not native rendering/performance evidence.',
        'No new gastric production behavior is accepted by the baseline.']
    path = OUT/'baseline.json'
    assert not path.exists(), 'Preserve existing baseline; pass a different output path for a fresh authorized baseline.'
    write_json(path, report)
    print(path, flush=True)


def interface_status():
    module = ROOT/'scripts/war/GastricBattlefield.lua'
    data = ROOT/'scripts/war/GastricBattlefieldData.lua'
    geometry = ROOT/'docs/body-life/vascular-art-study/stomach-playable/geometry.json'
    missing = [str(p.relative_to(ROOT)) for p in [module, data, geometry] if not p.is_file()]
    if missing:
        report = {'status': 'WAITING_FOR_PRODUCTION_INTERFACE', 'missing': missing,
            'nativeEvidence': False, 'navigationAccepted': False}
    else:
        l = runtime()
        exports = convert(l.execute("local r={};for k,v in pairs(require('war.GastricBattlefield'))do r[k]=type(v)end;return r"))
        report = {'status': 'PRODUCTION_INTERFACE_PRESENT_TESTS_PENDING', 'exports': exports,
            'testedModuleHashes': module_hashes(), 'nativeEvidence': False,
            'navigationAccepted': False}
    write_json(OUT/'interface-status.json', report)
    print(json.dumps(report, ensure_ascii=False), flush=True)


class Oracle:
    """Independent full disks/capsules from un-eroded authoring polygons.

    G's cached eroded polygons and grid are deliberately not used here. Blood
    is a separate plane; food geometry may occlude it visually but cannot turn
    a true lumen into tissue. Only named gates/shared graph nodes join planes.
    """
    def __init__(self, layout):
        from shapely.geometry import Polygon, Point, LineString
        from shapely.ops import unary_union
        self.Point, self.LineString, self.union = Point, LineString, unary_union
        self.layout = layout
        self.tissue = self.rings(layout['tissueWalkableRings'])
        self.food = self.rings(layout['foodRings'])
        self.walls = self.rings(layout['wallRings'])
        self.outer = self.rings(layout['outerRings'])
        self.blood = {}
        self.lines = {}
        for lane, b in layout['bloodLanes']['siege'].items():
            line = LineString(b.get('samples') or b['points'])
            self.lines[int(lane)] = line
            self.blood[int(lane)] = line.buffer(b['lumenWidthSource']/2, quad_segs=32)
        self.gates = layout['gateContracts']['siege']
        self.tolerance = 2e-6
        self.disk_cache = {}

    def rings(self, polygons):
        from shapely.geometry import Polygon
        return self.union([Polygon(p['outer'], p.get('holes', [])) for p in polygons])

    @staticmethod
    def source(point):
        return point['x']*.5, (point['y']-512)*.5

    @staticmethod
    def radius(kind):
        return {'scout': 14, 'siege': 34, 'worker': 19, 'virus': 18,
            'spear': 22, 'archer': 22, 'heavy': 27, 'wolf': 19, 'shadow': 17}[kind]/64

    def domain(self, lane):
        return self.tissue if not lane else self.blood.get(lane)

    def disk(self, p, kind):
        transit = p.get('transit')
        transit_key = tuple(sorted(transit.items())) if isinstance(transit, dict) else ()
        key = (p['x'],p['y'],p['lane'],kind,transit_key)
        if key in self.disk_cache:return self.disk_cache[key]
        xy = self.source(p)
        domain = self.domain(p['lane'])
        transit = p.get('transit')
        if isinstance(transit, dict):
            for g in self.gates:
                if g['id'] == transit.get('gateId') and p['lane'] in [transit.get('fromLane'), transit.get('toLane')]:
                    domain = self.union([self.tissue, self.blood[g['laneIndex']],
                        self.Point(*g['wallSource']).buffer(g['radiusSource'], quad_segs=64)])
        if domain is None:
            return None  # Exterior lanes need the exported actual source curve.
        r = self.radius(kind)
        q = self.Point(*xy)
        result = domain.covers(q) and domain.boundary.distance(q)>=r-self.tolerance
        if len(self.disk_cache)>8192:self.disk_cache.clear()
        self.disk_cache[key]=result
        return result

    def capsule(self, a, b, kind):
        aa, bb = self.source(a), self.source(b)
        r = self.radius(kind)
        if aa==bb and a['lane']==b['lane']:return self.disk(b,kind)
        shape = self.LineString([aa, bb]).buffer(r, quad_segs=32)
        la, lb = a['lane'], b['lane']
        active = b.get('transit') or a.get('transit')
        if isinstance(active, dict):
            for g in self.gates:
                if g['id'] == active.get('gateId') and la in [active.get('fromLane'), active.get('toLane')] and lb in [active.get('fromLane'), active.get('toLane')]:
                    region = self.union([self.tissue, self.blood[g['laneIndex']],
                        self.Point(*g['wallSource']).buffer(g['radiusSource'], quad_segs=64)])
                    return region.buffer(self.tolerance).covers(shape)
            return False
        if la == lb:
            domain = self.domain(la)
            return None if domain is None else domain.buffer(self.tolerance).covers(shape)
        # Exact authored gateways; a blood/tissue transition must use one of
        # these throats. Same-tissue sweeps can never exploit an entire lumen.
        if not la or not lb:
            lane = la or lb
            blood = self.blood.get(lane)
            if blood is None:
                return False
            for gate in self.gates:
                if gate['laneIndex'] != lane:
                    continue
                throat = self.Point(*gate['wallSource']).buffer(gate['radiusSource'], quad_segs=64)
                region = self.union([self.tissue, blood, throat])
                if throat.intersects(shape) and region.buffer(self.tolerance).covers(shape):
                    return True
            return False
        # Two blood lanes join only at a truly shared named graph endpoint.
        for junction in self.layout['junctionContracts']['siege']:
            if {junction['aLane'], junction['bLane']} == {la, lb}:
                return self.union([self.blood[la], self.blood[lb]]).buffer(self.tolerance).covers(shape)
        return False


def layout_data():
    return json.loads((OUT.parent/'layout.json').read_text())


def geometry_checks():
    """Component contract checks, not a gameplay/native acceptance."""
    layout = layout_data()
    oracle = Oracle(layout)
    l = runtime()
    l.execute("G=require('war.GastricBattlefield');s={anatomyVersion=4,gastricBattlefieldVersion=1}")
    point = l.eval("function(kind,x,y,lane)return G.pointAllowed(s,{kind=kind,vesselLane=lane},x,y,lane)end")
    sweep = l.eval("function(kind,x,y,tx,ty,a,b)return G.sweep(s,{kind=kind,vesselLane=a},x,y,tx,ty,a,b)end")
    route = l.eval("function(kind,x,y,lane,tx,ty,targetLane)return G.route(s,{kind=kind,x=x,y=y,vesselLane=lane},tx,ty,targetLane)end")
    checks, failures = [], []
    def add(name, passed, detail):
        row = {'id': name, 'passed': bool(passed), 'details': detail}
        checks.append(row)
        if not passed:
            failures.append(row)
    graph = json.loads(GRAPH.read_text())
    original = {g['id']: g for g in graph['gates']}
    frozen = []
    for g in layout['gates']:
        src = original[g['id']]
        frozen.append({'id': g['id'], 'unchanged': all(g[k] == src[k] for k in
            ['pipeCenterSource','wallSource','tissueTargetSource','radius','edgeId'])})
    add('frozen-source-and-original-gates', sha(GRAPH) == FROZEN_GRAPH_SHA and all(r['unchanged'] for r in frozen), frozen)
    add('production-finalized-network', l.execute("return #G.net(s).edges") == 202,
        {'edges': l.execute("return #G.net(s).edges"), 'sourceReplacement': False})
    centers = []
    for room in layout['rooms']:
        for kind in ['scout', 'siege']:
            for name in ['rallySource', 'approachSource']:
                x,y=room[name]
                p={'x':2*x, 'y':2*y+512, 'lane':0}
                centers.append({'room':room['id'],'kind':kind,'position':name,
                    'runtimeAllowed':bool(point(kind,p['x'],p['y'],0)),
                    'fullDiskCovered':oracle.disk(p,kind)})
    add('all-room-rallies-and-approaches-full-disk', all(r['runtimeAllowed'] and r['fullDiskCovered'] for r in centers), centers)
    route_rows=[]
    for kind in ['scout','siege']:
        for a in layout['rooms']:
            for b in layout['rooms']:
                if a['id']==b['id']:
                    continue
                start={'x':a['centerSource'][0]*2,'y':a['centerSource'][1]*2+512,'lane':0}
                goal={'x':b['centerSource'][0]*2,'y':b['centerSource'][1]*2+512,'lane':0}
                raw=route(kind,start['x'],start['y'],0,goal['x'],goal['y'],0)
                if isinstance(raw, tuple):
                    result, reason=raw
                else:
                    result, reason=raw, None
                path=convert(result) if result else []
                previous=start;bad=[]
                for i,p in enumerate(path):
                    runtime_sweep=sweep(kind,previous['x'],previous['y'],p['x'],p['y'],previous['lane'],p['lane'])
                    runtime_sweep=runtime_sweep[0] if isinstance(runtime_sweep, tuple) else runtime_sweep
                    independent=oracle.capsule(previous,p,kind)
                    if not runtime_sweep or independent is False:
                        bad.append({'index':i,'from':previous,'to':p,'runtime':bool(runtime_sweep),'fullDiskCapsule':independent})
                    previous=p
                exact=bool(path and abs(path[-1]['x']-goal['x'])+abs(path[-1]['y']-goal['y'])<1e-8 and path[-1]['lane']==0)
                route_rows.append({'kind':kind,'from':a['id'],'to':b['id'],'points':len(path),
                    'routeAccepted':bool(result),'reason':reason,'exactEndpoint':exact,'invalidCapsules':bad,
                    'path':path})
    add('sixty-exact-room-routes-independent-capsules', all(r['routeAccepted'] and r['exactEndpoint'] and not r['invalidCapsules'] for r in route_rows),
        [{k:v for k,v in r.items() if k!='path'} for r in route_rows])
    gates=[]
    for kind in ['scout','siege']:
        for g in layout['gateContracts'][kind]:
            a={'x':2*g['pipeAnchorSource'][0],'y':2*g['pipeAnchorSource'][1]+512,'lane':g['laneIndex']}
            b={'x':2*g['tissueAnchorSource'][0],'y':2*g['tissueAnchorSource'][1]+512,'lane':0}
            for start,end in [(a,b),(b,a)]:
                raw=sweep(kind,start['x'],start['y'],end['x'],end['y'],start['lane'],end['lane'])
                accepted=raw[0] if isinstance(raw,tuple) else raw
                gates.append({'id':g['id'],'kind':kind,'fromLane':start['lane'],'toLane':end['lane'],
                    'runtimeAllowed':bool(accepted),'fullDiskCapsule':oracle.capsule(start,end,kind)})
    add('all-five-gates-bidirectional-full-disk-contract', all(g['runtimeAllowed'] and g['fullDiskCapsule'] for g in gates), gates)
    # Non-membrane wall crossings: independent geometry finds precise capsule
    # probes rather than trusting production's own cached floor classifications.
    probes=[]
    from shapely.geometry import LineString
    gate_regions=oracle.union([oracle.Point(*g['wallSource']).buffer(3) for g in oracle.gates])
    for lane,b in layout['bloodLanes']['siege'].items():
        line=oracle.lines[int(lane)]
        for i in range(1,40):
            p=line.interpolate(line.length*i/40)
            if gate_regions.covers(p):continue
            p0=line.interpolate(max(0,line.length*i/40-.05));p1=line.interpolate(min(line.length,line.length*i/40+.05))
            dx,dy=p1.x-p0.x,p1.y-p0.y;length=(dx*dx+dy*dy)**.5
            if not length:continue
            for side in [-1,1]:
                out=(p.x-dy/length*side*2.3,p.y+dx/length*side*2.3)
                start={'x':p.x*2,'y':p.y*2+512,'lane':int(lane)}
                end={'x':out[0]*2,'y':out[1]*2+512,'lane':0}
                if not oracle.disk(end,'scout'):continue
                raw=sweep('scout',start['x'],start['y'],end['x'],end['y'],int(lane),0)
                ok=raw[0] if isinstance(raw,tuple)else raw
                probes.append({'lane':int(lane),'from':start,'to':end,'runtimeAllowed':bool(ok)})
    add('ordinary-blood-walls-sealed', bool(probes) and not any(p['runtimeAllowed'] for p in probes), probes)
    wall_cases=[]
    # Interior, food and exterior boundaries: test the entire disk at a center
    # only .1source from each true raw boundary and inward in otherwise floor.
    for name,barrier in [('interior',oracle.walls),('food',oracle.food),('outer',oracle.outer.boundary)]:
        boundary=barrier.boundary if name!='outer' else barrier
        lines=list(boundary.geoms) if hasattr(boundary,'geoms') else [boundary]
        for curve in lines:
            if curve.length<.2:continue
            for t in [.12,.33,.57,.81]:
                p=curve.interpolate(curve.length*t);a=curve.interpolate(max(0,curve.length*t-.01));b=curve.interpolate(min(curve.length,curve.length*t+.01))
                dx,dy=b.x-a.x,b.y-a.y;length=(dx*dx+dy*dy)**.5
                if not length:continue
                for sign in [-1,1]:
                    center=(p.x-sign*dy/length*.1,p.y+sign*dx/length*.1)
                    if not oracle.tissue.contains(oracle.Point(*center)):continue
                    for kind in ['scout','siege','worker','virus','heavy','archer','spear','wolf','shadow']:
                        q={'x':center[0]*2,'y':center[1]*2+512,'lane':0}
                        covered=oracle.disk(q,kind);allowed=bool(point(kind,q['x'],q['y'],0))
                        if covered is False:wall_cases.append({'barrier':name,'kind':kind,'point':q,'runtimeAllowed':allowed})
    add('near-wall-all-nine-cell-radii-rejected', bool(wall_cases) and not any(p['runtimeAllowed'] for p in wall_cases), wall_cases)
    # Static two-siege geometric certificate is independently checked, but is
    # not sufficient evidence for production collision/pathfinding meeting.
    passing=[]
    for room in layout['rooms']:
        tracks=room['doorPassingCertificate']['tracks'];segments=[];covered=[]
        for t in tracks:
            a={'x':t['startSource'][0]*2,'y':t['startSource'][1]*2+512,'lane':0};b={'x':t['endSource'][0]*2,'y':t['endSource'][1]*2+512,'lane':0}
            covered.append(oracle.capsule(a,b,'siege'));segments.append(LineString([t['startSource'],t['endSource']]))
        clearance=segments[0].distance(segments[1])-2*oracle.radius('siege')
        passing.append({'room':room['id'],'sweepsCovered':covered,'minimumWholeTrackDiskSeparationSource':clearance,'actualProductionMeetingVerified':False})
    add('room-door-static-full-disk-passing-certificates', all(all(r['sweepsCovered']) and r['minimumWholeTrackDiskSeparationSource']>=0 for r in passing), passing)
    report={'schema':'gastric-component-geometry-qa/v1','nativeEvidence':False,
        'productionGameplayAccepted':False,'navigationSubstituted':False,
        'runtimeScope':'production G / Vessels component contracts; real per-frame Commands movement is tested separately',
        'sourceGraphSha256':sha(GRAPH),'layoutSha256':sha(OUT.parent/'layout.json'),
        'testedModuleHashes':module_hashes(),'checks':checks,'passed':len(checks)-len(failures),
        'total':len(checks),'failures':failures,'limitations':['Static full-displacement gate and door sweeps do not prove real per-frame movement or meeting.','Native preview stopped; native rendering and performance remain UNDETERMINED.']}
    write_json(OUT/'geometry-report.json',report)
    write_json(OUT/'component-routes.json',{'nativeEvidence':False,'routes':route_rows})
    print('component geometry',report['passed'],'/',report['total'],flush=True)
    return report


LUA_SCENARIO = r'''
local T,S,C,W,K,P,G,Save,M=require('war.GastricTrial'),require('war.Simulation'),
 require('war.Commands'),require('war.World'),require('war.CellCollision'),
 require('war.Path'),require('war.GastricBattlefield'),require('war.Save'),require('war.Motion')
local function position(e,phase)
 return {id=e.id,kind=e.kind,x=e.x,y=e.y,lane=e.vesselLane or 0,
  phase=phase,pathFailed=e.pathFailed or false,transit=e.gastricTransit and
   {gateId=e.gastricTransit.gateId,fromLane=e.gastricTransit.fromLane,toLane=e.gastricTransit.toLane} or nil}
end
return function(config)
 local s=T.new(73)
 -- Isolate only scenario actors, keeping the exact production trial terrain,
 -- enabled state, vessel network, commands, routes, collisions and step hook.
 s.entities={};s.commands={};W.rebuild(s)
 local result={id=config.id,trace={},frames={},starts={},commands={},goals={},arrival={},spawnErrors={}}
 local actors={}
 for i,a in ipairs(config.actors) do
  local e=C.spawn(s,'unit',a.kind,1,a.x,a.y)
  if not e then result.spawnErrors[#result.spawnErrors+1]=i
  else
   actors[i]=e;result.starts[#result.starts+1]=position(e,'spawn')
   if a.lane~=nil and e.vesselLane~=a.lane then result.spawnErrors[#result.spawnErrors+1]={index=i,wrongLane=e.vesselLane,expected=a.lane} end
  end
 end
 W.rebuild(s)
 local original=M.record
 M.record=function(e)
  if s.entities[e.id]==e then local row=position(e,'substep');row.time=s.time;row.tick=s.tick
   result.trace[#result.trace+1]=row
  end
  original(e)
 end
 local function command(a,i)
  if not actors[i] then return end
  local row={kind='move',faction=1,ids={actors[i].id},x=a.tx,y=a.ty}
  local accepted=C.execute(s,row)
  local order=actors[i].orders[1]
  result.commands[#result.commands+1]={id=actors[i].id,accepted=accepted==true,
   requested={x=a.tx,y=a.ty},order=order and {x=order.x,y=order.y,lane=order.lane} or nil}
  result.goals[#result.goals+1]={id=actors[i].id,x=order and order.x or a.tx,y=order and order.y or a.ty,lane=a.targetLane}
 end
 if config.group then
  local ids={};for _,e in ipairs(actors)do ids[#ids+1]=e.id end
  local accepted=C.execute(s,{kind='move',faction=1,ids=ids,x=config.group.x,y=config.group.y})
  result.groupAccepted=accepted==true
  for i,e in ipairs(actors) do local o=e.orders[1]
   result.commands[#result.commands+1]={id=e.id,accepted=accepted==true,requested={x=config.group.x,y=config.group.y},
    order=o and{x=o.x,y=o.y,lane=o.lane}or nil}
   result.goals[#result.goals+1]={id=e.id,x=o and o.x or config.group.x,y=o and o.y or config.group.y,lane=config.group.lane}
  end
 else for i,a in ipairs(config.actors) do if a.tx then command(a,i) end end end
 local elapsed,maxTime,dt=0,config.maxTime or 120,config.dt or require('war.Data').STEP
 local minGap=math.huge;local completed=false
 while elapsed<maxTime and #result.spawnErrors==0 do
  S.step(s,dt);elapsed=elapsed+dt
  local frame={time=s.time,points={}}
  for _,e in ipairs(actors)do frame.points[#frame.points+1]=position(e,'frame')end
  result.frames[#result.frames+1]=frame
  for i,e in ipairs(actors)do for j=i+1,#actors do local b=actors[j]
   local gap=math.sqrt((e.x-b.x)^2+(e.y-b.y)^2)-K.radius(e)-K.radius(b)
   minGap=math.min(minGap,gap)
  end end
  completed=true
  for _,e in ipairs(actors)do if #e.orders>0 then completed=false end end
  if require('war.GastricTraffic').stats(s).activePairs>0 then completed=false end
  if completed and not config.observeIdle then break end
 end
 M.record=original
 result.elapsed=elapsed;result.completed=completed;result.minimumFrameDiskGapWorld=minGap<math.huge and minGap or nil
 result.endpoints={};for _,e in ipairs(actors)do
  result.endpoints[#result.endpoints+1]=position(e,'end')
  result.arrival[#result.arrival+1]={id=e.id,ordersRemaining=#e.orders,
   pathFailed=e.pathFailed or false,routeReason=e.gastricRouteReason}
 end
 local snap=Save.snapshot(s);local ok,restored=pcall(Save.restore,snap)
 result.save={version=snap.version,flag=snap.gastricBattlefieldVersion,restored=ok,
  restoreError=not ok and tostring(restored)or nil,positionErrors=0,laneErrors=0}
 if ok then
  result.save.restoredFlag=restored.gastricBattlefieldVersion
  result.save.restoredNetworkEdges=#W.vessels(restored).edges
  for _,e in ipairs(actors)do local f=restored.entities[e.id]
   if not f then result.save.positionErrors=result.save.positionErrors+1
   else result.save.positionErrors=result.save.positionErrors+math.abs(e.x-f.x)+math.abs(e.y-f.y)
    if f.vesselLane~=e.vesselLane then result.save.laneErrors=result.save.laneErrors+1 end
   end
  end
 end
 result.trafficStats=require('war.GastricTraffic').stats(s)
 result.trafficInspect=require('war.GastricTraffic').inspect and require('war.GastricTraffic').inspect(s)or nil
 result.stateFlag=s.gastricBattlefieldVersion;result.networkEdges=#W.vessels(s).edges
 return result
end
'''


def lua_table(l, value):
    if isinstance(value, dict):
        return l.table_from({k:lua_table(l,v) for k,v in value.items()})
    if isinstance(value, list):
        return l.table_from([lua_table(l,v) for v in value])
    return value


def check_actual_trace(result, oracle):
    failures=[];by_id={p['id']:p for p in result['starts']}
    radius_kind={p['id']:p['kind'] for p in result['starts']}
    disk_count,capsule_count,exterior_unknown=0,0,0
    events=[]
    # Motion.record contains every Commands move plus the final collision
    # relaxation endpoint. Frame endpoints additionally verify all idle actors.
    for p in result['trace']:
        previous=by_id.get(p['id'])
        kind=radius_kind[p['id']]
        disk=oracle.disk(p,kind);disk_count+=1
        if disk is False:failures.append({'type':'full-disk','point':p})
        elif disk is None:exterior_unknown+=1
        if previous:
            capsule=oracle.capsule(previous,p,kind);capsule_count+=1
            if capsule is False:failures.append({'type':'swept-capsule','from':previous,'to':p})
            elif capsule is None:exterior_unknown+=1
            if previous['lane']!=p['lane']:events.append({'id':p['id'],'fromLane':previous['lane'],'toLane':p['lane'],'time':p['time'],'point':p})
        by_id[p['id']]=p
    for frame in result['frames']:
        for p in frame['points']:
            disk=oracle.disk(p,p['kind']);disk_count+=1
            if disk is False:failures.append({'type':'frame-full-disk','point':p,'time':frame['time']})
    arrivals=[];goals={p['id']:p for p in result['goals']}
    for p in result['endpoints']:
        g=goals.get(p['id'])
        if g:
            gap=((p['x']-g['x'])**2+(p['y']-g['y'])**2)**.5
            arrivals.append({'id':p['id'],'distanceToAssignedTargetWorld':gap,
                'laneMatchesTarget':g.get('lane') is None or p['lane']==g['lane']})
    save=result['save']
    return {'completed':result['completed'],'spawnErrors':result['spawnErrors'],
        'disksChecked':disk_count,'capsulesChecked':capsule_count,'exteriorDomainUnverified':exterior_unknown,
        'geometryFailures':len(failures),'firstGeometryFailures':failures[:20],
        'minimumFrameDiskGapWorld':result.get('minimumFrameDiskGapWorld'),
        'assignedTargetArrivals':arrivals,'transitionEvents':events,
        'savePassed':save['restored'] and save.get('restoredFlag')==1 and save.get('restoredNetworkEdges')==202
            and save['positionErrors']<1e-8 and save['laneErrors']==0}


def scenario_configs(layout):
    def world(p):return [p[0]*2,p[1]*2+512]
    def actor(kind,start,end,lane=0,target=0):
        a,b=world(start),world(end)
        return {'kind':kind,'x':a[0],'y':a[1],'tx':b[0],'ty':b[1],'lane':lane,'targetLane':target}
    out=[]
    rooms={r['id']:r for r in layout['rooms']}
    # A shared real rally in each disconnected tissue component, reached from
    # blood by explicit membranes. Cross-component commands intentionally use
    # actual vessel routing rather than a fabricated tissue bridge.
    rally=rooms['south_middle']['centerSource']
    for kind in ['scout','siege']:
        for r in layout['rooms']:
            if r['id']!='south_middle':
                out.append({'id':f'room/{kind}/rally-to-{r["id"]}','actors':[actor(kind,rally,r['centerSource'])]})
                out.append({'id':f'room/{kind}/{r["id"]}-to-rally','actors':[actor(kind,r['centerSource'],rally)]})
            out.append({'id':f'room/{kind}/{r["id"]}-door','actors':[actor(kind,r['rallySource'],r['approachSource'])]})
    for kind in ['scout','siege','worker']:
        for g in layout['gateContracts']['scout' if kind=='scout' else 'siege']:
            for enter in [False,True]:
                a,b=g['pipeAnchorSource'],g['tissueAnchorSource'];la,lb=g['laneIndex'],0
                if enter:a,b=b,a;la,lb=lb,la
                out.append({'id':f'gate/{kind}/{g["id"]}/{"enter"if enter else"exit"}',
                    'actors':[actor(kind,a,b,la,lb)],'maxTime':20})
    for r in layout['rooms']:
        tracks=r['doorPassingCertificate']['tracks']
        for kinds in [('scout','siege'),('siege','siege')]:
            actors=[actor(kind,t['startSource'],t['endSource'])for kind,t in zip(kinds,tracks)]
            out.append({'id':f'meeting/{r["id"]}/{kinds[0]}-{kinds[1]}','actors':actors,'maxTime':30})
    # Reciprocal requests through the same true fixed membrane are harder than
    # a wide room door: 2 siege cannot fit side-by-side in the original lumen.
    for g in layout['gateContracts']['siege']:
        for kinds in [('scout','siege'),('siege','siege')]:
            out.append({'id':f'membrane-meeting/{g["id"]}/{kinds[0]}-{kinds[1]}',
                'actors':[actor(kinds[0],g['pipeAnchorSource'],g['tissueAnchorSource'],g['laneIndex'],0),
                    actor(kinds[1],g['tissueAnchorSource'],g['pipeAnchorSource'],0,g['laneIndex'])],
                'maxTime':300})
    for lane,b in layout['bloodLanes']['siege'].items():
        from shapely.geometry import LineString
        line=LineString(b.get('samples') or b['points']);pa=line.interpolate(.2*line.length);pb=line.interpolate(.8*line.length)
        for kinds in [('scout','siege'),('siege','siege')]:
            out.append({'id':f'blood-meeting/{b["edgeId"]}/{kinds[0]}-{kinds[1]}',
                'actors':[actor(kinds[0],[pa.x,pa.y],[pb.x,pb.y],int(lane),int(lane)),
                    actor(kinds[1],[pb.x,pb.y],[pa.x,pa.y],int(lane),int(lane))],'maxTime':300})
    for kinds in [('scout','siege'),('siege','siege')]:
        for left,right in [('southwest','south_middle'),('northwest','central')]:
            a,b=rooms[left]['centerSource'],rooms[right]['centerSource']
            out.append({'id':f'room-exchange/{left}-{right}/{kinds[0]}-{kinds[1]}',
                'actors':[actor(kinds[0],a,b),actor(kinds[1],b,a)],'maxTime':300})
    for target in ['south_middle','central']:
        start_rooms=layout['rooms'];actors=[]
        for i,r in enumerate(start_rooms):
            aa=world(r['centerSource']);actors.append({'kind':['siege','scout','worker'][i%3],'x':aa[0],'y':aa[1],'lane':0})
        target_xy=world(rooms[target]['centerSource'])
        out.append({'id':'group/mixed-six-to-'+target,'actors':actors,'group':{'x':target_xy[0],'y':target_xy[1],'lane':0},'maxTime':240})
    oracle=Oracle(layout)
    box=layout['sourceBox']
    from shapely.geometry import box as make_box
    food_only=oracle.food.intersection(make_box(*box)).difference(oracle.union(list(oracle.blood.values())).buffer(1))
    food_target=food_only.representative_point()
    for kind in ['scout','siege']:
        out.append({'id':f'negative/{kind}/food-target','expectReject':True,
            'actors':[actor(kind,rooms['south_middle']['centerSource'],[food_target.x,food_target.y])],
            'maxTime':2,'observeIdle':True})
    a=world(rooms['west_tail']['centerSource']);b=world(rooms['south_middle']['centerSource'])
    out.append({'id':'group/single-siege-avoids-idle-siege','idleMustStay':True,
        'actors':[{'kind':'siege','x':a[0],'y':a[1],'tx':b[0],'ty':b[1],'lane':0,'targetLane':0},
            {'kind':'siege','x':b[0],'y':b[1],'lane':0}], 'maxTime':240})
    for q in out:
        if q['id'].startswith('blood-meeting/study.stomach.wall_service'):
            q['maxTime']=420
        if q['id'].startswith('room/'):
            q.setdefault('maxTime',300)
    return out


def projection_checks():
    l=runtime();project=l.eval("function(z,w,h,x,y) return require('war.View').project({zoom=z,camera={x=1140,y=1580}},w,h,x,y) end")
    unproject=l.eval("function(z,w,h,x,y) return require('war.View').unproject({zoom=z,camera={x=1140,y=1580}},w,h,x,y) end")
    rows=[]
    for z in [.085,.115,.15,.18]:
        for w,h in [(1440,900),(1024,768),(844,390),(430,932),(360,780)]:
            for dpr in [1,2,3]:
                x,y=1138.125,1564.875;sx,sy=project(z,w,h,x,y);rx,ry=unproject(z,w,h,sx,sy)
                rows.append({'zoom':z,'logicalSize':[w,h],'dpr':dpr,'physicalSize':[w*dpr,h*dpr],
                    'sourcePixelsToLogicalPixels':64*z,'logicalProjection':[sx,sy],
                    'physicalProjection':[sx*dpr,sy*dpr],'roundtripWorldError':abs(rx-x)+abs(ry-y)})
    return rows


def production_checks(ids=None, include_regressions=True):
    before=module_hashes();layout=layout_data();oracle=Oracle(layout)
    l=runtime();run=l.execute(LUA_SCENARIO)
    configs=scenario_configs(layout)
    if ids:configs=[q for q in configs if any(s in q['id'] for s in ids)]
    rows=[];OUT.mkdir(parents=True,exist_ok=True)
    for config in configs:
        started=time.perf_counter()
        try:
            result=convert(run(lua_table(l,config)))
            summary=check_actual_trace(result,oracle)
            gap=summary['minimumFrameDiskGapWorld']
            passed=(summary['completed'] and not summary['spawnErrors'] and not summary['geometryFailures']
                and not summary['exteriorDomainUnverified'] and (gap is None or gap>=-.000001)
                and all(a['distanceToAssignedTargetWorld']<=.75+1e-6 and a['laneMatchesTarget']for a in summary['assignedTargetArrivals'])
                and summary['savePassed'])
            if config.get('expectReject'):
                starts={p['id']:p for p in result['starts']}
                stayed=all(abs(p['x']-starts[p['id']]['x'])+abs(p['y']-starts[p['id']]['y'])<1e-8 for p in result['endpoints'])
                rejected=all(not c['accepted'] and not c.get('order')for c in result['commands'])
                passed=rejected and stayed and not summary['geometryFailures'] and summary['savePassed']
                summary['exactInvalidTargetRejected']=rejected;summary['unitsStayedAtOriginalPositions']=stayed
            if config.get('idleMustStay'):
                starts={p['id']:p for p in result['starts']}
                idle_ids=[result['starts'][i]['id']for i,a in enumerate(config['actors'])if not a.get('tx')]
                idle_stayed=all(abs(p['x']-starts[p['id']]['x'])+abs(p['y']-starts[p['id']]['y'])<1e-8 for p in result['endpoints']if p['id']in idle_ids)
                summary['unselectedIdleUnitsStayed']=idle_stayed;passed=passed and idle_stayed
            summary['trafficStats']=result.get('trafficStats',{})
            passed=passed and summary['trafficStats'].get('activePairs',0)==0 and summary['trafficStats'].get('expired',0)==0
            row={'id':config['id'],'passed':passed,'elapsedOfflineSeconds':round(time.perf_counter()-started,3),**summary}
            write_json(OUT/'traces'/f'{config["id"].replace("/","__")}.json',{
                'schema':'gastric-production-lua-trace/v1','nativeEvidence':False,
                'navigationSubstituted':False,'configuration':config,'result':result})
        except Exception as error:
            row={'id':config['id'],'passed':False,'runnerError':str(error),
                'elapsedOfflineSeconds':round(time.perf_counter()-started,3)}
        rows.append(row);print(row['id'], 'PASS'if row['passed']else'FAIL',flush=True)
    after=module_hashes();changed=[k for k in before if before[k]!=after.get(k)]
    projection=projection_checks()
    reg=regressions()if include_regressions else {}
    current_legacy=legacy_signatures()if include_regressions else []
    baseline=json.loads((OUT/'baseline.json').read_text())
    legacy_equal=current_legacy==baseline['legacySignatures']if include_regressions else None
    new_regression_failures=[]
    for name,result in reg.items():
        old=baseline['regressions'][name]
        if result['passed']!=old['passed'] or result['total']!=old['total']:
            new_regression_failures.append(name)
    report={'schema':'gastric-production-gameplay-qa/v1','nativeEvidence':False,
        'navigationSubstituted':False,'runtimeScope':'actual production GastricTrial.new and Simulation.step; actual Commands/Path/CellCollision/Workers; Motion.record is observed only',
        'sourceGraphSha256':sha(GRAPH),'sourceGraphUnchanged':sha(GRAPH)==FROZEN_GRAPH_SHA,
        'layoutSha256':sha(OUT.parent/'layout.json'),'testedModuleHashes':before,
        'modulesChangedDuringCapture':changed,'passed':sum(r['passed']for r in rows),'total':len(rows),'cases':rows,
        'regressions':reg,'newRegressionFailures':new_regression_failures,'legacySignatures':current_legacy,
        'legacySignaturesEqualBaseline':legacy_equal,'projection':projection,
        'projectionPassed':all(r['roundtripWorldError']<1e-8 for r in projection),
        'limitations':['Only this opt-in gastric trial is tested; no rollout to existing game/save.','Native preview remains stopped. Native renderer, visual edge seams and frame time are UNDETERMINED.','A test run during runtime edits is provisional until all tested module hashes are stable.']}
    report['status']='OFFLINE_PRODUCTION_LUA_PASS'if all(r['passed']for r in rows) and not changed and not new_regression_failures and legacy_equal is not False and report['projectionPassed'] and report['sourceGraphUnchanged'] else'FAIL_OR_PROVISIONAL'
    write_json(OUT/'production-report.json',report)
    print(report['status'],report['passed'],'/',report['total'],flush=True)
    return report



def contract_checks():
    layout=layout_data();oracle=Oracle(layout);l=runtime()
    probe=l.execute(r'''
      local T,W,C,P,K,G=require('war.GastricTrial'),require('war.World'),
       require('war.Commands'),require('war.Path'),require('war.CellCollision'),require('war.GastricBattlefield')
      local s=T.new(73)
      return function(kind,x,y,tx,ty,fromLane,toLane)
       s.entities={};s.commands={};W.rebuild(s)
       local e=C.spawn(s,'unit',kind,1,x,y)
       if not e then return{spawned=false}end
       W.rebuild(s)
       local clear=P.clear(s,x,y,tx,ty,1,fromLane,toLane,e)
       local nx,ny,lane,transit=K.move(s,e,tx,ty,toLane)
       return{spawned=true,spawn={x=e.x,y=e.y,lane=e.vesselLane},
        directClear=clear,movement={x=nx,y=ny,lane=lane,transit=transit}}
      end
    ''')
    candidates=[]
    for wall in layout['wallPaths']:
        samples=wall.get('samples')
        if not samples or len(samples)<3:continue
        for i in [len(samples)//4,len(samples)//2,3*len(samples)//4]:
            x,y=samples[i];a,b=samples[max(0,i-1)],samples[min(len(samples)-1,i+1)]
            dx,dy=b[0]-a[0],b[1]-a[1];size=(dx*dx+dy*dy)**.5
            if not size:continue
            start={'x':2*(x-dy/size*1.8),'y':2*(y+dx/size*1.8)+512,'lane':0}
            end={'x':2*(x+dy/size*1.8),'y':2*(y-dx/size*1.8)+512,'lane':0}
            if oracle.disk(start,'siege') and oracle.disk(end,'siege') and not oracle.capsule(start,end,'siege'):
                candidates.append((wall['id'],start,end))
    rows=[]
    for wall,a,b in candidates:
        for kind in ['scout','siege','worker','virus','heavy','spear','archer','wolf','shadow']:
            result=convert(probe(kind,a['x'],a['y'],b['x'],b['y'],0,0))
            moved=result.get('movement')
            independently_safe=bool(moved and oracle.capsule(result['spawn'],moved,kind))
            rows.append({'wall':wall,'kind':kind,'start':a,'attemptedTarget':b,
                'attemptedDistanceWorld':((b['x']-a['x'])**2+(b['y']-a['y'])**2)**.5,
                'actualCollisionResult':result,'returnedSweepIndependentlyCovered':independently_safe,
                'passed':result['spawned'] and not result['directClear'] and independently_safe})
    report={'schema':'gastric-production-collision-contracts/v1','nativeEvidence':False,
        'runtimeScope':'actual opt-in GastricTrial spawn, Path.clear and CellCollision.move APIs; explicit isolated large-displacement collision contract, not full Simulation step',
        'passed':sum(q['passed']for q in rows),'total':len(rows),'results':rows,
        'sourceGraphUnchanged':sha(GRAPH)==FROZEN_GRAPH_SHA,'testedModuleHashes':module_hashes(),
        'status':'OFFLINE_COLLISION_CONTRACT_PASS'if rows and all(q['passed']for q in rows)else'FAIL'}
    write_json(OUT/'collision-contract-report.json',report)
    print('full-displacement collision contracts',report['passed'],'/',report['total'],flush=True)
    return report



def read_only_checks():
    l=runtime(True)
    raw=l.execute(r'''
      local T,R,M,Save,V=require('war.GastricTrial'),require('war.Render'),require('war.Motion'),require('war.Save'),require('war.View')
      local s=T.new(73);local game={state=s,camera={x=1140,y=1580},zoom=.15,
       selection={},fogDisabled=true,started=true,realTime=0,accumulator=0}
      M.reset(game);M.capture(game);R.vg=1;R.font=0
      NVG_CCW=1;NVG_CW=2;NVG_ALIGN_LEFT=1;NVG_ALIGN_RIGHT=2
      local physicalW,physicalH,dpr=1440,900,1
      graphics={GetDPR=function()return dpr end,GetWidth=function()return physicalW end,GetHeight=function()return physicalH end}
      local frames={};nvgBeginFrame=function(vg,w,h,pixelRatio)frames[#frames+1]={logicalWidth=w,logicalHeight=h,dpr=pixelRatio}end
      local before=Save.snapshot(s);local states={}
      for _,size in ipairs({{1440,900},{1024,768},{844,390},{430,932},{360,780}})do
       for _,ratio in ipairs({1,2,3})do
        dpr=ratio;physicalW,physicalH=size[1]*ratio,size[2]*ratio
        for _,z in ipairs({.085,.115,.15,.18})do
         game.zoom=z;game.realTime=game.realTime+.13
         local oldX,oldY=game.camera.x,game.camera.y
         R.draw(game)
         local px,py=R.project(game,1138.125,1564.875);local x,y=R.unproject(game,px,py)
         states[#states+1]={zoom=z,roundtripError=math.abs(x-1138.125)+math.abs(y-1564.875),
          cameraUnchanged=oldX==game.camera.x and oldY==game.camera.y}
        end
       end
      end
      return{before=before,after=Save.snapshot(s),frames=frames,states=states,
       rng=s.rng,simulationTime=s.time,tick=s.tick}
    ''')
    q=convert(raw)
    expected=[{'logicalWidth':w,'logicalHeight':h,'dpr':dpr}
        for w,h in [(1440,900),(1024,768),(844,390),(430,932),(360,780)]
        for dpr in [1,2,3]for z in [.085,.115,.15,.18]]
    report={'schema':'gastric-render-read-only-qa/v1','nativeEvidence':False,
        'graphicsAPIsMocked':True,'imageLoadingMocked':True,'visualQualityAccepted':False,
        'runtimeScope':'actual production Render.draw, View, Motion, World, Save; only NanoVG image and draw API calls mocked',
        'testedFrames':len(q['frames']),'actualNanoVGFrameArguments':q['frames'],
        'projectionChecks':q['states'],'exactSnapshotUnchanged':q['before']==q['after'],
        'frameArgumentsMatchLogicalPixelsDpr':q['frames']==expected,
        'rngUnchanged':q['before']['rng']==q['after']['rng'],
        'simulationTimeUnchanged':q['before']['time']==q['after']['time'],
        'ticksUnchanged':q['before']['tick']==q['after']['tick'],
        'testedModuleHashes':module_hashes(),
        'limitations':['Graphics/image no-ops cannot prove visual asset loading, native seams, frame rate or image-handle lifecycle.','Native preview remains stopped.']}
    report['passed']=report['exactSnapshotUnchanged']and report['frameArgumentsMatchLogicalPixelsDpr']and all(t['roundtripError']<1e-8 and t['cameraUnchanged']for t in report['projectionChecks'])
    write_json(OUT/'render-read-only-report.json',report)
    print('actual Render read-only / DPR',report['passed'],report['testedFrames'],'frames',flush=True)
    return report


def transit_restore_checks():
    l=runtime();raw=l.execute(r'''
      local T,C,S,W,G,Save,D=require('war.GastricTrial'),require('war.Commands'),require('war.Simulation'),
       require('war.World'),require('war.GastricBattlefield'),require('war.Save'),require('war.Data')
      local rows={}
      for _,kind in ipairs({'scout','siege'})do
       for _,g in ipairs(G.data.gateContracts[kind])do
        for _,enter in ipairs({false,true})do
         local s=T.new(73);s.entities={};s.commands={};W.rebuild(s)
         local a,b=g.pipeAnchorSource,g.tissueAnchorSource;local targetLane=0
         if enter then a,b=b,a;targetLane=g.laneIndex end
         local e=C.spawn(s,'unit',kind,1,a[1]*2,a[2]*2+512);W.rebuild(s)
         C.execute(s,{kind='move',ids={e.id},x=b[1]*2,y=b[2]*2+512,lane=targetLane})
         local captured=false
         for i=1,400 do S.step(s,D.STEP);if e.gastricTransit then captured=true;break end end
         local row={id=g.id,kind=kind,enter=enter,capturedTransit=captured}
         if captured then
          local snap=Save.snapshot(s);local restored=Save.restore(snap);local f=restored.entities[e.id]
          row.exactPositionRestored=e.x==f.x and e.y==f.y and e.vesselLane==f.vesselLane
          row.transitIdRestored=f.gastricTransit and f.gastricTransit.gateId==e.gastricTransit.gateId
          row.trace={{x=f.x,y=f.y,lane=f.vesselLane,kind=f.kind,transit=f.gastricTransit}}
          for i=1,400 do S.step(restored,D.STEP)
           row.trace[#row.trace+1]={x=f.x,y=f.y,lane=f.vesselLane,kind=f.kind,transit=f.gastricTransit}
           if #f.orders==0 then break end
          end
          row.completed=#f.orders==0;row.finalLane=f.vesselLane;row.expectedLane=targetLane
          row.finalTransitCleared=f.gastricTransit==nil
          row.finalDistanceWorld=math.sqrt((f.x-b[1]*2)^2+(f.y-b[2]*2-512)^2)
         end
         rows[#rows+1]=row
        end
       end
      end
      return rows
    ''')
    rows=convert(raw);oracle=Oracle(layout_data())
    for q in rows:
        previous=None;bad=0
        for p in q.get('trace',[]):
            if not oracle.disk(p,p['kind']):bad+=1
            if previous and not oracle.capsule(previous,p,p['kind']):bad+=1
            previous=p
        q['independentGeometryFailures']=bad
        q['passed']=q['capturedTransit']and q['exactPositionRestored']and q['transitIdRestored']and q['completed']and q['finalLane']==q['expectedLane']and q['finalTransitCleared']and not bad
    report={'schema':'gastric-mid-transit-save-qa/v1','nativeEvidence':False,
        'runtimeScope':'actual trial Commands / Simulation.step / Save.snapshot / Save.restore; no geometry or movement substitution',
        'passed':sum(q['passed']for q in rows),'total':len(rows),'cases':rows,'testedModuleHashes':module_hashes()}
    write_json(OUT/'transit-save-report.json',report)
    print('actual mid-transit restore',report['passed'],'/',report['total'],flush=True)
    return report



def traffic_save_checks():
    layout=layout_data();blood=layout['bloodLanes']['siege']['124']
    from shapely.geometry import LineString
    line=LineString(blood.get('samples')or blood['points']);a=line.interpolate(.2*line.length);b=line.interpolate(.8*line.length)
    l=runtime()
    capture=l.execute(r'''
      local T,S,C,W,G,D,Traffic,Save=require('war.GastricTrial'),require('war.Simulation'),require('war.Commands'),
       require('war.World'),require('war.GastricBattlefield'),require('war.Data'),require('war.GastricTraffic'),require('war.Save')
      return function(ax,ay,bx,by)
       local s=T.new(73);s.entities={};W.rebuild(s)
       local e=C.spawn(s,'unit','siege',1,ax,ay);local f=C.spawn(s,'unit','siege',1,bx,by);W.rebuild(s)
       C.execute(s,{kind='move',ids={e.id},x=bx,y=by,lane=124});C.execute(s,{kind='move',ids={f.id},x=ax,y=ay,lane=124})
       local goals={};for _,u in ipairs({e,f})do local o=u.orders[1];goals[#goals+1]={id=u.id,x=o.x,y=o.y,lane=o.lane}end
       local snaps={};local wanted={planning=true,retreat=true,passing=true,clearPriority=true,resumeYielder=true,restorePriority=true}
       for i=1,5000 do
        S.step(s,D.STEP)
        local info=Traffic.inspect(s);local p=info[1]
        if p and wanted[p.phase]and not snaps[p.phase]then snaps[p.phase]=Save.snapshot(s)end
        if(e.gastricTransit or f.gastricTransit)and not snaps.transit then snaps.transit=Save.snapshot(s)end
        if #e.orders==0 and #f.orders==0 and Traffic.stats(s).activePairs==0 then break end
       end
       return{snapshots=snaps,goals=goals}
      end
    ''')
    captured=convert(capture(2*a.x,2*a.y+512,2*b.x,2*b.y+512))
    resume=l.execute(r'''
      local S,D,K,M,Save,Traffic=require('war.Simulation'),require('war.Data'),require('war.CellCollision'),
       require('war.Motion'),require('war.Save'),require('war.GastricTraffic')
      return function(snap)
       local s=Save.restore(snap);local errors=0
       local result={starts={},trace={},frames={},saveCoordinateError=0}
       local function pos(e)return{id=e.id,kind=e.kind,x=e.x,y=e.y,lane=e.vesselLane,transit=e.gastricTransit}end
       for _,e in ipairs(K.units(s))do local original=snap.entities[tostring(e.id)]or snap.entities[e.id]
        result.saveCoordinateError=result.saveCoordinateError+math.abs(e.x-original.x)+math.abs(e.y-original.y)
        result.starts[#result.starts+1]=pos(e)
       end
       local old=M.record
       M.record=function(e)if s.entities[e.id]==e then result.trace[#result.trace+1]=pos(e)end;old(e)end
       for i=1,6500 do S.step(s,D.STEP)
        local frame={points={}};local done=true
        for _,e in ipairs(K.units(s))do frame.points[#frame.points+1]=pos(e);if#e.orders>0 then done=false end end
        result.frames[#result.frames+1]=frame
        if done and Traffic.stats(s).activePairs==0 then result.completed=true;break end
       end
       M.record=old;result.endpoints={}
       for _,e in ipairs(K.units(s))do result.endpoints[#result.endpoints+1]=pos(e)end
       result.traffic=Traffic.stats(s);return result
      end
    ''')
    oracle=Oracle(layout);rows=[]
    for stage in ['planning','retreat','transit','passing','clearPriority','resumeYielder','restorePriority']:
        snap=captured['snapshots'].get(stage)
        if snap is None:
            rows.append({'stage':stage,'passed':False,'captured':False});continue
        q=convert(resume(lua_table(l,snap)));previous={p['id']:p for p in q['starts']};bad=[]
        for p in q['trace']:
            old=previous[p['id']]
            if oracle.disk(p,p['kind'])is not True or oracle.capsule(old,p,p['kind'])is not True:
                bad.append({'from':old,'to':p})
            previous[p['id']]=p
        goals={p['id']:p for p in captured['goals']};arrivals=[]
        for p in q['endpoints']:
            goal=goals[p['id']];arrivals.append({'id':p['id'],'distanceWorld':((p['x']-goal['x'])**2+(p['y']-goal['y'])**2)**.5,'laneMatches':p['lane']==goal['lane']})
        passed=q.get('completed',False)and q['saveCoordinateError']<1e-8 and not bad and all(a['distanceWorld']<.05 and a['laneMatches']for a in arrivals)
        rows.append({'stage':stage,'passed':passed,'captured':True,'saveCoordinateError':q['saveCoordinateError'],
            'completed':q.get('completed',False),'arrivals':arrivals,'geometryFailures':len(bad),
            'firstGeometryFailures':bad[:4],'realSubsteps':len(q['trace']),'traffic':q['traffic']})
    report={'schema':'gastric-independent-traffic-save-qa/v1','nativeEvidence':False,
        'navigationSubstituted':False,'runtimeScope':'actual production reciprocal siege Commands, Simulation.step, Traffic protocol and Save snapshot/restore; actual Motion.record observed only',
        'passed':sum(q['passed']for q in rows),'total':len(rows),'cases':rows,'testedModuleHashes':module_hashes()}
    write_json(OUT/'traffic-save-report.json',report)
    print('independent actual traffic save',report['passed'],'/',report['total'],flush=True)
    return report


def main():
    os.chdir(ROOT)
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--baseline', action='store_true')
    p.add_argument('--geometry', action='store_true')
    p.add_argument('--contracts', action='store_true')
    p.add_argument('--read-only', action='store_true')
    p.add_argument('--transit-save', action='store_true')
    p.add_argument('--traffic-save', action='store_true')
    p.add_argument('--production', action='store_true')
    p.add_argument('--case', action='append', help='Run only cases with this substring')
    p.add_argument('--no-regressions', action='store_true')
    args = p.parse_args()
    if args.baseline:
        baseline()
    elif args.read_only:
        read_only_checks()
    elif args.traffic_save:
        traffic_save_checks()
    elif args.transit_save:
        transit_restore_checks()
    elif args.contracts:
        contract_checks()
    elif args.geometry:
        geometry_checks()
    elif args.production:
        production_checks(args.case, not args.no_regressions)
    else:
        interface_status()


if __name__ == '__main__':
    main()
