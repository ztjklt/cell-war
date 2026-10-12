"""Register a GPT cleanup only inside the proven food-guide display strip."""
from pathlib import Path
from copy import deepcopy
import hashlib,json,sys
sys.path.insert(0,'/tmp/reference-map-tools')
import numpy as np
from PIL import Image
from shapely.geometry import LineString
import build_fullbody_vascular_material as c

ROOT=Path(__file__).resolve().parents[2]
DOC=ROOT/'docs/body-life/vascular-art-study/fullbody-015/bake'
OUT=DOC/'fourth-candidate-g'
ASSET=ROOT/'assets/image/anatomy-reference/vascular-study/fullbody-015-candidate-v4g/foreground'
GENERATED=ROOT/'assets/image/anatomy-reference/vascular-study/fullbody-gpt-source/fourth/root/celiac-helper-clean-gpt-v1.png'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()

def main():
 OUT.mkdir(parents=True,exist_ok=True);ASSET.mkdir(parents=True,exist_ok=True)
 previous=DOC/'fourth-candidate-f/manifest.json';d=deepcopy(json.loads(previous.read_text()))
 a=next(a for a in d['assets'] if a['id']=='celiac-stomach-complete-junction')
 old_path=ROOT/a['path'];old=np.asarray(Image.open(old_path).convert('RGBA')).copy()
 im=Image.open(GENERATED).convert('RGBA')
 original=Image.open(ROOT/a['rawPath'])
 assert im.size==original.size==(1254,1254),'GPT fixed registration changed'
 x,y,xx,yy=a['generatedContentBox'];w,h=a['pixelSize'];b=a['sourceBox']
 fresh=np.asarray(im.transform((w,h),Image.Transform.AFFINE,((xx-x)/w,0,x,0,(yy-y)/h,y),resample=Image.Resampling.BILINEAR))
 # This strip is the independently located thin guide in a flat food floor.
 # It has no tube, wall or access point; apply the GPT raster there only.
 raw_points=[(900,250),(970,248),(1040,250),(1110,260),(1190,276),(1254,286)]
 source_points=[(b[0]+(px-x)/(xx-x)*(b[2]-b[0]),b[1]+(py-y)/(yy-y)*(b[3]-b[1])) for px,py in raw_points]
 curve=LineString(source_points)
 outer=c.mask(curve.buffer(.70),b,[w,h]);inner=c.mask(curve.buffer(.38),b,[w,h])
 weight=np.maximum(inner,outer.astype(float)*.35)/255
 weight*=old[:,:,3]>0
 new=old.copy();new[:,:,:3]=np.rint(old[:,:,:3]*(1-weight[:,:,None])+fresh[:,:,:3]*weight[:,:,None]).astype(np.uint8)
 assert np.array_equal(old[:,:,3],new[:,:,3])
 changed=np.any(old[:,:,:3]!=new[:,:,:3],axis=2)
 assert not np.any(changed & (outer==0))
 path=ASSET/'celiac-stomach-complete-junction.png';Image.fromarray(new).save(path)
 mask=OUT/'gpt-display-strip-mask.png';Image.fromarray(outer).save(mask)
 old_sha=a['sha256'];new_resource=str(path.relative_to(ROOT/'assets'))
 a.update(path=str(path.relative_to(ROOT)),resource=new_resource,sha256=sha(path))
 for row in d['runtimeSpec']['foregroundPatches']:
  if row['id']==a['id']:row['resource']=new_resource
 contract={'schema':'gpt-fixed-celiac-helper-cleanup/v1','status':'PRIVATE_CANDIDATE',
  'baselineManifestPath':str(previous.relative_to(ROOT)),'baselineManifestSha256':sha(previous),
  'oldAssetPath':str(old_path.relative_to(ROOT)),'oldAssetSha256':old_sha,
  'generatedImagePath':str(GENERATED.relative_to(ROOT)),'generatedImageSha256':sha(GENERATED),
  'newAssetPath':str(path.relative_to(ROOT)),'newAssetSha256':sha(path),
  'sourceBox':b,'pixelSize':[w,h],'sourceCenterline':source_points,
  'maskPath':str(mask.relative_to(ROOT)),'maskSha256':sha(mask),'maximumStripHalfWidthSource':.70,
  'changedRgbPixels':int(changed.sum()),'alphaChangedPixels':0,'changesOutsideMask':0,
  'heartAndBothLungsUnchanged':True,'routes202AndLogical135Visual107Unchanged':True,
  'generator':'built-in GPT imagegen','nativeEvidence':False,
  'reason':'GPT removed a faint copied authoring guide in the yellow food floor. Register only its fixed strip; retain all vessel banks, wall edges, foreground alpha and other pixels.'}
 cp=OUT/'repair-contract.json';cp.write_text(json.dumps(contract,ensure_ascii=False,indent=2)+'\n')
 d['gptCeliacHelperCleanup']=contract
 for p in [GENERATED,mask,cp,Path(__file__),previous]:d['inputs'][str(p.relative_to(ROOT))]=sha(p)
 (OUT/'manifest.json').write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
 print(json.dumps({'manifestSha256':sha(OUT/'manifest.json'),'changedRgbPixels':int(changed.sum()),'sourcePoints':source_points}),flush=True)

if __name__=='__main__':main()
