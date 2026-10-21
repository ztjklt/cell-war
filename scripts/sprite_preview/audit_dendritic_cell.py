#!/usr/bin/env python3
"""Verify painted dendritic poses, untouched scan originals and Godot deliveries."""
from pathlib import Path
from zipfile import ZipFile
import hashlib
import json
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
ART=ROOT/'assets/image/dendritic-cell-cartoon-20261021'
ACTIONS={'dcMove':('move-16',16),'dcScan':('original-skill1-6',6),'dcHit':('hit-12',12),'dcDeath':('death-12',12)}

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    runtime=json.loads((ROOT/'godot/data/dendritic_cell.json').read_text())
    manifest={row['path']:row for row in json.loads((ROOT/'godot/data/asset_manifest.json').read_text())}
    records=[]
    for key,(name,count) in ACTIONS.items():
        folder=ART/name; doc=json.loads((folder/'animation.json').read_text())
        assert len(doc['frames'])==doc['frameCount']==count
        assert sum(f['duration'] for f in doc['frames'])==doc['durationMs']
        clip=runtime['clips'][key]
        assert clip['durations']==[f['duration']/1000 for f in doc['frames']]
        atlas=Image.open(folder/doc['spritesheet']).convert('RGBA')
        hashes=[]; margins=[]
        for frame in doc['frames']:
            path=folder/frame['name']; painted=Image.open(path).convert('RGBA')
            r=frame['rect']; crop=atlas.crop((r['x'],r['y'],r['x']+r['w'],r['y']+r['h']))
            assert painted.tobytes()==crop.tobytes(),path
            assert painted.getchannel('A').getextrema()[0]==0,path
            hashes.append(sha(path))
            if key!='dcScan':
                b=frame['sourceBodyBounds']; r=frame['sourceGridCell']
                source_margin=min(b[0],b[1],r[2]-r[0]-b[2],r[3]-r[1]-b[3])
                v=frame['visibleBounds']; packed_margin=min(v[0],v[1],doc['width']-v[2],doc['height']-v[3])
                assert source_margin>=3 and packed_margin>=4,(path,source_margin,packed_margin)
                margins.append({'source':source_margin,'packed':packed_margin})
        relative='assets/'+clip['path']; installed=ROOT/'godot'/relative
        assert sha(installed)==sha(folder/'spritesheet.png')==manifest[relative]['sha256']
        if key!='dcScan':
            assert len(set(hashes))==count
            assert sha(folder/doc['sourceImage'])==doc['sourceSHA256']
        records.append({'clip':key,'folder':name,'frames':count,'uniqueFrames':len(set(hashes)),
                        'durationMs':doc['durationMs'],'loop':doc['loop'],'atlasMatchesFrames':True,
                        'runtimeMatchesAtlas':True,'transparentAlpha':True,'margins':margins})
    folder=ART/'original-skill1-6'
    doc=json.loads((folder/'animation.json').read_text())
    archive=ROOT/doc['sourceArchive']; assert sha(archive)==doc['sourceArchiveSHA256']
    with ZipFile(archive) as z:
        prefix='树突状细胞json+动画/'
        for i in range(1,7):
            assert (folder/f'frame-{i:03}.png').read_bytes()==z.read(prefix+f'frames/skill1/{i:03}.png')
        assert (folder/'spritesheet.png').read_bytes()==z.read(prefix+'树突状细胞技能1.png')
        assert (folder/'preview.webp').read_bytes()==z.read(prefix+'树突状细胞技能1.webp')
    assert (ART/'runtime.json').read_bytes()==(ROOT/'godot/data/dendritic_cell.json').read_bytes()
    report={'date':'2026-10-21','status':'passed','actions':records,'originalScanByteMatch':True,
            'originalScanNote':'Six source frames retained; first and last are identical by design (five unique PNGs).',
            'originalTimingMs':[200]*6,'runtimeDataMatches':True,'totalFrames':46}
    (ART/'animation-audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'status':'passed','frames':46,'originalScanByteMatch':True,'uniqueFrames':{r['clip']:r['uniqueFrames'] for r in records}}))

if __name__=='__main__': main()
