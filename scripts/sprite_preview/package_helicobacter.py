#!/usr/bin/env python3
"""Package twenty painted poses per clip; preserve source art and provenance.

Requires Pillow, numpy and scipy. Connected-island extraction preserves extended
flagella when adjacent pose bounding rectangles overlap. No poses are invented
or interpolated. Death uses fixed row-space registration, never auto-enlarging
the disappearing remnants.
"""
from pathlib import Path
import hashlib
import json
import shutil
import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/image/helicobacter-cartoon-v2-20261020'
SOURCE = Path('/Users/jitian/.codex/generated_images/01a1587d-2487-7982-af7f-934c90397ed0')
SPECS = {
    'move': ('移动', 12, True, 'exec-d894dd44-01ef-4685-b3f9-87c0ec111d58.png', [0,279,560,838,1122]),
    'attack': ('鞭毛普攻', 16, False, 'exec-73447e80-97bf-4233-8b38-51476ec7e004.png', [0,297,564,838,1122]),
    'urease': ('布置尿素酶', 12, False, 'exec-7d29a4bf-e73e-4095-9997-b90c92bc3534.png', [0,291,567,830,1122]),
    'hit': ('受击', 20, False, 'exec-1b46b4b2-db4a-4b48-92ec-7b720ec5418f.png', [0,288,568,834,1122]),
    'death': ('死亡', 10, False, 'exec-e4ad82e9-2799-41a9-994c-47b8c77aceb6.png', [0,398,693,921,1122]),
}
SIZE = 512


def bounds(mask):
    yy, xx = np.nonzero(mask)
    return None if not len(xx) else [int(xx.min()), int(yy.min()), int(xx.max())+1, int(yy.max())+1]


def core_bounds(mask):
    thick = ndimage.distance_transform_edt(mask) > 13
    labels, count = ndimage.label(thick)
    if not count:
        raise ValueError('Missing solid body core')
    sizes = np.bincount(labels.ravel())
    sizes[0] = 0
    return bounds(labels == int(sizes.argmax()))


def extract_live(rgba, ys, row_count=4, min_body=5000):
    cells = []
    for row in range(row_count):
        y0, y1 = ys[row:row+2]
        strip = rgba[y0:y1].copy()
        labels, count = ndimage.label(strip[:,:,3] >= 192)
        sizes = np.bincount(labels.ravel())
        sizes[0] = 0
        bodies = sorted(range(1, count+1), key=lambda k: int(sizes[k]), reverse=True)[:5]
        if len(bodies) != 5 or min(sizes[k] for k in bodies) < min_body:
            raise ValueError(f'Row {row}: expected five separate main characters')
        bodies.sort(key=lambda k: bounds(labels == k)[0])
        # Assign detached painted motion arcs / bubbles to the closest body.
        distances = np.stack([ndimage.distance_transform_edt(labels != k) for k in bodies])
        label_owner = np.full(count+1, -1, dtype=np.int16)
        for k in range(1, count+1):
            if sizes[k] < 12:
                continue
            mask = labels == k
            label_owner[k] = int(np.argmin([distances[j][mask].min() for j in range(5)]))
        selected = label_owner[labels]
        # Restore the original antialiasing around opaque islands, without
        # copying a neighboring pose or isolated generation speckles.
        gap, nearest = ndimage.distance_transform_edt(selected < 0, return_indices=True)
        owner = selected[nearest[0], nearest[1]]
        for col, body_id in enumerate(bodies):
            keep = (owner == col) & (gap <= 3)
            paint = strip.copy()
            paint[:,:,3] = np.where(keep, paint[:,:,3], 0)
            box = bounds(paint[:,:,3] >= 8)
            if box is None:
                raise ValueError('Empty painted pose')
            l,t,r,b = box
            body = core_bounds(labels == body_id)
            cells.append({'image': Image.fromarray(paint[t:b,l:r]),
                          'sourceBox': [l,t+y0,r,b+y0],
                          'core': [body[0]-l,body[1]-t,body[2]-l,body[3]-t],
                          'row':row, 'column':col})
    return cells


def extract_death(rgba, ys):
    cells = []
    baselines = [368,665,889,1054]
    width = rgba.shape[1]
    # The collapsing silhouettes in row two slightly overlap regular cell
    # rectangles; isolate their complete islands, keeping their original origin.
    intact = extract_live(rgba, ys, row_count=2, min_body=1000)
    first_core = intact[0]['core']
    first_x = intact[0]['sourceBox'][0]+(first_core[0]+first_core[2])/2
    for index in range(20):
        row, col = divmod(index,5)
        if index < 10:
            cell = intact[index]
            cell['pivotX'] = first_x+col*width/5-cell['sourceBox'][0]
            cell['baseline'] = baselines[row]-cell['sourceBox'][1]
            cells.append(cell)
            continue
        x0,x1 = round(col*width/5),round((col+1)*width/5)
        y0,y1 = ys[row:row+2]
        part = rgba[y0:y1,x0:x1].copy()
        # Discard only disconnected subpixel speckles; retain small late bubbles.
        labels,n = ndimage.label(part[:,:,3] >= 64)
        sizes = np.bincount(labels.ravel()); sizes[0] = 0
        ids = np.flatnonzero(sizes >= 3)
        keep = ndimage.binary_dilation(np.isin(labels,ids),iterations=2)
        part[:,:,3] = np.where(keep,part[:,:,3],0)
        if index == 19:
            if np.count_nonzero(part[:,:,3] >= 64) > 8:
                raise ValueError('Last source death frame is not empty')
            part[:,:,3] = 0
        cells.append({'image':Image.fromarray(part), 'sourceBox':[x0,y0,x1,y1],
                      'row':row,'column':col,'baseline':baselines[row]-y0,
                      'pivotX':first_x+col*width/5-x0})
    return cells


def package(action):
    label,fps,loop,filename,ys = SPECS[action]
    path = SOURCE / filename
    original = Image.open(path).convert('RGBA')
    if original.size != (1402,1122) or original.getchannel('A').getextrema()[0] != 0:
        raise ValueError('Source dimensions/transparency differ from inspected sheet')
    rgba = np.array(original)
    cells = extract_death(rgba,ys) if action == 'death' else extract_live(rgba,ys)
    target = OUT / (action+'-20')
    if target.exists():
        raise ValueError(f'Refusing to overwrite {target}')
    # Same scale for every frame in a clip: squash/stretch remains painted.
    if action == 'death':
        scale = 1.12
        pivots = [(c['pivotX'],c['baseline']) for c in cells]
        anchors = [(256,450)]*20
    else:
        first = cells[0]['core']
        scale = 220/(first[3]-first[1])
        pivots = [((c['core'][0]+c['core'][2])/2,c['core'][3]) for c in cells]
        bob = [0,4,8,2,-8,-14,-8,-2,4,0,6,10,2,-10,-14,-6,0,4,2,0]
        recoil = [0,0,-4,-12,-22,-28,-20,-8,0,8,12,6,-4,-2,0,0,0,0,0,0]
        anchors = [(240 if action == 'attack' else 256,310) for _ in range(20)]
        if action == 'move': anchors = [(x,y+bob[i]) for i,(x,y) in enumerate(anchors)]
        if action == 'hit': anchors = [(x+recoil[i],y) for i,(x,y) in enumerate(anchors)]
        # Fit the most extreme source pose, preserving one constant clip scale.
        for c,(px,py),(ax,ay) in zip(cells,pivots,anchors):
            box = c['image'].getchannel('A').point(lambda v:255 if v>=64 else 0).getbbox()
            if box is None: continue
            for extent,space in [(px-box[0],ax-22),(box[2]-px,490-ax),
                                 (py-box[1],ay-22),(box[3]-py,490-ay)]:
                if extent>0: scale = min(scale,space/extent)
    frames,entries = [],[]
    target.mkdir()
    shutil.copy2(path,target/'source-painted-sheet.png')
    for index,(cell,(px,py),(ax,ay)) in enumerate(zip(cells,pivots,anchors)):
        paint = cell['image']
        resized = paint.resize((round(paint.width*scale),round(paint.height*scale)),Image.Resampling.LANCZOS)
        offset = (round(ax-px*scale),round(ay-py*scale))
        frame = Image.new('RGBA',(SIZE,SIZE))
        frame.paste(resized,offset)
        box = frame.getchannel('A').point(lambda v:255 if v>=64 else 0).getbbox()
        if box and (min(box[:2])<12 or max(box[2:])>500):
            raise ValueError(f'{action} frame {index+1} clips canvas')
        duration = round((index+1)*1000/fps)-round(index*1000/fps)
        filename = f'frame-{index+1:03}.png'
        frame.save(target/filename)
        entries.append({'name':filename,'duration':duration,
                        'rect':{'x':index%5*SIZE,'y':index//5*SIZE,'w':SIZE,'h':SIZE},
                        'anchor':{'x':.5,'y':450/SIZE},'sourceFrame':index+1,
                        'sourceBox':cell['sourceBox'],'registrationOffset':list(offset),
                        'registrationScale':scale,'visibleBounds':box})
        frames.append(frame)
    hashes = [hashlib.sha256(f.tobytes()).hexdigest() for f in frames]
    assert len(set(hashes)) == 20, (action,'Duplicated frames')
    if action == 'death': assert frames[-1].getchannel('A').getbbox() is None
    atlas = Image.new('RGBA',(SIZE*5,SIZE*4))
    for i,frame in enumerate(frames): atlas.paste(frame,(i%5*SIZE,i//5*SIZE))
    atlas.save(target/'spritesheet.png')
    frames[0].save(target/'preview.webp',save_all=True,append_images=frames[1:],
                   duration=[e['duration'] for e in entries],loop=0,lossless=True,method=4)
    metadata = {'name':'幽门螺杆菌 · '+label,'animation':action,'fps':fps,'loop':loop,
                'frameCount':20,'width':SIZE,'height':SIZE,'columns':5,'rows':4,
                'durationMs':sum(e['duration'] for e in entries),
                'spritesheet':'spritesheet.png','preview':'preview.webp','frames':entries,
                'generatedBy':'OpenAI built-in image_gen: twenty painted temporal source slots',
                'processing':'Connected-island extraction, transparent fringe cleanup, constant clip scale and pivot registration. No interpolated or duplicate substitute poses. Death uses a fixed origin and finishes transparent.',
                'sourceSHA256':hashlib.sha256(path.read_bytes()).hexdigest()}
    (target/'animation.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n')
    return {'action':action,'frames':20,'distinctFrames':len(set(hashes)),
            'fps':fps,'loop':loop,'durationMs':metadata['durationMs'],'scale':scale,
            'visibleBounds':[e['visibleBounds'] for e in entries],
            'opaquePixelCounts':[int(np.count_nonzero(np.array(f)[:,:,3]>=64)) for f in frames]}


def main():
    reports = [package(action) for action in SPECS]
    manifest = {'character':'helicobacter','displayName':'幽门螺杆菌',
                'baseCharacter':'character-v1.png','runtimeIntegrated':False}
    manifest.update({SPECS[a][0]+' · 20帧':a+'-20/animation.json' for a in SPECS})
    (OUT/'animations.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    (OUT/'animation-validation.json').write_text(json.dumps(reports,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps([{k:v for k,v in r.items() if k not in ('visibleBounds','opaquePixelCounts')} for r in reports],ensure_ascii=False))


if __name__ == '__main__':
    main()
