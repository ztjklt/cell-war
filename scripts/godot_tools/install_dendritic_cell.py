#!/usr/bin/env python3
"""Install self-contained dendritic reconnaissance assets and first balance defaults."""
from pathlib import Path
import hashlib
import json
import math
import shutil
import sys
from PIL import Image
from install_platelet import outline as source_outline

ROOT=Path(__file__).resolve().parents[2]
ART=ROOT/'assets/image/dendritic-cell-cartoon-20261021'
GAME=ROOT/'godot'
sys.path.insert(0,str(ROOT/'scripts/sprite_preview'))
from package_t_cell import body_core

ACTIONS={'dcMove':'move-16','dcScan':'original-skill1-6','dcHit':'hit-12','dcDeath':'death-12'}

def write(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')

def main():
    clips,outlines,deliveries={},{},[]
    for key,folder_name in ACTIONS.items():
        folder=ART/folder_name; doc=json.loads((folder/'animation.json').read_text())
        if key=='dcScan':
            core=body_core(Image.open(folder/doc['frames'][0]['name']).convert('RGBA'))
            doc.update({'anchorX':(core[0]+core[2])/2,'anchorY':(core[1]+core[3])/2,'bodyDiameter':core[3]-core[1]+30})
        size=doc['width']; radius=doc['bodyDiameter']/2
        path=(folder/'spritesheet.png').relative_to(ROOT).as_posix()
        clips[key]={'path':path.removeprefix('assets/'),'frameSize':size,'columns':doc['columns'],'rows':doc['rows'],
                    'anchorX':doc['anchorX'],'anchorY':doc['anchorY'],'occupancy':doc['bodyDiameter']/size,
                    'duration':doc['durationMs']/1000,'durations':[f['duration']/1000 for f in doc['frames']]}
        outlines[key]=[]
        for frame in doc['frames']:
            points=source_outline(Image.open(folder/frame['name']).convert('RGBA'))
            outlines[key].append([[round(((x*150+256)*size/512-doc['anchorX'])/radius,5),round(((y*150+300)*size/512-doc['anchorY'])/radius,5)] for x,y in points])
        deliveries.append(path)
    data={'schema':1,'name':'树突状细胞','unitKind':'dendritic_cell','character':'image/dendritic-cell-cartoon-20261021/character-refined-v1.png',
          'clips':clips,'outlines':outlines,'hull':[[round(math.cos(i*math.tau/16)*.8,5),round(math.sin(i*math.tau/16),5)] for i in range(16)],
          'scan':{'radius':8.0,'moveMultiplier':.7,'attackSpeedMultiplier':.7,'stacking':'highest only','trigger':'stationary reconnaissance','enemyUnitsOnly':True,'requiresClearSameLane':True,'detectConcealed':True,'concealmentFields':['burrowed','concealed']},
          'noAttack':True,'note':'User chose both movement and attack slowdown. Original six-frame sequential lamps retained exactly. Radius and 30 percent reductions are first balance defaults.'}
    write(ART/'runtime.json',data)
    deliveries += [(ART/'runtime.json').relative_to(ROOT).as_posix(),(ART/'character-refined-v1.png').relative_to(ROOT).as_posix()]
    manifest_path=GAME/'data/asset_manifest.json';manifest={row['path']:row for row in json.loads(manifest_path.read_text())}
    for relative in deliveries:
        destination='data/dendritic_cell.json' if relative.endswith('/runtime.json') else relative
        target=GAME/destination;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/relative,target)
        manifest[destination]={'source':relative,'path':destination,'bytes':target.stat().st_size,'sha256':hashlib.sha256(target.read_bytes()).hexdigest()}
    write(manifest_path,list(manifest.values()))
    path=GAME/'data/source_manifest.json';source=json.loads(path.read_text());source['assets']=len(manifest);source['assetBytes']=sum(row['bytes'] for row in manifest.values());write(path,source)
    path=GAME/'data/config.json';config=json.loads(path.read_text())
    config['Data']['units'].setdefault('dendritic_cell',{'name':'树突状细胞','desc':'停下侦察，精确标记敌人并降低其移动和攻击速度；可标记地下目标。','at':'barracks','hp':110,'damage':0,'cool':1,'range':0,'speed':2.1,'vision':8,'pop':1,'tier':1,'train':26,'cost':{'wood':20,'food':20},'sprite':'dendritic_cell','supportCell':True})
    config['Data']['cellRadii']['dendritic_cell']=.8
    if 'dendritic_cell' not in config['Data']['unitOrder']:
        config['Data']['unitOrder'].insert(config['Data']['unitOrder'].index('b_cell')+1,'dendritic_cell')
    config['CellFrames']['assets']['dendritic_cell']={'path':data['character'],'occupancy':.6}
    config['CellFrames']['kinds']['dendritic_cell']='dendritic_cell'
    write(path,config)
    print(json.dumps({'unit':'dendritic_cell','frames':{key:len(clip['durations']) for key,clip in clips.items()},'slowBoth':.7,'radius':8,'runtimeAssets':len(deliveries)}))

if __name__=='__main__': main()
