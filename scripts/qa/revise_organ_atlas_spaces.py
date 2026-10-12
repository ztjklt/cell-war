"""Repeatable, fixed-coordinate open-room revision of the organ atlas.

The baseline is immutable. These are tissue baffles, not new blood passages.
No image-generation output, global graph, organ outline, lumen or physical
membrane is changed by this authoring pass. Collision walls and reachable
decorative room floors are separate geometries.
"""
from pathlib import Path
import argparse, base64, hashlib, json, math, shutil, sys
from collections import deque
import numpy, cffi  # Load interpreter-matched extensions before historical QA paths.
from PIL import Image
sys.path.insert(0, '/tmp/passage-tools314')
from lupa.lua54 import LuaRuntime
sys.path.insert(0, '/tmp/reference-map-tools')
from shapely.geometry import Polygon, Point, LineString
from shapely.ops import unary_union
import cairosvg

ROOT = Path(__file__).resolve().parents[2]
ATLAS = ROOT / 'docs/body-life/vascular-art-study/organ-atlas'
REV = ATLAS / 'revision-v2'
BASELINE = REV / 'baseline'
RADII = {'scout': .21875, 'siege': .53125}
TARGETS = {'brain': 4, 'heart': 3, 'liver': 3, 'lung_l': 3, 'lung_r': 3,
           'kidney_l': 2, 'kidney_r': 2, 'pancreas': 2, 'bladder': 3,
           'small_intestine': 3, 'large_intestine': 4}
PALETTES = {'brain': ['#e7bec9', '#d9adb9', '#d5b7a5'],
            'heart': ['#e4aaa6', '#d99596', '#ecc3ab'],
            'liver': ['#ddb19c', '#d5a18f', '#d1b59d'],
            'lung_l': ['#e4c0c4', '#d6abb7', '#d8c4b3'],
            'lung_r': ['#e4c0c4', '#d6abb7', '#d8c4b3'],
            'kidney_l': ['#dfb5b0', '#d4a29f', '#dfc5a9'],
            'kidney_r': ['#dfb5b0', '#d4a29f', '#dfc5a9'],
            'pancreas': ['#e6c5a5', '#dab695', '#ddd1b2'],
            'bladder': ['#e4c6ae', '#d8b3a0', '#ded1b2'],
            'small_intestine': ['#e4bcbc', '#d8aaaa', '#e0c9ae'],
            'large_intestine': ['#e2b6bf', '#d4a7b1', '#dfc6b0']}

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def digest(v): return hashlib.sha256(json.dumps(v, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
def load(p): return json.loads(p.read_text())
def dump(p, v):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(v, ensure_ascii=False, indent=2, sort_keys=True) + '\n')
def geometry(rs): return unary_union([Polygon(p['outer'], p.get('holes', [])) for p in rs])
def polys(g):
    if g.is_empty: return []
    if g.geom_type == 'Polygon': return [g]
    return [p for p in getattr(g, 'geoms', []) if p.geom_type == 'Polygon' and not p.is_empty]
def rings(g):
    return [{'outer': [list(p) for p in q.exterior.coords],
             'holes': [[list(p) for p in h.coords] for h in q.interiors]} for q in polys(g)]
def dpath(g):
    def ring(ps): return 'M ' + ' L '.join(f'{x:.5f} {y:.5f}' for x, y in ps) + ' Z'
    return ' '.join(ring(p.exterior.coords) + ' ' + ' '.join(ring(h.coords) for h in p.interiors) for p in polys(g))

def protected_hashes(d):
    keys = ['sourceBox', 'sourceTransform', 'outerRings', 'fineOutlinePaths',
            'foodAirUrineRings', 'reservedLocalFeatures', 'protectedPassages',
            'frozenBloodEdges', 'frozenPorts', 'occlusions']
    result = {k: digest(d.get(k)) for k in keys}
    result['physicalGates'] = digest({k: v['gateContracts'] for k, v in d['profiles'].items()})
    result['roomIdentityAndRallies'] = digest({k: [{n: r.get(n) for n in
        ['id', 'rallySource', 'rallyWorld', 'accessGateId', 'doorSource', 'reachableGateIds']}
        for r in v['rooms']] for k, v in d['profiles'].items()})
    return result

def topology(raw, original):
    result = {}
    for kind, radius in RADII.items():
        cs = sorted(polys(raw.buffer(-radius-.025)), key=lambda p: -p.area)
        major = [q for q in cs if q.area >= 4]
        rooms = original['profiles'][kind]['rooms']
        gates = original['profiles'][kind]['gateContracts']
        # Do not create new playable components or discard an original room.
        if len(major) != len(rooms): return None
        for c in major:
            if not any(c.covers(Point(r['rallySource'])) for r in rooms): return None
            if not any(c.covers(Point(g['tissueAnchorSource'])) for g in gates): return None
        for r in rooms:
            c = next((q for q in major if q.covers(Point(r['rallySource']))), None)
            if c is None or not raw.covers(Point(r['rallySource']).buffer(radius)): return None
            if not any(c.covers(Point(g['tissueAnchorSource'])) for g in gates
                       if g['id'] in r['reachableGateIds']): return None
        result[kind] = {'major': major, 'small': [q for q in cs if q.area < 4]}
    return result

def candidates(d):
    raw = geometry(d['tissueRings']); x0, y0, x1, y1 = raw.bounds
    w, h = x1-x0, y1-y0; step = max(2, min(w, h)/17)
    protected = unary_union([Point(r['rallySource']).buffer(3.2)
        for p in d['profiles'].values() for r in p['rooms']] +
        [geometry(g['rawThroatRings']).buffer(3.0)
         for g in d['profiles']['siege']['gateContracts']])
    blood = unary_union([LineString(e['samples']).buffer(e['lumenWidthSource']/2+1.4)
                         for e in d['frozenBloodEdges']])
    center_target = Point((x0+x1)/2, (y0+y1)/2)
    base = min(14, min(w, h)*.145)
    rows=[]
    nx, ny = math.ceil(w/step), math.ceil(h/step)
    for iy in range(1, ny):
        for ix in range(1, nx):
            center=Point(x0+ix*w/nx,y0+iy*h/ny)
            if not raw.covers(center): continue
            clearance = raw.boundary.distance(center)
            radius = min(base, (clearance-1.2)*.78)
            if radius < 2.6: continue
            thickness = max(.48, min(1.1, radius*.11))
            if not raw.covers(center.buffer(radius+thickness/2+1.0)): continue
            # The gap faces an existing rally, making the chamber visibly enterable.
            rally = min(d['profiles']['siege']['rooms'], key=lambda r: center.distance(Point(r['rallySource'])))
            a = math.atan2(rally['rallySource'][1]-center.y, rally['rallySource'][0]-center.x)
            for offset in [0, math.pi/3, -math.pi/3, math.pi]:
                angle=a+offset; halfgap=math.radians(58)
                points = [[center.x+radius*math.cos(angle+halfgap+(2*math.pi-2*halfgap)*i/40),
                           center.y+radius*math.sin(angle+halfgap+(2*math.pi-2*halfgap)*i/40)] for i in range(41)]
                wall=LineString(points).buffer(thickness/2,quad_segs=10)
                if wall.intersects(protected) or wall.intersects(blood): continue
                opening=[center.x+radius*math.cos(angle),center.y+radius*math.sin(angle)]
                gap=2*radius*math.sin(halfgap)-thickness
                if gap < 3.0: continue
                floor=center.buffer(radius-thickness*.6,quad_segs=32)
                score=radius*8-center.distance(center_target)*.035
                rows.append({'center':center,'radius':radius,'thickness':thickness,'wall':wall,
                             'floor':floor,'opening':opening,'width':gap,'points':points,'score':score})
                break
    return sorted(rows,key=lambda r:-r['score'])

def revise(d):
    original=load(BASELINE/'geometry'/f"{d['organId']}.json")
    raw=geometry(original['tissueRings']); oldwall=geometry(original['wallRings'])
    used=[]; chambers=[]; added=[]
    for q in candidates(original):
        if any(q['center'].distance(p['center']) < q['radius']+p['radius']+3.0 for p in used): continue
        newraw=raw.difference(q['wall'])
        top=topology(newraw,original)
        if top is None: continue
        if not geometry(rings(unary_union(top['siege']['major']))).covers(q['center']): continue
        if not newraw.buffer(-RADII['siege']-.025).covers(LineString([[q['center'].x,q['center'].y],q['opening']])): continue
        raw=newraw; used.append(q); added.append(q['wall'])
        ci=len(chambers)+1
        chambers.append({'id':f"{d['organId']}.visual-chamber.{ci}",
                         'kind':'open rounded mucosal/lobular tissue bay',
                         'centerSource':[q['center'].x,q['center'].y],
                         'openingSource':q['opening'], 'openingWidthSource':q['width'],
                         'entryForProfiles':['scout','siege'], 'floorCollision':False,
                         'floorRings':rings(q['floor']), 'wallRings':rings(q['wall']),
                         'curvedWallCenterline':q['points'],
                         'fill':PALETTES[d['organId']][(ci-1)%3],
                         'wallsAreRealTissueCollision':True,
                         'bloodProjectionCreatesDoor':False})
        if len(chambers)>=TARGETS[d['organId']]:break
    # A broad C-bay should resemble mucosal folds, not a manufactured circle.
    # Select stable centers/opening directions first, then introduce only smooth
    # low-frequency, slightly asymmetric curvature around those fixed anchors.
    # A small inward bias keeps the revised footprint inside the original room.
    raw=geometry(original['tissueRings']);added=[]
    protected=unary_union([Point(r['rallySource']).buffer(3.2)
        for p in original['profiles'].values() for r in p['rooms']]+
        [geometry(g['rawThroatRings']).buffer(3.0)
         for g in original['profiles']['siege']['gateContracts']])
    blood=unary_union([LineString(e['samples']).buffer(e['lumenWidthSource']/2+1.4)
                       for e in original['frozenBloodEdges']])
    for i,(q,c) in enumerate(zip(used,chambers)):
        first=math.atan2(q['points'][0][1]-q['center'].y,q['points'][0][0]-q['center'].x)
        last=first+math.radians(244)
        chosen=None
        for scale in [1, .85, .7, .5]:
            def point(a,r):
                factor=1+scale*(-.026+.038*math.sin(a*2+i*.73)+.020*math.cos(a*3-i*.41))
                return [q['center'].x+r*factor*math.cos(a),q['center'].y+r*factor*math.sin(a)]
            points=[point(first+(last-first)*j/60,q['radius'])for j in range(61)]
            wall=LineString(points).buffer(q['thickness']/2,quad_segs=10)
            next_raw=raw.difference(wall)
            if wall.intersects(protected) or wall.intersects(blood):continue
            if topology(next_raw,original) is None:continue
            if not next_raw.buffer(-RADII['siege']-.025).covers(LineString([[q['center'].x,q['center'].y],q['opening']])):continue
            floor=Polygon([point(2*math.pi*j/96,q['radius']-q['thickness']*.6)for j in range(96)])
            chosen=(wall,points,floor,next_raw,scale);break
        assert chosen is not None, ('organic curvature changed clearance', d['organId'], c['id'])
        wall,points,floor,raw,scale=chosen
        added.append(wall);c.update({'wallRings':rings(wall),'curvedWallCenterline':points,
           'floorRings':rings(floor),'organicCurvature':{'harmonics':[2,3],
            'radialVariationMaximumFraction':.084*scale,'fixedCenterAndOpening':True}})
    top=topology(raw, original)
    assert top is not None, d['organId']
    d=json.loads(json.dumps(original));wall=unary_union([oldwall,*added]);reserve=geometry(d['foodAirUrineRings'])
    d['tissueRings']=rings(raw);d['wallRings']=rings(wall);d['obstacleRings']=rings(wall.union(reserve))
    d['visualChambers']=chambers
    d['spaceRevision']={'version':2,'baseGeometrySha256':sha(BASELINE/'geometry'/f"{d['organId']}.json"),
        'openChambers':len(chambers),'requestedMaximum':TARGETS[d['organId']],
        'flatOpenTerrainFraction':raw.area/geometry(d['outerRings']).area,
        'addedWallAreaSource':unary_union(added).area,
        'preservesExternalBoundariesAndLumen':True,'preservesPhysicalGatesAndRallies':True,
        'separateBloodAndTissuePlanes':True,'noNewBloodJunctions':True}
    for kind, radius in RADII.items():
        p=d['profiles'][kind]; safe=unary_union(top[kind]['major'])
        p['safeRings']=rings(safe);p['safePath']=dpath(safe)
        p['discardedSmallComponents']=[{'areaSource':q.area,'rawRings':rings(q),'policy':'non-playable original silhouette sliver; not an inaccessible visual room'} for q in top[kind]['small']]
        for r in p['rooms']:
            c=next(q for q in top[kind]['major'] if q.covers(Point(r['rallySource'])))
            r['rawRings']=rings(c);r['areaSource']=c.area
        p['accessChecks']['spaceRevisionExistingRalliesAndGatesConnected']=True
    return d

def guide(d):
    x0,y0,x1,y1=d['sourceBox'];w,h=x1-x0,y1-y0
    outer=geometry(d['outerRings']);reserve=geometry(d['foodAirUrineRings']);wall=geometry(d['wallRings'])
    begin=f'<svg xmlns="http://www.w3.org/2000/svg" width="{w*12}" height="{h*12}" viewBox="{x0} {y0} {w} {h}">'
    s=begin+f'<defs><clipPath id="organ"><path d="{dpath(outer)}" clip-rule="evenodd"/></clipPath></defs><rect x="{x0}" y="{y0}" width="{w}" height="{h}" fill="#f1e9e2"/><g clip-path="url(#organ)">'
    colors=PALETTES[d['organId']]
    for i,z in enumerate(d['decorativeZones']):s+=f'<path d="{dpath(geometry(z["rawRings"]))}" fill="{colors[i%3]}" fill-rule="evenodd"/>'
    # The color patch is walkable floor: never draw a closed outline around it,
    # which image generators can mistake for a sealed fourth wall at the mouth.
    for c in d['visualChambers']:s+=f'<path d="{dpath(geometry(c["floorRings"]))}" fill="{c["fill"]}" fill-rule="evenodd"/>'
    s+=f'<path d="{dpath(reserve)}" fill="#ead4b7" stroke="#a88473" stroke-width=".28" fill-rule="evenodd"/>'
    s+=f'<path d="{dpath(wall)}" fill="#c48b8e" stroke="#865e5f" stroke-width=".32" fill-rule="evenodd"/>'
    s+=f'</g><path d="{dpath(outer)}" fill="none" stroke="#875e61" stroke-width=".65"/></svg>'
    p=REV/'guides'/f'{d["organId"]}-terrain-guide.svg';p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s)
    cairosvg.svg2png(bytestring=s.encode(),write_to=str(p.with_suffix('.png')))
    return {'guide':str(p.with_suffix('.png').relative_to(ROOT)), 'sourceBox':d['sourceBox'],
            'widthPixels':w*12, 'heightPixels':h*12, 'outlineSha256':digest(d['outerRings']),
            'reservedLumenSha256':digest(d['foodAirUrineRings']),
            'textFree':True,'bloodAndMembranesExcludedForSeparateFixedForeground':True,
            'openings':[{k:c[k] for k in ['id','centerSource','openingSource','openingWidthSource']} for c in d['visualChambers']]}

def verify_runtime():
    """Check every compiled navigation point, not just sampled room centers."""
    current=load(ATLAS/'runtime-data.json'); baseline=load(BASELINE/'runtime-data.json')
    rows=[]
    def components(g):
        valid=base64.b64decode(g['validBase64']);adj=base64.b64decode(g['adjacencyBase64'])
        width,height=g['width'],g['height'];seen=set();out=[]
        offsets=[dy*width+dx for dx,dy in current['organs'][next(iter(current['organs']))]['directions']]
        for start,v in enumerate(valid):
            if not v or start in seen:continue
            todo=deque([start]);seen.add(start);component=[]
            while todo:
                node=todo.popleft();component.append(node);bits=adj[node]
                for bit,offset in enumerate(offsets):
                    if bits&(1<<bit):
                        nxt=node+offset
                        assert 0<=nxt<len(valid) and valid[nxt], 'adjacency points outside domain'
                        if nxt not in seen:seen.add(nxt);todo.append(nxt)
            out.append(component)
        def nearest_index(point):
            px=(point[0]-g['origin'][0])/g['step'];py=(point[1]-g['origin'][1])/g['step']
            return min((i for i,v in enumerate(valid) if v),key=lambda i:(i%width-px)**2+(i//width-py)**2)
        return out,nearest_index
    for oid,organ in current['organs'].items():
        d=load(ATLAS/'geometry'/f'{oid}.json');old=load(BASELINE/'geometry'/f'{oid}.json')
        fixed=protected_hashes(d)==protected_hashes(old)
        assert fixed and organ['geometrySha256']==sha(ATLAS/'geometry'/f'{oid}.json')
        for kind,g in organ['grids'].items():
            cs,near=components(g);oldg=baseline['organs'][oid]['grids'][kind];oldcs,oldnear=components(oldg)
            rallies=[near(r['rallySource']) for r in d['profiles'][kind]['rooms']]
            gates=[near(r['tissueAnchorSource']) for r in d['profiles'][kind]['gateContracts']]
            playable=[c for c in cs if set(c).intersection(rallies)]
            no_gate=[c for c in playable if not set(c).intersection(gates)]
            original_rallies=[oldnear(r['rallySource']) for r in old['profiles'][kind]['rooms']]
            original_orphan=[c for c in oldcs if not set(c).intersection(original_rallies)]
            original_orphan_indices={i for c in original_orphan for i in c}
            orphan=[c for c in cs if not set(c).intersection(rallies)]
            # Tiny original silhouette slivers remain explicitly non-playable;
            # an added chamber is never one of those disconnected slivers.
            chamber_indices=[near(c['centerSource'])for c in d['visualChambers']]
            chamber_connected=all(any(i in c and set(c).intersection(gates) for c in playable)for i in chamber_indices)
            row={'organId':oid,'profile':kind,'fixedContractsUnchanged':fixed,
                 'gridComponents':len(cs),'baselineGridComponents':len(oldcs),
                 'allExistingRalliesHaveGate':not no_gate,
                 'allNewChambersHaveGate':chamber_connected,
                 'gridPoints':g['validGridPoints'],'allGridNeighborSweepsAlreadyCovered':g['neighborSweepsChecked'],
                 'orphanGridPoints':sum(len(c)for c in orphan),'baselineOrphanGridPoints':len(original_orphan_indices),
                 'baselineOrphanComponentSizes':sorted(len(c)for c in original_orphan),
                 'orphanComponentSizes':sorted(len(c)for c in orphan)}
            row['noNewOrphanGridPoints']=all(i in original_orphan_indices for c in orphan for i in c)
            row['pass']=not no_gate and chamber_connected and row['noNewOrphanGridPoints']
            rows.append(row);print('full-domain',oid,kind,row['pass'],len(cs),'components',flush=True)
    report={'schema':'organ-open-space-full-grid/v2','nativeEvidence':False,
       'runtimeSha256':sha(ATLAS/'runtime-data.json'),'passed':sum(r['pass']for r in rows),'total':len(rows),
       'allFixedContractsUnchanged':all(r['fixedContractsUnchanged']for r in rows),'profiles':rows}
    dump(REV/'qa/full-domain-grid-report.json',report)
    return report

def verify_movement():
    """Actual Commands/Path/Simulation into every new bay, with raw oracle."""
    sys.path.insert(0,str(ROOT/'scripts/qa'))
    import check_organ_battlefield_atlas as qa
    qa.OUT=REV/'qa/chambers'
    def cases(records):
        configs=[]
        def actor(kind,a,b,oid):
            return {'kind':kind,'x':a[0]*2,'y':a[1]*2+512,
                'tx':b[0]*2,'ty':b[1]*2+512,'lane':0,'targetLane':0,'targetOrgan':oid}
        for oid,d in records.items():
            if oid=='stomach':continue
            for c in d['visualChambers']:
                center=c['centerSource'];opening=c['openingSource']
                for kind in ['scout','siege']:
                    safe=geometry(d['profiles'][kind]['safeRings'])
                    component=next(q for q in polys(safe) if q.covers(Point(center)))
                    room=next(r for r in d['profiles'][kind]['rooms'] if component.covers(Point(r['rallySource'])))
                    rally=room['rallySource']
                    for label,start,end in [('enter',rally,center),('leave',center,rally)]:
                        configs.append({'id':f'{oid}/{c["id"]}/{kind}/{label}', 'organs':qa.ORGANS,
                           'actors':[actor(kind,start,end,oid)],'maxTime':300})
                # Both actual cells cross the broad opening in opposite directions.
                vec=[opening[i]-center[i]for i in range(2)];length=math.hypot(*vec)
                outside=[opening[i]+vec[i]/length*2.0 for i in range(2)]
                safe=geometry(d['profiles']['siege']['safeRings'])
                assert safe.covers(Point(outside)),('meeting outside point',oid,c['id'])
                configs.append({'id':f'{oid}/{c["id"]}/meeting/scout-siege', 'organs':qa.ORGANS,
                    'actors':[actor('scout',center,outside,oid),actor('siege',outside,center,oid)],'maxTime':300})
        return configs
    qa.scenario_configs=cases
    result=qa.production_checks()
    print('new chambers production',result['status'],result.get('passed',0),'/',result.get('total',0),flush=True)
    return result

def verify_walls():
    """Each authored curved baffle must actually stop a swept cell in Lua."""
    sys.path.insert(0,str(ROOT/'scripts/qa'))
    import check_organ_battlefield_atlas as qa
    _,records=qa.contract_records();oracle=qa.MotionOracle(records)
    harness=qa.gastric_qa();l=harness.runtime();before=qa.hashes()
    probe=l.execute(r'''
      local T,W,C,P,K,O=require('war.OrganTrial'),require('war.World'),require('war.Commands'),
       require('war.Path'),require('war.CellCollision'),require('war.OrganBattlefield')
      local s=T.new(73,...)
      return function(kind,x,y,tx,ty)
       s.entities={};s.commands={};W.rebuild(s)
       local e=C.spawn(s,'unit',kind,1,x,y)
       if not e then return{spawned=false}end
       W.rebuild(s)
       local clear=P.clear(s,e.x,e.y,tx,ty,1,e.vesselLane,0,e)
       local nx,ny,lane,transit=K.move(s,e,tx,ty,0)
       return{spawned=true,spawn={x=e.x,y=e.y,lane=e.vesselLane,organId=O.organAt(s,e,e.x,e.y)},
        directClear=clear,movement={x=nx,y=ny,lane=lane,transit=transit,organId=O.organAt(s,e,nx,ny)}}
      end
    ''',harness.lua_table(l,qa.ORGANS))
    rows=[]
    for oid,d in records.items():
        if oid=='stomach':continue
        raw=geometry(d['tissueRings'])
        for c in d['visualChambers']:
            points=c['curvedWallCenterline'];candidate=None
            for i in range(3,len(points)-3):
                px,py=points[i];dx=points[i+1][0]-points[i-1][0];dy=points[i+1][1]-points[i-1][1];n=math.hypot(dx,dy)
                a=[px-dy/n*1.7,py+dx/n*1.7];b=[px+dy/n*1.7,py-dx/n*1.7]
                if raw.covers(Point(a).buffer(.53125)) and raw.covers(Point(b).buffer(.53125)):
                    candidate=(a,b);break
            assert candidate, ('no wall sweep fixture',oid,c['id'])
            a,b=candidate
            for kind in ['scout','siege']:
                r=harness.convert(probe(kind,a[0]*2,a[1]*2+512,b[0]*2,b[1]*2+512))
                covered=bool(r.get('movement')and oracle.capsule(r['spawn'],r['movement'],kind))
                passed=bool(r['spawned']and not r['directClear']and covered)
                rows.append({'id':f'{c["id"]}/{kind}/wall-crossing', 'pass':passed,
                    'sourceStart':a,'sourceTarget':b,'actual':r,'actualSweepCovered':covered})
    changed=[k for k,v in before.items()if k not in qa.DRAW_ONLY_MODULES and qa.hashes().get(k)!=v]
    report={'schema':'organ-new-baffle-production-collision/v2','nativeEvidence':False,
        'navigationSubstituted':False,'passed':sum(r['pass']for r in rows),'total':len(rows),'cases':rows,
        'testedModuleHashes':before,'modulesChangedDuringCapture':changed}
    report['status']='UNDETERMINED' if changed else 'PASS' if all(r['pass']for r in rows)else 'FAIL'
    dump(REV/'qa/new-wall-collision-report.json',report)
    print('new wall collision',report['status'],report['passed'],'/',report['total'],flush=True)
    return report

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--organ',action='append')
    parser.add_argument('--verify-runtime',action='store_true');parser.add_argument('--verify-movement',action='store_true')
    parser.add_argument('--verify-walls',action='store_true');args=parser.parse_args()
    if args.verify_runtime:
        r=verify_runtime();raise SystemExit(0 if r['passed']==r['total'] else 1)
    if args.verify_movement:
        r=verify_movement();raise SystemExit(0 if r['status']=='PASS' else 1)
    if args.verify_walls:
        r=verify_walls();raise SystemExit(0 if r['status']=='PASS' else 1)
    assert (BASELINE/'manifest.json').is_file(), 'Freeze complete baseline before revision.'
    reports=[];guides=[]
    c=load(ATLAS/'contract.json' if args.organ else BASELINE/'contract.json')
    for rec in c['organs']:
        oid=rec['organId']
        if oid=='stomach' or (args.organ and oid not in args.organ):continue
        p=ATLAS/'geometry'/f'{oid}.json';old=load(BASELINE/'geometry'/f'{oid}.json')
        d=revise(old);before=protected_hashes(old);after=protected_hashes(d)
        assert before==after, ('fixed contract changed', oid)
        g=guide(d);d['guidePaths']['revisionV2']=g['guide'];dump(p,d);guides.append(dict(organId=oid,**g))
        rec['geometrySha256']=sha(p);rec['guidePaths']=d['guidePaths']
        rec['spaceRevision']=d['spaceRevision'];rec['profileSummary']={k:v['accessChecks'] for k,v in d['profiles'].items()}
        reports.append({'organId':oid,'fixedHashes':before,'allFixedContractsUnchanged':before==after,
            'spaceRevision':d['spaceRevision'],'profiles':{k:{'components':v['componentCount'],
               'rooms':len(v['rooms']),'gates':len(v['gateContracts'])} for k,v in d['profiles'].items()}})
        print(oid,'chambers',len(d['visualChambers']),'guide',g['guide'],flush=True)
    c['spaceRevision']={'version':2,'scope':'open tissue bays without changing physical blood membranes, lumen or outline',
        'authoringScript':str(Path(__file__).relative_to(ROOT)), 'scriptSha256':sha(Path(__file__))}
    dump(ATLAS/'contract.json',c)
    if args.organ:
        old_guides=load(REV/'guides/manifest.json').get('guides',[]) if (REV/'guides/manifest.json').is_file() else []
        old_reports=load(REV/'space-geometry-checks.json').get('organs',[]) if (REV/'space-geometry-checks.json').is_file() else []
        gids={r['organId']:r for r in old_guides};gids.update({r['organId']:r for r in guides});guides=list(gids.values())
        rids={r['organId']:r for r in old_reports};rids.update({r['organId']:r for r in reports});reports=list(rids.values())
    dump(REV/'guides/manifest.json',{'schema':'organ-open-space-guides/v2','guides':guides})
    dump(REV/'space-geometry-checks.json',{'schema':'organ-open-space-geometry/v2','nativeEvidence':False,
        'allFixedContractsUnchanged':all(r['allFixedContractsUnchanged']for r in reports),'organs':reports,
        'scope':'exact polygon topology and safe disk erosion; independent production movement still required'})

if __name__=='__main__':main()
