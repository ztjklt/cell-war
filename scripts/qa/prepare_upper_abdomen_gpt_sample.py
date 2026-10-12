"""Create registered SVG/PNG guides for a GPT upper-abdomen art edit.

The raster source is embedded unchanged. These are code-native reference
compositions, not a replacement for GPT artwork or runtime anatomy.
"""
from pathlib import Path
import base64
import hashlib
import json
import sys
import cffi
from PIL import Image, ImageOps  # preload the host's compatible native dependency

sys.path.insert(0, '/tmp/reference-map-tools')
import cairosvg

ROOT = Path(__file__).resolve().parents[2]
D = ROOT / 'docs/body-life/vascular-art-study'
OUT = D / 'upper-abdomen-inputs'
OUT.mkdir(exist_ok=True)
data = json.loads((D / 'final-reference-data.json').read_text())
BOX = [350, 450, 674, 666]
WIDTH, HEIGHT = BOX[2] - BOX[0], BOX[3] - BOX[1]
source = ROOT / 'assets/image/anatomy-reference/reference.png'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(source) == data['referenceSha256']
encoded = base64.b64encode(source.read_bytes()).decode()
image = lambda alpha: f'<image href="data:image/png;base64,{encoded}" width="1024" height="1536" opacity="{alpha}"/>'
path = lambda ps: 'M ' + ' L '.join(' '.join(f'{v:.5f}' for v in p) for p in ps)
inside = lambda p: BOX[0] <= p[0] <= BOX[2] and BOX[1] <= p[1] <= BOX[3]
local = [e for e in data['edges'] if any(inside(p) for p in e['samples'])]
palette = {'artery': '#cb544c', 'vein': '#448ac0', 'capillary': '#8b7094'}
start = f'<svg xmlns="http://www.w3.org/2000/svg" width="1296" height="864" viewBox="350 450 {WIDTH} {HEIGHT}"><rect x="350" y="450" width="{WIDTH}" height="{HEIGHT}" fill="#fff"/>'
art = [start, image(.28)]
for e in sorted(local, key=lambda e: e['layer']):
    for ps in e['visibleSegments']:
        art.append(f'<path data-edge="{e["id"]}" d="{path(ps)}" fill="none" stroke="{palette[e["system"]]}" stroke-width="{e["lumenWidthSource"]}" stroke-linecap="round" stroke-linejoin="round"/>')
art.append('</svg>')
technical = art[:-1]
for h in data['occlusions']:
    if not any(inside(p) for p in h['points']):
        continue
    technical.append(f'<path data-hidden="{h["id"]}" d="{path(h["points"])}" fill="none" stroke="#556376" stroke-width=".55" stroke-dasharray="2 2" opacity=".65"/>')
for g in data['gates']:
    p, q = g['wallSource'], g['tissueTargetSource']
    technical.append(f'<path d="{path([g["pipeCenterSource"],p,q])}" fill="none" stroke="#2e845b" stroke-width=".75"/><circle cx="{p[0]}" cy="{p[1]}" r="1.3" fill="#e6f0d8" stroke="#2e845b" stroke-width=".7"/>')
technical.append('</svg>')
documents = {'original': start + image(1) + '</svg>', 'visible-vessels': '\n'.join(art), 'depth-and-gates': '\n'.join(technical)}
documents['vessels-only'] = '\n'.join([start] + art[2:-1] + ['</svg>'])
for name, svg in documents.items():
    (OUT / (name + '.svg')).write_text(svg)
    cairosvg.svg2png(bytestring=svg.encode(), write_to=str(OUT / (name + '.png')))
record = {'schema': 'upper-abdomen-gpt-inputs/v1', 'sourceSha256': sha(source),
    'finalReferenceSha256': sha(D / 'final-reference-data.json'), 'sourceBox': BOX,
    'sourceSize': [WIDTH, HEIGHT], 'guideRasterSize': [1296,864],
    'sourceToGuide': {'scale': 4, 'offset': [-BOX[0]*4,-BOX[1]*4]},
    'localEdgeIds': [e['id'] for e in local], 'editTarget': 'original.png',
    'visibleReference': 'visible-vessels.png', 'technicalReference': 'depth-and-gates.png',
    'brainAndLimbsIncludedInEdit': False, 'imageGenerated': False}
(OUT / 'registration.json').write_text(json.dumps(record, ensure_ascii=False, indent=2)+'\n')
print(json.dumps({'inputs':str(OUT),'sourceBox':BOX,'localEdges':len(local)},ensure_ascii=False))
