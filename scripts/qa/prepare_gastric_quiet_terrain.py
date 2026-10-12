"""Make fixed-coordinate inputs for a new gentle gastric RTS terrain asset.

The GPT raster supplies wall material. Source contour, food, blood and door
ownership stay in the renderer; generated pixels are never collision geometry.
"""
from pathlib import Path
import base64, hashlib, json, sys
import cffi, numpy as np
from PIL import Image
sys.path.insert(0, '/tmp/reference-map-tools')
import cairosvg
sys.path.insert(0, '/tmp/passage-tools314')
from shapely.geometry import Polygon, LineString, box
from shapely.ops import unary_union

ROOT=Path(__file__).resolve().parents[2]
D=ROOT/'docs/body-life/vascular-art-study'
OUT=D/'stomach-terrain-v1';OUT.mkdir(exist_ok=True)
A=ROOT/'assets/image/anatomy-reference/vascular-study/stomach-terrain-v1';A.mkdir(exist_ok=True)
SOURCE=ROOT/'assets/image/anatomy-reference/reference.png'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
data=json.loads((D/'final-reference-data.json').read_text())
assert sha(SOURCE)==data['referenceSha256']
stomach=next(o for o in data['organs']if o['id']=='stomach')
organ=unary_union([Polygon(p['points'])for p in stomach['outlines']])
food=unary_union([Polygon(p)for p in data['stomachFoodUnion']]+[LineString(p['points']).buffer(p['width']/2,quad_segs=12)for p in data['protectedPassages']if p['id']in['food.esophagus','food.stomach','food.duodenum']])
BOX=[464,461,644,641]
def rings(g):
    ps=[g]if g.geom_type=='Polygon'else list(g.geoms)
    return [{'outer':[list(p)for p in q.exterior.coords],'holes':[[list(p)for p in h.coords]for h in q.interiors]}for q in ps if q.geom_type=='Polygon'and not q.is_empty]
def path(g):
    ring=lambda ps:'M '+' L '.join(' '.join(f'{v:.6f}'for v in p)for p in ps)+' Z'
    return ' '.join(ring(q['outer'])+' '+' '.join(ring(h)for h in q['holes'])for q in rings(g))
organ_path=path(organ);food_path=path(food);tissue=organ.difference(food)
head='<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="464 461 180 180">'
original=head+'<image href="data:image/png;base64,'+base64.b64encode(SOURCE.read_bytes()).decode()+'" width="1024" height="1536"/></svg>'
# Keep this a native geometry guide, not a substituted final raster.
guide=head+'<rect x="464" y="461" width="180" height="180" fill="#ded1c0"/><defs><clipPath id="organ"><path d="'+organ_path+'"/></clipPath></defs><path d="'+organ_path+'" fill="#d9ae9b" stroke="#ab796d" stroke-width=".45"/><g clip-path="url(#organ)"><path d="'+food_path+'" fill="#dec59c" stroke="#b49a79" stroke-width=".45"/><path d="M560 489 Q562 499 557 506 M606 503 Q610 512 607 519 M573 558 Q584 561 593 556" fill="none" stroke="#bd8e80" stroke-width=".55" opacity=".18"/></g></svg>'
for name,svg in [('original',original),('guide',guide)]:
    (OUT/(name+'.svg')).write_text(svg)
    cairosvg.svg2png(bytestring=svg.encode(),write_to=str(OUT/(name+'.png')))
record={'schema':'gastric-quiet-terrain-registration/v1','sourceBox':BOX,'sourceSha256':sha(SOURCE),'finalReferenceSha256':sha(D/'final-reference-data.json'),'organBoundaryDataSha256':sha(ROOT/'scripts/war/OrganBoundariesData.lua'),'outerPath':organ_path,'foodPath':food_path,'tissuePath':path(tissue),'outerRings':rings(organ),'foodRings':rings(food),'tissueRings':rings(tissue),'gates':data['gates'],'organBounds':list(organ.bounds),'outerAreaSource2':organ.area,'tissueAreaBeforeBloodSource2':tissue.area,'tissueFractionBeforeBlood':tissue.area/organ.area,'worldTransform':{'scale':2,'offsetY':512},'logicalPixelsPerSource':'64 * zoom','productionInstalled':False,'nativeEvidence':False}
(OUT/'registration.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
prompt='''Use case: stylized-concept. Asset: an actual gentle top-down stomach WALL terrain painting for an immune-cell RTS game at a close map zoom, not a medical image or a biology photograph.
Input image 1 is the fixed-coordinate edit target / terrain guide. Input image 2 is only a reference for the original friendly cartoon anatomy colors and softness. Edit image 1, preserving its square framing and the stomach silhouette, orientation, proportions and tan food corridor exactly. The narrow tan corridor has an incoming branch and an outgoing branch; it is food passage, not blood or walkable tissue.
Paint the large peach/salmon wall-tissue fields as broad, smooth, FLAT walkable ground. Approximately 70 percent of the organ is quiet tissue ground. The eye should mostly see open empty surfaces for tiny game cells to travel and fight. Give the wall a very soft organic skin material through wide low-contrast painted color variation and at most 2–3 large, shallow, barely visible crease arcs close to the rim. The crease arcs are printed color on flat tissue, not raised ridges, cliffs or obstacles. Keep the central ground especially empty. Rounded gentle edges, lightly cute educational-game illustration, no faces or characters. Calm dusty peach and warm tan, low saturation, soft diffuse lighting and very restrained shading; preserve the original warm palette while reducing glare. Clearly readable soft outer rim, but no thick black outline and no bright shiny white streaks.
Do not make a hollow gastric cavity: this map represents the cut surface of flat stomach WALL tissue beside a separately bounded food lumen. The tan food corridor stays continuous and visually separate, clean and smooth, without contents, particles, teeth or holes. Do not connect food to blood. Keep all regions at their exact guide positions. Paint only gentle material and broad shading; no new anatomy, no reshaping or extra landmarks.
Do not add ANY blood vessels, capillaries, route lines, cells, UI, labels, text, arrows, grid, doors or symbols; the locked blood network and small cell sprites will be composited at authoritative source coordinates separately. No dense rugae, folds packed across the center, cellular speckles, cobblestones, grains, pores, branching fibers, coral, tentacles, wrinkles, wet flesh, gore, exposed meat, horror, photorealistic viscera, Cthulhu, metallic/plastic tubes or dramatic lighting. No high-frequency texture. One square game-art canvas, not a diagram sheet or a presentation.'''
(OUT/'prompt.txt').write_text(prompt+'\n')
print(json.dumps({'inputGuide':str(OUT/'guide.png'),'styleReference':str(OUT/'original.png'),'registration':str(OUT/'registration.json'),'usableBeforeBlood':record['tissueFractionBeforeBlood']},ensure_ascii=False))
