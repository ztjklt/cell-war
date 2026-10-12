"""Bounded large-zoom SurfacePattern contracts; no native GPU performance claim."""
from pathlib import Path
import io,json,resource
from PIL import Image
import numpy as np
import body_life_backend as b

def main():
 results=[];details={};ident=900001
 pixels=Image.new('RGBA',(4,4),(220,40,30,255))
 for y in range(4):
  for x in range(2,4):pixels.putpixel((x,y),(30,180,70,255))
 tex=b.texture('qa-native-pattern',pixels);b.decoded_images['qa-native-pattern']=tex;b.image_handles[ident]=tex;b.image_flags[ident]=0
 def check(name,fn):
  try:fn();results.append({'name':name,'pass':True})
  except Exception as ex:results.append({'name':name,'pass':False,'error':str(ex)})
 def frame(x,y,w,h,opacity=1,alpha=1,tint=None,dpr=1,angle=0):
  b.reset();b.begin_frame(None,64,48,dpr);b.rect(None,0,0,64,48);b.global_alpha(None,alpha);b.setfill(None,b.image_pattern(None,x,y,w,h,angle,ident,opacity,tint));b.fill_path();return np.array(Image.open(io.BytesIO(b.png(64,48,dpr))).convert('RGBA'))
 def huge():
  rows=[]
  for scale in (9.6,25.6,57.6,1000):
   w,h=1024*scale,1536*scale;a=frame(32-w*.75,24-h*.25,w,h);color=a[24,32]
   assert np.max(np.abs(color.astype(int)-[30,180,70,255]))<=1,color
   rows.append({'sourceDisplayedWidth':w,'sourceDisplayedHeight':h,'sample':color.tolist()})
  details['largePatterns']=rows;details['processPeakRssBytes']=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
 check('Large zoom patterns retain native texture allocation and correct sampled coordinates',huge)
 def alpha():
  a=frame(-300,-100,400,400,.4,.5);actual=a[24,32]
  assert abs(int(actual[3])-51)<=1,actual
  assert max(abs(int(actual[i])-v) for i,v in enumerate((30,180,70)))<=4,actual
  details['alphaProduct']=actual.tolist()
 check('Image opacity and global alpha multiply once under bounded patch groups',alpha)
 def tint():
  a=frame(-300,-100,400,400,.5,.5,(128,255,128));actual=a[24,32]
  assert abs(int(actual[3])-64)<=1,actual
  assert max(abs(int(actual[i])-v) for i,v in enumerate((15,180,35)))<=4,actual
  details['tint']=actual.tolist()
 check('Tint RGB and alpha remain correct through SurfacePattern sampling',tint)
 def repeat():
  b.image_flags[ident]=0;pad=frame(-128,0,128,128)[24,32]
  b.image_flags[ident]=b.G.NVG_IMAGE_REPEATX|b.G.NVG_IMAGE_REPEATY;tile=frame(-128,0,128,128)[24,32]
  b.image_flags[ident]=0
  assert pad[1]>150 and tile[0]>180,(pad,tile)
  details['clampAndRepeat']=[pad.tolist(),tile.tolist()]
 check('Default edge clamp and explicit repeat flags use distinct sampling modes',repeat)
 def dpr():
  colors=[]
  for d in (1,2,3):
   a=frame(-30000,-10000,40000,40000,.6,.5,dpr=d);colors.append(a[24*d,32*d].tolist());assert a.shape==(48*d,64*d,4)
  assert max(abs(a-b) for c in colors for a,b in zip(c,colors[0]))<=2,colors
  details['dprColors']=colors
 check('DPR scales output while giant pattern coordinates remain logical',dpr)
 b.delete_image(None,ident)
 report={'nativeEvidence':False,'passed':sum(x['pass'] for x in results),'total':len(results),'results':results,'evidence':details,'limitations':['Cairo sampling differs from NanoVG filtering.','Peak RSS includes Python libraries and is diagnostic only.']}
 out=Path('docs/body-life/closeup-interactive-v2/backend-pattern-checks.json');out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2));assert report['passed']==report['total']
if __name__=='__main__':main()
