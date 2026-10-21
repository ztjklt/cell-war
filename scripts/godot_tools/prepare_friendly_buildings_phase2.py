#!/usr/bin/env python3
"""Read-only PNG audit; write phase2 metadata, review HTML and installation plan.

Never writes an image, alters alpha, resizes an asset, or writes game runtime data.
The 96px review uses CSS scaling of the original PNG in a local browser.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage
from shapely.geometry import box, Point
from shapely.ops import unary_union

ROOT=Path(__file__).resolve().parents[2]
ART=ROOT/'assets/image/friendly-buildings-20261021/phase2'
KINDS={'lab','clinic','house'}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def bounds(alpha,threshold):
    yy,xx=np.nonzero(alpha>=threshold)
    if not len(xx):return None
    return [int(xx.min()),int(yy.min()),int(xx.max())+1,int(yy.max())+1]


def write(path,value):
    path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')


def review_html(buildings):
    cards=[]
    for kind,spec in buildings.items():
        name=spec['name'];file=Path(spec['texture']).name
        x,y=[v*100 for v in spec['anchor']]
        cards.append(f'''<article><h2>{name} <small>{kind}</small></h2>
<div class="large checker"><img src="{file}" alt="{kind}原始PNG"><span class="anchor" style="left:{x}%;top:{y}%" title="基座锚点"></span></div>
<div class="reviews"><div><div class="tiny dark"><img src="{file}" alt="{kind}-96-dark"></div><span>96px · 深色底</span></div><div><div class="tiny light"><img src="{file}" alt="{kind}-96-light"></div><span>96px · 浅色底</span></div></div></article>''')
    return '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>友军建筑第二批 · 原始PNG与96px检查</title><style>
*{box-sizing:border-box}body{margin:0;padding:24px;background:#10151d;color:#eef4f3;font-family:system-ui,sans-serif}h1{font-size:22px;margin:0 0 8px}p{color:#aebfc2;font-size:13px}main{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:18px}article{min-width:0;background:#1a2430;border:1px solid #384c5c;border-radius:16px;overflow:hidden}h2{font-size:18px;margin:16px}small{color:#8fc7c1;font-size:12px}.large{position:relative;width:100%;aspect-ratio:1;display:grid;place-items:center}.large img{width:100%;height:100%;object-fit:contain}.checker{background-color:#e8eeef;background-image:linear-gradient(45deg,#d5dfe3 25%,transparent 25%),linear-gradient(-45deg,#d5dfe3 25%,transparent 25%),linear-gradient(45deg,transparent 75%,#d5dfe3 75%),linear-gradient(-45deg,transparent 75%,#d5dfe3 75%);background-size:24px 24px;background-position:0 0,0 12px,12px -12px,-12px 0}.anchor{position:absolute;width:10px;height:10px;border-radius:50%;border:2px solid #0e2846;background:#ffe27b;transform:translate(-50%,-50%);box-shadow:0 0 0 1px white}.reviews{display:flex;justify-content:center;gap:20px;padding:18px 10px}.reviews>div{display:grid;justify-items:center;gap:8px}.tiny,.tiny img{width:96px;height:96px;object-fit:contain}.dark{background:#10141b}.light{background:#fff9ee}.reviews span{font-size:12px;color:#b6cad0}@media(max-width:800px){main{grid-template-columns:1fr}article{max-width:540px}body{padding:16px}}
</style><h1>友军建筑第二批 · 原始PNG检查</h1><p>原始alpha原样保留 · 黄色点为元数据基座锚点 · 下方原图直接以96 CSS像素显示 · 未接入战场</p><main>'''+''.join(cards)+'</main></html>'


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check-only',action='store_true')
    args=parser.parse_args()
    generation=json.loads((ART/'generation.json').read_text())
    snapshot=json.loads((ART/'existing-kind-snapshot.json').read_text())
    current=json.loads((ROOT/'godot/data/config.json').read_text())['Data']['buildings']
    assert {r['kind'] for r in generation['images']}==KINDS
    buildings={};checks=[];copies=[]
    for record in generation['images']:
        kind=record['kind'];path=ART/record['image']
        assert path.resolve().parent==ART.resolve()
        before=sha(path);assert before==record['sha256']==record['generatedSHA256']
        original=Path(record['generatedSource'])
        if original.exists():assert sha(original)==before
        assert all(current[kind][k]==snapshot[kind][k] for k in ['size','hp'])
        im=Image.open(path);assert im.mode=='RGBA'
        alpha=np.array(im.getchannel('A'));assert im.getchannel('A').getextrema()==(0,255)
        visible=bounds(alpha,64);assert visible and min(visible[:2])>=3 and visible[2]<im.width-3 and visible[3]<im.height-3
        border=np.r_[alpha[0],alpha[-1],alpha[:,0],alpha[:,-1]]
        assert border.max()<8,'Visible art touches border; regenerate instead of editing PNG'
        point=record['groundAnchorPx'];assert alpha[point[1],point[0]]>=64
        mask=alpha>=80;labels,_=ndimage.label(mask);areas=np.bincount(labels.ravel());areas[0]=0
        assert areas.max()/np.count_nonzero(mask)>.995
        runs=[]
        for y,row in enumerate(mask):
            edges=np.diff(np.r_[False,row,False].astype(np.int8))
            runs.extend(box(int(l),y,int(r),y+1) for l,r in zip(np.flatnonzero(edges==1),np.flatnonzero(edges==-1)))
        geometry=unary_union(runs)
        if geometry.geom_type=='MultiPolygon':geometry=max(geometry.geoms,key=lambda g:g.area)
        geometry=geometry.simplify(3,preserve_topology=True)
        assert geometry.is_valid and geometry.covers(Point(*point))
        outline=[[round(x,3),round(y,3)] for x,y in list(geometry.exterior.coords)[:-1]]
        texture='image/friendly-buildings-20261021/phase2/'+path.name
        buildings[kind]={'kind':kind,'name':record['name'],'texture':texture,
            'pixelSize':list(im.size),'sha256':before,'rawAlphaPreserved':True,
            'alphaBoundsPx':visible,'alphaBoundsThreshold':64,
            'occupancy':round((visible[2]-visible[0])/im.width,8),
            'anchor':[round(point[0]/im.width,8),round(point[1]/im.height,8)],
            'groundAnchorPx':point,'visualOutlinePx':outline,'outlineAlphaThreshold':80,
            'collisionSource':'Data.buildings.'+kind+'.size',
            'existingCollisionSize':snapshot[kind]['size'],'existingHp':snapshot[kind]['hp'],'animated':False}
        checks.append({'kind':kind,'sha256':before,'rawAlphaBoundsPx':bounds(alpha,1),
            'visibleAlphaBoundsPx':visible,'rawBorderAlphaMax':int(border.max()),
            'rawBorderAlphaNonzeroPixels':int(np.count_nonzero(border)),
            'rawAlphaPreserved':True,'pixelsWritten':0,'anchorPx':point,
            'anchorAlpha':int(alpha[point[1],point[0]]),'anchorInsideVisualContour':True,
            'outlineValid':True,'outlineVertices':len(outline),'sizeHpUnchanged':True})
        copies.append({'source':path.relative_to(ROOT).as_posix(),'path':'assets/'+texture,
                       'bytes':path.stat().st_size,'sha256':before})
        assert sha(path)==before
    data={'schema':1,'name':'友军建筑第二批静态原画','rawAlphaPreserved':True,
        'runtimeRendererConnected':False,'imageEdits':'none; original GPT PNG bytes preserved',
        'collisionPolicy':'Keep existing Data.buildings[kind].size and hp; visual outline/canvas is not a collider.',
        'renderContract':{'textureRoot':'res://assets/','sideWorld':'Data.buildings[kind].size / occupancy',
            'drawRect':'Rect2(projected_world_center - anchor * sideWorld, Vector2.ONE * sideWorld)'},
        'buildings':buildings}
    raw=(json.dumps(data,ensure_ascii=False,indent=2)+'\n').encode()
    copies.append({'source':(ART/'friendly_buildings_phase2.json').relative_to(ROOT).as_posix(),
        'path':'data/friendly_buildings_phase2.json','bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()})
    plan={'schema':1,'mode':'plan-only','executed':False,'runtimeFilesWritten':0,
        'rawAlphaPreserved':True,'globalManifestsModified':False,'copyPlan':copies,
        'nextStep':'Coordinating task may copy these four files and explicitly dispatch lab/clinic/house; do not overwrite phase1 friendly_buildings.json.'}
    if not args.check_only:
        (ART/'friendly_buildings_phase2.json').write_bytes(raw)
        write(ART/'art-validation.json',{'images':checks,'pngPixelsModified':False,'sourceBytesMatchGenerated':True})
        write(ART/'install-plan.json',plan)
        (ART/'review.html').write_text(review_html(buildings))
    else:
        assert (ART/'friendly_buildings_phase2.json').read_bytes()==raw
    print(json.dumps({'mode':'check-only' if args.check_only else 'metadata-plan',
        'kinds':sorted(KINDS),'PNGFilesWritten':0,'runtimeFilesWritten':0,
        'rawAlphaPreserved':True,'installFilesPlanned':len(copies)},ensure_ascii=False))


if __name__=='__main__':main()
