"""Audit close-up fill coverage/budgets and the .15 transition using actual Lua.
This measures draw commands, not native frame time.
"""
from pathlib import Path
import hashlib, io, json
import numpy as np
from PIL import Image
import render_body_life as r
from render_practical_fill import SCENARIOS

r.initialise(); b=r.b; root=b.ROOT; out=root/'docs/body-life/practical-fill'
results=[];records=[]
def check(name,passed,**evidence):results.append(dict(name=name,passed=bool(passed),**evidence))
check('Gameplay trace and reference PNG untouched',
      (root/'scripts/war/ReferenceTrace.lua').read_bytes()==(out/'baseline/ReferenceTrace.lua').read_bytes()
      and hashlib.sha256((root/'assets/image/anatomy-reference/reference.png').read_bytes()).hexdigest()=='9a04e39961c07073cd9fdcfcdc2c98253ccc25d968e97dbea1f36669e06b5d9f')
# A single fixed crop changes smoothly as the actual game zoom crosses .15.
images=[]
for z in [.149,.15,.151]:
    b.reset();w,h=640,480;cy=72*2+512-.03*h/(32*z)
    b.l.execute(f"game.zoom={z};game.camera={{x=1024,y={cy}}};graphics={{GetWidth=function() return {w} end,GetHeight=function() return {h} end,GetDPR=function() return 1 end}};R.draw(game)")
    data=b.png(w,h);(out/f'transition-{z}.png').write_bytes(data)
    images.append(np.asarray(Image.open(io.BytesIO(data)).convert('RGB'),dtype=np.int16))
diffs=[float(np.abs(a-c).mean()) for a,c in zip(images,images[1:])]
check('No full-frame color jump across .149/.15/.151',max(diffs)<4,meanAbsoluteRgbDifferences=diffs)

b.l.execute('fillCalls=0')
for name in b.functions:
    if name.startswith('nvg') and name not in ['nvgCreateImage','nvgDeleteImage','nvgRGBA','nvgRGBAf','nvgLinearGradient','nvgRadialGradient','nvgImagePattern','nvgImagePatternTinted']:
        b.G[name]=b.l.eval('function(...) fillCalls=fillCalls+1 end')
zooms=[.085,.1,.149,.15,.151,.299,.3,.301,.699,.7,.701,1.399,1.4,1.401,2.8]
for ident,_,sx,sy in SCENARIOS:
    for w,h in [(1440,900),(1024,768),(844,390),(430,932),(360,780)]:
        for z in zooms:
            cy=sy*2+512-.03*h/(32*z)
            b.l.execute(f"fillCalls=0;game.zoom={z};game.camera={{x={sx*2},y={cy}}};graphics={{GetWidth=function() return {w} end,GetHeight=function() return {h} end,GetDPR=function() return 1 end}};R.draw(game)")
            a=b.l.eval("require('war.ReferenceArt')")
            records.append(dict(view=ident,size=[w,h],zoom=z,calls=int(b.G.fillCalls),regions=int(a.last.regions),details=int(a.last.details)))
check('Five device sizes and all organ/LOD probes stay within existing draw budgets',
      all(x['calls']<30000 and x['regions']<800 and x['details']==0 for x in records),
      samples=len(records),maximumCalls=max(x['calls'] for x in records),maximumRegions=max(x['regions'] for x in records))
report=dict(passed=sum(x['passed'] for x in results),total=len(results),results=results,nativeEvidence=False,budgetProbes=records)
(out/'fill-checks.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:v for k,v in report.items() if k!='budgetProbes'},ensure_ascii=False,indent=2))
assert report['passed']==report['total']
