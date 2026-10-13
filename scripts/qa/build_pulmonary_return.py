"""Expose one continuous pulmonary return on the unchanged production graph.

The accepted watercolor strip follows lanes 175 -> 8 -> left atrium. Their
shared node has one open material floor; projected aortic crossings are bridges,
never graph junctions. Stage the existing one-panel cardiac sprite only.
"""
from pathlib import Path
import sys,json,hashlib
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter,maximum_filter
from shapely.geometry import LineString,Point,box
from shapely.ops import unary_union,substring
from shapely.affinity import scale
from lupa.lua54 import LuaRuntime

sys.path.insert(0,str(Path(__file__).parent))
import build_fullbody_vascular_material as material
from build_heart_perimeter import mask
from register_simple_heart import overlay,padding,rings
from rebuild_heart_connections import register_image,BOX,SIZE
from register_heart_port_connections import sampler,uv_edge
from check_regional_vascular_refinement import convert
from prepare_heart_battlefield import lua,rings as export_rings

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'docs/heart-simple-20261012/pulmonary-return-v9'
ASSETS=ROOT/'assets/image/anatomy-reference/vascular-study/heart-simple-20261012/pulmonary-return-v9'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def write(p,obj):Path(p).write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n')
def smooth(v):v=np.clip(v,0,1);return v*v*(3-2*v)
def display_shape(alpha):
 g=material.raster_runs_geometry(alpha>=16,BOX,SIZE[0]/(BOX[2]-BOX[0]))
 g=scale(g,xfact=1,yfact=((BOX[3]-BOX[1])/SIZE[1])/((BOX[2]-BOX[0])/SIZE[0]),origin=(BOX[0],BOX[1]))
 return g.simplify(.04,preserve_topology=True)

def main():
 l=LuaRuntime(unpack_returned_tuples=True)
 l.globals().baseline=(OUT/'baseline-HeartVisualData.lua').read_text()
 l.execute("package.path='scripts/?.lua;'..package.path;package.loaded['war.HeartVisualData']=assert(load(baseline))();D=require('war.HeartBattlefieldData');H=require('war.HeartVisualData');A=require('war.FullBodyMapArtData');S=require('war.FullBodyBattlefield').new(72026);N=require('war.OrganBattlefield').net(S)")
 H=convert(l.globals().H);D=convert(l.globals().D);N=l.globals().N
 def edge(i):
  e=N.edges[i];pts=[(p[1]*.5,(p[2]-512)*.5)for _,p in e.points.items()]
  return {'points':pts,'width':e.width*.5,'a':N.nodes[e.a].id,'b':N.nodes[e.b].id,'line':LineString(pts)}
 lanes={i:edge(i)for i in [5,8,9,6,175]}
 assert lanes[175]['b']==lanes[8]['a']=='lung_l.exit'
 assert lanes[8]['b']==lanes[5]['b']=='left_heart'
 assert np.allclose(lanes[175]['points'][-1],lanes[8]['points'][0])
 physical={i:e['line'].buffer(e['width']/2,quad_segs=24)for i,e in lanes.items()}
 before=np.array(Image.open(ROOT/'assets'/H['resource']).convert('RGBA'))
 raw=register_image(ROOT/'assets/image/anatomy-reference/vascular-study/heart-simple-20261012/registered-v3/heart-watercolor-registered-v1.png',[468,326,568,467])
 # Remove the old isolated generated blue Y before registering the real inlet.
 # Restore its accepted chamber art, while preserving every red pipe pixel.
 mouth_cleanup=Point(542,374).buffer(14)
 peripheral=box(556,378,580,434)
 cleanup=mouth_cleanup.union(peripheral).union(rings(H['frontPipeRings']['e175']).buffer(.6))
 arteries=unary_union([physical[9],physical[6]])
 rgb=before[:,:,:3].astype(int)
 blue=(rgb[:,:,2]>rgb[:,:,0])&(rgb[:,:,2]>rgb[:,:,1]+8)&(before[:,:,3]>40)
 weight=gaussian_filter(maximum_filter(blue.astype(float),size=15),1.8)*mask(cleanup,BOX,SIZE)/255
 weight=np.maximum(weight,gaussian_filter(mask(mouth_cleanup.difference(arteries.buffer(.35)),BOX,SIZE)/255,1.5))
 # The lung floor itself contains an older blue approach. Cover its obsolete
 # exposed pieces inside this cardiac scope; leaving the sprite transparent
 # would make those detached pixels show through again.
 lung=next(s for s in convert(l.globals().A)['organs']if s['id']=='lung_l')
 under=register_image(ROOT/'assets'/lung['resource'],lung['sourceBox']);u=under[:,:,:3].astype(int)
 old_under=(u[:,:,2]>u[:,:,0])&(u[:,:,2]>u[:,:,1]+8)&(under[:,:,3]>40)&(before[:,:,3]<40)
 weight=np.maximum(weight,gaussian_filter(maximum_filter(old_under.astype(float),size=11),1.3)*mask(peripheral,BOX,SIZE)/255)
 # Only a few old peripheral blue pixels lie outside the heart silhouette.
 # Use the already generated vessel-free tissue bed there, not transparency
 # that would reveal the same obsolete vein in the lung image underneath.
 clean=register_image(ROOT/'assets/image/anatomy-reference/vascular-study/heart-simple-20261012/perimeter-v8/perimeter-clean-bed-raw-v1.png',[452,282,588,486])
 restoration=overlay(clean,raw)
 heart=before.copy()
 for k in range(4):heart[:,:,k]=np.rint(before[:,:,k]*(1-weight)+restoration[:,:,k]*weight).astype(np.uint8)
 # A single path owns longitudinal UV across the real lung exit, so the
 # thicker proximal vein cannot restart its phase at that named-node joint.
 origin=np.asarray(lanes[8]['points'][-1]);room=next(c for c in D['chambers']if c['id']=='left_atrium')
 room_shape=rings(room['rings']);center=np.asarray(room['centerSource'])
 inward=(center-origin)/np.linalg.norm(center-origin);end=origin+inward*7
 extension=LineString([origin,end]).buffer(lanes[8]['width']/2,cap_style=2,quad_segs=24).intersection(room_shape)
 shapes={175:physical[175],8:physical[8].union(extension)}
 union=unary_union(list(shapes.values()))
 manifest=json.loads((ROOT/'docs/body-life/vascular-art-study/fullbody-015/bake/manifest.json').read_text())
 bake=sampler(manifest['pipeMaterials']['materials'])
 # The core sprite has unequal X/Y texel scale: the sampler's alpha must use
 # the same exact affine registration as RGB and its runtime visibility rings.
 material.mask=mask
 # Restore the exact red material under old blue remnants at a projected
 # crossing before painting the continuous vein over it.
 for i in [6,9]:
  red=bake.pipe_material(physical[i],BOX,SIZE,'artery',lanes[i]['width'],uv_edge(lanes[i]['points']))
  red[:,:,3]=np.rint(red[:,:,3]*weight).astype(np.uint8)
  heart=overlay(heart,red)
 uv=uv_edge(lanes[175]['points']+lanes[8]['points'][1:]+[end.tolist()])
 yy,xx=np.mgrid[:SIZE[1],:SIZE[0]];sx=BOX[0]+(xx+.5)*.1;sy=BOX[1]+(yy+.5)*174/1692
 progress=(sx-origin[0])*inward[0]+(sy-origin[1])*inward[1]
 fade=smooth((7-progress)/4)
 coverage={};paint=np.zeros_like(heart)
 for i in [175,8]:
  raster=bake.pipe_material(union,BOX,SIZE,'vein',lanes[i]['width'],uv)
  cover=mask(shapes[i],BOX,SIZE)/255
  if i==8:cover*=np.where(mask(room_shape,BOX,SIZE)>0,fade,1)
  raster[:,:,3]=np.rint(cover*255).astype(np.uint8)
  coverage[i]=raster[:,:,3];paint=overlay(paint,raster)
 # A fine watercolor bridge shadow separates blue and red at their overlap.
 # It does not leave a white break in either blood route.
 crossing=union.intersection(arteries)
 shadow_scope=union.buffer(.30).difference(union).intersection(arteries.buffer(.30))
 shadow=np.zeros_like(heart);shadow[:,:,:3]=[99,74,105]
 shadow[:,:,3]=np.rint(mask(shadow_scope,BOX,SIZE)*.40).astype(np.uint8)
 result=overlay(overlay(heart,shadow),paint)
 resource=ASSETS/'heart-continuous-pulmonary-vein-v1.png'
 Image.fromarray(padding(result)).save(resource)
 Image.fromarray(paint).save(OUT/'continuous-vein.png')
 for i,alpha in coverage.items():Image.fromarray(alpha).save(OUT/f'lane-{i}-coverage.png')
 Image.fromarray(np.rint(weight*255).astype(np.uint8)).save(OUT/'old-mouth-cleanup-mask.png')
 Image.fromarray(result).save(OUT/'cardiac-after.png')
 # The same ownership contract hides aortic cells under the blue crossing,
 # while exposing pulmonary-return cells throughout the corrected inlet.
 front=H['frontPipeRings']
 front['e005']=[] # The other lung return remains behind the cardiac roof.
 for i in [8,175]:front[f'e{i:03d}']=export_rings(display_shape(coverage[i]))
 bridge=display_shape(paint[:,:,3]).buffer(.12)
 for i in [6,9]:front[f'e{i:03d}']=export_rings(rings(front[f'e{i:03d}']).difference(bridge))
 text=(OUT/'baseline-HeartVisualData.lua').read_text()
 text=text.replace(H['resource'],str(resource.relative_to(ROOT/'assets'))).replace('revision=11,','revision=12,')
 start=text.index('H.frontPipeRings=');stop=text.index('\nlocal function inside',start)
 text=text[:start]+'H.frontPipeRings='+lua(front)+text[stop:]
 (OUT/'HeartVisualData.lua').write_text(text)
 scope=cleanup.buffer(.65).union(union.buffer(.35)).intersection(box(*BOX))
 write(OUT/'registration.json',{'status':'STAGED','resource':str(resource.relative_to(ROOT/'assets')),'sha256':sha(resource),'sourceBox':BOX,'pixelSize':list(SIZE),'revision':12,'atlasPanels':1,'geometryUnchanged':True,'perspectiveUnchanged':True,'detailsMinZoom':None,'continuousVisibleLanes':[175,8],'trueJoint':'lung_l.exit','atriumNode':'left_heart','atriumLane':205,'otherLungReturnBehindRoof':True,'obsoleteLungFloorFragmentsCovered':True,'crossingIsGraphJunction':False,'bridgeRings':export_rings(crossing),'editScope':export_rings(scope),'materials':manifest['pipeMaterials']['materials'],'generatedTissueSource':'assets/image/anatomy-reference/vascular-study/heart-simple-20261012/perimeter-v8/perimeter-clean-bed-raw-v1.png','imagegenPromptRecord':'docs/heart-simple-20261012/perimeter-v8/imagegen-prompts.txt','nativeVisualEvidence':False,'builderSha256':sha(__file__)})
 print(json.dumps({'resource':str(resource.relative_to(ROOT/'assets')),'continuousLanes':[175,8],'revision':12}))

if __name__=='__main__':main()
