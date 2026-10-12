"""Render source bitmap versus selected fixed pigment vector fill, no organ redraw.
SVG/Cairo comparison only; native renderer still requires acceptance.
"""
from pathlib import Path
import io,json
import numpy as np
from PIL import Image,ImageDraw
import body_life_backend as b
out=Path('/tmp/organ-foreground');out.mkdir(exist_ok=True)
b.l.execute("R=require('war.Render');R.vg={};R.w=1000;R.h=800;s={anatomyVersion=4};g={zoom=.4};atlas=nvgCreateImage(R.vg,'image/anatomy-reference/reference.png',0)")
report={}
for name,(cx,cy) in {'lung':(437,373),'heart':(520,418),'great-vein':(482,360)}.items():
 images=[]
 for on in [False,True]:
  b.reset();b.l.execute(f'g.camera={{x={cx*2},y={cy*2+512}}}')
  b.l.execute("local x,y=R.project(g,0,512);local z=64*g.zoom;nvgBeginPath(R.vg);nvgRect(R.vg,x,y,1024*z,1536*z);nvgFillPaint(R.vg,nvgImagePattern(R.vg,x,y,1024*z,1536*z,0,atlas,1));nvgFill(R.vg)")
  if on:b.l.execute(f"require('war.OrganForeground').draw(R,g,s,{cx*2-1000/(32*.4)/2},{cx*2+1000/(32*.4)/2},{cy*2+512-800/(32*.4)/2},{cy*2+512+800/(32*.4)/2})")
  im=Image.open(io.BytesIO(b.png(1000,800))).convert('RGB');im.save(out/(name+('-after' if on else '-before')+'.png'));images.append(im)
 pair=Image.new('RGB',(2000,830),'white');pair.paste(images[0],(0,30));pair.paste(images[1],(1000,30));d=ImageDraw.Draw(pair);d.text((12,9),'Source bitmap at zoom .4',fill='black');d.text((1012,9),'Selected blue/coronary fill; no strokes',fill='black');pair.save(out/(name+'-comparison.png'))
 before,after=[np.asarray(im,dtype=np.int16) for im in images];delta=np.abs(after-before)
 report[name]={'changedPixels':int(np.count_nonzero(np.max(delta,axis=2)>5)),'maxChannelDelta':int(delta.max())}
(out/'report.json').write_text(json.dumps(report,indent=2));print(report)
