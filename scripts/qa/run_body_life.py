"""Run body-life contracts and existing regressions without replacing baseline reports."""
from pathlib import Path
from lupa.lua54 import LuaRuntime, lua_type
import json
import argparse
parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output',default='docs/body-life/regression-results.json');args=parser.parse_args()

def convert(v):
    if lua_type(v)!='table':return v
    keys=list(v.keys())
    if keys and all(isinstance(k,int) for k in keys):return [convert(v[i]) for i in range(1,len(keys)+1)]
    return {k:convert(value) for k,value in v.items()}

suites=['OrganForegroundAcceptance','OrganBoundariesAcceptance','BodyLifeAcceptance','BodyLifeMotionAcceptance','BodyLifeFlowAcceptance','BattleHUDAcceptance','ReferenceAcceptance','ReferenceRenderAcceptance','AnatomyAcceptance','NasalAcceptance','NasalTerrainAcceptance','VesselAcceptance','SmoothAcceptance','ZoomAcceptance','Acceptance']
report={}
for suite in suites:
    l=LuaRuntime(unpack_returned_tuples=True)
    l.execute("package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={};print=function() end")
    r=convert(l.eval(f"require('war.{suite}').run()"));report[suite]=r
    print(suite,r['passed'],r['total'],flush=True)
    for item in r['results']:
        if not item['pass']:print('FAIL',item['name'],item['error'],flush=True)
check=l.eval('function(s,n) local f,e=load(s,n);return f~=nil,e end')
errors=[]
for p in Path('scripts').rglob('*.lua'):
    ok,err=check(p.read_text(),str(p))
    if not ok:errors.append({'file':str(p),'error':err})
report['syntaxErrors']=errors
Path(args.output).parent.mkdir(parents=True,exist_ok=True)
Path(args.output).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
assert not errors,errors
assert all(report[s]['passed']==report[s]['total'] for s in suites)
