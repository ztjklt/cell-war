"""Exact BVH vs original geometry, including boundary-near adversarial points."""
from pathlib import Path
import json,hashlib,random
from lupa.lua54 import LuaRuntime
from check_stomach_connectivity import lua,convert
R=Path(__file__).resolve().parents[2];D=R/'docs/body-life/vascular-art-study'
data=json.loads((D/'passages-data.json').read_text());body=json.loads((D/'body-region-candidates.json').read_text())
for r in body['regions']:data['zones'].append(dict(id=r['id'],outlines=r['boundaryRings'],forbiddenEdges=[]))
rng=random.Random(83017);points=[]
for z in data['zones']:
 vertices=[p for r in z['outlines'] for p in r['points']];xmin=min(p[0] for p in vertices)-2;xmax=max(p[0] for p in vertices)+2;ymin=min(p[1] for p in vertices)-2;ymax=max(p[1] for p in vertices)+2
 for _ in range(800):points.append([z['id'],rng.uniform(xmin,xmax),rng.uniform(ymin,ymax)])
 for p in vertices:
  for dx,dy in [(0,0),(1e-7,0),(-1e-7,0),(0,1e-7),(0,-1e-7)]:points.append([z['id'],p[0]+dx,p[1]+dy])
rt=LuaRuntime(unpack_returned_tuples=True);rt.execute("package.path='scripts/?.lua;'..package.path")
rt.execute('qaData='+lua(data)+';qaPoints='+lua(points))
r=convert(rt.execute('''local B=require('war.PassageCollisionStudy');local G=require('war.TissueGeometry');local model=B.prepare(qaData);local start=os.clock();local prepared=G.prepare(model);local setup=os.clock()-start;local maxError=0;local mismatch=0;local reference={};start=os.clock()
for i,p in ipairs(qaPoints)do reference[i]=B.clearance(model,p[1],p[2],p[3])end
local oldTime=os.clock()-start;start=os.clock()
for i,p in ipairs(qaPoints)do local n=G.clearance(prepared,p[1],p[2],p[3]);local old=reference[i];local error=math.abs(n-old);maxError=math.max(error,maxError);if error>1e-9 or (n>=.55125)~=(old>=.55125)then mismatch=mismatch+1 end end
local newTime=os.clock()-start;local collision={clearance=B.clearance};local before=B.clearance;local un=G.attachForTest(B,collision,model);assert(B.clearance~=before);un();assert(B.clearance==before and collision.clearance==before)
return {points=#qaPoints,mismatches=mismatch,maxError=maxError,oldCpuSeconds=oldTime,newCpuSeconds=newTime,setupCpuSeconds=setup,speedup=oldTime/newTime,uninstallRestored=true}'''))
r.update(inputHashes={f:hashlib.sha256((D/f).read_bytes()).hexdigest() for f in ['passages-data.json','body-region-candidates.json']},moduleSha256=hashlib.sha256((R/'scripts/war/TissueGeometry.lua').read_bytes()).hexdigest(),qaScriptSha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),scope='Exact boundary distance/parity equivalence; Python/Lupa CPU comparison only, not native frame performance')
assert r['mismatches']==0,r
(D/'tissue-geometry-evidence.json').write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n');print(r)
