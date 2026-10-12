"""Visibility regression floors at a full-body view, beyond nonzero animation.

Thresholds are engineering acceptance floors, not a psychophysical guarantee.
The test uses lossless frames, avoiding WebP compression noise as motion evidence.
"""
from pathlib import Path
import argparse
import io
import json
import hashlib
import numpy as np
from PIL import Image
import render_body_life as renderer

LUMA=np.array([.2126,.7152,.0722],np.float32)
ORGANS=('heart','lung_r','lung_l')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',default='docs/body-life/visible-life-visibility.json')
    args=parser.parse_args();renderer.initialise();b=renderer.b
    b.l.execute("VisibilityBody=require('war.BodyLife')")
    body=b.l.globals().VisibilityBody
    # A 576px-high source canvas in the 720x600 whole-body inspection view.
    scale=.375;ox,oy=168,12
    bounds={};meshes={};results=[];evidence={}
    def check(name,fn):
        try:fn();results.append({'name':name,'pass':True})
        except Exception as error:results.append({'name':name,'pass':False,'error':str(error)})
    for key in ORGANS:
        mesh=body.mesh(key);meshes[key]=mesh;s=mesh.spec
        bounds[key]=(round(ox+s.x*scale),round(oy+s.y*scale),round(ox+(s.x+s.w)*scale),round(oy+(s.y+s.h)*scale))
    def topology():
        evidence['mesh']={}
        for key,m in meshes.items():
            active=[v for v in m.vertices.values() if v.weight>=.25]
            countFloor=6 if key=='heart' else 4
            peak=0
            for i in range(361):
                for v in active:
                    dx,dy=body.offset(key,v,m.spec,i/120,.384,.006)
                    peak=max(peak,float((dx*dx+dy*dy)**.5*.384))
            spanX=(max(v.x for v in active)-min(v.x for v in active))/m.spec.w if active else 0
            spanY=(max(v.y for v in active)-min(v.y for v in active))/m.spec.h if active else 0
            row={'verticesWithWeightAtLeast025':len(active),'vertexFloor':countFloor,'sourceSpanFraction':[spanX,spanY],'peakDisplacementLogicalPixelsAtZoom006':peak,'peakFloor':.15 if key=='heart' else .3}
            evidence['mesh'][key]=row
            assert len(active)>=countFloor,(key,row)
            assert min(spanX,spanY)>=.3,(key,'active vertices too clustered',row)
            assert peak>=row['peakFloor'],(key,'subpixel displacement below floor',row)
    check('Heart and each lung have multiple spatially distributed effective vertices',topology)
    def pixels(t):
        return np.array(Image.open(io.BytesIO(renderer.frame(t,view='whole'))).convert('RGB'),np.float32)
    initial=pixels(0)
    def contrast():
        evidence['losslessPeakContrast']={}
        for key in ORGANS:
            t=.13 if key=='heart' else 1.92;current=pixels(t)
            x1,y1,x2,y2=bounds[key]
            delta=np.abs((current-initial)@LUMA)[y1:y2,x1:x2]
            meanFloor=4 if key=='heart' else 2
            fractionFloor=.25
            row={'time':t,'screenSize':[x2-x1,y2-y1],'meanLumaDifference':float(delta.mean()),'meanFloor':meanFloor,'fractionPixelsChangingByAtLeast4Luma':float((delta>=4).mean()),'fractionFloor':fractionFloor,'p90LumaDifference':float(np.percentile(delta,90))}
            evidence['losslessPeakContrast'][key]=row
            assert row['meanLumaDifference']>=meanFloor,(key,row)
            assert row['fractionPixelsChangingByAtLeast4Luma']>=fractionFloor,(key,row)
    check('Whole-body heart and lungs exceed brightness and changed-area floors',contrast)
    history={key:[] for key in ORGANS}
    for i in range(37):
        frame=pixels(i/12)@LUMA
        for key,(x1,y1,x2,y2) in bounds.items():history[key].append(frame[y1:y2,x1:x2])
    def sequence():
        evidence['firstThreeSeconds']={}
        for key,frames in history.items():
            values=np.array(frames);means=values.mean((1,2));span=float(means.max()-means.min())
            floor=3 if key=='heart' else 1.5
            row={'frames':37,'durationSeconds':3,'meanOrganLumaRange':span,'rangeFloor':floor,'meanConsecutiveFrameLumaChange':float(np.abs(np.diff(values,axis=0)).mean())}
            evidence['firstThreeSeconds'][key]=row
            assert span>=floor,(key,row)
    check('Three-second lossless sequence has sustained organ-scale contrast variation',sequence)
    paths=list((b.ROOT/'scripts/war').glob('BodyLife*.lua'))
    report={'nativeEvidence':False,'passed':sum(r['pass'] for r in results),'total':len(results),'results':results,'evidence':evidence,'runtimeSha256':{str(p.relative_to(b.ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths},'limitations':['Visibility floors reject numerically nonzero but imperceptibly weak regressions; user/native visual review is still required.','Luma is measured in 8-bit sRGB code values, not physical display luminance.','Axis-aligned organ crops include small amounts of neighboring tissue and flow.']}
    Path(args.output).parent.mkdir(parents=True,exist_ok=True);Path(args.output).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(report['results'],ensure_ascii=False));print(json.dumps(evidence,ensure_ascii=False,indent=2));assert report['passed']==report['total']

if __name__=='__main__':main()
