"""Straight-channel bilinear/trilinear model at native009 cameras; offline only."""
from pathlib import Path
import json,hashlib,math,sys
sys.path.insert(0,'/tmp/reference-map-tools')
import numpy as np
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[3]
STAGE=Path(__file__).resolve().parent
OUT=ROOT/'docs/body-life/vascular-art-study/fullbody-015/bake/fourth-candidate-j/diagnostics'
OUT.mkdir(exist_ok=True)
H=json.loads((STAGE/'baseline-manifest.json').read_text())
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
records=[]
scan=json.loads((ROOT/'.tmp/fullbody-015/h-staging/native009-scan/review.json').read_text())
cases=[{'id':'celiac-ellipse','sourceBBoxApprox':[516.4270833333334,480.1625,531.0104166666666,496.04895833333336],
        'nativeScreenshot':'docs/body-life/vascular-art-study/fullbody-015/native-009/21-celiac-stomach-z0.15.png',
        'nativePixelBBox':[950,535,1230,840]}]+scan['findings']
sheet_items=[]
for n,q in enumerate(cases):
 b=q['sourceBBoxApprox'];w,h=q['nativePixelBBox'][2]-q['nativePixelBBox'][0],q['nativePixelBBox'][3]-q['nativePixelBBox'][1]
 # Camera crop preserves .15 DPR2 sampling; enlarge only after composition.
 before=compose(H,b,(w,h));after=compose(I,b,(w,h))
 bp=OUT/(q['id']+'-straight-H-before.png');ap=OUT/(q['id']+'-straight-J-after.png')
 before.save(bp);after.save(ap)
 native=Image.open(ROOT/q['nativeScreenshot']).crop(tuple(q['nativePixelBBox']))
 scale=min(3,max(1,round(430/w)));size=(w*scale,h*scale)
 header=40;compare=Image.new('RGB',(size[0]*3,size[1]+header),'white');draw=ImageDraw.Draw(compare)
 for column,(label,im)in enumerate([('Native009',native),('H straight mip model',before),('J straight mip model',after)]):
  compare.paste(im.resize(size,Image.Resampling.NEAREST),(column*size[0],header));draw.text((column*size[0]+8,8),label,fill='black')
 cp=OUT/(q['id']+'-compare.png');compare.save(cp)
 records.append({'id':q['id'],'sourceBox':b,'samplingPixelSize':[w,h],
   'nativeScreenshot':q['nativeScreenshot'],'nativeScreenshotSha256':sha(ROOT/q['nativeScreenshot']),
   'nativePixelBBox':q['nativePixelBBox'],'comparisonPath':str(cp.relative_to(ROOT)),
   'modelBeforePath':str(bp.relative_to(ROOT)),'modelAfterPath':str(ap.relative_to(ROOT)),
   'modelAfterSha256':sha(ap),'nativeEvidence':False})
 thumb=compare.copy();thumb.thumbnail((1000,410));sheet_items.append((q['id'],thumb))
 print(q['id'],flush=True)
columns=2;row_height=455;sheet=Image.new('RGB',(2040,row_height*math.ceil(len(sheet_items)/columns)),'#f4f4f4');draw=ImageDraw.Draw(sheet)
for idx,(label,im)in enumerate(sheet_items):
 x=(idx%2)*1020;y=(idx//2)*row_height;draw.text((x+10,y+5),label,fill='black');sheet.paste(im,(x+10,y+32))
sp=OUT/'native009-known-fringes-straight-model-contact.png';sheet.save(sp)
report={'schema':'candidate-j-straight-channel-mip-diagnostics/v1','nativeEvidence':False,
 'candidateManifestSha256':sha(OUT.parent/'manifest.json'),'baselineManifestSha256':sha(STAGE/'baseline-manifest.json'),
 'sampling':'RGBA bands independent bilinear; box downsampled mip levels and trilinear blend at rho=texels/physicalPixel. GPU approximation; exact native backend filtering remains unverified.',
 'cases':records,'contactSheet':str(sp.relative_to(ROOT)),'contactSheetSha256':sha(sp)}
(OUT/'previews.json').write_text(json.dumps(report,indent=2)+'\n')
