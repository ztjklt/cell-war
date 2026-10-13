"""Register the uninterrupted lower cava on the existing cardiac atlas.

Use approved watercolor strip UVs and the already generated vessel-free tissue
bed. The former y420 edit limit must never become a painted pipe end.
"""
from pathlib import Path
import sys,json,hashlib
import numpy as np
from PIL import Image
from scipy.ndimage import maximum_filter
from shapely.geometry import LineString,box
from shapely.ops import unary_union
from lupa.lua54 import LuaRuntime
sys.path.insert(0,str(Path(__file__).parent))
from build_left_vessels import register,smooth,contour,BOX,SIZE
from build_heart_perimeter import mask
from register_simple_heart import overlay,padding,rings
from register_heart_port_connections import sampler,uv_edge
from prepare_heart_battlefield import lua,rings as export_rings
from check_regional_vascular_refinement import convert
import build_fullbody_vascular_material as material

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'docs/heart-simple-20261012/cava-transition-v13'
ASSETS=ROOT/'assets/image/anatomy-reference/vascular-study/heart-simple-20261012/cava-transition-v13'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
 OUT.mkdir(parents=True,exist_ok=True);ASSETS.mkdir(parents=True,exist_ok=True)
 visual=(ROOT/'scripts/war/HeartVisualData.lua').read_text()
 (OUT/'baseline-HeartVisualData.lua').write_text(visual)
 l=LuaRuntime(unpack_returned_tuples=True);l.globals().source=visual
 l.execute("package.path='scripts/?.lua;'..package.path;H=assert(load(source))();A=require('war.FullBodyMapArtData')")
 H=convert(l.globals().H);data=json.loads((ROOT/'docs/heart-v1/geometry/runtime-data.json').read_text())
 reference=json.loads((ROOT/'docs/body-life/vascular-art-study/final-reference-data.json').read_text())['edges']
 def edge(i):
  if i>202:return next(e for e in data['edgeAdditions']if e['laneIndex']==i)
  return data['edgeUpdates'].get(str(i),{'points':reference[i-1]['samples'],'widthSource':reference[i-1]['lumenWidthSource']})
 def shape(i):
  if str(i)in data['rawBloodDomains']:return rings(data['rawBloodDomains'][str(i)])
  e=edge(i);return LineString(e['points']).buffer(e['widthSource']/2,quad_segs=24)
 before=np.array(Image.open(ROOT/'assets'/H['resource']).convert('RGBA'))
 clean=register(ROOT/'assets/image/anatomy-reference/vascular-study/heart-simple-20261012/left-vessels-v11/left-vessel-clean-bed-raw-v1.png',[432,306,580,475.2])
 heart=register(ROOT/'assets/image/anatomy-reference/vascular-study/heart-simple-20261012/registered-v3/heart-watercolor-registered-v1.png',[468,326,568,467])
 yy,xx=np.mgrid[:SIZE[1],:SIZE[0]];sx=432+(xx+.5)*.1;sy=306+(yy+.5)*174/1692
 # Only the old horizontal tissue scar and the actual caval banks are cleared.
 # The lung texture below the repaired margin remains completely transparent.
 seam=smooth((sx-459)/1)*smooth((484-sx)/2)*smooth((sy-414)/3)*smooth((429-sy)/4)
 # Protect the accepted wall pigments, including their antialiased rim. The
 # cleanup must not blend a second generated heart edge into that silhouette.
 wall=maximum_filter(heart[:,:,3]/255,size=21)
 clean_weight=seam*(1-wall)*(1-mask(shape(173).buffer(.4),BOX,SIZE)/255)
 manifest=json.loads((ROOT/'docs/body-life/vascular-art-study/fullbody-015/bake/manifest.json').read_text())
 bake=sampler(manifest['pipeMaterials']['materials']);material.mask=mask
 blue=unary_union([shape(i)for i in [1,15,17,22,67,72,211]])
 # Sample the whole union before blending this local section. The working
 # rectangle cannot create a transverse material cap at y420.
 uv=uv_edge(edge(22)['points']+edge(211)['points'][1:])
 vein=bake.pipe_material(blue,BOX,SIZE,'vein',3,uv)
 vein[:,:,3]=np.rint(vein[:,:,3]*(1-wall)).astype(np.uint8)
 # The pulmonary return passes behind the caval stem and remains a separate
 # graph route. Restore its exposed bank after tissue cleanup.
 # Preserve the already repaired branch byte-for-byte. Its existing accepted
 # texture owns the complete pulmonary-return path outside the caval crossing.
 candidate=overlay(clean,vein)
 # Crossfade the final tube and tissue exactly once, in premultiplied alpha.
 # Transparent padding carries blue RGB for filtering; interpolating that RGB
 # directly paints a blue ghost into partially opaque restored tissue.
 old_alpha=before[:,:,3]/255;new_alpha=candidate[:,:,3]/255
 alpha=old_alpha*(1-clean_weight)+new_alpha*clean_weight
 premult=before[:,:,:3]*old_alpha[:,:,None]*(1-clean_weight[:,:,None])+candidate[:,:,:3]*new_alpha[:,:,None]*clean_weight[:,:,None]
 rgb=np.divide(premult,alpha[:,:,None],out=np.zeros_like(premult),where=alpha[:,:,None]>0)
 result=np.dstack([np.rint(rgb).clip(0,255).astype(np.uint8),np.rint(alpha*255).clip(0,255).astype(np.uint8)])
 vein[:,:,3]=np.rint(vein[:,:,3]*clean_weight).astype(np.uint8)
 resource=ASSETS/'heart-continuous-cava-v1.png';Image.fromarray(padding(result)).save(resource)
 Image.fromarray(vein).save(OUT/'continuous-cava.png')
 Image.fromarray(np.rint(clean_weight*255).astype(np.uint8)).save(OUT/'cleanup-weight.png')
 front=H['frontPipeRings'];shown=contour(vein[:,:,3])
 region=box(460,417,484,425)
 front['e015']=export_rings(rings(front['e015']).difference(region).union(shown.intersection(shape(15))))
 # A rear lung-return unit is hidden exactly where the new caval bank covers it.
 front['e173']=export_rings(rings(front['e173']).difference(shown.buffer(.08)))
 text=visual.replace(H['resource'],str(resource.relative_to(ROOT/'assets'))).replace('revision=15,','revision=16,')
 start=text.index('H.frontPipeRings=');end=text.index('\nlocal function inside',start)
 text=text[:start]+'H.frontPipeRings='+lua(front)+text[end:]
 (OUT/'HeartVisualData.lua').write_text(text)
 scope=contour(np.where(np.maximum(clean_weight,vein[:,:,3]/255)>0,255,0).astype(np.uint8)).buffer(.12)
 report={'status':'STAGED','revision':16,'layoutRevision':4,'resource':str(resource.relative_to(ROOT/'assets')),'sha256':sha(resource),'sourceBox':BOX,'pixelSize':list(SIZE),'atlasPanels':1,'formerCutY':420,'continuousLane':15,'editScope':export_rings(scope),'geometryUnchanged':True,'nativeVisualEvidence':False,'reusedGeneratedSource':'assets/image/anatomy-reference/vascular-study/heart-simple-20261012/left-vessels-v11/left-vessel-clean-bed-raw-v1.png','imagegenPromptRecord':'docs/heart-simple-20261012/left-vessels-v11/imagegen-prompts.txt','builderSha256':sha(__file__),'unchangedRuntimeHashes':{str(p.relative_to(ROOT)):sha(p)for p in (ROOT/'scripts/war').glob('*.lua')if p.name!='HeartVisualData.lua'}}
 (OUT/'registration.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
 print(json.dumps({'status':'STAGED','revision':16,'continuousLane':15,'geometryUnchanged':True}))
if __name__=='__main__':main()
