"""Compose an opt-in gastric battlefield from GPT paint and fixed geometry."""
from pathlib import Path
import base64
import hashlib
import json
import sys
import cffi
import numpy as np  # load host-compatible extensions before SVG helper path
from PIL import Image
sys.path.insert(0, '/tmp/reference-map-tools')
import cairosvg
sys.path.insert(0, '/tmp/passage-tools314')
from shapely.geometry import Polygon, LineString, box, Point
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parents[2]
D = ROOT/'docs/body-life/vascular-art-study'
OUT = D/'final-stomach-output'
OUT.mkdir(exist_ok=True)
A = ROOT/'assets/image/anatomy-reference/vascular-study/stomach-015'
data = json.loads((D/'final-reference-data.json').read_text())
reg = json.loads((D/'final-stomach-inputs/registration.json').read_text())
sha = lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert reg['finalReferenceSha256'] == sha(D/'final-reference-data.json')
path = lambda ps:'M '+' L '.join(' '.join(f'{v:.6f}' for v in p) for p in ps)
def rings(g):
    ps = [g] if g.geom_type == 'Polygon' else list(g.geoms)
    return [{'outer':list(p.exterior.coords), 'holes':[list(r.coords) for r in p.interiors]} for p in ps if not p.is_empty]
def geom_path(g):
    return ' '.join(path(p['outer'])+' Z '+' '.join(path(r)+' Z' for r in p['holes']) for p in rings(g))
stomach = next(o for o in data['organs'] if o['id'] == 'stomach')
organ = unary_union([Polygon(p['points']) for p in stomach['outlines']])
food_geoms = [Polygon(ps) for ps in data['stomachFoodUnion']]
food_passages = [p for p in data['protectedPassages'] if p['id'] in ['food.esophagus','food.stomach','food.duodenum']]
food_geoms += [LineString(p['points']).buffer(p['width']/2,quad_segs=12) for p in food_passages]
food = unary_union(food_geoms)
tissue = organ.difference(food)
region = box(464,461,644,641)
scope = organ.union(food.intersection(region))
local = [e for e in data['edges'] if LineString(e['samples']).buffer(e['lumenWidthSource']/2).intersects(scope)]
palette = {'artery':('#7e4544','#a9655c'), 'vein':('#415e75','#63869d'), 'capillary':('#695969','#97808c')}
def encoded(p):return base64.b64encode(p.read_bytes()).decode()
defs_parts = ['<defs><clipPath id="gastric-paint"><path d="'+geom_path(tissue)+'" clip-rule="evenodd"/></clipPath><clipPath id="gastric-scope"><path d="'+geom_path(scope)+'" clip-rule="evenodd"/></clipPath>']
layers = ['<g id="gastric-closeup">', '<path data-organ="stomach" d="'+geom_path(organ)+'" fill="#ac857c"/>',
    '<g clip-path="url(#gastric-paint)"><g opacity=".40"><image href="data:image/png;base64,'+encoded(A/'gpt-quiet-wall-v1.png')+'" x="464" y="461" width="180" height="180"/></g></g>',
    '<g clip-path="url(#gastric-scope)"><path data-food="protected-food-union" d="'+geom_path(food)+'" fill="#bca584" fill-rule="evenodd" stroke="#8c745b" stroke-width=".65"/>',
    '<g id="gastric-vessels">']
visible = []
for e in sorted(local,key=lambda e:e['layer']):
    for i,ps in enumerate(e['visibleSegments']):
        # Clipping excludes the complete protected food footprint, including
        # esophagus. Blood continues on an independent logical layer below.
        shown = LineString(ps).intersection(tissue)
        pieces = [shown] if shown.geom_type=='LineString' else [g for g in getattr(shown,'geoms',[]) if g.geom_type=='LineString']
        for j,p in enumerate(pieces):
            if p.length < .08:continue
            q=list(p.coords)
            stem=f'end-{e["id"].replace(".","-")}-{i}-{j}'
            # Fade only exposure/cutaway ends, never a named blood junction.
            for side,point,along in [('start',q[0],min(p.length/3,1.4)),('end',q[-1],p.length-min(p.length/3,1.4))]:
                fixed=any(Point(point).distance(Point(endpoint))<.015 for endpoint in [e['samples'][0],e['samples'][-1]])
                target=list(p.interpolate(along).coords)[0]
                grad=stem+'-'+side+'-gradient'
                defs_parts.append(f'<linearGradient id="{grad}" gradientUnits="userSpaceOnUse" x1="{point[0]}" y1="{point[1]}" x2="{target[0]}" y2="{target[1]}"><stop offset="0" stop-color="white" stop-opacity="0"/><stop offset="1" stop-color="white"/></linearGradient><mask id="{stem}-{side}" maskUnits="userSpaceOnUse" x="464" y="461" width="180" height="180"><rect x="464" y="461" width="180" height="180" fill="{('white' if fixed else 'url(#'+grad+')')}"/></mask>')
            short=p.length<e['lumenWidthSource']*2.4
            visible.append({'edgeId':e['id'],'piece':i,'part':j,'points':q,'width':e['lumenWidthSource'],'system':e['system'],'quietDepthHint':short})
            layers.append(f'<g data-edge="{e["id"]}" data-piece="{i}" data-part="{j}" opacity="{.12 if short else 1}"><g mask="url(#{stem}-start)"><g mask="url(#{stem}-end)">')
            for c,s in [(palette[e['system']][0],1),(palette[e['system']][1],.70)]:
                layers.append(f'<path d="{path(q)}" fill="none" stroke="{c}" stroke-width="{e["lumenWidthSource"]*s}" stroke-linecap="butt" stroke-linejoin="round"/>')
            layers.append('</g></g></g>')
layers.append('</g></g>')
# Vessel wall opening is an actual short perpendicular channel from the pipe
# to tissue, not a hole in the stomach's outer edge or an entry to food.
layers.append('<g id="fixed-gastric-openings" clip-path="url(#gastric-paint)">')
for gate in data['gates']:
    ps=[gate['pipeCenterSource'],gate['wallSource'],gate['tissueTargetSource']]
    layers.append(f'<path data-opening="{gate["id"]}" d="{path(ps)}" fill="none" stroke="#786273" stroke-width="1.35" stroke-linecap="round"/>')
    layers.append(f'<path d="{path(ps)}" fill="none" stroke="#b9988c" stroke-width=".78" stroke-linecap="round"/>')
layers.append('</g>')
layers.append('<path data-fixed-outline="stomach" d="'+geom_path(organ)+'" fill="none" stroke="#7f615b" stroke-width=".6"/></g>')
defs=''.join(defs_parts)+'</defs>'
payload = ''.join(layers)
art = {'schema':'final-stomach-art/v1','sourceBox':reg['sourceBox'],
    'sourceSha256':reg['sourceSha256'],'finalReferenceSha256':reg['finalReferenceSha256'],
    'organOutlines':stomach['outlines'],'organBounds':stomach['bounds'],
    'foodRings':rings(food), 'foodScopedRings':rings(food.intersection(scope)), 'tissueRings':rings(tissue), 'scopeRings':rings(scope),
    'foodPath':geom_path(food),'tissuePath':geom_path(tissue),'scopePath':geom_path(scope),
    'localEdgeIds':[e['id'] for e in local], 'visiblePieces':visible,
    'bloodFullPaths':[{'edgeId':e['id'],'points':e['samples'],'width':e['lumenWidthSource']} for e in local],
    'gates':data['gates'],'sourcePixelToLogical':'64 * zoom',
    'gptAssetSha256':sha(A/'gpt-quiet-wall-v1.png'), 'textureOpacity':.40,
    'foodWalkableByTissueCells':False,'productionInstalled':False,
    'navigationEvidence':'final-stomach-navigation-evidence/report.json',
    'nativeEvidence':False,'seamsFullBodyCertified':False}
(D/'final-stomach-art-data.json').write_text(json.dumps(art,ensure_ascii=False,separators=(',',':'))+'\n')
def lua(v):
    if isinstance(v,bool):return str(v).lower()
    if v is None:return 'nil'
    if isinstance(v,(int,float)):return repr(v)
    if isinstance(v,str):return json.dumps(v,ensure_ascii=False)
    if isinstance(v,(list,tuple)):return '{'+','.join(lua(q) for q in v)+'}'
    return '{'+','.join('['+lua(k)+']='+lua(q) for k,q in v.items())+'}'
runtime = {k:art[k] for k in ['sourceBox','sourceSha256','finalReferenceSha256','organOutlines','foodScopedRings','tissueRings','visiblePieces','gates','textureOpacity']}
(ROOT/'scripts/war/FinalStomachArtData.lua').write_text('-- Generated fixed-coordinate study data; not imported by production.\nreturn '+lua(runtime)+'\n')
(OUT/'stomach-layer.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="464 461 180 180" width="1024" height="1024">'+defs+payload+'</svg>')
cairosvg.svg2png(url=str(OUT/'stomach-layer.svg'),output_width=2048,output_height=2048,write_to=str(A/'stomach-layer-v1.png'))
for name,view,size,bg in [('stomach-battlefield','476 469 153 108',(1530,1080),'#bfa796'),
                         ('stomach-registered','350 450 324 216',(1536,1024),None)]:
    base = f'<rect x="350" y="450" width="324" height="216" fill="{bg}"/>' if bg else '<image href="data:image/png;base64,'+encoded(D/'upper-abdomen-output/registered-full-body.png')+'" width="1024" height="1536"/>'
    svg = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{view}" width="{size[0]}" height="{size[1]}">'+defs+base+payload+'</svg>'
    (OUT/(name+'.svg')).write_text(svg)
    cairosvg.svg2png(bytestring=svg.encode(),write_to=str(OUT/(name+'.png')))
shutil_asset = OUT/'gpt-quiet-wall-v1.png'
shutil_asset.write_bytes((A/'gpt-quiet-wall-v1.png').read_bytes())
print(json.dumps({'data':str(D/'final-stomach-art-data.json'),'localEdges':len(local),'visiblePieces':len(visible),'foodPolygons':len(rings(food))},ensure_ascii=False))
