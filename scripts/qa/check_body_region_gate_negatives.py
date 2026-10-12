"""Rebuild final graph with each body gate omitted; same coordinates/radii stay fixed."""
from pathlib import Path
import hashlib,json,os
from lupa.lua54 import LuaRuntime
from check_stomach_connectivity import lua,convert
ROOT=Path(__file__).resolve().parents[2];os.chdir(ROOT);DOC=ROOT/'docs/body-life/vascular-art-study'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
paths=[Path(__file__),*(ROOT/'scripts/war'/f for f in ('BodyRegionAccessStudy.lua','OrganAccessStudy.lua','StomachConnectivityStudy.lua','OrganRouteCollisionStudy.lua','TissueGeometry.lua','Path.lua','World.lua','Vessels.lua')),*[DOC/f for f in ('body-region-candidates.json','interface-contract.json','passages-data.json','network.json')]]
hashes={str(p.relative_to(ROOT)):sha(p) for p in paths}
body,contract,data,network=[json.loads((DOC/f).read_text()) for f in ('body-region-candidates.json','interface-contract.json','passages-data.json','network.json')]
fixtures=[]
for region in body['regions']:
 data['zones'].append(dict(id=region['id'],outlines=region['boundaryRings'],forbiddenEdges=[]))
 if region['id'] not in ('arm_r','leg_r'):continue
 gate=next(p for r in contract['regions'] if r['id']==region['id'] for p in r['ports'] if p.get('exitToTissue'))
 edges=sorted(set([e['id'] for e in network['edges'] if e['a'].startswith(region['id']+'.') or e['b'].startswith(region['id']+'.')]+[gate['edge']]))
 fixtures.append(dict(region=region['id'],name='body.'+region['id']+'.clear_bank',tissueEdgeIds=edges))
setup="package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={};print=function()end;local L=require('war.BodyRegionAccessStudy').create(require('war.OrganAccessStudy').create(require('war.StomachConnectivityStudy')));"
results=[]
for f in fixtures:
 full=LuaRuntime(unpack_returned_tuples=True);full.execute(setup+"package.loaded['war.ReferenceVessels']=L")
 full.execute('qaName='+lua(f['name']))
 fixed=convert(full.execute("local W=require('war.World');local s=W.generate(73,nil,nil,nil,4);W.rebuild(s);local net=W.vessels(s);for _,g in ipairs(net.gates)do if g.name==qaName then return {x=g.x,y=g.y,px=g.px,py=g.py,nx=g.nx,ny=g.ny,edge=g.edge,gates=#net.gates}end end"))
 for omit in (False,True):
  rt=LuaRuntime(unpack_returned_tuples=True)
  rt.execute('qaName='+lua(f['name'])+';qaOmit='+lua(omit))
  rt.execute(setup+"if qaOmit then for i=#L.gates,1,-1 do if L.gates[i].name==qaName then table.remove(L.gates,i)end end end;package.loaded['war.ReferenceVessels']=L")
  rt.execute('qaData='+lua(data)+';qaFixed='+lua(fixed)+';qaFixture='+lua(f))
  records=convert(rt.execute(r'''
local W,P,K=require('war.World'),require('war.Path'),require('war.CellCollision');local M=require('war.OrganRouteCollisionStudy');local L=require('war.ReferenceVessels')
local s=W.generate(73,nil,nil,nil,4);W.rebuild(s);local net=W.vessels(s);local model=M.prepare(qaData);local context={zone=qaFixture.region,tissueEdges={}}
for _,id in ipairs(qaFixture.tissueEdgeIds)do context.tissueEdges[L.edgeIndexById[id]]=true end
local unG=require('war.TissueGeometry').attachForTest(require('war.PassageCollisionStudy'),M,model);local un=M.attachForTest(model,context,net,W)
local found=false;for _,g in ipairs(net.gates)do if g.name==qaName then found=true end end
assert(found~=qaOmit);assert(#net.gates==qaFixed.gates-(qaOmit and 1 or 0))
local a={x=qaFixed.px,y=qaFixed.py,lane=qaFixed.edge};local b={x=qaFixed.x+qaFixed.nx*5.2,y=qaFixed.y+qaFixed.ny*5.2,lane=0};local records={}
for _,kind in ipairs({'scout','worker','siege'})do context.radius=K.radius(kind)
 for direction=1,2 do local from,to=a,b;if direction==2 then from,to=b,a end
 local clear=P.clear(s,from.x,from.y,to.x,to.y,1,from.lane,to.lane)
 records[#records+1]={gate=qaName,kind=kind,radius=context.radius,direction=direction==1 and 'outward' or 'inward',gateRemoved=qaOmit,freshNetworkRebuilt=true,gateCount=#net.gates,from=from,to=to,startAllowed=M.allowed(model,context,net,from.x,from.y,from.lane),endAllowed=M.allowed(model,context,net,to.x,to.y,to.lane),clear=not not clear,pass=qaOmit and not clear or not qaOmit and clear}
 end
end
un();unG();return records
'''))
  results.extend(records)
assert all(sha(ROOT/p)==h for p,h in hashes.items()),'inputs changed'
report=dict(testedHashes=hashes,records=results,summary=dict(cases=len(results),negativeCases=sum(r['gateRemoved'] for r in results),positiveControls=sum(not r['gateRemoved'] for r in results),passed=sum(r['pass'] for r in results)),method='Independent Lua runtimes rebuild W.generate and Vessels gate buckets for each omitted gate, preserving exact coordinates and all radii. Same-lumen anchor to tissue endpoint, both directions; no wall widening.')
(DOC/'body-region-navigation-evidence/gate-negatives.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(report['summary'])
for r in results:
 if not r['pass']:print(r)
assert all(r['pass'] for r in results)
