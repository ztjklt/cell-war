"""Explicit-zoom actual Lua close-up frames for inspection and browser Canvas playback.

The catalog distinguishes organ centres from semantic-boundary probes. A fixed zoom
is not fitted to the organ: at .9 this is a tissue-sized crop, not an organ overview.
PNG sequences are deterministic frames, not AI-generated video or native GPU evidence.
"""
from pathlib import Path
import argparse,hashlib,json,time,io
from PIL import Image
import numpy as np
import render_body_life as r

def draw(t,sx,sy,zoom,w,h,dpr):
 b=r.b;b.reset();cy=sy*2+512-.03*h/(32*zoom)
 b.l.execute(f"graphics={{GetWidth=function() return {w*dpr} end,GetHeight=function() return {h*dpr} end,GetDPR=function() return {dpr} end}};game.camera={{x={sx*2},y={cy}}};game.zoom={zoom};game.realTime={t};R.draw(game)")
 return b.png(w,h,dpr)

def catalog(zooms,w,h,tissue_focus=False):
 b=r.b;b.l.execute("CloseupMap=require('war.ReferenceMap')");views=[]
 if tissue_focus:b.l.execute("CloseupBoundary=require('war.OrganBoundaries')")
 for organ in b.l.globals().CloseupMap.organs.values():
  x,y=organ.x*.5,(organ.y-512)*.5
  source_w,source_h=(organ.x2-organ.x1)*.5,(organ.y2-organ.y1)*.5
  focus_x,focus_y=x,y
  if tissue_focus:
   import cv2,numpy as np
   boundary=b.l.globals().CloseupBoundary
   mask=np.zeros((1536,1024),np.uint8)
   for path in boundary.paths(organ.id).values():
    points=np.array([[p[1],p[2]] for p in path.points.values()],np.int32);cv2.fillPoly(mask,[points],0 if path.hole else 255)
   distance=cv2.distanceTransform(mask,cv2.DIST_L2,5)
   ys,xs=np.where(distance>=max(1,float(distance.max())*.8))
   if len(xs):
    index=np.argmin(((xs-x)/max(1,source_w))**2+((ys-y)/max(1,source_h))**2);focus_x,focus_y=int(xs[index]),int(ys[index])
  # A 12% margin on each side, using the canonical gameplay geometry bounds.
  fit_zoom=min(w/(source_w*1.24*64),h/(source_h*1.24*64))
  views.append({'id':f'{organ.id}-organ-fit','organ':organ.id,'name':organ.name,'anchor':'organ-fit','zoom':fit_zoom,'sourceCenter':[x,y],'sourceBounds':[organ.x1*.5,(organ.y1-512)*.5,organ.x2*.5,(organ.y2-512)*.5],'contextMarginPerSide':.12,'visibleSourceSize':[w/(64*fit_zoom),h/(64*fit_zoom)],'logicalSize':[w,h]})
  for z in zooms:
   for anchor in ['center','boundary']:
    if anchor=='boundary':sx,sy=organ.points[1][1]*.5,(organ.points[1][2]-512)*.5
    else:sx,sy=focus_x,focus_y
    views.append({'id':f'{organ.id}-{anchor}-z{z:g}','organ':organ.id,'name':organ.name,'anchor':anchor,'zoom':z,'geometryCenter':[x,y],'tissueFocusEnabled':tissue_focus and anchor=='center','tissueFocus':[focus_x,focus_y] if tissue_focus else None,'sourceCenter':[sx,sy],'visibleSourceSize':[w/(64*z),h/(64*z)],'logicalSize':[w,h]})
 return views

def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--output',default='docs/body-life/closeup-baseline-20261009');p.add_argument('--zooms',default='.15,.4,.9');p.add_argument('--organs',default='all');p.add_argument('--anchors',default='center');p.add_argument('--width',type=int,default=640);p.add_argument('--height',type=int,default=480);p.add_argument('--dpr',type=int,default=1,choices=[1,2,3]);p.add_argument('--time',type=float,default=1.92);p.add_argument('--frames',type=int,default=1);p.add_argument('--fps',type=float,default=12);p.add_argument('--catalog-only',action='store_true');p.add_argument('--tissue-focus',action='store_true',help='Centre tissue crops on the organ interior, avoiding holes and protected connections.');p.add_argument('--browser-frames',action='store_true',help='Write each view as id/000.jpg and a viewer-compatible catalog, preserving absolute times.');a=p.parse_args()
 if a.frames<1 or a.fps<=0:p.error('frames and fps must be positive')
 out=Path(a.output);out.mkdir(parents=True,exist_ok=True);r.initialise()
 sources=list((r.b.ROOT/'scripts/war').glob('BodyLife*.lua'))+list((r.b.ROOT/'scripts/war').glob('OrganDetail*.lua'))+list((r.b.ROOT/'scripts/war').glob('OrganBoundaries*.lua'))+list((r.b.ROOT/'scripts/war').glob('OrganForeground*.lua'))+[r.b.ROOT/'scripts/war/ReferenceArt.lua',r.b.ROOT/'scripts/war/Render.lua',r.b.ROOT/'scripts/war/HUD.lua',r.b.ROOT/'scripts/war/SmoothTerrain.lua',r.b.ROOT/'scripts/war/ReferenceTrace.lua',r.b.ROOT/'scripts/war/Contour.lua',Path(__file__),Path(r.b.__file__)]
 hashes={str(x.relative_to(r.b.ROOT)):hashlib.sha256(x.read_bytes()).hexdigest() for x in sources};views=catalog([float(z) for z in a.zooms.split(',')],a.width,a.height,a.tissue_focus)
 (out/'view-catalog.json').write_text(json.dumps({'views':views,'nativeEvidence':False,'coordinates':'source 1024x1536; world x=2*sx,y=2*sy+512; logical screen scale=64*zoom'},ensure_ascii=False,indent=2)+'\n')
 selected=[v for v in views if (a.organs=='all' or v['organ'] in a.organs.split(',')) and v['anchor'] in a.anchors.split(',')]
 records=[];browser_records=[];start=time.perf_counter();suffix=(a.organs.replace(',','-')+'-'+a.anchors.replace(',','-'))
 r.b.l.execute("CloseupDetail=require('war.OrganDetail')")
 assets=[r.b.ROOT/'assets/image/anatomy-reference/reference.png',r.b.ROOT/'assets/image/anatomy-reference/body-life/organ-tissue-atlas.png',r.b.ROOT/'assets/image/anatomy-reference/body-life/lung-tissue-inpaint.png']
 assets.extend((r.b.ROOT/'assets/image/anatomy-reference/body-life').glob('*-tissue-hires.png'))
 asset_hashes={str(x.relative_to(r.b.ROOT)):hashlib.sha256(x.read_bytes()).hexdigest() for x in assets if x.is_file()}
 if not a.catalog_only:
  for v in selected:
   files=[];detail_counts=[];motion_rows=[];pane_rows=[];base_pixels=None;base_pane=None;ever_change=None;ever_pane=None
   for i in range(a.frames):
    t=a.time+i/a.fps;sx,sy=v['sourceCenter'];data=draw(t,sx,sy,v['zoom'],a.width,a.height,a.dpr)
    current_image=Image.open(io.BytesIO(data)).convert('RGB')
    current_pixels=np.asarray(current_image,dtype=np.int16);pane_pixels=np.asarray(current_image.resize((295,221),Image.Resampling.LANCZOS),dtype=np.int16)
    if base_pixels is None:
     base_pixels=current_pixels.copy();base_pane=pane_pixels.copy();ever_change=np.zeros(current_pixels.shape[:2],np.int16);ever_pane=np.zeros(pane_pixels.shape[:2],np.int16)
    for current,base,rows,ever in [(current_pixels,base_pixels,motion_rows,ever_change),(pane_pixels,base_pane,pane_rows,ever_pane)]:
     difference=np.abs(current-base);per_pixel=difference.max(axis=2);np.maximum(ever,per_pixel,out=ever)
     rows.append({'frame':i,'time':t,'meanAbsoluteRgbDifference':float(difference.mean()),'p95MaximumChannelDifference':float(np.percentile(per_pixel,95)),'changedPixelFraction':float((per_pixel>0).mean()),'fractionChangingByAtLeast5':float((per_pixel>=5).mean())})
    if a.browser_frames:
     folder=out/v['id'];folder.mkdir(parents=True,exist_ok=True);name=f"{v['id']}/{i:03d}.jpg"
     current_image.save(out/name,quality=94,subsampling=0)
    else:
     name=f"{v['id']}-t{t:.4f}.png";(out/name).write_bytes(data)
    files.append({'file':name,'time':t});detail_counts.append(int(r.b.l.globals().CloseupDetail.last.details))
   def motion_summary(rows,ever):
    keys=['meanAbsoluteRgbDifference','p95MaximumChannelDifference','changedPixelFraction','fractionChangingByAtLeast5']
    return {'maximumOverFrames':{key:max(row[key] for row in rows) for key in keys},'peakMeanFrame':max(rows,key=lambda row:row['meanAbsoluteRgbDifference'])['frame'],'everChangedPixelFraction':float((ever>0).mean()),'everAtLeast5Fraction':float((ever>=5).mean()),'firstFrameIsReference':True,'comparisonBeforeJpegEncoding':True,'perceptibility':'not inferred from pixel differences'}
   records.append({**v,'frames':files,'fps':a.fps,'dpr':a.dpr,'detailCounts':detail_counts,'detailCountMin':min(detail_counts),'detailCountMax':max(detail_counts),'motionEvidence':motion_summary(motion_rows,ever_change),'paneMotionEvidence':{'size':[295,221],**motion_summary(pane_rows,ever_pane)}})
   label=v['name']+(' · 器官概览' if v['anchor']=='organ-fit' else ' · 组织近景' if v['anchor']=='center' else ' · 边界近景')
   browser_records.append({'id':v['id'],'label':label,'folder':'frames/'+v['id'],'frames':len(files),'fps':a.fps,'width':a.width*a.dpr,'height':a.height*a.dpr})
   if a.browser_frames:(out/f'partial-catalog-{suffix}.json').write_text(json.dumps(browser_records,ensure_ascii=False,indent=2)+'\n')
   print(v['id'],len(files),'elapsed',round(time.perf_counter()-start,1),'paneMeanChange',round(records[-1]['paneMotionEvidence']['maximumOverFrames']['meanAbsoluteRgbDifference'],4),flush=True)
 report={'nativeEvidence':False,'framesAreActualLuaRenders':True,'frameTimeIsAbsoluteVisualTime':True,'durationSeconds':a.frames/a.fps if a.frames>1 else 0,'records':records,'runtimeSha256':hashes,'assetSha256':asset_hashes,'assetsChangedDuringExport':[k for k,v in asset_hashes.items() if hashlib.sha256((r.b.ROOT/k).read_bytes()).hexdigest()!=v],'sourcesChangedDuringExport':[str(x.relative_to(r.b.ROOT)) for x in sources if hashlib.sha256(x.read_bytes()).hexdigest()!=hashes[str(x.relative_to(r.b.ROOT))]],'elapsedOfflineSeconds':time.perf_counter()-start,'limitations':['Cairo rendering differs from native NanoVG in antialiasing and filtering.','A static frame is not proof of perceptible motion.','Centre crops at high zoom contain tissue rather than the entire organ; boundary probes assess identification separately.']}
 suffix=(a.organs.replace(',','-')+'-'+a.anchors.replace(',','-'));(out/f'frames-{suffix}.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
 if a.browser_frames:(out/f'browser-catalog-{suffix}.json').write_text(json.dumps(browser_records,ensure_ascii=False,indent=2)+'\n')
 print(out,flush=True)
if __name__=='__main__':main()
