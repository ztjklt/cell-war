"""Export actual game glyphs, fill calls and prior Lua movement for art review.

This is isolated SVG/Cairo evidence. It does not install the new vascular art,
rerun navigation, emulate gameplay with JavaScript, or certify native rendering.
Run with the existing Python 3.13 QA dependencies, e.g.:
  PYTHONPATH=/tmp/reference-map-tools python3.13 scripts/qa/check_registered_vascular_game_art.py
"""
from pathlib import Path
import argparse
import hashlib
import json
import math
import os
import re
import shutil
import xml.etree.ElementTree as ET

import body_life_backend as backend

ROOT = Path(__file__).resolve().parents[2]
DOC = ROOT / 'docs/body-life/vascular-art-study'
FROZEN_GRAPH_SHA = '3890744e2fcaf9e9907c85513e170e479f67b7fbb1fbf06385ac02bd80e8550c'
ZOOMS = [.085, .115, .15, .18]
VIEWPORTS = [[1440, 900], [1024, 768], [844, 390], [430, 932], [360, 780]]
KINDS = ['scout', 'siege', 'worker', 'virus']
NS = '{http://www.w3.org/2000/svg}'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def initialise_unit_renderer():
    """Keep actual R.draw's entity branch, hiding only non-unit scenery.

    Changes exist solely in this process's Lua runtime. Modules on disk are
    never edited, and no helper copies the private unit drawing code.
    """
    backend.l.execute("""
      R=require('war.Render');R.vg={};R.font=1
      Cells=require('war.Cells');Cells.init(R.vg)
      W=require('war.World');C=require('war.Commands');View=require('war.View')
      s=W.generate(73,nil,nil,nil,4);W.rebuild(s)
      s.campaign=true;s.effects={};s.resources={}
      game={state=s,selection={},camera={x=1132,y=1518},zoom=1,
            realTime=.6,flowTime=.6,accumulator=0,started=true,fogDisabled=true}
      for _,pair in ipairs({{'war.SmoothTerrain','draw'},
          {'war.SmoothTerrain','detail'},{'war.SmoothTerrain','fog'},
          {'war.VesselArt','coarse'},{'war.VesselArt','details'},
          {'war.NasalArt','draw'}})do require(pair[1])[pair[2]]=function()end end
      local rect=R.rect
      R.rect=function(x,y,w,h,c,a)
        if x==0 and y==0 and w==R.w and h==R.h then return end
        return rect(x,y,w,h,c,a)
      end
      function qaGlyph(kind,selected,z,side)
        s.entities={};s.nextId=1;W.rebuild(s)
        s.campaign=nil
        local e=C.spawn(s,'unit',kind,kind=='virus'and 2 or 1,1132,1518,true)
        s.campaign=true
        assert(e);game.selection=selected and {[e.id]=true}or{}
        local key=require('war.Util').key(e.x,e.y)
        s.factions[1].visible[key]=true;s.factions[1].seen[key]=true
        if selected then e.hp=e.maxHp*.65 end
        game.zoom=z;game.camera={x=e.x,y=e.y-.03*side/(32*z)}
        graphics={GetWidth=function()return side end,
                  GetHeight=function()return side end,GetDPR=function()return 1 end}
        R.draw(game)
        return Cells.radius(kind)
      end
    """)


def standalone_svg(w, h, out):
    """Self-contained SVG: SVG-as-image forbids external texture references."""
    out.write_text(backend.document(w, h))


def export_glyphs(out):
    initialise_unit_renderer()
    (out / 'textures').mkdir(exist_ok=True)
    texture_paths, textures = {}, []
    for key in backend.decoded_images:
        path = Path(key)
        relative = 'textures/' + path.name
        shutil.copyfile(path, out / relative)
        texture_paths[key] = relative
        textures.append({'file': relative, 'source': str(path.relative_to(ROOT)), 'sha256': sha(path), 'pixelsUnchanged': True})
    sprites = {}
    # z >= .14 scales all geometry, including rings/bars, with g.zoom.
    # A 128-logical-pixel z=1 glyph maps to exactly 2 source pixels.
    for kind in KINDS:
        for selected in [False, True]:
            ident = kind + ('-selected' if selected else '-normal')
            backend.reset()
            radius = backend.l.eval('qaGlyph')(kind, selected, 1, 128)
            file = ident + '.svg'
            standalone_svg(128, 128, out / file)
            (out / (ident + '.png')).write_bytes(backend.png(128, 128))
            from PIL import Image
            assert Image.open(out / (ident + '.png')).getchannel('A').getbbox(), ident + ' is invisible'
            sprites[ident] = {'file': file, 'png': ident + '.png', 'kind': kind,
                'selected': selected, 'hpFraction': .65 if selected else 1,
                'mode': 'actual-Render.draw-unit', 'encodingZoom': 1,
                'logicalSideAtEncodingZoom': 128, 'centerLogical': [64, 64],
                'sourceSide': 2, 'cellRadiusWorld': float(radius) / 32,
                'cellRadiusSource': float(radius) / 64,
                'faction': 2 if kind == 'virus' else 1,
                'fixedPoseTime': .6, 'fixedEntityId': 1, 'sha256': sha(out / file)}
    # z < .14 paints actual 2-logical-pixel faction dots instead.
    for kind in ['scout', 'virus']:
        for selected in [False, True]:
            ident = ('enemy' if kind == 'virus' else 'ally') + ('-selected' if selected else '-normal') + '-far'
            backend.reset()
            backend.l.eval('qaGlyph')(kind, selected, .085, 16)
            file = ident + '.svg'
            standalone_svg(16, 16, out / file)
            sprites[ident] = {'file': file, 'kind': kind, 'selected': selected,
                'mode': 'actual-Render.draw-far-dot', 'encodingZoom': .085,
                'logicalSide': 16, 'centerLogical': [8, 8],
                'radiusLogical': 2, 'selectionRadiusLogical': 4 if selected else None,
                'sourceSideFormula': '16 / (64 * zoom)', 'faction': 2 if kind == 'virus' else 1,
                'sha256': sha(out / file)}
    atlas = {'schema': 'registered-vessels-actual-glyph-atlas/v1',
        'nativeEvidence': False, 'productionInstalled': False,
        'backend': 'actual Render.draw entity branch through SVG/Cairo',
        'textures': textures, 'sprites': sprites,
        'display': {'near': 'At zoom >= .14 use kind-normal/selected: image source width = 2, centered on source position.',
            'far': 'At zoom < .14 use ally/enemy-normal/selected-far: source width = 16/(64*zoom).',
            'warning': 'The fixed .6-second pose is a glyph fixture; movement comes only from the recorded Lua trace.'}}
    write_json(out / 'sprite-atlas.json', atlas)
    return atlas


def export_existing_fill(out):
    """Existing ReferenceArt full-fill draw, normalized to source coordinates."""
    backend.reset()
    backend.l.execute("""
      local A=require('war.ReferenceArt');local B=require('war.BodyLife')
      B.draw=function()end;B.perfusion=function()end
      local z=.15;local scale=64*z;local w,h=1024*scale,1536*scale
      local g={zoom=z,camera={x=1024,y=2048-.03*h/(32*z)},realTime=.6}
      qaReferenceContext={}
      local refR={vg=qaReferenceContext,project=function(q,x,y)return View.project(q,w,h,x,y)end}
      nvgScale(refR.vg,1/scale,1/scale)
      A.draw(refR,g,s,0,2048,512,3584)
    """)
    path = out / 'actual-reference-fill.svg'
    path.write_text(backend.document(1024, 1536))
    return {'file': path.name, 'sha256': sha(path), 'sourceBox': [0, 0, 1024, 1536],
        'renderer': 'actual war.ReferenceArt.draw at zoom=.15',
        'baseOnly': True, 'nativeEvidence': False,
        'bodyLifeDisabledInIsolatedQaRuntime': True,
        'meaning': 'Existing full-fill renderer for handover comparison; not a new generated organ map.'}


def export_fill_display_data(out):
    """Capture the actual quadratic path commands in source coordinates."""
    root = ET.fromstring((out / 'actual-reference-fill.svg').read_bytes())
    scale = 64*.15
    gradients = {g.get('id'): g for g in root.iter(NS + 'linearGradient')}
    number = re.compile(r'-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?')
    def rgba(value):
        parts = value.removeprefix('rgba(').removesuffix(')').split(',')
        assert len(parts) == 4
        a, b, c, d = map(float, parts)
        return [a, b, c, d]
    paths = []
    for index, p in enumerate(root.iter(NS + 'path')):
        # Contour.path uses only absolute M/Q/Z. Supporting C/L here allows the
        # same export if those native commands are later used, without guessing.
        d = p.get('d')
        assert set(re.findall(r'[A-Za-z]', number.sub('', d))) <= set('MQLCZ')
        source_d = number.sub(lambda m: f'{float(m.group())/scale:.8f}'.rstrip('0').rstrip('.'), d)
        fill = p.get('fill')
        row = {'id': 'body-outline' if index == 0 else 'reference-region-' + str(index),
            'order': index, 'd': source_d, 'fillRule': p.get('fill-rule', 'nonzero')}
        if fill.startswith('url(#'):
            gradient = gradients[fill[5:-1]]
            stops = list(gradient)
            row['gradient'] = {'x1': float(gradient.get('x1'))/scale,
                'y1': float(gradient.get('y1'))/scale, 'x2': float(gradient.get('x2'))/scale,
                'y2': float(gradient.get('y2'))/scale,
                'stops': [{'offset': float(q.get('offset')), 'rgba': rgba(q.get('stop-color'))} for q in stops]}
        else:
            row['rgba'] = rgba(fill)
        paths.append(row)
    assert len(paths) == 1 + int(backend.l.eval("#require('war.ReferenceFill').regions"))
    data = {'schema': 'registered-vessels-actual-fill-display/v1',
        'sourceBox': [0, 0, 1024, 1536], 'pathCount': len(paths),
        'sourceToLogicalScale': '64 * zoom', 'paths': paths,
        'provenance': {'renderer': 'actual ReferenceArt.draw at .15 via Contour.path',
            'ReferenceFillSha256': sha(ROOT/'scripts/war/ReferenceFill.lua'),
            'ContourSha256': sha(ROOT/'scripts/war/Contour.lua'),
            'ReferenceArtSha256': sha(ROOT/'scripts/war/ReferenceArt.lua'),
            'rawSvgSha256': sha(out/'actual-reference-fill.svg')},
        'drawingRule': 'Preserve order. At intermediate zoom apply floor(smoothstep*255)/255 alpha to every drawing primitive, including each gradient stop; do not alpha-fade the completed fill layer as one image.',
        'nativeEvidence': False, 'productionInstalled': False}
    write_json(out/'fill-display-data.json', data)
    return {'file': 'fill-display-data.json', 'sha256': sha(out/'fill-display-data.json'), 'paths': len(paths)}


def verify_fill_display(out):
    """Rebuild code-native source paths, comparing with actual offline draw."""
    import io
    import cairosvg
    import numpy as np
    from PIL import Image
    data = json.loads((out/'fill-display-data.json').read_text())
    root = ET.Element('svg', {'xmlns': 'http://www.w3.org/2000/svg',
        'width': '1024', 'height': '1536', 'viewBox': '0 0 1024 1536'})
    defs = ET.SubElement(root, 'defs')
    def color(c):
        return f'rgba({c[0]},{c[1]},{c[2]},{c[3]})'
    for row in data['paths']:
        props = {'d': row['d'], 'fill-rule': row['fillRule']}
        if 'gradient' in row:
            g, name = row['gradient'], 'fg'+str(row['order'])
            gradient = ET.SubElement(defs, 'linearGradient', {'id': name,
                'gradientUnits': 'userSpaceOnUse',
                **{k: str(g[k]) for k in ['x1', 'y1', 'x2', 'y2']}})
            for stop in g['stops']:
                ET.SubElement(gradient, 'stop', {'offset': str(stop['offset']), 'stop-color': color(stop['rgba'])})
            props['fill'] = 'url(#'+name+')'
        else:
            props['fill'] = color(row['rgba'])
        ET.SubElement(root, 'path', props)
    raw = ET.tostring(root)
    (out/'fill-display-verification.svg').write_bytes(raw)
    a = cairosvg.svg2png(bytestring=(out/'actual-reference-fill.svg').read_bytes(), output_width=512, output_height=768)
    b = cairosvg.svg2png(bytestring=raw, output_width=512, output_height=768)
    (out/'actual-reference-fill.png').write_bytes(a)
    (out/'fill-display-verification.png').write_bytes(b)
    aa = np.asarray(Image.open(io.BytesIO(a))).astype(float)
    bb = np.asarray(Image.open(io.BytesIO(b))).astype(float)
    difference = np.abs(aa-bb)
    mean, p95, peak = float(difference.mean()), float(np.quantile(difference, .95)), float(difference.max())
    assert mean < .1
    result = {'status': 'PASS_JSON_PATHS_MATCH_ACTUAL_OFFLINE_DRAW', 'nativeEvidence': False,
        'meanRgbaDifference': mean, 'p95RgbaDifference': p95, 'peakRgbaDifference': peak,
        'imageSize': [512, 768], 'fillDisplaySha256': sha(out/'fill-display-data.json'),
        'actualSvgSha256': sha(out/'actual-reference-fill.svg'),
        'limit': 'Cairo and export decimal precision differ from native NanoVG; source comparison only. Transparent RGB can produce a high peak.'}
    write_json(out/'fill-display-verification.json', result)
    return result


def export_projection(out, graph):
    """Actual Lua projection samples; DPR affects the final surface once."""
    points = [p['source'] for p in graph['ports']]
    points += [g[k] for g in graph['gates'] for k in ['pipeCenterSource', 'wallSource', 'tissueTargetSource']]
    samples = []
    maximum = 0
    project = backend.l.eval("function(w,h,z,x,y) local g={zoom=z,camera={x=1024,y=2048}};local a,b=View.project(g,w,h,x*2,y*2+512);local c,d=View.unproject(g,w,h,a,b);return a,b,c,d end")
    alpha = backend.l.execute("""
      local draw=require('war.ReferenceArt').draw
      for i=1,20 do local name,base=debug.getupvalue(draw,i)
        if name=='drawBase'then for j=1,20 do local n,f=debug.getupvalue(base,j)
          if n=='blend'then return f end
        end end
      end
      error('actual ReferenceArt blend function unavailable')
    """)
    for w, h in VIEWPORTS:
        for dpr in [1, 2, 3]:
            for z in ZOOMS:
                error = 0
                for x, y in points:
                    px, py, wx, wy = project(w, h, z, x, y)
                    error = max(error, abs(wx - x*2), abs(wy - (y*2+512)))
                    a, b, _, _ = project((w*dpr)/dpr, (h*dpr)/dpr, z, x, y)
                    assert abs(a-px) < 1e-9 and abs(b-py) < 1e-9
                maximum = max(maximum, error)
                samples.append({'logicalSize': [w, h], 'dpr': dpr, 'zoom': z,
                    'sourceToLogicalScale': 64*z, 'fillAlpha': float(alpha(z)),
                    'fillPaintAlpha': math.floor(float(alpha(z))*255)/255,
                    'roundTripWorldError': error, 'unitsMode': 'far-dot' if z < .14 else 'cell'})
    assert maximum < 1e-8
    result = {'schema': 'registered-vessels-projection-contract/v1', 'nativeEvidence': False,
        'sourceToWorld': {'xScale': 2, 'yScale': 2, 'yOffset': 512},
        'worldToLogical': {'scale': '32 * zoom', 'center': ['logicalWidth*.5', 'logicalHeight*.47']},
        'sourceToLogicalScale': '64 * zoom', 'fillAlpha': 'smoothstep(clamp((zoom-.085)/.065,0,1))',
        'fillPaintAlpha': 'floor(fillAlpha * 255) / 255',
        'dpr': 'Mode B: logical viewport = physical viewport / DPR; physical output = logical output * DPR.',
        'pointsTested': len(points), 'samples': samples, 'maximumWorldError': maximum,
        'zoomSizes': [{'zoom': z, 'sourceToLogicalScale': 64*z, 'fillAlpha': float(alpha(z)),
            'fillPaintAlpha': math.floor(float(alpha(z))*255)/255,
            'unitMode': 'far-dot' if z < .14 else 'cell',
            'scoutDiameterLogical': 4 if z < .14 else 28*z,
            'siegeDiameterLogical': 4 if z < .14 else 68*z} for z in ZOOMS],
        'limits': ['The actual .14 far-dot/cell switch is discontinuous in current Render.lua; this records it without changing it.',
            'A CSS-fit full-body picture is not zoom=.15. A .15 viewport uses 9.6 logical pixels per source pixel.',
            'Existing .15 fill is a comparison layer. New vascular art is a separate uninstalled study layer.']}
    write_json(out / 'projection-contract.json', result)
    return result


def export_replay(out, graph, nav, nav_path):
    lines = []
    for edge in graph['edges']:
        accumulated = 0
        segments = []
        for a, b in zip(edge['samples'], edge['samples'][1:]):
            length = math.dist(a, b)
            segments.append((a, b, accumulated, length))
            accumulated += length
        lines.append(segments)
    def along(lane, x, y):
        nearest, result = math.inf, 0
        for a, b, start, length in lines[lane-1]:
            dx, dy = b[0]-a[0], b[1]-a[1]
            t = max(0, min(1, ((x-a[0])*dx+(y-a[1])*dy)/(length*length))) if length else 0
            distance = (x-a[0]-dx*t)**2+(y-a[1]-dy*t)**2
            if distance < nearest:
                nearest, result = distance, start+length*t
        return result
    # Drawing classification only: retain exact lane/world values so a browser
    # cannot accidentally reinterpret paint occlusion as navigation permission.
    def point(p):
        x, y = p['x']/2, (p['y']-512)/2
        lane = p.get('lane', 0)
        edge = graph['edges'][lane-1] if lane > 0 else None
        distance = along(lane, x, y) if edge else None
        hidden = any(a <= distance <= b for a, b in edge['hiddenIntervals']) if edge else False
        return {'t': p['t'], 'world': [p['x'], p['y']], 'source': [x, y], 'laneIndex': lane,
            'edgeId': edge['id'] if edge else None, 'stage': p.get('stage'),
            'recordedGraphHidden': hidden,
            'bladderDeepWallRequiresForeground': bool(edge and edge['id'] in ['e143', 'e197', 'e198'])}
    routes = []
    for route in nav['routes']:
        trace = [point(p) for p in route['trace']]
        assert all(b['t'] >= a['t'] for a, b in zip(trace, trace[1:]))
        routes.append({'id': route['id'], 'kind': route['kind'], 'seconds': route['seconds'],
            'pass': route['pass'], 'cellRadiusWorld': route['cellRadiusWorld'],
            'faction': 1, 'trace': trace, 'stages': route['stages']})
    meeting = nav['meeting']
    replay_meeting = {'scenario': meeting['scenario'], 'seconds': meeting['seconds'],
        'pass': meeting['pass'], 'units': [{'id': i+1, 'kind': u['kind'], 'faction': 1} for i, u in enumerate(meeting['units'])],
        'trace': [{'t': p['t'], 'units': [dict(point(dict(u, t=p['t'])), id=u['id']) for u in p['units']]} for p in meeting['trace']]}
    module_changes = []
    for name, digest in nav['testedModuleHashes'].items():
        path = ROOT / 'scripts/war' / name
        if not path.exists() or sha(path) != digest:
            module_changes.append(name)
    result = {'schema': 'registered-vessels-recorded-lua-replay/v1',
        'nativeEvidence': False, 'productionInstalled': False,
        'provenance': {'recordedBy': 'scripts/qa/check_final_stomach_navigation.py',
            'sourceReport': str(nav_path.relative_to(ROOT)), 'reportSha256': sha(nav_path),
            'sourceGraphSha256': sha(DOC / 'final-reference-data.json'),
            'originalQaScriptSha256': nav['qaScriptSha256'],
            'recordedTestedModuleHashes': nav['testedModuleHashes'],
            'modulesChangedSinceRecording': module_changes, 'navigationReexecutedThisExport': False,
            'summary': nav['summary']},
        'coordinateSystem': 'world x=source x*2; world y=source y*2+512',
        'routes': routes, 'meeting': replay_meeting,
        'fixedGates': nav['fixedGates'], 'targets': nav['targets'],
        'displayRules': ['Replay only recorded positions in trace; interpolation is display only, never a new collision result.',
            'Use logical zoom projection and actual sprite atlas. Never enlarge cells to imply readability.',
            'Mask unit paint behind the same foreground as its hidden vessel; graph visibility is not navigation permission.',
            'Bladder deep-wall flag is an art obligation. These stomach traces do not validate bladder movement.',
            'A browser replay is neither native running gameplay nor a new pathfinding PASS.']}
    write_json(out / 'actual-lua-replay.json', result)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', default=str(DOC / 'registered-vessels-game-evidence'))
    args = parser.parse_args()
    os.chdir(ROOT)
    out = Path(args.output);out.mkdir(parents=True, exist_ok=True)
    source = DOC / 'final-reference-data.json'
    nav_path = DOC / 'final-stomach-navigation-evidence/report.json'
    graph = json.loads(source.read_text())
    nav = json.loads(nav_path.read_text())
    assert sha(source) == FROZEN_GRAPH_SHA == nav['sourceSha256']
    source_files = [ROOT / 'scripts/war' / name for name in ['Render.lua', 'View.lua', 'Cells.lua', 'CellFrames.lua', 'ReferenceArt.lua', 'ReferenceFill.lua', 'Data.lua']]
    input_hashes = {str(p.relative_to(ROOT)): sha(p) for p in source_files}
    atlas = export_glyphs(out)
    fill = export_existing_fill(out)
    fill_display = export_fill_display_data(out)
    fill_verification = verify_fill_display(out)
    projection = export_projection(out, graph)
    replay = export_replay(out, graph, nav, nav_path)
    backend.l.execute("require('war.ReferenceArt').release(qaReferenceContext);Cells.release(R.vg)")
    assert not backend.image_handles, 'isolated QA left image handles after release'
    assert sha(source) == FROZEN_GRAPH_SHA
    assert all(sha(ROOT / name) == digest for name, digest in input_hashes.items())
    report = {'schema': 'registered-vessels-game-evidence/v1',
        'status': 'OFFLINE_FIXTURES_EXPORTED_NATIVE_UNDETERMINED',
        'nativeEvidence': False, 'productionInstalled': False,
        'frozenGraphSha256': sha(source), 'navigationReportSha256': sha(nav_path),
        'inputs': input_hashes, 'sprites': len(atlas['sprites']),
        'projectionSamples': len(projection['samples']), 'maximumWorldError': projection['maximumWorldError'],
        'actualTracePoints': sum(len(r['trace']) for r in replay['routes']),
        'meetingTraceFrames': len(replay['meeting']['trace']),
        'fill': fill, 'fillDisplay': fill_display,
        'fillDisplayVerification': fill_verification,
        'imageHandlesAfterRelease': len(backend.image_handles),
        'modulesChangedSinceMovementRecording': replay['provenance']['modulesChangedSinceRecording'],
        'nativePreview': 'Stopped; not restarted by this QA export.',
        'checks': {'sourceGraphUnchanged': True, 'gameSourceFilesUnchanged': True,
            'projectionRoundTripAndDpr': True, 'movementCoordinatesCopiedFromActualLuaReport': True,
            'gameSpritesDrawnByActualRenderDraw': True},
        'limits': ['Fixture for art inspection, not a production art integration test.',
            'Native seam, filtering, performance and live-unit visibility remain unconfirmed.',
            'The .14 marker/cell switch and current .15 fill are preserved for honest review.']}
    write_json(out / 'report.json', report)
    print(json.dumps({k: report[k] for k in ['status', 'sprites', 'projectionSamples', 'actualTracePoints', 'meetingTraceFrames', 'modulesChangedSinceMovementRecording']}, ensure_ascii=False))


if __name__ == '__main__':
    main()
