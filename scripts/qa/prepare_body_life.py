"""Analyze reference pixels into fixed foreground geometry; never edits the source image."""
from pathlib import Path
import json, hashlib
import numpy as np
import cv2
from PIL import Image

source=Path('assets/image/anatomy-reference/reference.png')
rgb=np.asarray(Image.open(source).convert('RGB')).astype(np.int16)
specs={'heart':(478,382,79,77),'lung_r':(375,292,102,188),'lung_l':(541,294,99,186)}
data={};parts=[]
for name,(x,y,w,h) in specs.items():
    crop=rgb[y:y+h+1,x:x+w+1]
    # Fixed vessels and airway pigment plus a one-pixel safety rim.
    protected=((crop[:,:,2]-crop[:,:,0]>10)&(crop[:,:,1]-crop[:,:,0]>4)).astype(np.uint8)*255
    if name=='heart':protected[:10,:]=255
    protected=cv2.dilate(protected,np.ones((3,3),np.uint8))
    contours,_=cv2.findContours(protected,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE)
    paths=[]
    for contour in contours:
        if cv2.contourArea(contour)<2:continue
        p=cv2.approxPolyDP(contour,.35,True).reshape(-1,2)
        paths.append([[int(a)+x,int(b)+y] for a,b in p])
    data[name]={'sourceRect':[x,y,w,h],'fixedPaths':paths}
    def lua(v):
        if isinstance(v,list):return '{'+','.join(lua(a) for a in v)+'}'
        return str(v)
    parts.append(name+'='+lua(paths))
dest=Path('assets/image/anatomy-reference/body-life');dest.mkdir(parents=True,exist_ok=True)
prior=json.loads((dest/'manifest.json').read_text()) if (dest/'manifest.json').exists() else {}
manifest={**prior,'source':'image/anatomy-reference/reference.png','sourceSha256':hashlib.sha256(source.read_bytes()).hexdigest(),'anatomyVersion':4,'coordinateSpace':[1024,1536],'delivery':prior.get('delivery','original atlas sampled through runtime geometry; no repainted pixels'),'organs':data}
(dest/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
Path('scripts/war/BodyLifeMasks.lua').write_text('-- Pixel-derived fixed foreground. Regenerate with scripts/qa/prepare_body_life.py.\nreturn {'+','.join(parts)+'}\n')
print({name:sum(len(p) for p in value['fixedPaths']) for name,value in data.items()})
