#!/usr/bin/env python3
"""Audit/stage three pathogen animation deliveries without editing the live game.

Default mode is dry-run. --report writes audit evidence and candidate registration
JSON only. --apply --stage-dir copies a self-contained review bundle into a NEW
isolated directory; the live godot/ tree and original artwork are refused targets.
This tool never edits config.json, global resource manifests or runtime scripts.
Offline dependencies: Pillow, numpy, shapely (available in the retained art env).
"""
import argparse
import hashlib
import json
import shutil
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import numpy as np
from PIL import Image
from shapely.geometry import box
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT/'godot'
SPEC = {
    'influenza': ('流感病毒','influenza-cartoon-v2-20261020',20,'virus'),
    'pneumococcus': ('肺炎链球菌','pneumococcus-cartoon-v2-20261021',16,None),
    'adenovirus': ('腺病毒','adenovirus-cartoon-v2-20261021',16,None),
}


def read(path):
    return json.loads(path.read_text())


def encoded(data):
    return (json.dumps(data,ensure_ascii=False,indent=2)+'\n').encode()


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def relative(path):
    return path.relative_to(ROOT).as_posix()


def bounds(alpha, threshold):
    yy,xx=np.nonzero(alpha>=threshold)
    return [int(xx.min()),int(yy.min()),int(xx.max())+1,int(yy.max())+1] if len(xx) else None


def contours(image):
    """Visual alpha polygons at 2px resolution, including disconnected fragments.

    These are inspection/selection candidates, not approved combat hitboxes.
    Impact stars, shockwaves and stalks must not inflate a future standing hull.
    """
    small=np.asarray(image.getchannel('A').resize((256,256),Image.Resampling.NEAREST))>=80
    runs=[]
    for y,row in enumerate(small):
        edges=np.diff(np.r_[False,row,False].astype(np.int8))
        runs.extend(box(int(l)*2,y*2,int(r)*2,(y+1)*2)
                    for l,r in zip(np.flatnonzero(edges==1),np.flatnonzero(edges==-1)))
    if not runs: return [],0
    shape=unary_union(runs)
    polygons=list(shape.geoms) if shape.geom_type=='MultiPolygon' else [shape]
    result=[]
    for polygon in sorted(polygons,key=lambda p:p.area,reverse=True):
        if polygon.area<4: continue
        polygon=polygon.simplify(1.5,preserve_topology=True)
        if not polygon.is_valid: raise ValueError('Invalid extracted alpha contour')
        result.append({'outer':[[round(x,2),round(y,2)] for x,y in list(polygon.exterior.coords)[:-1]],
                       'holes':[[[round(x,2),round(y,2)] for x,y in list(h.coords)[:-1]] for h in polygon.interiors],
                       'areaPx2':round(polygon.area,2)})
    return result,int(np.count_nonzero(small))*4


def file_row(source,destination=None):
    dest=destination or relative(source)
    live=GAME/dest
    return {'source':relative(source),'destination':dest,'bytes':source.stat().st_size,
            'sha256':sha(source),'liveExists':live.is_file(),
            'liveMatches':live.is_file() and sha(live)==sha(source)}


def inspect_clip(path,expected):
    data=read(path); folder=path.parent
    count=len(data['frames'])
    if count!=expected or data['frameCount']!=expected: raise ValueError(f'Wrong frame count: {path}')
    if len(list(folder.glob('frame-*.png')))!=expected: raise ValueError(f'Wrong PNG count: {path}')
    atlas_path=folder/data['spritesheet']; atlas=Image.open(atlas_path).convert('RGBA')
    if atlas.size!=(int(data['columns'])*512,int(data['rows'])*512): raise ValueError(f'Wrong atlas size: {path}')
    webp=Image.open(folder/data['preview'])
    if webp.n_frames!=expected: raise ValueError(f'Wrong WebP frame count: {path}')
    checks=[]; frames=[]; hashes=[]; warnings=[]; anchors=set()
    for i,entry in enumerate(data['frames']):
        frame=Image.open(folder/entry['name'])
        if frame.mode!='RGBA' or frame.size!=(512,512): raise ValueError(f'Wrong PNG format: {folder/entry["name"]}')
        pixels=np.asarray(frame); alpha=pixels[:,:,3]
        if np.any(np.r_[alpha[0],alpha[-1],alpha[:,0],alpha[:,-1]]): raise ValueError(f'Paint touches canvas border: {path} frame {i+1}')
        r=entry['rect']
        if r['w']!=512 or r['h']!=512 or atlas.crop((r['x'],r['y'],r['x']+512,r['y']+512)).tobytes()!=frame.tobytes():
            raise ValueError(f'Atlas differs from PNG: {path} frame {i+1}')
        duration=entry['duration']
        if not isinstance(duration,(int,float)) or duration<=0: raise ValueError(f'Bad duration: {path}')
        anchor=[float(entry['anchor']['x'])*512,float(entry['anchor']['y'])*512]
        if not all(0<=v<=512 for v in anchor): raise ValueError(f'Invalid anchor: {path}')
        anchors.add(tuple(anchor))
        polys,mask_area=contours(frame)
        solid=bounds(alpha,64); rgb=pixels[:,:,:3].astype(float)
        red,green,blue=rgb[:,:,0],rgb[:,:,1],rgb[:,:,2]
        matte=int(np.count_nonzero((alpha>=64)&(green>100)&(red<green*.55)&(blue<green*.75)))
        if matte>max(50,mask_area*.005): warnings.append(f'frame {i+1}: {matte} saturated-green pixels; visual edge review required')
        if entry.get('visibleBounds') is not None and list(entry['visibleBounds'])!=solid:
            warnings.append(f'frame {i+1}: recorded visibleBounds differs from alpha>=64; actual bounds retained')
        digest=hashlib.sha256(frame.tobytes()).hexdigest(); hashes.append(digest)
        yy,xx=np.nonzero(alpha>=128)
        checks.append({'frame':i+1,'sha256':digest,'durationMs':duration,'alphaBounds':bounds(alpha,1),
                       'opaqueBounds':solid,'opaquePixels':int(np.count_nonzero(alpha>=64)),
                       'opaqueCentroidPx':[round(float(xx.mean()),3),round(float(yy.mean()),3)] if len(xx) else None,
                       'transparentBorder':True,'contourCount':len(polys),'matteGreenPixels':matte})
        frames.append({'rect':r,'durationMs':duration,'anchorPx':anchor,
                       'visualAlphaContoursPx':polys,'contourRasterAreaPx2':mask_area})
    if len(set(hashes))!=expected: raise ValueError(f'Duplicate frame content: {path}')
    duration=sum(e['duration'] for e in data['frames'])
    if duration!=data['durationMs']: raise ValueError(f'Duration sum differs: {path}')
    death=data['animation']=='death'
    if death and checks[-1]['alphaBounds'] is not None: raise ValueError(f'Death final frame is not transparent: {path}')
    if len(anchors)!=1: warnings.append('Source has changing frame anchors; inspect before runtime conversion')
    source_hash_checked=False
    if data.get('source') and data.get('sourceSHA256'):
        source=(folder/data['source']).resolve()
        if not source.is_relative_to(ROOT) or not source.is_file() or sha(source)!=data['sourceSHA256']:
            raise ValueError(f'Source provenance differs: {path}')
        source_hash_checked=True
    events={k:data[k] for k in ['releaseFrame','chargeFrames','apexFrame','impactFrame','shockwaveFrames','impactSide','recoilDirection','facing','bodyFacing','baseGaze','mirrored'] if k in data}
    for name in ['releaseFrame','apexFrame','impactFrame']:
        if name in events:
            f=int(events[name])
            if not 1<=f<=count: raise ValueError(f'Bad event frame: {path}')
            events[name.removesuffix('Frame')+'AtMs']=sum(e['duration'] for e in data['frames'][:f-1])
    candidate={'texture':'res://'+relative(atlas_path),'frameCount':count,'frameSize':512,
               'columns':data['columns'],'rows':data['rows'],'durationMs':duration,
               'loop':data.get('loop',False),'frames':frames,'events':events}
    report={'action':data['animation'],'metadata':relative(path),'metadataSHA256':sha(path),
            'frames':count,'uniqueFrames':len(set(hashes)),'webpFrames':webp.n_frames,
            'durationMs':duration,'loop':data.get('loop',False),'anchorsPx':[list(a) for a in sorted(anchors)],
            'lastFrameFullyTransparent':checks[-1]['alphaBounds'] is None,
            'sourceProvenanceChecked':source_hash_checked,'events':events,'warnings':warnings,
            'frameChecks':checks,'atlas':file_row(atlas_path)}
    if data.get('impactSide') in ['left','right']:
        dx=checks[6]['opaqueCentroidPx'][0]-checks[0]['opaqueCentroidPx'][0]
        good=dx>0 if data['impactSide']=='left' else dx<0
        report['directionCheck']={'impactSide':data['impactSide'],'recoilAtFrame7DxPx':round(dx,3),
                                  'recoilSignMatches':good,'mirrored':data.get('mirrored')}
        if not good: raise ValueError(f'Recoil direction differs from impact metadata: {path}')
    return report,candidate


def build():
    config=read(GAME/'data/config.json')
    catalogue=read(GAME/'data/character_catalogue.json')
    catalogue={e['id']:e for e in catalogue['entries']}
    rows={}; characters=[]; candidates={}
    watched=['data/config.json','data/asset_manifest.json','data/source_manifest.json','data/character_catalogue.json',
             'scripts/simulation.gd','scripts/combat.gd','scripts/world_view.gd','scripts/hud.gd',
             'scripts/cell_shape.gd','scripts/influenza_animation.gd','scripts/influenza_colonies.gd']
    snapshot={p:sha(GAME/p) for p in watched}
    for id,(name,folder,expected,kind) in SPEC.items():
        base=ROOT/'assets/image'/folder; manifest=read(base/'animations.json')
        entry=catalogue.get(kind or id,{})
        art_files=[base/manifest['baseCharacter']]
        if manifest.get('projectileAppearance'): art_files.append(base/manifest['projectileAppearance'])
        for f in art_files: rows[relative(f)]=file_row(f)
        clips=[]; candidate_clips={}
        for label,ref in manifest.items():
            if not isinstance(ref,str) or not ref.endswith('/animation.json'): continue
            report,candidate=inspect_clip(base/ref,expected)
            report['label']=label; clips.append(report)
            candidate_clips[report['action']]=candidate
            rows[report['atlas']['destination']]=report['atlas']
        active=kind is not None and kind in config['Data']['units']
        status={'id':id,'name':name,'sourceFolder':relative(base),'manifestSHA256':sha(base/'animations.json'),
                'battleKind':kind if active else None,'proposedBattleKind':kind or id,
                'presentInDataUnits':(kind or id) in config['Data']['units'],
                'catalogueStatus':entry.get('status'),'catalogueKind':entry.get('kind'),
                'catalogueActionCount':len(entry.get('actions',[])),
                'sourceFrameCount':sum(c['frames'] for c in clips),'actions':clips}
        candidate={'schema':1,'name':name,'proposedBattleKind':kind or id,'battleEnabled':False,
                   'scope':'Offline review delivery only. This JSON does not register a unit or implement mechanics.',
                   'portrait':'res://'+relative(art_files[0]),'clips':candidate_clips,
                   'contourPolicy':'Visual alpha contours only, 2px raster threshold 80 with 1.5px simplification. Includes effects and shards. Do not use animated effects as physical contact hulls.',
                   'physicsPolicy':'Keep existing influenza standing hull. New kinds require separately reviewed standing body hull/radius and explicit renderer facing policy.'}
        if id=='influenza':
            candidate['existingBattleRegistration']=read(GAME/'data/influenza.json')
            candidate['sourcePreviewVsBattleAnchor']='Preview PNG anchors differ from existing battle (256,275). Keep the existing battle anchor/occupancy pair together.'
        candidates['data/pathogen_delivery/'+id+'.json']=candidate
        characters.append(status)
    extra=[(ROOT/'assets/image/influenza-cartoon-v2-20261020/runtime.json','data/influenza.json'),
           (ROOT/'assets/image/influenza-fortress-20261020/fortress.json','data/influenza_fortress.json'),
           (ROOT/'assets/image/influenza-fortress-20261020/fortress-simple-v2.png',None)]
    for path,dest in extra:
        row=file_row(path,dest); rows[row['destination']]=row
    after={p:sha(GAME/p) for p in watched}
    tests={}
    for test in ['influenza','influenza-fortress']:
        path=GAME/'test-output'/(test+'.json')
        tests[test]={'report':relative(path),'result':read(path)} if path.exists() else {'status':'not run'}
    report={'schema':1,'scope':'Three pathogen asset delivery and read-only integration audit; not full-game acceptance.',
            'generatedAt':datetime.now(ZoneInfo('Asia/Shanghai')).isoformat(),
            'mode':'dry-run','copiedFiles':0,'runtimeScriptsEdited':False,'globalManifestsEdited':False,
            'totalActions':sum(len(c['actions']) for c in characters),
            'totalFrames':sum(c['sourceFrameCount'] for c in characters),
            'characters':characters,'copyPlan':list(rows.values()),
            'candidateRegistrations':[{'destination':p,'bytes':len(encoded(v)),'sha256':hashlib.sha256(encoded(v)).hexdigest()} for p,v in candidates.items()],
            'runtimeSnapshotSHA256':snapshot,'concurrentRuntimeChanges':[p for p in watched if snapshot[p]!=after[p]],
            'observedTargetedTests':tests,'warnings':[w for c in characters for a in c['actions'] for w in a['warnings']]}
    return report,candidates


def stage(report,candidates,target):
    target=target.resolve()
    if target.is_relative_to(GAME) or target.is_relative_to(ROOT/'assets') or target==ROOT or target.exists():
        raise ValueError('Staging requires a NEW directory outside live godot/ and source assets/')
    target.mkdir(parents=True)
    for row in report['copyPlan']:
        source=ROOT/row['source']; destination=target/row['destination']
        destination.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(source,destination)
        if sha(destination)!=row['sha256']: raise ValueError('Staged copy hash mismatch')
    for path,data in candidates.items():
        destination=target/path; destination.parent.mkdir(parents=True,exist_ok=True)
        destination.write_bytes(encoded(data))
        for clip in data['clips'].values():
            if not (target/clip['texture'].removeprefix('res://')).is_file(): raise ValueError('Staged texture dependency missing')
    report.update(mode='isolated-stage',stagingDirectory=str(target),copiedFiles=len(report['copyPlan']),generatedFiles=len(candidates))
    (target/'delivery-manifest.json').write_bytes(encoded(report))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    mode=parser.add_mutually_exclusive_group()
    mode.add_argument('--dry-run',action='store_true',help='Audit/plan without copying game assets (default)')
    mode.add_argument('--apply',action='store_true',help='Copy only to a new isolated --stage-dir')
    parser.add_argument('--stage-dir',type=Path)
    parser.add_argument('--report',type=Path,help='Save audit JSON and candidate registrations beside it')
    args=parser.parse_args()
    if args.apply and args.stage_dir is None: parser.error('--apply requires --stage-dir')
    if args.stage_dir is not None and not args.apply: parser.error('--stage-dir requires --apply')
    if args.report:
        output=args.report.resolve()
        if output.suffix!='.json' or output.is_relative_to(ROOT/'assets') or (output.is_relative_to(GAME) and not output.is_relative_to(GAME/'planning') and not output.is_relative_to(GAME/'test-output')):
            parser.error('--report must be audit JSON outside source assets and live game data/scripts')
    report,candidates=build()
    if args.apply: stage(report,candidates,args.stage_dir)
    if args.report:
        args.report.parent.mkdir(parents=True,exist_ok=True)
        candidate_dir=args.report.parent/(args.report.stem+'-candidates')
        for path,data in candidates.items():
            destination=candidate_dir/Path(path).name
            destination.parent.mkdir(parents=True,exist_ok=True); destination.write_bytes(encoded(data))
        report['candidateReportDirectory']=str(candidate_dir)
        args.report.write_bytes(encoded(report))
    print(json.dumps({k:report[k] for k in ['mode','totalActions','totalFrames','copiedFiles','warnings','concurrentRuntimeChanges']},ensure_ascii=False))


if __name__=='__main__':main()
