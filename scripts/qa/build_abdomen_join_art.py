"""Continue five exposed upper-abdomen curves into a narrow lower band.

The source image and finalized geometry are immutable. GPT repairs only the
old blue pigment selection. This closes the inspected y=666 crop boundary;
it does not certify the remainder of the body's artwork.
"""
from pathlib import Path
import base64
import hashlib
import json
import sys
import cffi
import numpy as np
from PIL import Image
sys.path.insert(0,'/tmp/reference-map-tools')
import cairosvg
sys.path.insert(0,'/tmp/passage-tools314')
from shapely.geometry import Polygon, LineString, box, Point
from shapely.ops import unary_union

ROOT=Path(__file__).resolve().parents[2]
D=ROOT/'docs/body-life/vascular-art-study'
OUT=D/'abdomen-join-output';OUT.mkdir(exist_ok=True)
data=json.loads((D/'final-reference-data.json').read_text())
ids=['e133','e135','e188','e189','e191']
es=[e for e in data['edges'] if e['id'] in ids]
band=[385,646,638,724]
source=ROOT/'assets/image/anatomy-reference/reference.png'
asset=ROOT/'assets/image/anatomy-reference/vascular-study/abdomen-join/gpt-clean-underlay-v1.png'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(source)==data['referenceSha256']
path=lambda ps:'M '+' L '.join(' '.join(f'{v:.6f}' for v in p) for p in ps)
def shape(g):
 ps=[g] if g.geom_type=='Polygon' else list(g.geoms)
 return ' '.join(path(list(p.exterior.coords))+' Z '+' '.join(path(list(r.coords))+' Z' for r in p.interiors) for p in ps if not p.is_empty)
def img(p,b):
 return f'<image href="data:image/png;base64,{base64.b64encode(p.read_bytes()).decode()}" x="{b[0]}" y="{b[1]}" width="{b[2]-b[0]}" height="{b[3]-b[1]}"/>'
src=np.asarray(Image.open(source).convert('RGB'),dtype=np.int16)
r,g,b=[src[:,:,k] for k in range(3)]
blue=(b-r>12)&(g-r>-45)&(b>100)
runs=[]
for y in range(band[1],band[3]):
 xs=np.flatnonzero(blue[y,band[0]:band[2]])+band[0]
 for indices in np.split(xs,np.flatnonzero(np.diff(xs)>1)+1):
  if len(indices):runs.append(box(indices[0]-.5,y-.5,indices[-1]+.5,y+.5))
selection=unary_union(runs).buffer(.9)
protected=unary_union([Polygon(o['outlines'][0]['points']) for o in data['organs'] if o['id'] in ['small_intestine','large_intestine','bladder','kidney_r','kidney_l']])
selection=selection.difference(protected).intersection(box(*band))
# Feather the selected old paint; hard pigment clipping would expose a
# jagged edge between GPT repair color and the original surrounding tissue.
repair_mask=[]
for pad in [3.0,2.2,1.5,.8,0]:
 repair_mask.append('<path d="'+shape(selection.buffer(pad).difference(protected).intersection(box(*band)))+'" fill="white" opacity=".32"/>')
repair_mask.append('<path d="'+shape(selection)+'" fill="white"/>')
defs=['<defs><clipPath id="join-band"><rect x="385" y="646" width="253" height="78"/></clipPath>',
 '<mask id="old-blue-selection" maskUnits="userSpaceOnUse" x="385" y="646" width="253" height="78">'+''.join(repair_mask)+'</mask>',
 '<linearGradient id="join-top-gradient" gradientUnits="userSpaceOnUse" x1="0" y1="646" x2="0" y2="656"><stop offset="0" stop-color="white" stop-opacity="0"/><stop offset="1" stop-color="white"/></linearGradient>',
 '<linearGradient id="join-bottom-gradient" gradientUnits="userSpaceOnUse" x1="0" y1="724" x2="0" y2="714"><stop offset="0" stop-color="white" stop-opacity="0"/><stop offset="1" stop-color="white"/></linearGradient>']
for side in ['top','bottom']:
 defs.append(f'<mask id="join-{side}" maskUnits="userSpaceOnUse" x="385" y="646" width="253" height="78"><rect x="385" y="646" width="253" height="78" fill="url(#join-{side}-gradient)"/></mask>')
pieces=[];paints=[]
palette={'artery':('#98443f','#c45a50'),'vein':('#3a668a','#4a83ae'),'capillary':('#705b76','#8a708b')}
for e in sorted(es,key=lambda e:e['layer']):
 for i,ps in enumerate(e['visibleSegments']):
  if not LineString(ps).intersects(box(*band)):continue
  p=LineString(ps);stem='join-'+e['id']+'-'+str(i)
  fixed=[min(Point(ps[j]).distance(Point(endpoint)) for endpoint in [e['samples'][0],e['samples'][-1]])<.015 for j in [0,-1]]
  named=any(Point(ps[j]).distance(Point(port['source']))<.02 for j in [0,-1] for port in data['ports'] if port['kind']=='named_port')
  short=p.length<e['lumenWidthSource']*2.4 and not named
  for side,k,along in [('start',0,min(p.length/3,1.4)),('end',1,p.length-min(p.length/3,1.4))]:
   q=ps[0 if k==0 else -1];t=list(p.interpolate(along).coords)[0]
   defs.append(f'<linearGradient id="{stem}-{side}-gradient" gradientUnits="userSpaceOnUse" x1="{q[0]}" y1="{q[1]}" x2="{t[0]}" y2="{t[1]}"><stop offset="0" stop-color="white" stop-opacity="0"/><stop offset="1" stop-color="white"/></linearGradient><mask id="{stem}-{side}" maskUnits="userSpaceOnUse" x="350" y="450" width="324" height="300"><rect x="350" y="450" width="324" height="300" fill="{('white' if fixed[k] else 'url(#'+stem+'-'+side+'-gradient)')}"/></mask>')
  paints.append(f'<g data-join-edge="{e["id"]}" data-piece="{i}" opacity="{.12 if short else 1}"><g mask="url(#{stem}-start)"><g mask="url(#{stem}-end)">')
  for c,s in [(palette[e['system']][0],1),(palette[e['system']][1],.8)]:
   paints.append(f'<path d="{path(ps)}" fill="none" stroke="{c}" stroke-width="{e["lumenWidthSource"]*s}" stroke-linecap="butt" stroke-linejoin="round"/>')
  paints.append('</g></g></g>')
  pieces.append({'edgeId':e['id'],'piece':i,'points':ps,'shortDepthHint':short})
defs.append('</defs>')
layers=['<g id="lower-joining-band" clip-path="url(#join-band)"><g mask="url(#join-top)"><g mask="url(#join-bottom)">',
 '<g mask="url(#old-blue-selection)">'+img(asset,[376,624,646,804])+'</g>',*paints,'</g></g></g>']
base=(D/'upper-abdomen-output/registered-full-body.svg').read_text()
combined=base.replace('</svg>',''.join(defs+layers)+'</svg>')
(OUT/'registered-full-body-v2.svg').write_text(combined)
cairosvg.svg2png(bytestring=combined.encode(),write_to=str(OUT/'registered-full-body-v2.png'))
upper=combined.replace('width="1024" height="1536" viewBox="0 0 1024 1536"','width="1296" height="1200" viewBox="350 450 324 300"',1)
(OUT/'abdomen-joined.svg').write_text(upper)
cairosvg.svg2png(bytestring=upper.encode(),write_to=str(OUT/'abdomen-joined.png'))
baseline=np.asarray(Image.open(D/'upper-abdomen-output/registered-full-body.png').convert('RGB'))
trial=np.asarray(Image.open(OUT/'registered-full-body-v2.png').convert('RGB'))
outside=np.ones(baseline.shape[:2],bool);outside[646:724,385:638]=False
assert np.array_equal(baseline[outside],trial[outside])
record={'schema':'abdomen-join-art/v1','sourceSha256':sha(source),'finalReferenceSha256':sha(D/'final-reference-data.json'),
 'priorPilotSha256':sha(D/'upper-abdomen-output/registered-full-body.png'), 'generatedUnderlaySha256':sha(asset),
 'newEditBox':band,'gptSourceBox':[376,624,646,804],'sourceGeometryMoved':False,
 'fixedContinuationEdgeIds':ids,'renderedPieces':pieces,'oldBlueSelectionAreaSource':selection.area,
 'outsideNewBandChangedPixels':0,'brainAndLimbsOriginalPixels':True,'reviewedY666BoundaryContinues':True,
 'fullBodyArtworkComplete':False,'productionInstalled':False,'nativeEvidence':False,
 'outputs':{p.name:sha(p) for p in OUT.glob('*') if p.suffix in ['.svg','.png']}}
(D/'abdomen-join-art-data.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'continued':ids,'pieces':len(pieces),'outsideBandChangedPixels':0},ensure_ascii=False))
