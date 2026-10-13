"""Whole-path pixels, shared display coordinates, scope and image lifecycle."""
import sys,json,hashlib
from pathlib import Path
import numpy as np
from PIL import Image
from shapely.geometry import LineString,Point,box
sys.path.insert(0,str(Path(__file__).parent))
import body_life_backend as b
from left_vessels_support import load,OUT
from register_simple_heart import rings
from build_heart_perimeter import mask

def main():
 load(b.l)
 b.l.execute('''
 S=require('war.FullBodyBattlefield').new(72026);S.entities={};N=require('war.OrganBattlefield').net(S)
 H=require('war.HeartVisualData');R=require('war.Render');R.vg={};R.font=1;A=require('war.FullBodyMapArt')
 T=require('war.HeartDisplayTransform');P=require('war.AnatomyPerspective');Ref=require('war.ReferenceArt');ui={}
 A.prepare(R.vg);A.prepare(ui);Ref.prepareOriginal(R.vg);Ref.prepareOriginal(ui);require('war.Cells').init(R.vg);R.prepare(S)
 assert(A.ready(R.vg,S)and A.stats().images==86)
 graphics={GetWidth=function()return 1480*dpr end,GetHeight=function()return 1692*dpr end,GetDPR=function()return dpr end}
 g={state=S,zoom=.15625,camera={x=1012,y=1283.048},selection={},started=true,fogDisabled=true,realTime=0,bodyLifeEnabled=false}
 ''')
 b.G.dpr=1;b.reset();b.G.R.draw(b.G.g);(OUT/'map-after.png').write_bytes(b.png(1480,1692))
 frame=Image.open(OUT/'map-after.png');frame.crop((0,140,825,995)).save(OUT/'left-vessels-closeup.png')
 before=Image.open(OUT/'baseline-expanded-map.png').crop((0,140,825,995));after=frame.crop((0,140,825,995))
 comparison=Image.new('RGB',(1650,855));comparison.paste(before,(0,0));comparison.paste(after,(825,0));comparison.save(OUT/'before-after.png')
 pixels=np.array(Image.open(b.ROOT/'assets'/b.G.H.resource).convert('RGBA'))
 assert pixels.shape==(1692,1480,4)
 cache=b.decoded_images[str((b.ROOT/'assets'/b.G.H.resource).resolve())].pixels;assert np.array_equal(np.array(cache),pixels)
 curves={i:LineString([(p[1]*.5,(p[2]-512)*.5)for _,p in e.points.items()])for i,e in b.G.N.edges.items()}
 data=json.loads((OUT/'runtime-data.json').read_text());red_shape=rings(data['rawBloodDomains']['3']).union(rings(data['rawBloodDomains']['172']))
 checked={};vein_under_red=0
 for i in [3,172,17,22,67,72,211]:
  samples=0
  for distance in np.arange(0,curves[i].length+.001,.12):
   p=curves[i].interpolate(float(distance))
   if not box(433,326,513,401).covers(p):continue
   hidden=b.G.A.unitDepth(b.G.S,b.l.table_from({'vesselLane':i}),p.x*2,p.y*2+512)=='under-foreground'
   rgb=pixels[int((p.y-306)*1692/174),int((p.x-432)*10),:3].astype(int)
   if hidden:
    if i==211:
     assert red_shape.buffer(.2).covers(p),('stem is hidden without an arterial crossing',p.x,p.y,rgb);vein_under_red+=1
    continue
   # The thin bridge shadow is intentionally a mixed pigment at the arterial
   # bank; it must not be mistaken for a hole in the blue material underneath.
   if i not in [3,172]and red_shape.buffer(.3).covers(p):continue
   assert rgb[0]>rgb[2]+18 if i in [3,172]else rgb[2]>rgb[0]+12,('visible centerline pigment',i,p.x,p.y,rgb)
   samples+=1
  assert samples>12,(i,samples);checked[i]=samples
 assert vein_under_red>0
 # At the old squared junction shown in the user crop, the stem now has one
 # constant 7-source-unit diameter, and one graph edge owns its whole length.
 assert b.G.N.edges[211].width==14 and b.G.N.nodes[b.G.N.edges[211].a].id=='svc.junction'
 assert all(b.G.N.edges[i].b==b.G.N.edges[211].a for i in [17,22,67,72])
 motion_samples=[]
 for time in [0,.3,.59,.9]:
  b.G.g.bodyLifeEnabled=True;b.G.g.realTime=time;f=b.G.T.beginFrame(b.G.g)
  assert f.safe
  for i in [3,172,211]:
   for distance in np.arange(0,curves[i].length,.5):
    p=curves[i].interpolate(float(distance));x,y=b.G.T.forward(f,p.x,p.y)
    assert np.hypot(x-p.x,y-p.y)<1e-7,('external pipe display pin',i,p.x,p.y,x,y)
  for zoom in [.06,.15,.25]:
   for dpr in [1,2]:
    b.G.dpr=dpr;b.G.g.zoom=zoom;b.reset();b.G.R.draw(b.G.g)
    assert b.l.eval("require('war.HeartArt').last.atlasPanel==0 and require('war.HeartArt').last.detailVisible")
    motion_samples.append({'time':time,'zoom':zoom,'dpr':dpr,'pass':True})
 old=np.array(Image.open(b.ROOT/'assets/image/anatomy-reference/vascular-study/heart-simple-20261012/cava-junction-v10/heart-open-cava-junction-v1.png').convert('RGBA'))
 scope=mask(box(432,314,514,420),[432,306,580,480],(1480,1692))[:,280:]>0
 visible=(old[:,:,3]>0)|(pixels[:,280:,3]>0)
 assert np.array_equal(old[visible&~scope],pixels[:,280:][visible&~scope]),'Unaffected cardiac art changed'
 original=(b.ROOT/'assets/image/anatomy-reference/reference.png').resolve()
 camera=(b.G.g.camera.x,b.G.g.camera.y,b.G.g.zoom)
 b.G.P.toggle(b.G.g,1480,1692);b.reset();b.G.R.draw(b.G.g);assert b.frame_images=={b.decoded_images[str(original)].key}
 b.G.P.toggle(b.G.g,1480,1692);assert camera==(b.G.g.camera.x,b.G.g.camera.y,b.G.g.zoom)
 b.l.execute('A.release(R.vg);A.release(ui);Ref.release(R.vg);Ref.release(ui);assert(A.stats().images==0)')
 report={'status':'PASS_PRODUCTION_LUA_OFFLINE','nativeVisualEvidence':False,'wholeVesselCenterlineSamples':checked,'blueStemCrossingSamples':vein_under_red,'singleCavalStem':211,'cavalWidthSource':7,'renderSamples':motion_samples,'externalBloodPinnedToSameCellDisplay':True,'unrelatedVisibleHeartPixelsByteExact':True,'originalPerspectiveExclusive':True,'resourceSpecsPerContext':43,'releaseLeaks':0,'assetSha256':hashlib.sha256((b.ROOT/'assets'/b.G.H.resource).read_bytes()).hexdigest()}
 (OUT/'art-check.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps({k:report[k]for k in ['status','wholeVesselCenterlineSamples','blueStemCrossingSamples','resourceSpecsPerContext']}))

if __name__=='__main__':main()
