"""Compare flow-only visibility at atlas scale, independent of organ animation.

Usage: PYTHONPATH=/tmp/reference-map-tools python3 scripts/qa/measure_body_flow.py \
  --before /tmp/BodyLifeFlow-before-readable.lua --output /tmp/body-flow-readable
This measures SVG/Cairo logical pixels; it is not native GPU acceptance.
"""
from pathlib import Path
import argparse,hashlib,io,json,statistics
import numpy as np
from PIL import Image
import body_life_backend as b

p=argparse.ArgumentParser();p.add_argument('--before',required=True);p.add_argument('--output',required=True);args=p.parse_args()
out=Path(args.output);out.mkdir(parents=True,exist_ok=True)
before=Path(args.before);after=Path('scripts/war/BodyLifeFlow.lua')
b.l.execute("R=require('war.Render');R.vg={};R.w=430;R.h=680;g={camera={x=1024,y=2048},zoom=.006,realTime=0};s={anatomyVersion=4};Fafter=require('war.BodyLifeFlow')")
b.l.globals()['beforeSource']=before.read_text();b.l.execute("Fbefore=assert(load(beforeSource))();atlas=nvgCreateImage(R.vg,'image/anatomy-reference/reference.png',0)")
def draw(t,which=None):
    b.reset();b.l.globals()['qaTime']=t
    b.l.execute("g.realTime=qaTime;local x,y=R.project(g,0,512);nvgBeginPath(R.vg);nvgRect(R.vg,x,y,1024*.384,1536*.384);nvgFillPaint(R.vg,nvgImagePattern(R.vg,x,y,1024*.384,1536*.384,0,atlas,1));nvgFill(R.vg)")
    if which:b.l.execute(which+'.draw(R,g,s,0,2048,512,3584)')
    data=b.png(430,680)
    im=Image.open(io.BytesIO(data)).convert('RGB')
    return np.asarray(im,dtype=np.int16),im
base,_=draw(0)
y,x=np.mgrid[0:680,0:430];sx=(x-215)/.384+512;sy=(y-340)/.384+768
region=np.where(sy<295,1,np.where((sx<375)&(sy<910),3,np.where((sx>647)&(sy<910),4,np.where(sy>800,np.where(sx<510,5,6),2))))
report={'zoom':.006,'logicalSize':[430,680],'samples':180,'fps':12,'evidence':'offline SVG/Cairo; actual flow-only renderer','regions':{}}
for label,which,peak,speed in [('before','Fbefore',185,76),('after','Fafter',245,32)]:
    stats={i:{'width':[],'length':[],'alpha':[],'travel':[],'changed':[],'delta':[],'motion':[]} for i in range(1,7)}
    images=[];previous=None
    fn=b.l.globals()[which]
    for frame in range(180):
        t=frame/12;result=fn.sample(b.l.globals().s,t,.006,0,2048,512,3584)
        for v in result['streaks'].values():
            a=stats[v['region']];a['width'].append(v['width']*.192);a['length'].append((v['b']-v['a'])*.192);a['alpha'].append(v['alpha']*peak);a['travel'].append((v['b']-v['a'])/speed)
        pixels,im=draw(t,which);delta=np.max(np.abs(pixels-base),axis=2)
        motion=np.max(np.abs(pixels-previous),axis=2) if previous is not None else np.zeros_like(delta)
        previous=pixels
        for r,a in stats.items():
            mask=region==r;a['changed'].append(int(np.count_nonzero((delta>=5)&mask)));a['delta'].append(int(delta[mask].max()));a['motion'].append(int(np.count_nonzero((motion>=5)&mask)))
        images.append(im)
    images[0].save(out/(label+'-15s.webp'),save_all=True,append_images=images[1:],duration=[83]*179+[143],loop=0,lossless=True)
    for r,a in stats.items():
        report['regions'].setdefault(r,{})[label]={
            'meanWidthPx':statistics.mean(a['width']),'meanLengthPx':statistics.mean(a['length']),
            'meanHeadAlpha255':statistics.mean(a['alpha']),'medianTravelOwnLengthSeconds':statistics.median(a['travel']),
            'meanChangedPixelsAbove5':statistics.mean(a['changed']),'meanMaxChannelDelta255':statistics.mean(a['delta']),
            'meanMovingPixelsAbove5PerFrame':statistics.mean(a['motion'])}
report['beforeSha256']=hashlib.sha256(before.read_bytes()).hexdigest();report['afterSha256']=hashlib.sha256(after.read_bytes()).hexdigest()
(out/'comparison.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
