"""Straight-channel bilinear/trilinear model at native009 cameras; offline only."""
from pathlib import Path
import json,hashlib,math,sys
sys.path.insert(0,'/tmp/reference-map-tools')
import numpy as np
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[3]
STAGE=Path(__file__).resolve().parent
OUT=ROOT/'docs/body-life/vascular-art-study/fullbody-015/bake/fourth-candidate-k/diagnostics'
OUT.mkdir(exist_ok=True)
H=json.loads((OUT.parent.parent/'fourth-candidate-j/manifest.json').read_text())
I=json.loads((OUT.parent/'manifest.json').read_text())
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def sampled(im,size,transform,lod):
 bands=im.split();lo=math.floor(lod);hi=math.ceil(lod);layers=[]
 for level in sorted(set([lo,hi])):
  scale=2**level
  downs=(max(1,im.width//scale),max(1,im.height//scale))
  fx,fy=downs[0]/im.width,downs[1]/im.height
  tr=(transform[0]*fx,0,transform[2]*fx,0,transform[4]*fy,transform[5]*fy)
  arrays=[]
  for band in bands:
   data=band if level==0 else band.resize(downs,Image.Resampling.BOX)
   arrays.append(np.asarray(data.transform(size,Image.Transform.AFFINE,tr,resample=Image.Resampling.BILINEAR)))
  layers.append(np.stack(arrays,axis=2))
 if len(layers)==1:return layers[0]
 return np.rint(layers[0].astype(float)*(hi-lod)+layers[1].astype(float)*(lod-lo)).astype(np.uint8)
def compose(m,b,size):
 sx,sy=(b[2]-b[0])/size[0],(b[3]-b[1])/size[1]
 quiet=ROOT/'assets/image/anatomy-reference/vascular-study/fullbody-gpt-source/quiet-body-registered-v2.png'
 im=Image.open(quiet).convert('RGBA');base=Image.fromarray(sampled(im,size,(sx,0,b[0],0,sy,b[1]),max(0,math.log2(max(sx,sy)))))
 ys,xs=np.mgrid[:size[1],:size[0]];px,py=b[0]+(xs+.5)*sx,b[1]+(ys+.5)*sy
 for kind in ['surfaceTiles','organs','deepTiles','junctions','foregroundPatches']:
  for q in m['runtimeSpec'].get(kind,[]):
   box=q['sourceBox']
   if box[2]<=b[0]or box[0]>=b[2]or box[3]<=b[1]or box[1]>=b[3]:continue
   im=Image.open(ROOT/'assets'/q['resource']).convert('RGBA')
   fx,fy=im.width/(box[2]-box[0]),im.height/(box[3]-box[1])
   tr=(sx*fx,0,(b[0]-box[0])*fx,0,sy*fy,(b[1]-box[1])*fy)
   layer=sampled(im,size,tr,max(0,math.log2(max(sx*fx,sy*fy))))
   if q.get('coreBox'):
    c=q['coreBox'];layer[~((px>=c[0])&(px<c[2])&(py>=c[1])&(py<c[3]))]=0
   base=Image.alpha_composite(base,Image.fromarray(layer))
 return base

import shutil
assert shutil.disk_usage(ROOT).free>=500*1024*1024
views=json.loads((ROOT/'docs/body-life/vascular-art-study/fullbody-015/native-011/system-views.json').read_text())
phases={q['path']:q for q in views['captures']}
cases=[('large-gut-blue-in-red','09-large_intestine-z0.15.png',[910,520,1170,605]),
       ('small-intestine-exit','10-small_intestine-z0.15.png',[2100,80,2300,260]),
       ('celiac-triangle-and-crossing','21-celiac-stomach-z0.15.png',[950,535,1230,840]),
       ('stomach-same-celiac-site','02-stomach-z0.15.png',[500,410,810,750]),
       ('wrist-right-blue-inner-line','43-wrist-right-z0.15.png',[1120,540,1400,920]),
       ('wrist-left-blue-inner-line','44-wrist-left-z0.15.png',[990,500,1320,950])]
records=[];thumbs=[]
for case,filename,bb in cases:
 p=ROOT/'docs/body-life/vascular-art-study/fullbody-015/native-011'/filename
 assert sha(p)==phases[filename]['sha256']
 im=Image.open(p);physical_width,physical_height=im.size[0],im.size[1]-64
 camera=phases[filename]['phase']['camera'];zoom=phases[filename]['phase']['zoom'];pps=64*zoom*2
 b=[camera['x']/2+(bb[0]-physical_width/2)/pps,(camera['y']-512)/2+(bb[1]-64-physical_height*.47)/pps,
    camera['x']/2+(bb[2]-physical_width/2)/pps,(camera['y']-512)/2+(bb[3]-64-physical_height*.47)/pps]
 w,h=bb[2]-bb[0],bb[3]-bb[1]
 before=compose(H,b,(w,h));after=compose(I,b,(w,h));native=im.crop(tuple(bb))
 bp=OUT/(case+'-J-straight-before.png');ap=OUT/(case+'-K-straight-after.png');before.save(bp);after.save(ap)
 scale=2;size=(w*scale,h*scale);compare=Image.new('RGB',(size[0]*3,size[1]+38),'white');draw=ImageDraw.Draw(compare)
 for column,(label,panel)in enumerate([('Actual Native011 / J',native),('J straight RGBA mip model',before),('K straight RGBA mip model',after)]):
  compare.paste(panel.resize(size,Image.Resampling.NEAREST),(column*size[0],38));draw.text((column*size[0]+6,10),label,fill='black')
 cp=OUT/(case+'-compare.png');compare.save(cp)
 changed=np.any(np.asarray(after)!=np.asarray(before),axis=2)
 records.append({'id':case,'sourceBox':b,'physicalPixelCrop':bb,'physicalPixelsPerSource':pps,'samplingPixelSize':[w,h],
                 'nativeReferencePath':str(p.relative_to(ROOT)),'nativeReferenceSha256':sha(p),'nativeCandidate':'J',
                 'comparisonPath':str(cp.relative_to(ROOT)),'comparisonSha256':sha(cp),
                 'beforePath':str(bp.relative_to(ROOT)),'beforeSha256':sha(bp),'afterPath':str(ap.relative_to(ROOT)),'afterSha256':sha(ap),
                 'modelChangedPixels':int(changed.sum()),'nativeEvidenceForK':False})
 thumb=compare.copy();thumb.thumbnail((1500,600));thumbs.append((case,thumb));print(case,int(changed.sum()),flush=True)
 sheet_height=sum(im.height+40 for _,im in thumbs);sheet=Image.new('RGB',(1520,sheet_height),'#eeeeee');draw=ImageDraw.Draw(sheet);y=0
 for label,panel in thumbs:
  draw.text((10,y+8),label,fill='black');sheet.paste(panel,(10,y+30));y+=panel.height+40
 sp=OUT/'native011-key-crops-model-contact.png';sheet.save(sp)
report={'schema':'candidate-k-native011-same-camera-straight-model/v1','candidateManifestSha256':sha(OUT.parent/'manifest.json'),
        'baselineJManifestSha256':sha(OUT.parent.parent/'fourth-candidate-j/manifest.json'),
        'quietBodySourcePath':'assets/image/anatomy-reference/vascular-study/fullbody-gpt-source/quiet-body-registered-v2.png',
        'quietBodySourceSha256':sha(ROOT/'assets/image/anatomy-reference/vascular-study/fullbody-gpt-source/quiet-body-registered-v2.png'),
        'nativeEvidenceForK':False,'sampling':'RGBA independent bands, BOX mip downsample and bilinear/trilinear interpolation at native011 .15 DPR2 camera. This is an approximation of GPU image sampling; it excludes dynamic cells/runtime overlays and does not replace native K evidence.',
        'cameraMapping':'source_x=camera.x/2+(px-W/2)/(64*zoom*2); source_y=(camera.y-512)/2+(py-64-(H-64)*.47)/(64*zoom*2)',
        'cases':records,'contactSheetPath':str(sp.relative_to(ROOT)),'contactSheetSha256':sha(sp)}
(OUT/'previews.json').write_text(json.dumps(report,indent=2)+'\n')
