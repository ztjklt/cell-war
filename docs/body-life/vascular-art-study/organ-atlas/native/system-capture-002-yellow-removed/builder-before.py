"""Compose accepted GPT material and the authoritative three-plane geometry.
No refitting, anatomy generation, or collision inference from pixel colors.
"""
from pathlib import Path
import json,hashlib,re,shutil,sys,base64
import cffi
from PIL import Image,ImageOps
sys.path.insert(0,'/tmp/reference-map-tools')
import cairosvg
ROOT=Path(__file__).resolve().parents[2]
DOC=ROOT/'docs/body-life/vascular-art-study'
OUT=DOC/'stomach-playable'
ASSET=ROOT/'assets/image/anatomy-reference/vascular-study/stomach-playable'
ASSET.mkdir(parents=True,exist_ok=True)
D=json.loads((OUT/'layout.json').read_text())
V=json.loads((DOC/'registered-vessels/geometry.json').read_text())
base=(ROOT/'assets/image/anatomy-reference/vascular-study/stomach-terrain-v2/terrain-base-v2.svg').read_text()
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert D['finalReferenceSha256']==sha(DOC/'final-reference-data.json')
# GPT supplies surface material only: its rearranged canvas is never a geometry
# source. A dedicated seamless flat floor is reused inside exact stencils.
material=ASSET/'gpt-flat-floor-v1.png'
patterns=[]
if material.exists():
    encoded=base64.b64encode(material.read_bytes()).decode()
    for name,color,opacity in [('food','#f4d6a0',.55),('artery','#d8878a',.12),('vein','#90b3c0',.10),('capillary','#c89ba7',.12),('wall','#f2b7a3',.18)]:
        patterns.append(f'<pattern id="surface_{name}" patternUnits="userSpaceOnUse" width="16" height="16"><rect width="16" height="16" fill="{color}"/><image width="16" height="16" opacity="{opacity}" href="data:image/png;base64,{encoded}"/></pattern>')
def surface(name,color):return f'url(#surface_{name})'if material.exists()else color
# Exact fixed food plane covers conflicts with generated room paint.
parts=['<defs>'+''.join(patterns)+'<clipPath id="gastricPlayOrgan"><path d="'+D['outerPath']+'" clip-rule="evenodd"/></clipPath></defs><g clip-path="url(#gastricPlayOrgan)">']
parts.append('<path d="'+D['foodPath']+'" fill="'+surface('food','#f4d6a0')+'" fill-rule="evenodd" stroke="#b47671" stroke-width=".28" stroke-linejoin="round"/>')
# Flattened top-down vessel banks, clipped at the food foreground.
parts.append('<defs><clipPath id="gastricPlayTissue"><path d="'+D['tissueWalkablePath']+'" clip-rule="evenodd"/></clipPath></defs>')
palette={'artery':('#d8878a','#9e686f'),'vein':('#90b3c0','#607f97'),'capillary':('#c89ba7','#8b6c80')}
# Blood geometry remains complete below food. Only its visible projection is masked.
foodcut='<defs><mask id="gastricFoodCover"><rect x="464" y="448" width="180" height="180" fill="white"/><path d="'+D['foodPath']+'" fill="black" fill-rule="evenodd"/></mask></defs>'
parts.append(foodcut+'<g mask="url(#gastricFoodCover)">')
for edge in sorted(V['edges'],key=lambda e:(e['layer'],e['id'])):
    fill,ink=palette.get(edge['system'],palette['capillary'])
    parts.append('<path d="'+edge['paintPath']+'" fill="'+surface(edge['system'],fill)+'" stroke="'+ink+'" stroke-width=".18" stroke-linejoin="round"/>')
parts.append('</g>')
# These are the real collision wall banks. Rounded room gaps remain open.
parts.append('<path d="'+D['wallPath']+'" fill="'+surface('wall','#f2b7a3')+'" fill-rule="evenodd" stroke="#a76c69" stroke-width=".18" stroke-linejoin="round"/>')
# Explicit blood/tissue apertures are visible, and never open the food wall.
for gate in D['gates']+D['localGates']:
    pts=[gate['pipeCenterSource'],gate['wallSource'],gate['tissueTargetSource']]
    path='M '+' L '.join(f'{x:.6f} {y:.6f}'for x,y in pts)
    parts.append('<path d="'+path+'" fill="none" stroke="#886e81" stroke-width="1.42" stroke-linecap="round"/><path d="'+path+'" fill="none" stroke="#e4bda7" stroke-width="1.06" stroke-linecap="round"/>')
parts.append('</g>')
svg=base.replace('</svg>',''.join(parts)+'</svg>')
(ASSET/'battlefield.svg').write_text(svg)
cairosvg.svg2png(bytestring=svg.encode(),write_to=str(ASSET/'battlefield.png'))
shutil.copy2(ASSET/'battlefield.png',OUT/'battlefield.png')
meta={'schema':'gastric-play-art/v1','sourceBox':[464,448,644,628], 'approvedSourceSha256':D['approvedArtSha256'],'layoutSha256':sha(OUT/'layout.json'),'assetSha256':sha(ASSET/'battlefield.png'),'resource':'image/anatomy-reference/vascular-study/stomach-playable/battlefield.png','foodIsCellTerrain':False,'roomCount':6,'gateCount':5,'nativeEvidence':False}
meta['materialSourceSha256']=sha(material)if material.exists()else None
meta['materialUsage']='GPT dedicated seamless flat floor texture only; approved surrounding pixels, authored geometry and apertures are retained by deterministic SVG stencils.'
(OUT/'art.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(meta))
