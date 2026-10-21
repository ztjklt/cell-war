#!/usr/bin/env python3
"""Package the three GPT-painted B-cell actions; no attack action is generated."""
from pathlib import Path
import hashlib
import json
import shutil
import numpy as np
from PIL import Image, ImageFilter
from package_macrophage import grid_borders, main_component

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/image/b-cell-cartoon-20261021'
SOURCE=Path('/Users/jitian/.codex/generated_images/01a15817-fc76-7bb2-aebe-1877b122d39b')
SPECS={
 'move':('exec-ef62f5d9-d8cb-40db-9206-929fa644db00.png',90,True,'移动 · 16帧'),
 'buff':('exec-8b19f51c-6e45-4453-be4f-e501084e56eb.png',100,True,'摇花增益 · 16帧'),
 'death':('exec-5536e572-88f6-4fcc-8b07-b2b64a924f27.png',90,False,'死亡 · 16帧'),
 'death-v2':('exec-cb037af6-92cb-47bc-8ca8-0d17defeba38.png',120,False,'侧倒死亡 · 12帧'),
}

def core_bounds(cell,bounds):
    # Erosion removes narrow receptor stems so moving flowers do not move the
    # registration pivot. Original pixels are never eroded in the output.
    eroded=np.asarray(cell.getchannel('A').filter(ImageFilter.MinFilter(17)))
    try: body,_=main_component(eroded)
    except ValueError: body=bounds
    return body

def padded_grid_borders(projection,count):
    # Split in the middle of a clear gutter so antialias pixels at receptor
    # tips are retained even when the painted pose crosses its nominal cell.
    empty=np.flatnonzero(projection==0)
    runs=np.split(empty,np.where(np.diff(empty)>1)[0]+1)
    edges=[0]
    for index in range(1,count):
        expected=len(projection)*index/count
        gaps=[r for r in runs if len(r)>=8 and abs((r[0]+r[-1])/2-expected)<len(projection)/count*.3]
        if not gaps: raise ValueError(f'No transparent source gutter near {expected}')
        gap=min(gaps,key=lambda r:abs((r[0]+r[-1])/2-expected))
        edges.append(round((int(gap[0])+int(gap[-1]))/2))
    return edges+[len(projection)]

def package(action):
    source,ms,loop,label=SPECS[action]
    columns,rows=(4,3) if action=='death-v2' else (4,4)
    count=columns*rows
    image=Image.open(SOURCE/source).convert('RGBA'); rgba=np.asarray(image)
    borders=padded_grid_borders if action=='death-v2' else grid_borders
    alpha=rgba[:,:,3]; ys=borders((alpha>=64).sum(axis=1),rows)
    cells=[]
    for row in range(rows):
        top,bottom=ys[row:row+2]; xs=borders((alpha[top:bottom]>=64).sum(axis=0),columns)
        for col in range(columns):
            left,right=xs[col:col+2]; pixels=rgba[top:bottom,left:right].copy()
            bounds,keep=main_component(pixels[:,:,3]); pixels[:,:,3]=np.where(keep,pixels[:,:,3],0)
            if action=='death-v2' and (min(bounds[:2])<4 or bounds[2]>right-left-4 or bounds[3]>bottom-top-4):
                raise ValueError(f'Incomplete source pose at {row},{col}: {bounds}')
            pixels[pixels[:,:,3]==0,:3]=0
            cell=Image.fromarray(pixels)
            cells.append((cell,bounds,core_bounds(cell,bounds),[left,top,right,bottom]))
    first=cells[0][2]
    scale=min(280/(first[2]-first[0]),460/max(b[2]-b[0] for _,b,_,_ in cells),380/max(b[3]-b[1] for _,b,_,_ in cells))
    anchor_y=round(440-(cells[0][1][3]-(first[1]+first[3])/2)*scale)
    diameter=(first[2]-first[0])*scale
    target=OUT/f'{action}-{count}'; target.mkdir(exist_ok=True)
    shutil.copy2(SOURCE/source,target/'source-painted-sheet.png')
    frames=[]; records=[]
    for i,(cell,bounds,core,source_box) in enumerate(cells):
        offset=(round(256-(core[0]+core[2])/2*scale),round(440-bounds[3]*scale))
        frame=Image.new('RGBA',(512,512))
        frame.paste(cell.resize((round(cell.width*scale),round(cell.height*scale)),Image.Resampling.LANCZOS),offset)
        visible=frame.getchannel('A').point(lambda a:255 if a>=96 else 0).getbbox()
        if visible is None or min(visible[:2])<=2 or max(visible[2:])>=510: raise ValueError(f'{action}: clipped pose {i+1}, {visible}')
        name=f'frame-{i+1:03}.png'; frame.save(target/name); frames.append(frame)
        records.append({'name':name,'duration':ms,'rect':{'x':i%columns*512,'y':i//columns*512,'w':512,'h':512},'anchor':{'x':.5,'y':anchor_y/512},'sourceGridCell':source_box,'sourceBodyBounds':list(bounds),'bodyCoreBounds':list(core),'registrationOffset':list(offset),'visibleBounds':list(visible)})
    atlas=Image.new('RGBA',(columns*512,rows*512))
    for i,frame in enumerate(frames): atlas.paste(frame,(i%columns*512,i//columns*512))
    atlas.save(target/'spritesheet.png')
    frames[0].save(target/'preview.webp',save_all=True,append_images=frames[1:],duration=ms,loop=0 if loop else 1,lossless=True,method=3)
    doc={'name':'B细胞 · '+label,'animation':action,'width':512,'height':512,'columns':columns,'rows':rows,'frameCount':count,'durationMs':ms*count,'loop':loop,'spritesheet':'spritesheet.png','preview':'preview.webp','generatedBy':'Built-in GPT image generation','processing':'Painted grid extraction, connected-alpha cleanup, one fixed scale per action and body-core registration; no pose interpolation.','fixedScale':scale,'anchorX':256,'anchorY':anchor_y,'bodyDiameter':diameter,'sourceSHA256':hashlib.sha256((SOURCE/source).read_bytes()).hexdigest(),'frames':records}
    (target/'animation.json').write_text(json.dumps(doc,ensure_ascii=False,indent=2)+'\n')
    return doc

def main():
    doc=package('death-v2')
    manifest={'character':'b_cell','displayName':'B细胞','portrait':'character-refined-v1.png',
              '摇花增益 · 原版6帧':'original-skill1-6/animation.json',
              '移动 · 16帧':'move-16/animation.json',
              '侧倒死亡 · 12帧':'death-v2-12/animation.json'}
    manifest['原型细化 · 单体立绘']='portrait-v1.json'
    (OUT/'animations.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    print('death-v2',doc['frameCount'],doc['durationMs'],round(doc['bodyDiameter'],2))

if __name__=='__main__': main()
