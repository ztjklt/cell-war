"""Publish fixed-coordinate inspection data and real Lua movement replays.

The browser only replays recorded positions. It does not simulate cell movement
or certify final organ textures / native rendering.
"""
from pathlib import Path
import json, shutil, hashlib
from lupa.lua54 import LuaRuntime

ROOT=Path(__file__).resolve().parents[2]
DOC=ROOT/'docs/body-life/vascular-art-study'
PUB=ROOT/'docs/body-life/previews/visible-life/vascular-art-study'

def main():
    rt=LuaRuntime(unpack_returned_tuples=True)
    rt.execute("package.path='scripts/?.lua;'..package.path")
    m=rt.eval("require('war.ReferenceMap')")[0]
    def points(p):return [[p[i][1]/2,(p[i][2]-512)/2] for i in range(1,len(p)+1)]
    geometry=dict(outline=points(m.outline),organs=[dict(id=o.id,name=o.name,points=points(o.points)) for o in m.organs.values()])
    # These constants are checked against actual renderer output by the zoom QA.
    geometry['projection']=dict(sourceScale=2,worldOffsetY=512,logicalCellSize=32,overviewEnd=.085,fillFull=.15)
    (DOC/'inspection-geometry.json').write_text(json.dumps(geometry,ensure_ascii=False,separators=(',',':'))+'\n')
    report=json.loads((DOC/'navigation-review.json').read_text())
    graph=DOC/'network.json'
    assert report['sourceSha256']==hashlib.sha256(graph.read_bytes()).hexdigest(), 'stale movement report'
    for name,digest in report['testedModuleHashes'].items():
        assert hashlib.sha256((ROOT/'scripts/war'/name).read_bytes()).hexdigest()==digest, 'stale tested module: '+name
    network=json.loads(graph.read_text());nodes={n['id']:n for n in network['nodes']}
    contract={'sourceNetworkSha256':report['sourceSha256'],'sourceSize':[1024,1536],
              'transform':geometry['projection'],'scope':'shared world/local map authoring contract; isolated navigation fixture',
              'regions':[],'adapterOnlyAdditions':report['adapterOnlyAdditions']}
    for o in network['organs']:
        actual=next(i for i in report['interfaces'] if i['id']==o['id'])
        ports=[]
        for role,key in [('supply','entryGate'),('return','exitGate'),('portalSupply','secondaryEntryGate')]:
            if key not in o:continue
            n=nodes[o[key]];ports.append(dict(id=n['id'],role=role,source=[n['x'],n['y']],world=[2*n['x'],2*n['y']+512],exitToTissue=False))
        ports.append(dict(id=o['tissueAccess']['id'],role='controlledTissueAccess',source=actual['adjustedGateSource'],world=actual['membraneCentre'],insideWorld=actual['insidePoint'],outsideWorld=actual['outsidePoint'],edge=actual['accessEdge'],exitToTissue=True))
        contract['regions'].append(dict(id=o['id'],name=o['name'],ports=ports,foodPassage=False))
    (DOC/'interface-contract.json').write_text(json.dumps(contract,ensure_ascii=False,indent=2)+'\n')
    for name in ['inspection.html','inspection.js','inspection-geometry.json','navigation-review.json','network.json','interface-contract.json','gate-calibration.json','maintenance.html']:
        shutil.copy2(DOC/name,PUB/name)
    print('Published real Lua movement replay and source-coordinate inspection')

if __name__=='__main__':main()
