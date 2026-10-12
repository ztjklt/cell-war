"""Add bounded limb corrections to the reviewed v10 editable art study.

The graph is immutable. Raster inputs are embedded unchanged; cleanup is an SVG
display composition, not an edited bitmap. This is not a gameplay integration.
"""
from pathlib import Path
import base64
import hashlib
import json
import math
import shutil
import cv2
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
ASSET = ROOT / 'assets/image/anatomy-reference/vascular-study'
DOC = ROOT / 'docs/body-life/vascular-art-study'
PUB = ROOT / 'docs/body-life/previews/visible-life/vascular-art-study'
network_bytes = (DOC / 'network.json').read_bytes()
network = json.loads(network_bytes)
edges = {e['id']: e for e in network['edges']}
nodes = {n['id']: n for n in network['nodes']}

# Local repair windows deliberately exclude the generated upper-arm/thigh bones.
# Rectangles are not extraction masks: only the relevant vessel corridors inside
# them receive the generated cleanup image.
regions = {
    'elbow_r': [268, 510, 321, 612], 'elbow_l': [694, 510, 749, 612],
    'wrist_hand_r': [171, 715, 252, 822], 'wrist_hand_l': [763, 715, 847, 822],
    'knee_r': [385, 964, 446, 1045], 'knee_l': [565, 964, 634, 1045],
    'ankle_r': [380, 1285, 427, 1372], 'ankle_l': [585, 1285, 634, 1372],
    'foot_r': [337, 1368, 417, 1450], 'foot_l': [604, 1368, 682, 1450],
    'calf_overlap_r': [386, 1197, 409, 1286],
}
# The all-muscle working underlay is sampled only inside source blood footprints;
# original bone pixels are always restored separately in front.
cleanup_sources={k:'limbs-muscle-underlay.png' for k in regions}

def path(points):
    return 'M' + ' L'.join(f'{x:.4f},{y:.4f}' for x,y in points)

def image(name):
    data = base64.b64encode((ASSET/name).read_bytes()).decode()
    return f'<image width="1024" height="1536" href="data:image/png;base64,{data}"/>'

def rect(box):
    x,y,x1,y1=box
    return f'<rect x="{x}" y="{y}" width="{x1-x}" height="{y1-y}"/>'

def intersects(e):
    for a,b in zip(e['points'],e['points'][1:]):
        for x,y,x1,y1 in regions.values():
            if min(a[0],b[0])<=x1 and max(a[0],b[0])>=x and min(a[1],b[1])<=y1 and max(a[1],b[1])>=y:
                return True
    return False

selected = {k:e for k,e in edges.items() if e['group']=='limbs' and intersects(e)}
# Preserve exact polygonal centerlines, including every authored endpoint.
for eid,e in selected.items():
    for point,key in [(e['points'][0],e['a']),(e['points'][-1],e['b'])]:
        assert math.dist(point,(nodes[key]['x'],nodes[key]['y']))<.001,(eid,key)

def width(e):
    # Thin finger/toe branches remain legible without filling the palm/foot.
    small = '.finger' in e['a'] or '.finger' in e['b'] or '.toe' in e['a'] or '.toe' in e['b']
    return 1.2 if small else float(e.get('renderingWidthSource',2.2))

def outline(e):
    return .4 if width(e)==1.2 else .6

crossings=[]
seen=set()
for c in network['geometry']['crossings']:
    if c['under'] not in selected or c['over'] not in selected:
        continue
    # Duplicate near-identical crossings use a single mask intersection.
    key=(c['under'],c['over'],round(c['point'][0],1),round(c['point'][1],1))
    if key not in seen:
        seen.add(key);crossings.append(c)

def color_contours(kind):
    """Trace display masks from source colors; never write a modified raster."""
    pixels=cv2.imread(str(ASSET/'overview-v2.png'))
    b,g,r=[pixels[:,:,i].astype(float) for i in range(3)]
    if kind=='blood':
        wanted=((b>r*1.05)&(b>g*.94)&(b>85))|((r>155)&(g<86)&(r>g*2.3)&(r-b>70))
    else:
        wanted=(r>178)&(g>168)&(r-g<35)&(g-b>12)&(b>100)
    mask=np.zeros(pixels.shape[:2],np.uint8)
    for x,y,x1,y1 in regions.values():mask[y:y1,x:x1]=wanted[y:y1,x:x1].astype(np.uint8)*255
    mask=cv2.dilate(mask,np.ones((3,3),np.uint8),iterations=1)
    contours,_=cv2.findContours(mask,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE)
    output=[]
    for c in contours:
        if cv2.contourArea(c)<3:continue
        c=cv2.approxPolyDP(c,.35,True)
        output.append(path([p[0].tolist() for p in c])+' Z')
    return output

blood_contours=color_contours('blood')
bone_contours=color_contours('bone')
defs=['<defs><clipPath id="limbRepairWindows">',*(rect(b) for b in regions.values()),'</clipPath>']
for name,box in regions.items():defs.append(f'<clipPath id="limbRegion-{name}">{rect(box)}</clipPath>')
# Use narrow corridors around reviewed routes; a little extra cleanup is needed
# at old raster fork locations, whose paths predate the graph.
defs+=['<clipPath id="limbCleanup">']
for d in blood_contours:
    defs.append(f'<path d="{d}" fill="white"/>')
defs.append('</clipPath>')

# A union of the actual OVER strokes cuts the UNDER edge. The cutting stroke
# includes the upper outline plus 0.8 source-pixel clearance; duplicate crossings
# share the same black mask, so overlap cannot darken or double-cut the image.
for i,c in enumerate(crossings):
    x,y=c['point']
    defs.append(f'<clipPath id="limbCross{i}"><circle cx="{x}" cy="{y}" r="10"/></clipPath>')
for eid in selected:
    cuts=[(i,c) for i,c in enumerate(crossings) if c['under']==eid]
    defs.append(f'<mask id="limbUnder-{eid}" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1536"><rect width="1024" height="1536" fill="white"/>')
    for i,c in cuts:
        over=selected[c['over']]
        defs.append(f'<path clip-path="url(#limbCross{i})" d="{path(over["points"])}" fill="none" stroke="black" stroke-width="{width(over)+outline(over)+.8}" stroke-linecap="round" stroke-linejoin="round"/>')
    defs.append('</mask>')

# Source-color bone caps preserve the original joint illustrations.
defs+=['<clipPath id="limbJointFront">',*(f'<path d="{d}"/>' for d in bone_contours),'</clipPath>']
# Toe fan crossovers at y1430..1445 are a hidden deep bed, not a tangle of visible
# capillary junctions. This affects only display, never points/edges/movement.
defs+=['<mask id="limbDeepFan" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1536"><rect width="1024" height="1536" fill="white"/><rect x="339" y="1426" width="77" height="24" rx="9" fill="black"/><rect x="604" y="1426" width="77" height="24" rx="9" fill="black"/></mask></defs>']

source_ids={name:'limb-clean-source-'+str(i) for i,name in enumerate(sorted(set(cleanup_sources.values())))}
defs+=['<defs>']+[f'<g id="{source_ids[name]}">{image(name)}</g>' for name in source_ids]+['</defs>']

layers=['<g id="limb-revision-v13">',''.join(defs),'<g clip-path="url(#limbRepairWindows)"><g clip-path="url(#limbCleanup)">']
for name,source in cleanup_sources.items():
    layers += [f'<g clip-path="url(#limbRegion-{name})">',f'<use href="#{source_ids[source]}"/>','</g>']
layers += ['</g><g mask="url(#limbDeepFan)">']
palette={'artery':('#963b37','#d8544d','#f3a18b'),'vein':('#38566f','#428cba','#abd2df'),'exchange':('#796274','#b08999','#d7b3bd')}
for eid,e in sorted(selected.items(),key=lambda pair:pair[1]['drawOrder']):
    dark,mid,light=palette.get(e['kind'],palette['exchange'])
    w=width(e)
    layers.append(f'<g data-edge="{eid}" mask="url(#limbUnder-{eid})" fill="none" stroke-linecap="round" stroke-linejoin="round">')
    for color,sw,opacity in [(dark,w+outline(e),.95),(mid,w,1),(light,w*.22,.45)]:
        layers.append(f'<path d="{path(e["points"])}" stroke="{color}" stroke-width="{sw}" stroke-opacity="{opacity}"/>')
    layers.append('</g>')
layers+=['</g></g><g clip-path="url(#limbJointFront)">',image('overview-v2.png'),'</g></g>']
base=(ASSET/'overview-v10-layered.svg').read_text()
assert base.rstrip().endswith('</svg>')
result=base.rstrip()[:-6]+'\n'+''.join(layers)+'\n</svg>\n'
(ASSET/'overview-v13-layered.svg').write_text(result)
(DOC/'candidate-v13.svg').write_text(result)
record={
    'status':'BOUNDED_LIMB_ART_STUDY_NOT_RUNTIME','base':'overview-v10-layered.svg',
    'sourceNetworkSha256':hashlib.sha256(network_bytes).hexdigest(),
    'cleanupSha256':{name:hashlib.sha256((ASSET/name).read_bytes()).hexdigest() for name in set(cleanup_sources.values())},
    'cleanupSourcesByRegion':cleanup_sources,
    'regions':regions,'selectedEdgeIds':list(selected),'crossingCountAfterDeduplication':len(crossings),
    'endpointCheck':'PASS','graphChanged':False,'runtimeModified':False,
    'crossingRule':'Lower path masked by actual upper stroke plus outline and 0.8 source-pixel clearance, locally clipped; masks union duplicate overlaps.',
    'displayWidths':{'mainFill':2.2,'mainOutlineAddition':.6,'fingerToeFill':1.2,'fingerToeOutlineAddition':.4,'maskClearanceAddition':.8},
    'jointRule':'Original v2 bone raster restored inside source-color traced foreground masks.',
    'cleanupRule':'Source blood-color contours clipped to repair windows; raster inputs never modified.',
    'deepFanRule':'Crowded toe fan is hidden; graph and edge arc lengths remain continuous.',
    'limitations':['Upper arms, thighs and most calf raster remain unchanged outside bounded repair windows.',
      'Clipped patch-to-old-raster joins are visual candidates; raster routes are not graph-certified.',
      'Source-color bone masks are display masks, not collision boundaries or complete bone segmentation.',
      'Full near-view battlefield hand/toe expansion, runtime cell clearance and native zoom transition remain unverified.'],
    'visualReview':'V13_BROWSER_REVIEW_PENDING',
    'offlineEvidence':'candidate-v12-offline.png (previous version; not width-fix evidence)',
    'offlineRendererLimitation':'CairoSVG does not apply luminance masks correctly; abdominal overlays, crossovers and deep toe fan in this PNG are not reliable final appearance evidence.',
    'remainingVisualRisks':['All-muscle working underlay is constrained to old blood footprints; patch boundaries still require browser review.',
      'Bone foreground uses source-color contours and has not been certified as a complete segmentation.',
      'This candidate is not certified as a final full-body vascular illustration.'],
}
(DOC/'limb-review.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
PUB.mkdir(exist_ok=True)
for name in ['candidate-v13.svg','limb-review.json']:
    shutil.copy2(DOC/name,PUB/name)
print(json.dumps({'asset':str(ASSET/'overview-v13-layered.svg'),'edges':len(selected),'crossings':len(crossings),'endpointCheck':'PASS'}))
