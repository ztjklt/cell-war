"""Repair cardiac texture seams with generated tissue and registered vessel UVs.

Reuses the fully occluded old heart venous patch slot. The vessel graph, chamber
art, perspective switch and every remote organ remain fixed.
"""
from pathlib import Path
import sys,json,hashlib
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter
from shapely.geometry import Polygon,LineString,box,Point
from shapely.ops import unary_union
from lupa.lua54 import LuaRuntime
from io import BytesIO
import cairosvg

sys.path.insert(0,str(Path(__file__).parent))
from register_simple_heart import overlay,padding,rings
from rebuild_heart_connections import register_image
from build_fullbody_vascular_material import mask as legacy_mask,geometry_path
from register_heart_port_connections import sampler,uv_edge
from check_regional_vascular_refinement import convert
from prepare_heart_battlefield import lua

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'docs/heart-simple-20261012/perimeter-v8'
ASSETS=ROOT/'assets/image/anatomy-reference/vascular-study/heart-simple-20261012/perimeter-v8'
BOX=[452,282,588,486];SIZE=(1360,2040)
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def smooth(v):v=np.clip(v,0,1);return v*v*(3-2*v)
def mask(shape,bounds,size):
 # The cardiac sprite has different X/Y texel scales. SVG's default "meet"
 # mode silently recenters the mask, leaving the intended blue fragment.
 shape=shape.intersection(box(*bounds))
 if shape.is_empty:return np.zeros((size[1],size[0]),np.uint8)
 x,y,xx,yy=bounds
 svg=f'<svg xmlns="http://www.w3.org/2000/svg" width="{size[0]}" height="{size[1]}" viewBox="{x} {y} {xx-x} {yy-y}" preserveAspectRatio="none"><path d="{geometry_path(shape)}" fill="white" fill-rule="evenodd"/></svg>'
 return np.array(Image.open(BytesIO(cairosvg.svg2png(bytestring=svg.encode()))).convert('RGBA'))[:,:,3]

def main():
 l=LuaRuntime(unpack_returned_tuples=True)
 l.execute("package.path='scripts/?.lua;'..package.path;D=require('war.HeartBattlefieldData');H=require('war.HeartVisualData');A=require('war.FullBodyMapArtData');S=require('war.FullBodyBattlefield').new(72026);N=require('war.OrganBattlefield').net(S)")
 H=convert(l.globals().H);specs=convert(l.globals().A);net=l.globals().N
 before=np.array(Image.open(ROOT/'assets'/H['resource']).convert('RGBA'))
 raw=register_image(ROOT/'assets/image/anatomy-reference/vascular-study/heart-simple-20261012/registered-v3/heart-watercolor-registered-v1.png',[468,326,568,467])
 # This connected posterior vein is correctly hidden by the heart. Its tiny
 # exposed component was a visibility defect, never an extra lumen to erase.
 fragments=[]
 for edge in ['e008','e175']:
  removed=[r for r in H['frontPipeRings'][edge]if min(p[1]for p in r['outer'])>378 and max(p[0]for p in r['outer'])<566]
  fragments+=removed
  H['frontPipeRings'][edge]=[r for r in H['frontPipeRings'][edge]if r not in removed]
 assert fragments
 removal=rings(fragments).buffer(.28)
 cut=mask(removal,H['sourceBox'],(before.shape[1],before.shape[0]))/255
 cut=gaussian_filter(cut,1)
 heart=before.copy()
 for k in range(4):heart[:,:,k]=np.rint(before[:,:,k]*(1-cut)+raw[:,:,k]*cut).astype(np.uint8)
 resource=ASSETS/'heart-internal-map-v2.png';Image.fromarray(padding(heart)).save(resource)
 Image.fromarray(heart).save(OUT/'heart-without-posterior-sliver.png')
 # The editable tissue bed comes from imagegen. Geometry supplies the same
 # actual vessel centerlines and the approved three watercolor strip sources.
 clean=np.array(Image.open(ASSETS/'perimeter-clean-bed-raw-v1.png').convert('RGBA').resize(SIZE,Image.Resampling.LANCZOS))
 manifest=json.loads((ROOT/'docs/body-life/vascular-art-study/fullbody-015/bake/manifest.json').read_text())
 bake=sampler(manifest['pipeMaterials']['materials'])
 yy,xx=np.mgrid[:SIZE[1],:SIZE[0]];sx=BOX[0]+(xx+.5)/10;sy=BOX[1]+(yy+.5)/10
 upper=smooth((sy-282)/7)*smooth((328-sy)/8)*smooth((sx-454)/6)*smooth((586-sx)/6)
 lower=smooth(1-np.abs(sy-480)/5.7)*np.maximum(smooth((sx-465)/5)*smooth((496-sx)/5),smooth((sx-515)/5)*smooth((545-sx)/5))
 band=np.maximum(upper,lower)
 zone=box(454,282,586,328).union(box(465,473,545,486))
 lanes={}
 for lane,e in net.edges.items():
  if lane>202 or e.hidden or e.system not in ['artery','vein']:continue
  pts=[(p[1]*.5,(p[2]-512)*.5)for _,p in e.points.items()]
  shape=LineString(pts).buffer(e.width*.25,quad_segs=24)
  if not shape.intersects(zone):continue
  lanes[lane]={'a':net.nodes[e.a].id,'b':net.nodes[e.b].id,'points':pts,'system':e.system,'width':e.width*.5,'shape':shape}
 def priority(lane):
  if lane==9:return 90
  if lane==15:return 85
  return 75 if lane in [151,153,156,158]else 70 if lanes[lane]['system']=='artery'else 50
 pipes=np.zeros_like(clean)
 for lane in sorted(lanes,key=lambda k:(priority(k),k)):
  e=lanes[lane];shape=e['shape'];uvshape=shape
  for node,point in [(e['a'],e['points'][0]),(e['b'],e['points'][-1])]:
   joint=unary_union([q['shape']for q in lanes.values()if node in[q['a'],q['b']]])
   uvshape=uvshape.union(joint.intersection(Point(point).buffer(max(e['width'],7)*2)))
  raster=bake.pipe_material(uvshape,BOX,SIZE,e['system'],e['width'],uv_edge(e['points']))
  coverage=mask(shape,BOX,SIZE)/255
  for other,q in lanes.items():
   if(priority(other),other)<=(priority(lane),lane)or {e['a'],e['b']}&{q['a'],q['b']}:continue
   coverage*=1-mask(q['shape'].buffer(.16),BOX,SIZE)/255
  raster[:,:,3]=np.rint(raster[:,:,3]*coverage).astype(np.uint8)
  pipes=overlay(pipes,raster)
 # Preserve neighboring organ floors except within the actual blood footprint.
 organ=np.zeros(band.shape)
 for spec in specs['organs']:
  if spec['id']=='heart':continue
  im=Image.open(ROOT/'assets'/spec['resource']).convert('RGBA');b=spec['sourceBox']
  reg=np.array(im.transform(SIZE,Image.Transform.AFFINE,(.1*im.width/(b[2]-b[0]),0,(BOX[0]-b[0])*im.width/(b[2]-b[0]),0,.1*im.height/(b[3]-b[1]),(BOX[1]-b[1])*im.height/(b[3]-b[1])),resample=Image.Resampling.BILINEAR))
  organ=np.maximum(organ,reg[:,:,3]/255)
 blood_scope=mask(unary_union([e['shape'].buffer(2.3)for e in lanes.values()]),BOX,SIZE)/255
 band*=np.maximum(1-organ,blood_scope)
 patch=overlay(clean,pipes);patch[:,:,3]=np.rint(band*255).astype(np.uint8)
 patch_resource=ASSETS/'heart-perimeter-banks-v1.png';Image.fromarray(padding(patch)).save(patch_resource)
 Image.fromarray(patch).save(OUT/'perimeter-patch.png')
 Image.fromarray(pipes).save(OUT/'perimeter-registered-vessels.png')
 text=(OUT/'baseline-HeartVisualData.lua').read_text()
 text=text.replace(H['resource'],str(resource.relative_to(ROOT/'assets'))).replace('revision=10,','revision=11,')
 start=text.index('H.frontPipeRings=');end=text.index('\nlocal function inside',start)
 text=text[:start]+'H.frontPipeRings='+lua(H['frontPipeRings'])+text[end:]
 extra="""-- Reuse the old, fully hidden venous patch slot for seam restoration.
H.perimeter={id='heart-venous-junction',resource='%s',sourceBox={452,282,588,486},pixelSize={1360,2040},perimeter=true}
function H.replacePatch(spec)
 if spec.id~=H.perimeter.id then return spec end
 local out={};for k,v in pairs(spec)do out[k]=v end
 for k,v in pairs(H.perimeter)do out[k]=v end
 out.coreBox=nil;return out
end
"""%str(patch_resource.relative_to(ROOT/'assets'))
 text=text.replace('return H\n',extra+'return H\n')
 (OUT/'HeartVisualData.lua').write_text(text)
 report={'status':'STAGED','geometryUnchanged':True,'detailsMinZoom':None,'perspectiveUnchanged':True,'heartResource':str(resource.relative_to(ROOT/'assets')),'heartSha256':sha(resource),'perimeterResource':str(patch_resource.relative_to(ROOT/'assets')),'perimeterSha256':sha(patch_resource),'sourceBox':BOX,'pixelSize':list(SIZE),'reusedPatchId':'heart-venous-junction','removedPosteriorComponentRings':fragments,'seamSourceY':[306,480],'lanes':sorted(lanes),'generatorIntegration':'tissue background only; vascular color is UV sampled on actual unchanged geometry','generatedSources':[str((ASSETS/n).relative_to(ROOT))for n in ['perimeter-polish-raw-v1.png','perimeter-clean-bed-raw-v1.png']],'nativeVisualEvidence':False,'builderSha256':sha(__file__)}
 (OUT/'registration.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps({'resource':report['heartResource'],'patch':report['perimeterResource'],'lanes':report['lanes']}))

if __name__=='__main__':main()
