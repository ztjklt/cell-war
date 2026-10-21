#!/usr/bin/env python3
"""Extract GPT-painted T-cell poses and retain detached thrown knives.

Only alpha cleanup, grid extraction, fixed per-action scale and registration are
applied. No replacement poses or interpolated animation frames are drawn here.
"""
from pathlib import Path
from collections import deque
import argparse
import hashlib
import json
import numpy as np
from PIL import Image, ImageFilter
from package_b_cell import padded_grid_borders
from package_macrophage import main_component

ROOT=Path(__file__).resolve().parents[2]
ART=ROOT/'assets/image/t-cell-cartoon-20261021'
CANVAS=640
ANCHOR_X=360
GROUND=540
SPECS={
 'move':{'name':'移动 · 16帧','grid':(4,4),'durations':[90]*16,'loop':True},
 'blink':{'name':'瞬身前进 · 16帧','source':'blink-v2.png','grid':(4,4),'durations':[70,60,60,50,35,30,30,35,45,50,55,65,70,80,90,120],'loop':False},
 'throw':{'name':'投掷小刀 · 16帧','grid':(4,4),'durations':[90,90,90,80,80,70,50,50,60,70,80,90,90,90,90,90],'loop':True},
 'hit':{'name':'受击 · 12帧','grid':(4,3),'durations':[65,55,45,45,55,75,75,75,80,85,90,100],'loop':False},
 'death':{'name':'侧倒死亡 · 12帧','grid':(4,3),'durations':[120]*12,'loop':False},
}

def retained_art(alpha):
    """Retain real painted components, including the released knife."""
    height,width=alpha.shape
    occupied=alpha>=64
    seen=np.zeros_like(occupied,dtype=np.uint8)
    keep=np.zeros_like(occupied,dtype=np.uint8)
    components=[]
    for y,x in zip(*np.nonzero(occupied)):
        if seen[y,x]: continue
        seen[y,x]=1; pending=deque([(int(x),int(y))]); points=[]
        while pending:
            px,py=pending.popleft(); points.append((px,py))
            for qx,qy in ((px-1,py),(px+1,py),(px,py-1),(px,py+1)):
                if 0<=qx<width and 0<=qy<height and occupied[qy,qx] and not seen[qy,qx]:
                    seen[qy,qx]=1; pending.append((qx,qy))
        if len(points)<60: continue
        xs,ys=zip(*points); keep[list(ys),list(xs)]=255
        components.append({'pixels':len(points),'bounds':[min(xs),min(ys),max(xs)+1,max(ys)+1]})
    components.sort(key=lambda c:c['pixels'],reverse=True)
    if not components or components[0]['pixels']<2000: raise ValueError('No complete painted T-cell')
    dilated=np.asarray(Image.fromarray(keep).filter(ImageFilter.MaxFilter(7)))>0
    return dilated,components

def body_core(cell):
    eroded=np.asarray(cell.getchannel('A').filter(ImageFilter.MinFilter(31)))
    try: bounds,_=main_component(eroded)
    except ValueError: bounds,_=main_component(np.asarray(cell.getchannel('A')))
    return bounds

def package(action,art=ART,specs=SPECS):
    spec=specs[action]; columns,rows=spec['grid']; count=columns*rows
    source=art/'source-images'/spec.get('source',f'{action}-v1.png')
    raw=np.asarray(Image.open(source).convert('RGBA'))
    alpha=raw[:,:,3]
    ys=padded_grid_borders((alpha>=64).sum(axis=1),rows)
    cells=[]
    for row in range(rows):
        top,bottom=ys[row:row+2]
        xs=padded_grid_borders((alpha[top:bottom]>=64).sum(axis=0),columns)
        for col in range(columns):
            left,right=xs[col:col+2]; pixels=raw[top:bottom,left:right].copy()
            keep,components=retained_art(pixels[:,:,3])
            pixels[:,:,3]=np.where(keep,pixels[:,:,3],0)
            pixels[pixels[:,:,3]==0,:3]=0
            cell=Image.fromarray(pixels)
            bounds=cell.getchannel('A').point(lambda a:255 if a>=64 else 0).getbbox()
            if min(bounds[:2])<3 or bounds[2]>cell.width-3 or bounds[3]>cell.height-3:
                raise ValueError(f'{action} source pose {len(cells)+1} touches extraction edge: {bounds}')
            core=body_core(cell)
            cells.append((cell,bounds,core,[left,top,right,bottom],components))
    first=cells[0][2]
    # Undo the erosion inset only for measuring apparent body size.
    # Every clip starts upright. Height is stable across the ready poses,
    # whereas the free hand and knife can change their apparent width.
    body_diameter=first[3]-first[1]+30
    scale=280/body_diameter
    max_left=max((c[2][0]+c[2][2])/2-c[1][0] for c in cells)
    max_right=max(c[1][2]-(c[2][0]+c[2][2])/2 for c in cells)
    scale=min(scale,(ANCHOR_X-24)/max_left,(CANVAS-ANCHOR_X-24)/max_right,450/max(c[1][3]-c[1][1] for c in cells))
    anchor_y=round(GROUND-(cells[0][1][3]-(first[1]+first[3])/2)*scale)
    folder=art/f'{action}-{count}'; folder.mkdir(exist_ok=True)
    frames=[]; records=[]
    for index,(cell,bounds,core,box,components) in enumerate(cells):
        offset=(round(ANCHOR_X-(core[0]+core[2])/2*scale),round(GROUND-bounds[3]*scale))
        frame=Image.new('RGBA',(CANVAS,CANVAS))
        frame.paste(cell.resize((round(cell.width*scale),round(cell.height*scale)),Image.Resampling.LANCZOS),offset)
        visible=frame.getchannel('A').point(lambda a:255 if a>=64 else 0).getbbox()
        if not visible or min(visible[:2])<4 or max(visible[2:])>CANVAS-4:
            raise ValueError(f'{action} clipped packed frame {index+1}: {visible}')
        name=f'frame-{index+1:03}.png'; frame.save(folder/name); frames.append(frame)
        records.append({'name':name,'duration':spec['durations'][index],
          'rect':{'x':index%columns*CANVAS,'y':index//columns*CANVAS,'w':CANVAS,'h':CANVAS},
          'anchor':{'x':ANCHOR_X/CANVAS,'y':anchor_y/CANVAS},'sourceGridCell':box,
          'sourceBodyBounds':list(bounds),'bodyCoreBounds':list(core),
          'sourceComponents':components,'registrationOffset':list(offset),'visibleBounds':list(visible)})
    atlas=Image.new('RGBA',(CANVAS*columns,CANVAS*rows))
    for index,frame in enumerate(frames): atlas.paste(frame,(index%columns*CANVAS,index//columns*CANVAS))
    atlas.save(folder/'spritesheet.png')
    frames[0].save(folder/'preview.webp',save_all=True,append_images=frames[1:],duration=spec['durations'],loop=0 if spec['loop'] else 1,lossless=True,method=3)
    doc={'name':spec.get('displayName','T细胞')+' · '+spec['name'],'animation':action,'width':CANVAS,'height':CANVAS,
      'columns':columns,'rows':rows,'frameCount':count,'durationMs':sum(spec['durations']),
      'loop':spec['loop'],'spritesheet':'spritesheet.png','preview':'preview.webp',
      'sourceImage':'../source-images/'+source.name,'sourceSHA256':hashlib.sha256(source.read_bytes()).hexdigest(),
      'generatedBy':'Built-in GPT image generation','fixedScale':scale,
      'anchorX':ANCHOR_X,'anchorY':anchor_y,'bodyDiameter':body_diameter*scale,
      'processing':spec.get('processing','Painted-pose extraction and alpha-speckle cleanup; retains released knife components; fixed scale per action and ground/body registration; no interpolation.'),
      'frames':records}
    if action=='blink':
        doc['motionPreview']={'kind':'blink','bodyDiameter':doc['bodyDiameter'],
          'launchFrame':5,'arriveFrame':10,'distanceInBodies':5.5,
          'trailMs':330,'ghosts':8,'hideFrames':[7,8]}
    (folder/'animation.json').write_text(json.dumps(doc,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'action':action,'frames':count,'durationMs':doc['durationMs'],'bodyDiameter':round(doc['bodyDiameter'],2),'components':[len(r['sourceComponents']) for r in records]}))
    return doc

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--action',choices=list(SPECS));args=parser.parse_args()
    for action in [args.action] if args.action else SPECS: package(action)
    if args.action and args.action!='blink': return
    manifest={'character':'t_cell','displayName':'T细胞','portrait':'character-refined-v1.png'}
    for action in ['blink','throw','hit','death']:
        spec=SPECS[action];manifest[spec['name']]=f'{action}-{len(spec["durations"])}/animation.json'
    (ART/'animations.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')

if __name__=='__main__': main()
