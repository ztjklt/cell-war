"""Prepare fixed-coordinate GPT inputs for the 0.15 stomach art study.

The model supplies quiet paint only. All food, organ and blood boundaries
remain editable SVG geometry from the finalized reference.
"""
from pathlib import Path
import base64
import hashlib
import json
import sys
import cffi
from PIL import Image

sys.path.insert(0, '/tmp/reference-map-tools')
import cairosvg

ROOT = Path(__file__).resolve().parents[2]
D = ROOT / 'docs/body-life/vascular-art-study'
OUT = D / 'final-stomach-inputs'
OUT.mkdir(exist_ok=True)
data = json.loads((D / 'final-reference-data.json').read_text())
BOX = [464, 461, 644, 641]
stomach = next(o for o in data['organs'] if o['id'] == 'stomach')
source = ROOT / 'assets/image/anatomy-reference/reference.png'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(source) == data['referenceSha256']
path = lambda ps: 'M ' + ' L '.join(' '.join(f'{v:.6f}' for v in p) for p in ps)
outline = ' '.join(path(p['points']) + ' Z' for p in stomach['outlines'])
food = ' '.join(path(ps) + ' Z' for ps in data['stomachFoodUnion'])
start = '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="464 461 180 180">'
original = start + '<image href="data:image/png;base64,' + base64.b64encode(source.read_bytes()).decode() + '" width="1024" height="1536"/></svg>'
guide = [start, '<rect x="464" y="461" width="180" height="180" fill="#d2b5a1"/>',
    '<defs><clipPath id="organ"><path d="'+outline+'"/></clipPath></defs>',
    '<path d="'+outline+'" fill="#ad857b" stroke="#805f59" stroke-width=".8"/>',
    '<path d="'+food+'" fill="#c5ac87" stroke="#9a8060" stroke-width=".75"/>',
    '<g clip-path="url(#organ)" fill="none" stroke="#89665e" stroke-width=".7" opacity=".28">',
    '<path d="M 558 489 Q 559 500 553 509"/><path d="M 560 517 Q 554 525 558 534"/><path d="M 610 498 Q 615 510 611 518"/></g>']
guide.append('</svg>')
for name, svg in [('original', original), ('quiet-tissue-guide', '\n'.join(guide))]:
    (OUT / (name+'.svg')).write_text(svg)
    cairosvg.svg2png(bytestring=svg.encode(), write_to=str(OUT/(name+'.png')))
record = {'schema':'final-stomach-art-registration/v1', 'sourceBox':BOX,
    'sourceSha256':sha(source), 'finalReferenceSha256':sha(D/'final-reference-data.json'),
    'organOutline':stomach['outlines'], 'foodUnion':data['stomachFoodUnion'],
    'gates':data['gates'], 'worldTransform':{'scale':2,'offsetY':512},
    'displayLogicalPixelsPerSourcePixel':'64 * zoom',
    'exactOutlineAndFoodOwnership':'code-native clip; model paint cannot move a boundary',
    'productionInstalled':False}
(OUT/'registration.json').write_text(json.dumps(record, ensure_ascii=False, indent=2)+'\n')
prompt = '''Edit the first image, a quiet fixed-coordinate game terrain guide, using the second image ONLY for the original cartoon anatomy color and soft illustration style. Return one square image with the SAME framing; do not crop, rotate, move, enlarge, or reshape the stomach or food passages.

Purpose: this is stomach wall tissue terrain for a top-down real-time strategy game where small immune cells move on tissue outside a separate food lumen. It is a gentle game cutaway, not a photograph of an organ, not a medical simulation.

Match the guide's exact muted dusty salmon stomach wall and warm ochre continuous food channel. Paint soft hand-drawn shading and at most THREE large, shallow folds in the wall tissue, like the very faint guide strokes. The wide tissue areas should remain open, smooth, quiet and readable as walkable terrain. Food lumen stays a distinct continuous warm tan corridor, with no teeth or openings into blood. Keep organ silhouettes and neighboring orange duodenum footprint exactly aligned to the guide. Retain the original friendly anatomy-art softness, but use the muted guide palette and subdued broad light. No glossy highlights. No high-frequency cellular or cobblestone texture. No spots, dots, grains, veins, tiny branching patterns, flowers, coral, craters, rough fibers or wet surface.

Do not add ANY blood vessels, routes, door markers, cells, UI, labels, arrows, grid or text: these will be drawn from fixed coordinates separately. The model supplies quiet shading, not topology. No gore, horror, tentacles or Cthulhu-like detail. Single square art canvas, no frame or decorative border.'''
(OUT/'prompt-quiet-tissue.txt').write_text(prompt+'\n')
print(json.dumps({'inputs':str(OUT), 'sourceBox':BOX, 'outlinePoints':len(stomach['outlines'][0]['points'])},ensure_ascii=False))
