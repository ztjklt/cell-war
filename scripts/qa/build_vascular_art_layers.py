"""Build the editable SVG art study from GPT underlays and reviewed vessel geometry.

Raster assets are read unchanged. Generated patches are clipped in the display
composition; selected blood vessels remain independently editable SVG geometry.
This does not change runtime geometry or publish the study as a game map.
"""
from pathlib import Path
import base64
import hashlib
import json
import math
import shutil

ROOT = Path(__file__).resolve().parents[2]
DOC = ROOT / 'docs/body-life/vascular-art-study'
ASSET = ROOT / 'assets/image/anatomy-reference/vascular-study'
PUB = ROOT / 'docs/body-life/previews/visible-life/vascular-art-study'
network_path = DOC / 'network.json'
network = json.loads(network_path.read_text())
edges = {e['id']: e for e in network['edges']}
outlines = json.loads((DOC / 'occlusion-outlines.json').read_text())

def image(name):
    data = base64.b64encode((ASSET / name).read_bytes()).decode()
    return f'<image width="1024" height="1536" href="data:image/png;base64,{data}"/>'

def path(points):
    return 'M' + ' L'.join(f'{x:.4f},{y:.4f}' for x, y in points)

def rounded_vessel_path(points):
    """Soften interior authoring corners; graph junctions/endpoints never move."""
    commands = [f'M{points[0][0]:.4f},{points[0][1]:.4f}']
    for before, point, after in zip(points, points[1:], points[2:]):
        length_a = math.dist(before, point)
        length_b = math.dist(after, point)
        if min(length_a, length_b) < .001:
            continue
        radius = min(4, length_a / 3, length_b / 3)
        start = [point[i] + (before[i]-point[i])*radius/length_a for i in (0,1)]
        end = [point[i] + (after[i]-point[i])*radius/length_b for i in (0,1)]
        commands.append(f'L{start[0]:.4f},{start[1]:.4f} Q{point[0]:.4f},{point[1]:.4f} {end[0]:.4f},{end[1]:.4f}')
        # Sample the rendered quadratic against the two reviewed line segments.
        # A 2px bound keeps rounding within the local vessel silhouette.
        for step in range(21):
            t = step/20
            q = [(1-t)**2*start[i]+2*t*(1-t)*point[i]+t*t*end[i] for i in (0,1)]
            def segment_distance(a,b):
                v = [b[i]-a[i] for i in (0,1)]
                u = max(0,min(1,sum((q[i]-a[i])*v[i] for i in (0,1))/sum(x*x for x in v)))
                return math.dist(q,[a[i]+u*v[i] for i in (0,1)])
            assert min(segment_distance(before,point),segment_distance(point,after)) <= 2.001
    commands.append(f'L{points[-1][0]:.4f},{points[-1][1]:.4f}')
    return ' '.join(commands)

def silhouette(name):
    return ' '.join(path(p['points']) + ' Z' for p in outlines[name])

neck_ids = ['e017', 'e067', 'e018', 'e021', 'e022', 'e068', 'e071', 'e072'] + [f'e{i}' for i in range(153,160)]
abdomen_ids = ['e116', 'e117', 'e119', 'e123', 'e125', 'e136', 'e138', 'e139', 'e141', 'e164', 'e165', 'e166', 'e169', 'e170', 'e171']
palette = {'artery': ('#923c37','#df5850','#f49c83'), 'vein': ('#34536c','#408abe','#a0cfde'), 'portal': ('#574259','#927399','#c4a3c4')}

def vessel(eid, width=None):
    e = edges[eid]
    dark, mid, light = palette[e['kind']]
    w = width or (4.8 if e['kind']=='artery' else 5.2)
    if e['kind']=='portal': w = 3.4
    d = rounded_vessel_path(e['points'])
    # Graph endpoints stay exact. A restrained highlight matches the soft art.
    return f'<g data-edge="{eid}" fill="none" stroke-linecap="round" stroke-linejoin="round"><path d="{d}" stroke="{dark}" stroke-width="{w+1.4}"/><path d="{d}" stroke="{mid}" stroke-width="{w}"/><path d="{d}" stroke="{light}" stroke-opacity=".48" stroke-width="{w*.26}"/></g>'

defs = '''<defs>
<clipPath id="chestPatch"><path d="M374 324 H645 V469 H374 Z"/></clipPath>
<clipPath id="neckPatch"><path d="M458 146 H560 V224 Q560 253 658 266 V379 H366 V266 Q458 248 458 224 Z"/></clipPath>
<clipPath id="neckDraw"><rect x="348" y="142" width="328" height="237"/></clipPath>
<clipPath id="trachea"><path d="M500 146 H518 V324 L528 343 L535 353 L530 360 L509 342 L487 366 L478 362 L499 334 Z"/></clipPath>
<clipPath id="kidneyCleanup"><rect x="419" y="593" width="43" height="40" rx="7"/><rect x="563" y="595" width="43" height="40" rx="7"/></clipPath>
<clipPath id="shoulderBones"><circle cx="357" cy="313" r="19"/><circle cx="661" cy="313" r="19"/></clipPath>
<clipPath id="abdomenDraw"><rect x="420" y="477" width="180" height="157"/></clipPath>
<mask id="deepTissue" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1536"><rect width="1024" height="1536" fill="white"/>
'''
# Keep food passages, organs and their outside rims in front of deep vessels.
for organ in ['liver','stomach','pancreas','kidney_r','kidney_l','small_intestine','large_intestine']:
    defs += f'<path d="{silhouette(organ)}" fill="black" fill-rule="evenodd" stroke="black" stroke-width="2"/>'
# Expose short organ-side gate segments without uncovering a long deep route.
for node_id in ['liver.entry','liver.portal_entry','stomach.entry','stomach.exit','kidney_r.entry','kidney_r.exit','kidney_l.entry','kidney_l.exit']:
    node = next(n for n in network['nodes'] if n['id']==node_id)
    radius = 5.5 if node_id.startswith('kidney') else 4.5
    defs += f'<circle cx="{node["x"]}" cy="{node["y"]}" r="{radius}" fill="white"/>'
# Explicit food-channel protection remains above the white gate windows.
defs += '<path d="M540 463 Q532 486 537 509" fill="none" stroke="black" stroke-width="19" stroke-linecap="round"/><path d="M501 551 C472 552 463 570 468 597 C473 615 489 625 527 619" fill="none" stroke="black" stroke-width="31" stroke-linecap="round"/></mask></defs>'

svg = ['<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1536" viewBox="0 0 1024 1536">', '<title>局部校准的人体血管美术稿</title>', defs,
       image('overview-v2.png'), '<g clip-path="url(#chestPatch)">', image('overview-v3-chest.png'), '</g>',
       '<g clip-path="url(#neckPatch)">', image('ports-clean-underlay.png'), '</g>',
       '<g clip-path="url(#kidneyCleanup)">', image('ports-clean-underlay.png'), '</g>',
       '<g clip-path="url(#neckDraw)">']
svg += [vessel(eid) for eid in neck_ids]
svg += ['</g><g clip-path="url(#trachea)">',image('ports-clean-underlay.png'),'</g><g clip-path="url(#shoulderBones)">', image('overview-v2.png'), '</g>',
        '<g clip-path="url(#abdomenDraw)" mask="url(#deepTissue)">']
svg += [vessel(eid,3.7) for eid in abdomen_ids]
svg += ['</g></svg>']
result = '\n'.join(svg)
(ASSET/'overview-v10-layered.svg').write_text(result)
(DOC/'candidate-v10.svg').write_text(result)

record = {
    'status':'LAYERED_ART_STUDY_NOT_RUNTIME',
    'sourceNetworkSha256':hashlib.sha256(network_path.read_bytes()).hexdigest(),
    'sourceImageSha256':hashlib.sha256((ROOT/'assets/image/anatomy-reference/reference.png').read_bytes()).hexdigest(),
    'base':'overview-v2.png','chestPatch':'overview-v3-chest.png','neckPatch':'ports-clean-underlay.png','kidneyCleanup':'ports-clean-underlay.png',
    'neckEdges':neck_ids,'abdomenEdges':abdomen_ids,
    'geometryRule':'Exact reviewed endpoints; interior corners rounded within 2 source pixels of reviewed segments',
    'compositionRule':'Original v2 remains the base; generated underlays visible only in explicit clips',
    'foodProtection':'Black foreground mask above deep vessels, including duodenal C loop',
    'limitations':['Only selected neck/abdominal connections have an independent geometry layer.',
                   'Deep masked connections are designed continuity, not visible raster evidence.',
                   'Visible gate positions need visual review against illustrated contours.',
                   'Original limb vessels remain; whole-body topology has not been certified in the art.',
                   'No gameplay, zoom transition, native integration or performance verification.'],
    'runtimeModified':False,
}
# Verify endpoint data still agrees with the graph rather than assuming that
# sharing a filename means the two revisions are synchronized.
nodes={n['id']:n for n in network['nodes']}
for eid in neck_ids+abdomen_ids:
    e=edges[eid]
    for p,key in [(e['points'][0],e['a']),(e['points'][-1],e['b'])]:
        n=nodes[key]
        assert abs(p[0]-n['x'])<.001 and abs(p[1]-n['y'])<.001, (eid,key)
record['endpointCheck']='PASS'
(DOC/'layered-review.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
PUB.mkdir(exist_ok=True)
for name in ['candidate-v10.svg','layered-review.json','generation-round2.json']:
    shutil.copy2(DOC/name,PUB/name)
print(json.dumps({'asset':str(ASSET/'overview-v10-layered.svg'),'edgeCount':len(neck_ids+abdomen_ids),'endpointCheck':'PASS'}))
