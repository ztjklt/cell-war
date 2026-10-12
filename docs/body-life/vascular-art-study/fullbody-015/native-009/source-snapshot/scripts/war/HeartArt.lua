-- Registered GPT artwork only: this module warps existing image handles.
-- FullBodyMapArt owns image creation/release and its resource budget.
local T=require('war.HeartDisplayTransform')
local H={last={triangles=0},clips={}}
local function imagePaint(vg,spec,image,alpha,panel)
 local b=spec.sourceBox;local height=b[4]-b[2]
 return nvgImagePattern(vg,b[1],b[2]-(panel or 0)*height,
  b[3]-b[1],height*(spec.atlasPanels or 1),0,image,(alpha or 1)*(spec.opacity or 1))
end
local function clipSide(points,axis,value,sign)
 local out={};local previous=points[#points]
 for _,current in ipairs(points)do
  local pa=(axis==1 and previous.x or previous.y)-value
  local ca=(axis==1 and current.x or current.y)-value
  local pin,cin=pa*sign>=0,ca*sign>=0
  if pin~=cin then
   local mix=pa/(pa-ca)
   out[#out+1]={x=previous.x+(current.x-previous.x)*mix,y=previous.y+(current.y-previous.y)*mix}
  end
  if cin then out[#out+1]=current end
  previous=current
 end
 return out
end
local function clipped(mesh,spec)
 local b=spec.sourceBox;local key=table.concat(b,':')..':'..mesh.generation
 if H.clips[key]then return H.clips[key]end
 local result={}
 for index,tr in ipairs(mesh.triangles)do
  local p={mesh.vertices[tr[1]],mesh.vertices[tr[2]],mesh.vertices[tr[3]]}
  p=clipSide(p,1,b[1],1)
  if #p>0 then p=clipSide(p,1,b[3],-1)end
  if #p>0 then p=clipSide(p,2,b[2],1)end
  if #p>0 then p=clipSide(p,2,b[4],-1)end
  if #p>=3 then result[#result+1]={index=index,points=p}end
 end
 H.clips[key]=result;return result
end
local function affine(mesh,target,tr)
 local a,b,c=mesh.vertices[tr[1]],mesh.vertices[tr[2]],mesh.vertices[tr[3]]
 local p,q,r=target[tr[1]],target[tr[2]],target[tr[3]]
 local ux,uy,vx,vy=b.x-a.x,b.y-a.y,c.x-a.x,c.y-a.y
 local det=ux*vy-uy*vx
 local xx,xy,yx,yy=q.x-p.x,q.y-p.y,r.x-p.x,r.y-p.y
 local aa,bb=(xx*vy-yx*uy)/det,(xy*vy-yy*uy)/det
 local cc,dd=(yx*ux-xx*vx)/det,(yy*ux-xy*vx)/det
 return aa,bb,cc,dd,p.x-aa*a.x-cc*a.y,p.y-bb*a.x-dd*a.y
end
function H.drawSpec(R,g,s,spec,image,alpha)
 if not T.enabled(s)or not image or image<=0 or (alpha or 1)<=0 then return false end
 local f=T.frame(g);local mesh=f.mesh;local b=spec.sourceBox
 local ox,oy=R.project(g,0,512);local scale=64*g.zoom
 local vg=R.vg;H.last.triangles=0
 nvgSave(vg);nvgTranslate(vg,ox,oy);nvgScale(vg,scale,scale)
 nvgShapeAntiAlias(vg,0)
 if spec.staticPanel then
  nvgBeginPath(vg);nvgRect(vg,b[1],b[2],b[3]-b[1],b[4]-b[2])
  nvgFillPaint(vg,imagePaint(vg,spec,image,alpha,spec.staticPanel));nvgFill(vg)
 end
 -- Optional coreBox is a static distant boundary, never an internal cardiac seam.
 if spec.coreBox then
  local c=spec.coreBox
  nvgIntersectScissor(vg,c[1],c[2],c[3]-c[1],c[4]-c[2])
 end
 local animatedPaint=imagePaint(vg,spec,image,alpha,spec.animatedPanel)
 if g.heartStaticDiagnostic then
  nvgBeginPath(vg);nvgRect(vg,b[1],b[2],b[3]-b[1],b[4]-b[2])
  nvgFillPaint(vg,animatedPaint);nvgFill(vg)
  nvgRestore(vg);return true
 end
 -- Shared vessel tiles can extend beyond the cardiac mesh. Their distant pixels
 -- retain the original registration; only the overlapping area is deformed.
 local mb=mesh.sourceBox
 local x1,y1=math.max(b[1],mb[1]),math.max(b[2],mb[2])
 local x2,y2=math.min(b[3],mb[3]),math.min(b[4],mb[4])
 local function fixedRect(ax,ay,bx,by)
  if bx<=ax or by<=ay then return end
  nvgBeginPath(vg);nvgRect(vg,ax,ay,bx-ax,by-ay)
  nvgFillPaint(vg,animatedPaint)
  nvgFill(vg)
 end
 if x2<=x1 or y2<=y1 then fixedRect(b[1],b[2],b[3],b[4])
 else
  fixedRect(b[1],b[2],b[3],y1);fixedRect(b[1],y2,b[3],b[4])
  fixedRect(b[1],y1,x1,y2);fixedRect(x2,y1,b[3],y2)
 end
 for _,part in ipairs(clipped(mesh,spec))do
  local tr=mesh.triangles[part.index]
  local a,bb,c,d,e,ff=affine(mesh,f.vertices,tr)
  nvgSave(vg);nvgTransform(vg,a,bb,c,d,e,ff)
  local p=part.points;nvgBeginPath(vg);nvgMoveTo(vg,p[1].x,p[1].y)
  for i=2,#p do nvgLineTo(vg,p[i].x,p[i].y)end
  nvgClosePath(vg)
  nvgFillPaint(vg,animatedPaint)
  nvgFill(vg);nvgRestore(vg);H.last.triangles=H.last.triangles+1
 end
 nvgRestore(vg)
 return true
end
local function exclusionPath(vg,g,points)
 if #points<3 then return end
 local first=points[1];local x,y=T.forwardSource(g,first[1],first[2])
 nvgMoveTo(vg,x,y)
 local step=math.min(T.mesh.dx,T.mesh.dy)*.25
 for i=1,#points do
  local p,q=points[i],points[i%#points+1]
  local length=math.sqrt((q[1]-p[1])^2+(q[2]-p[2])^2)
  local count=math.max(1,math.ceil(length/step))
  for part=1,count do
   local mix=part/count
   local xx,yy=T.forwardSource(g,p[1]+(q[1]-p[1])*mix,p[2]+(q[2]-p[2])*mix)
   nvgLineTo(vg,xx,yy)
  end
 end
 nvgClosePath(vg)
end
-- Old shared deep/foreground tiles keep all pixels outside the new cardiac
-- silhouette. The hole follows the same display frame as the final heart PNG.
-- Ring format: {outer={{x,y},...},holes={...}}; plain point arrays also work.
function H.drawOutsideSpec(R,g,s,spec,image,alpha,excludeRings)
 if not T.enabled(s)or not image or image<=0 or (alpha or 1)<=0 or not excludeRings then return false end
 local b=spec.sourceBox;local vg=R.vg
 local ox,oy=R.project(g,0,512);local scale=64*g.zoom
 nvgSave(vg);nvgTranslate(vg,ox,oy);nvgScale(vg,scale,scale)
 nvgIntersectScissor(vg,b[1],b[2],b[3]-b[1],b[4]-b[2])
 if spec.coreBox then
  local c=spec.coreBox;nvgIntersectScissor(vg,c[1],c[2],c[3]-c[1],c[4]-c[2])
 end
 nvgBeginPath(vg);nvgRect(vg,b[1],b[2],b[3]-b[1],b[4]-b[2]);nvgPathWinding(vg,NVG_SOLID)
 for _,ring in ipairs(excludeRings)do
  exclusionPath(vg,g,ring.outer or ring.points or ring);nvgPathWinding(vg,NVG_HOLE)
  for _,hole in ipairs(ring.holes or {})do exclusionPath(vg,g,hole);nvgPathWinding(vg,NVG_SOLID)end
 end
 nvgFillPaint(vg,nvgImagePattern(vg,b[1],b[2],b[3]-b[1],b[4]-b[2],0,image,(alpha or 1)*(spec.opacity or 1)))
 nvgFill(vg);nvgRestore(vg)
 return true
end
function H.reset()H.clips={};H.last.triangles=0 end
return H
