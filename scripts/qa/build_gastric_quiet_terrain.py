"""Register GPT material to an immutable gastric silhouette; bake study grids."""
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
OUT=D/'stomach-terrain-v1';A=ROOT/'assets/image/anatomy-reference/vascular-study/stomach-terrain-v1'
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
raw=A/'gpt-terrain-raw-v1.png';assert raw.exists()
clip='<defs><clipPath id="organ"><path d="'+reg['outerPath']+'" clip-rule="evenodd"/></clipPath><clipPath id="tissue"><path d="'+reg['tissuePath']+'" clip-rule="evenodd"/></clipPath><clipPath id="food"><path d="'+reg['foodPath']+'" clip-rule="evenodd"/></clipPath></defs>'
# The generated image is sampled by the renderer, never edited or used to infer
# geometry. Food and external wall retain their exact data-defined shapes.
paint='<g clip-path="url(#organ)"><path d="'+reg['outerPath']+'" fill="#d5ab99"/><image href="data:image/png;base64,'+enc(raw)+'" x="464" y="461" width="180" height="180"/><g clip-path="url(#food)"><path d="'+reg['foodPath']+'" fill="#d8c09b" fill-opacity=".75"/></g>'
paint+='<path d="'+reg['foodPath']+'" fill="none" stroke="#ae957d" stroke-width=".32" stroke-opacity=".58" stroke-linejoin="round"/>'
# Reuse the same painted blood layer at the same anchor. This is a renderer
# composition, not a new AI network; food remains foreground over deep blood.
paint+='<g clip-path="url(#tissue)"><image href="data:image/png;base64,'+enc(D/'registered-vessels/vessel-overlay.png')+'" x="333" y="250" width="360" height="594"/><image href="data:image/png;base64,'+enc(D/'registered-vessels/cutaway-overlay.png')+'" x="333" y="250" width="360" height="594"/></g>'
for gate in reg['gates']:
    ps=[gate['pipeCenterSource'],gate['wallSource'],gate['tissueTargetSource']]
    line='M '+' L '.join(' '.join(str(v)for v in p)for p in ps)
    # Small wall opening into tissue, never a hole in the organ outer contour.
    paint+='<g clip-path="url(#tissue)"><path d="'+line+'" fill="none" stroke="#9b7b83" stroke-width=".55" stroke-opacity=".65" stroke-linecap="round"/><path d="'+line+'" fill="none" stroke="#d6ad9c" stroke-width=".27" stroke-linecap="round"/></g>'
paint+='<path d="'+reg['outerPath']+'" fill="none" stroke="#a97768" stroke-width=".35" stroke-opacity=".6" stroke-linejoin="round"/></g>'
svg='<svg xmlns="http://www.w3.org/2000/svg" width="2160" height="2160" viewBox="464 461 180 180">'+clip+paint+'</svg>'
(A/'terrain-layer-v1.svg').write_text(svg)
cairosvg.svg2png(bytestring=svg.encode(),write_to=str(A/'terrain-layer-v1.png'))
shutil.copy2(A/'terrain-layer-v1.png',OUT/'terrain-layer.png')
source_img='<image href="data:image/png;base64,'+enc(ROOT/'assets/image/anatomy-reference/reference.png')+'" width="1024" height="1536"/>'
for name,view,size,bg in [('art-overview','476 469 153 108',(1530,1080),'<rect x="476" y="469" width="153" height="108" fill="#c4b09c"/>'),('registered-upper','350 450 324 216',(1536,1024),source_img)]:
    out='<svg xmlns="http://www.w3.org/2000/svg" viewBox="'+view+'" width="'+str(size[0])+'" height="'+str(size[1])+'">'+clip+bg+paint+'</svg>'
    (OUT/(name+'.svg')).write_text(out);cairosvg.svg2png(bytestring=out.encode(),write_to=str(OUT/(name+'.png')))

# Local tissue-only movement demonstrator. Blood is its own transport plane;
# entry/exit is not fabricated by allowing ground to cross every visible tube.
internal=[e for e in frozen['edges']if e['a'].startswith('stomach.')and e['b'].startswith('stomach.')]
blood_walls=unary_union([LineString(e['samples']).buffer(e['lumenWidthSource']/2+.7,quad_segs=16)for e in internal])
free=tissue.difference(blood_walls)
atlas=json.loads((D/'registered-vessels-game-evidence/sprite-atlas.json').read_text())
grids={};directions=[[-1,0],[1,0],[0,-1],[0,1],[-1,-1],[1,-1],[-1,1],[1,1]]
minx,miny,maxx,maxy=organ.bounds;step=.75
xs=np.arange(np.floor(minx),np.ceil(maxx)+step,step);ys=np.arange(np.floor(miny),np.ceil(maxy)+step,step)
X,Y=np.meshgrid(xs,ys);points=np.stack((X.ravel(),Y.ravel()),axis=1);nx=len(xs);ny=len(ys)
for kind,desired in [('scout',[562,520]),('siege',[557,518])]:
    radius=atlas['sprites'][kind+'-selected']['cellRadiusSource'];safe=free.buffer(-radius-.02,quad_segs=24)
    good=contains_xy(safe,points[:,0],points[:,1]);adj=np.zeros(len(points),dtype=np.uint8)
    for bit,(dx,dy)in enumerate(directions):
        ids=np.flatnonzero(good);iy,ix=np.divmod(ids,nx);j=ids+dy*nx+dx
        ok=(ix+dx>=0)&(ix+dx<nx)&(iy+dy>=0)&(iy+dy<ny);ids=ids[ok];j=j[ok];ok=good[j];ids=ids[ok];j=j[ok]
        clear=covers(safe,linestrings(np.stack((points[ids],points[j]),axis=1)))
        adj[ids[clear]]|=1<<bit
    valid=np.flatnonzero(good);seed=valid[np.argmin(np.linalg.norm(points[valid]-np.array(desired),axis=1))]
    grids[kind]={'radiusSource':radius,'safePath':gpath(safe),'safeRings':rings(safe),'origin':[float(xs[0]),float(ys[0])],'step':step,'width':nx,'height':ny,'adjacencyBase64':base64.b64encode(adj.tobytes()).decode(),'validBase64':base64.b64encode(good.astype(np.uint8).tobytes()).decode(),'startIndex':int(seed),'startSource':points[seed].tolist(),'validGridPoints':int(good.sum()),'neighborSweepsChecked':int(sum(int(v).bit_count()for v in adj))}
data={**reg,'schema':'gastric-quiet-terrain-study/v1','asset':'terrain-layer.png','rawAssetSha256':sha(raw),'layerSha256':sha(A/'terrain-layer-v1.png'),'promptSha256':sha(OUT/'prompt.txt'),'walkableFractionAfterBloodBeforeRadius':free.area/organ.area,'walkableBeforeRadiusRings':rings(free),'walkableBeforeRadiusPath':gpath(free),'directions':directions,'grids':grids,'collisionAuthority':'same frozen outer contour; food and internal blood wall exclusion; full cell disk plus .02 source-pixel guard','movementDemo':'browser tissue-plane inspection; not production Lua navigation','productionOuterWallInstalled':False,'productionInstalled':False,'nativeEvidence':False,'boundaryAudit':'../gastric-quiet-boundary-audit.json','rejectedOldArtReused':False}
(OUT/'data.json').write_text(json.dumps(data,ensure_ascii=False,separators=(',',':'))+'\n')
metrics={'schema':'gastric-quiet-build-checks/v1','status':'FIXED_CONTOUR_AND_PRECOMPUTED_DISK_SWEEPS_PASS_STUDY_ONLY','referenceSha256':reg['sourceSha256'],'frozenReferenceSha256':reg['finalReferenceSha256'],'fineBoundarySha256':reg['organBoundaryDataSha256'],'rawAssetSha256':sha(raw),'layerSha256':data['layerSha256'],'guideSha256':sha(OUT/'guide.png'),'promptSha256':data['promptSha256'],'dataSha256':sha(OUT/'data.json'),'outerContourRegeneratedByAI':False,'foodGeometryChanged':False,'bloodGeometryChanged':False,'invisibleWallSource':'reg.outerPath and radius-eroded tissue grids, not generated image edge','percentTissueBeforeBlood':100*tissue.area/organ.area,'percentTissueAfterBlood':100*free.area/organ.area,'grids':{k:{q:v[q]for q in ['radiusSource','validGridPoints','neighborSweepsChecked']}for k,v in grids.items()},'productionInstalled':False,'nativeEvidence':False}
(OUT/'checks.json').write_text(json.dumps(metrics,ensure_ascii=False,indent=2)+'\n')
(A/'mapping.json').write_text(json.dumps({'sourceBox':reg['sourceBox'],'sourceSha256':reg['sourceSha256'],'frozenReferenceSha256':reg['finalReferenceSha256'],'rawAssetSha256':sha(raw),'layerSha256':data['layerSha256'],'guide':'docs/body-life/vascular-art-study/stomach-terrain-v1/guide.png','prompt':'docs/body-life/vascular-art-study/stomach-terrain-v1/prompt.txt','outerContourOwnedBy':'final-reference-data.organs[stomach].outlines','productionInstalled':False},ensure_ascii=False,indent=2)+'\n')
print(json.dumps(metrics,ensure_ascii=False))
