"""Verify retained views after a local organ-mask correction using fixed cameras."""
import argparse,hashlib,json,subprocess,sys,io
from pathlib import Path
import numpy as np
from PIL import Image
import render_body_closeups as c
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--old-data',required=True);p.add_argument('--output',required=True);p.add_argument('--roi',default='430,532,470,578');p.add_argument('--worker',choices=['old','current']);a=p.parse_args()
root=c.r.b.ROOT;out=Path(a.output);out.mkdir(parents=True,exist_ok=True)
if a.worker:
 if a.worker=='old':c.r.b.l.globals().qaOldData=str(Path(a.old_data).resolve());c.r.b.l.execute("package.loaded['war.OrganBoundariesData']=dofile(qaOldData)")
 c.r.initialise();rows=[]
 views=json.loads((root/'docs/body-life/previews/visible-life/frames/view-catalog.json').read_text())['views']
 roi=list(map(float,a.roi.split(',')))
 for v in views:
  if v['anchor'] not in ('organ-fit','center'):continue
  x,y=v['sourceCenter'];w,h=v['visibleSourceSize'];box=[x-w/2,y-h/2,x+w/2,y+h/2]
  hit=box[0]<roi[2] and box[2]>roi[0] and box[1]<roi[3] and box[3]>roi[1]
  for t in (0,1.92):
   data=c.draw(t,x,y,v['zoom'],640,480,1);name=f"{a.worker}-{v['id']}-{t}.png";(out/name).write_bytes(data)
  rows.append({'id':v['id'],'sourceViewport':box,'intersectsCorrectedROI':hit})
 (out/f'{a.worker}-views.json').write_text(json.dumps(rows,indent=2));sys.exit()
for version in ('old','current'):
 subprocess.run([sys.executable,__file__,'--old-data',a.old_data,'--output',str(out),'--roi',a.roi,'--worker',version],check=True)
rows=json.loads((out/'current-views.json').read_text());different=[]
for v in rows:
 v['pixelComparisons']=[]
 for t in (0,1.92):
  old=np.asarray(Image.open(out/f"old-{v['id']}-{t}.png").convert('RGB'),np.int16);now=np.asarray(Image.open(out/f"current-{v['id']}-{t}.png").convert('RGB'),np.int16);diff=np.abs(old-now)
  v['pixelComparisons'].append({'time':t,'maxRgbDifference':int(diff.max()),'changedPixelCount':int((diff.max(axis=2)>0).sum())})
 if any(x['changedPixelCount'] for x in v['pixelComparisons']):different.append(v['id'])
 if not v['intersectsCorrectedROI']:assert all(x['maxRgbDifference']==0 for x in v['pixelComparisons']),v
report={'nativeEvidence':False,'oldDataSha256':hashlib.sha256(Path(a.old_data).read_bytes()).hexdigest(),'currentDataSha256':hashlib.sha256((root/'scripts/war/OrganBoundariesData.lua').read_bytes()).hexdigest(),'correctionROI':list(map(float,a.roi.split(','))),'actualChangedViews':different,'views':rows,'reason':'Retained fixed cameras outside local corrected source ROI render identically at two independent phases; intersecting views are regenerated. This does not claim native pixel identity.'}
(out/'data-compatibility.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps({'changed':different,'unchanged':len(rows)-len(different)},indent=2))
