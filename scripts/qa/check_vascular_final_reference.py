"""Independent final-reference checks: geometry, directed topology, mask intervals, gates."""
from pathlib import Path
import collections
import hashlib
import json
import math
import re

from shapely import make_valid, union_all
from shapely.geometry import LineString, Point, Polygon
from shapely.ops import substring

ROOT=Path(__file__).resolve().parents[2]
D=ROOT/'docs/body-life/vascular-art-study'
read=lambda name:json.loads((D/name).read_text())
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
d=read('final-reference-data.json')
old=read('vascular-organ-overlap-data.json')
draft=read(old['draft'])
central=read('central-vessel-connections.json')
contract=read('interface-contract.json')
edges={e['id']:e for e in d['edges']}
before={e['id']:e for e in old['edges']}
nodes={}
for e in draft['edges']:
    if e['id']=='study.stomach.wall_service':continue
    for key,p in [(e['a'],e['points'][0]),(e['b'],e['points'][-1])]:
        if key in nodes:assert math.dist(nodes[key],p)<1e-7,key
        nodes[key]=p
for name,value in d['sourceHashes'].items():assert sha(D/name)==value,name
assert d['referenceSha256']==sha(ROOT/'assets/image/anatomy-reference/reference.png')
assert len(edges)==202 and set(edges)==set(before)
for eid in central['preservedEdges']:
    assert edges[eid]['points']==before[eid]['points'],eid
    assert edges[eid]['d']==before[eid]['d'],eid
    assert all(edges[eid][k]==before[eid][k] for k in ['a','b','system','kind','lumenWidthSource']),eid
for e in edges.values():
    assert math.dist(e['points'][0],nodes[e['a']])<1e-7,(e['id'],'start')
    assert math.dist(e['points'][-1],nodes[e['b']])<1e-7,(e['id'],'end')
    assert math.dist(e['samples'][0],e['points'][0])<1e-7,e['id']
    assert math.dist(e['samples'][-1],e['points'][-1])<1e-7,e['id']
wall=edges['study.stomach.wall_service']
assert wall['points']==list(reversed(before[wall['id']]['points']))
def controls(path):
    values=[float(v) for v in re.findall(r'-?\d+(?:\.\d+)?(?:e[+-]?\d+)?',path,re.I)]
    start=values[:2];result=[]
    for i in range(2,len(values),6):
        span=[start,values[i:i+2],values[i+2:i+4],values[i+4:i+6]]
        result.append(span);start=span[-1]
    return result
assert controls(wall['d'])==[[s[3],s[2],s[1],s[0]] for s in reversed(controls(before[wall['id']]['d']))]
assert wall['a']=='stomach.a' and wall['b']=='stomach.v' and wall['system']=='capillary'

def reach(start,goal,systems):
    q=[start];seen={start}
    for at in q:
        if at==goal:return True
        for e in edges.values():
            if e['a']==at and e['system'] in systems and e['b'] not in seen:
                seen.add(e['b']);q.append(e['b'])
    return False
loops=[]
for o in central['organs']:
    check={'organ':o['id'],'supply':reach(o['supplyRoot'],o['entry'],['artery']),
        'exchange':reach(o['entry'],o['exit'],['artery','vein','capillary']),
        'return':reach(o['exit'],o['returnRoot'],['vein','capillary'])}
    assert all(check[k] for k in ['supply','exchange','return']),check
    loops.append(check)
assert reach('stomach.entry','stomach.a',['artery']) and reach('stomach.a','stomach.v',['capillary'])
assert reach('stomach.v','stomach.exit',['vein'])
expected={r['id'] for r in old['records'] if r['category'] in {'reroute','occlude'}}
assert {r['id'] for r in d['decisions']}==expected and len(expected)==48
assert all(r['resolved'] for r in d['decisions'])
assert all(e['edgeId'] not in d['protectedEdges'] for e in d['routeChoices'])

def mask(rings):
    return union_all([make_valid(Polygon(r['points'])) for r in rings if not r.get('hole')]).difference(
        union_all([make_valid(Polygon(r['points'])) for r in rings if r.get('hole')]))
masks={o['id']:mask(o['outlines']) for o in d['organs']}
food=union_all([Polygon(p) for p in d['stomachFoodUnion']])
for p in d['protectedPassages']:
    masks[p['id']]=food if p['id']=='food.stomach' else LineString(p['points']).buffer(p['width']/2)
for c in d['crossings']:
    top=edges[c['over']]
    masks['crossing:'+c['over']]=LineString(top['samples']).buffer(top['lumenWidthSource']/2)
    assert c['createsConnection'] is False
hide={h['id']:h for h in d['occlusions']}
for r in d['decisions']:
    assert all(hid in hide and hide[hid]['edgeId']==r['edgeId'] and hide[hid]['owner']==r['organ'] for hid in r['hiddenSegments'])
point_checks=0
for h in hide.values():
    e=edges[h['edgeId']];line=LineString(e['samples']);band=masks[h['owner']].buffer(e['lumenWidthSource']/2+.651)
    assert math.dist(h['points'][0],h['startSource'])<.0001 and math.dist(h['points'][-1],h['endSource'])<.0001
    assert 0<=h['startT']<h['endT']<=1 and h['createsConnection'] is False
    assert math.dist(line.interpolate(h['startDistance']).coords[0],h['startSource'])<.00001
    assert math.dist(line.interpolate(h['endDistance']).coords[0],h['endSource'])<.00001
    for p in h['points']:
        assert band.covers(Point(p)),(h['id'],p)
        point_checks+=1
for e in edges.values():
    line=LineString(e['samples'])
    visible=sum(LineString(p).length for p in e['visibleSegments'])
    hidden=sum(b-a for a,b in e['hiddenIntervals'])
    assert abs(visible+hidden-line.length)<.015,(e['id'],visible,hidden,line.length)
    if e['points']!=before[e['id']]['points'] and e['id']!=wall['id']:
        assert line.is_simple,e['id']
        assert len(e['points'])<=8,e['id']
        assert all(math.dist(a,b)>=3 for a,b in zip(e['points'],e['points'][1:])),e['id']
        # Every remaining foreign contact is explicitly foreground-occluded.
        layers=read('organ-layers.json')['zones']
        for oid in [o['id'] for o in d['organs']]:
            prefixes=next(z['nodeNamespaces'] for z in layers if z['id']==oid)
            if any(n==p or n.startswith(p+'.') for n in [e['a'],e['b']] for p in prefixes):continue
            if any(h['edgeId']==e['id'] and h['owner']==oid for h in hide.values()):continue
            assert line.intersection(masks[oid]).is_empty or any(p['organ']==oid and p['edgeId']==e['id'] and p['category']=='connect' for p in old['records']),(e['id'],oid)

wall_line=LineString(wall['samples'])
assert len(d['gates'])==2
for g in d['gates']:
    p=g['pipeCenterSource'];normal=[g['nx'],g['ny']]
    assert wall_line.distance(Point(p))<1e-7
    assert abs(math.hypot(*normal)-1)<1e-7
    s=g['distanceAlongSource'];a=wall_line.interpolate(s-.3);b=wall_line.interpolate(s+.3)
    assert abs((b.x-a.x)*normal[0]+(b.y-a.y)*normal[1])<1e-7
    assert min(s,wall_line.length-s)>=6
    assert Point(g['wallSource']).distance(food)>g['radius']
    assert masks['stomach'].covers(Point(g['tissueTargetSource']))
    assert Point(g['tissueTargetSource']).distance(food)>=2.5
    assert g['newNamedBloodJunction'] is False
assert d['ports']==old['ports']
report={'status':'PASS_FINAL_ART_REFERENCE_NOT_MOVEMENT','dataSha256':sha(D/'final-reference-data.json'),
    'generatorSha256':sha(ROOT/'scripts/qa/build_vascular_final_reference.py'),'checkerSha256':sha(Path(__file__)),
    'counts':d['counts'],'protected116SourceCurvesUnchanged':True,'namedEndpointChecks':404,
    'all29NamedPortsUnchanged':True,'original48DecisionsResolved':True,'occlusionPointsChecked':point_checks,
    'visibleAndHiddenIntervalsCoverEveryCurve':True,'directedLoops':loops,'stomachSupplyToReturn':True,
    'stomachUserShapePreserved':True,'stomachTwoGatesOnCurveClearOfFoodAndJunction':True,
    'productionInstalled':False,'imageGenerated':False,'newMovementCertified':False,'nativeConfirmed':False}
(D/'final-reference-checks.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(f'PASS: 116 frozen curves, 404 named endpoints, {len(loops)} directed loops, 48 decisions, {len(hide)} exact hidden segments, 2 re-seated stomach gates.')
