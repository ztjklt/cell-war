"""Replace intestinal tube pixels, not organ-background rectangles.

Generated tissue is registered only into former tube footprints. The original
organ alpha/cream corridors stay fixed. One transparent network atlas is baked
from the same remodeled routes and raw membrane domains used by movement.
"""
from pathlib import Path
import sys,json,hashlib
import numpy as np
from PIL import Image
from scipy.spatial import cKDTree
from scipy.ndimage import gaussian_filter,distance_transform_edt
from shapely.geometry import LineString,Point,box
from shapely.ops import unary_union
from lupa.lua54 import LuaRuntime
sys.path.insert(0,str(Path(__file__).parent))
from prepare_bowel_remodel import OUT,CHANGED,OWNED,ROOT,write,sha
from prepare_heart_battlefield import lua,rings as export_rings
from register_simple_heart import overlay,padding,rings
from register_heart_port_connections import sampler,uv_edge
from build_left_vessels import register,contour
from build_heart_perimeter import mask
from check_regional_vascular_refinement import convert
import build_fullbody_vascular_material as material

ASSETS=ROOT/'assets/image/anatomy-reference/vascular-study/bowel-remodel-20261013'
BOX=[440,603,600,731];SIZE=(1600,1280)
def uv_edges(edges):
    pieces=[uv_edge(e['points'])for e in edges]
    uv={k:np.concatenate([p[k]for p in pieces])for k in ['uvStarts','uvVectors','uvLengths','uvArcStarts']}
    uv.update(uvTree=cKDTree(uv['uvStarts']+uv['uvVectors']*.5),pipePhaseSource=0,pipeArcUVScale=1,flatUnionFloor=True)
    return uv
def tissue_register(original,raw):
    # Normalize to the original silhouette bounding box; nearest generated
    # tissue supplies pigment only where an old tube covered pink tissue.
    a=np.array(original);b=np.array(raw)
    def bbox(im):
        yy,xx=np.nonzero(im[:,:,3]>128);return [int(xx.min()),int(yy.min()),int(xx.max()+1),int(yy.max()+1)]
    ba,bb=bbox(a),bbox(b);h,w=a.shape[:2]
    kx=(bb[2]-bb[0])/(ba[2]-ba[0]);ky=(bb[3]-bb[1])/(ba[3]-ba[1])
    registered=np.array(raw.transform((w,h),Image.Transform.AFFINE,(kx,0,bb[0]-ba[0]*kx,0,ky,bb[1]-ba[1]*ky),resample=Image.Resampling.BILINEAR))
    rgb=registered[:,:,:3].astype(np.int16)
    tissue=(registered[:,:,3]>220)&(rgb[:,:,0]-rgb[:,:,1]>25)&(rgb[:,:,0]-rgb[:,:,2]>35)
    indices=distance_transform_edt(~tissue,return_distances=False,return_indices=True)
    return registered[indices[0],indices[1]],{'originalAlphaBounds':ba,'generatedAlphaBounds':bb,'affine':[kx,ky]}
def main():
    ASSETS.mkdir(parents=True,exist_ok=True)
    d=json.loads((OUT/'runtime-data.json').read_text());network=json.loads((OUT/'network.json').read_text())
    old=json.loads((ROOT/'docs/vascular-map-audit-20261013/runtime-network.json').read_text())
    edges={e['lane']:e for e in network};previous={e['lane']:e for e in old}
    shapes={i:LineString(e['points']).buffer(e['widthSource']/2,quad_segs=24)for i,e in edges.items()}
    for i,raw in d['rawBloodDomains'].items():shapes[int(i)]=rings(raw)
    oldshapes={i:LineString(e['points']).buffer(e['widthSource']/2,quad_segs=24)for i,e in previous.items()}
    own=unary_union([oldshapes[i].buffer(.55)for i in OWNED]+[shapes[i].buffer(.55)for i in OWNED])
    foreign={i:g for i,g in shapes.items()if i not in OWNED and g.intersects(own)and i<=202}
    protected=unary_union(list(foreign.values()))
    cleanup=own.difference(protected.buffer(.16))
    l=LuaRuntime(unpack_returned_tuples=True);l.execute("package.path='scripts/?.lua;'..package.path;A=require('war.FullBodyMapArtData')")
    a=convert(l.globals().A);replacements={};changes=[]
    manifest=json.loads((ROOT/'docs/body-life/vascular-art-study/fullbody-015/bake/manifest.json').read_text())
    fg=manifest['actualArtForeground']
    # Whole existing foreground stencil, sampled in the same source frame.
    foreground=register(ROOT/fg['path'],fg['sourceBox'],size=SIZE,target=BOX)[:,:,0]/255
    food_by_organ={}
    for oid in ['small_intestine','large_intestine']:
        organ=json.loads((ROOT/f'docs/body-life/vascular-art-study/organ-atlas/geometry/{oid}.json').read_text())
        food_by_organ[oid]=rings(organ['foodAirUrineRings'])
    for layer in ['surfaceTiles','deepTiles','organs']:
        for spec in a[layer]:
            if not box(*spec['sourceBox']).intersects(cleanup):continue
            if layer=='organs'and spec['id']not in food_by_organ:continue
            path=ROOT/'assets'/spec['resource'];im=Image.open(path).convert('RGBA');before=np.array(im);result=before.copy()
            b=spec['sourceBox'];size=im.size;weight=mask(cleanup,b,size)/255
            if layer=='organs':
                oid=spec['id'];raw=Image.open(ASSETS/('small-vessel-free-raw.png'if oid=='small_intestine'else'large-vessel-free-raw.png')).convert('RGBA')
                tissue,reg=tissue_register(im,raw)
                # Exact existing cream passage pixels are protected. Only
                # actual older tube footprints receive generated tissue.
                food=mask(food_by_organ[oid],b,size)/255
                rgb=before[:,:,:3].astype(np.int16)
                cream=(rgb[:,:,0]>175)&(rgb[:,:,1]>155)&(rgb[:,:,0]-rgb[:,:,2]>12)&(rgb[:,:,0]-rgb[:,:,1]<48)
                weight=gaussian_filter(weight,1)*(1-food*cream)
                result[:,:,:3]=np.rint(before[:,:,:3]*(1-weight[:,:,None])+tissue[:,:,:3]*weight[:,:,None]).clip(0,255).astype(np.uint8)
                assert np.array_equal(result[:,:,3],before[:,:,3])
                write(OUT/f'{oid}-registration.json',reg)
            else:result[:,:,3]=np.rint(result[:,:,3]*(1-weight)).astype(np.uint8)
            p=ASSETS/(spec['id']+'.png');Image.fromarray(padding(result)).save(p)
            replacements[spec['id']]=spec|{'resource':str(p.relative_to(ROOT/'assets'))}
            changes.append({'id':spec['id'],'layer':layer,'modifiedPixels':int(np.any(result!=before,axis=2).sum()),'alphaUnchanged':layer=='organs','sha256':sha(p)})
    bake=sampler(manifest['pipeMaterials']['materials']);material.mask=mask
    # Each real named connection is sampled as a complete lumen, so ends
    # between the supply/exchange/return pieces cannot acquire a transverse cap.
    gates=d['gateContracts']['siege'];bylane={}
    for gate in gates:bylane.setdefault(gate['laneIndex'],[]).append(gate)
    pipes=np.zeros((SIZE[1],SIZE[0],4),np.uint8);front={};priority={'capillary':20,'vein':30,'artery':40}
    for i in sorted(OWNED,key=lambda i:(priority[edges[i]['system']],i)):
        e=edges[i];shape=shapes[i];uvshape=shape
        for node,point in [(e['a'],e['points'][0]),(e['b'],e['points'][-1])]:
            incident=unary_union([shapes[j]for j,q in edges.items()if node in[q['a'],q['b']]])
            uvshape=uvshape.union(incident.intersection(Point(point).buffer(8)))
        for gate in bylane.get(i,[]):uvshape=uvshape.union(rings(gate['rawThroatRings']))
        raster=bake.pipe_material(uvshape,BOX,SIZE,e['system'],e['widthSource'],uv_edge(e['points']))
        coverage=mask(shape,BOX,SIZE)/255
        # Unrelated crossed blood lanes have an explicit over/under ordering.
        # Major systemic conduits keep their uninterrupted foreground bank.
        blockers=[]
        for j,q in edges.items():
            if j==i or j>202 or {e['a'],e['b']}&{q['a'],q['b']}:continue
            if j in foreign or(j in OWNED and (priority[q['system']],j)>(priority[e['system']],i)):
                blockers.append(shapes[j].buffer(.12))
        if blockers:coverage*=1-mask(unary_union(blockers),BOX,SIZE)/255
        coverage*=1-foreground
        # The side-bank opening is the exact physical throat, shared by both
        # cell sizes. Its tissue end fades into the retained organ floor.
        for gate in bylane.get(i,[]):
            g=rings(gate['rawThroatRings']);opening=mask(g,BOX,SIZE)/255
            ax,ay=gate['pipeAnchorSource'];bx,by=gate['tissueAnchorSource'];v=np.array([bx-ax,by-ay]);length=np.linalg.norm(v);v/=length
            yy,xx=np.mgrid[:SIZE[1],:SIZE[0]];sx=BOX[0]+(xx+.5)*.1;sy=BOX[1]+(yy+.5)*.1
            progress=(sx-ax)*v[0]+(sy-ay)*v[1]
            fade=np.clip((length+1.1-progress)/1.8,0,1)
            coverage=np.maximum(coverage,opening*fade*(1-foreground))
        raster[:,:,3]=np.rint(raster[:,:,3]*coverage).astype(np.uint8)
        pipes=overlay(pipes,raster)
        front[i]=export_rings(contour(raster[:,:,3],bounds=BOX,size=SIZE))
    atlas=ASSETS/'bowel-blood-from-routes.png';Image.fromarray(padding(pipes)).save(atlas)
    # Reuse the two obsolete gut patch slots; neither carries a background.
    original=next(s for s in a['foregroundPatches']if s['id']=='small-gut-open-mouths')
    replacements[original['id']]={'id':original['id'],'resource':str(atlas.relative_to(ROOT/'assets')),'sourceBox':BOX,'pixelSize':list(SIZE)}
    empty=ASSETS/'retired-gut-patch.png';Image.new('RGBA',(1,1)).save(empty)
    original=next(s for s in a['foregroundPatches']if s['id']=='large-gut-open-mouths')
    replacements[original['id']]=original|{'resource':str(empty.relative_to(ROOT/'assets')),'pixelSize':[1,1],'opacity':0}
    visual={'schema':'bowel-registered-route-art/v1','layoutRevision':1,'sourceBox':BOX,'replacements':replacements,
            'ownedLanes':d['ownedLanes'],'frontPipeRings':front,'mouthGateIds':[g['id']for g in gates]}
    (OUT/'BowelVisualData.lua').write_text('-- Registered tube-only art and matching cell visibility.\nreturn '+lua(visual)+'\n')
    write(OUT/'visual-data.json',visual)
    allspec=[a['quietBase']]+[s for layer in ['surfaceTiles','organs','deepTiles','junctions','foregroundPatches']for s in a[layer]]
    specs=[replacements.get(s['id'],s)for s in allspec]
    # Heart has its own resource substitutions; production prepare checks the
    # final combined budget. This is the incremental bowel allocation only.
    report={'status':'STAGED_ART','changedAssets':changes,'atlas':str(atlas.relative_to(ROOT/'assets')),
            'atlasSha256':sha(atlas),'onlyTubeAndMembraneAtlas':True,'opaqueBackgroundPatches':0,
            'retiredOldGutMouthPatches':2,'resourceSlots':len(specs),'registeredFromCurrentRuntimeRoutes':True,
            'sourceBox':BOX,'pixelSize':list(SIZE),'geometryDataSha256':sha(OUT/'runtime-data.json'),
            'nativeVisualEvidence':False,'imagegenMode':'built-in edit','promptRecord':str((OUT/'imagegen-prompts.txt').relative_to(ROOT))}
    write(OUT/'art-check.json',report);print(json.dumps({k:report[k]for k in ['status','resourceSlots','opaqueBackgroundPatches','retiredOldGutMouthPatches']}))
if __name__=='__main__':main()
