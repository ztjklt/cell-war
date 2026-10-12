"""Deterministic scheduler lifecycle/budget/memo checks, separate from route evidence."""
from pathlib import Path
import json,hashlib,os
from lupa.lua54 import LuaRuntime
from check_stomach_connectivity import convert
ROOT=Path(__file__).resolve().parents[2];os.chdir(ROOT);path=ROOT/'scripts/war/BodyRegionNavigationStudy.lua';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();before=sha(path)
l=LuaRuntime(unpack_returned_tuples=True);l.execute("package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={}")
result=convert(l.execute(r'''
local N=require('war.BodyRegionNavigationStudy');local checks={}
local function setup()
 local context={zone='one',radius=.4375,tissueEdges={[201]=true}}
 local P={request=function()end,update=function()end,reset=function()end,clear=function()return false end}
 local e={id=1,kind='scout',x=0,y=0,orderToken=1,vesselLane=0,orders={{x=100,y=0,vesselLane=0}}};local s={entities={[1]=e}}
 local un,stats,jobs=N.attachForTest(P,{}, {},context);P.request(s,e,100,0)
 return P,e,s,un,stats,jobs,context
end
local oldNode,oldCpu=N.maxExpandedPerJob,N.maxCpuPerJob
local P,e,s,un,stats,jobs,context=setup();N.maxExpandedPerJob=1;P.update(s,500,.003)
checks[#checks+1]={id='module-node-budget',pass=e.pathFailed and N.getFailure(e)=='BODY_REGION_NODE_BUDGET_EXCEEDED' and #jobs==0};un();N.maxExpandedPerJob=oldNode
P,e,s,un,stats,jobs,context=setup();N.maxCpuPerJob=0;P.update(s,500,.003)
checks[#checks+1]={id='module-cpu-budget',pass=e.pathFailed and N.getFailure(e)=='BODY_REGION_CPU_BUDGET_EXCEEDED' and #jobs==0};un();N.maxCpuPerJob=oldCpu
P,e,s,un,stats,jobs,context=setup();un();checks[#checks+1]={id='uninstall-pending-cleanup',pass=not e.pathPending and #jobs==0}
P,e,s,un,stats,jobs,context=setup();P.reset();checks[#checks+1]={id='reset-pending-cleanup',pass=not e.pathPending and #jobs==0};un()
P,e,s,un,stats,jobs,context=setup();e.orderToken=2;P.update(s,500,.003)
checks[#checks+1]={id='cancel-does-not-install-old-route',pass=#jobs==0 and not e.path[1] and stats.cancelled==1};un()
local entity={id=91,kind='worker'};N.setContext(entity,{zone='private',radius=1,tissueEdges={[9]=true}})
local clean=true;for k in pairs(entity)do if k~='id' and k~='kind' then clean=false end end
checks[#checks+1]={id='private-context-does-not-pollute-save-entity',pass=clean};N.setContext(entity,nil);N.clearDiagnostics(entity)
local B={clearance=function(m,z,x,y)return x+y end};local C={clearance=B.clearance};local model={}
local remove,memo=N.cacheGeometry(B,C,model)
for i=1,50005 do assert(B.clearance(model,'a',i,0)==i)end
local near=1+2^-52;assert(B.clearance(model,'precision',1,0)==1);assert(B.clearance(model,'precision',near,0)==near)
assert(B.clearance(model,'precision',near,0)==near)
checks[#checks+1]={id='memo-bounded-and-exact',pass=memo.peak==50000 and memo.count<=50000 and memo.evictions==7 and memo.hits>=1,stats=memo}
remove();for _,c in ipairs(checks)do assert(c.pass,c.id)end
return {checks=checks,passed=#checks,failed=0}
'''))
assert sha(path)==before;result['moduleSha256']=before;result['testSha256']=sha(Path(__file__));p=ROOT/'docs/body-life/vascular-art-study/body-region-navigation-evidence/scheduler.json';p.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(result)
