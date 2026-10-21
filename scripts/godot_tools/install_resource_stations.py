#!/usr/bin/env python3
"""Copy GPT originals unchanged and register self-contained resource station art."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT / 'godot'
ART = ROOT / 'assets/image/organ-resource-stations-20261021'

def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--friendly-buildings', action='store_true', help='Also register the selected original-alpha friendly building art')
    options = parser.parse_args()
    manifest_path = GAME/'data/asset_manifest.json'
    manifest = {row['path']: row for row in json.loads(manifest_path.read_text())}
    records = []
    generated = {
        'oxygen': 'exec-462f3065-3955-4167-b734-a33081358905.png',
        'glucose': 'exec-028b9fe2-04d1-4728-b72e-86a6f6c2b658.png',
        'protein': 'exec-dace8fb8-4762-49bb-85fb-3f4284b4e75b.png',
    }
    for name, original in generated.items():
        source = ART/f'{name}-station-v1.png'
        picture = Image.open(source)
        assert picture.mode == 'RGBA', (name, 'missing alpha')
        alpha = picture.getchannel('A')
        raw_bounds = alpha.getbbox()
        # The generator leaves near-transparent (alpha 1–7) pixels outside the
        # visible silhouette. Audit visible padding without modifying its alpha.
        bounds = alpha.point(lambda value: 255 if value >= 8 else 0).getbbox()
        assert alpha.getextrema() == (0, 255) and bounds
        assert bounds[0] > 0 and bounds[1] > 0 and bounds[2] < picture.width and bounds[3] < picture.height, (name, bounds)
        relative = source.relative_to(ROOT).as_posix()
        target = GAME/relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        manifest[relative] = {'source':relative,'path':relative,'bytes':source.stat().st_size,'sha256':digest}
        records.append({'name':name,'source':relative,'runtime':'godot/'+relative,'generator':'built-in image_gen',
                        'generatedOriginal':original,'prompt':name+'-prompt.txt','size':list(picture.size),
                        'alphaBounds':list(raw_bounds),'visibleAlphaBounds':list(bounds),
                        'sha256':digest,'pixelsChanged':False})
    write(ART/'generation-records.json', records)
    if options.friendly_buildings:
        building_art = ROOT/'assets/image/friendly-buildings-20261021'
        metadata = json.loads((building_art/'friendly_buildings.json').read_text())
        metadata['runtimeRendererConnected'] = True
        metadata['rawAlphaPreserved'] = True
        metadata['runtimeSelection'] = 'Original GPT pixels and alpha; intermediate cleaned variants retained only as source history.'
        for kind, spec in metadata['buildings'].items():
            spec['texture'] = f'image/friendly-buildings-20261021/source-{kind}-v1.png'
            spec['sha256'] = hashlib.sha256((GAME.parent/'assets'/spec['texture']).read_bytes()).hexdigest()
            spec['rawAlphaPreserved'] = True
        phase2_source = building_art/'phase2/friendly_buildings_phase2.json'
        if phase2_source.exists():
            phase2 = json.loads(phase2_source.read_text())
            assert phase2.get('rawAlphaPreserved') is True
            assert not set(metadata['buildings']).intersection(phase2['buildings'])
            metadata['buildings'].update(phase2['buildings'])
            metadata['name'] = '友军建筑两批静态原画'
            metadata['sourceBatches'] = ['friendly_buildings.json', 'phase2/friendly_buildings_phase2.json']
        for kind, spec in metadata['buildings'].items():
            relative = 'assets/'+spec['texture']
            source = ROOT/relative
            target = GAME/relative
            assert source.is_file() and source.resolve().is_relative_to(building_art.resolve())
            if spec.get('sha256'):
                assert hashlib.sha256(source.read_bytes()).hexdigest() == spec['sha256'], kind
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source,target)
            manifest[relative] = {'source':relative,'path':relative,'bytes':source.stat().st_size,'sha256':hashlib.sha256(source.read_bytes()).hexdigest()}
        source = building_art/'runtime_buildings.json'
        write(source,metadata)
        relative = 'data/friendly_buildings.json'
        shutil.copy2(source,GAME/relative)
        manifest[relative] = {'source':source.relative_to(ROOT).as_posix(),'path':relative,'bytes':source.stat().st_size,'sha256':hashlib.sha256(source.read_bytes()).hexdigest()}
    write(manifest_path,list(manifest.values()))
    source_path = GAME/'data/source_manifest.json'
    summary = json.loads(source_path.read_text())
    summary.update(assets=len(manifest), assetBytes=sum(row['bytes'] for row in manifest.values()))
    write(source_path,summary)
    print(json.dumps({'installed':len(records),'unchangedOriginalPixels':True,'records':records},ensure_ascii=False))

if __name__ == '__main__':
    main()
