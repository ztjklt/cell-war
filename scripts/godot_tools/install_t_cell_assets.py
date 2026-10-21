#!/usr/bin/env python3
"""Install/audit T-cell media and data, without enabling units or shared runtime hooks."""
from pathlib import Path
from zipfile import ZipFile
import hashlib
import json
import os
import shutil
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
ART=ROOT/'assets/image/t-cell-cartoon-20261021'
GAME=ROOT/'godot'
ACTIONS={'tBlink':'blink-16','tThrow':'throw-16','tHit':'hit-12','tDeath':'death-12'}

def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def write(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')

def replace_if_unchanged(path,original,value):
    """Do not overwrite a concurrent manifest edit read during this merge."""
    temp=path.with_name(path.name+f'.t-cell-{os.getpid()}.tmp')
    temp.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')
    if path.read_bytes()!=original:
        temp.unlink()
        raise RuntimeError(f'Concurrent manifest change; safely retry T-cell installer: {path.name}')
    temp.replace(path)

def audit_sources():
    generated=json.loads((ART/'generation-actions.json').read_text())
    portrait=json.loads((ART/'generation-v1.json').read_text())
    assert digest(ART/portrait['image'])==portrait['sha256'],'Portrait source changed'
    records=[]
    for key,name in ACTIONS.items():
        folder=ART/name; doc=json.loads((folder/'animation.json').read_text())
        source=folder/doc['sourceImage']
        assert digest(source)==doc['sourceSHA256']==generated['sources'][source.name]['sha256']
        external=Path(generated['sources'][source.name]['originalPath'])
        external_status='matches' if external.exists() and digest(external)==digest(source) else 'not available locally'
        if external.exists(): assert digest(external)==digest(source),'GPT source archive changed'
        atlas=Image.open(folder/'spritesheet.png').convert('RGBA')
        hashes=[]; widths=[]; heights=[]
        for frame in doc['frames']:
            path=folder/frame['name']; image=Image.open(path).convert('RGBA'); r=frame['rect']
            assert image.tobytes()==atlas.crop((r['x'],r['y'],r['x']+r['w'],r['y']+r['h'])).tobytes()
            assert image.getchannel('A').getextrema()[0]==0 and image.size==(doc['width'],doc['height'])
            assert frame['anchor']=={'x':doc['anchorX']/doc['width'],'y':doc['anchorY']/doc['height']}
            hashes.append(digest(path)); widths.append(image.width); heights.append(image.height)
        assert len(set(hashes))==len(doc['frames'])==doc['frameCount']
        assert sum(f['duration'] for f in doc['frames'])==doc['durationMs']
        records.append({'clip':key,'folder':name,'frames':doc['frameCount'],'uniqueFrames':len(set(hashes)),
                        'sourceSHA256':digest(source),'originalGPTSource':external_status,
                        'atlasSHA256':digest(folder/'spritesheet.png'),'atlasMatchesAllFrames':True,'sourcePivotsAndTimingPreserved':True})
    original=ART/'original-skill1-6'; doc=json.loads((original/'animation.json').read_text()); archive=ROOT/doc['sourceArchive']
    assert digest(archive)==doc['sourceArchiveSHA256']
    with ZipFile(archive) as z:
        base='T细胞json+动画/'
        for i in range(1,7): assert (original/f'frame-{i:03}.png').read_bytes()==z.read(base+f'frames/skill1/{i}.png')
        assert (original/'spritesheet.png').read_bytes()==z.read(base+'T细胞技能1.png')
        assert (original/'preview.webp').read_bytes()==z.read(base+'T细胞技能1.webp')
    return {'actions':records,'frames':sum(r['frames'] for r in records),'portraitSHA256':digest(ART/portrait['image']),
            'originalSixFrameArchiveByteMatch':True,'originalArchiveSHA256':digest(archive)}

def main():
    audit=audit_sources()
    # Preparation is an explicit separate step; installing must not reset later
    # approved tuning by silently regenerating an earlier registration draft.
    runtime_source=ART/'runtime.json'
    if not runtime_source.exists(): raise RuntimeError('Run prepare_t_cell_runtime.py once before installing assets')
    runtime_data=json.loads(runtime_source.read_text())
    deliveries=[(ART/name/'spritesheet.png',GAME/'assets/image/t-cell-cartoon-20261021'/name/'spritesheet.png') for name in ACTIONS.values()]
    deliveries += [(ART/'character-refined-v1.png',GAME/'assets/image/t-cell-cartoon-20261021/character-refined-v1.png'),(runtime_source,GAME/'data/t_cell.json')]
    rows=[]
    for source,target in deliveries:
        target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(source,target)
        rows.append({'source':source.relative_to(ROOT).as_posix(),'path':target.relative_to(GAME).as_posix(),'bytes':target.stat().st_size,'sha256':digest(target)})
    for row in rows:
        source=ROOT/row['source']; runtime=GAME/row['path']
        assert source.read_bytes()==runtime.read_bytes() and digest(runtime)==row['sha256']
    manifest_path=GAME/'data/asset_manifest.json'; original=manifest_path.read_bytes()
    manifest={row['path']:row for row in json.loads(original)}
    added=[row['path'] for row in rows if row['path'] not in manifest]
    for row in rows: manifest[row['path']]=row
    replace_if_unchanged(manifest_path,original,list(manifest.values()))
    # Re-read the latest manifest before totals, preserving intervening additions.
    latest=json.loads(manifest_path.read_text())
    source_path=GAME/'data/source_manifest.json'; original=source_path.read_bytes(); source=json.loads(original)
    source['assets']=len(latest);source['assetBytes']=sum(row['bytes'] for row in latest)
    replace_if_unchanged(source_path,original,source)
    registered='t_cell' in json.loads((GAME/'data/config.json').read_text())['Data']['units']
    audit.update({'date':'2026-10-21','status':'passed','runtimeAssetsInstalled':rows,'newManifestPaths':added,
                  'manifestFiles':len(latest),'manifestBytes':source['assetBytes'],'unitRegistered':registered,'runtimeIntegrated':bool(runtime_data.get('runtimeIntegrated',False)),
                  'runtimeHooksWritten':False,'manifestRegistrationOnly':True})
    write(ART/'runtime-install-audit.json',audit)
    write(GAME/'planning/gameplay-completion-20261021/t-cell-assets-installed.json',audit)
    print(json.dumps({'framesVerified':audit['frames'],'assetsInstalled':len(rows),'newManifestPaths':added,
                      'originalSixFrameArchiveByteMatch':True,'unitRegistered':registered,'runtimeHooksWritten':False},ensure_ascii=False))

if __name__=='__main__': main()
