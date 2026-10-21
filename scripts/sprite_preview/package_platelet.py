#!/usr/bin/env python3
"""Register GPT-painted platelet poses and pack their original pixels for playback.

No poses are synthesized. Defensive/impact clips retain the painted connecting arms
outside a bounded central-body mask so the two grip points cannot wander.
"""
from pathlib import Path
import hashlib
import json
import math
import shutil
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from package_macrophage import grid_borders, main_component

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/image/platelet-cartoon-v2-20261021'
SOURCE = Path('/Users/jitian/.codex/generated_images/01a15817-fc76-7bb2-aebe-1877b122d39b')
SPECS = {
    'move': ('exec-71472c77-cf15-4943-ab45-0b465e4c9429.png',4,4,90,True,'行走 · 16帧'),
    'connect': ('exec-f517c3be-35d6-4f77-bfbe-b2e4da7acdb9.png',4,3,90,False,'伸手连接 · 12帧'),
    'defend': ('exec-470ffc67-ca13-41e2-b4a3-a979e55e6c7a.png',4,3,120,True,'牵手防御 · 12帧'),
    'hit': ('exec-c7e636f7-c515-4a04-9777-4f4c68fccf3b.png',4,2,70,False,'受击硬抗 · 8帧'),
    'death': ('exec-07516378-509e-4951-9cf9-ec91c2a3eda7.png',4,3,100,False,'松手倒下 · 12帧'),
}

def body_bounds(image):
    solid = np.asarray(image)[:,:,3] >= 96
    columns = solid.sum(axis=0)
    occupied = np.flatnonzero(columns >= max(8, columns.max()*.35))
    left, right = int(occupied[0]), int(occupied[-1])+1
    ys = np.flatnonzero(solid[:,left:right].any(axis=1))
    return left, int(ys[0]), right, int(ys[-1])+1

def extract(name):
    source,cols,rows,_,_,_ = SPECS[name]
    rgba = np.asarray(Image.open(SOURCE/source).convert('RGBA'))
    alpha = rgba[:,:,3]
    ys = grid_borders((alpha>=96).sum(axis=1),rows)
    result = []
    for row in range(rows):
        top,bottom = ys[row:row+2]
        xs = grid_borders((alpha[top:bottom]>=96).sum(axis=0),cols)
        for col in range(cols):
            left,right = xs[col:col+2]
            cell = rgba[top:bottom,left:right].copy()
            _, keep = main_component(cell[:,:,3])
            cell[:,:,3] = np.where(keep,cell[:,:,3],0)
            cell[cell[:,:,3]==0,:3] = 0
            painted = Image.fromarray(cell)
            result.append((painted,body_bounds(painted),[left,top,right,bottom]))
    return result

def write_clip(name,frames,records,scale):
    _,cols,rows,ms,loop,label = SPECS[name]
    target = OUT/f'{name}-{len(frames)}'
    target.mkdir(exist_ok=True)
    shutil.copy2(SOURCE/SPECS[name][0],target/'source-painted-sheet.png')
    atlas = Image.new('RGBA',(cols*512,math.ceil(len(frames)/cols)*512))
    for i,(frame,record) in enumerate(zip(frames,records)):
        filename = f'frame-{i+1:03}.png'
        frame.save(target/filename)
        x,y = i%cols*512,i//cols*512
        atlas.paste(frame,(x,y))
        record.update(name=filename,duration=ms,rect={'x':x,'y':y,'w':512,'h':512},anchor={'x':.5,'y':300/512})
    atlas.save(target/'spritesheet.png')
    frames[0].save(target/'preview.webp',save_all=True,append_images=frames[1:],duration=ms,loop=0 if loop else 1,lossless=True,method=3)
    doc={'name':'血小板 · '+label,'animation':name,'width':512,'height':512,'columns':cols,'rows':rows,
         'frameCount':len(frames),'durationMs':ms*len(frames),'loop':loop,'spritesheet':'spritesheet.png','preview':'preview.webp',
         'generatedBy':'Built-in GPT image generation','processing':'Connected-alpha cleanup; one fixed scale per action; body-centered ground registration.',
         'sourceSHA256':hashlib.sha256((SOURCE/SPECS[name][0]).read_bytes()).hexdigest(),'frames':records,'fixedScale':scale}
    if name in ['defend','hit']:
        doc.update(fixedGripPixels=True,gripReference='../connect-12/frame-012.png',bodyMotionBounds=[110,60,402,446])
        if name == 'hit':
            doc.update(bodyMotionBounds=[76,60,436,446],fixedGripRects=[[0,270,98,350],[414,270,512,350]])
    (target/'animation.json').write_text(json.dumps(doc,ensure_ascii=False,indent=2)+'\n')
    return doc

def main():
    packed={}
    manifest={'character':'platelet','displayName':'血小板 · 梯形新版','portrait':'character-v4-original-trapezoid.png'}
    for name in ['connect','move','defend','hit','death']:
        cells=extract(name)
        scale=300/(cells[0][1][2]-cells[0][1][0])
        frames,records=[],[]
        for cell,body,source_box in cells:
            offset=(round(256-(body[0]+body[2])/2*scale),round(440-body[3]*scale))
            frame=Image.new('RGBA',(512,512))
            frame.paste(cell.resize((round(cell.width*scale),round(cell.height*scale)),Image.Resampling.LANCZOS),offset)
            frames.append(frame)
            records.append({'sourceGridCell':source_box,'sourceBodyBounds':list(body),'registrationOffset':list(offset)})
        if name in ['defend','hit']:
            reference=packed['connect'][-1]
            mask=Image.new('L',(512,512))
            ImageDraw.Draw(mask).rectangle((114,60,398,442),fill=255)
            mask=mask.filter(ImageFilter.GaussianBlur(2))
            bounded=Image.new('L',(512,512)); bounded.paste(mask.crop((110,60,402,446)),(110,60)); mask=bounded
            if name == 'hit':
                # Clear the entire old body silhouette on a compressed hit;
                # preserve only the grip bands, rather than leaving side ghosts.
                mask=Image.new('L',(512,512))
                ImageDraw.Draw(mask).rectangle((78,62,434,444),fill=255)
                mask=mask.filter(ImageFilter.GaussianBlur(2))
                draw=ImageDraw.Draw(mask)
                draw.rectangle((0,270,97,349),fill=0)
                draw.rectangle((414,270,511,349),fill=0)
            frames=[Image.composite(frame,reference,mask) for frame in frames]
            frames[0]=reference.copy(); frames[-1]=reference.copy()
        for frame in frames:
            alpha=frame.getchannel('A')
            bounds=alpha.point(lambda a:255 if a>=96 else 0).getbbox()
            if bounds is None or min(bounds[:2])<4 or bounds[2]>508 or bounds[3]>508:
                raise ValueError(f'{name}: clipped painted pose {bounds}')
        doc=write_clip(name,frames,records,scale)
        packed[name]=frames
        manifest[SPECS[name][-1]]=f'{name}-{len(frames)}/animation.json'
        print(name,len(frames),doc['durationMs'])
    if (OUT/'wall-preview-12/animation.json').exists():
        manifest['三只牵手成墙 · 预览']='wall-preview-12/animation.json'
    (OUT/'animations.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    acceptance=json.loads((OUT/'generation-v4.json').read_text())
    acceptance.update(status='Approved by user for use',approved='2026-10-21',userQuote='我觉得这个非常非常好。我们就用这个。')
    (OUT/'generation-v4.json').write_text(json.dumps(acceptance,ensure_ascii=False,indent=2)+'\n')

if __name__=='__main__': main()
