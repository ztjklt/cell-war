"""Prepare immutable source geometry for a vessel-only GPT painting layer.

Reads source pixels to select foreground; never edits the bitmap. SVG selections
are part of the map renderer, not generated replacements for raster artwork.
"""
from pathlib import Path
import base64, hashlib, json, sys
import numpy as np, cffi
from PIL import Image, ImageOps
sys.path.insert(0, '/tmp/reference-map-tools')
import cv2, cairosvg
sys.path.insert(0, '/tmp/passage-tools314')
from lupa.lua54 import LuaRuntime
from shapely.geometry import Polygon, LineString, box
from shapely.ops import unary_union, substring

ROOT = Path(__file__).resolve().parents[2]
D = ROOT/'docs/body-life/vascular-art-study'
OUT = D/'registered-vessels'; OUT.mkdir(exist_ok=True)
SOURCE = ROOT/'assets/image/anatomy-reference/reference.png'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
data = json.loads((D/'final-reference-data.json').read_text())
assert sha(SOURCE) == data['referenceSha256']
assert sha(D/'final-reference-data.json') == '3890744e2fcaf9e9907c85513e170e479f67b7fbb1fbf06385ac02bd80e8550c'
BOX = [333, 250, 693, 844]
roi = box(*BOX)
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute("package.path='scripts/?.lua;'..package.path")
boundaries = lua.eval("require('war.OrganBoundariesData')")[0]
assert boundaries.sourceSha256 == sha(SOURCE)

def path(ps, close=False):
    return 'M '+' L '.join(' '.join(f'{float(v):.4f}' for v in p) for p in ps)+(' Z' if close else '')

def geometry_path(g):
    if g.is_empty: return ''
    gs = [g] if g.geom_type == 'Polygon' else list(g.geoms)
    return ' '.join(path(p.exterior.coords,True)+' '+' '.join(path(r.coords,True) for r in p.interiors)
                    for p in gs if p.geom_type == 'Polygon' and not p.is_empty)

def polygon_from_paths(paths):
    positive=[]; negative=[]
    for p in paths:
        g=Polygon(p['points']).buffer(0)
        (negative if p['hole'] else positive).append(g)
    return unary_union(positive).difference(unary_union(negative))

def convert(v):
    if hasattr(v, 'items'):
        pairs=list(v.items())
        return [convert(v[i]) for i in range(1,len(pairs)+1)] if pairs and all(isinstance(k,int) for k,_ in pairs) else {k:convert(q) for k,q in pairs}
    return v

organs = {id:convert(o) for id,o in boundaries.organs.items()}
rgb=np.asarray(Image.open(SOURCE).convert('RGB')).astype(np.int16)
r,g,b=[rgb[:,:,i] for i in range(3)]
lung_area=np.zeros(r.shape,np.uint8)
for id in ['lung_r','lung_l']:
    for ring in organs[id]['outlinePaths']:
        cv2.fillPoly(lung_area,[np.rint(ring['points']).astype(np.int32)],0 if ring['hole'] else 1)
air=(lung_area>0)&(b-r>15)&(g-r>-25)&(b>110)
air=cv2.dilate(air.astype(np.uint8),np.ones((3,3),np.uint8))

def pixel_selection(mask):
    # Exact source-pixel squares: no polygon fitting of the anatomical edge.
    runs=[]
    for py in range(BOX[1],BOX[3]):
        xs=np.flatnonzero(mask[py,BOX[0]:BOX[2]])+BOX[0]
        if not len(xs): continue
        starts=np.r_[0,np.flatnonzero(np.diff(xs)>1)+1]
        ends=np.r_[starts[1:]-1,len(xs)-1]
        runs.extend(box(xs[a]-.5,py-.5,xs[z]+.5,py+.5) for a,z in zip(starts,ends))
    return unary_union(runs)

airway=pixel_selection(air).intersection(roi)
bladder=polygon_from_paths(organs['bladder']['outlinePaths'])
# Fixed original orange face, not the legacy fourteen-point locator.
bladder_core=bladder.buffer(1.5)
bladder_wall_edges={'e143','e197','e198'}
coronary=np.zeros(r.shape,np.uint8)
coronary[390:460,477:559]=((r>220)&(g>140)&(g-b>30))[390:460,477:559]
coronary_shape=pixel_selection(coronary)
fixed_foreground=airway.union(coronary_shape)
# Whole-body view shows intact organ faces. Internal wall vessels belong to
# the cutaway layer, revealed together with the existing .085–.15 fill.
# This changes only foreground display, never graph paths, ports or obstacles.
overview_shapes=[]
for id in ['lung_r','lung_l','heart','liver','stomach','pancreas','kidney_r','kidney_l','large_intestine','small_intestine']:
    g=polygon_from_paths(organs[id]['outlinePaths'])
    # Tiny spaces between intestinal coils or pancreatic lobules are not
    # windows into the deeper vascular plane in the intact overview.
    if id in {'pancreas','large_intestine','small_intestine'}:g=g.convex_hull
    overview_shapes.append(g.buffer(.65))
overview_foreground=unary_union(overview_shapes)
edges=[]; footprints=[]
palette={'artery':'#bb574e','vein':'#4a85af','capillary':'#947786'}
display_overrides={'H055','H056','H057','H068','H069','H154','H155','H156'}
def display_segments(e):
    # Rebuild the union of remaining occlusions. Never subtract from a merged
    # interval: an airway and an invisible deep conduit may overlap there.
    line=LineString(e['samples']); intervals=[]
    for q in data['occlusions']:
        if q['edgeId']==e['id'] and q['id'] not in display_overrides:
            intervals.append([q['startDistance'],q['endDistance']])
    merged=[]
    for a,b in sorted(intervals):
        if merged and a<=merged[-1][1]+1e-6: merged[-1][1]=max(b,merged[-1][1])
        else: merged.append([a,b])
    result=[];a=0
    for left,right in merged+[[line.length,line.length]]:
        if left>a+1e-5: result.append(substring(line,a,left))
        a=max(a,right)
    return result
for e in data['edges']:
    if e['id'] in data['protectedEdges']: continue
    visible=display_segments(e)
    if not visible: continue
    width=e['lumenWidthSource']
    # Original width and flat hidden cut ends. No rim or shadow outside this.
    tube=unary_union([line.buffer(width/2,cap_style=2,join_style=1) for line in visible]).intersection(roi)
    # Round only graph endpoints, never the endpoints created by an occlusion.
    from shapely.geometry import Point
    for q in (e['samples'][0],e['samples'][-1]):
        if any(np.linalg.norm(np.array(q)-p)<.015 for line in visible for p in (line.coords[0],line.coords[-1])):
            tube=tube.union(Point(q).buffer(width/2)).intersection(roi)
    tube=tube.difference(fixed_foreground)
    tube=tube.difference(bladder_core)
    if tube.is_empty: continue
    ps=[list(map(float,p)) for line in visible for p in [line.coords[0],line.coords[-1]]]
    overview_tube=tube.difference(overview_foreground)
    overview_pieces=[]
    components=[overview_tube]if overview_tube.geom_type=='Polygon'else list(getattr(overview_tube,'geoms',[]))
    for component in components:
        if component.is_empty or component.geom_type!='Polygon':continue
        near_port=any(component.distance(Point(p['source']))<=width*2 for p in data['ports'] if p['kind']=='named_port' and p['id'] in {e['a'],e['b']})
        x0,y0,x1,y1=component.bounds
        short=max(x1-x0,y1-y0)<width*4 and component.area<width*width*5
        overview_pieces.append({'d':geometry_path(component),'opacity':.10 if short and not near_port else 1,'areaSource':component.area,'namedPortApproach':near_port})
    edges.append({'id':e['id'],'a':e['a'],'b':e['b'],'system':e['system'],'layer':e['layer'],
                  'widthSource':width,'paintPath':geometry_path(tube),'areaSource':tube.area,
                  'overviewPaintPath':geometry_path(overview_tube),
                  'overviewPieces':overview_pieces,
                  'visibleSegments':[[list(p) for p in line.coords] for line in visible],'samples':e['samples'],
                  'bladderWallOnly':e['id'] in bladder_wall_edges})
    footprints.append(tube)
combined=unary_union(footprints)
encoded=base64.b64encode(SOURCE.read_bytes()).decode()
source_image=f'<image href="data:image/png;base64,{encoded}" width="1024" height="1536"/>'
start='<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="1782" viewBox="333 250 360 594">'
guide=start+'<rect x="333" y="250" width="360" height="594" fill="#f1e6df"/>'
guide+=''.join(f'<path data-edge="{e["id"]}" d="{e["paintPath"]}" fill="{palette[e["system"]]}" fill-rule="evenodd"/>' for e in sorted(edges,key=lambda e:e['layer']))+'</svg>'
for name, svg in [('guide',guide),('original',start+source_image+'</svg>')]:
    (OUT/f'{name}.svg').write_text(svg)
    cairosvg.svg2png(bytestring=svg.encode(),write_to=str(OUT/f'{name}.png'))
record={'schema':'registered-vessel-art-geometry/v1','sourceBox':BOX,'sourceSha256':sha(SOURCE),
        'finalReferenceSha256':sha(D/'final-reference-data.json'),'boundariesSha256':sha(ROOT/'scripts/war/OrganBoundariesData.lua'),
        'protectedEdgeIds':data['protectedEdges'],'edges':edges,'paintUnionPath':geometry_path(combined),
        'airwayForegroundPath':geometry_path(airway),'coronaryForegroundPath':geometry_path(coronary_shape),
        'overviewForegroundPath':geometry_path(overview_foreground),
        'unitOverviewForegroundPath':geometry_path(overview_foreground.union(fixed_foreground).union(bladder_core)),
        'unitCloseForegroundPath':geometry_path(fixed_foreground.union(bladder_core)),
        'bladderForegroundPath':geometry_path(bladder_core),'bladderFineOutline':organs['bladder']['outlinePaths'],
        'ports':data['ports'],'gates':data['gates'],
        'displayContract':{'noFootprintExpansion':True,'hiddenCutCaps':'flat','topologyEdited':False,
                           'ignoredDeepCandidateOcclusionIds':sorted(display_overrides),
                           'organInteriorLayer':'intact source foreground in overview; reveal registered wall spans with the existing .085–.15 fill, not in the food lumen',
                           'wallDepthEdges':sorted(bladder_wall_edges),'unitsInDepth':'hide solid sprite beneath original face; optional explicit depth marker only'},
        'counts':{'paintedEdges':len(edges),'paintAreaSource':combined.area},'productionInstalled':False}
(OUT/'geometry.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'edges':len(edges),'area':combined.area,'output':str(OUT)},ensure_ascii=False))
