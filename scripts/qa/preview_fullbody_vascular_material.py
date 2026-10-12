"""Compose frozen .15 map art at native source scale, without gameplay/UI.

This supports deterministic visual review of the registered quiet base plus
surface→organs→deep layers. It is not native NanoVG evidence. Input hashes and
source-space crops are recorded alongside every preview.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import sys
import zipfile
from io import BytesIO
sys.path.insert(0, '/tmp/reference-map-tools')
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
DOC=ROOT/'docs/body-life/vascular-art-study/fullbody-015'
QUIET=ROOT/'assets/image/anatomy-reference/vascular-study/fullbody-gpt-source/quiet-body-registered-v2.png'

def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()

def compose(manifest,bounds,size,archive=None):
    b=bounds;sx=(b[2]-b[0])/size[0];sy=(b[3]-b[1])/size[1]
    base=Image.open(QUIET).convert('RGBA').transform(size,Image.Transform.AFFINE,
                 (sx,0,b[0],0,sy,b[1]),resample=Image.Resampling.BILINEAR)
    ys,xs=np.mgrid[:size[1],:size[0]]
    px,py=b[0]+(xs+.5)*sx,b[1]+(ys+.5)*sy
    for kind in ['surfaceTiles','organs','deepTiles','junctions','foregroundPatches']:
        for item in manifest['runtimeSpec'].get(kind,[]):
            box=item['sourceBox']
            if box[2]<=b[0] or box[0]>=b[2] or box[3]<=b[1] or box[1]>=b[3]: continue
            path='assets/'+item['resource']
            im=Image.open(BytesIO(archive.read(path)) if archive else ROOT/path).convert('RGBA')
            scalex,scaley=im.width/(box[2]-box[0]),im.height/(box[3]-box[1])
            layer=np.asarray(im.transform(size,Image.Transform.AFFINE,
                (sx*scalex,0,(b[0]-box[0])*scalex,0,sy*scaley,(b[1]-box[1])*scaley),
                resample=Image.Resampling.BILINEAR)).copy()
            if item.get('coreBox'):
                q=item['coreBox']; inside=(px>=q[0])&(px<q[2])&(py>=q[1])&(py<q[3])
                layer[~inside]=0
            base=Image.alpha_composite(base,Image.fromarray(layer))
    return base

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--manifest',default=str(DOC/'bake/manifest.json'))
    p.add_argument('--out',default=str(DOC/'bake/third-repair/previews'))
    p.add_argument('--baseline-zip',default=str(DOC/'bake/third-repair/native003-assets.zip'))
    p.add_argument('--labels',default='aortic-arch,lung_l,pancreas,large_intestine,small_intestine,bladder,stomach,kidney_r,kidney_l,heart,celiac-stomach,portal,mesenteric,pelvis-main,foot-right,foot-left')
    args=p.parse_args();out=Path(args.out).resolve();out.mkdir(parents=True,exist_ok=True)
    current=json.loads(Path(args.manifest).read_text())
    archive=zipfile.ZipFile(args.baseline_zip)
    baseline=json.loads(archive.read('docs/body-life/vascular-art-study/fullbody-015/bake/manifest.json'))
    phases=json.loads((DOC/'native-003/driver-report.json').read_text())['phases']
    records=[];size=(2048,1151) # native logical viewport1249×702, DPR2 scaled to2048
    labels=set(args.labels.split(','))
    for phase in phases:
        if phase.get('modal') or abs(phase.get('zoom',0)-.15)>1e-8: continue
        label=phase['label'].split('-z')[0]
        if label not in labels: continue
        cx,cy=phase['camera']['x']/2,(phase['camera']['y']-512)/2
        width,height=1249/9.6,702/9.6
        b=[cx-width/2,cy-height*.47,cx+width/2,cy+height*.53]
        before=compose(baseline,b,size,archive);after=compose(current,b,size)
        before.save(out/(label+'-before.png'));after.save(out/(label+'-after.png'))
        comparison=Image.new('RGBA',(size[0],size[1]*2),'white')
        comparison.paste(before,(0,0));comparison.paste(after,(0,size[1]))
        comparison.save(out/(label+'-compare.png'))
        records.append(dict(label=label,sourceBox=b,pixelSize=list(size),camera=phase['camera'],
                            beforePath=str((out/(label+'-before.png')).relative_to(ROOT)),
                            afterPath=str((out/(label+'-after.png')).relative_to(ROOT)),
                            scale='native .15 source registration; viewport resized to2048px, noUI'))
        print(label,flush=True)
    (out/'manifest.json').write_text(json.dumps(dict(schema='fullbody-offline-native-source-preview/v1',
        nativeDriverSha256=sha(DOC/'native-003/driver-report.json'),materialManifestSha256=sha(args.manifest),
        quietBaseSha256=sha(QUIET),nativeEvidence=False,previews=records),indent=2)+'\n')

if __name__=='__main__': main()
