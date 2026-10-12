"""Full-body visibility and travelling-wave contracts; offline, not native evidence."""
from pathlib import Path
import argparse,io,json,hashlib
import numpy as np
import cv2
from PIL import Image
import render_body_life as r
LUMA=np.array([.2126,.7152,.0722],np.float32)
GI=('stomach','small_intestine','large_intestine')
LIMBS=('arm_r','arm_l','forearm_r','forearm_l','thigh_r','thigh_l','calf_r','calf_l')

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',default='docs/body-life/fullbody-life-visibility.json');p.add_argument('--images',default='docs/body-life/previews/fullbody-life');a=p.parse_args()
 r.initialise();b=r.b;b.l.execute("B=require('war.BodyLife');Q=require('war.BodyLifeMotion');Regions=require('war.BodyLifeRegions');Flow=require('war.BodyLifeFlow');Art=require('war.ReferenceArt')")
 B,Q,Regions,Flow=b.l.globals().B,b.l.globals().Q,b.l.globals().Regions,b.l.globals().Flow
 checks=[];e={};out=Path(a.images);out.mkdir(parents=True,exist_ok=True)
 def check(name,fn):
  try: fn();checks.append({'name':name,'pass':True})
  except Exception as ex: checks.append({'name':name,'pass':False,'error':str(ex)})
 def pixels(t,view,flow=False):
  Flow.enabled=flow
  return np.array(Image.open(io.BytesIO(r.frame(t,view=view))).convert('RGB'),np.float32)
 def mask(key,view):
  sx,sy,w,h=r.VIEWS[view];scale=min(696/w,576/h);ox,oy=360-sx*scale,300-sy*scale
  m=np.zeros((600,720),np.uint8)
  for path in Regions[key].values():
   ps=np.array([[round(ox+v[1]*scale),round(oy+v[2]*scale)] for v in path.points.values()],np.int32)
   cv2.fillPoly(m,[ps],0 if path.hole else 255)
  return m>0
 def mesh():
  e['meshes']={}
  for key,floor in zip(GI,[.2,.07,.18]):
   m=B.mesh(key);active=[v for v in m.vertices.values() if v.weight>=.25];peaks={}
   for z in [.006,.0242]:
    peak=0
    for i in range(721):
     for v in active:
      dx,dy=B.offset(key,v,m.spec,i/60,z*64,z);peak=max(peak,float((dx*dx+dy*dy)**.5*z*64))
    peaks[str(z)]=peak
   e['meshes'][key]={'effectiveVertices':len(active),'totalVertices':len(m.vertices),'peakLogicalPixels':peaks,'wholeFloor':floor}
   assert len(active)>=4,(key,'too few effective vertices')
   assert peaks['0.006']>=floor,(key,peaks)
   assert peaks['0.0242']<=1.000001,(key,peaks)
 check('GI effective vertices and useful whole-body displacement remain within 1px cap',mesh)
 histories={}
 for view in ['whole','digestive']:
  keys=GI if view=='digestive' else GI+('brain','liver','kidney_r','kidney_l','bladder')+LIMBS
  masks={key:mask(key,view) for key in keys};history={key:[] for key in keys}
  for i in range(25):
   image=pixels(i*.5+(i%3)*.13,view)@LUMA
   for key,m in masks.items():history[key].append(image[m])
  histories[view]={key:np.array(v) for key,v in history.items()}
 def readable():
  e['losslessGI']={}
  for view in ['whole','digestive']:
   for key in GI:
    values=histories[view][key];ranges=np.ptp(values,axis=0)
    row={'meanPixelLumaRange':float(ranges.mean()),'p95PixelLumaRange':float(np.percentile(ranges,95)),'fractionAtLeast2Luma':float((ranges>=2).mean()),'samples':25,'seconds':12}
    e['losslessGI'][view+'/'+key]=row
    assert row['meanPixelLumaRange']>=(.6 if view=='whole' else 1.0),(view,key,row)
    assert row['p95PixelLumaRange']>=4,(view,key,row)
    assert row['fractionAtLeast2Luma']>=.12,(view,key,row)
 check('Each digestive organ has lossless visible local change across its cycle',readable)
 def travel():
  e['waveProgression']={}
  for key,period in zip(GI,[8,10,12]):
   indexes=[];maxConcurrent=0
   for i in range(1,100):
    q=Q.sample(period*i/100,key);segments=list(q.segments.values());maxConcurrent=max(maxConcurrent,len(segments))
    indexes.append(sum(s.index*s.weight for s in segments)/sum(s.weight for s in segments))
   row={'firstIndex':indexes[0],'lastIndex':indexes[-1],'nodes':len(Q.paths[key]),'maxConcurrentSegments':maxConcurrent,'minimumProgress':min(np.diff(indexes))}
   e['waveProgression'][key]=row
   assert maxConcurrent<=2 and row['minimumProgress']>=-1e-9 and indexes[-1]-indexes[0]>=len(Q.paths[key])-2,(key,row)
 check('Digestive wave visits ordered tissue nodes with at most two concurrent segments',travel)
 def secondary():
  e['secondaryLumaRange']={}
  signals=[]
  for key in ('brain','liver','kidney_r','kidney_l','bladder')+LIMBS:
   x=histories['whole'][key];span=np.ptp(x,axis=0)
   e['secondaryLumaRange'][key]={'meanPixelRange':float(span.mean()),'p95PixelRange':float(np.percentile(span,95))}
   e['secondaryLumaRange'][key]['wholeViewBelow8BitVisibility']=bool(span.max()<1)
   if key in LIMBS and x.mean(axis=1).std()>1e-5:signals.append(x.mean(axis=1))
  corr=np.corrcoef(signals);e['limbCorrelationMaxOffDiagonal']=float(corr[np.triu_indices(len(signals),1)].max());e['limbCorrelationMin']=float(corr.min())
  assert corr.min()<.7,'all limbs pulse together'
  for key,crop,t0,t in [('brain',(512,85,210,150),0,.13),('liver',(460,515,190,150),.33,.83),('kidney_r',(420,610,130,130),.39,.89),('kidney_l',(598,610,130,130),.56,1.06),('bladder',(510,780,160,140),0,1.92),('pancreas',(528,583,180,110),.47,.97)]:
   r.VIEWS[key]=crop;m=mask(key,key);rgbDelta=np.abs(pixels(t,key)-pixels(t0,key));delta=np.abs(rgbDelta@LUMA)[m]
   e['secondaryLumaRange'].setdefault(key,{})
   e['secondaryLumaRange'][key]['nearMeanLumaChange']=float(delta.mean())
   e['secondaryLumaRange'][key]['nearMaximumLumaChange']=float(delta.max())
   e['secondaryLumaRange'][key]['nearMaximumRgbChange']=float(rgbDelta[m].max())
   e['secondaryLumaRange'][key]['nearReadability']='unconfirmed; presence only'
   assert rgbDelta[m].max()>=1 and delta.mean()>0,(key,'near detail missing')
 check('Secondary near-view changes exist and limb phases differ (not a readability claim)',secondary)
 def flow_dominates():
  baseline=[];flow=[]
  for i in range(8):
   off=pixels(i*.5,'legs',False);on=pixels(i*.5,'legs',True)
   # Exclude the lower gut at the top of the requested legs composition.
   # source y>=840 maps to screen y>=101 in this view.
   baseline.append(off[101:]);flow.append((on-off)[101:])
  tissueStd=np.std(baseline,axis=0);flowStd=np.std(flow,axis=0)
  tissueRms=float(tissueStd.mean());flowRms=float(flowStd.mean())
  # Mean energy over the canvas favours broad low-contrast gradients.
  # A short flow cue should dominate local peak contrast, not total area.
  tissuePeak=float(tissueStd.max());flowPeak=float(flowStd.max())
  tissueStrong=int((tissueStd.max(axis=2)>=2).sum());flowStrong=int((flowStd.max(axis=2)>=2).sum())
  e['legsTemporalChange']={'sourceYMinimum':840,'tissueMeanTemporalStd':tissueRms,'flowMeanTemporalStd':flowRms,'flowToTissue':flowRms/max(1e-9,tissueRms),'tissuePeakTemporalStd':tissuePeak,'flowPeakTemporalStd':flowPeak,'tissuePixelsStdAtLeast2':tissueStrong,'flowPixelsStdAtLeast2':flowStrong}
  assert flowPeak>tissuePeak and flowStrong>tissueStrong,e['legsTemporalChange']
 check('Visible leg motion is led by circulating blood rather than tissue flashing',flow_dominates)
 def micro():
  e['microscopy']={};Flow.enabled=False
  for key,crop in [('muscle',(378,1130,20,20)),('marrow',(412,1130,20,20))]:
   r.VIEWS[key]=crop;images=[]
   for t in (0,1,2):
    image=pixels(t,key);images.append(image);Image.fromarray(image.astype('uint8')).save(out/f'{key}-{t}.png')
   active=float(np.abs(images[2]-images[0]).mean())
   B.intensity=0;static0=pixels(0,key);static2=pixels(2,key);B.intensity=1
   still=float(np.abs(static2-static0).max());e['microscopy'][key]={'meanRgbChangeOverTwoSeconds':active,'intensityZeroMaxChange':still}
   assert active>.03 and still==0,(key,e['microscopy'][key])
 check('Close-up muscle/marrow details move and intensity zero stays static',micro)
 Flow.enabled=True
 paths=list((b.ROOT/'scripts/war').glob('BodyLife*.lua'))+[b.ROOT/'scripts/war/ReferenceArt.lua']
 report={'sampleTimes':[i*.5+(i%3)*.13 for i in range(25)],'nativeEvidence':False,'passed':sum(x['pass'] for x in checks),'total':len(checks),'results':checks,'evidence':e,'runtimeSha256':{str(x.relative_to(b.ROOT)):hashlib.sha256(x.read_bytes()).hexdigest() for x in paths},'limitations':['Engineering visibility floors are not a guarantee of human perception.','Lossless source renders use Cairo rather than native NanoVG; native seams/performance remain separate.','Secondary ranges exclude flow; leg flow comparison isolates source y>=840, excluding digestive tissue at the top of the requested view.','Small secondary organs may fall below 8-bit compositing visibility in whole view; this is reported per organ and their detail is checked in close view. They are not counted as whole-body motion cues.','Uniform 0.5s sampling aliases 1s perfusion; nonuniform fixed times cover cardiac phases. Canvas-average flow variation may be lower than broad tissue shading; local contrast is the relevant comparison.']}
 Path(a.output).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps(report,ensure_ascii=False,indent=2));assert report['passed']==report['total']
if __name__=='__main__':main()
