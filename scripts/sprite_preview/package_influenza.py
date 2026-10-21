#!/usr/bin/env python3
"""Package painted influenza poses; no generated substitute animation frames."""
from pathlib import Path
import hashlib
import json
import shutil
import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/image/influenza-cartoon-v2-20261020'
SOURCE = Path('/Users/jitian/.codex/generated_images/01a1587d-2487-7982-af7f-934c90397ed0')
SOURCES = {
    'move': 'exec-51b09cca-0f11-42b1-b11a-2a15dcbb1159.png',
    'attack': 'exec-b7fa79c3-d8c6-4ae6-8b15-2775852d264d.png',
    'hit': 'exec-4aa70a56-2ca3-467d-83a0-5549a42bfffe.png',
    'death': 'exec-052dea0e-e5ca-4873-b670-55fd98a1cf52.png',
    'build': 'exec-2756c2da-38e9-46bc-9f89-56be75d6acb8.png',
}
NAMES = {'move':'移动', 'attack':'夸张啃咬', 'hit':'受击', 'death':'灰飞烟灭', 'build':'电钻建造'}


def bounds(mask):
    yy, xx = np.nonzero(mask)
    return None if not len(xx) else (int(xx.min()), int(yy.min()), int(xx.max())+1, int(yy.max())+1)


def borders(projection, count, radius):
    result = [0]
    for i in range(1, count):
        expected = len(projection)*i/count
        choices = range(max(result[-1]+1, round(expected)-radius), min(len(projection)-1, round(expected)+radius))
        result.append(min(choices, key=lambda x: (int(projection[max(0,x-1):x+2].sum()), abs(x-expected))))
    return result + [len(projection)]


def prepare(action):
    image = Image.open(SOURCE / SOURCES[action]).convert('RGBA')
    rgba = np.array(image)
    alpha = rgba[:,:,3]
    rows = borders((alpha >= 64).sum(axis=1), 4, 60)
    cells, boxes, bodyboxes = [], [], []
    for row in range(4):
        y0,y1 = rows[row:row+2]
        cols = borders((alpha[y0:y1] >= 64).sum(axis=0), 5, 40)
        for col in range(5):
            x0,x1 = cols[col:col+2]
            cell = rgba[y0:y1,x0:x1].copy()
            labels,count = ndimage.label(cell[:,:,3] >= 64)
            sizes = np.bincount(labels.ravel())
            sizes[0] = 0
            major = labels == int(sizes.argmax()) if count else np.zeros(labels.shape, bool)
            body = bounds(major)
            if action != 'death':
                if body is None: raise ValueError(f'{action}: missing pose {len(cells)+1}')
                # Retain painted connected body, drill and antialiased outline;
                # discard disconnected low-opacity generation speckles.
                keep = ndimage.binary_dilation(major, iterations=3)
                cell[:,:,3] = np.where(keep, cell[:,:,3], 0)
            else:
                cell[:,:,3] = np.where(cell[:,:,3] >= 8, cell[:,:,3], 0)
            cells.append(Image.fromarray(cell))
            boxes.append([x0,y0,x1,y1])
            bodyboxes.append(body)
    return cells, boxes, bodyboxes


def package(action):
    target = OUT / (action+'-20')
    if target.exists(): raise ValueError(f'Refusing to overwrite {target}')
    cells, boxes, bodies = prepare(action)
    first = bodies[0]
    scale = (310 if action == 'build' else 290) / (first[2]-first[0])
    frames, metadata = [], []
    move_bob = [0,0,1,2,-4,-14,-24,-29,-20,-8,0,2,-8,-16,-10,0,1,-2,-1,0]
    attack_lunge = [0,0,2,1,-7,-6,-4,0,5,10,23,28,24,16,8,3,0,0,0,0]
    hit_recoil = [0,0,-2,-6,-14,-24,-28,-22,-14,-6,4,-6,3,-3,0,0,0,0,0,0]
    fps = 16 if action == 'hit' else 10
    target.mkdir()
    shutil.copy2(SOURCE/SOURCES[action], target/'source-painted-sheet.png')
    for index, (cell, body) in enumerate(zip(cells, bodies)):
        frame = Image.new('RGBA', (512,512))
        if action == 'death':
            # Shared cell-space pivot: disintegration is never recentered or enlarged.
            reference_x = (first[0]+first[2])/2
            reference_y = first[3]
            cx = cell.width/2 + (reference_x-cells[0].width/2)
            baseline = cell.height - (cells[0].height-reference_y)
            offset = (round(256-cx*scale),round(420-baseline*scale))
        else:
            cx = (body[0]+body[2])/2
            dx = attack_lunge[index] if action == 'attack' else hit_recoil[index] if action == 'hit' else 0
            dy = move_bob[index] if action == 'move' else 0
            offset = (round(256-cx*scale+dx),round(420-body[3]*scale+dy))
        painted = cell.resize((round(cell.width*scale),round(cell.height*scale)),Image.Resampling.LANCZOS)
        frame.paste(painted, offset)
        # The model paints a near-empty final death cell; explicitly clear subvisible dust.
        if action == 'death' and index == 19:
            if np.count_nonzero(np.array(frame)[:,:,3]>=64)>32:
                raise ValueError('Death final frame is not empty enough')
            frame = Image.new('RGBA',(512,512))
        visible = frame.getchannel('A').point(lambda x:255 if x>=64 else 0).getbbox()
        if visible and (visible[0]<=1 or visible[1]<=1 or visible[2]>=511 or visible[3]>=511):
            raise ValueError(f'{action} frame {index+1} clipped output bounds')
        duration = round((index+1)*1000/fps)-round(index*1000/fps)
        frame.save(target/f'frame-{index+1:03}.png')
        frames.append(frame)
        metadata.append({'name':f'frame-{index+1:03}.png','duration':duration,
                         'rect':{'x':(index%5)*512,'y':(index//5)*512,'w':512,'h':512},
                         'anchor':{'x':.5,'y':420/512},'sourceGridCell':boxes[index],
                         'sourceBodyBounds':body,'registrationOffset':list(offset),
                         'visibleBounds':visible})
    atlas = Image.new('RGBA',(2560,2048))
    for i,frame in enumerate(frames): atlas.paste(frame,((i%5)*512,(i//5)*512))
    atlas.save(target/'spritesheet.png')
    frames[0].save(target/'preview.webp',save_all=True,append_images=frames[1:],
                   duration=[m['duration'] for m in metadata],loop=0,lossless=True,method=4)
    config = {'name':'流感病毒 · '+NAMES[action],'animation':action,'fps':fps,
              'loop':action in ('move','build'),'frameCount':20,'width':512,'height':512,
              'durationMs':sum(m['duration'] for m in metadata),'columns':5,'rows':4,
              'spritesheet':'spritesheet.png','preview':'preview.webp','frames':metadata,
              'generatedBy':'OpenAI built-in image_gen: twenty painted source poses',
              'processing':'Adaptive transparent-gutter extraction; detached speckle cleanup; constant per-clip scale; pivot registration and translation. No interpolated substitute poses. Final death frame transparent.',
              'sourceSHA256':hashlib.sha256((SOURCE/SOURCES[action]).read_bytes()).hexdigest()}
    (target/'animation.json').write_text(json.dumps(config,ensure_ascii=False,indent=2)+'\n')
    return {'action':action,'frames':20,'distinctFrames':len({hashlib.sha256(f.tobytes()).hexdigest() for f in frames}),
            'durationMs':config['durationMs'],'finalOpaquePixels':int(np.count_nonzero(np.array(frames[-1])[:,:,3]>=64))}


if __name__ == '__main__':
    report = [package(action) for action in SOURCES]
    manifest = {'character':'influenza','baseCharacter':'character-evil-v1.png'}
    manifest.update({NAMES[action]+' · 20帧':action+'-20/animation.json' for action in SOURCES})
    (OUT/'animations.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    (OUT/'animation-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(report,ensure_ascii=False))
