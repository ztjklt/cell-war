"""Production unitDepth against an independently built, unexported v8 fixture.

This is a small interface preflight, not final artwork/native acceptance. The
accepted source SVG determines the fixture. No resource, route, state or source
file is changed, and final FullBodyMapArtData must still be checked separately.
"""
from pathlib import Path
import datetime
import hashlib
import json
import os
import sys
import time

for dependency in ['/tmp/reference-map-tools', '/tmp/passage-tools314']:
    if Path(dependency).is_dir():
        sys.path.insert(0, dependency)
from shapely.geometry import LineString, Point
import check_gastric_battlefield as gastric
import check_fullbody_foreground_semantics as semantic

ROOT = Path(__file__).resolve().parents[2]
DOC = ROOT / 'docs/body-life/vascular-art-study/fullbody-015'
OUT = DOC / 'qa/fourth-repair'
GUIDE = DOC / 'bake/fourth-guides/manifest-v8.json'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text())


def line_parts(geometry):
    if geometry.geom_type == 'LineString':
        return [geometry] if geometry.length > 1e-6 else []
    return [part for child in getattr(geometry, 'geoms', [])
            for part in line_parts(child)]


def main():
    os.chdir(ROOT)
    started = time.perf_counter()
    inputs, rows, samples = {}, [], []

    def bind(path):
        value = sha(path)
        inputs[str(path.relative_to(ROOT))] = value
        return value

    def check(name, passed, **facts):
        rows.append(dict(id=name, status='PASS' if passed else 'FAIL', **facts))

    bind(Path(__file__).resolve())
    guide = read(GUIDE); bind(GUIDE)
    svg = ROOT / guide['sharedForegroundSvgPath']
    check('accepted v8 SVG bytes', bind(svg) == guide['sharedForegroundSvgSha256'])
    graph = read(semantic.GRAPH)
    check('202 frozen source curves', bind(semantic.GRAPH) == semantic.GRAPH_SHA and
          len(graph['edges']) == 202)
    geometry = semantic.svg_geometry(svg)
    guarded = geometry.buffer(.025)
    fixture = {}
    for edge in graph['edges']:
        line = LineString(edge['samples']); intervals = []
        for part in line_parts(line.intersection(guarded)):
            a, b = sorted([line.project(Point(part.coords[0])),
                           line.project(Point(part.coords[-1]))])
            if b - a > 1e-5:
                intervals.append(dict(startDistance=a, endDistance=b,
                    sourceStart=list(line.interpolate(a).coords[0]),
                    sourceEnd=list(line.interpolate(b).coords[0]),
                    unitDepth='under-foreground', connectsToForeground=False))
        if intervals:
            fixture[edge['id']] = sorted(intervals, key=lambda item: item['startDistance'])
    check('v8 bounded exclusion leaves 107 visual intervals',
          sum(map(len, fixture.values())) == 107,
          actualIntervalCount=sum(map(len, fixture.values())))
    motion_path = DOC / 'qa/fullbody-motion-report.json'
    motion = read(motion_path); bind(motion_path)
    nav_differences = []
    for path, expected in motion['inputHashes'].items():
        actual = bind(ROOT / path)
        if actual != expected:
            nav_differences.append(dict(path=path, before=expected, after=actual))
    check('970 production cases remain eligible on identical navigation bytes',
          motion['status'] == 'PASS' and motion['passed'] == 970 and
          motion['total'] == 970 and not nav_differences,
          differences=nav_differences, matrixNotRerun=True)
    source_data = ROOT / 'scripts/war/FullBodyMapArtData.lua'; bind(source_data)
    for name in ['FullBodyMapArt', 'FullBodyBattlefield', 'World', 'Vessels', 'Save', 'Util']:
        bind(ROOT / ('scripts/war/' + name + '.lua'))
    lua = gastric.runtime()
    lua.execute(r'''
      local U=require('war.Util')
      QFixture=U.copy(require('war.FullBodyMapArtData'))
      package.loaded['war.FullBodyMapArtData']=QFixture
    ''')
    # Only an in-memory rendering table is substituted. Navigation and the
    # production function under test remain the real modules.
    lua.globals().QFixture.visibility = gastric.lua_table(lua, fixture)
    lua.execute(r'''
      QA=require('war.FullBodyMapArt');QS=require('war.FullBodyBattlefield').new(702)
      QSave=require('war.Save');QU=require('war.Util');QN=require('war.World').vessels(QS)
      QBefore=QSave.snapshot(QS);QSeen=QU.copy(QS.factions[1].visible)
      function qsame(a,b)
        if type(a)~=type(b)then return false end
        if type(a)~='table'then return a==b end
        for k,v in pairs(a)do if not qsame(v,b[k])then return false end end
        for k in pairs(b)do if a[k]==nil then return false end end;return true
      end
      function qdepth(lane,x,y,kind,mode)
        local state=QS
        if mode=='old'then state={anatomyVersion=4,terrainStyle='body-v4'}
        elseif mode=='trial'then state={anatomyVersion=4,organBattlefieldVersion=1,terrainStyle='body-v4'}
        elseif mode=='old-anatomy'then state={anatomyVersion=3,fullbodyBattlefieldVersion=1,terrainStyle='body-v4'}end
        return QA.unitDepth(state,{kind=kind,vesselLane=lane},x,y)
      end
    ''')
    runtime_edges = gastric.convert(lua.eval('QN.edges'))
    by_name = {edge['name']: edge for edge in runtime_edges}
    check('factory retains all 202 production lanes', len(by_name) == 202 and
          set(by_name) == {edge['id'] for edge in graph['edges']})
    depth = lua.eval('qdepth')
    for edge in graph['edges']:
        line = LineString(edge['samples']); lane = by_name[edge['id']]['id']
        intervals = fixture.get(edge['id'], [])
        distances = {line.length * .5}
        for interval in intervals:
            a, b = interval['startDistance'], interval['endDistance']
            guard = min(.0001, (b-a)*.01)
            distances.update([a, b, (a+b)*.5, max(0,a-guard), min(line.length,a+guard),
                              max(0,b-guard), min(line.length,b+guard)])
        for along in sorted(distances):
            point=line.interpolate(along);x,y=point.x*2,point.y*2+512
            expected='under-foreground' if any(i['startDistance'] <= along <=
                        i['endDistance'] for i in intervals) else None
            boundary=any(abs(along-d)<1e-10 for i in intervals
                         for d in [i['startDistance'],i['endDistance']])
            actual=depth(lane,x,y,'scout','fullbody')
            label=f"{edge['id']}:{along:.12f}"
            check('production depth:'+label, actual==expected or boundary,
                  sourceDistance=along, expected=expected, actual=actual,
                  exactBoundaryTolerance=boundary)
            check('kind independent:'+label,depth(lane,x,y,'siege','fullbody')==actual)
            check('tissue remains visible:'+label,depth(0,x,y,'siege','fullbody') is None)
            for mode in ['old','trial','old-anatomy']:
                check('legacy remains visible:'+label+':'+mode,
                      depth(lane,x,y,'scout',mode) is None)
            samples.append(dict(edgeId=edge['id'],sourceDistance=along,
                source=[point.x,point.y],expected=expected,actual=actual,exactBoundary=boundary))
    for probe in semantic.semantic_depth_probes(graph,portal_exclusion=True):
        lane=by_name[probe['edgeId']]['id'];x,y=probe['source']
        expected='under-foreground' if probe['expectedHidden'] else None
        for kind in ['scout','siege']:
            actual=depth(lane,x*2,y*2+512,kind,'fullbody')
            check(f"independent semantic:{probe['edgeId']}:{probe['sourceDistance']:.12f}:{kind}",
                  actual==expected,**probe,expected=expected,actual=actual)
    check('display calls preserve Save RNG positions and enemy visibility',bool(lua.eval(
          'qsame(QBefore,QSave.snapshot(QS))and qsame(QSeen,QS.factions[1].visible)')))
    changed=[p for p,h in inputs.items() if sha(ROOT/p)!=h]
    result=dict(schema='fullbody-v8-production-depth-preflight/v1',
        createdAt=datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
        status='UNDETERMINED_INPUT_CHANGED' if changed else
               'PASS' if all(row['status']=='PASS' for row in rows) else 'FAIL',
        passed=sum(row['status']=='PASS' for row in rows),total=len(rows),rows=rows,samples=samples,
        fixtureVisibility=fixture, fixtureOnly=True, finalExportVerified=False,
        nativeEvidence=False, productionNavigationSubstituted=False,
        elapsedSeconds=round(time.perf_counter()-started,3),inputHashes=inputs,
        changedDuringChecks=changed,limits=[
          'The production unitDepth API reads an independently derived v8 table in memory; this does not verify the upcoming exported Data or candidate pixels.',
          'No image loading, native rendering, movement or performance measurement was performed.',
          'Exact interval mouths permit only floating point reprojection ambiguity; nearby interior/exterior samples are strict.',
          '970 existing production movement cases were not rerun; their original evidence is eligible only because every bound navigation byte remains unchanged.'])
    output=OUT/'unit-depth-v8-fixture-preflight.json';output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(result,ensure_ascii=False,indent=2,allow_nan=False)+'\n')
    print(result['status'],result['passed'],'/',result['total'],result['elapsedSeconds'],'seconds',sha(output))
    return 0 if result['status']=='PASS' else 1


if __name__=='__main__':
    raise SystemExit(main())
