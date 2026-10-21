#!/usr/bin/env python3
"""Install three selected static friendly sprites and their independent data JSON.

Offline authoring tool. Never edits runtime scripts, config or global manifests.
The default is --dry-run; --apply copies only this owned art folder plus
godot/data/friendly_buildings.json. Collision sizes always come from existing kinds.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path

from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
GAME=ROOT/'godot'
ART=ROOT/'assets/image/friendly-buildings-20261021'
DATA=ART/'friendly_buildings.json'
KINDS={'core','barracks','store'}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inspect():
    data=json.loads(DATA.read_text())
    current=json.loads((GAME/'data/config.json').read_text())['Data']['buildings']
    if data.get('schema')!=1 or set(data.get('buildings',{}))!=KINDS:
        raise ValueError('Expected exactly core, barracks and store in schema 1')
    rows=[]
    for kind,spec in data['buildings'].items():
        if kind not in current or float(current[kind]['size'])!=float(spec['existingCollisionSize']):
            raise ValueError(f'Existing kind/size changed: {kind}; do not replace collision from art')
        if spec['collisionSource']!='Data.buildings.'+kind+'.size':
            raise ValueError('Collision must continue to come from the original kind')
        texture=Path(spec['texture'])
        if texture.is_absolute() or texture.parts[:-1]!=('image','friendly-buildings-20261021'):
            raise ValueError('Texture path must remain inside the owned relative folder')
        source=ROOT/'assets'/texture
        if source.resolve().parent!=ART.resolve() or source.suffix!='.png' or not source.is_file():
            raise ValueError('Texture must be an owned local PNG')
        image=Image.open(source)
        if image.mode!='RGBA' or list(image.size)!=spec['pixelSize'] or image.getchannel('A').getextrema()!=(0,255):
            raise ValueError(f'PNG format/alpha differs: {kind}')
        if sha(source)!=spec['sha256']: raise ValueError(f'Selected PNG hash differs: {kind}')
        box=image.getchannel('A').getbbox()
        if box is None or box[0]<2 or box[1]<2 or box[2]>image.width-2 or box[3]>image.height-2:
            raise ValueError(f'Artwork touches canvas border: {kind}')
        anchor=spec['anchor']
        if len(anchor)!=2 or not all(0<float(v)<1 for v in anchor): raise ValueError('Invalid anchor')
        point=(round(anchor[0]*image.width),round(anchor[1]*image.height))
        if image.getchannel('A').getpixel(point)<64: raise ValueError(f'Anchor is outside visible base: {kind}')
        occupancy=(spec['alphaBoundsPx'][2]-spec['alphaBoundsPx'][0])/image.width
        if abs(occupancy-float(spec['occupancy']))>.00001: raise ValueError('Occupancy differs from reviewed outline width')
        outline=spec['visualOutlinePx']
        if len(outline)<3 or not all(len(p)==2 and 0<=p[0]<=image.width and 0<=p[1]<=image.height for p in outline):
            raise ValueError('Invalid visual outline')
        rows.append({'kind':kind,'source':source.relative_to(ROOT).as_posix(),
                     'path':(Path('assets')/spec['texture']).as_posix(),
                     'bytes':source.stat().st_size,'sha256':sha(source)})
    rows.append({'source':DATA.relative_to(ROOT).as_posix(),'path':'data/friendly_buildings.json',
                 'bytes':DATA.stat().st_size,'sha256':sha(DATA)})
    return data,rows


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    mode=parser.add_mutually_exclusive_group()
    mode.add_argument('--dry-run',action='store_true')
    mode.add_argument('--apply',action='store_true')
    parser.add_argument('--report',type=Path)
    args=parser.parse_args()
    if args.report:
        report=args.report.resolve()
        allowed=(report.is_relative_to(ROOT/'.tmp') or report.is_relative_to(GAME/'planning') or (report.parent==ART and report.name.startswith('install-')))
        if not allowed or report.suffix!='.json' or report==DATA:
            parser.error('Report must be independent audit JSON in .tmp/, planning/ or the owned art folder')
    _,rows=inspect()
    written=0
    for row in rows:
        target=GAME/row['path']
        row['matchesInstalled']=target.is_file() and sha(target)==row['sha256']
        if args.apply and not row['matchesInstalled']:
            target.parent.mkdir(parents=True,exist_ok=True)
            temp=target.with_name(target.name+'.friendly-art.tmp')
            temp.write_bytes((ROOT/row['source']).read_bytes())
            if sha(temp)!=row['sha256']: raise ValueError('Temporary copy hash mismatch')
            os.replace(temp,target); written+=1
        if args.apply and sha(target)!=row['sha256']: raise ValueError('Installed copy hash mismatch')
    result={'schema':1,'mode':'apply' if args.apply else 'dry-run','validatedKinds':sorted(KINDS),
            'files':len(rows),'writtenFiles':written,'collisionSizesUnchanged':True,
            'runtimeRendererConnected':False,'globalManifestsModified':False,
            'resourceManifestEntries':[{k:v for k,v in row.items() if k in ['source','path','bytes','sha256']} for row in rows],
            'installedMatchesBefore':{row['path']:row['matchesInstalled'] for row in rows}}
    if args.report:
        args.report.parent.mkdir(parents=True,exist_ok=True)
        args.report.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k not in ['resourceManifestEntries','installedMatchesBefore']},ensure_ascii=False))


if __name__=='__main__':main()
