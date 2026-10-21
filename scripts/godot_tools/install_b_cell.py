#!/usr/bin/env python3
"""Install B-cell move16, the unchanged original flower loop6 and side-fall death12."""
from pathlib import Path
import hashlib
import json
import math
import shutil
from PIL import Image
from install_platelet import outline as source_outline

ROOT=Path(__file__).resolve().parents[2]
ART=ROOT/'assets/image/b-cell-cartoon-20261021'
GAME=ROOT/'godot'
ACTIONS={'move':('bMove','move-16'),'buff':('bBuff','original-skill1-6'),'death':('bDeath','death-v2-12')}

def write(path,data):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')

def main():
    clips,outlines,deliveries={},{},[]
    for action,(key,folder_name) in ACTIONS.items():
        folder=ART/folder_name; doc=json.loads((folder/'animation.json').read_text())
        if action=='buff':
            # The six source PNGs and their atlas remain byte-for-byte original.
            # Registration follows the source pivot; the measured opaque core
            # is 421px wide in the original 576px canvas.
            doc.update({'columns':3,'rows':2,'anchorX':288,'anchorY':285,'bodyDiameter':421})
        frame_size=doc['width']
        radius=doc['bodyDiameter']/2
        path=(folder/'spritesheet.png').relative_to(ROOT).as_posix()
        clips[key]={'path':path.removeprefix('assets/'),'frameSize':frame_size,'columns':doc['columns'],'rows':doc['rows'],
                    'anchorX':doc['anchorX'],'anchorY':doc['anchorY'],'occupancy':doc['bodyDiameter']/frame_size,
                    'duration':doc['durationMs']/1000,'durations':[frame['duration']/1000 for frame in doc['frames']]}
        outlines[key]=[]
        for frame in doc['frames']:
            points=source_outline(Image.open(folder/frame['name']).convert('RGBA'))
            outlines[key].append([[round(((x*150+256)*frame_size/512-doc['anchorX'])/radius,5),round(((y*150+300)*frame_size/512-doc['anchorY'])/radius,5)] for x,y in points])
        deliveries.append(path)
    data={'schema':1,'name':'B细胞','unitKind':'b_cell','character':'image/b-cell-cartoon-20261021/character-refined-v1.png',
          'clips':clips,'outlines':outlines,'hull':[[round(math.cos(i*math.tau/16),5),round(math.sin(i*math.tau/16),5)] for i in range(16)],
          'aura':{'radius':6.0,'attackSpeedMultiplier':2.0,'stacking':'highest only','trigger':'stationary flower shaking','sameFactionOnly':True,'self':False,'buildings':False,'requiresClearSameLane':True},
          'noAttack':True,'note':'User chose unchanged original six-frame flower loop (150ms each) and a new twelve-frame intact side-fall death (120ms each). No shooting.'}
    write(ART/'runtime.json',data)
    deliveries += [(ART/'runtime.json').relative_to(ROOT).as_posix(),(ART/'character-refined-v1.png').relative_to(ROOT).as_posix()]
    manifest_path=GAME/'data/asset_manifest.json'; manifest={row['path']:row for row in json.loads(manifest_path.read_text())}
    for relative in deliveries:
        destination='data/b_cell.json' if relative.endswith('/runtime.json') else relative
        target=GAME/destination; target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(ROOT/relative,target)
        manifest[destination]={'source':relative,'path':destination,'bytes':target.stat().st_size,'sha256':hashlib.sha256(target.read_bytes()).hexdigest()}
    write(manifest_path,list(manifest.values()))
    source_path=GAME/'data/source_manifest.json'; source=json.loads(source_path.read_text())
    source['assets']=len(manifest); source['assetBytes']=sum(row['bytes'] for row in manifest.values()); write(source_path,source)
    config_path=GAME/'data/config.json'; config=json.loads(config_path.read_text())
    config['Data']['units'].setdefault('b_cell',{'name':'B细胞','desc':'停下摇花，使附近友军攻击速度变为2倍；不会攻击。','at':'barracks','hp':100,'damage':0,'cool':1,'range':0,'speed':2.3,'vision':11,'pop':1,'tier':1,'train':24,'cost':{'wood':20,'food':15},'sprite':'b_cell','supportCell':True})
    config['Data']['cellRadii']['b_cell']=.6875
    if 'b_cell' not in config['Data']['unitOrder']:
        config['Data']['unitOrder'].insert(config['Data']['unitOrder'].index('spear')+1,'b_cell')
    config['CellFrames']['assets']['b_cell']={'path':data['character'],'occupancy':.86}
    config['CellFrames']['kinds']['b_cell']='b_cell'
    write(config_path,config)
    print(json.dumps({'unit':'b_cell','frames':{key:len(clip['durations']) for key,clip in clips.items()},'attackSpeedMultiplier':2,'radius':6,'runtimeAssets':len(deliveries)},ensure_ascii=False))

if __name__=='__main__': main()
