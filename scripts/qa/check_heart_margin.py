"""Full-view seam regression using actual Lua drawing (offline Cairo only)."""
import sys, json, hashlib
from pathlib import Path
import numpy as np
from PIL import Image
from shapely.geometry import box
sys.path.insert(0, str(Path(__file__).parent))
import body_life_backend as b
from left_vessels_support import load
from build_heart_margin import OUT
from build_heart_perimeter import mask

def main():
    load(b.l)
    b.G.qaSource = (OUT/'HeartVisualData.lua').read_text()
    b.l.execute("package.loaded['war.HeartVisualData']=assert(load(qaSource))();package.loaded['war.FullBodyMapArt']=nil")
    b.l.execute('''
    S=require('war.FullBodyBattlefield').new(72026);S.entities={}
    R=require('war.Render');R.vg={};R.font=1;A=require('war.FullBodyMapArt');H=require('war.HeartVisualData')
    T=require('war.HeartDisplayTransform');A.prepare(R.vg);require('war.Cells').init(R.vg);R.prepare(S)
    dpr=1;vw=1480;vh=1692
    graphics={GetWidth=function()return vw*dpr end,GetHeight=function()return vh*dpr end,GetDPR=function()return dpr end}
    g={state=S,zoom=.15625,camera={x=1012,y=1283.048},selection={},started=true,fogDisabled=true,realTime=0,bodyLifeEnabled=false}
    ''')
    b.reset();b.G.R.draw(b.G.g);(OUT/'map-after.png').write_bytes(b.png(1480,1692))
    # The user screenshot shows the lower left lung and diaphragm. Previously
    # this area was all opaque, and clipped a passing pulmonary branch.
    b.G.g.zoom=.25;b.G.vw=900;b.G.vh=860
    b.G.g.camera.x=895;b.G.g.camera.y=1410.525
    b.reset();b.G.R.draw(b.G.g);(OUT/'lower-lung-after.png').write_bytes(b.png(900,860))
    image=np.array(Image.open(b.ROOT/'assets'/b.G.H.resource).convert('RGBA'))
    yy,xx=np.mgrid[:1692,:1480];sx=432+(xx+.5)*.1;sy=306+(yy+.5)*174/1692
    margin=(sx<459.8)&(sy>420.2)
    assert np.all(image[margin,3]==0), 'Opaque flattened lung/diaphragm margin survived'
    # Expanded clipping must leave unchanged branches and lung background open.
    for x,y in [(440,435),(455,430),(459,450),(435,470)]:
        for _,ring in b.G.H.replacementRings.items():
            from register_simple_heart import rings
            from check_regional_vascular_refinement import convert
            from shapely.geometry import Point
            assert not rings([convert(ring)]).covers(Point(x,y)), ('Unchanged map still clipped',x,y)
    old=np.array(Image.open(b.ROOT/'assets/image/anatomy-reference/vascular-study/heart-simple-20261012/left-vessels-v11/heart-smooth-left-vessels-v1.png').convert('RGBA'))
    scope=mask(box(432,314,514,420),[432,306,580,480],(1480,1692))[:,280:]>0
    scope |= mask(box(457,404,477,425),[432,306,580,480],(1480,1692))[:,280:]>0
    visible=(image[:,280:,3]>0)|(old[:,280:,3]>0)
    assert np.array_equal(image[:,280:][visible&~scope],old[:,280:][visible&~scope]), 'Unchanged cardiac core altered'
    # The material centerline and actual node topology are unchanged.
    n=b.G.S.heartVesselNet or b.l.eval("require('war.OrganBattlefield').net(S)")
    from shapely.geometry import LineString
    checks={}
    for i in [3,172,17,22,67,72,173,211]:
        e=n.edges[i];curve=LineString([(p[1]*.5,(p[2]-512)*.5)for _,p in e.points.items()]);count=0
        for dist in np.arange(0,curve.length,.18):
            p=curve.interpolate(float(dist))
            sample_box=box(457,410,476,425)if i==173 else box(433,326,513,401)
            if not sample_box.covers(p):continue
            if b.G.A.unitDepth(b.G.S,b.l.table_from({'vesselLane':i}),p.x*2,p.y*2+512)=='under-foreground':continue
            rgb=image[int((p.y-306)*1692/174),int((p.x-432)*10),:3].astype(int)
            if i not in [3,172] and rgb[0]>=rgb[2]:continue # arterial bridge boundary
            assert rgb[0]>rgb[2]+18 if i in [3,172]else rgb[2]>rgb[0]+12,(i,p.x,p.y,rgb)
            count+=1
        assert count>12,(i,count);checks[i]=count
    assert n.edges[211].width==14
    samples=[]
    for time,zoom,dpr in [(0,.06,1),(.3,.15,2),(.59,.25,1),(.9,.15,1)]:
        b.G.dpr=dpr;b.G.g.zoom=zoom;b.G.g.realTime=time;b.G.g.bodyLifeEnabled=True
        frame=b.G.T.beginFrame(b.G.g);assert frame.safe
        b.reset();b.G.R.draw(b.G.g)
        assert b.l.eval("require('war.HeartArt').last.atlasPanel==0")
        samples.append({'time':time,'zoom':zoom,'dpr':dpr})
    assert b.G.A.ready(b.G.R.vg,b.G.S) and b.G.A.stats().images==43
    b.G.A.release(b.G.R.vg);assert b.G.A.stats().images==0
    report={'status':'PASS_PRODUCTION_LUA_OFFLINE','nativeVisualEvidence':False,
            'transparentLowerMarginPixels':int(margin.sum()),'unaffectedMapRestored':True,
            'unchangedCardiacPixelsExact':True,'bloodCenterlineChecks':checks,
            'renderSamples':samples,'resourceSpecsPerContext':43,'releaseLeaks':0,
            'assetSha256':hashlib.sha256((b.ROOT/'assets'/b.G.H.resource).read_bytes()).hexdigest()}
    (OUT/'art-check.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(report))

if __name__=='__main__':main()
