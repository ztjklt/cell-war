#!/usr/bin/env python3
"""Package painted adenovirus poses into aligned transparent 16-frame clips.

Offline art tooling only. No mirrored, interpolated, or synthetic body poses.
The phase offsets register the authored jumps and recoil to a common ground.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

from package_pneumococcus import extract_islands

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT/'assets/image/adenovirus-cartoon-v2-20261021'
SIZE, AX, GROUND = 512, 256, 440
SPECS = {
    'move': ('跳跃移动', 12, True),
    'slam': ('蓄力重砸', 12, False),
    'hit-right': ('右侧来袭受击', 16, False),
    'hit-left': ('左侧来袭受击', 16, False),
    'death': ('死亡消散', 10, False),
}
HOP = [0, 0, 0, -8, -30, -50, -62, -65, -58, -40, -15, 0, 4, -7, -3, 0]
SLAM = [0, 0, 0, 0, -25, -75, -110, -70, -20, 0, 3, -5, -12, -6, -2, 0]
RECOIL = [0, 2, 8, 20, 32, 42, 36, 18, -14, -18, -8, 8, -4, 3, 1, 0]
SLAM_TIMES = [80, 100, 130, 180, 60, 65, 80, 70, 55, 100, 70, 80, 90, 85, 80, 75]


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n')


def alpha_bounds(image, threshold=64):
    return image.getchannel('A').point(lambda a: 255 if a >= threshold else 0).getbbox()


def prepare(action, layout):
    source = OUT/layout.get('source',f'source-{action}-16.png')
    image = Image.open(source).convert('RGBA')
    assert image.getchannel('A').getextrema() == (0, 255), source
    ys = layout['rowEdges']
    assert ys[0] == 0 and ys[-1] == image.height and ys == sorted(set(ys))
    rgba = np.array(image)
    if layout.get('cleanMatteGreen'):
        # Reject the saturated green matte hue; retain the mint/teal artwork.
        # This changes extraction alpha only, never paints over the source art.
        rgb=rgba[:,:,:3].astype(float)
        red,green,blue=rgb[:,:,0],rgb[:,:,1],rgb[:,:,2]
        matte=(green>100)&(red<green*.55)&(blue<green*.75)
        rgba[matte,3]=0
        fringe=ndimage.distance_transform_edt(rgba[:,:,3]>=192)<=2.5
        cyan=(red<80)&(green>145)&(blue>140)
        rgba[fringe&cyan,3]=0
        image=Image.fromarray(rgba)
    if action == 'death':
        first = extract_islands(rgba, ys, 'projectile', rows=1)[0]
        px = first['sourceBox'][0] + (first['core'][0]+first['core'][2])/2
        baselines = layout['groundRows']
        cells, pivots = [], []
        for i in range(16):
            row, col = divmod(i, 4)
            x0, x1 = round(col*image.width/4), round((col+1)*image.width/4)
            y0, y1 = ys[row:row+2]
            paint = image.crop((x0, y0, x1, y1))
            if i == 15:
                # Only negligible antialias dust may be cleared from an empty slot.
                assert np.count_nonzero(np.array(paint)[:,:,3] >= 32) <= 8, 'Death ending still contains artwork'
                paint = Image.new('RGBA', paint.size)
            cells.append({'image': paint, 'sourceBox': [x0,y0,x1,y1]})
            pivots.append((px+col*image.width/4-x0, baselines[row]-y0))
        neutral_height = first['image'].height
    else:
        # Detached impact arcs remain assigned to their original source column.
        cells = extract_islands(rgba, ys, 'projectile')
        first = cells[0]
        neutral_height = first['image'].height
        tail = first['image'].height-first['core'][3]
        pivots = [((c['core'][0]+c['core'][2])/2, c['core'][3]+tail) for c in cells]
    anchors = [(AX, GROUND)]*16
    if action == 'move': anchors = [(AX, GROUND+v) for v in HOP]
    if action == 'slam': anchors = [(AX, GROUND+v) for v in SLAM]
    if action.startswith('hit-'):
        sign = 1 if action == 'hit-left' else -1
        anchors = [(AX+sign*v, GROUND) for v in RECOIL]
    scale = 300/neutral_height
    for cell, (px,py), (ax,ay) in zip(cells,pivots,anchors):
        box = alpha_bounds(cell['image'])
        if box is None: continue
        for extent, room in [(px-box[0],ax-22),(box[2]-px,490-ax),
                             (py-box[1],ay-22),(box[3]-py,490-ay)]:
            if extent > 0: scale = min(scale, room/extent)
    return {'source':source,'prompt':layout.get('prompt',f'prompt-{action}-16.txt'),
            'cleanMatteGreen':bool(layout.get('cleanMatteGreen')),
            'cells':cells,'pivots':pivots,'anchors':anchors,
            'neutralHeight':neutral_height,'maxNeutralHeight':scale*neutral_height}


def render(action, plan, neutral_height):
    label, fps, loop = SPECS[action]
    scale = neutral_height/plan['neutralHeight']
    frames, entries = [], []
    for i,(cell,(px,py),(ax,ay)) in enumerate(zip(plan['cells'],plan['pivots'],plan['anchors'])):
        art = cell['image']
        painted = art.resize((round(art.width*scale),round(art.height*scale)),Image.Resampling.LANCZOS)
        offset = (round(ax-px*scale),round(ay-py*scale))
        frame = Image.new('RGBA',(SIZE,SIZE)); frame.paste(painted,offset)
        box = alpha_bounds(frame)
        assert box is None or (min(box[:2])>=12 and max(box[2:])<=500),(action,i+1,box)
        duration = SLAM_TIMES[i] if action=='slam' else round((i+1)*1000/fps)-round(i*1000/fps)
        entries.append({'name':f'frame-{i+1:03}.png','duration':duration,
                        'rect':{'x':i%4*SIZE,'y':i//4*SIZE,'w':SIZE,'h':SIZE},
                        'anchor':{'x':AX/SIZE,'y':GROUND/SIZE},'sourceFrame':i+1,
                        'sourceBox':cell['sourceBox'],'registrationOffset':list(offset),
                        'registrationScale':scale,'visibleBounds':list(box) if box else None})
        frames.append(frame)
    hashes = [hashlib.sha256(f.tobytes()).hexdigest() for f in frames]
    assert len(set(hashes))==16,(action,'Duplicate output frames')
    if action=='death': assert frames[-1].getchannel('A').getbbox() is None
    config = {'name':'腺病毒 · '+label,'animation':action,'fps':fps,'loop':loop,
              'frameCount':16,'width':SIZE,'height':SIZE,'columns':4,'rows':4,
              'durationMs':sum(e['duration'] for e in entries),'spritesheet':'spritesheet.png',
              'preview':'preview.webp','source':'../'+plan['source'].name,
              'prompt':'../'+plan['prompt'],
              'sourceSHA256':hashlib.sha256(plan['source'].read_bytes()).hexdigest(),
              'generatedBy':'OpenAI built-in image_gen: sixteen painted temporal source poses',
              'processing':'Connected-island/source-slot extraction, constant clip scale, common neutral size and ground anchor with authored jump/recoil phase registration. No mirrored, interpolated or duplicate substitute poses.',
              'baseGaze':'forward','bodyFacing':'front','mirrored':False,
              'runtimeIntegrated':False,'frames':entries}
    if plan['cleanMatteGreen']:
        config['matteCleanup']='Alpha extraction excludes saturated green matte pixels (G>100, R<0.55G, B<0.75G), plus bright cyan matte within 2.5px of transparent contours. Original source preserved; no artwork redraw.'
    if action=='slam': config.update({'chargeFrames':[2,3,4],'apexFrame':7,'impactFrame':10,'shockwaveFrames':[10,11,12,13]})
    if action.startswith('hit-'):
        side=action.split('-')[1]
        config.update({'impactSide':side,'recoilDirection':'right' if side=='left' else 'left'})
    return frames,config


def save(action, frames, config):
    target=OUT/(action+'-16'); target.mkdir()
    atlas=Image.new('RGBA',(SIZE*4,SIZE*4))
    for frame,entry in zip(frames,config['frames']):
        frame.save(target/entry['name'])
        atlas.paste(frame,(entry['rect']['x'],entry['rect']['y']))
    atlas.save(target/'spritesheet.png')
    frames[0].save(target/'preview.webp',save_all=True,append_images=frames[1:],
                   duration=[e['duration'] for e in config['frames']],loop=0,lossless=True,method=4)
    write_json(target/'animation.json',config)
    for frame,entry in zip(frames,config['frames']):
        r=entry['rect']
        assert atlas.crop((r['x'],r['y'],r['x']+SIZE,r['y']+SIZE)).tobytes()==frame.tobytes()
    assert Image.open(target/'preview.webp').n_frames==16
    return {'action':action,'frames':16,'uniqueFrames':16,'webpFrames':16,
            'atlasMatchesFrames':True,'fps':config['fps'],'durationMs':config['durationMs'],
            'loop':config['loop'],'visibleBounds':[e['visibleBounds'] for e in config['frames']],
            'opaquePixelCounts':[int(np.count_nonzero(np.array(f)[:,:,3]>=64)) for f in frames],
            'source':config['source'][3:],'sourceSHA256':config['sourceSHA256'],
            'prompt':config['prompt'][3:],'animation':action+'-16/animation.json'}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--layout',type=Path,required=True)
    args=parser.parse_args()
    layout=json.loads(args.layout.read_text())
    for action in SPECS:
        assert not (OUT/(action+'-16')).exists(),'Refusing to overwrite existing clips'
    plans={a:prepare(a,layout[a]) for a in SPECS}
    height=min(p['maxNeutralHeight'] for p in plans.values())
    # Validate all art before creating any clip output directories.
    rendered={a:render(a,p,height) for a,p in plans.items()}
    reports=[save(a,*rendered[a]) for a in SPECS]
    manifest={'character':'adenovirus','displayName':'腺病毒','baseCharacter':'character-v4.png',
              'baseGaze':'forward','runtimeIntegrated':False}
    manifest.update({SPECS[a][0]+' · 16帧':a+'-16/animation.json' for a in SPECS})
    write_json(OUT/'animations.json',manifest)
    write_json(OUT/'animation-validation.json',{'totalFrames':80,'neutralHeight':height,'actions':reports})
    write_json(OUT/'generation-animations.json',{'generator':'built-in image_gen',
               'characterReference':'character-v4.png','status':'complete-awaiting-user-review',
               'baseGaze':'forward','runtimeIntegrated':False,'totalFrames':80,
               'layout':args.layout.name,'actions':[{k:v for k,v in r.items() if k not in ('visibleBounds','opaquePixelCounts')} for r in reports]})
    print(json.dumps({'totalFrames':80,'neutralHeight':height,
                     'actions':[{k:v for k,v in r.items() if k not in ('visibleBounds','opaquePixelCounts')} for r in reports]},ensure_ascii=False))


if __name__=='__main__':main()
