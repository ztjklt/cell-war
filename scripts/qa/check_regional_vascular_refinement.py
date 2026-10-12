"""Independent pixel-scope, production-render and lifecycle checks for a candidate.

Offline results do not certify native filtering, performance or visual acceptance.
"""
from pathlib import Path
import argparse
import hashlib
import json
import sys
import numpy as np
from PIL import Image
from shapely.geometry import LineString, Point, box
from shapely.ops import unary_union
from shapely import contains_xy
from lupa.lua54 import LuaRuntime

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).parent))

def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()

def write(p, data):
    p.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')

def convert(t):
    if not hasattr(t, 'items'):
        return t
    pairs = dict(t.items())
    if pairs and set(pairs) == set(range(1, len(pairs)+1)):
        return [convert(pairs[i]) for i in range(1, len(pairs)+1)]
    return {k: convert(v) for k, v in pairs.items()}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('candidate', type=Path)
    parser.add_argument('--contract-key', default='renalBowelMaterialRefinement')
    args = parser.parse_args()
    out = args.candidate.resolve()
    base = json.loads((out/'baseline-manifest.json').read_text())
    candidate = json.loads((out/'manifest.json').read_text())
    contract = candidate[args.contract_key]
    binding = {'manifestSha256': sha(out/'manifest.json'),
               'dataSha256': sha(out/'FullBodyMapArtData.lua')}
    checks = []
    def check(name, condition):
        checks.append({'name': name, 'pass': bool(condition)})
        assert condition, name
    graph = json.loads((ROOT/'docs/body-life/vascular-art-study/final-reference-data.json').read_text())
    shapes = {}
    for edge in graph['edges']:
        radius = edge['lumenWidthSource']/2
        shapes[edge['id']] = unary_union([
            LineString(edge['samples']).buffer(radius, cap_style=2, join_style=1),
            Point(edge['samples'][0]).buffer(radius),
            Point(edge['samples'][-1]).buffer(radius)])
    check('all 202 authored routes unchanged', base['edges'] == candidate['edges'] and len(graph['edges']) == 202)
    check('crossings unchanged', base['crossings'] == candidate['crossings'])
    check('foreground patches unchanged', base['runtimeSpec']['foregroundPatches'] == candidate['runtimeSpec']['foregroundPatches'])
    check('resource count unchanged', len(base['assets']) == len(candidate['assets']))
    old_by_id = {a['id']: a for a in base['assets']}
    changed_ids = {a['id'] for a in contract['changes']}
    for asset in candidate['assets']:
        old = old_by_id[asset['id']]
        check(asset['id']+': current file hash', sha(ROOT/asset['path']) == asset['sha256'])
        if asset['id'] not in changed_ids:
            check(asset['id']+': record unchanged', asset == old)
            continue
        check(asset['id']+': only resource fields changed',
              {k:v for k,v in asset.items() if k not in {'path','resource','sha256'}} ==
              {k:v for k,v in old.items() if k not in {'path','resource','sha256'}})
        a = np.asarray(Image.open(ROOT/old['path']).convert('RGBA'))
        b = np.asarray(Image.open(ROOT/asset['path']).convert('RGBA'))
        check(asset['id']+': size and alpha unchanged', a.shape == b.shape and np.array_equal(a[:,:,3], b[:,:,3]))
        changed = np.any(a[:,:,:3] != b[:,:,:3], axis=2)
        check(asset['id']+': transparent RGB unchanged', not np.any(changed & (a[:,:,3] == 0)))
        sy,sx = np.nonzero(changed)
        rect = asset['sourceBox']; w,h = asset['pixelSize']
        dx,dy = (rect[2]-rect[0])/w,(rect[3]-rect[1])/h
        px,py = rect[0]+(sx+.5)*dx,rect[1]+(sy+.5)*dy
        allowed = unary_union([unary_union([shapes[e] for e in region['edgeIds']]).intersection(box(*region['editBox']))
                               for region in contract['regions']])
        check(asset['id']+': changed RGB confined to authored blood ROIs',
              # Coverage-AA pixels may intersect the contour at a corner;
              # centre distance is bounded by half the pixel diagonal plus
              # the compositor's documented .008 source simplification.
              np.all(contains_xy(allowed.buffer(np.hypot(dx,dy)*.5+.009), px, py)))
        if asset.get('replacementMaskPath'):
            mask = np.asarray(Image.open(ROOT/asset['replacementMaskPath']).convert('L'))
            check(asset['id']+': replacement mask respected', np.all(mask[sy,sx] > 0))
    left,right = json.loads(json.dumps(base['runtimeSpec'])),json.loads(json.dumps(candidate['runtimeSpec']))
    for runtime in [left,right]:
        for rows in runtime.values():
            if isinstance(rows,list):
                for row in rows:
                    row.pop('resource',None)
    check('all runtime geometry, opacity and budget identical', left == right)
    for name,digest in contract['frozenRuntimeHashes'].items():
        check(name+': frozen', sha(ROOT/name) == digest)
    write(out/'scope-check-report.json', {'status':'PASS', **binding, 'checks':checks,
          'changedAssets': sorted(changed_ids), 'nativeEvidence':False})

    import check_fullbody_resource_budget as budget
    lua = LuaRuntime(unpack_returned_tuples=True)
    data = convert(lua.execute((out/'FullBodyMapArtData.lua').read_text()))
    for layer in budget.LAYERS:
        if not data.get(layer): data[layer] = []
    for organ in data['organs']:
        if organ['id'] == 'heart':
            organ.update(resource='image/anatomy-reference/vascular-study/heart-four-chamber-v1/gpt-heart-atlas-v4.png',
                         sourceBox=[468,326,568,467], pixelSize=[2400,3384])
    result = budget.run_case('candidate with current heart override',data,budget.SUCCESS)
    assert result['status'] == 'PASS'
    write(out/'resource-lifecycle-report.json', {**result, **binding, 'nativeEvidence':False,
          'limits':['Virtual image lifecycle; decoded byte count is not measured native GPU memory.']})

    import body_life_backend as b
    b.G.candidateSource = (out/'FullBodyMapArtData.lua').read_text()
    b.l.execute("""
      package.loaded['war.FullBodyMapArtData']=assert(load(candidateSource))()
      S=require('war.FullBodyBattlefield').new(72026)
      A=require('war.FullBodyMapArt');R=require('war.Render');Save=require('war.Save')
      worldContext={};uiContext={};R.vg=worldContext;R.font=1
      A.prepare(worldContext);A.prepare(uiContext)
      assert(A.ready(worldContext,S) and A.ready(uiContext,S))
      require('war.Cells').init(worldContext);R.prepare(S)
      function same(a,b)
        if type(a)~=type(b)then return false end
        if type(a)~='table'then return a==b end
        for k,v in pairs(a)do if not same(v,b[k])then return false end end
        for k in pairs(b)do if a[k]==nil then return false end end
        return true
      end
      baseline=Save.snapshot(S)
      graphics={GetWidth=function()return logicalW*dpr end,GetHeight=function()return logicalH*dpr end,GetDPR=function()return dpr end}
      game={state=S,zoom=.15,camera={x=877,y=1736},selection={},started=true,fogDisabled=true,realTime=1.92,flowTime=S.time}
      math.random=function()error('Rendering consumed RNG')end
      math.randomseed=function()error('Rendering reseeded RNG')end
    """)
    samples=[];frames=[]
    cameras = [('kidney-right',877,1736),('kidney-left',1168,1734),('bowel-inlets',1029,1883)]
    if contract['regions'] and all('center' in r for r in contract['regions']):
        cameras = [(r['id'],r['center'][0]*2,r['center'][1]*2+512) for r in contract['regions']]
    for region,x,y in cameras:
        for w,h in [(1024,768),(844,390)]:
            for dpr in [1,2,3]:
                for zoom in [.149,.15,.151]:
                    b.G.logicalW,b.G.logicalH,b.G.dpr=w,h,dpr
                    b.G.game.zoom=zoom;b.G.game.camera.x=x;b.G.game.camera.y=y
                    b.reset();b.G.R.draw(b.G.game)
                    assert b.l.eval('same(baseline,Save.snapshot(S))')
                    samples.append({'region':region,'logicalSize':[w,h],'dpr':dpr,'zoom':zoom,'stateUnchanged':True})
                    if (w,h,dpr,zoom)==(1024,768,1,.15):
                        frame=out/(region+'-production-render.png');frame.write_bytes(b.png(w,h,dpr))
                        frames.append({'path':str(frame.relative_to(ROOT)),'sha256':sha(frame)})
    assert b.G.A.stats()['images']==86
    b.l.execute('A.release(worldContext);A.release(uiContext);assert(A.stats().images==0)')
    write(out/'production-render-report.json', {'status':'PASS_PRODUCTION_RENDER_OFFLINE', **binding,
          'samples':samples,'frames':frames,'nativeEvidence':False,
          'limits':['Actual production Lua drawing through SVG/Cairo adapter; native filtering and performance unverified.']})
    print(json.dumps({'scopeChecks':len(checks),'resourceStatus':result['status'],'renderSamples':len(samples),**binding}))

if __name__ == '__main__':
    main()
