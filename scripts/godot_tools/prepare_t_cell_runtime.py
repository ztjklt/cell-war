#!/usr/bin/env python3
"""Prepare T-cell data and registration candidates; never change shared hooks/config/manifests.

All artwork remains unchanged. Throw-body and knife regions refer to the original
atlas; no painted poses, timing, pixels or alpha are regenerated here.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math
import shutil
from PIL import Image
from install_platelet import outline as source_outline

ROOT=Path(__file__).resolve().parents[2]
ART=ROOT/'assets/image/t-cell-cartoon-20261021'
GAME=ROOT/'godot'
ACTIONS={'tBlink':'blink-16','tThrow':'throw-16','tHit':'hit-12','tDeath':'death-12'}

def write(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')

def mapped_rect(frame,bounds,scale,pad=5):
    ox,oy=frame['registrationOffset']; a,b,c,d=bounds
    x=max(0,math.floor(ox+a*scale)-pad); y=max(0,math.floor(oy+b*scale)-pad)
    right=min(640,math.ceil(ox+c*scale)+pad); bottom=min(640,math.ceil(oy+d*scale)+pad)
    return {'x':x,'y':y,'w':right-x,'h':bottom-y}

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--stage-assets',action='store_true');args=parser.parse_args()
    # This is a draft authoring command, not a live balance reset. Once enabled,
    # install the explicitly edited runtime source with install_t_cell_assets.py.
    current=ART/'runtime.json'
    if current.exists() and json.loads(current.read_text()).get('runtimeIntegrated',False):
        raise RuntimeError('T-cell runtime is live; edit runtime.json explicitly and use install_t_cell_assets.py to preserve live tuning')
    clips,outlines,records={},{},[]
    release_frame=None; projectile_art=None
    for key,name in ACTIONS.items():
        folder=ART/name; doc=json.loads((folder/'animation.json').read_text())
        path=(folder/'spritesheet.png').relative_to(ROOT).as_posix()
        clips[key]={'path':path.removeprefix('assets/'),'frameSize':doc['width'],'columns':doc['columns'],'rows':doc['rows'],
                    'anchorX':doc['anchorX'],'anchorY':doc['anchorY'],'occupancy':doc['bodyDiameter']/doc['width'],
                    'duration':doc['durationMs']/1000,'durations':[f['duration']/1000 for f in doc['frames']]}
        outlines[key]=[]
        body_rects=[]
        for index,frame in enumerate(doc['frames']):
            image=Image.open(folder/frame['name']).convert('RGBA')
            radius=doc['bodyDiameter']/2
            points=source_outline(image)
            outlines[key].append([[round(((x*150+256)*doc['width']/512-doc['anchorX'])/radius,5),round(((y*150+300)*doc['width']/512-doc['anchorY'])/radius,5)] for x,y in points])
            components=frame['sourceComponents']
            body_rects.append(mapped_rect(frame,components[0]['bounds'],doc['fixedScale'],8))
            if key=='tThrow' and len(components)>1 and release_frame is None:
                release_frame=index
                r=mapped_rect(frame,components[1]['bounds'],doc['fixedScale'],8)
                projectile_art={'path':clips[key]['path'],'frame':index,'rect':r,'atlasRect':dict(r,x=r['x']+frame['rect']['x'],y=r['y']+frame['rect']['y']),
                                'pivot':[r['w']/2,r['h']/2],'nativeFacing':'left','widthInBodies':r['w']/doc['bodyDiameter']}
        if key=='tThrow': clips[key]['bodyRects']=body_rects
        target=GAME/path
        if args.stage_assets:
            target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/path,target)
        assert target.exists() and target.read_bytes()==(ROOT/path).read_bytes(),f'Runtime atlas differs: {path}'
        records.append({'source':path,'path':path,'bytes':target.stat().st_size,'sha256':hashlib.sha256(target.read_bytes()).hexdigest()})
    assert release_frame==7,'Review changed release art before changing gameplay timing'
    unit={'name':'T细胞','desc':'沿合法通路瞬身前进，投掷独立小刀；受击可打断未出手攻击。','at':'barracks','tier':2,'hp':105,'pop':2,
          'cost':{'wood':25,'food':20,'oxygen':5},'train':22,'damage':14,'range':6,'cool':1.4,'speed':3.0,'vision':11,'sprite':'t_cell','tCellRole':True}
    data={'schema':1,'name':'T细胞','unitKind':'t_cell','runtimeIntegrated':False,'unitDefinition':unit,'radius':.65,
          'character':'image/t-cell-cartoon-20261021/character-refined-v1.png','clips':clips,'outlines':outlines,
          'hull':[[round(math.cos(i*math.tau/16)*.83,5),round(math.sin(i*math.tau/16),5)] for i in range(16)],
          'blink':{'departure':.24,'arrival':.415,'cycle':clips['tBlink']['duration'],'distanceInBodiesCap':5.5,'hiddenFrames':[6,7],
                   'trailSeconds':.33,'maxGhosts':8,'budget':'One speed * cycle allowance per cadence; move multiplier shortens distance; no banking or reorder resets.',
                   'laneChange':'Stop and require host-certified gate transition; never blink across a lane boundary.'},
          'weapon':{'damage':14.0,'range':6.0,'cooldown':1.4,'speed':16.0,'radius':.08,'releaseFrame':release_frame,
                    'windup':sum(clips['tThrow']['durations'][:release_frame]),'animationDuration':clips['tThrow']['duration'],'style':'t_knife'},
          'projectileArt':projectile_art,'limits':{'actors':256,'projectiles':128,'events':256,'pathPoints':512,'substep':.025,'geometryStep':.2},
          'registration':'Independent service only. Register the unit and route T combat/movement/render/save hooks before enabling production. Generic fight/go must not also execute.',
          'artSemantics':'Original 56 frames, pivots, alpha and timing retained. Throw renders bodyRects only; separate projectile renders projectileArt from the same unchanged atlas.'}
    write(ART/'runtime.json',data);write(GAME/'data/t_cell.json',data)
    portrait=ART/'character-refined-v1.png';target=GAME/'assets'/portrait.relative_to(ROOT/'assets')
    if args.stage_assets: target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(portrait,target)
    assert target.read_bytes()==portrait.read_bytes()
    records.append({'source':portrait.relative_to(ROOT).as_posix(),'path':target.relative_to(GAME).as_posix(),'bytes':target.stat().st_size,'sha256':hashlib.sha256(target.read_bytes()).hexdigest()})
    target=GAME/'data/t_cell.json'
    records.append({'source':(ART/'runtime.json').relative_to(ROOT).as_posix(),'path':'data/t_cell.json','bytes':target.stat().st_size,'sha256':hashlib.sha256(target.read_bytes()).hexdigest()})
    write(GAME/'planning/gameplay-completion-20261021/t-cell-install-candidate.json',{'unitKind':'t_cell','unitDefinition':unit,'cellRadius':data['radius'],
        'cellFramesAsset':{'path':data['character'],'occupancy':.6},'cellFramesKind':'t_cell','unitOrderAfter':'dendritic_cell','assetManifestCandidates':records,
        'sharedFilesWritten':False,'hooksRequiredBeforeTraining':True})
    print(json.dumps({'frames':sum(len(c['durations']) for c in clips.values()),'releaseFrameOneBased':release_frame+1,'windupSeconds':data['weapon']['windup'],
                      'runtimeIntegrated':False,'sharedFilesWritten':False,'assetsVerified':len(records)-1},ensure_ascii=False))

if __name__=='__main__': main()
