"""Check candidate true nodes against production curves and swept-disk lanes.

This tests short local joins, not full organ travel, crowds or native gameplay.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys
from lupa.lua54 import LuaRuntime

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(Path(__file__).parent))
from check_regional_vascular_refinement import convert

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('candidate',type=Path)
    parser.add_argument('--contract-key',default='nodeBankRefinement')
    args=parser.parse_args();out=args.candidate.resolve()
    manifest=json.loads((out/'manifest.json').read_text());contract=manifest[args.contract_key]
    graph={e['id']:e for e in json.loads((ROOT/'docs/body-life/vascular-art-study/final-reference-data.json').read_text())['edges']}
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.execute("package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={};print=function()end;s=require('war.FullBodyBattlefield').new(72026);O=require('war.OrganBattlefield');P=require('war.Path');net=O.net(s)")
    rows=[];geometry=[];checked=set()
    for region in contract['regions']:
        indices=[int(key[1:]) for key in region['edgeIds']]
        first,second=indices
        curves=[]
        for key,index in zip(region['edgeIds'],indices):
            edge=lua.globals().net.edges[index];curve=convert(edge['points']);curves.append(curve)
            if key in checked:continue
            checked.add(key);expected=[[p[0]*2,p[1]*2+512] for p in graph[key]['samples']]
            same=len(curve)==len(expected) and all(abs(a[0]-b[0])<1e-8 and abs(a[1]-b[1])<1e-8 for a,b in zip(curve,expected))
            geometry.append({'edge':key,'stableId':edge['stableId'],'curveSamples':len(curve),'sourceWidth':graph[key]['lumenWidthSource'],
                'worldWidth':edge['width'],'pass':same and edge['stableId']==key and abs(edge['width']-graph[key]['lumenWidthSource']*2)<1e-8})
        a,b=curves
        assert a[-1]==b[0]==[region['center'][0]*2,region['center'][1]*2+512]
        for kind in ['scout','worker','siege']:
            for reverse in [False,True]:
                fr,to=(second,first) if reverse else (first,second)
                start,end=(b[1],a[-2]) if reverse else (a[-2],b[1])
                entity=lua.table_from({'kind':kind,'faction':1,'vesselLane':fr})
                result=lua.globals().P.clear(lua.globals().s,*start,*end,1,fr,to,entity)
                passed=result[0] if isinstance(result,tuple) else result
                rows.append({'node':region['id'],'kind':kind,'reverse':reverse,'fromLane':fr,'toLane':to,'pass':bool(passed)})
    for path,digest in contract['frozenRuntimeHashes'].items():assert sha(ROOT/path)==digest,path
    status='PASS' if all(r['pass'] for r in rows+geometry) else 'FAIL'
    report={'status':status,'manifestSha256':sha(out/'manifest.json'),'dataSha256':sha(out/'FullBodyMapArtData.lua'),
            'geometryChecks':geometry,'checks':rows,'testCount':len(rows),'nativeEvidence':False,
            'frozenRuntimeHashes':contract['frozenRuntimeHashes'],
            'testedEntry':'war.FullBodyBattlefield.new(72026)','testedAPI':'war.Path.clear',
            'limits':['Short centreline joins in both directions with three swept-disk sizes; not complete organ travel or traffic verification.']}
    (out/'node-navigation-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'status':status,'curveChecks':len(geometry),'nodeSweepChecks':len(rows)}))
    assert status=='PASS'

if __name__=='__main__':main()
