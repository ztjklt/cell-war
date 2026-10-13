"""One complete registered artery and one caval trunk in a single heart image."""
from pathlib import Path
import sys,json,hashlib
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter
from shapely.geometry import LineString,Point,box
from shapely.ops import unary_union
from shapely.affinity import scale
from lupa.lua54 import LuaRuntime
sys.path.insert(0,str(Path(__file__).parent))
from prepare_heart_battlefield import lua,rings as export_rings
from register_simple_heart import overlay,padding,rings
from register_heart_port_connections import sampler,uv_edge
from build_heart_perimeter import mask
import build_fullbody_vascular_material as material
from check_regional_vascular_refinement import convert

ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'docs/heart-simple-20261012/left-vessels-v11'
ASSETS=ROOT/'assets/image/anatomy-reference/vascular-study/heart-simple-20261012/left-vessels-v11'
BOX=[432,306,580,480];SIZE=(1480,1692);CORE=[460,306,580,480];EDIT=[432,314,514,420]
IDS=[1,3,15,17,22,67,72,172,211]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def smooth(t):t=np.clip(t,0,1);return t*t*(3-2*t)
def register(path,bounds,size=SIZE,target=BOX):
 im=Image.open(path).convert('RGBA');x,y,xx,yy=bounds;dx=(target[2]-target[0])/size[0];dy=(target[3]-target[1])/size[1]
 return np.array(im.transform(size,Image.Transform.AFFINE,(dx*im.width/(xx-x),0,(target[0]-x)*im.width/(xx-x),0,dy*im.height/(yy-y), (target[1]-y)*im.height/(yy-y)),resample=Image.Resampling.BILINEAR))
def contour(alpha,bounds=BOX,size=SIZE):
 g=material.raster_runs_geometry(alpha>=16,bounds,size[0]/(bounds[2]-bounds[0]))
 g=scale(g,xfact=1,yfact=((bounds[3]-bounds[1])/size[1])/((bounds[2]-bounds[0])/size[0]),origin=(bounds[0],bounds[1]))
 return g.simplify(.045,preserve_topology=True)

def main():
 l=LuaRuntime(unpack_returned_tuples=True);l.globals().src=(OUT/'baseline-HeartVisualData.lua').read_text()
 l.execute("package.path='scripts/?.lua;'..package.path;package.loaded['war.HeartVisualData']=assert(load(src))();H=require('war.HeartVisualData');S=require('war.FullBodyBattlefield').new(91);O=require('war.OrganBattlefield');A=require('war.FullBodyMapArt');N=O.net(S)")
 H=convert(l.globals().H);oldN=l.globals().N
 oldData=json.loads((OUT/'baseline-runtime-data.json').read_text());d=json.loads((OUT/'runtime-data.json').read_text())
 domains={int(i):rings(g)for i,g in d['rawBloodDomains'].items()};oldDomains={int(i):rings(g)for i,g in oldData['rawBloodDomains'].items()}
 source=json.loads((ROOT/'docs/body-life/vascular-art-study/final-reference-data.json').read_text())['edges']
 def spec(i,data=d):
  if i>202:return next(e for e in data['edgeAdditions']if e['laneIndex']==i)
  return data['edgeUpdates'].get(str(i),{'a':source[i-1]['a'],'b':source[i-1]['b'],'points':source[i-1]['samples'],'widthSource':source[i-1]['lumenWidthSource']})
 for i in IDS:
  if i not in domains:domains[i]=LineString(spec(i)['points']).buffer(spec(i)['widthSource']/2,quad_segs=24)
  if i!=211 and i not in oldDomains:oldDomains[i]=LineString(spec(i,oldData)['points']).buffer(spec(i,oldData)['widthSource']/2,quad_segs=24)
 full=np.array(Image.open(OUT/'baseline-expanded-map.png').convert('RGBA'))
 original=Image.open(ROOT/'assets'/H['resource']).convert('RGBA');before=full.copy();before[:,280:]=np.array(original)
 clean=np.array(Image.open(ASSETS/'left-vessel-clean-bed-raw-v1.png').convert('RGBA').resize(SIZE,Image.Resampling.LANCZOS))
 yy,xx=np.mgrid[:SIZE[1],:SIZE[0]];sx=432+(xx+.5)*.1;sy=306+(yy+.5)*174/1692
 area=smooth((sx-EDIT[0])/2)*smooth((EDIT[2]-sx)/2)*smooth((sy-EDIT[1])/2)*smooth((EDIT[3]-sy)/2)
 portal=smooth((np.hypot(sx-487,sy-379)-5.5)/2)
 root=smooth((np.hypot(sx-507,sy-346)-3.5)/2)
 area*=portal*root
 region=box(*EDIT).difference(Point(487,379).buffer(5.5)).difference(Point(507,346).buffer(3.5))
 # Replace complete old/new corridor footprints, rather than merely masking
 # blue pixels: that is what eliminates stepped banks and isolated cap scraps.
 cleanup_scope=unary_union([oldDomains[i].buffer(3.5)for i in IDS if i!=211]+[domains[i].buffer(2.3)for i in IDS]).intersection(region)
 heart=register(ROOT/'assets/image/anatomy-reference/vascular-study/heart-simple-20261012/registered-v3/heart-watercolor-registered-v1.png',[468,326,568,467])
 heart_alpha=heart[:,:,3]/255
 cleanup=area*np.maximum(1-heart_alpha,gaussian_filter(mask(cleanup_scope,BOX,SIZE)/255,2))
 # Unchanged cardiac shafts are distinct depth paths, except at the common
 # pulmonary root that the protected circle already preserves.
 protected_ids=[2,4,6,9,150]
 protected_shapes=[]
 for i in protected_ids:
  g=domains.get(i,LineString(spec(i)['points']).buffer(spec(i)['widthSource']/2,quad_segs=24))
  protected_shapes.append(g.buffer(.3))
 protected=unary_union(protected_shapes)
 cleanup*=1-mask(protected,BOX,SIZE)/255
 fgInfo=json.loads((ROOT/'docs/body-life/vascular-art-study/fullbody-015/bake/manifest.json').read_text())['actualArtForeground']
 fg=register(ROOT/fgInfo['path'],fgInfo['sourceBox'])[:,:,0]/255
 cleanup*=np.where(sx<453,1-fg,1)
 art=before.copy()
 for k in range(4):art[:,:,k]=np.rint(before[:,:,k]*(1-cleanup)+clean[:,:,k]*cleanup).astype(np.uint8)
 manifest=json.loads((ROOT/'docs/body-life/vascular-art-study/fullbody-015/bake/manifest.json').read_text());bake=sampler(manifest['pipeMaterials']['materials']);material.mask=mask
 blue=unary_union([domains[i]for i in [1,15,17,22,67,72,211]])
 red=domains[3].union(domains[172])
 # Precise whole-path boundary and longitudinal UV; no clipped union from
 # previous texture alpha, no per-fragment end caps or angle patches.
 vein=bake.pipe_material(blue,BOX,SIZE,'vein',3,uv_edge(spec(22)['points']+spec(211)['points'][1:]))
 artery=bake.pipe_material(red,BOX,SIZE,'artery',2,uv_edge(spec(3)['points']+spec(172)['points'][1:]))
 # The lower cava continues behind the existing heart wall. Use that real
 # silhouette to hide it smoothly; never cut its material at the edit box.
 vein[:,:,3]=np.rint(vein[:,:,3]*area*(1-heart_alpha*smooth((sy-390)/4))).astype(np.uint8)
 artery[:,:,3]=np.rint(artery[:,:,3]*area*np.where(sx<453,1-fg,1)).astype(np.uint8)
 shadow=np.zeros_like(art);shadow[:,:,:3]=[104,68,95]
 shadow_shape=red.buffer(.24).difference(red).intersection(blue)
 shadow[:,:,3]=np.rint(mask(shadow_shape,BOX,SIZE)*area*.32).astype(np.uint8)
 result=overlay(overlay(overlay(art,vein),shadow),artery)
 resource=ASSETS/'heart-smooth-left-vessels-v1.png';Image.fromarray(padding(result)).save(resource)
 for name,pixels in [('complete-vein.png',vein),('complete-artery.png',artery),('cardiac-after.png',result),('background-cleanup-weight.png',np.rint(cleanup*255).astype(np.uint8))]:Image.fromarray(pixels).save(OUT/name)
 # The old seam image is still one reused slot. It cannot overpaint the new
 # complete tube where the cleanup/new floor has taken ownership.
 pb=H['perimeter']['sourceBox'];ps=tuple(H['perimeter']['pixelSize']);patch=np.array(Image.open(ROOT/'assets'/H['perimeter']['resource']).convert('RGBA'))
 own=np.maximum(cleanup,np.maximum(vein[:,:,3],artery[:,:,3])/255)
 Image.fromarray(np.rint(own*255).astype(np.uint8)).save(OUT/'ownership.png')
 registered_own=register(OUT/'ownership.png',BOX,size=ps,target=pb)[:,:,0]/255
 patch[:,:,3]=np.rint(patch[:,:,3]*(1-registered_own)).astype(np.uint8)
 patch_resource=ASSETS/'heart-perimeter-banks-v11.png';Image.fromarray(padding(patch)).save(patch_resource)
 front=H['frontPipeRings'];alpha_shapes={'vein':contour(vein[:,:,3]),'artery':contour(artery[:,:,3])};redFront=alpha_shapes['artery']
 # Preserve old visibility outside the authored corridor. Existing foreign
 # organ crossings in the added left margin retain their original contract.
 for i in IDS:
  system='artery'if i in [3,172]else'vein';old=rings(front.get(f'e{i:03d}',[])).difference(region)
  if i!=211:
   e=oldN.edges[i];points=[(p[1]*.5,(p[2]-512)*.5)for _,p in e.points.items()]
   pieces=[]
   for a,b in zip(points,points[1:]):
    mid=((a[0]+b[0])/2,(a[1]+b[1])/2)
    if 432<=mid[0]<460 and 306<=mid[1]<=480:
     visible=l.globals().A.unitDepth(l.globals().S,l.table_from({'vesselLane':i}),mid[0]*2,mid[1]*2+512)!='under-foreground'
     if visible:pieces.append(LineString([a,b]).buffer(e.width*.25,quad_segs=8))
   if pieces:old=old.union(unary_union(pieces).difference(region))
  shown=alpha_shapes[system].intersection(domains[i])
  if system=='vein':shown=shown.difference(redFront.buffer(.12))
  front[f'e{i:03d}']=export_rings(old.union(shown).simplify(.045,preserve_topology=True))
 front['heart.vessel.superior_cava']=front['e211']
 text=(OUT/'baseline-HeartVisualData.lua').read_text()
 text=text.replace(H['resource'],str(resource.relative_to(ROOT/'assets'))).replace('sourceBox={460,306,580,480},pixelSize={1200,1692},revision=13,','sourceBox={432,306,580,480},pixelSize={1480,1692},revision=14,')
 text=text.replace('replacementRings={{outer={{460,306},{580,306},{580,480},{460,480}},holes={}}}', 'replacementRings={{outer={{432,306},{580,306},{580,480},{432,480}},holes={}}}')
 text=text.replace('for _,spec in ipairs(Data.edgeAdditions)do\n H.localFloorEdges[spec.id]=true;H.localFloorEdges[string.format(\'e%03d\',spec.laneIndex)]=true\nend',"for _,spec in ipairs(Data.edgeAdditions)do\n if spec.system=='chamber'or spec.system=='valve'then H.localFloorEdges[spec.id]=true;H.localFloorEdges[string.format('e%03d',spec.laneIndex)]=true end\nend")
 start=text.index('H.frontPipeRings=');end=text.index('\nlocal function inside',start);text=text[:start]+'H.frontPipeRings='+lua(front)+text[end:]
 helper="""H.previousCoreBox={460,306,580,480}
H.editedEdges={e003=true,e017=true,e022=true,e067=true,e072=true,e172=true,e211=true,['heart.vessel.superior_cava']=true}
local function ownsVisibility(edge,sx,sy)
 local b=H.sourceBox
 if sx<b[1]or sx>b[3]or sy<b[2]or sy>b[4]then return false end
 return sx>=H.previousCoreBox[1]or H.editedEdges[edge.name]==true
end
"""
 text=text.replace('function H.unitBehindHeart',helper+'function H.unitBehindHeart')
 text=text.replace(' if sx<b[1]or sx>b[3]or sy<b[2]or sy>b[4]then return false end\n if H.localFloorEdges',' if not ownsVisibility(edge,sx,sy)then return false end\n if H.localFloorEdges')
 text=text.replace(' return sx>=b[1]and sx<=b[3]and sy>=b[2]and sy<=b[4]',' return ownsVisibility(edge,sx,sy)')
 text=text.replace(H['perimeter']['resource'],str(patch_resource.relative_to(ROOT/'assets')))
 (OUT/'HeartVisualData.lua').write_text(text)
 reg={'status':'STAGED','revision':14,'layoutRevision':4,'resource':str(resource.relative_to(ROOT/'assets')),'sha256':sha(resource),'sourceBox':BOX,'pixelSize':list(SIZE),'editBox':EDIT,'atlasPanels':1,'scopeSource':'one expanded heart image; old left blood removed before whole-path painting','newSuperiorCavaLane':211,'redPathLanes':[3,172],'bloodPixelsOwnedOnce':True,'perimeterResource':str(patch_resource.relative_to(ROOT/'assets')),'perimeterSha256':sha(patch_resource),'generatedCleanupAsset':str((ASSETS/'left-vessel-clean-bed-raw-v1.png').relative_to(ROOT)),'imagegenPromptRecord':str((OUT/'imagegen-prompts.txt').relative_to(ROOT)),'nativeVisualEvidence':False,'approvedMaterials':manifest['pipeMaterials']['materials'],'builderSha256':sha(__file__)}
 (OUT/'registration.json').write_text(json.dumps(reg,ensure_ascii=False,indent=2)+'\n');print(json.dumps({'resource':reg['resource'],'oneSuperiorCava':True,'oneTaperedArtery':True,'corePanels':1}))

if __name__=='__main__':main()
