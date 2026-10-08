"""Run isolated Lua 5.4 map/campaign regressions. Offline dependency: lupa."""
from pathlib import Path
import json, os
from lupa.lua54 import LuaRuntime, lua_type
root=Path(__file__).resolve().parents[2]
os.chdir(root)
def convert(value):
    if lua_type(value)!='table':return value
    keys=list(value.keys())
    if keys and all(isinstance(k,int) for k in keys):return [convert(value[i]) for i in range(1,len(keys)+1)]
    return {k:convert(v) for k,v in value.items()}
suites=['GameplayUpdateAcceptance','BattleHUDAcceptance','ReferenceAcceptance','ReferenceRenderAcceptance','AnatomyAcceptance','NasalAcceptance','NasalTerrainAcceptance','VesselAcceptance','SmoothAcceptance','ZoomAcceptance','Acceptance']
report={}
for suite in suites:
    runtime=LuaRuntime(unpack_returned_tuples=True)
    runtime.execute("package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={};print=function() end")
    result=convert(runtime.eval(f"require('war.{suite}').run()"));report[suite]=result
    print(suite,result['passed'],result['total'],flush=True)
    for r in result['results']:
        if not r['pass']:print('FAIL',r['name'],r['error'],flush=True)
runtime=LuaRuntime(unpack_returned_tuples=True)
check=runtime.eval('function(text,name) local fn,err=load(text,name);return fn~=nil,err end')
errors=[]
files=list(Path('scripts').rglob('*.lua'))
for file in files:
    ok,err=check(file.read_text(),str(file))
    if not ok:errors.append({'file':str(file),'error':err})
report['syntax']={'files':len(files),'errors':errors}
Path('docs/reference-map-regression-results.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
assert not errors,errors
assert all(report[s]['passed']==report[s]['total'] for s in suites),'regression failures'
print('TOTAL',sum(report[s]['passed'] for s in suites),'syntax',len(files))
