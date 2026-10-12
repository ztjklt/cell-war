"""Analyze reference pixels into fixed organ membranes and safe interior geometry.
No bitmap, gameplay polygon, route or save is modified. Existing polygons are
segmentation ROIs only; existing interior effect masks supply foreground seeds.
"""
from pathlib import Path
import argparse, hashlib, json
import cv2, numpy as np
from PIL import Image,ImageDraw
from lupa.lua54 import LuaRuntime
from scipy.ndimage import gaussian_filter1d

root=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--review',default='/tmp/organ-boundaries');args=p.parse_args()
review=Path(args.review);review.mkdir(parents=True,exist_ok=True)
l=LuaRuntime(unpack_returned_tuples=True);l.execute("package.path='scripts/?.lua;'..package.path")
m=l.eval("require('war.ReferenceMap')")[0];regions=l.eval("require('war.BodyLifeRegions')")[0]
source=root/'assets/image/anatomy-reference/reference.png';rgb=np.asarray(Image.open(source).convert('RGB'))
r,g,b=[rgb[:,:,i].astype(np.int16) for i in range(3)]
organs=list(m.organs.values());raw={};seeds={};full={};stats={}
shape=(1536,1024)
for o in organs:
 points=np.array([[q[1]/2,(q[2]-512)/2] for q in o.points.values()],np.int32)
 roi=np.zeros(shape,np.uint8);cv2.fillPoly(roi,[points],255);raw[o.id]=roi
 seed=np.zeros(shape,np.uint8)
 for path in regions[o.id].values():
  points=np.array([list(q.values()) for q in path.points.values()],np.int32)
  cv2.fillPoly(seed,[points],0 if path.hole else 255)
 seeds[o.id]=seed
for o in organs:
 mask=raw[o.id];ys,xs=np.where(mask>0);x0,y0,x1,y1=max(0,xs.min()-9),max(0,ys.min()-9),min(1024,xs.max()+10),min(1536,ys.max()+10)
 labels=np.zeros((y1-y0,x1-x0),np.uint8)
 dilated=cv2.dilate(mask,np.ones((11,11),np.uint8))[y0:y1,x0:x1]
 labels[dilated>0]=cv2.GC_PR_BGD;labels[mask[y0:y1,x0:x1]>0]=cv2.GC_PR_FGD
 seed=cv2.erode(seeds[o.id],np.ones((3,3),np.uint8))[y0:y1,x0:x1]
 labels[seed>0]=cv2.GC_FGD
 cv2.setRNGSeed(73)
 cv2.grabCut(rgb[y0:y1,x0:x1].copy(),labels,None,np.zeros((1,65),float),np.zeros((1,65),float),5,cv2.GC_INIT_WITH_MASK)
 a=np.zeros(shape,np.uint8);a[y0:y1,x0:x1]=np.isin(labels,[cv2.GC_FGD,cv2.GC_PR_FGD]).astype(np.uint8)*255
 # Close narrow internal fissures into an organ silhouette, then retain the
 # largest connected organ. Internal foreground holes are restored separately.
 join=7
 a=cv2.morphologyEx(a,cv2.MORPH_CLOSE,np.ones((join,join),np.uint8))
 cs,hierarchy=cv2.findContours(a,cv2.RETR_CCOMP,cv2.CHAIN_APPROX_NONE)
 outer=[c for i,c in enumerate(cs) if hierarchy[0][i][3]<0]
 holes=[c for i,c in enumerate(cs) if hierarchy[0][i][3]>=0 and cv2.contourArea(c)>200]
 a[:]=0;cv2.drawContours(a,[max(outer,key=cv2.contourArea)],-1,255,-1)
 if o.id=='large_intestine':
  for hole in holes:cv2.drawContours(a,[hole],-1,0,-1)
 a=(cv2.GaussianBlur(a,(7,7),1.3)>127).astype(np.uint8)*255
 full[o.id]=a
blue=(b-r>8)&(g-r>3)
# Match ivory only near known bones; pale organ highlights are not bone.
boneArea=np.zeros(shape,np.uint8)
for bone in m.bones.values():
 x,y,tx,ty,width=[float(bone[i]) for i in range(1,6)]
 cv2.line(boneArea,(round(x/2),round((y-512)/2)),(round(tx/2),round((ty-512)/2)),255,round(width+5))
bone=(boneArea>0)&(r>170)&(g>165)&(r-g<55)&(g-b>12)
whiteStem=np.zeros(shape,np.uint8);whiteStem[85:150,483:534]=1
stem=(whiteStem>0)&(r>180)&(g>165)&(r-g<55)&(g-b>8)
protected=blue|bone|stem
protected[154:332,496:522]=True

def paths_of(a):
 cs,h=cv2.findContours(a,cv2.RETR_CCOMP,cv2.CHAIN_APPROX_NONE)
 if h is None:return []
 return [{'points':c.reshape(-1,2).tolist(),'hole':bool(h[0][i][3]>=0)} for i,c in enumerate(cs) if cv2.contourArea(c)>=3]
def smooth_loop(points):
 # Smooth several adjacent source-pixel steps BEFORE corner cutting. Chaikin
 # alone rounds each stair but retains the staircase at close viewing scales.
 # A closed Gaussian coordinate filter preserves topology and fixed locations.
 p=gaussian_filter1d(np.array(points,float),sigma=2.5,axis=0,mode='wrap')
 for _ in range(2):
  q=np.roll(p,-1,axis=0);out=np.empty((len(p)*2,2));out[::2]=p*.75+q*.25;out[1::2]=p*.25+q*.75;p=out
 # <= .006 source px (~.35 logical px at zoom .9) chord error.
 return [[round(float(v),3) for v in point] for point in cv2.approxPolyDP(p.astype(np.float32),.006,True).reshape(-1,2)]
connections={
 'brain':[[509,110,12]],'lung_r':[[471,376,9]],'lung_l':[[545,377,9]],
 'heart':[[500,382,12],[536,380,10]],'liver':[[465,532,8]],
 'stomach':[[544,472,8],[491,548,7]],'pancreas':[[568,584,5]],
 'kidney_r':[[431,611,8]],'kidney_l':[[587,611,8]],
 'large_intestine':[[453,640,5],[534,740,6]],'small_intestine':[[473,660,5],[514,726,5]],
 'bladder':[[509,810,6]],
}
result={};overlay=Image.fromarray(rgb).convert('RGBA');draw=ImageDraw.Draw(overlay)
for idx,o in enumerate(organs):
 a=full[o.id];occluded=protected.copy()
 for front in organs[idx+1:]:occluded|=full[front.id]>0
 if o.id=='liver':
  # Fixed gallbladder/bile duct foreground: sample actual green source pigment
  # only in its anatomical ROI. Red liver highlights cannot satisfy both green
  # differences. The shared dilation/erosion below supplies a conservative rim.
  gall_roi=np.zeros(shape,bool);gall_roi[531:590,425:474]=True
  gallbladder=gall_roi&(g-r>8)&(g-b>8)&(g>85)
  occluded|=gallbladder
 if o.id=='heart':
  occluded[:390,:]=True
  # Coronary yellow branches are fixed foreground for close tissue patches.
  # Apply only to this heart ROI: pale pulmonary/gastric highlights stay intact.
  coronary=(a>0)&(r>220)&(g>135)&(g-b>24)
  occluded|=coronary
 port_mask=np.zeros(shape,np.uint8)
 for cx,cy,radius in connections[o.id]:cv2.circle(port_mask,(cx,cy),radius,1,-1)
 occluded|=port_mask>0
 occlusion=cv2.dilate(occluded.astype(np.uint8),np.ones((3,3),np.uint8))>0
 safe=cv2.erode(a,np.ones((5,5),np.uint8));safe[occlusion]=0
 cavity=[]
 if o.id=='large_intestine':
  # This drawing's central cavity is open at the intestinal connection. Keep
  # that source topology, and identify the enclosed small-bowel compartment
  # explicitly instead of painting an invented closing membrane across it.
  central=full['small_intestine'];safe[central>0]=0
  cavity=paths_of(central)
  for cp in cavity:cp['hole']=True;cp['points']=smooth_loop(cp['points'])
 outlines=paths_of(a)
 for path in outlines:path['points']=smooth_loop(path['points'])
 # Dense source-pixel contour steps limit corner cutting to subpixel movement.
 # Reserve an extra full pixel first, so smoothing cannot bridge into any
 # vessel or coronary foreground. Both drawing and query use these same paths.
 safe=cv2.erode(safe,np.ones((3,3),np.uint8))
 contours,hierarchy=cv2.findContours(safe,cv2.RETR_CCOMP,cv2.CHAIN_APPROX_NONE)
 interiors=[]
 if hierarchy is not None:
  for ci,c in enumerate(contours):
   if cv2.contourArea(c)<3:continue
   points=smooth_loop(c.reshape(-1,2).tolist())
   interiors.append({'points':points,'hole':bool(hierarchy[0][ci][3]>=0)})
 # Every original protected pixel inside the organ must remain out of the
 # smooth fill, including all coronary and bronchial pixels, not only anchors.
 checked=0;intrusions=0
 protected_pixels=occlusion&(a>0)
 compiled=[np.array(path['points'],np.float32) for path in interiors]
 for py,px in zip(*np.where(protected_pixels)):
  checked+=1;inside=False
  for contour in compiled:
   if cv2.pointPolygonTest(contour,(float(px),float(py)),False)>=0:inside=not inside
  intrusions+=int(inside)
 assert intrusions==0,(o.id,intrusions)

 rim=[]
 for path in outlines:
  pts=path['points'];current=[]
  for i,p0 in enumerate(pts):
   p1=pts[(i+1)%len(pts)];mid=(np.array(p0)+p1)/2;x,y=np.rint(mid).astype(int)
   visible=not occlusion[y,x]
   if visible:
    if not current:current.append(p0)
    current.append(p1)
   elif len(current)>1:rim.append(current);current=[]
  if len(current)>1:rim.append(current)
 # Reject subpixel fragments that read as disconnected dots at membrane scale.
 rim=[p for p in rim if sum(np.linalg.norm(np.array(v)-p[i-1]) for i,v in enumerate(p) if i)>3]
 ys,xs=np.where(a>0)
 result[o.id]={'outlinePaths':outlines,'interiorPaths':interiors,'rimPaths':rim,'bounds':[int(xs.min()),int(ys.min()),int(xs.max()),int(ys.max())],'connections':connections[o.id],'cavityPaths':cavity}
 for line in rim:draw.line([tuple(v) for v in line],fill=(67,217,178,240),width=2)
 stats[o.id]={'outlineVertices':sum(len(v['points']) for v in outlines),'interiorVertices':sum(len(v['points']) for v in interiors),'visibleRimSegments':len(rim),'safePixels':int(np.count_nonzero(safe)),'smoothedArea':sum(cv2.contourArea(np.array(p['points'],np.float32))*(-1 if p['hole'] else 1) for p in interiors),'outlineHoles':sum(p['hole'] for p in outlines),'connections':len(connections[o.id]),'cavities':len(cavity),'protectedPixelsChecked':checked,'protectedPixelIntrusions':intrusions}

def lua(v):
 if isinstance(v,dict):return '{'+','.join(k+'='+lua(value) for k,value in v.items())+'}'
 if isinstance(v,list):return '{'+','.join(lua(x) for x in v)+'}'
 if isinstance(v,bool):return str(v).lower()
 return str(v)
text='-- Fixed visual organ geometry derived from reference pixels; not gameplay geometry.\n-- Generated by scripts/qa/prepare_organ_boundaries.py. Coordinates: original 1024 x 1536 atlas.\nreturn {sourceSha256="'+hashlib.sha256(source.read_bytes()).hexdigest()+'",organs='+lua(result)+'}\n'
(root/'scripts/war/OrganBoundariesData.lua').write_text(text)
overlay.save(review/'source-boundaries.png');(review/'report.json').write_text(json.dumps(stats,indent=2)+'\n');print(json.dumps(stats,indent=2))
