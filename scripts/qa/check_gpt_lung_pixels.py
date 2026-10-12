"""Offline pixel contracts for registered GPT lung tissue; no native GPU claim."""
from pathlib import Path
import argparse
import io
import json
import hashlib
import cv2
import numpy as np
from PIL import Image
import body_life_backend as b

W,H,SCALE,X0,Y0=640,480,2,350,270


def setup():
    b.l.execute('''
    B=require('war.BodyLife');A=require('war.ReferenceArt');M=require('war.ReferenceMap')
    Motion=require('war.BodyLifeMotion');Assets=require('war.BodyLifeAssets')
    RR={vg={},w=640,h=480}
    function RR.project(g,x,y) return (x*.5-350)*64*g.zoom,((y-512)*.5-270)*64*g.zoom end
    state={anatomyVersion=4};g={zoom=.03125,realTime=0}
    assert(B.prepare(RR.vg)>0 and B.packs[RR.vg].tissue>0)
    originalTissueOrgans=Assets.tissueOrgans
    hidden={}
    function isolateLungs(on)
      for _,key in ipairs({'heart','stomach','small_intestine','large_intestine'}) do
        if on then hidden[key]=M.byId[key];M.byId[key]={x1=1e9,x2=1e9,y1=1e9,y2=1e9}
        elseif hidden[key] then M.byId[key]=hidden[key];hidden[key]=nil end
      end
    end
    ''')


def render(time, zoom=.03125, generated=True, mode='mesh'):
    b.reset()
    b.l.globals().sampleTime=time;b.l.globals().sampleZoom=zoom
    b.l.globals().generated=generated;b.l.globals().renderMode=mode
    b.l.execute('''
    g.realTime=sampleTime;g.zoom=sampleZoom
    Assets.tissueOrgans=generated and originalTissueOrgans or {}
    nvgSave(RR.vg);nvgScale(RR.vg,2/(64*g.zoom),2/(64*g.zoom))
    if renderMode=='atlas' then
      A.draw(RR,g,state,1,2048,1,4096)
    else
      local scale=64*g.zoom;local x,y=RR.project(g,0,512)
      nvgBeginPath(RR.vg);nvgRect(RR.vg,x,y,1024*scale,1536*scale)
      nvgFillPaint(RR.vg,nvgImagePattern(RR.vg,x,y,1024*scale,1536*scale,0,B.images[RR.vg],1));nvgFill(RR.vg)
      if renderMode~='static' then B.draw(RR,g,state,1,2048,1,4096) end
    end
    nvgRestore(RR.vg);Assets.tissueOrgans=originalTissueOrgans
    ''')
    return np.array(Image.open(io.BytesIO(b.png(W,H))).convert('RGB')).astype(np.int16)


def masks():
    allowed=np.zeros((H,W),np.uint8);rects=np.zeros_like(allowed)
    regions=b.l.eval("require('war.BodyLifeRegions')")
    for key in ('lung_r','lung_l'):
        spec=b.l.eval(f"B.mesh('{key}').spec")
        x,y,w,h=[spec[v] for v in ('x','y','w','h')]
        cv2.rectangle(rects,(round((x-X0)*SCALE),round((y-Y0)*SCALE)),(round((x+w-X0)*SCALE)-1,round((y+h-Y0)*SCALE)-1),255,-1)
        for item in regions[key].values():
            pts=item['points'] or item
            points=np.array([[round((p[1]-X0)*SCALE),round((p[2]-Y0)*SCALE)] for p in pts.values()],np.int32)
            cv2.fillPoly(allowed,[points],0 if item['hole'] else 255)
    # Raster-edge coverage belongs to native visual acceptance. Exclude a 3px
    # margin to measure fixed foreground interiors without polygon AA ambiguity.
    protected=(rects>0)&(cv2.dilate(allowed,np.ones((7,7),np.uint8))==0)
    return allowed>0,protected


def stats(a,c,mask=None):
    d=np.abs(a-c)
    if mask is not None:d=d[mask]
    return {'maxChannelDifference':int(d.max()),'meanChannelDifference':round(float(d.mean()),6),'changedPixels':int((d.max(axis=-1)>0).sum())}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',default='docs/body-life/gpt-lung-pixel-checks.json')
    args=parser.parse_args();setup();results=[];evidence={}
    def check(name,fn):
        try:fn();results.append({'name':name,'pass':True})
        except Exception as error:results.append({'name':name,'pass':False,'error':str(error)})
    allowed,protected=masks()
    b.l.execute('isolateLungs(true)')
    baseline=render(0,mode='static')
    def fixed():
        rows={}
        for t in (0,.13,.96,1.92,3.36,4.8,9.6):
            row=stats(baseline,render(t),protected);rows[str(t)]=row
            assert row['maxChannelDifference']==0,row
        evidence['fixedForeground']={'testedPixels':int(protected.sum()),'times':rows}
    check('Lung outer boundary and fixed foreground interiors preserve original pixels',fixed)
    def generated_rim():
        source=np.array(Image.open(b.ROOT/'assets/image/anatomy-reference/reference.png').convert('RGB')).astype(np.int16)
        tissue=np.array(Image.open(b.ROOT/'assets'/b.l.globals().Assets.tissue).convert('RGB')).astype(np.int16)
        a=source[440:481,375:479];c=tissue[440:481,375:479]
        suspect=(c[:,:,0]>240)&(c[:,:,1]>205)&(c[:,:,2]>180)&(c[:,:,1]-a[:,:,1]>20)
        ys,xs=np.where(suspect);assert len(xs)>0,'fixture has no generated rim displacement'
        raster=np.zeros((H,W),np.uint8)
        for x,y in zip(xs+375,ys+440):
            xx,yy=(x-X0)*SCALE,(y-Y0)*SCALE
            raster[yy:yy+SCALE,xx:xx+SCALE]=1
        rows={}
        for t in (0,.13,.96,1.92,3.36,4.8,9.6):
            row=stats(baseline,render(t),raster>0);rows[str(t)]=row
            assert row['maxChannelDifference']==0,row
        evidence['generatedRimRegression']={'sourcePixels':len(xs),'sourceBounds':[int(xs.min()+375),int(ys.min()+440),int(xs.max()+375),int(ys.max()+440)],'testedScreenPixels':int(raster.sum()),'times':rows}
    check('Misregistered GPT bright-rim pixels retain the original foreground at every phase',generated_rim)
    def cycle():
        rows={}
        for t in (0,.96,3.36,4.8,9.6):
            before,at,after=render(t-1e-6),render(t),render(t+1e-6)
            row={'before':stats(before,at,allowed),'after':stats(at,after,allowed)};rows[str(t)]=row
            assert max(row['before']['maxChannelDifference'],row['after']['maxChannelDifference'])<=2,row
        # Exact breathing periods reproduce the same lung imagery, not an old atlas.
        period=stats(render(0),render(4.8),allowed)
        evidence['cycleBoundary']={'epsilonSeconds':1e-6,'times':rows,'period':period}
        assert period['maxChannelDifference']==0,period
        assert stats(baseline,render(.96),allowed)['changedPixels']>100,'zero displacement dropped registered tissue'
    check('Zero-displacement crossings and full breath periods do not switch source images',cycle)
    def lod():
        rows={}
        for z in (.0005,.001,.00125):
            # Crops remain normalized to source coordinates, so this tests texture
            # selection at tiny runtime LOD independently of screen resampling.
            a=render(.96,z);c=render(1.92,z)
            rows[str(z)]=stats(a,c,allowed)
            assert rows[str(z)]['maxChannelDifference']==0,rows[str(z)]
            assert stats(baseline,a,allowed)['changedPixels']>100
        evidence['tinyLod']=rows
    check('Sub-16px lung LOD retains the registered texture without mesh motion',lod)
    b.l.execute('isolateLungs(false)')
    def selected():
        b.l.execute('''
        local sample=Motion.sample;local image=nvgImagePattern;local current=nil;local seen={}
        Motion.sample=function(time,key) current=key;return sample(time,key) end
        nvgImagePattern=function(vg,x,y,w,h,angle,id,alpha)
          local pack=B.packs[vg]
          if pack and current then
            if id==pack.tissue then assert(current=='lung_r' or current=='lung_l','generated texture used by '..current)
            else assert(id==pack.source,'unexpected texture') end
            seen[current]=seen[current] or {};seen[current][id]=true
          end
          return image(vg,x,y,w,h,angle,id,alpha)
        end
        local ok,err=pcall(function()
          for _,time in ipairs({.13,1.92,4,6,8,10}) do
            g.realTime=time;g.zoom=.03125;B.draw(RR,g,state,1,2048,1,4096)
          end
          local pack=B.packs[RR.vg]
          for _,key in ipairs({'heart','stomach','small_intestine','large_intestine'}) do
            assert(seen[key] and seen[key][pack.source] and not seen[key][pack.tissue],key)
          end
        end)
        Motion.sample=sample;nvgImagePattern=image;assert(ok,err)
        ''')
    check('Only the two lungs sample the generated tissue handle; other organs sample source',selected)
    def transition():
        rows={}
        for z in (.084,.12,.1499,.15):
            row=stats(render(.96,z,True,'atlas'),render(.96,z,False,'atlas'),allowed)
            rows[str(z)]=row
        assert rows['0.084']['changedPixels']>100
        assert rows['0.15']['maxChannelDifference']==0
        assert rows['0.1499']['maxChannelDifference']<=3,rows['0.1499']
        crossing=stats(render(.96,.15-1e-7,True,'atlas'),render(.96,.15,True,'atlas'),allowed)
        assert crossing['maxChannelDifference']<=3,crossing
        evidence['zoomTransition']={'assetContribution':rows,'boundaryDifference':crossing,'projection':'normalized to source coordinates to isolate atlas/vector handoff'}
    check('Generated tissue contribution continuously vanishes at the vector transition',transition)
    report={'nativeEvidence':False,'passed':sum(x['pass'] for x in results),'total':len(results),'results':results,'evidence':evidence,
            'referenceSha256':hashlib.sha256((b.ROOT/'assets/image/anatomy-reference/reference.png').read_bytes()).hexdigest(),
            'tissueSha256':hashlib.sha256((b.ROOT/'assets'/b.l.globals().Assets.tissue).read_bytes()).hexdigest(),
            'limitations':['Fixed-pixel check excludes a 3px mask-edge margin; native edge coverage still needs inspection.','Cairo filtering and tessellation differ from NanoVG.']}
    Path(args.output).parent.mkdir(parents=True,exist_ok=True);Path(args.output).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(report,ensure_ascii=False,indent=2));assert report['passed']==report['total']

if __name__=='__main__':main()
