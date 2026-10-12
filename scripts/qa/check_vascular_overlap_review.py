"""Check annotation coverage and named semantics without reusing gameplay pass claims."""
from pathlib import Path
import hashlib
import json
import math
import xml.etree.ElementTree as ET

from shapely import make_valid, union_all
from shapely.geometry import Point, Polygon, LineString

ROOT=Path(__file__).resolve().parents[2]
D=ROOT/'docs/body-life/vascular-art-study'
read=lambda p: json.loads((D/p).read_text())
sha=lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
data=read('vascular-organ-overlap-data.json')
draft=read(data['draft'])
contracts=read('interface-contract.json')
baseline=read('navigation-review-data.json')['network']
for name, value in data['sourceHashes'].items():
    assert sha(D/name)==value, ('stale source',name)
assert data['referenceSha256']==sha(ROOT/'assets/image/anatomy-reference/reference.png')
assert len(data['edges'])==202 and len(data['organs'])==12
assert [{k:v for k,v in e.items() if k!='d'} for e in data['edges']]==draft['edges']
assert len({r['id'] for r in data['records']})==len(data['records'])
assert len({(r['edgeId'],r['organ']) for r in data['records']})==len(data['records'])
assert len({r['id'] for r in data['passageConflicts']})==len(data['passageConflicts'])
assert len({c['portId'] for c in data['channels']})==29
by_pair={(r['edgeId'],r['organ']):r for r in data['records']}
expected={('e125','stomach'):'reroute',('e136','pancreas'):'reroute',('e139','pancreas'):'reroute',
          ('e147','pancreas'):'reroute',('e149','kidney_r'):'reroute',('e012','small_intestine'):'occlude',
          ('e013','large_intestine'):'occlude',('e022','lung_r'):'occlude',('e010','liver'):'occlude',
          ('e174','heart'):'connect',('e175','heart'):'connect',
          ('study.stomach.wall_service','stomach'):'pending'}
for pair,category in expected.items():
    assert by_pair[pair]['category']==category, (pair,by_pair.get(pair))
assert data['draftAudit']['endpoints'][0]['matches']==['stomach.a']
assert len(data['draftAudit']['gateIssues'])==2

masks={}
for o in data['organs']:
    mask=union_all([make_valid(Polygon(r['points'])) for r in o['outlines'] if not r.get('hole')])
    holes=union_all([make_valid(Polygon(r['points'])) for r in o['outlines'] if r.get('hole')])
    masks[o['id']]=mask.difference(holes)
    assert any(r['organ']==o['id'] for r in data['records'])
edges={e['id']:e for e in data['edges']}
points_checked=0
for record in data['records']:
    assert record['segments'] and record['movementCertified'] is False
    band=masks[record['organ']].buffer(edges[record['edgeId']]['lumenWidthSource']/2+.001)
    for segment in record['segments']:
        assert len(segment)>=2
        for point in segment:
            assert all(math.isfinite(v) for v in point) and 0<=point[0]<=1024 and 0<=point[1]<=1536
            assert band.covers(Point(point)), (record['id'],point)
            points_checked+=1
port_map={p['id']:p for r in contracts['regions'] for p in r['ports']}
for channel in data['channels']:
    original=port_map[channel['portId']]['source']
    assert original==channel['frozenSource']==channel['points'][0]
    assert channel['newBloodGraphConnection'] is False and channel['movementCertified'] is False
    assert edges[channel['edgeId']]['a']==channel['portId'] or edges[channel['edgeId']]['b']==channel['portId']
    assert masks[channel['organ']].covers(Point(channel['targetSource']))
    assert channel['lengthSource']>0
    assert LineString(channel['points']).length>0
foreign_ports={c['portId'] for c in data['channels'] if c['crossedOrgans']}
assert foreign_ports=={'lung_l.entry','lung_l.exit','colon_proximal.exit'},foreign_ports
conflict_pairs={(c['edgeId'],c['passageId']) for c in data['passageConflicts']}
for pair in [('e131','food.small'),('e133','food.colon'),('e135','food.colon'),
             ('e143','urine.bl_right'),('e143','urine.bl_left'),('study.stomach.wall_service','food.stomach')]:
    assert pair in conflict_pairs,pair
svg=(D/'vascular-organ-overlap-overview.svg').read_text()
assert 'data:image/png;base64,' in svg and svg.count('data-record=')>=len(data['records'])
svg_edges={p.attrib['data-base-edge']:p for p in ET.fromstring(svg).iter() if 'data-base-edge' in p.attrib}
assert len(svg_edges)==202
palette={'artery':'#b85350','vein':'#3b77a6','capillary':'#726877'}
for edge in data['edges']:
    path=svg_edges[edge['id']]
    assert path.attrib['d']==edge['d'] and path.attrib['stroke']==palette[edge['system']]
evidence={'status':'PASS_ANNOTATION_STRUCTURE_NOT_MOVEMENT', 'counts':data['counts'],
          'sourceDraftUnchanged':True,'annotationPointsWithinOrganContactBand':points_checked,
          'semanticSpecialCasesChecked':len(expected),'channelsRetain29FrozenPorts':True,
          'foreignChannelApproachesListed':sorted(foreign_ports),
          'ownedBloodFoodUrineConflictsListed':True,'standaloneSvgEmbedsUnchangedReference':True,
          'standaloneSvgHasAll202UnchangedVesselCurves':True,
          'dataSha256':sha(D/'vascular-organ-overlap-data.json'),
          'generatorSha256':sha(ROOT/'scripts/qa/build_vascular_overlap_review.py'),
          'checkerSha256':sha(Path(__file__)),
          'productionInstalled':False,'newMovementCertified':False,'nativeConfirmed':False}
(D/'vascular-organ-overlap-checks.json').write_text(json.dumps(evidence,ensure_ascii=False,indent=2)+'\n')
print(f'PASS: 12 organs, {len(data["records"])} pairs, {points_checked} contact-band points, 29 frozen channels; no new movement claim.')
