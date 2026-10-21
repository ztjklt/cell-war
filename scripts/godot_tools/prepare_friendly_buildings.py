#!/usr/bin/env python3
"""Reproduce selected static building PNG alpha cleanup and visual metadata.

Original GPT PNGs are immutable inputs. Only subvisible alpha (<4/255) is cleared;
artwork is neither redrawn, cropped nor resized. Thumbnails are local QA only.
"""
from pathlib import Path
import hashlib
import json

import numpy as np
from PIL import Image
from scipy import ndimage
from shapely.geometry import box
from shapely.ops import unary_union

ROOT=Path(__file__).resolve().parents[2]
ART=ROOT/'assets/image/friendly-buildings-20261021'


def write(path,data):
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')


def main():
    generation=json.loads((ART/'generation.json').read_text())
    sizes=json.loads((ART/'existing-kind-snapshot.json').read_text())
    review=ROOT/'.tmp/friendly-building-art-20261021';review.mkdir(parents=True,exist_ok=True)
    buildings={};checks=[]
    for record in generation['images']:
        kind=record['kind'];raw=ART/record['rawImage'];target=ART/record['selectedImage']
        assert hashlib.sha256(raw.read_bytes()).hexdigest()==record['rawSHA256']
        image=Image.open(raw).convert('RGBA');pixels=np.array(image)
        removed=int(np.count_nonzero((pixels[:,:,3]>0)&(pixels[:,:,3]<4)))
        pixels[pixels[:,:,3]<4,3]=0
        image=Image.fromarray(pixels);image.save(target)
        alpha=pixels[:,:,3]
        assert image.getchannel('A').getextrema()==(0,255)
        assert not np.any(np.r_[alpha[0],alpha[-1],alpha[:,0],alpha[:,-1]])
        bounds=image.getchannel('A').getbbox()
        assert min(bounds[:2])>=2 and bounds[2]<image.width-2 and bounds[3]<image.height-2
        point=record['groundAnchorPx'];assert alpha[point[1],point[0]]>=64
        labels,_=ndimage.label(alpha>=64);areas=np.bincount(labels.ravel());areas[0]=0
        fraction=float(areas.max())/int(np.count_nonzero(alpha>=64));assert fraction>.999
        small=np.array(image.getchannel('A').resize((320,320),Image.Resampling.NEAREST))>=80
        sx,sy=image.width/320,image.height/320;runs=[]
        for y,row in enumerate(small):
            edges=np.diff(np.r_[False,row,False].astype(np.int8))
            runs.extend(box(float(l)*sx,y*sy,float(r)*sx,(y+1)*sy)
                        for l,r in zip(np.flatnonzero(edges==1),np.flatnonzero(edges==-1)))
        geometry=unary_union(runs)
        if geometry.geom_type=='MultiPolygon':geometry=max(geometry.geoms,key=lambda g:g.area)
        geometry=geometry.simplify(3,preserve_topology=True);assert geometry.is_valid
        outline=[[round(x,3),round(y,3)] for x,y in list(geometry.exterior.coords)[:-1]]
        digest=hashlib.sha256(target.read_bytes()).hexdigest();record['sha256']=digest
        record['subvisibleAlphaPixelsCleared']=removed
        buildings[kind]={'kind':kind,'name':record['name'],
            'texture':'image/friendly-buildings-20261021/'+target.name,
            'pixelSize':list(image.size),'sha256':digest,'alphaBoundsPx':list(bounds),
            'occupancy':round((bounds[2]-bounds[0])/image.width,8),
            'anchor':[round(point[0]/image.width,8),round(point[1]/image.height,8)],
            'groundAnchorPx':point,'visualOutlinePx':outline,
            'collisionSource':'Data.buildings.'+kind+'.size',
            'existingCollisionSize':sizes[kind]['size'],'animated':False}
        check={'kind':kind,'format':'RGBA','size':list(image.size),'alphaExtrema':[0,255],
               'alphaBoundsPx':list(bounds),'transparentBorder':True,
               'mainComponentFraction':round(fraction,8),'anchorPx':point,
               'anchorAlpha':int(alpha[point[1],point[0]]),'outlineVertices':len(outline),
               'outlineValid':True,'originalCollisionSizeUnchanged':sizes[kind]['size'],
               'subvisibleAlphaPixelsCleared':removed,'smallScaleReviewFiles':[]}
        for side in [96,64]:
            thumb=image.copy();thumb.thumbnail((side,side),Image.Resampling.LANCZOS)
            output=review/f'{kind}-{side}.png';thumb.save(output)
            check['smallScaleReviewFiles'].append(output.relative_to(ROOT).as_posix())
        checks.append(check)
    descriptor={'schema':1,'name':'首批友军建筑静态美术','artDate':'2026-10-21',
        'generator':'built-in image_gen','runtimeRendererConnected':False,
        'collisionPolicy':'Always use existing Data.buildings[kind].size. Image canvas/visual outline is not a physics collider.',
        'renderContract':{'textureRoot':'res://assets/',
            'sideWorld':'Data.buildings[kind].size / occupancy',
            'drawRect':'Rect2(projected_world_center - anchor * sideWorld, Vector2.ONE * sideWorld)',
            'outlineUse':'Optional visual picking only; never replace existing square footprint.'},
        'buildings':buildings}
    write(ART/'friendly_buildings.json',descriptor)
    write(ART/'generation.json',generation)
    write(ART/'art-validation.json',{'schema':1,'scope':'Static PNG alpha, reviewed base anchor, visual contour and small-scale readability; not runtime game acceptance.','buildings':checks})
    print(json.dumps([{'kind':c['kind'],'bounds':c['alphaBoundsPx'],'anchor':c['anchorPx'],
                      'mainComponentFraction':c['mainComponentFraction'],'outlineVertices':c['outlineVertices']} for c in checks],ensure_ascii=False))


if __name__=='__main__':main()
