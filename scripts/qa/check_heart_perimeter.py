"""Independent scope, image seam, actual flow and lifecycle checks for v8."""
from pathlib import Path
import sys,json,hashlib
import numpy as np
from PIL import Image
from shapely.geometry import LineString,Point

sys.path.insert(0,str(Path(__file__).parent))
import body_life_backend as b

def main():
 out=b.ROOT/'docs/heart-simple-20261012/perimeter-v8'
 for name in ['HeartVisualData','FullBodyMapArt']:
  b.G.src=(out/(name+'.lua')).read_text();b.G.name='war.'+name
  b.l.execute('package.loaded[name]=assert(load(src))()')
 b.l.execute('''
  S=require('war.FullBodyBattlefield').new(72026);R=require('war.Render');R.vg={};R.font=1
  A=require('war.FullBodyMapArt');H=require('war.HeartVisualData');Ref=require('war.ReferenceArt')
  P=require('war.AnatomyPerspective');Save=require('war.Save');F=require('war.BodyLifeFlow')
  N=require('war.OrganBattlefield').net(S);uiContext={}
  A.prepare(R.vg);A.prepare(uiContext);Ref.prepareOriginal(R.vg);Ref.prepareOriginal(uiContext)
  assert(A.ready(R.vg,S)and A.ready(uiContext,S));require('war.Cells').init(R.vg);R.prepare(S)
  assert(A.stats().images==86)
  function same(a,b)
   if type(a)~=type(b)then return false end
   if type(a)~='table'then return a==b end
   for k,v in pairs(a)do if not same(v,b[k])then return false end end
   for k in pairs(b)do if a[k]==nil then return false end end
   return true
  end
  baseline=Save.snapshot(S)
  graphics={GetWidth=function()return 1360*dpr end,GetHeight=function()return 2040*dpr end,GetDPR=function()return dpr end}
  game={state=S,zoom=.15625,camera={x=1040,y=1267.76},selection={},started=true,fogDisabled=true,realTime=0,bodyLifeEnabled=false}
 ''')
 samples=[]
 for zoom in [.06,.15,.25]:
  for time in [0,.3,.59]:
   for dpr in [1,2]:
    b.G.dpr=dpr;b.G.game.zoom=zoom;b.G.game.realTime=time;b.reset();b.G.R.draw(b.G.game)
    assert b.l.eval('same(baseline,Save.snapshot(S))')
    assert b.l.eval("require('war.HeartArt').last.detailVisible and require('war.HeartArt').last.atlasPanel==0")
    assert b.decoded_images[str((b.ROOT/'assets'/b.G.H.perimeter.resource).resolve())].key in b.frame_images
    samples.append({'zoom':zoom,'time':time,'dpr':dpr,'pass':True})
 b.G.dpr=1;b.G.game.zoom=.15625;b.G.game.realTime=0
 # This comparison is the exact same registered viewport as the user defects.
 b.G.S.entities=b.l.table();b.reset();b.G.R.draw(b.G.game)
 frame=b.png(1360,2040);(out/'perimeter-after.png').write_bytes(frame)
 im=Image.open(out/'perimeter-after.png');im.crop((0,100,1360,430)).save(out/'upper-seam-after.png');im.crop((965,775,1170,1290)).save(out/'right-wall-after.png')
 before=np.array(Image.open(out/'perimeter-guide.png').convert('RGB')).astype(float)
 after=np.array(im.convert('RGB')).astype(float)
 # At the old patch boundary, inspect quiet background independently of tube
 # shading. Large vertical jumps must fall rather than move to another layer.
 old=np.linalg.norm(before[240]-before[239],axis=1);new=np.linalg.norm(after[240]-after[239],axis=1)
 quiet=(old>35)&(np.min(before[240],axis=1)>90)
 assert quiet.sum()>20
 assert np.median(new[quiet])<np.median(old[quiet])*.25
 pixels=np.array(Image.open(b.ROOT/'assets'/b.G.H.resource).convert('RGBA'))
 previous=np.array(Image.open(b.ROOT/'assets/image/anatomy-reference/vascular-study/heart-simple-20261012/perspective-v7/heart-internal-map-v1.png').convert('RGBA'))
 yy,xx=np.mgrid[:1692,:1200];sx=460+(xx+.5)*.1;sy=306+(yy+.5)*174/1692
 rgb=pixels[:,:,:3].astype(int)
 defect=(sx>556)&(sx<566)&(sy>378)&(sy<412)
 blue=(rgb[:,:,2]>rgb[:,:,0])&(rgb[:,:,2]>rgb[:,:,1]+8)&(pixels[:,:,3]>100)
 assert not np.any(blue&defect),'Posterior blue fragment still present'
 # Ignore filtering padding where the PNG is fully transparent; the actual
 # heart chambers and all other visible pipe pixels must be byte-exact.
 visible=(pixels[:,:,3]>0)|(previous[:,:,3]>0)
 outside=visible&~((sx>559.5)&(sx<564)&(sy>378)&(sy<410))
 assert np.array_equal(pixels[outside],previous[outside]),'Remote heart pixels changed'
 # Flow uses the same actual net and the updated posterior visibility; no
 # particle may wander outside its lumen after the visual sliver is hidden.
 curves={lane:LineString([(p[1],p[2])for _,p in e.points.items()])for lane,e in b.G.N.edges.items()}
 flow=0
 for time in np.arange(0,3,.25):
  result=b.G.F.sample(b.G.S,float(time),.15,900,1190,1100,1510,b.l.table_from({'intensity':1}))
  for kind in ['streaks','cells']:
   for _,p in result[kind].items():
    flow+=1;assert curves[p.edge].distance(Point(p.x,p.y))<=b.G.N.edges[p.edge].width*.5+1e-6
 assert flow>0
 # The old whole-body image remains an exclusive perspective, unaffected by
 # the repair, and switching back restores the interactive map camera.
 original=(b.ROOT/'assets/image/anatomy-reference/reference.png').resolve()
 camera=(b.G.game.camera.x,b.G.game.camera.y,b.G.game.zoom)
 b.G.P.toggle(b.G.game,1360,2040);b.reset();b.G.R.draw(b.G.game)
 assert b.frame_images=={b.decoded_images[str(original)].key}
 b.G.P.toggle(b.G.game,1360,2040);assert camera==(b.G.game.camera.x,b.G.game.camera.y,b.G.game.zoom)
 b.l.execute('A.release(R.vg);A.release(uiContext);Ref.release(R.vg);Ref.release(uiContext);assert(A.stats().images==0)')
 frozen=json.loads((out/'frozen-runtime-hashes.json').read_text())
 assert all(hashlib.sha256((b.ROOT/p).read_bytes()).hexdigest()==h for p,h in frozen.items())
 movement=json.loads((out/'main-trunk-navigation-report.json').read_text());assert all(r['passed']for r in movement['routes'])
 report={'status':'PASS_PRODUCTION_LUA_OFFLINE','nativeVisualEvidence':False,'renderSamples':samples,'oldSeamMedianRGBJump':float(np.median(old[quiet])),'newSeamMedianRGBJump':float(np.median(new[quiet])),'posteriorBlueFragmentPixels':0,'unrelatedVisibleHeartPixelsByteExact':True,'flowLumenSamples':flow,'movementChecks':len(movement['routes']),'originalPerspectiveExclusive':True,'cameraRestored':True,'resourceSpecsPerContext':43,'twoContextsImages':86,'releaseLeaks':0,'geometryAndUnrelatedRuntimeHashesUnchanged':True,'limitations':['Offline NanoVG/Cairo rendering; native window pixels not captured.']}
 (out/'perimeter-check.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps({k:report[k]for k in ['status','oldSeamMedianRGBJump','newSeamMedianRGBJump','posteriorBlueFragmentPixels','movementChecks','flowLumenSamples']}))

if __name__=='__main__':main()
