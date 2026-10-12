"""Verify the accepted heartbeat/flow scope using actual Lua renders."""
from pathlib import Path
import io,json,hashlib
import numpy as np
from PIL import Image
import render_body_life as renderer
b=renderer.b
renderer.initialise()
b.l.execute("A=require('war.ReferenceArt');M=require('war.ReferenceMap');B=require('war.BodyLife')")
results=[]
def picture(t,x,y,z=.4,flow=False):
 b.reset();w,h=480,360
 cy=y*2+512-.03*h/(32*z)
 b.l.execute(f"R.w={w};R.h={h};game.camera={{x={x*2},y={cy}}};game.zoom={z};game.realTime={t};local x1,x2,y1,y2=require('war.View').bounds(game,R.w,R.h,0);nvgBeginFrame(R.vg,{w},{h},1);A.draw(R,game,state,x1,x2,y1,y2);A.details(R,game,state,x1,x2,y1,y2);{'A.flow(R,game,state,x1,x2,y1,y2);' if flow else ''}nvgEndFrame(R.vg)")
 return np.asarray(Image.open(io.BytesIO(b.png(w,h))).convert('RGB'))
for o in b.l.globals().M.organs.values():
 if o.id=='heart':continue
 a=picture(.13,o.x*.5,(o.y-512)*.5);c=picture(3.6,o.x*.5,(o.y-512)*.5)
 maximum=int(np.abs(a.astype(int)-c.astype(int)).max())
 results.append(dict(name=o.id+' restored static closeup',passed=maximum==0,maxRgbDifference=maximum))
a=picture(.13,515,420,.04);c=picture(.39,515,420,.04)
results.append(dict(name='heartbeat remains active',passed=bool(np.any(a!=c)),changedPixels=int(np.any(a!=c,axis=2).sum())))
a=picture(.13,512,367,.025,True);c=picture(1.13,512,367,.025,True)
results.append(dict(name='vessel flow remains active',passed=bool(np.any(a!=c)),changedPixels=int(np.any(a!=c,axis=2).sum())))
b.l.execute("Assets=require('war.BodyLifeAssets')");assets=b.l.globals().Assets
results.append(dict(name='no generated organ texture in runtime pack',passed=not assets.tissue and not assets.foreground))
report=dict(passed=sum(x['passed'] for x in results),total=len(results),results=results,nativeEvidence=False,sourceSha256=hashlib.sha256((b.ROOT/'assets/image/anatomy-reference/reference.png').read_bytes()).hexdigest())
r=b.ROOT/'docs/body-life/rollback-heart-flow';r.mkdir(parents=True,exist_ok=True);(r/'scope-checks.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2));assert report['passed']==report['total']
