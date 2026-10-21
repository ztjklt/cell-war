#!/usr/bin/env python3
"""Package approved pneumococcus art into five aligned 16-frame clips.

Uses painted source poses only. Connected-island separation preserves artwork
whose bounds overlap adjacent slots. No frame interpolation or substitute poses.
Requires Pillow, numpy and scipy (offline asset tooling only).
"""
from pathlib import Path
import hashlib
import json
import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT/'assets/image/pneumococcus-cartoon-v2-20261021'
SIZE = 512
SPECS = {
    'move': ('移动',12,True,[0,361,684,961,1254]),
    'shoot': ('鼓腮射击',12,False,[0,402,713,987,1254]),
    'projectile': ('吐核弹丸飞行',16,True,[0,333,636,930,1254]),
    'hit': ('受击',16,False,[0,369,662,966,1254]),
    'death': ('死亡消散',10,False,[0,388,691,1027,1254]),
}


def bounds(mask):
    yy,xx = np.nonzero(mask)
    return None if not len(xx) else [int(xx.min()),int(yy.min()),int(xx.max())+1,int(yy.max())+1]


def main_core(mask):
    thick = ndimage.distance_transform_edt(mask)>12
    labels,count = ndimage.label(thick)
    if not count: raise ValueError('Missing solid character core')
    sizes = np.bincount(labels.ravel());sizes[0]=0
    return bounds(labels==int(sizes.argmax()))


def extract_islands(rgba,ys,action,rows=4):
    cells=[]
    for row in range(rows):
        y0,y1=ys[row:row+2]
        strip=rgba[y0:y1].copy()
        labels,count=ndimage.label(strip[:,:,3]>=192)
        sizes=np.bincount(labels.ravel());sizes[0]=0
        bodies=sorted(range(1,count+1),key=lambda k:int(sizes[k]),reverse=True)[:4]
        if len(bodies)!=4 or min(sizes[k] for k in bodies)<2000:
            raise ValueError(f'{action}: missing body on row {row}')
        bodies.sort(key=lambda k:bounds(labels==k)[0])
        boxes=[bounds(labels==k) for k in bodies]
        distances=np.stack([ndimage.distance_transform_edt(labels!=k) for k in bodies])
        owners=np.full(count+1,-1,dtype=np.int16)
        for k in range(1,count+1):
            if sizes[k]<8: continue
            mask=labels==k
            if k in bodies:
                owner=bodies.index(k)
            elif action in ('projectile', 'hit-left'):
                # Detached droplets / hit arcs belong to their authored slot.
                owner=min(3,int(np.nonzero(mask)[1].mean()/(strip.shape[1]/4)))
            else:
                owner=int(np.argmin([distances[j][mask].min() for j in range(4)]))
                if action=='shoot':
                    pixels=strip[mask,:3].astype(float)
                    gold=(pixels[:,0]>140)&(pixels[:,1]>60)&(pixels[:,2]<140)&(pixels[:,0]>pixels[:,1]*1.08)
                    if gold.mean()>.12:
                        x=float(np.nonzero(mask)[1].mean())
                        left=[i for i,b in enumerate(boxes) if (b[0]+b[2])/2<x]
                        if left: owner=left[-1]
            owners[k]=owner
        selected=owners[labels]
        gap,nearest=ndimage.distance_transform_edt(selected<0,return_indices=True)
        owner_map=selected[nearest[0],nearest[1]]
        for col,body in enumerate(bodies):
            keep=(owner_map==col)&(gap<=3)
            paint=strip.copy();paint[:,:,3]=np.where(keep,paint[:,:,3],0)
            box=bounds(paint[:,:,3]>=8)
            if box is None:raise ValueError('Empty painted slot')
            l,t,r,b=box
            core=main_core(labels==body)
            cells.append({'image':Image.fromarray(paint[t:b,l:r]),
                          'sourceBox':[l,t+y0,r,b+y0],
                          'core':[core[0]-l,core[1]-t,core[2]-l,core[3]-t],
                          'row':row,'column':col})
    return cells


def extract_death(rgba,ys):
    intact=extract_islands(rgba,ys,'death',rows=2)
    first=intact[0];core=first['core']
    pivot_x=first['sourceBox'][0]+(core[0]+core[2])/2
    baselines=[321,639,935,1180]
    width=rgba.shape[1]
    cells=[]
    for i in range(16):
        row,col=divmod(i,4)
        if i<8:
            cell=intact[i]
            cell['pivotX']=pivot_x+col*width/4-cell['sourceBox'][0]
            cell['pivotY']=baselines[row]-cell['sourceBox'][1]
        else:
            y0,y1=ys[row:row+2];x0,x1=round(col*width/4),round((col+1)*width/4)
            part=rgba[y0:y1,x0:x1].copy()
            labels,n=ndimage.label(part[:,:,3]>=64)
            sizes=np.bincount(labels.ravel());sizes[0]=0
            keep=ndimage.binary_dilation(np.isin(labels,np.flatnonzero(sizes>=2)),iterations=2)
            part[:,:,3]=np.where(keep,part[:,:,3],0)
            if i==15:
                if np.count_nonzero(part[:,:,3]>=64)>8:raise ValueError('Final source death cell is not empty')
                part[:,:,3]=0
            cell={'image':Image.fromarray(part),'sourceBox':[x0,y0,x1,y1],
                  'row':row,'column':col,'pivotX':pivot_x+col*width/4-x0,
                  'pivotY':baselines[row]-y0}
        cells.append(cell)
    return cells


def package(action):
    label,fps,loop,ys=SPECS[action]
    source=OUT/f'source-{action}-16.png'
    im=Image.open(source).convert('RGBA')
    if im.size!=(1254,1254) or im.getchannel('A').getextrema()[0]!=0:
        raise ValueError('Source differs from inspected sheet')
    rgba=np.array(im)
    cells=extract_death(rgba,ys) if action=='death' else extract_islands(rgba,ys,action)
    target=OUT/(action+'-16')
    if target.exists():raise ValueError(f'Refusing to overwrite {target}')
    bob=[0,3,6,4,-10,-24,-30,-18,2,12,6,-9,-13,-5,1,0]
    recoil=[0,-2,-8,-18,-28,-22,-10,8,12,0,-8,-4,0,0,0,0]
    flutter=[0,-2,-3,-4,-3,-2,0,2,3,4,3,2,0,-2,-1,0]
    if action=='death':
        pivots=[(c['pivotX'],c['pivotY']) for c in cells]
        anchors=[(256,370)]*16;scale=1.16
    elif action=='projectile':
        pivots=[((c['core'][0]+c['core'][2])/2,(c['core'][1]+c['core'][3])/2) for c in cells]
        anchors=[(320,256+flutter[i]) for i in range(16)]
        scale=1.3
    else:
        first=cells[0]['core'];scale=350/(first[2]-first[0])
        pivots=[((c['core'][0]+c['core'][2])/2,c['core'][3]) for c in cells]
        anchors=[(218 if action=='shoot' else 256,370) for _ in cells]
        if action=='move':anchors=[(x,y+bob[i]) for i,(x,y) in enumerate(anchors)]
        if action=='hit':anchors=[(x+recoil[i],y) for i,(x,y) in enumerate(anchors)]
    # One scale per clip; do not normalize away the painted shape changes.
    for c,(px,py),(ax,ay) in zip(cells,pivots,anchors):
        box=c['image'].getchannel('A').point(lambda a:255 if a>=64 else 0).getbbox()
        if not box:continue
        for extent,space in [(px-box[0],ax-22),(box[2]-px,490-ax),
                             (py-box[1],ay-22),(box[3]-py,490-ay)]:
            if extent>0:scale=min(scale,space/extent)
    target.mkdir()
    frames,entries=[],[]
    for i,(cell,(px,py),(ax,ay)) in enumerate(zip(cells,pivots,anchors)):
        image=cell['image'];paint=image.resize((round(image.width*scale),round(image.height*scale)),Image.Resampling.LANCZOS)
        offset=(round(ax-px*scale),round(ay-py*scale))
        frame=Image.new('RGBA',(SIZE,SIZE));frame.paste(paint,offset)
        box=frame.getchannel('A').point(lambda a:255 if a>=64 else 0).getbbox()
        if box and (min(box[:2])<12 or max(box[2:])>500):
            raise ValueError(f'{action} frame {i+1} clipped output')
        name=f'frame-{i+1:03}.png';frame.save(target/name)
        duration=round((i+1)*1000/fps)-round(i*1000/fps)
        anchor=(320,256) if action=='projectile' else (218,370) if action=='shoot' else (256,370)
        entries.append({'name':name,'duration':duration,
                        'rect':{'x':i%4*SIZE,'y':i//4*SIZE,'w':SIZE,'h':SIZE},
                        'anchor':{'x':anchor[0]/SIZE,'y':anchor[1]/SIZE},
                        'sourceFrame':i+1,'sourceBox':cell['sourceBox'],
                        'registrationOffset':list(offset),'registrationScale':scale,'visibleBounds':box})
        frames.append(frame)
    hashes=[hashlib.sha256(f.tobytes()).hexdigest() for f in frames]
    assert len(set(hashes))==16,(action,'Duplicate painted frames')
    if action=='death':assert frames[-1].getchannel('A').getbbox() is None
    atlas=Image.new('RGBA',(SIZE*4,SIZE*4))
    for i,frame in enumerate(frames):atlas.paste(frame,(i%4*SIZE,i//4*SIZE))
    atlas.save(target/'spritesheet.png')
    frames[0].save(target/'preview.webp',save_all=True,append_images=frames[1:],
                   duration=[e['duration'] for e in entries],loop=0,lossless=True,method=4)
    config={'name':'肺炎链球菌 · '+label,'animation':action,'fps':fps,'loop':loop,
            'frameCount':16,'width':SIZE,'height':SIZE,'columns':4,'rows':4,
            'durationMs':sum(e['duration'] for e in entries),'spritesheet':'spritesheet.png',
            'preview':'preview.webp','source':'../'+source.name,
            'sourceSHA256':hashlib.sha256(source.read_bytes()).hexdigest(),
            'generatedBy':'OpenAI built-in image_gen: sixteen painted temporal source slots',
            'processing':'Connected-island extraction, transparent fringe cleanup, constant clip scale and phase-aware pivot registration. No interpolated or duplicate substitute poses. Death uses a fixed original slot origin.',
            'frames':entries,'runtimeIntegrated':False}
    if action=='shoot':config['releaseFrame']=9
    if action=='projectile':config.update({'role':'independent_projectile','facing':'right','baseAppearance':'../projectile-v1.png'})
    (target/'animation.json').write_text(json.dumps(config,ensure_ascii=False,indent=2)+'\n')
    return {'action':action,'frameCount':16,'distinctFrames':len(set(hashes)),
            'fps':fps,'loop':loop,'durationMs':config['durationMs'],'registrationScale':scale,
            'opaquePixelCounts':[int(np.count_nonzero(np.array(f)[:,:,3]>=64)) for f in frames],
            'visibleBounds':[e['visibleBounds'] for e in entries]}


def main():
    reports=[package(a) for a in SPECS]
    manifest={'character':'pneumococcus','displayName':'肺炎链球菌',
              'baseCharacter':'character-v1.png','projectileAppearance':'projectile-v1.png',
              'runtimeIntegrated':False}
    manifest.update({SPECS[a][0]+' · 16帧':a+'-16/animation.json' for a in SPECS})
    (OUT/'animations.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    (OUT/'animation-validation.json').write_text(json.dumps(reports,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps([{k:v for k,v in r.items() if k not in ('opaquePixelCounts','visibleBounds')} for r in reports],ensure_ascii=False))


if __name__=='__main__':main()
