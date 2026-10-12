"""Register GPT raster materials against the reviewed upper-abdomen map.

GPT supplies tissue repair and vessel paint. Source organ rims and reviewed
visible lumen geometry supply registration. This is an art pilot, not runtime.
SVG composition is retained so crop offsets and occlusion masks remain editable.
"""
from pathlib import Path
import base64
import hashlib
import json
import sys
import cffi
import numpy as np
from PIL import Image, ImageOps

sys.path.insert(0, '/tmp/reference-map-tools')
import cairosvg
sys.path.insert(0, '/tmp/passage-tools314')
from shapely.geometry import Polygon, Point, LineString, box as rectangle
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parents[2]
D = ROOT / 'docs/body-life/vascular-art-study'
A = ROOT / 'assets/image/anatomy-reference/vascular-study/upper-abdomen'
CLEAN = A / 'gpt-clean-underlay-v2.png'
OUT = D / 'upper-abdomen-output'
OUT.mkdir(exist_ok=True)
data = json.loads((D / 'final-reference-data.json').read_text())
reg = json.loads((D / 'upper-abdomen-inputs/registration.json').read_text())
BOX = reg['sourceBox']
x, y, x1, y1 = BOX
W, H = x1-x, y1-y
source = ROOT / 'assets/image/anatomy-reference/reference.png'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(source) == data['referenceSha256'] == reg['sourceSha256']
assert sha(D / 'final-reference-data.json') == reg['finalReferenceSha256']
edges = [e for e in data['edges'] if e['id'] in reg['localEdgeIds']]
organs = [o for o in data['organs'] if o['bounds'][1] < y1 and o['bounds'][3] > y]

def path(points, closed=False):
    return 'M ' + ' L '.join(' '.join(f'{v:.5f}' for v in p) for p in points) + (' Z' if closed else '')

def outline(o):
    return ' '.join(path(q['points'], True) for q in o['outlines'])

def geom_path(g):
    polys = [g] if g.geom_type == 'Polygon' else list(g.geoms)
    return ' '.join(path(list(p.exterior.coords), True) + ' ' +
        ' '.join(path(list(r.coords), True) for r in p.interiors) for p in polys if not p.is_empty)

def image(p, box=(0, 0, 1024, 1536), **attrs):
    encoded = base64.b64encode(p.read_bytes()).decode()
    a, b, c, d = box
    attributes = ' '.join(f'{k.replace("_", "-")}="{v}"' for k,v in attrs.items())
    return f'<image href="data:image/png;base64,{encoded}" x="{a}" y="{b}" width="{c-a}" height="{d-b}" {attributes}/>'

def strokes(es, color=None, width_scale=1):
    result = []
    for e in es:
        for i, ps in enumerate(e['visibleSegments']):
            result.append(f'<path data-edge="{e["id"]}" data-piece="{i}" d="{path(ps)}" fill="none" stroke="{color or PALETTE[e["system"]]}" stroke-width="{e["lumenWidthSource"]*width_scale}" stroke-linecap="butt" stroke-linejoin="round"/>')
        # Only real graph endpoints receive a round end. Hidden cut ends stay flat.
        for endpoint in [e['samples'][0], e['samples'][-1]]:
            if any(np.linalg.norm(np.array(endpoint)-ps[j]) < .015 for ps in e['visibleSegments'] for j in [0,-1]):
                result.append(f'<circle data-node-edge="{e["id"]}" cx="{endpoint[0]}" cy="{endpoint[1]}" r="{e["lumenWidthSource"]*width_scale/2}" fill="{color or PALETTE[e["system"]]}"/>')
    return '\n'.join(result)

source_rgb = np.asarray(Image.open(source).convert('RGB')).astype(np.int16)
r, g, b = [source_rgb[:,:,i] for i in range(3)]

def pigment_shape(selected):
    """Trace original pigment as source-coordinate SVG selection geometry."""
    runs = []
    for py in range(y,y1):
        indexes = np.flatnonzero(selected[py,x:x1]) + x
        if not len(indexes):
            continue
        starts = np.r_[0,np.flatnonzero(np.diff(indexes)>1)+1]
        ends = np.r_[starts[1:]-1,len(indexes)-1]
        runs.extend(rectangle(indexes[a]-.5,py-.5,indexes[z]+.5,py+.5) for a,z in zip(starts,ends))
    return unary_union(runs).buffer(.7).simplify(.08)

old_blue = pigment_shape((b-r>12)&(g-r>-45)&(b>100)).buffer(.8)

PALETTE = {'artery':'#c45a50', 'vein':'#4a83ae', 'capillary':'#8a708b'}
DEEP = {'artery':'#98443f', 'vein':'#3a668a', 'capillary':'#705b76'}
groups = [(layer, [e for e in edges if e['layer'] == layer]) for layer in sorted({e['layer'] for e in edges})]
defs = ['<defs><clipPath id="crop"><rect x="350" y="450" width="324" height="216"/></clipPath>',
    '<clipPath id="repair"><path d="M 386 450 L 634 450 L 638 530 L 633 600 L 639 666 L 385 666 L 386 610 L 390 550 Z"/></clipPath>']
defs.append(image(A/'gpt-vessel-material-v2.png', BOX, id='gpt-pipe-paint'))
for side,p0,p1 in [('top',(350,450),(350,460)),('bottom',(350,666),(350,656)),
        ('left',(350,450),(360,450)),('right',(674,450),(664,450))]:
    defs.append(f'<linearGradient id="crop-{side}-gradient" gradientUnits="userSpaceOnUse" x1="{p0[0]}" y1="{p0[1]}" x2="{p1[0]}" y2="{p1[1]}"><stop offset="0" stop-color="white" stop-opacity="0"/><stop offset="1" stop-color="white"/></linearGradient><mask id="crop-{side}" maskUnits="userSpaceOnUse" x="350" y="450" width="324" height="216"><rect x="350" y="450" width="324" height="216" fill="url(#crop-{side}-gradient)"/></mask>')
for o in organs:
    organ_polygon = Polygon(o['outlines'][0]['points'])
    p = organ_polygon
    # Original rims stay fixed. The only original vessel paint inside an organ
    # is the old renal hilar Y; replace its interior without moving kidney rims.
    if o['id'] in ['kidney_r','kidney_l']:
        p = p.difference(old_blue.intersection(p))
    defs.append(f'<clipPath id="source-{o["id"]}"><path data-organ="{o["id"]}" d="{geom_path(p)}" clip-rule="evenodd"/></clipPath>')
    # A faint GPT shading contribution remains strictly inside the fixed rim.
    inner = p.buffer(-4)
    if not inner.is_empty:
        defs.append(f'<clipPath id="interior-{o["id"]}"><path d="{geom_path(inner)}"/></clipPath>')
    paint_mask = []
    for inset in [1.5,2.5,3.5,4.5,5.5]:
        q = organ_polygon.buffer(-inset)
        if not q.is_empty:
            paint_mask.append(f'<path d="{geom_path(q)}" fill="white" opacity=".34"/>')
    q = organ_polygon.buffer(-6.5)
    if not q.is_empty:
        paint_mask.append(f'<path d="{geom_path(q)}" fill="white"/>')
    defs.append(f'<mask id="organ-paint-{o["id"]}" maskUnits="userSpaceOnUse" x="350" y="450" width="324" height="216">'+''.join(paint_mask)+'</mask>')

# Keep the original food conduit paint. This expanded display footprint does
# not alter its independent gameplay corridor or any vessel visibility span.
duodenum = next(p for p in data['protectedPassages'] if p['id'] == 'food.duodenum')
food_footprint = LineString(duodenum['points']).buffer(12.5).union(LineString([(536,450),(536,470),(544,487)]).buffer(13))
food_shape = pigment_shape((r-g>25)&(g-b>9)&(g>110)&(r>175)).intersection(food_footprint).difference(old_blue)
defs.append(f'<clipPath id="original-food"><path d="{geom_path(food_shape)}"/></clipPath>')
# Bilary green is a separate conduit, preserved from the original raster.
bile_shape = pigment_shape((g-r>4)&(g-b>8)).intersection(LineString([(451,550),(446,574),(448,616)]).buffer(8))
defs.append(f'<clipPath id="original-bile"><path d="{geom_path(bile_shape)}"/></clipPath>')
for layer, es in groups:
    # clipPath paths cannot use stroked open paths; use an alpha mask instead.
    defs.append(f'<mask id="lumen-{layer}" maskUnits="userSpaceOnUse" x="350" y="450" width="324" height="216">{strokes(es,"white")}</mask>')
    # Fade hidden cut ends within the reviewed visible interval. This gives
    # foreground cover a soft tuck rather than a rectangular broken pipe.
    for e in es:
        for i, ps in enumerate(e['visibleSegments']):
            line = LineString(ps)
            start_fixed = np.linalg.norm(np.array(ps[0])-e['samples'][0]) < .015
            end_fixed = np.linalg.norm(np.array(ps[-1])-e['samples'][-1]) < .015
            stem = f'fade-{e["id"].replace(".","-")}-{i}'
            fade_length = min(max(1.3,e['lumenWidthSource']*.9),line.length/3)
            for side, fixed, p0, p1 in [('start',start_fixed,ps[0],list(line.interpolate(fade_length).coords)[0]),
                    ('end',end_fixed,ps[-1],list(line.interpolate(line.length-fade_length).coords)[0])]:
                gradient = stem+'-'+side+'-gradient'
                defs.append(f'<linearGradient id="{gradient}" gradientUnits="userSpaceOnUse" x1="{p0[0]}" y1="{p0[1]}" x2="{p1[0]}" y2="{p1[1]}"><stop offset="0" stop-color="white" stop-opacity="0"/><stop offset="1" stop-color="white"/></linearGradient>')
                defs.append(f'<mask id="{stem}-{side}" maskUnits="userSpaceOnUse" x="350" y="450" width="324" height="216"><rect x="350" y="450" width="324" height="216" fill="{("white" if fixed else "url(#"+gradient+")")}"/></mask>')
            defs.append(f'<mask id="{stem}-tube" maskUnits="userSpaceOnUse" x="350" y="450" width="324" height="216"><path d="{path(ps)}" fill="none" stroke="white" stroke-width="{e["lumenWidthSource"]}" stroke-linecap="butt" stroke-linejoin="round"/></mask>')
defs.append('</defs>')
layers = [image(source), '<g id="registered-upper-abdomen" clip-path="url(#crop)">',
    '<g mask="url(#crop-top)"><g mask="url(#crop-bottom)"><g mask="url(#crop-left)"><g mask="url(#crop-right)">',
    '<g clip-path="url(#repair)">'+image(CLEAN, BOX)+'</g>']
for o in organs:
    layers.append('<g clip-path="url(#source-'+o['id']+')">'+image(source)+'</g>')
    if o['id'] in ['liver','stomach','pancreas','kidney_r','kidney_l']:
        layers.append('<g mask="url(#organ-paint-'+o['id']+')">'+image(CLEAN,BOX)+'</g>')
# The GPT clean repair preserves the original food and bile painting. Keep
# their source footprints as metadata/inspection masks without copying back
# mixed blue pixels from the source's old vessel–food antialiased boundaries.
short_glimpses = []
for layer, es in groups:
    layers.append(f'<g id="vessel-layer-{layer}">')
    # A quiet complete tube base prevents model omissions inside the mask.
    for e in es:
        for i, ps in enumerate(e['visibleSegments']):
            cap = 'round' if len(ps)>1 else 'butt'
            stem = f'fade-{e["id"].replace(".","-")}-{i}'
            named_port_end = any(np.linalg.norm(np.array(ps[j])-p['source'])<.02 for j in [0,-1] for p in data['ports'] if p['kind']=='named_port')
            short = LineString(ps).length < e['lumenWidthSource']*2.4 and not named_port_end
            # Sub-diameter glimpses are painted as quiet depth hints, never
            # enlarged into fake connections. The technical layer stays exact.
            if short:
                short_glimpses.append({'edgeId':e['id'],'piece':i,'lengthSource':LineString(ps).length,'widthSource':e['lumenWidthSource'],'opacity':.12})
            layers.append(f'<g data-render-edge="{e["id"]}" data-piece="{i}" data-short-glimpse="{str(short).lower()}" opacity="{.12 if short else 1}"><g mask="url(#lumen-{layer})"><g mask="url(#{stem}-start)"><g mask="url(#{stem}-end)">')
            for color, scale in [(DEEP[e['system']],1),(PALETTE[e['system']],.80)]:
                layers.append(f'<path d="{path(ps)}" fill="none" stroke="{color}" stroke-width="{e["lumenWidthSource"]*scale}" stroke-linejoin="round" stroke-linecap="{cap}"/>')
            layers.append(f'<g mask="url(#{stem}-tube)"><g opacity=".10"><use href="#gpt-pipe-paint"/></g></g>')
            layers.append('</g></g></g></g>')
    layers.append('</g>')
# Quiet visual marks at the two reviewed gastric wall openings; no new branch
# or food connection. Simulation has not adopted these openings.
layers.append('<g id="gastric-wall-marks">')
for gate in data['gates']:
    q = np.array(gate['wallSource']); tangent = np.array([-gate['ny'],gate['nx']])
    layers.append(f'<path data-gate="{gate["id"]}" d="{path([q-tangent*.55,q+tangent*.55])}" fill="none" stroke="#ead2b1" stroke-width=".48" stroke-linecap="round"/>')
layers.append('</g></g></g></g></g></g>')

def document(view, size):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{size[0]}" height="{size[1]}" viewBox="{view}">\n'+'\n'.join(defs+layers)+'\n</svg>'

for name, view, size in [('registered-full-body','0 0 1024 1536',(1024,1536)),
        ('registered-upper-abdomen','350 450 324 216',(1536,1024))]:
    svg = document(view,size)
    (OUT/(name+'.svg')).write_text(svg)
    cairosvg.svg2png(bytestring=svg.encode(),write_to=str(OUT/(name+'.png')))
source_pixels = np.asarray(Image.open(source).convert('RGB'))
result = np.asarray(Image.open(OUT/'registered-full-body.png').convert('RGB'))
outside = np.ones(source_pixels.shape[:2],dtype=bool)
outside[y:y1,x:x1] = False
equal = bool(np.array_equal(source_pixels[outside], result[outside]))
record = {'schema':'upper-abdomen-gpt-art-pilot/v1', 'tool':'GPT built-in imagegen',
    'status':'REGISTERED_ART_PILOT', 'sourceBox':BOX,
    'sourceSha256':sha(source), 'finalReferenceSha256':sha(D/'final-reference-data.json'),
    'registrationSha256':sha(D/'upper-abdomen-inputs/registration.json'),
    'generatedAssets':{p.name:sha(p) for p in A.glob('gpt-*.png')},
    'visibleEdgeIds':[e['id'] for e in edges if e['visibleSegments']],
    'hiddenOnlyEdgeIds':[e['id'] for e in edges if not e['visibleSegments']],
    'organRims':'original organ rims at exact source coordinates; GPT interior paint fades in 1.5–6.5 source pixels inside each fixed outline',
    'renalRepair':'old blue hilar Ys removed within source kidney masks; original rims retained',
    'composition':'GPT clean tissue/food/bile underlay v2 + original fixed organ rims + exact tube base with hidden-end fade + masked GPT vessel material at 0.10 opacity',
    'shortGlimpses':short_glimpses, 'cropInnerBlendSourcePixels':10,
    'gastricWallMarks':'2 subtle fixed-position opening marks; no simulation or movement acceptance',
    'modelTopologyCertified':False, 'rawBeautyAccepted':False,
    'rawBeautyRejection':['invented gastric blue bridge','missing reviewed branches','source organ shapes drift'],
    'outsideCropPixelIdentical':equal, 'outsideCropChangedPixels':int(np.count_nonzero(np.any(source_pixels!=result,axis=2)&outside)),
    'brainAndLimbsOriginalPixels':equal, 'imageGenerated':True,
    'productionInstalled':False, 'newMovementCertified':False,
    'outputs':{p.name:sha(p) for p in OUT.glob('*') if p.suffix in ['.svg','.png']}}
assert equal, 'Pixels outside the registered edit crop changed'
(D/'upper-abdomen-generation.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'output':str(OUT),'visibleEdges':len(record['visibleEdgeIds']),'outsideCropPixelIdentical':equal},ensure_ascii=False))
