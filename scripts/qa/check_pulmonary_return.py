"""Inspect continuous visible pulmonary blood and independent crossing depth.

Exercises production rendering/visibility/flow with Cairo as an offline raster
backend. Native pixels are a separate acceptance source, not claimed here.
"""
from pathlib import Path
import sys,json,hashlib
import numpy as np
from PIL import Image
from shapely.geometry import Point,LineString,box
from shapely.ops import unary_union
sys.path.insert(0,str(Path(__file__).parent))
import body_life_backend as b
from register_simple_heart import rings

def main():
 out=Path(sys.argv[1]).resolve()if len(sys.argv)>1 else b.ROOT/'docs/heart-simple-20261012/pulmonary-return-v9'
 b.G.oldSrc=(out/'baseline-HeartVisualData.lua').read_text();b.l.execute('previousHeart=assert(load(oldSrc))()')
 previous_resource=b.G.previousHeart.resource
 b.G.src=(out/'HeartVisualData.lua').read_text()
 b.l.execute("package.loaded['war.HeartVisualData']=assert(load(src))()")
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
   for k in pairs(b)do if a[k]==nil then return false end end;return true
  end
  baseline=Save.snapshot(S)
  graphics={GetWidth=function()return 1360*dpr end,GetHeight=function()return 2040*dpr end,GetDPR=function()return dpr end}
  game={state=S,zoom=.15625,camera={x=1040,y=1267.76},selection={},started=true,fogDisabled=true,realTime=0,bodyLifeEnabled=false}
 ''')
 curves={i:LineString([(p[1]*.5,(p[2]-512)*.5)for _,p in e.points.items()])for i,e in b.G.N.edges.items()}
 # Independently sample the graph, not the builder's alpha contour endpoints.
 coverage={i:np.array(Image.open(out/f'lane-{i}-coverage.png'))for i in [8,175]}
 region=box(460.2,306.2,579.8,479.8);continuity=[]
 for i in [175,8]:
  for d in np.arange(0,curves[i].length+.001,.125):
   p=curves[i].interpolate(float(d))
   if not region.covers(p):continue
   ix=int((p.x-460)*10);iy=int((p.y-306)*1692/174)
   assert coverage[i][iy,ix]>=240,(i,p.x,p.y,coverage[i][iy,ix])
   assert not b.G.H.unitBehindHeart(b.G.N.edges[i],p.x*2,p.y*2+512),(i,p.x,p.y)
   continuity.append({'lane':i,'x':p.x,'y':p.y})
 assert len(continuity)>350
 assert b.G.N.edges[175].b==b.G.N.edges[8].a
 assert b.G.N.edges[8].b==b.G.N.edges[205].a
 # The projected crossing has blue on top; red passes beneath without any
 # extra graph junction or artery/vein exchange.
 blue=unary_union([curves[i].buffer(b.G.N.edges[i].width*.25)for i in [175,8]])
 crossings=[]
 for i in [6,9]:
  hidden=0
  for d in np.arange(0,curves[i].length,.125):
   p=curves[i].interpolate(float(d))
   if region.covers(p)and blue.buffer(-.2).covers(p):
    assert b.G.H.unitBehindHeart(b.G.N.edges[i],p.x*2,p.y*2+512)
    hidden+=1
  assert hidden>0
  assert not any({j.aLane,j.bLane}in[{i,8},{i,175}]for _,j in b.l.eval("require('war.OrganBattlefield').organ('heart').junctionContracts.siege").items())
  crossings.append({'arteryLane':i,'hiddenCenterlineSamples':hidden,'accidentalJunction':False})
 samples=[]
 for zoom in [.06,.15,.25]:
  for time in [0,.3,.59]:
   for dpr in [1,2]:
    b.G.dpr=dpr;b.G.game.zoom=zoom;b.G.game.realTime=time;b.reset();b.G.R.draw(b.G.game)
    assert b.l.eval('same(baseline,Save.snapshot(S))')
    assert b.l.eval("require('war.HeartArt').last.detailVisible and require('war.HeartArt').last.atlasPanel==0")
    samples.append({'zoom':zoom,'time':time,'dpr':dpr,'pass':True})
 b.G.dpr=1;b.G.game.zoom=.15625;b.G.game.realTime=0;b.G.S.entities=b.l.table()
 b.reset();b.G.R.draw(b.G.game);(out/'return-after.png').write_bytes(b.png(1360,2040))
 Image.open(out/'return-after.png').crop((790,735,1260,1430)).save(out/'continuous-vein-closeup.png')
 if (out/'edit-weight.png').exists():Image.open(out/'return-after.png').crop((60,430,450,1100)).save(out/'cava-junction-closeup.png')
 pixels=np.array(Image.open(b.ROOT/'assets'/b.G.H.resource).convert('RGBA'))
 assert np.array_equal(np.array(b.decoded_images[str((b.ROOT/'assets'/b.G.H.resource).resolve())].pixels),pixels),'Rendered image differs from the saved asset'
 previous=np.array(Image.open(b.ROOT/'assets'/previous_resource).convert('RGBA'))
 reg=json.loads((out/'registration.json').read_text());scope=rings(reg['editScope']).buffer(.7)if 'editScope'in reg else box(*reg['editBox'])
 from build_heart_perimeter import mask
 visible=(pixels[:,:,3]>0)|(previous[:,:,3]>0)
 outside=visible&(mask(scope,[460,306,580,480],(1200,1692))==0)
 assert np.array_equal(pixels[outside],previous[outside]),'Unrelated cardiac art changed'
 flow=0;return_flow=0
 for time in np.arange(0,6,.2):
  result=b.G.F.sample(b.G.S,float(time),.25,1040,1220,1220,1420,b.l.table_from({'intensity':1}))
  for kind in ['streaks','cells']:
   for _,p in result[kind].items():
    flow+=1;source=Point(p.x*.5,(p.y-512)*.5)
    assert curves[p.edge].distance(source)<=b.G.N.edges[p.edge].width*.25+1e-6
    assert b.G.A.unitDepth(b.G.S,b.l.table_from({'vesselLane':p.edge}),p.x,p.y)!='under-foreground'
    if p.edge in [8,175]:return_flow+=1
 assert return_flow>0
 original=(b.ROOT/'assets/image/anatomy-reference/reference.png').resolve()
 camera=(b.G.game.camera.x,b.G.game.camera.y,b.G.game.zoom)
 b.G.P.toggle(b.G.game,1360,2040);b.reset();b.G.R.draw(b.G.game)
 assert b.frame_images=={b.decoded_images[str(original)].key}
 b.G.P.toggle(b.G.game,1360,2040);assert camera==(b.G.game.camera.x,b.G.game.camera.y,b.G.game.zoom)
 b.l.execute('A.release(R.vg);A.release(uiContext);Ref.release(R.vg);Ref.release(uiContext);assert(A.stats().images==0)')
 frozen=json.loads((out/'frozen-runtime-hashes.json').read_text())
 assert all(hashlib.sha256((b.ROOT/p).read_bytes()).hexdigest()==h for p,h in frozen.items())
 report={'status':'PASS_PRODUCTION_LUA_OFFLINE','nativeVisualEvidence':False,'renderedAssetSha256':hashlib.sha256((b.ROOT/'assets'/b.G.H.resource).read_bytes()).hexdigest(),'continuousVeinCenterlineSamples':len(continuity),'trueJoint':'lung_l.exit','atriumNode':'left_heart','crossings':crossings,'renderSamples':samples,'unrelatedVisibleHeartPixelsByteExact':True,'flowLumenSamples':flow,'pulmonaryReturnFlowSamples':return_flow,'originalPerspectiveExclusive':True,'cameraRestored':True,'resourceSpecsPerContext':43,'twoContextsImages':86,'releaseLeaks':0,'geometryAndUnrelatedRuntimeHashesUnchanged':True,'limitations':['Offline NanoVG/Cairo rendering; native window pixels not captured.']}
 (out/'continuity-check.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
 print(json.dumps({k:report[k]for k in ['status','continuousVeinCenterlineSamples','flowLumenSamples','pulmonaryReturnFlowSamples']}))

if __name__=='__main__':main()
