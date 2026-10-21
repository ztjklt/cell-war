#!/usr/bin/env python3
"""Package six painted urease pool frames around a stable ground pivot."""
from pathlib import Path
import hashlib
import json
import shutil
from PIL import Image
from package_grid import main_bounds

ROOT = Path(__file__).resolve().parents[2]
PARENT = ROOT / 'assets/image/helicobacter-cartoon-v2-20261020'
SOURCE = Path('/Users/jitian/.codex/generated_images/01a1587d-2487-7982-af7f-934c90397ed0/exec-ad7fe86d-e74c-4ed3-8ee1-56b226ae151e.png')
DEST = PARENT / 'urease-pool-6'


def main():
    im = Image.open(SOURCE).convert('RGBA')
    if im.size != (1536,1024) or im.getchannel('A').getextrema()[0] != 0:
        raise ValueError('Unexpected source dimensions or missing transparent alpha')
    if DEST.exists():
        raise ValueError(f'Refusing to overwrite {DEST}')
    width,height,scale = 512,320,.8
    frames,entries = [],[]
    DEST.mkdir()
    shutil.copy2(SOURCE,DEST/'source-painted-sheet.png')
    for i in range(6):
        col,row = i%3,i//3
        box = [col*512,row*512,(col+1)*512,(row+1)*512]
        cell = im.crop(tuple(box))
        l,t,r,b = main_bounds(cell)
        # The broad connected pool sets the ground origin; floating bubbles
        # remain in the full source slot and never affect this registration.
        offset = (round(256-(l+r)/2*scale),round(280-b*scale))
        resized = cell.resize((round(cell.width*scale),round(cell.height*scale)),Image.Resampling.LANCZOS)
        frame = Image.new('RGBA',(width,height))
        frame.paste(resized,offset)
        visible = frame.getchannel('A').point(lambda a:255 if a>=32 else 0).getbbox()
        if not visible or min(visible[:2])<10 or visible[2]>width-10 or visible[3]>height-10:
            raise ValueError(f'Frame {i+1} is clipped or empty')
        name = f'frame-{i+1:03}.png'
        frame.save(DEST/name)
        duration = round((i+1)*1000/6)-round(i*1000/6)
        entries.append({'name':name,'duration':duration,
                        'rect':{'x':col*width,'y':row*height,'w':width,'h':height},
                        'anchor':{'x':.5,'y':280/height},'sourceFrame':i+1,
                        'sourceBox':box,'sourcePoolBounds':[l,t,r,b],
                        'registrationOffset':list(offset),'registrationScale':scale,
                        'visibleBounds':visible})
        frames.append(frame)
    hashes = [hashlib.sha256(f.tobytes()).hexdigest() for f in frames]
    assert len(set(hashes))==6, 'Every frame must be distinct'
    atlas = Image.new('RGBA',(width*3,height*2))
    for i,frame in enumerate(frames): atlas.paste(frame,(i%3*width,i//3*height))
    atlas.save(DEST/'spritesheet.png')
    frames[0].save(DEST/'preview.webp',save_all=True,append_images=frames[1:],
                   duration=[e['duration'] for e in entries],loop=0,lossless=True,method=4)
    metadata = {'name':'尿素酶区域 · 冒泡','animation':'urease_pool','fps':6,'loop':True,
                'frameCount':6,'width':width,'height':height,'columns':3,'rows':2,
                'durationMs':1000,'spritesheet':'spritesheet.png','preview':'preview.webp',
                'role':'persistent_ground_effect','independentOfCaster':True,
                'runtimeIntegrated':False,'frames':entries,
                'generatedBy':'OpenAI built-in image_gen: six painted temporal poses',
                'processing':'Grid extraction, one constant scale and ground-pivot registration; original alpha preserved, no redrawn or interpolated frames.',
                'sourceSHA256':hashlib.sha256(SOURCE.read_bytes()).hexdigest()}
    (DEST/'animation.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n')
    provenance = {'name':'尿素酶独立地面区域 · 六帧冒泡循环','generator':'built-in image_gen',
                  'source':str(SOURCE),'prompt':'prompt-urease-pool-6.txt',
                  'reference':'urease-20/frame-013.png','animation':'urease-pool-6/animation.json',
                  'status':'complete-awaiting-user-review','runtimeIntegrated':False,
                  'frameCount':6,'uniqueFrames':6,'sourceSHA256':metadata['sourceSHA256']}
    (PARENT/'generation-urease-pool-6.json').write_text(json.dumps(provenance,ensure_ascii=False,indent=2)+'\n')
    manifest_path = PARENT/'animations.json'
    manifest = json.loads(manifest_path.read_text())
    manifest['尿素酶区域 · 冒泡6帧'] = 'urease-pool-6/animation.json'
    manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'frames':6,'uniqueFrames':6,'durationMs':1000,'loop':True,'atlas':str(DEST/'spritesheet.png')},ensure_ascii=False))


if __name__ == '__main__':
    main()
