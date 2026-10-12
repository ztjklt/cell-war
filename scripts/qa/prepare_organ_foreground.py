"""Refine only Trace-located chest foreground using original source pigment.
No bitmap changes: output smooth source-coordinate blue/coronary fill geometry.
The coarse 48-colour palette is not used to recolour the organ surface.
"""
from pathlib import Path
import hashlib,json
import cv2,numpy as np
from scipy.ndimage import gaussian_filter1d
from PIL import Image
rgb=np.asarray(Image.open('assets/image/anatomy-reference/reference.png').convert('RGB'))
r,g,b=[rgb[:,:,i].astype(np.int16) for i in range(3)]
roi=np.zeros(r.shape,bool);roi[270:491,360:657]=True
blue=roi&(b-r>32)&(g-r>28)&(b>150)
roi[:]=False;roi[390:459,478:557]=True
coronary=roi&(r>235)&(g>175)&(g-b>42)
specs=[('blue',blue,2),('coronary',coronary,.5)]
groups=[];audit={}
for name,mask,min_area in specs:
 mask=(cv2.GaussianBlur(mask.astype('float32'),(3,3),.6)>.5).astype('uint8')*255
 cs,h=cv2.findContours(mask,cv2.RETR_CCOMP,cv2.CHAIN_APPROX_NONE)
 if h is None:continue
 paths=[]
 for i,c in enumerate(cs):
  area=cv2.contourArea(c)
  if area<min_area:continue
  p=c.reshape(-1,2).astype(float)
  p=gaussian_filter1d(p,2 if name=='blue' else 1.25,axis=0,mode='wrap')
  for _ in range(2):
   q=np.roll(p,-1,axis=0);p=np.stack((p*.75+q*.25,p*.25+q*.75),axis=1).reshape(-1,2)
  p=cv2.approxPolyDP(p.astype('float32'),.025,True).reshape(-1,2)
  # A tenth-pixel inward reserve keeps the smoothed edge inside source pigment.
  tangent=np.roll(p,-1,axis=0)-np.roll(p,1,axis=0)
  normal=np.stack((-tangent[:,1],tangent[:,0]),axis=1)
  length=np.maximum(np.linalg.norm(normal,axis=1,keepdims=True),1e-9)
  signed=np.sum(p[:,0]*np.roll(p[:,1],-1)-np.roll(p[:,0],-1)*p[:,1])
  sign=(1 if signed>0 else -1)*(-1 if h[0][i][3]>=0 else 1)
  p=p+normal/length*sign*.1
  paths.append({'points':[[round(float(v),3) for v in q] for q in p],'hole':bool(h[0][i][3]>=0)})
 selected=rgb[mask>0];color=np.median(selected,axis=0).astype(int).tolist()
 top=[102,168,241] if name=='blue' else [255,219,145]
 bottom=[77,149,225] if name=='blue' else [251,202,128]
 groups.append({'kind':name,'color':color,'top':top,'bottom':bottom,'paths':paths})
 allowed=((b-r>20)&(g-r>-30)) if name=='blue' else ((r>220)&(g>135)&(g-b>24))
 y0,y1,x0,x1=(270,491,360,657) if name=='blue' else (390,459,478,557)
 compiled=[np.array(path['points'],np.float32) for path in paths]
 filled=0;outside=0
 for py in range(y0,y1):
  for px in range(x0,x1):
   inside=False
   for contour in compiled:
    if cv2.pointPolygonTest(contour,(float(px),float(py)),False)>=0:inside=not inside
   if inside:
    filled+=1;outside+=int(not allowed[py,px])
 assert outside==0,(name,outside)
 audit[name]={'sourceROI':[x0,y0,x1-1,y1-1],'paths':len(paths),'vertices':sum(len(p['points']) for p in paths),'filledSourcePixels':filled,'outsideForegroundPixels':outside}

def lua(v):
 if isinstance(v,dict):return '{'+','.join(k+'='+lua(value) for k,value in v.items())+'}'
 if isinstance(v,list):return '{'+','.join(lua(x) for x in v)+'}'
 if isinstance(v,str):return '"'+v+'"'
 if isinstance(v,bool):return str(v).lower()
 return str(v)
source_hash=hashlib.sha256(Path('assets/image/anatomy-reference/reference.png').read_bytes()).hexdigest()
Path('scripts/war/OrganForegroundData.lua').write_text('-- Source-pigment refinement of fixed chest foreground; no bitmap edits.\nreturn {sourceSha256="'+source_hash+'",groups='+lua(groups)+'}\n')
dest=Path('docs/body-life/organ-foreground');dest.mkdir(parents=True,exist_ok=True)
(dest/'source-pigment-audit.json').write_text(json.dumps({'sourceSha256':source_hash,'classification':'Blue includes its source indigo shadow (B-R>20, G-R>-30); coronary R>220,G>135,G-B>24. No red tissue or ivory foreground is included.','groups':audit},indent=2)+'\n')
print([(g['kind'],g['color'],len(g['paths'])) for g in groups])
