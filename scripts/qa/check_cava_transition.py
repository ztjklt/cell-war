"""No transverse seam, open lumen and shared heartbeat display registration."""
import sys,json,hashlib
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
from shapely.geometry import LineString,Point,box
sys.path.insert(0,str(Path(__file__).parent))
import body_life_backend as b
from build_cava_transition import OUT,BOX,SIZE
from register_simple_heart import rings
from build_heart_perimeter import mask

def main():
 b.G.qaSource=(OUT/'HeartVisualData.lua').read_text()
 b.l.execute("package.loaded['war.HeartVisualData']=assert(load(qaSource))()")
 b.l.execute('''
 S=require('war.FullBodyBattlefield').new(72026);S.entities={};N=require('war.OrganBattlefield').net(S)
 R=require('war.Render');R.vg={};R.font=1;A=require('war.FullBodyMapArt');H=require('war.HeartVisualData');T=require('war.HeartDisplayTransform')
 A.prepare(R.vg);require('war.Cells').init(R.vg);R.prepare(S);dpr=1
 graphics={GetWidth=function()return 1480*dpr end,GetHeight=function()return 1692*dpr end,GetDPR=function()return dpr end}
 g={state=S,zoom=.15625,camera={x=1012,y=1283.048},selection={},started=true,fogDisabled=true,realTime=0,bodyLifeEnabled=false}
 ''')
 b.reset();b.G.R.draw(b.G.g);(OUT/'map-after.png').write_bytes(b.png(*SIZE))
 old=Image.open(b.ROOT/'docs/heart-simple-20261012/transparent-margin-v12/map-after.png').convert('RGB')
 new=Image.open(OUT/'map-after.png').convert('RGB');crop=(260,1030,540,1270)
 comparison=Image.new('RGB',(560,268),'#f8f1e8');comparison.paste(old.crop(crop),(0,28));comparison.paste(new.crop(crop),(280,28))
 draw=ImageDraw.Draw(comparison);draw.text((8,8),'BEFORE',fill='#3f3237');draw.text((288,8),'AFTER',fill='#3f3237');comparison.save(OUT/'transition-before-after.png')
 image=np.array(Image.open(b.ROOT/'assets'/b.G.H.resource).convert('RGBA'))
 before=np.array(Image.open(b.ROOT/'assets/image/anatomy-reference/vascular-study/heart-simple-20261012/transparent-margin-v12/heart-transparent-margin-v1.png').convert('RGBA'))
 r=json.loads((OUT/'registration.json').read_text());scope=mask(rings(r['editScope']),BOX,SIZE)>0
 visible=(image[:,:,3]>0)|(before[:,:,3]>0)
 assert np.array_equal(image[visible&~scope],before[visible&~scope]),'Unrelated visible pixels changed'
 yy,xx=np.mgrid[:SIZE[1],:SIZE[0]];sx=432+(xx+.5)*.1;sy=306+(yy+.5)*174/1692
 assert np.all(image[(sx<458.4)&(sy>420.2),3]==0),'Lung margin background returned'
 e=b.G.N.edges[15];curve=LineString([(p[1]*.5,(p[2]-512)*.5)for _,p in e.points.items()])
 tube=curve.buffer(e.width*.25);samples=[]
 for y in np.arange(417,425,.2):
  # The left bank is exposed; the far bank may pass behind the cardiac wall.
  band=tube.intersection(LineString([(465,y),(480,y)]));x=band.bounds[0]+.5
  rgb=image[int((y-306)*1692/174),int((x-432)*10),:3].astype(int)
  assert rgb[2]>rgb[0]+12,('Caval bank discontinuity',x,y,rgb)
  samples.append([float(x),float(y)])
 # The bank and inverse input share the texture transform through every
 # tested heart phase and zoom; authored navigation is unchanged.
 samples_render=[]
 for time,zoom,dpr in [(0,.06,1),(.3,.15,2),(.59,.25,1),(.9,.15,1)]:
  b.G.dpr=dpr;b.G.g.realTime=time;b.G.g.zoom=zoom;b.G.g.bodyLifeEnabled=True
  frame=b.G.T.beginFrame(b.G.g);assert frame.safe
  for x,y in samples[::10]:
   tx,ty=b.G.T.forward(frame,x,y);rx,ry=b.G.T.inverse(frame,tx,ty)
   assert np.hypot(rx-x,ry-y)<1e-7
  b.reset();b.G.R.draw(b.G.g)
  assert b.l.eval("require('war.HeartArt').last.atlasPanel==0")
  samples_render.append({'time':time,'zoom':zoom,'dpr':dpr,'displayInverseConsistent':True})
 assert b.G.A.stats().images==43
 b.G.A.release(b.G.R.vg);assert b.G.A.stats().images==0
 for n,v in r['unchangedRuntimeHashes'].items():assert hashlib.sha256((b.ROOT/n).read_bytes()).hexdigest()==v,n
 report={'status':'PASS_PRODUCTION_LUA_OFFLINE','nativeVisualEvidence':False,'cavalBankSamples':len(samples),'formerY420CutRemoved':True,'unrelatedVisiblePixelsExact':True,'transparentLungMarginPreserved':True,'geometryUnchanged':True,'renderSamples':samples_render,'resourceSpecsPerContext':43,'releaseLeaks':0,'assetSha256':hashlib.sha256((b.ROOT/'assets'/b.G.H.resource).read_bytes()).hexdigest()}
 (OUT/'art-check.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps(report))

if __name__=='__main__':main()
