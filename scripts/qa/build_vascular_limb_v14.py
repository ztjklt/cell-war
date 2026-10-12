"""Independent v14 elbow/forearm art candidate with smooth authored masks.

No raster is edited and no graph coordinate is changed. This deliberately starts
from v10 rather than treating the incomplete v13 limb work as a finished base.
"""
from pathlib import Path
import base64
import hashlib
import json
import math
import shutil
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[2]
ASSET=ROOT/'assets/image/anatomy-reference/vascular-study'
DOC=ROOT/'docs/body-life/vascular-art-study'
PUB=ROOT/'docs/body-life/previews/visible-life/vascular-art-study'
raw=(DOC/'network.json').read_bytes()
network=json.loads(raw)
nodes={n['id']:n for n in network['nodes']}
edges={e['id']:e for e in network['edges']}
selected_ids=['e018','e019','e020','e068','e069','e070']
selected={key:edges[key] for key in selected_ids}

def image(name):
    data=base64.b64encode((ASSET/name).read_bytes()).decode()
    return f'<image width="1024" height="1536" href="data:image/png;base64,{data}"/>'

def path(points):
    return 'M'+' L'.join(f'{x:.4f},{y:.4f}' for x,y in points)

# One continuous tissue patch per forearm, hand-authored against the source.
# Its outside edge stays inside the body silhouette; the proximal/distal limits
# are separately reviewed seams, not newly invented graph endpoints.
region='M294 502 C301 499 314 501 320 512 C321 530 323 541 327 552 C332 579 322 603 309 625 C293 651 277 675 266 699 C258 713 253 728 248 743 Q234 751 219 743 Q214 738 219 726 C229 705 230 681 234 652 C236 628 239 606 249 585 C258 567 269 550 278 533 C284 519 285 510 294 502 Z'
bone_elbow='M283 542 C289 538 300 537 306 544 C312 548 313 556 309 563 C306 570 299 574 292 573 C283 573 279 568 278 561 C275 553 277 547 283 542 Z'
bone_forearm='M284 578 C282 598 272 620 264 642 C257 664 246 692 236 717 L240 718 C250 695 260 668 268 644 C275 623 286 600 288 580 Z'
bone_wrist='M223 723 C227 718 237 717 243 722 C249 727 247 738 243 743 C240 749 233 749 225 745 C218 742 217 730 223 723 Z'
symmetries=['','translate(1018 0) scale(-1 1)']

defs=['<defs><filter id="v14-edge-feather" x="-5%" y="-3%" width="110%" height="106%"><feGaussianBlur stdDeviation=".65"/></filter>',
      '<clipPath id="v14-tissue-clip">']
for transform in symmetries:
    defs.append(f'<path d="{region}" transform="{transform}"/>')
defs+=['</clipPath><mask id="v14-tissue-mask" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1536"><rect width="1024" height="1536" fill="black"/>']
for transform in symmetries:
    defs.append(f'<path d="{region}" transform="{transform}" fill="white" filter="url(#v14-edge-feather)"/>')
defs+=['</mask><clipPath id="v14-bone-front">']
for transform in symmetries:
    for d in [bone_elbow,bone_forearm,bone_wrist]:defs.append(f'<path d="{d}" transform="{transform}"/>')
defs+=['</clipPath>']

crossings=[c for c in network['geometry']['crossings'] if c['over'] in selected and c['under'] in selected and 502<=c['point'][1]<=747]
for i,c in enumerate(crossings):
    x,y=c['point']
    defs.append(f'<clipPath id="v14-cross-{i}"><circle cx="{x}" cy="{y}" r="10"/></clipPath>')
for eid in selected_ids:
    defs.append(f'<mask id="v14-under-{eid}" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1536"><rect width="1024" height="1536" fill="white"/>')
    for i,c in enumerate(crossings):
        if c['under']==eid:
            defs.append(f'<path clip-path="url(#v14-cross-{i})" d="{path(edges[c["over"]]["points"])}" fill="none" stroke="black" stroke-width="3.6" stroke-linecap="round" stroke-linejoin="round"/>')
    defs+=['</mask>']
defs+=['</defs>']

layers=['<g id="limb-revision-v14">',''.join(defs),'<g mask="url(#v14-tissue-mask)">',image('limbs-muscle-underlay.png'),'</g><g clip-path="url(#v14-tissue-clip)">']
palette={'artery':('#963b37','#d8544d','#f3a18b'),'vein':('#38566f','#428cba','#abd2df')}
for eid,e in sorted(selected.items(),key=lambda pair:pair[1]['drawOrder']):
    assert abs(e['renderingWidthSource']-2.2)<.001
    for point,key in [(e['points'][0],e['a']),(e['points'][-1],e['b'])]:
        assert math.dist(point,[nodes[key]['x'],nodes[key]['y']])<.001,(eid,key)
    dark,mid,light=palette[e['kind']]
    layers.append(f'<g data-edge="{eid}" fill="none" mask="url(#v14-under-{eid})" stroke-linecap="round" stroke-linejoin="round">')
    for color,width,opacity in [(dark,2.8,.95),(mid,2.2,1),(light,.48,.45)]:
        layers.append(f'<path d="{path(e["points"])}" stroke="{color}" stroke-width="{width}" stroke-opacity="{opacity}"/>')
    layers.append('</g>')
layers+=['</g><g clip-path="url(#v14-bone-front)">',image('overview-v2.png'),'</g></g>']
base=(ASSET/'overview-v10-layered.svg').read_text().rstrip()
assert base.endswith('</svg>')
result=base[:-6]+''.join(layers)+'</svg>\n'
root=ET.fromstring(result)
ids=[e.get('id') for e in root.iter() if e.get('id')]
assert len(ids)==len(set(ids))
(ASSET/'overview-v14-layered.svg').write_text(result)
(DOC/'candidate-v14.svg').write_text(result)
record={
    'version':14,'status':'ELBOW_FOREARM_ART_CANDIDATE_BROWSER_REVIEW_REQUIRED',
    'base':'overview-v10-layered.svg','scope':'Bilateral elbows and continuous forearms; other limb art remains v10.',
    'sourceNetworkSha256':hashlib.sha256(raw).hexdigest(),
    'underlaySha256':hashlib.sha256((ASSET/'limbs-muscle-underlay.png').read_bytes()).hexdigest(),
    'maskPolicy':'Hand-authored continuous cubic curves; no raster color thresholds or pixel contours.',
    'transitionPolicy':'0.65 source-pixel soft tissue edge; original body outline remains outside repair curve.',
    'bonePolicy':'Source v2 raster restored through manually smoothed elbow, forearm-shaft and wrist curves.',
    'vesselPolicy':'Exact reviewed edge point arrays; 2.2 fill + 0.6 outline, overpass mask width 3.6.',
    'selectedEdgeIds':selected_ids,'crossings':crossings,
    'endpointCheck':'PASS','svgIdUniqueness':'PASS','coordinatesChanged':False,'runtimeModified':False,
    'defaultPageChanged':False,'visualReview':'PENDING_CUA',
    'limitations':['Smooth bone curves are authored visual masks, not verified collision silhouettes.',
      'Proximal y502 and wrist seams still need browser inspection against older raster vessel positions.',
      'The inner forearm tissue is replaced continuously with GPT artwork and requires style/shape review.',
      'This does not certify upper arms, legs, hands or feet and does not integrate runtime movement.'],
}
(DOC/'limb-review-v14.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
PUB.mkdir(exist_ok=True)
for name in ['candidate-v14.svg','limb-review-v14.json']:shutil.copy2(DOC/name,PUB/name)
print(json.dumps({'asset':str(ASSET/'overview-v14-layered.svg'),'edges':len(selected),'crossings':len(crossings),'endpointCheck':'PASS'}))
