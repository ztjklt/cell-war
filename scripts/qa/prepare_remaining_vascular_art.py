"""Registered reference compositions for GPT edits of the remaining trunk vessels."""
from pathlib import Path
import base64
import hashlib
import json
import sys
import cffi
from PIL import Image
sys.path.insert(0,'/tmp/reference-map-tools')
import cairosvg

ROOT=Path(__file__).resolve().parents[2]
D=ROOT/'docs/body-life/vascular-art-study'
OUT=D/'remaining-vessels-inputs';OUT.mkdir(exist_ok=True)
source=ROOT/'assets/image/anatomy-reference/reference.png'
data=json.loads((D/'final-reference-data.json').read_text())
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(source)==data['referenceSha256']
encoded=base64.b64encode(source.read_bytes()).decode()
path=lambda ps:'M '+' L '.join(' '.join(f'{v:.5f}'for v in p)for p in ps)
palette={'artery':'#dc5549','vein':'#388fcc','capillary':'#956f97'}
regions={'chest':[333,250,693,490],'lower-abdomen':[350,628,674,844]}
all_records=[]
for name,box in regions.items():
    x,y,x1,y1=box;w,h=x1-x,y1-y
    inside=lambda p:x<=p[0]<=x1 and y<=p[1]<=y1
    edges=[e for e in data['edges'] if e['id']not in data['protectedEdges'] and any(inside(p)for p in e['samples'])]
    start=f'<svg xmlns="http://www.w3.org/2000/svg" width="{w*4}" height="{h*4}" viewBox="{x} {y} {w} {h}"><rect x="{x}" y="{y}" width="{w}" height="{h}" fill="white"/>'
    image=lambda alpha:f'<image href="data:image/png;base64,{encoded}" width="1024" height="1536" opacity="{alpha}"/>'
    guide=[start,image(.38)]
    for e in sorted(edges,key=lambda e:e['layer']):
        for i,ps in enumerate(e['visibleSegments']):
            guide.append(f'<path data-edge="{e["id"]}" data-piece="{i}" d="{path(ps)}" stroke="{palette[e["system"]]}" fill="none" stroke-width="{e["lumenWidthSource"]}" stroke-linecap="round" stroke-linejoin="round"/>')
    technical=guide.copy()
    ids={e['id']for e in edges}
    for hseg in data['occlusions']:
        if hseg['edgeId']in ids and any(inside(p)for p in hseg['points']):
            technical.append(f'<path d="{path(hseg["points"])}" stroke="#465663" fill="none" stroke-width=".55" stroke-dasharray="2 2" opacity=".68"/>')
    for p in data['ports']:
        if p['role']in ('supply','return') and inside(p['source']):
            px,py=p['source'];technical.append(f'<circle cx="{px}" cy="{py}" r="1.5" fill="#eae3b3" stroke="#617868" stroke-width=".65"/>')
    for label,svg in [('original',start+image(1)+'</svg>'),('visible-guide','\n'.join(guide)+ '</svg>'),('depth-guide','\n'.join(technical)+'</svg>')]:
        (OUT/f'{name}-{label}.svg').write_text(svg)
        cairosvg.svg2png(bytestring=svg.encode(),write_to=str(OUT/f'{name}-{label}.png'))
    record={'region':name,'sourceBox':box,'rasterSize':[w*4,h*4],'editableEdgeIds':[e['id']for e in edges],
            'sourceSha256':sha(source),'finalReferenceSha256':sha(D/'final-reference-data.json'),
            'protectedHeadAndLimbEdgesExcluded':True,'imageGenerated':False}
    all_records.append(record)
(OUT/'registration.json').write_text(json.dumps(all_records,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'regions':[(r['region'],len(r['editableEdgeIds']))for r in all_records]},ensure_ascii=False))
