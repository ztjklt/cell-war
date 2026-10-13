"""Compile the intestinal remodel from real named nodes, lanes and membrane gates.

The original reference, tissue grids and four gate identities are immutable.
Only this opted-in blood adapter relocates vessels. Display consumes this data.
"""
from pathlib import Path
import json,math,sys,hashlib
import numpy as np
from shapely.geometry import LineString,Point
from shapely.ops import unary_union
sys.path.insert(0,str(Path(__file__).parent))
from prepare_heart_battlefield import lua,rings
from register_simple_heart import rings as geometry
from prepare_left_vessels import cubic,tapered

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'docs/bowel-remodel-20261013'
CHANGED={132,166,167,168,188,189,190,192}
OWNED={130,131,132,133,134,135,166,167,168,187,188,189,190,191,192}
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def write(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n')
def chain(*segments):
    out=[]
    for seg in segments:out.extend(cubic(*seg)[bool(out):])
    return out

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    edges=json.loads((ROOT/'docs/vascular-map-audit-20261013/runtime-network.json').read_text())
    old={e['lane']:e for e in edges};updates={}
    def install(i,pts):updates[i]={k:old[i][k]for k in ['a','b','widthSource']};updates[i]['points']=pts
    gate=[489.26236877396417,638.5880269732409]
    # A smooth approach above the left colon; the former endpoint forced a U turn.
    install(132,chain(([524,606],[514,615],[501,628],gate),(gate,[477,649],[452,636],[452,646])))
    install(189,cubic([452,646],[452,651],[453,656.3],[451,657]))
    # Blue return has its own endpoint below the red distal arterial inlet.
    install(188,cubic([535,701],[545,698],[548,687],[548,678]))
    install(166,cubic([548,678],[548,664],[530,638],[530,620]))
    # Preserve the real membrane at (475,719) while removing the long hairpin.
    install(190,cubic([459,711],[463,712.5],[466,719],[470,719]))
    install(167,chain(([470,719],[472,719],[473,719],[475,719]),([475,719],[487,719],[507,637],[530,620])))
    # The distal return follows the outside of the bowel rather than a wide loop.
    install(192,cubic([565,713],[566,716],[571,718],[575,718]))
    install(168,chain(([575,718],[585,718],[591,700],[588,682]),([588,682],[585,660],[569,640],[555,632])))
    nodes={'colon_proximal.entry':[452,646],'small_intestine.exit':[548,678],
           'colon_proximal.exit':[470,719],'colon_distal.exit':[575,718]}
    current={i:old[i]|updates.get(i,{})for i in old}
    domains={i:LineString(e['points']).buffer(e['widthSource']/2,quad_segs=24)for i,e in current.items()}
    # The arterial mouth and venous starts share the same narrow width as
    # their incident exchange lead. Taper the physical walls over 7 source px.
    domains[132]=tapered(current[132]['points'],3,2,7)
    for i in [166,167,168]:domains[i]=tapered(current[i]['points'][::-1],3,2,7)
    d={'schema':'bowel-blood-remodel/v1','layoutRevision':1,'sourceBox':[440,603,596,735],
       'nodePoints':nodes,'edgeUpdates':updates,'rawBloodDomains':{i:rings(domains[i])for i in CHANGED},
       'bloodLanes':{},'junctionContracts':{},'ownedLanes':{i:True for i in OWNED},'gateContracts':{}}
    source={oid:json.loads((ROOT/f'docs/body-life/vascular-art-study/organ-atlas/geometry/{oid}.json').read_text())for oid in ['small_intestine','large_intestine']}
    gate_records=[]
    for kind,radius in [('scout',.21875),('siege',.53125)]:
        safe={i:g.buffer(-radius-.02,quad_segs=24)for i,g in domains.items()}
        lanes={}
        def include(i):
            e=current[i];lanes[i]={'laneIndex':i,'edgeId':e['name'],'a':e['a'],'b':e['b'],
                 'points':e['points'],'lumenWidthSource':e['widthSource'],'safeRings':rings(safe[i])}
        for i in CHANGED:include(i)
        junctions=[]
        for a,ea in current.items():
            for b,eb in current.items():
                if b<=a or not({a,b}&CHANGED):continue
                for node in {ea['a'],ea['b']}&{eb['a'],eb['b']}:
                    pa=ea['points'][0 if node==ea['a']else -1];pb=eb['points'][0 if node==eb['a']else -1]
                    assert math.dist(pa,pb)<1e-8,(a,b,node)
                    g=safe[a].intersection(safe[b]);assert g.covers(Point(pa)),(kind,a,b,node)
                    include(a);include(b)
                    junctions.append(dict(nodeId=node,aLane=a,bLane=b,source=pa,safeRings=rings(g)))
        d['bloodLanes'][kind]=lanes;d['junctionContracts'][kind]=junctions
        d['gateContracts'][kind]=[]
        for oid,organ in source.items():
            tissue=geometry(organ['profiles'][kind]['safeRings'])
            for gate_contract in organ['profiles'][kind]['gateContracts']:
                a=gate_contract['pipeAnchorSource'];b=gate_contract['tissueAnchorSource'];i=gate_contract['laneIndex']
                assert safe[i].covers(Point(a)),('gate moved off blood',kind,i)
                assert tissue.covers(Point(b))
                assert unary_union([safe[i],tissue,geometry(gate_contract['throatRings'])]).covers(LineString([a,b]))
                d['gateContracts'][kind].append(gate_contract)
                gate_records.append({'kind':kind,'id':gate_contract['id'],'lane':i,'anchorsPreserved':True})
    # Crossing is explicit depth, never an AV graph shortcut or coincident mouth.
    clearance=Point(nodes['small_intestine.exit']).distance(LineString(current[134]['points']))
    assert clearance>10,clearance
    write(OUT/'runtime-data.json',d)
    write(OUT/'network.json',list(current.values()))
    (OUT/'BowelBattlefieldData.lua').write_text('-- Real intestinal blood routes; compiled by prepare_bowel_remodel.py.\nreturn '+lua(d)+'\n')
    report={'status':'STAGED_GEOMETRY','changedLanes':sorted(CHANGED),'ownedLanes':sorted(OWNED),
            'namedNodesMoved':nodes,'gateChecks':gate_records,'smallReturnToArteryClearanceSource':clearance,
            'tissueGridsUnchanged':True,'originalReferenceUnchanged':True,'edgeCount':len(current),
            'lengths':{i:{'before':LineString(old[i]['points']).length,'after':LineString(current[i]['points']).length}for i in CHANGED}}
    write(OUT/'geometry-check.json',report)
    print(json.dumps({k:report[k]for k in ['status','changedLanes','smallReturnToArteryClearanceSource','edgeCount']}))
if __name__=='__main__':main()
