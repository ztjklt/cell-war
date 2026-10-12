"""Exercise production FullBodyMapArt with virtual NanoVG resource handles.

This test allocates no images and changes no runtime/art files. It verifies the
declared 42-spec / 288-MiB boundaries and atomic fallback, including the new
optional foreground layer. Actual candidate PNGs and native memory are separate
acceptance checks; synthetic boundary fixtures never certify candidate artwork.
"""
from pathlib import Path
import datetime
import hashlib
import json
import os
import runpy
import sys

for dependency in ['/tmp/reference-map-tools', '/tmp/passage-tools314']:
    if Path(dependency).is_dir():
        sys.path.insert(0, dependency)
from lupa.lua54 import LuaRuntime

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/body-life/vascular-art-study/fullbody-015/qa/fourth-repair/resource-budget-report.json'
MAX_SPECS = 42
MAX_BYTES = 288 * 1024 * 1024
LAYERS = ['surfaceTiles', 'organs', 'deepTiles', 'junctions', 'foregroundPatches']


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def table(lua, value):
    if isinstance(value, dict):
        return lua.table_from({k: table(lua, v) for k, v in value.items()})
    if isinstance(value, list):
        return lua.table_from([table(lua, v) for v in value])
    return value


def spec(ident, size=(8, 8), **extra):
    return {'id': ident, 'resource': 'image/virtual-budget-qa/' + ident + '.png',
            'sourceBox': [0, 0, 1, 1], 'pixelSize': list(size), **extra}


def specs(data):
    return ([data['quietBase']] if data.get('quietBase') else []) + [
        s for layer in LAYERS for s in data.get(layer, [])]


def fixture(count=42, with_budget=True):
    # Include all five production draw layers and exactly nine optional patches.
    data = {'quietBase': spec('quiet'), 'visibility': {}, 'surfaceTiles': [],
            'organs': [], 'deepTiles': [], 'junctions': [], 'foregroundPatches': []}
    for layer, n in [('organs', 12), ('deepTiles', 10), ('junctions', 1),
                     ('foregroundPatches', 9)]:
        data[layer] = [spec(layer + '-' + str(i + 1), opacity=.7 if layer == 'foregroundPatches' else 1)
                       for i in range(n)]
    data['foregroundPatches'][0]['coreBox'] = [.1, .1, .9, .9]
    data['surfaceTiles'] = [spec('surface-' + str(i + 1)) for i in range(count - 33)]
    assert len(specs(data)) == count
    if with_budget:
        data['resourceBudget'] = {'maxResourceSpecsPerContext': MAX_SPECS,
                                  'maxDecodedRGBABytesPerContext': MAX_BYTES}
    return data


def byte_fixture(delta=0, with_budget=True):
    # Realistic texture dimensions, but virtual handles: no 288-MiB allocation.
    # The last 1px strip changes the total by exactly one RGBA texel.
    data = {'quietBase': spec('quiet-large', (8192, 8192)),
            'surfaceTiles': [spec('second-large', (4096, 2047))],
            'foregroundPatches': [spec('last-strip', (4096 + delta, 1))], 'visibility': {}}
    if with_budget:
        data['resourceBudget'] = {'maxResourceSpecsPerContext': MAX_SPECS,
                                  'maxDecodedRGBABytesPerContext': MAX_BYTES}
    assert sum(s['pixelSize'][0] * s['pixelSize'][1] * 4 for s in specs(data)) == MAX_BYTES + delta * 4
    return data


HARNESS = r'''
package.path='scripts/?.lua;'..package.path
package.loaded['war.FullBodyMapArtData']=fixture
NVG_IMAGE_GENERATE_MIPMAPS=1
world={};ui={};live={};serial=0;created=0;deleted=0;queries=0;draws=0
clips=0;patterns={};rows={};failAll=false;failureValue=nil;missing=nil;badDecode=false
function nvgCreateImage(vg,path,flags)
 assert(flags==NVG_IMAGE_GENERATE_MIPMAPS)
 created=created+1
 if failAll or path==missing then return failureValue end
 serial=serial+1
 local dim=sizes[path];assert(dim,'unknown resource: '..path)
 live[serial]={vg=vg,path=path,width=badDecode and 16 or dim[1],height=badDecode and 16 or dim[2]}
 return serial
end
function nvgImageSize(vg,id)
 queries=queries+1;local h=live[id];assert(h and h.vg==vg)
 return h.width,h.height
end
function nvgDeleteImage(vg,id)
 assert(live[id]and live[id].vg==vg,'invalid, cross-context, or double deletion')
 live[id]=nil;deleted=deleted+1
end
function nvgSave(vg)end
function nvgRestore(vg)end
function nvgBeginPath(vg)end
function nvgRect(vg,x,y,w,h)assert(w>0 and h>0)end
function nvgFillPaint(vg,p)end
function nvgFill(vg)draws=draws+1 end
function nvgIntersectScissor(vg,x,y,w,h)assert(w>0 and h>0);clips=clips+1 end
function nvgImagePattern(vg,x,y,w,h,angle,id,alpha)
 local h=live[id];assert(h and h.vg==vg)
 patterns[#patterns+1]={path=h.path,alpha=alpha,vg=vg}
 return{}
end
function count()local n=0;for _ in pairs(live)do n=n+1 end;return n end
function check(name,pass)rows[#rows+1]={name=name,pass=not not pass}end
function snapshot(t)
 if type(t)~='table'then return type(t)..':'..tostring(t)end
 local keys={};for k in pairs(t)do keys[#keys+1]=k end
 table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
 local out={};for _,k in ipairs(keys)do out[#out+1]=snapshot(k)..'='..snapshot(t[k])end
 return'{'..table.concat(out,',')..'}'
end
local A=require('war.FullBodyMapArt');_G.A=A
full={anatomyVersion=4,fullbodyBattlefieldVersion=1,rng=12345,time=12,step=77,
 entities={{id=1,x=3,y=4,hp=70,order={x=5,y=6}}},supply=32,visible={brain=true}}
game={state=full,zoom=.15};R={vg=world,project=function(g,x,y)return x*32*g.zoom,y*32*g.zoom end}
stateBefore=snapshot(full)
math.random=function()error('resource/render code consumed RNG')end
math.randomseed=function()error('resource/render code reseeded RNG')end
function verifyFallback(label)
 check(label..': complete pack not ready',not A.ready(world,full))
 check(label..': no partial background',A.background(world,full)==nil)
 local previous=draws
 check(label..': static caller interface (false draw/no paints)',not A.draw(R,game,full,0,2,512,514)and draws==previous)
end
function verifyPurity()
 check('state, commands, time, supply, visibility, and RNG are unchanged',snapshot(full)==stateBefore)
end
'''


def run_case(name, data, action):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().fixture = table(lua, data)
    all_specs = specs(data)
    lua.globals().sizes = table(lua, {s['resource']: s['pixelSize'] for s in all_specs})
    lua.globals().expectedCount = len(all_specs)
    lua.globals().expectedOrder = table(lua, [s['resource'] for layer in LAYERS for s in data.get(layer, [])])
    lua.globals().foregroundResources = table(lua, [s['resource'] for s in data.get('foregroundPatches', [])])
    lua.execute(HARNESS + action + '\nverifyPurity()')
    rows = [{'name': r['name'], 'pass': bool(r['pass'])} for _, r in lua.globals().rows.items()]
    return {'id': name, 'declaredSpecs': len(all_specs),
            'declaredDecodedRGBABytes': sum(s['pixelSize'][0] * s['pixelSize'][1] * 4 for s in all_specs),
            'hasBudget': 'resourceBudget' in data,
            'created': lua.globals().created, 'deleted': lua.globals().deleted,
            'liveHandlesAfterCase': lua.eval('count()'),
            'status': 'PASS' if all(r['pass'] for r in rows) else 'FAIL', 'checks': rows}


SUCCESS = r'''
A.prepare(world);A.prepare(ui)
check('both contexts load the complete declared pack',created==2*expectedCount and count()==2*expectedCount)
check('both contexts ready',A.ready(world,full)and A.ready(ui,full))
check('no budget error within bound',A.resourceError==nil)
local p=A.background(world,full);local q=A.background(ui,full)
check('background handles context-local',p and q and p~=q and live[p].vg==world and live[q].vg==ui)
local before=created;local beforeQ=queries
for _=1,6 do A.prepare(world);A.prepare(ui);A.ready(world,full);A.ready(ui,full)end
check('prepare never duplicates uploads',created==before)
check('ready caches successful size verification',queries==beforeQ)
A.release(world);A.release(world)
check('world release deletes only its own complete pack',count()==expectedCount and A.ready(ui,full))
A.release(ui);A.release(ui)
check('both contexts fully and idempotently released',count()==0 and deleted==2*expectedCount)
check('released contexts are removed',A.stats().contexts==0 and A.stats().images==0)
'''

REJECT = r'''
A.prepare(world);A.prepare(ui)
check('over-budget pack rejects before the first upload in either context',created==0 and count()==0)
check('reason identifies resource budget',A.resourceError=='Full-body map resource budget exceeded')
verifyFallback('budget fallback')
check('second context cannot become partially ready',not A.ready(ui,full)and A.background(ui,full)==nil)
for _=1,6 do A.prepare(world);A.prepare(ui);A.draw(R,game,full,0,2,512,514)end
check('fallback never retries every frame',created==0 and draws==0)
A.release(world);A.release(ui)
check('rejected contexts release without deleting invalid handles',count()==0 and deleted==0 and A.stats().contexts==0)
'''


def main():
    os.chdir(ROOT)
    binding_paths = [Path(__file__).resolve(), ROOT / 'scripts/war/FullBodyMapArt.lua',
                     ROOT / 'scripts/war/FullBodyBattlefield.lua', ROOT / 'scripts/qa/prepare_fullbody_map_art.py']
    binding = {str(p.relative_to(ROOT)): sha(p) for p in binding_paths}
    exporter = runpy.run_path(str(ROOT / 'scripts/qa/prepare_fullbody_map_art.py'))
    exporter_checks = [
        {'name': 'exporter declares the locked 42-spec cap', 'pass': exporter['MAX_RESOURCE_SPECS'] == MAX_SPECS},
        {'name': 'exporter declares the locked 288-MiB cap', 'pass': exporter['MAX_DECODED_RGBA_BYTES'] == MAX_BYTES},
        {'name': 'exporter includes the final foreground layer in its common list', 'pass': exporter['LAYERS'] == LAYERS}]
    cases = [{'id': 'production-exporter-cap-and-layer-contract',
              'status': 'PASS' if all(r['pass'] for r in exporter_checks) else 'FAIL',
              'checks': exporter_checks}]
    for n in [41, 42, 43]:
        cases.append(run_case('spec-count-' + str(n), fixture(n), SUCCESS if n <= MAX_SPECS else REJECT))
    for delta in [-1, 0, 1]:
        cases.append(run_case('decoded-byte-boundary-' + str(delta * 4), byte_fixture(delta), SUCCESS if delta <= 0 else REJECT))
    cases.append(run_case('legacy-no-budget-43-specs', fixture(43, False), SUCCESS))
    cases.append(run_case('legacy-no-budget-cap-plus-4', byte_fixture(1, False), SUCCESS))
    old_data = fixture(with_budget=False)
    del old_data['foregroundPatches']
    cases.append(run_case('legacy-data-without-budget-or-foreground', old_data, SUCCESS))
    cases.append(run_case('optional-foreground-final-layer', fixture(), r'''
A.prepare(world);A.prepare(ui)
check('complete optional pack ready',A.ready(world,full)and A.ready(ui,full))
local before=created;local beforeQ=queries
check('draw succeeds at true .15',A.draw(R,game,full,0,2,512,514))
check('only five draw layers painted; background uses its separate handle',#patterns==#expectedOrder)
local ordered=true;for i,path in ipairs(expectedOrder)do ordered=ordered and patterns[i].path==path end
check('foreground follows every surface/organ/deep/junction in declared order',ordered)
local final=true;for i,path in ipairs(foregroundResources)do
 local p=patterns[#patterns-#foregroundResources+i]
 final=final and p.path==path and math.abs(p.alpha-.7)<1e-12
end
check('all nine foreground patches are final and preserve opacity',final)
check('optional foreground clips its fixed core',clips==1)
for _=1,15 do A.draw(R,game,full,0,2,512,514)end
check('drawing patches never creates images or rechecks decoded dimensions',created==before and queries==beforeQ)
check('old anatomy/normal sandbox/trial remain disabled',not A.ready(world,{anatomyVersion=3,fullbodyBattlefieldVersion=1})and
 not A.ready(world,{anatomyVersion=4})and not A.ready(world,{anatomyVersion=4,organBattlefieldVersion=1}))
game.zoom=.085;local beforeD=draws
check('transition start draws no foreground or vessel paint',not A.draw(R,game,full,0,2,512,514)and draws==beforeD)
A.release(world);check('world release preserves every UI patch',count()==expectedCount and A.ready(ui,full))
for _,path in ipairs(foregroundResources)do
 local found=false;for _,h in pairs(live)do found=found or(h.vg==ui and h.path==path)end
 check('remaining UI foreground: '..path,found)
end
for _=1,20 do A.release(ui);A.prepare(ui);check('reopen count remains bounded including foreground',count()==expectedCount)end
A.release(ui);check('foreground and every other layer released',count()==0)
'''))
    for value in ['nil', '0', '-1']:
        cases.append(run_case('complete-load-failure-' + value, fixture(), 'failAll=true;failureValue=' + value + r'''
A.prepare(world);A.prepare(ui)
check('all failed loads have no positive handles',created==2*expectedCount and count()==0)
verifyFallback('all-image failure')
check('UI all-failure remains atomic',not A.ready(ui,full))
local before=created;A.prepare(world);A.prepare(ui)
check('all-failure avoids per-frame retry',created==before)
A.release(world);A.release(ui);check('all-failure releases safely',deleted==0 and count()==0)
failAll=false;A.prepare(world)
check('explicit release/prepare recovers the entire pack',A.ready(world,full)and count()==expectedCount)
A.release(world);check('recovered pack including patches fully released',count()==0)
'''))
    for patch in fixture()['foregroundPatches']:
        for value in ['nil', '0', '-1']:
            cases.append(run_case('missing-' + patch['id'] + '-' + value, fixture(),
                                  'missing=' + json.dumps(patch['resource']) + ';failureValue=' + value + r'''
A.prepare(world);A.prepare(ui)
check('one failed foreground patch leaves only partial positive handles',count()==2*(expectedCount-1))
verifyFallback('missing last layer')
check('UI does not expose a partial pack',not A.ready(ui,full)and A.background(ui,full)==nil)
local before=created;A.prepare(world);A.prepare(ui)
check('failed patch is not uploaded again every frame',created==before)
A.release(world);check('world partial release preserves UI partial handles',count()==expectedCount-1)
A.release(ui);check('both contexts delete every successful partial handle',count()==0 and deleted==2*(expectedCount-1))
missing=nil;A.prepare(world)
check('explicit lifecycle restart recovers missing foreground',A.ready(world,full)and count()==expectedCount)
A.release(world);check('recovered final layer releases',count()==0)
'''))
    cases.append(run_case('positive-wrong-dimension-placeholders', fixture(), r'''
badDecode=true;A.prepare(world);A.prepare(ui)
verifyFallback('positive 16x16 placeholders')
check('UI rejects positive placeholders',not A.ready(ui,full))
A.release(world);A.release(ui);check('all placeholder handles safely released',count()==0 and deleted==2*expectedCount)
'''))
    cases.append(run_case('rejected-pack-recovery-requires-lifecycle', fixture(43), r'''
A.prepare(world);check('initial rejection has no uploads',created==0)
table.remove(fixture.surfaceTiles)
A.prepare(world);verifyFallback('rejection is cached until explicit release')
check('changing data cannot cause hidden per-frame allocation',created==0)
A.release(world);A.prepare(world)
check('new entry within bound can recover',A.ready(world,full)and count()==42 and A.resourceError==nil)
A.release(world);check('recovered pack fully releases',count()==0)
'''))
    changed = [p for p, h in binding.items() if sha(ROOT / p) != h]
    rows = [r for c in cases for r in c['checks']]
    result = {'schema': 'fullbody-015-resource-budget-qa/v1',
              'createdUTC': datetime.datetime.now(datetime.UTC).isoformat(),
              'status': 'UNDETERMINED_INPUT_CHANGED' if changed else 'PASS' if all(r['pass'] for r in rows) else 'FAIL',
              'scope': 'SYNTHETIC_RESOURCE_BOUNDARIES_USING_PRODUCTION_MODULE',
              'candidateAcceptance': False, 'nativeEvidence': False,
              'resourceBudget': {'maxResourceSpecsPerContext': MAX_SPECS,
                                 'maxDecodedRGBABytesPerContext': MAX_BYTES},
              'caseCount': len(cases), 'passed': sum(r['pass'] for r in rows), 'total': len(rows),
              'inputHashes': binding, 'changedDuringChecks': changed, 'cases': cases,
              'limits': ['No PNGs or GPU/CPU image surfaces are allocated; virtual handles test the production loading/render API contract.',
                         'False draw and nil background prove the static caller fallback interface; actual native visuals are a separate new-batch check.',
                         'Finite decoded RGBA caps exclude mipmaps and driver storage. Actual candidate count, bytes, SHA, masks and native performance remain unverified by this report.',
                         'Legacy Data without resourceBudget is deliberately compatible. The new exporter must declare/enforce finite caps for fourth-batch candidate assets.']}
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + '\n')
    print(json.dumps({'status': result['status'], 'cases': len(cases), 'passed': result['passed'],
                      'total': result['total'], 'report': str(OUT.relative_to(ROOT)), 'sha256': sha(OUT)}))
    return 0 if result['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
