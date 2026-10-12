"""Build registered gastric room art with separate food inlet context. Tissue navigation stays frozen to v1."""
from pathlib import Path
import base64, hashlib, json, sys, shutil
import cffi, numpy as np
from PIL import Image
sys.path.insert(0,'/tmp/reference-map-tools')
import cairosvg
sys.path.insert(0,'/tmp/passage-tools314')
from shapely.geometry import Polygon, LineString, Point, box
from shapely.ops import unary_union
from shapely import contains_xy, covers, linestrings

ROOT=Path(__file__).resolve().parents[2];D=ROOT/'docs/body-life/vascular-art-study'
OUT=D/'stomach-terrain-v2';A=ROOT/'assets/image/anatomy-reference/vascular-study/stomach-terrain-v2'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
reg=json.loads((OUT/'registration.json').read_text());frozen=json.loads((D/'final-reference-data.json').read_text())
assert reg['sourceSha256']==sha(ROOT/'assets/image/anatomy-reference/reference.png')
assert reg['finalReferenceSha256']==sha(D/'final-reference-data.json')
organ=unary_union([Polygon(p['outer'],p['holes'])for p in reg['outerRings']])
food=unary_union([Polygon(p['outer'],p['holes'])for p in reg['foodRings']])
tissue=organ.difference(food)
def rings(g):
    ps=[g]if g.geom_type=='Polygon'else list(getattr(g,'geoms',[]))
    return [{'outer':[list(p)for p in q.exterior.coords],'holes':[[list(p)for p in h.coords]for h in q.interiors]}for q in ps if q.geom_type=='Polygon'and not q.is_empty]
def gpath(g):
    ring=lambda ps:'M '+' L '.join(' '.join(f'{v:.6f}'for v in p)for p in ps)+' Z'
    return ' '.join(ring(q['outer'])+' '+' '.join(ring(h)for h in q['holes'])for q in rings(g))
enc=lambda p:base64.b64encode(p.read_bytes()).decode()
raw=A/reg.get('rawAsset','gpt-rich-rooms-tissue-v2.png');assert raw.exists()
inlet=json.loads((OUT/'inlet-geometry.json').read_text())
inlet_wall=LineString(inlet['points']).buffer(inlet['wallWidthSource']/2,cap_style=2,join_style=1,quad_segs=24)
foreground=unary_union([Polygon(points['points'])for o in frozen['organs']if o['id']in ['heart','lung_l','lung_r']for points in o['outlines']])
visible_context=organ.union(inlet_wall.difference(foreground))
inlet['visibleArtClipPath']=gpath(visible_context)
inlet['foregroundOcclusionIds']=['heart','lung_l','lung_r']
inlet['foregroundGeometrySource']='frozen final-reference-data organs[].outlines; the food tube remains behind heart and lungs'
(OUT/'inlet-geometry.json').write_text(json.dumps(inlet,ensure_ascii=False,indent=2)+'\n')
projection=reg['rawMaterialProjection']; raw_position=' '.join(k+'="'+str(projection[k])+'"' for k in ['x','y','width','height'])
raw_position+=' preserveAspectRatio="none"'
clip='<defs><clipPath id="organ"><path d="'+reg['outerPath']+'" clip-rule="evenodd"/></clipPath><clipPath id="artContext"><path d="'+inlet['visibleArtClipPath']+'" clip-rule="evenodd"/></clipPath><clipPath id="tissue"><path d="'+reg['tissuePath']+'" clip-rule="evenodd"/></clipPath><clipPath id="food"><path d="'+reg['foodPath']+'" clip-rule="evenodd"/></clipPath></defs>'
# The generated image is sampled by the renderer, never edited or used to infer
# geometry. Food and external wall retain their exact data-defined shapes.
# GPT supplies the room illustration and connected inlet. Native geometry clips
# the exact stomach and food context while leaving gameplay boundaries frozen.
paint='<g clip-path="url(#artContext)"><path d="'+inlet['artClipPath']+'" fill="#f0b7a4"/><image href="data:image/png;base64,'+enc(raw)+'" '+raw_position+'/>'
inlet_core=LineString(inlet['points']).buffer(inlet['lumenWidthSource']/2,cap_style=2,join_style=1,quad_segs=24)
# The esophagus is food context outside the unchanged tissue collider. A full
# closed organ rim here would cap the fixed cardia mouth, so omit that visual rim.
rim=organ.difference(organ.buffer(-1.25,quad_segs=24)).difference(inlet_wall.buffer(.3))
def lpath(g):
    lines=[g]if g.geom_type=='LineString'else list(getattr(g,'geoms',[]))
    return ' '.join('M '+' L '.join(' '.join(f'{v:.6f}'for v in p)for p in q.coords)for q in lines if q.geom_type=='LineString')
outer_ink=lpath(organ.boundary.difference(inlet_wall.buffer(.4)))
paint+='<path d="'+gpath(rim)+'" fill="#e79a90" fill-rule="evenodd"/>'
paint+='<g clip-path="url(#food)"><path d="'+reg['foodPath']+'" fill="#f3d9a3" stroke="#db8c81" stroke-width="2.6" stroke-linejoin="round"/>'
# Sparse flat color impressions inside the exact lumen; no raised food objects.
for x,y,rx,ry,angle in [(575,489,3.1,.65,24),(599,507,2.8,.8,61),(600,525,3.8,.9,104),(587,550,3.7,.8,-32),(552,558,3.2,.6,9),(507,549,2.7,.55,-4)]:
    paint+='<ellipse cx="'+str(x)+'" cy="'+str(y)+'" rx="'+str(rx)+'" ry="'+str(ry)+'" transform="rotate('+str(angle)+' '+str(x)+' '+str(y)+')" fill="#eabb88" opacity=".42"/>'
paint+='<path d="'+reg['foodPath']+'" fill="none" stroke="#af726a" stroke-width=".22" stroke-linejoin="round"/></g>'
# Base art is the accepted room illustration in the exact stomach clip.
# Fixed food/blood are a separate inspection overlay, never silently baked
# through newly proposed rooms before gameplay layout reconciliation.
base_paint='<g clip-path="url(#artContext)"><path d="'+inlet['artClipPath']+'" fill="#f0b7a4"/><image href="data:image/png;base64,'+enc(raw)+'" '+raw_position+'/><path d="'+gpath(rim)+'" fill="#e79a90" fill-rule="evenodd"/><path d="'+outer_ink+'" fill="none" stroke="#9d665f" stroke-width=".3" stroke-linejoin="round"/></g>'
# Flat vessel ink uses the identical registered footprint and draw order.
# This renderer style changes neither samples nor visible/hidden route decisions.
geometry=json.loads((D/'registered-vessels/geometry.json').read_text())
assert geometry['finalReferenceSha256']==reg['finalReferenceSha256']
palette={'artery':('#d98082','#a2656c'),'vein':('#8db2c2','#617f98'),'capillary':('#bb8f9f','#916d82')}
paint+='<g clip-path="url(#tissue)">'
for edge in sorted(geometry['edges'],key=lambda e:(e['layer'],e['id'])):
    fill,stroke=palette.get(edge['system'],palette['capillary'])
    paint+='<path d="'+edge['paintPath']+'" fill="'+fill+'" stroke="'+stroke+'" stroke-width=".14" stroke-linejoin="round"/>'
paint+='</g>'
for gate in reg['gates']:
    ps=[gate['pipeCenterSource'],gate['wallSource'],gate['tissueTargetSource']]
    line='M '+' L '.join(' '.join(str(v)for v in p)for p in ps)
    # Small wall opening into tissue, never a hole in the organ outer contour.
    paint+='<g clip-path="url(#tissue)"><path d="'+line+'" fill="none" stroke="#9b7b83" stroke-width=".55" stroke-opacity=".65" stroke-linecap="round"/><path d="'+line+'" fill="none" stroke="#d6ad9c" stroke-width=".27" stroke-linecap="round"/></g>'
paint+='<path d="'+outer_ink+'" fill="none" stroke="#9d665f" stroke-width=".3" stroke-linejoin="round"/></g>'
svg='<svg xmlns="http://www.w3.org/2000/svg" width="2160" height="2160" viewBox="464 448 180 180">'+clip+paint+'</svg>'
base_svg='<svg xmlns="http://www.w3.org/2000/svg" width="2160" height="2160" viewBox="464 448 180 180">'+clip+base_paint+'</svg>'
(A/'terrain-base-v2.svg').write_text(base_svg)
cairosvg.svg2png(bytestring=base_svg.encode(),write_to=str(A/'terrain-base-v2.png'))
shutil.copy2(A/'terrain-base-v2.png',OUT/'terrain-base.png')
(A/'terrain-layer-v2.svg').write_text(svg)
cairosvg.svg2png(bytestring=svg.encode(),write_to=str(A/'terrain-layer-v2.png'))
shutil.copy2(A/'terrain-layer-v2.png',OUT/'terrain-layer.png')
source_img='<image href="data:image/png;base64,'+enc(ROOT/'assets/image/anatomy-reference/reference.png')+'" width="1024" height="1536"/>'
for name,view,size,bg in [('art-overview','476 440 153 139',(1530,1390),'<rect x="476" y="440" width="153" height="139" fill="#c4b09c"/>'),('registered-upper','350 438 324 216',(1536,1024),source_img)]:
    out='<svg xmlns="http://www.w3.org/2000/svg" viewBox="'+view+'" width="'+str(size[0])+'" height="'+str(size[1])+'">'+clip+bg+base_paint+'</svg>'
    (OUT/(name+'.svg')).write_text(out);cairosvg.svg2png(bytestring=out.encode(),write_to=str(OUT/(name+'.png')))

# Local tissue-only movement demonstrator. Blood is its own transport plane;
# entry/exit is not fabricated by allowing ground to cross every visible tube.
internal=[e for e in frozen['edges']if e['a'].startswith('stomach.')and e['b'].startswith('stomach.')]
blood_walls=unary_union([LineString(e['samples']).buffer(e['lumenWidthSource']/2+.7,quad_segs=16)for e in internal])
free=tissue.difference(blood_walls)
# Art only: reuse certified circle-clearance grids without deriving walls from pixels.
previous=json.loads((D/'stomach-terrain-v1/data.json').read_text())
assert previous['outerPath']==reg['outerPath'] and previous['foodPath']==reg['foodPath']
grids=previous['grids'];directions=previous['directions']
data={**reg,'schema':'gastric-organic-terrain-study/v3','artCanvasSourceBox':[464,448,644,628],'inlet':inlet,'asset':'terrain-layer.png','baseAsset':'terrain-base.png','rawAssetSha256':sha(raw),'layerSha256':sha(A/'terrain-layer-v2.png'),'promptSha256':sha(OUT/'prompt.txt'),'walkableFractionAfterBloodBeforeRadius':free.area/organ.area,'walkableBeforeRadiusRings':rings(free),'walkableBeforeRadiusPath':gpath(free),'directions':directions,'grids':grids,'collisionAuthority':'same frozen outer contour; food and internal blood wall exclusion; full cell disk plus .02 source-pixel guard','movementDemo':'browser tissue-plane inspection; not production Lua navigation','productionOuterWallInstalled':False,'productionInstalled':False,'nativeEvidence':False,'boundaryAudit':'../gastric-quiet-boundary-audit.json','rejectedOldArtReused':False,'previousGridDataSha256':sha(D/'stomach-terrain-v1/data.json'),'flatMaterialZonesAreWalkable':True,'proposedRoomWallsInstalled':False,'roomFoodVesselReconciliation':'Art study only; fixed routes are a separate inspection overlay','materialDerivedColliders':False,'registeredVesselGeometrySha256':sha(D/'registered-vessels/geometry.json')}
(OUT/'data.json').write_text(json.dumps(data,ensure_ascii=False,separators=(',',':'))+'\n')
metrics={'schema':'gastric-organic-build-checks/v3','inletGeometrySha256':sha(OUT/'inlet-geometry.json'),'inletCellEntry':False,'inletOuterContourChanged':False,'imagePreserveAspectRatio':'none','status':'FIXED_CONTOUR_AND_PRECOMPUTED_DISK_SWEEPS_PASS_STUDY_ONLY','referenceSha256':reg['sourceSha256'],'frozenReferenceSha256':reg['finalReferenceSha256'],'fineBoundarySha256':reg['organBoundaryDataSha256'],'rawAssetSha256':sha(raw),'layerSha256':data['layerSha256'],'guideSha256':sha(OUT/'shape-stencil.png'),'promptSha256':data['promptSha256'],'dataSha256':sha(OUT/'data.json'),'outerContourRegeneratedByAI':False,'foodGeometryChanged':False,'priorGridsIdentical':grids==previous['grids'],'flatArtworkAddsColliders':False,'registeredVesselGeometrySha256':sha(D/'registered-vessels/geometry.json'),'bloodGeometryChanged':False,'invisibleWallSource':'reg.outerPath and radius-eroded tissue grids, not generated image edge','percentTissueBeforeBlood':100*tissue.area/organ.area,'percentTissueAfterBlood':100*free.area/organ.area,'grids':{k:{q:v[q]for q in ['radiusSource','validGridPoints','neighborSweepsChecked']}for k,v in grids.items()},'productionInstalled':False,'nativeEvidence':False}
(OUT/'checks.json').write_text(json.dumps(metrics,ensure_ascii=False,indent=2)+'\n')
(A/'mapping.json').write_text(json.dumps({'sourceBox':reg['sourceBox'],'materialSourceBox':reg['materialSourceBox'],'rawMaterialProjection':projection,'sourceSha256':reg['sourceSha256'],'frozenReferenceSha256':reg['finalReferenceSha256'],'rawAssetSha256':sha(raw),'layerSha256':data['layerSha256'],'guide':'docs/body-life/vascular-art-study/stomach-terrain-v2/shape-stencil.png','prompt':'docs/body-life/vascular-art-study/stomach-terrain-v2/prompt.txt','outerContourOwnedBy':'final-reference-data.organs[stomach].outlines','productionInstalled':False},ensure_ascii=False,indent=2)+'\n')
print(json.dumps(metrics,ensure_ascii=False))
