from pathlib import Path
import json,time
from lupa.lua54 import LuaRuntime
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute("package.loaded['urhox-libs/UI']={};package.path='scripts/?.lua;scripts/?/init.lua;'..package.path")
def convert(v):
 if hasattr(v,'items'):
  d={k:convert(x) for k,x in v.items()}
  return [d[i] for i in range(1,len(d)+1)] if d and all(isinstance(k,int) for k in d) else d
 return v
syntax=[]
for p in Path('scripts').rglob('*.lua'):
 r=lua.eval('loadfile')(str(p))
 if isinstance(r,tuple):syntax.append([str(p),r[1]])
print('syntax',syntax,flush=True)
results={}
for name in ['AnatomyAcceptance','NasalAcceptance','NasalTerrainAcceptance','VesselAcceptance','SmoothAcceptance','ZoomAcceptance','Acceptance']:
 t=time.time()
 try:
  m=lua.eval('require')(f'war.{name}');m=m[0] if isinstance(m,tuple) else m
  results[name]=convert(m.run());print(name,round(time.time()-t,2),json.dumps(results[name],ensure_ascii=False),flush=True)
 except Exception as e:results[name]={'error':str(e)};print(name,str(e),flush=True)
Path('docs/anatomy-v2-regression-results.json').write_text(json.dumps({'syntax':syntax,'suites':results},ensure_ascii=False,indent=2))
