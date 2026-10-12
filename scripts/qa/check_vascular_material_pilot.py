"""Read-only GPT vascular-material pilot checks; offline evidence, never native proof.

Run with the project QA dependencies, for example:
  PYTHONPATH=/tmp/reference-map-tools python3 scripts/qa/check_vascular_material_pilot.py
Only this pilot's qa/ output is written. Production geometry and images are read-only.
"""
from pathlib import Path
import argparse
import hashlib
import io
import json
import os
import sys

for path in ['/tmp/reference-map-tools', '/tmp/passage-tools314']:
    if Path(path).is_dir():
        sys.path.insert(0, path)
import numpy as np
from PIL import Image
from lupa.lua54 import LuaRuntime

ROOT = Path(__file__).resolve().parents[2]
DOC = ROOT / 'docs/body-life/vascular-art-study/vessel-material-pilot'
MODULE = 'war.VascularMaterialArt'
ZOOMS = [.085, .12, .149, .15, .151]
VIEWPORTS = [(1440, 900), (1024, 768), (844, 390), (430, 932), (360, 780)]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def baseline_check():
    baseline = json.loads((DOC / 'qa/frozen-baseline.json').read_text())
    rows = [{'path': path, 'beforeSha256': value, 'afterSha256': sha(ROOT / path),
             'unchanged': sha(ROOT / path) == value}
            for path, value in baseline['hashes'].items()]
    assert all(row['unchanged'] for row in rows), [row['path'] for row in rows if not row['unchanged']]
    return {'checked': len(rows), 'unchanged': True, 'files': rows}


RESOURCE_SETUP = r'''
package.path='scripts/?.lua;'..package.path
package.loaded['urhox-libs/UI']={}
NVG_IMAGE_GENERATE_MIPMAPS=1
local P=require('war.VascularMaterialArt')
local G=require('war.GastricArt');local A=require('war.OrganAtlasArt')
created,deleted,serial,draws=0,0,0,0
live={};failPath=false;failValue=0;placeholder=false
nvgCreateImage=function(vg,path)
 created=created+1
 if path==failPath then return failValue end
 serial=serial+1
 local isPilot=path:find('/vessel%-material%-pilot/')~=nil
 local sizes=resourceSizes[path] or {2160,2160}
 local w,h=sizes[1],sizes[2]
 if placeholder and isPilot then w,h=16,16 end
 live[serial]={vg=vg,path=path,w=w,h=h};return serial
end
nvgImageSize=function(vg,id)local h=assert(live[id]);assert(h.vg==vg);return h.w,h.h end
nvgDeleteImage=function(vg,id)
 assert(type(id)=='number' and id>0,'invalid handle deletion')
 assert(live[id]and live[id].vg==vg,'double/cross-context deletion')
 live[id]=nil;deleted=deleted+1
end
for _,name in ipairs({'nvgSave','nvgRestore','nvgBeginPath','nvgRect','nvgFillPaint'})do _G[name]=function()end end
nvgImagePattern=function(vg,x,y,w,h,angle,id,alpha)
 assert(live[id]and live[id].vg==vg,'wrong-context draw')
 lastPaint=live[id].path;return{}
end
nvgFill=function()draws=draws+1 end
local trial={anatomyVersion=4,organBattlefieldVersion=1,organBattlefieldIds={'stomach'}}
local gastric={anatomyVersion=4,gastricBattlefieldVersion=1}
local world,ui={},{}
local R={vg=world,project=function(_,x,y)return x,y end}
local game={zoom=.15,realTime=1.92}
local rows={}
local function check(name,ok)rows[#rows+1]={name=name,passed=ok};assert(ok,name)end
local function pilotCount()
 local count=0;for _,h in pairs(live)do if h.path:find('/vessel%-material%-pilot/')then count=count+1 end end;return count
end
'''


def resource_case(manifest, action):
    lua = LuaRuntime(unpack_returned_tuples=True)
    sizes = {}
    for asset in manifest['assets']:
        resource = asset['path'].removeprefix('assets/')
        sizes[resource] = lua.table_from(asset['pixelSize'])
    lua.globals().resourceSizes = lua.table_from(sizes)
    lua.execute(RESOURCE_SETUP + action)
    return [{'name': row['name'], 'passed': bool(row['passed'])}
            for _, row in lua.globals().resultRows.items()]


def resources_check(manifest):
    results = resource_case(manifest, r'''
P.prepare(world);P.prepare(ui)
check('two context pilot count',pilotCount()==4)
local first=created;P.prepare(world);P.prepare(ui)
check('prepare caches existing contexts',created==first)
check('both decoded contexts ready',P.ready(world,trial)and P.ready(ui,trial))
check('gastric trial is accepted',P.ready(world,gastric))
check('old anatomy rejected',not P.ready(world,{anatomyVersion=3,gastricBattlefieldVersion=1}))
check('normal campaign rejected',not P.ready(world,{anatomyVersion=4,campaign={}}))
check('other organ trial rejected',not P.ready(world,{anatomyVersion=4,organBattlefieldVersion=1,organBattlefieldIds={'brain'}}))
check('authored alpha endpoints',P.alpha(.085)==0 and math.abs(P.alpha(.15)-1)<1e-12)
check('monotone alpha',P.alpha(.149)<=P.alpha(.15)and P.alpha(.15)<=P.alpha(.151))
check('exterior draws when ready',P.draw(R,game,gastric,0,2048,512,3584)==true)
check('stomach replacement available',type(P.stomachImage(world,trial))=='number')
local before=created
for _=1,32 do P.draw(R,game,gastric,0,2048,512,3584);P.stomachImage(world,trial)end
check('draw creates no images',created==before)
local n=draws
check('invisible viewport skips exterior',P.draw(R,game,gastric,0,1,512,513)==false and draws==n)
for _=1,25 do P.release(ui);P.prepare(ui);check('reopen count bounded',pilotCount()==4)end
P.release(world);P.release(world)
check('world release preserves UI',pilotCount()==2 and P.ready(ui,trial))
P.release(ui);P.release(ui)
check('all dedicated images released',pilotCount()==0 and next(live)==nil)
resultRows=rows
''')
    results += resource_case(manifest, r'''
placeholder=true;P.prepare(world);P.prepare(ui)
check('positive decode placeholders rejected',not P.ready(world,trial)and not P.ready(ui,trial))
check('replacement unavailable before full decode',P.stomachImage(world,trial)==nil)
local n=draws;check('placeholder exterior stays static',not P.draw(R,game,gastric,0,2048,512,3584)and draws==n)
for _,h in pairs(live)do if h.vg==world then h.w,h.h=2160,2160 end end
check('world readiness advances independently',P.ready(world,trial)and not P.ready(ui,trial))
P.release(world);P.release(ui);check('placeholder handles released',next(live)==nil)
resultRows=rows
''')
    results += resource_case(manifest, r'''
placeholder=true;A.prepare(world);G.prepare(world)
check('accepted gastric fallback stays ready',A.ready(world,trial)and not P.ready(world,trial))
local n=draws
check('accepted stomach draws while pilot loads',G.draw(R,game,trial,0,2048,512,3584)and draws==n+1)
check('fallback uses accepted original stomach PNG',lastPaint=='image/anatomy-reference/vascular-study/stomach-playable/battlefield.png')
for _,h in pairs(live)do if h.vg==world and h.path:find('/vessel%-material%-pilot/')then h.w,h.h=2160,2160 end end
n=draws
check('ready pilot replaces one stomach draw',G.draw(R,game,trial,0,2048,512,3584)and draws==n+1)
check('ready stomach uses generated vascular overlay PNG',lastPaint=='image/anatomy-reference/vascular-study/vessel-material-pilot/battlefield.png')
G.release(world);A.release(world)
check('delegated gastric lifecycle releases pilot',next(live)==nil)
resultRows=rows
''')
    for asset in manifest['assets']:
        resource = asset['path'].removeprefix('assets/')
        for failure in ['nil', '0', '-1']:
            action = f"failPath={json.dumps(resource)};failValue={failure}\n" + r'''
P.prepare(world)
check('missing resource rejects complete pack',not P.ready(world,trial))
check('missing resource rejects stomach replacement',P.stomachImage(world,trial)==nil)
local n,c=draws,created
check('missing resource exterior is static',not P.draw(R,game,gastric,0,2048,512,3584)and draws==n)
for _=1,10 do P.draw(R,game,gastric,0,2048,512,3584);P.prepare(world)end
check('failure does not retry in draw/prepare',created==c)
P.release(world);P.release(world);check('partial successful handles released',next(live)==nil)
failPath=false;P.prepare(world)
check('explicit release permits recovery',P.ready(world,trial))
P.release(world);check('recovered resources release',next(live)==nil)
resultRows=rows
'''
            rows = resource_case(manifest, action)
            for row in rows:
                row['asset'] = asset['id']; row['failureValue'] = failure
            results.extend(rows)
    return {'passed': len(results), 'total': len(results), 'cases': results,
            'reopenCycles': 25, 'dedicatedImagesPeak': 4, 'dedicatedImagesAfterRelease': 0,
            'nativeEvidence': False, 'scope': 'Real Lua module; controlled NanoVG resource API and texture dimensions.'}


def manifest_check(manifest):
    assert manifest['schema'] == 'vascular-material-pilot/v1'
    rows = []
    for asset in manifest['assets']:
        path = ROOT / asset['path']; actual = Image.open(path)
        assert sha(path) == asset['sha256'], asset['id']
        assert list(actual.size) == asset['pixelSize'] == [2160, 2160], asset['id']
        assert asset['sourceBox'] == [464, 448, 644, 628], asset['id']
        rows.append({'id': asset['id'], 'path': asset['path'], 'sha256': sha(path),
                     'pixelSize': list(actual.size), 'sourceBox': asset['sourceBox']})
    assert {row['id'] for row in rows} == {'exterior', 'battlefield'}, rows
    return rows



def path_mask(path, box, size=(2160,2160)):
    import cairosvg
    x1,y1,x2,y2=box
    svg=(f'<svg xmlns="http://www.w3.org/2000/svg" width="{size[0]}" height="{size[1]}" '
         f'viewBox="{x1} {y1} {x2-x1} {y2-y1}"><path d="{path}" fill="white" fill-rule="evenodd"/></svg>')
    rgba=Image.open(io.BytesIO(cairosvg.svg2png(bytestring=svg.encode()))).convert('RGBA')
    return np.asarray(rgba)[:,:,3]


def green_candidates(rgba):
    # Same float-HSV boundary as the all-visible organ palette audit; a blue
    # vein cannot evade inspection by being assigned a blood/collision role.
    rgb=rgba[:,:,:3].astype(np.float32);high=rgb.max(axis=2);low=rgb.min(axis=2)
    chroma=high-low;den=np.where(chroma>0,chroma,1);hue=np.zeros(high.shape,dtype=np.float32)
    red=(rgb[:,:,0]==high)&(chroma>0);green=(rgb[:,:,1]==high)&~red&(chroma>0);blue=(chroma>0)&~red&~green
    hue[red]=((rgb[:,:,1]-rgb[:,:,2])/den)[red]%6
    hue[green]=((rgb[:,:,2]-rgb[:,:,0])/den)[green]+2
    hue[blue]=((rgb[:,:,0]-rgb[:,:,1])/den)[blue]+4;hue*=60
    alpha=rgba[:,:,3].astype(np.float32)/255
    return ((rgba[:,:,3]>0)&(hue>=70)&(hue<=202)&(chroma/np.where(high>0,high,1)>=25/255)
            &(high>=40)&(chroma>=12)&(chroma*alpha>=8))


def pixel_check(manifest):
    from PIL import ImageFilter
    geometry=json.loads((DOC/'geometry.json').read_text())
    assert geometry['schema']=='vascular-material-pilot-geometry/v1'
    box=geometry['sourceBox'];assert box==[464,448,644,628]
    assets={a['id']:ROOT/a['path']for a in manifest['assets']}
    exterior=np.asarray(Image.open(assets['exterior']).convert('RGBA'))
    battlefield=np.asarray(Image.open(assets['battlefield']).convert('RGBA'))
    baseline=np.asarray(Image.open(ROOT/'assets/image/anatomy-reference/vascular-study/stomach-playable/battlefield.png').convert('RGBA'))
    assert battlefield.shape==baseline.shape
    masks={k:path_mask(geometry[k],box)for k in ['exteriorPath','stomachBloodPath','foodPath','outerPath','wallPath','junctionPatchPath']}
    # 1 raster pixel = 1/12 source pixel; two pixels cover differing Cairo /
    # affine AA support, not a geometric passage or position adjustment.
    def aa_margin(mask):
        return np.asarray(Image.fromarray(mask).filter(ImageFilter.MaxFilter(5)))>0
    outside_exterior=int(((exterior[:,:,3]>0)&~aa_margin(masks['exteriorPath'])).sum())
    changed=np.any(battlefield!=baseline,axis=2)
    approved_blood=aa_margin(np.maximum(masks['stomachBloodPath'],masks['junctionPatchPath']))
    outside_blood=int((changed&~approved_blood).sum())
    protected_food=int((changed&(masks['foodPath']==255)&~aa_margin(masks['stomachBloodPath'])).sum())
    frozen=json.loads((DOC.parent/'final-reference-data.json').read_text());byid={e['id']:e for e in frozen['edges']}
    edge_rows=[]
    for edge in geometry['edges']:
        canonical=byid[edge['id']]
        assert (edge['a'],edge['b'],edge['system'],edge['widthSource'])==(canonical['a'],canonical['b'],canonical['system'],canonical['lumenWidthSource']),edge['id']
        edge_rows.append({'id':edge['id'],'nominalWidthSource':edge['widthSource'],'endpointsFrozen':True})
    # The accepted stomach contains allowed sage terrain; restrict this one
    # color query to new blood pixels, while all exterior and raw GPT material
    # colors are audited without a spatial exemption.
    blood_green=int((green_candidates(battlefield)&approved_blood).sum())
    palette=[{'kind':'compiled-exterior','path':str(assets['exterior'].relative_to(ROOT)),
              'sha256':sha(assets['exterior']),'greenPixels':int(green_candidates(exterior).sum())},
             {'kind':'compiled-stomach-vessels','path':str(assets['battlefield'].relative_to(ROOT)),
              'sha256':sha(assets['battlefield']),'greenPixels':blood_green}]
    for path in manifest['inputs']:
        if '/vessel-material-pilot/gpt-'not in path:continue
        rgba=np.asarray(Image.open(ROOT/path).convert('RGBA'))
        palette.append({'kind':'raw-GPT','path':path,'sha256':sha(ROOT/path),'greenPixels':int(green_candidates(rgba).sum())})
    result={'sourceFrame':box,'rasterPixelsPerSourcePixel':12,'changedStomachPixels':int(changed.sum()),
            'changedStomachPixelsOutsideApprovedBloodAndPatch':outside_blood,
            'exteriorAlphaPixelsOutsideApprovedFootprint':outside_exterior,
            'changedProtectedFoodPixels':protected_food,'antialiasMarginRasterPixels':2,
            'edgeContracts':edge_rows,'palette':palette,'stomachFoodInletIsCellEntry':geometry['foodInletCellEntry'],
            'hiddenMainTrunkPreserved':geometry['hiddenMainTrunkPreserved'],
            'nativeEvidence':False,'scope':'Final PNG alpha/color comparisons to frozen source-coordinate paths; accepted stomach floor is unchanged outside blood masks.'}
    write_json(DOC/'qa/pixel-report.json',result)
    assert outside_exterior==outside_blood==protected_food==0,result
    assert not geometry['foodInletCellEntry']and geometry['hiddenMainTrunkPreserved']
    assert all(row['greenPixels']<=8 for row in palette),palette
    return result


def render_check(manifest, out, animate=False):
    import body_life_backend as b
    lua, G = b.l, b.G
    lua.execute(r'''
S=require('war.OrganTrial').new(72026,{'stomach'})
P=require('war.VascularMaterialArt');A=require('war.OrganAtlasArt');GA=require('war.GastricArt')
Save=require('war.Save');U=require('war.Util');R=require('war.Render')
local function same(a,c)
 if type(a)~=type(c)then return false end;if type(a)~='table'then return a==c end
 for k,v in pairs(a)do if not same(v,c[k])then return false end end
 for k in pairs(c)do if a[k]==nil then return false end end;return true
end
qaSame=same;baseline=Save.snapshot(S);visibility=U.copy(S.factions[1].visible)
worldContext={};uiContext={};R.vg=worldContext;R.font=1
A.prepare(worldContext);GA.prepare(worldContext);A.prepare(uiContext);GA.prepare(uiContext)
require('war.Cells').init(worldContext);R.prepare(S)
assert(P.ready(worldContext,S)and P.ready(uiContext,S))
function configure(w,h,z,dpr,x,y)
 graphics={GetWidth=function()return w*dpr end,GetHeight=function()return h*dpr end,GetDPR=function()return dpr end}
 game={state=S,zoom=z,camera={x=x,y=y},realTime=1.92,flowTime=S.time,
  selection={},accumulator=0,started=true,fogDisabled=true}
 R.w,R.h=w,h
end
function stateUnchanged()
 return same(baseline,Save.snapshot(S))and same(visibility,S.factions[1].visible)
end
''')
    samples = []
    for w, h in VIEWPORTS:
        for dpr in [1, 2, 3]:
            for zoom in ZOOMS:
                b.reset(); G.qw=w;G.qh=h;G.qdpr=dpr;G.qz=zoom
                lua.execute(r'''
configure(qw,qh,qz,qdpr,1108,1588)
local x,y=R.project(game,1096.352,1516.064)
local wx,wy=R.unproject(game,x,y)
projectionError=math.max(math.abs(wx-1096.352),math.abs(wy-1516.064))
assert(projectionError<1e-8)
local expectedX=qw*.5+(1096.352-game.camera.x)*32*qz
local expectedY=qh*.47+(1516.064-game.camera.y)*32*qz
assert(math.abs(x-expectedX)<1e-8 and math.abs(y-expectedY)<1e-8)
R.draw(game);assert(stateUnchanged())
''')
                samples.append({'viewportLogical':[w,h], 'dpr':dpr, 'zoom':zoom,
                                'projectionError':float(G.projectionError), 'saveRngVisibilityUnchanged':True})
    frames = []
    views = [('gastric-entry', [548.176,502.032]), ('return-entry',[539,520]),
             ('tissue-gate',[565.0100505063389,503.98994949366113])]
    for name, center in views:
        near = []
        for zoom in ZOOMS:
            b.reset();G.qz=zoom;G.qx=center[0]*2;G.qy=center[1]*2+512
            lua.execute('configure(1024,768,qz,1,qx,qy);R.draw(game);assert(stateUnchanged())')
            raw=b.png(1024,768);path=out/'render'/f'{name}-z{zoom}.png'
            path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(raw)
            frames.append({'name':name,'sourceCenter':center,'zoom':zoom,'file':str(path.relative_to(DOC)), 'sha256':sha(path)})
            if zoom in [.149,.15,.151]:near.append(np.asarray(Image.open(io.BytesIO(raw)).convert('RGB'),dtype=np.int16))
        diffs=[float(np.abs(a-c).mean())for a,c in zip(near,near[1:])]
        assert max(diffs)<8,(name,'zoom discontinuity',diffs)
        frames[-1]['near015MeanRgbDifference']=diffs
    movement = None
    if animate:
        lua.execute(r"""
S=require('war.OrganTrial').new(72026,{'stomach'})
actor=nil;for _,e in pairs(S.entities)do if e.category=='unit'and e.kind=='scout'then actor=e;break end end
assert(actor);startPosition={x=actor.x,y=actor.y}
local data=require('war.GastricBattlefieldData')
gate=nil;for _,v in ipairs(data.gateContracts.scout)do if v.id=='gastric.local.northwest'then gate=v;break end end
assert(gate);local p=gate.pipeAnchorSource
assert(require('war.Commands').execute(S,{kind='move',ids={actor.id},faction=1,x=p[1]*2,y=p[2]*2+512,lane=gate.laneIndex}))
configure(1024,768,.15,1,1130,1512);game.selection={[actor.id]=true}
""")
        sequence=[];trace=[]
        for i in range(60):
            while float(G.S.time)+1e-7 < i*.25:
                lua.execute("require('war.Simulation').step(S,.1)")
            b.reset();G.qaTime=i*.25
            lua.execute("local snap=Save.snapshot(S);local seen=U.copy(S.factions[1].visible);game.realTime=qaTime;game.flowTime=S.time;R.draw(game);assert(qaSame(snap,Save.snapshot(S))and qaSame(seen,S.factions[1].visible))")
            sequence.append(Image.open(io.BytesIO(b.png(1024,768))).convert('RGB'))
            trace.append({'visualTime':i*.25,'simulationTime':float(G.S.time),
                          'source':[float(G.actor.x)/2,(float(G.actor.y)-512)/2],
                          'lane':int(G.actor.vesselLane or 0)})
        distance=np.linalg.norm(np.array(trace[-1]['source'])-np.array(trace[0]['source']))
        assert distance>1e-3,'production cell did not move'
        file=out/'render/production-entry-movement-15s.webp'
        sequence[0].save(file,save_all=True,append_images=sequence[1:],duration=250,loop=0,quality=86)
        movement={'file':str(file.relative_to(DOC)),'sha256':sha(file),'durationMs':15000,'frames':60,'fps':4,
                  'zoom':.15,'productionModules':['war.Simulation','war.OrganTrial','war.Commands','war.Path','war.CellCollision'],
                  'gateId':str(G.gate.id),'targetLane':int(G.gate.laneIndex),'trace':trace,
                  'distanceMovedSource':float(distance),'nativeEvidence':False}
    lua.execute('A.release(worldContext);GA.release(worldContext);A.release(uiContext);GA.release(uiContext);P.release(worldContext);P.release(uiContext)')
    pilot_live=sum('/vessel-material-pilot/'in tex.key for tex in b.image_handles.values())
    assert pilot_live==0
    return {'nativeEvidence':False, 'productionEntry':'war.Render.draw', 'actualAssetDecodeVerified':True,
            'samples':samples, 'frames':frames, 'movement':movement, 'logicalSourceScale':'64*zoom',
            'pixelScaleAt015':9.6, 'saveRngVisibilityUnchanged':True,
            'dedicatedImagesAfterRelease':pilot_live,
            'limitations':['SVG/Cairo approximates native GPU filtering and antialiasing.',
                           'These still frames do not certify continuous native movement or P95 frame time.']}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--phase',choices=['all','resources','render','pixels'],default='all')
    parser.add_argument('--animate',action='store_true',help='Also record 15-second production cell movement; all phase enables it automatically.')
    args=parser.parse_args();os.chdir(ROOT)
    manifest_path=DOC/'manifest.json';manifest=json.loads(manifest_path.read_text())
    assert all(sha(ROOT/path)==value for path,value in manifest['inputs'].items()), 'manifest input SHA mismatch'
    binding_files=['scripts/war/VascularMaterialArt.lua','scripts/war/GastricArt.lua',
                   'scripts/war/ReferenceArt.lua','scripts/war/Render.lua','scripts/war/OrganAtlasArt.lua',
                   'scripts/war/Cells.lua','scripts/war/BodyLifeFlow.lua',
                   'scripts/qa/body_life_backend.py','scripts/qa/check_vascular_material_pilot.py']
    binding={path:sha(ROOT/path)for path in binding_files}
    binding.update({a['path']:a['sha256']for a in manifest['assets']})
    binding.update({str(manifest_path.relative_to(ROOT)):sha(manifest_path)})
    result={'schema':'vascular-material-pilot-qa/v1','nativeEvidence':False,
            'manifestSha256':sha(manifest_path),'assets':manifest_check(manifest),
            'frozenBaseline':baseline_check(),'inputHashes':binding}
    result['pixels']=pixel_check(manifest)
    if args.phase in ['all','resources']:result['resources']=resources_check(manifest)
    if args.phase in ['all','render']:result['render']=render_check(manifest,DOC/'qa',animate=args.animate or args.phase=='all')
    result['frozenAfter']=baseline_check()
    result['changedDuringChecks']=[path for path,value in binding.items()if sha(ROOT/path)!=value]
    result['status']='PASS_OFFLINE'if not result['changedDuringChecks']else'UNDETERMINED_INPUT_CHANGED'
    assert not result['changedDuringChecks'],result['changedDuringChecks']
    write_json(DOC/'qa'/f'{args.phase}-report.json',result)
    print(json.dumps({'status':result['status'],'phase':args.phase,
         'resources':result.get('resources',{}).get('passed'),
         'renderSamples':len(result.get('render',{}).get('samples',[])),
         'frames':len(result.get('render',{}).get('frames',[]))}))


if __name__=='__main__':main()
