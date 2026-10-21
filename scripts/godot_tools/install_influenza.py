"""Install the reviewed influenza art into Godot without re-exporting Lua data."""
import hashlib
import json
import shutil
from pathlib import Path
import numpy as np
from PIL import Image
from shapely.geometry import box
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / 'assets/image/influenza-cartoon-v2-20261020'
GAME = ROOT / 'godot'
ACTIONS = {'move':'fluMove','attack':'fluAttack','hit':'fluHit','death':'fluDeath','build':'fluBuild'}


def write(path, value):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')


def outline(image):
    # Extract pixel runs at half resolution, then simplify the real alpha contour.
    mask = np.asarray(image.getchannel('A').resize((256,256),Image.Resampling.NEAREST)) >= 80
    runs = []
    for y,row in enumerate(mask):
        changes = np.diff(np.r_[False,row,False].astype(np.int8))
        for left,right in zip(np.flatnonzero(changes==1),np.flatnonzero(changes==-1)):
            runs.append(box(int(left)*2,y*2,int(right)*2,(y+1)*2))
    if not runs: return []
    shape = unary_union(runs)
    if shape.geom_type == 'MultiPolygon': shape = max(shape.geoms,key=lambda item:item.area)
    points = shape.simplify(1.5,preserve_topology=True).exterior.coords
    return [[round((x-256)/145,5),round((y-275)/145,5)] for x,y in list(points)[:-1]]


def main():
    clips, silhouettes, deliveries = {}, {}, []
    for action,key in ACTIONS.items():
        folder = ART / (action+'-20')
        animation = json.loads((folder/'animation.json').read_text())
        relative = (folder/'spritesheet.png').relative_to(ROOT).as_posix()
        clips[key] = {'path':relative.removeprefix('assets/'),'frameSize':512,'columns':5,'rows':4,
                      'anchorX':256,'anchorY':275,'occupancy':290/512,
                      'duration':animation['durationMs']/1000,
                      'durations':[frame['duration']/1000 for frame in animation['frames']]}
        silhouettes[key] = [outline(Image.open(folder/frame['name']).convert('RGBA'))
                            if action != 'death' else [] for frame in animation['frames']]
        deliveries.append(relative)
    registration = {'schema':1,'name':'流感病毒','unitKind':'virus','approved':'2026-10-20',
                    'character':'image/influenza-cartoon-v2-20261020/character-evil-v1.png',
                    'clips':clips,'outlines':silhouettes,
                    'construction':'fluBuild is used by ten retained virus builders to construct flu_fortress; each completed fortress produces one virus every thirty seconds.'}
    write(ART/'runtime.json',registration)
    deliveries.extend([(ART/'character-evil-v1.png').relative_to(ROOT).as_posix(),
                       (ART/'runtime.json').relative_to(ROOT).as_posix()])
    manifest_path = GAME/'data/asset_manifest.json'
    manifest = json.loads(manifest_path.read_text())
    by_path = {row['path']:row for row in manifest}
    for source in deliveries:
        destination = 'data/influenza.json' if source.endswith('/runtime.json') else source
        target = GAME/destination
        target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(ROOT/source,target)
        by_path[destination] = {'source':source,'path':destination,'bytes':target.stat().st_size,
                               'sha256':hashlib.sha256(target.read_bytes()).hexdigest()}
    updated = list(by_path.values())
    write(manifest_path,updated)
    baseline_path = GAME/'data/source_manifest.json'
    baseline = json.loads(baseline_path.read_text())
    baseline['assets'] = len(updated)
    baseline['assetBytes'] = sum(row['bytes'] for row in updated)
    # Keep the original Lua source hashes; this is an explicit reviewed Godot art addition.
    write(baseline_path,baseline)
    config_path = GAME/'data/config.json'
    config = json.loads(config_path.read_text())
    config['Data']['units']['virus']['name'] = registration['name']
    config['CellFrames']['assets']['influenza'] = {'path':registration['character'],'occupancy':.85}
    config['CellFrames']['kinds']['virus'] = 'influenza'
    write(config_path,config)
    print(json.dumps({'registered':'virus','name':registration['name'],'actions':list(ACTIONS),
                      'framesPerAction':20,'runtimeAssets':len(deliveries)},ensure_ascii=False))


if __name__ == '__main__': main()
