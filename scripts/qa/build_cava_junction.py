"""Register one open watercolor floor at the venous and pulmonary joins.

Reuse the approved blood strip on the actual union boundary: per-branch banks
must never cross the interior of a common blood lumen. Artery and vein retain
their independent graph routes and explicit crossing depth.
"""
from pathlib import Path
import sys,json,hashlib
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter,maximum_filter
from shapely.geometry import LineString,Point,box
from shapely.ops import unary_union
sys.path.insert(0,str(Path(__file__).parent))
import build_fullbody_vascular_material as material
from build_heart_perimeter import mask
from build_pulmonary_return import display_shape,smooth
from register_simple_heart import overlay,padding,rings
from rebuild_heart_connections import register_image,BOX,SIZE
from register_heart_port_connections import sampler,uv_edge
from prepare_heart_battlefield import lua,rings as export_rings
from check_regional_vascular_refinement import convert
from lupa.lua54 import LuaRuntime

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'docs/heart-simple-20261012/cava-junction-v10'
ASSETS=ROOT/'assets/image/anatomy-reference/vascular-study/heart-simple-20261012/cava-junction-v10'
EDIT=[460,328,495,394]
GROUPS={'vein':[1,15,17,22,67,72],'artery':[3,172]}
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()

def main():
 l=LuaRuntime(unpack_returned_tuples=True);l.globals().baseline=(OUT/'baseline-HeartVisualData.lua').read_text()
 l.execute("package.path='scripts/?.lua;'..package.path;package.loaded['war.HeartVisualData']=assert(load(baseline))();H=require('war.HeartVisualData');S=require('war.FullBodyBattlefield').new(72026);N=require('war.OrganBattlefield').net(S)")
 H=convert(l.globals().H);N=l.globals().N
 lanes={}
 for system,ids in GROUPS.items():
  for i in ids:
   e=N.edges[i];pts=[(p[1]*.5,(p[2]-512)*.5)for _,p in e.points.items()]
   lanes[i]={'points':pts,'a':N.nodes[e.a].id,'b':N.nodes[e.b].id,'width':e.width*.5,'shape':LineString(pts).buffer(e.width*.25,quad_segs=24)}
 assert lanes[3]['b']==lanes[172]['a']=='lung_r.entry'
 assert all(lanes[i]['b']=='heart.v'for i in [15,17,22,67,72])
 assert lanes[1]['a']=='heart.v'
 before=np.array(Image.open(ROOT/'assets'/H['resource']).convert('RGBA'))
 raw=register_image(ROOT/'assets/image/anatomy-reference/vascular-study/heart-simple-20261012/registered-v3/heart-watercolor-registered-v1.png',[468,326,568,467])
 clean=register_image(ROOT/'assets/image/anatomy-reference/vascular-study/heart-simple-20261012/perimeter-v8/perimeter-clean-bed-raw-v1.png',[452,282,588,486])
 bed=overlay(clean,raw)
 yy,xx=np.mgrid[:SIZE[1],:SIZE[0]];sx=BOX[0]+(xx+.5)*.1;sy=BOX[1]+(yy+.5)*174/1692
 # Retain the generated right-atrial mouth. All other boundaries feather back
 # to the preceding one-panel map without painting neighboring chambers.
 area=smooth((sx-EDIT[0])/2)*smooth((EDIT[2]-sx)/2)*smooth((sy-EDIT[1])/2)*smooth((EDIT[3]-sy)/2)
 area*=smooth((np.hypot(sx-487,sy-379)-5)/2)
 physical={system:unary_union([lanes[i]['shape']for i in ids])for system,ids in GROUPS.items()}
 visible={system:physical[system].intersection(unary_union([rings(H['frontPipeRings'][f'e{i:03d}'])for i in ids]).buffer(.45))for system,ids in GROUPS.items()}
 # The old per-branch visibility clipped part of this true arterial node.
 # Open the actual union across the complete inlet, with no inherited caps.
 arterial_joint=Point(lanes[3]['points'][-1]).buffer(6)
 visible['artery']=visible['artery'].union(physical['artery'].intersection(arterial_joint))
 # Remove only obsolete colored edge pixels outside the actual union. The
 # accepted tissue bed supplies their background; cardiac art stays intact.
 rgb=before[:,:,:3].astype(int)
 old_blue=(rgb[:,:,2]>rgb[:,:,0])&(rgb[:,:,2]>rgb[:,:,1]+8)&(before[:,:,3]>40)
 outside=1-mask(unary_union(list(physical.values())).buffer(.16),BOX,SIZE)/255
 cleanup=gaussian_filter(maximum_filter(old_blue.astype(float),size=7),1.1)*outside*area
 art=before.copy()
 for k in range(4):art[:,:,k]=np.rint(before[:,:,k]*(1-cleanup)+bed[:,:,k]*cleanup).astype(np.uint8)
 materials=json.loads((ROOT/'docs/body-life/vascular-art-study/fullbody-015/bake/manifest.json').read_text())['pipeMaterials']['materials']
 bake=sampler(materials);material.mask=mask
 # One continuous dominant arc per joined material. Precise union boundary
 # distance owns the external banks, and flatUnionFloor owns every merge.
 vena=bake.pipe_material(physical['vein'],BOX,SIZE,'vein',3,uv_edge(list(reversed(lanes[17]['points']))))
 red_points=lanes[3]['points']+lanes[172]['points'][1:]
 artery=bake.pipe_material(physical['artery'],BOX,SIZE,'artery',4,uv_edge(red_points))
 for raster,system in [(vena,'vein'),(artery,'artery')]:raster[:,:,3]=mask(visible[system],BOX,SIZE)
 # The lower pulmonary artery crosses in front of the cava. This is a
 # shallow shadow on a separated plane, with no white cut or false node.
 shadow=np.zeros_like(art);shadow[:,:,:3]=[100,70,93]
 shadow_shape=visible['artery'].buffer(.20).difference(visible['artery']).intersection(visible['vein'])
 shadow[:,:,3]=np.rint(mask(shadow_shape,BOX,SIZE)*.35).astype(np.uint8)
 layer=overlay(overlay(vena,shadow),artery)
 layer[:,:,3]=np.rint(layer[:,:,3]*area).astype(np.uint8)
 result=overlay(art,layer)
 resource=ASSETS/'heart-open-cava-junction-v1.png';Image.fromarray(padding(result)).save(resource)
 Image.fromarray(layer).save(OUT/'joined-material.png');Image.fromarray(np.rint(area*255).astype(np.uint8)).save(OUT/'edit-weight.png')
 # Update the same per-lane depth contracts that gameplay cells and ambient
 # flow use, including the separated artery/vein crossing.
 front=H['frontPipeRings'];region=box(*EDIT).difference(Point(487,379).buffer(5))
 alpha_shape=display_shape(np.rint(area*255).astype(np.uint8))
 for system,ids in GROUPS.items():
  for i in ids:
   shown=visible[system].intersection(lanes[i]['shape']).intersection(alpha_shape)
   if system=='vein':shown=shown.difference(visible['artery'].buffer(.12))
   old=rings(front[f'e{i:03d}']).difference(region)
   front[f'e{i:03d}']=export_rings(old.union(shown).simplify(.035,preserve_topology=True))
 text=(OUT/'baseline-HeartVisualData.lua').read_text().replace(H['resource'],str(resource.relative_to(ROOT/'assets'))).replace('revision=12,','revision=13,')
 start=text.index('H.frontPipeRings=');stop=text.index('\nlocal function inside',start)
 text=text[:start]+'H.frontPipeRings='+lua(front)+text[stop:];(OUT/'HeartVisualData.lua').write_text(text)
 reg={'status':'STAGED','revision':13,'resource':str(resource.relative_to(ROOT/'assets')),'sha256':sha(resource),'sourceBox':BOX,'pixelSize':list(SIZE),'editBox':EDIT,'protectedRightAtrialMouth':[487,379,5],'groups':GROUPS,'veinCommonNode':'heart.v','arteryCommonNode':'lung_r.entry','redBlueCrossingIsJunction':False,'geometryUnchanged':True,'atlasPanels':1,'automaticArtSwitchByZoom':False,'nativeVisualEvidence':False,'approvedMaterials':materials,'generatedTissueSource':'assets/image/anatomy-reference/vascular-study/heart-simple-20261012/perimeter-v8/perimeter-clean-bed-raw-v1.png','imagegenPromptRecord':'docs/heart-simple-20261012/perimeter-v8/imagegen-prompts.txt','builderSha256':sha(__file__)}
 (OUT/'registration.json').write_text(json.dumps(reg,ensure_ascii=False,indent=2)+'\n')
 print(json.dumps({'revision':13,'resource':reg['resource'],'joinedGroups':GROUPS}))

if __name__=='__main__':main()
