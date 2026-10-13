-- One piecewise-affine display map for cardiac pixels, cells and inverse input.
-- The authored navigation remains in the undeformed source/world coordinates.
local Motion=require('war.HeartMotion')
local T={generation=0,contract=Motion.defaultContract,frames=setmetatable({},{__mode='k'})}
local function cross(ax,ay,bx,by)return ax*by-ay*bx end
local function segmentHitsTriangle(a,b,p,q,r)
 local low,high=0,1
 for _,edge in ipairs({{p,q},{q,r},{r,p}})do
  local u,v=edge[1],edge[2]
  local sx,sy=v.x-u.x,v.y-u.y
  local first=cross(sx,sy,a[1]-u.x,a[2]-u.y)
  local change=cross(sx,sy,b[1]-a[1],b[2]-a[2])
  if math.abs(change)<1e-12 then
   if first< -1e-9 then return false end
  else
   local at=(-1e-9-first)/change
   if change>0 then low=math.max(low,at)else high=math.min(high,at)end
   if low>high then return false end
  end
 end
 return true
end
local function preparePins(mesh,contract)
 local sections={};local pinned={}
 for _,c in ipairs(contract.connectors or {})do
  local a,n=c.anchorSource,c.inwardSource or c.normalSource
  local w=c.halfWidthSource or 4
  sections[#sections+1]={id=c.id,kind='proximal',points={
   {a[1]-n[2]*w,a[2]+n[1]*w},{a[1]+n[2]*w,a[2]-n[1]*w}}}
 end
 for _,ring in ipairs(contract.fixedBloodContours or{})do
  local last=ring.outer[#ring.outer]
  for _,point in ipairs(ring.outer)do
   sections[#sections+1]={id='fixed-blood',kind='external',points={last,point}};last=point
  end
 end
 local b,registered=contract.sourceBox,Motion.crossBoxSourceBox
 local same=true;for i=1,4 do if b[i]~=registered[i]then same=false end end
 local distant=contract.crossBoxSections or (same and Motion.crossBoxSections or {})
 for _,c in ipairs(distant)do sections[#sections+1]={id=c.id,kind='crossBox',points=c.points}end
 for _,section in ipairs(sections)do
  for _,tr in ipairs(mesh.triangles)do
   if segmentHitsTriangle(section.points[1],section.points[2],
     mesh.vertices[tr[1]],mesh.vertices[tr[2]],mesh.vertices[tr[3]])then
    for _,i in ipairs(tr)do pinned[i]=true end
   end
  end
 end
 mesh.pinWeights={};mesh.sections=sections;mesh.pinnedVertices=0
 for _,p in pairs(pinned)do if p then mesh.pinnedVertices=mesh.pinnedVertices+1 end end
 for i,p in ipairs(mesh.vertices)do
  local distance=math.huge
  for j in pairs(pinned)do
   local q=mesh.vertices[j];distance=math.min(distance,math.sqrt((p.x-q.x)^2+(p.y-q.y)^2))
  end
  local t=math.min(1,distance/(contract.pinFadeSource or 10))
  mesh.pinWeights[i]=t*t*(3-2*t)
 end
end
local function barycentric(vertices,tr,x,y)
 local a,b,c=vertices[tr[1]],vertices[tr[2]],vertices[tr[3]]
 local ux,uy,vx,vy=b.x-a.x,b.y-a.y,c.x-a.x,c.y-a.y
 local det=cross(ux,uy,vx,vy)
 local u=cross(x-a.x,y-a.y,vx,vy)/det
 local v=cross(ux,uy,x-a.x,y-a.y)/det
 if u>=-1e-8 and v>=-1e-8 and u+v<=1+1e-8 then return 1-u-v,u,v end
end
function T.configure(contract)
 contract=contract or T.contract
 if T.mesh and T.contract==contract then return T.mesh end
 local b=assert(contract.sourceBox,'cardiac sourceBox required')
 assert(b[3]>b[1]and b[4]>b[2],'invalid cardiac sourceBox')
 T.contract=contract;T.generation=T.generation+1;T.frames=setmetatable({},{__mode='k'})
 local grid=contract.grid or {12,16};local nx,ny=grid[1],grid[2]
 local sx,sy=(b[3]-b[1])/nx,(b[4]-b[2])/ny
 local mesh={vertices={},triangles={},nx=nx,ny=ny,dx=sx,dy=sy,sourceBox=b,
  generation=T.generation,cellMargin=math.sqrt(sx*sx+sy*sy)*1.01}
 for iy=0,ny do for ix=0,nx do
  mesh.vertices[#mesh.vertices+1]={x=b[1]+ix*sx,y=b[2]+iy*sy}
 end end
 for iy=0,ny-1 do for ix=0,nx-1 do
  local a=iy*(nx+1)+ix+1;local c=a+nx+1
  mesh.triangles[#mesh.triangles+1]={a,a+1,c+1}
  mesh.triangles[#mesh.triangles+1]={a,c+1,c}
 end end
 preparePins(mesh,contract)
 mesh.offsetBases={};mesh.activeVertices=0
 for i,p in ipairs(mesh.vertices)do
  if mesh.pinWeights[i]>0 then
   local basis=Motion.prepareBasis(p.x,p.y,contract)
   mesh.offsetBases[i]=basis
   if basis then mesh.activeVertices=mesh.activeVertices+1 end
  end
 end
 mesh.dynamicTriangles={};mesh.staticTriangles={};mesh.triangleStatic={}
 mesh.staticMinAreaRatio=math.huge;mesh.identityMinAreaRatio=math.huge
 for index,tr in ipairs(mesh.triangles)do
  local a,b,c=mesh.vertices[tr[1]],mesh.vertices[tr[2]],mesh.vertices[tr[3]]
  local area=cross(b.x-a.x,b.y-a.y,c.x-a.x,c.y-a.y)/(mesh.dx*mesh.dy)
  mesh.identityMinAreaRatio=math.min(mesh.identityMinAreaRatio,area)
  if not mesh.offsetBases[tr[1]]and not mesh.offsetBases[tr[2]]and not mesh.offsetBases[tr[3]]then
   mesh.triangleStatic[index]=true;mesh.staticTriangles[#mesh.staticTriangles+1]=tr
   mesh.staticMinAreaRatio=math.min(mesh.staticMinAreaRatio,area)
  else mesh.dynamicTriangles[#mesh.dynamicTriangles+1]=tr end
 end
 T.mesh=mesh
 return mesh
end
T.configure(require('war.HeartBattlefieldData'))
function T.enabled(s)
 if not s or s.anatomyVersion~=4 or s.heartDisplayEnabled==false then return false end
 if s.fullbodyBattlefieldVersion==1 then return true end
 if s.organBattlefieldVersion==1 then
  for _,id in ipairs(s.organBattlefieldIds or {})do if id=='heart'then return true end end
 end
 return false
end
function T.makeFrame(time,intensity)
 local mesh=T.mesh;local q=Motion.sample(time)
 local amount=math.max(0,math.min(1,intensity==nil and 1 or intensity))
 local f={time=time or 0,sample=q,vertices={},mesh=mesh,generation=T.generation,
  minAreaRatio=mesh.staticMinAreaRatio,intensity=amount,maxOffsetSource=0}
 if amount==0 or(q.atrial==0 and q.ventricular==0)then
  f.vertices=mesh.vertices;f.minAreaRatio=mesh.identityMinAreaRatio
  f.identity=true;f.safe=f.minAreaRatio>=.7
  return f
 end
 for i,p in ipairs(mesh.vertices)do
  local basis=mesh.offsetBases[i]
  if amount>0 and basis then
   local dx,dy,length=Motion.offsetPrepared(basis,q)
   local weight=amount*mesh.pinWeights[i]
   f.vertices[i]={x=p.x+dx*weight,y=p.y+dy*weight}
   f.maxOffsetSource=math.max(f.maxOffsetSource,length*weight)
  else
   -- Source vertices are immutable; the frame remains safe to retain for input.
   f.vertices[i]=p
  end
 end
 for _,tr in ipairs(mesh.dynamicTriangles)do
  local a,b,c=f.vertices[tr[1]],f.vertices[tr[2]],f.vertices[tr[3]]
  local area=cross(b.x-a.x,b.y-a.y,c.x-a.x,c.y-a.y)/(mesh.dx*mesh.dy)
  f.minAreaRatio=math.min(f.minAreaRatio,area)
 end
 -- Reject an unsafe contract as a whole; never render a folded/click-ambiguous mesh.
 if f.minAreaRatio<.7 then
  f.safe=false;f.vertices=mesh.vertices;f.maxOffsetSource=0
 else f.safe=true end
 return f
end
-- Call once before drawing the world. Input reuses this exact displayed frame.
function T.beginFrame(g)
 local amount=not g.heartStaticDiagnostic and T.enabled(g.state)and g.bodyLifeEnabled~=false
  and math.max(0,math.min(1,g.heartDisplayIntensity or 1))or 0
 local time=g.heartStaticDiagnostic and 0 or g.heartDisplayTime or g.realTime or 0
 local current=T.frames[g]
 if not current or current.time~=time or current.generation~=T.generation or current.intensity~=amount then
  current=T.makeFrame(time,amount);T.frames[g]=current
 end
 return current
end
function T.frame(g)
 local f=T.frames[g]
 if not f or f.generation~=T.generation then return T.beginFrame(g)end
 return f
end
function T.forward(f,x,y)
 local m=f.mesh;local b=m.sourceBox
 if x<b[1]or y<b[2]or x>b[3]or y>b[4]then return x,y end
 local ix=math.min(m.nx-1,math.floor((x-b[1])/m.dx))
 local iy=math.min(m.ny-1,math.floor((y-b[2])/m.dy))
 local first=(iy*m.nx+ix)*2+1
 for index=first,first+1 do
  local tr=m.triangles[index];local a,u,v=barycentric(m.vertices,tr,x,y)
  if a then
   local p,q,r=f.vertices[tr[1]],f.vertices[tr[2]],f.vertices[tr[3]]
   return p.x*a+q.x*u+r.x*v,p.y*a+q.y*u+r.y*v
  end
 end
 return x,y
end
-- Bind an immutable authored point once; evaluate its exact source-triangle
-- barycentrics against the same display frame used by inverse point selection.
function T.bindSource(x,y)
 local m=T.mesh;local b=m.sourceBox
 local result={x=x,y=y,generation=T.generation}
 if x<b[1]or y<b[2]or x>b[3]or y>b[4]then return result end
 local ix=math.min(m.nx-1,math.floor((x-b[1])/m.dx))
 local iy=math.min(m.ny-1,math.floor((y-b[2])/m.dy))
 local first=(iy*m.nx+ix)*2+1
 for index=first,first+1 do
  local tr=m.triangles[index];local a,u,v=barycentric(m.vertices,tr,x,y)
  if a then result.tr=tr;result.a=a;result.u=u;result.v=v;break end
 end
 return result
end
function T.forwardBound(f,point)
 if point.generation~=f.generation then return T.forward(f,point.x,point.y)end
 local tr=point.tr
 if not tr then return point.x,point.y end
 local p,q,r=f.vertices[tr[1]],f.vertices[tr[2]],f.vertices[tr[3]]
 local a,u,v=point.a,point.u,point.v
 return p.x*a+q.x*u+r.x*v,p.y*a+q.y*u+r.y*v
end
function T.inverse(f,x,y)
 local m=f.mesh;local b=m.sourceBox
 if x<b[1]or y<b[2]or x>b[3]or y>b[4]then return x,y end
 -- Displacement is bounded below one source pixel; candidate neighboring cells
 -- include every containing deformed triangle without a whole-mesh search.
 local ix=math.min(m.nx-1,math.floor((x-b[1])/m.dx))
 local iy=math.min(m.ny-1,math.floor((y-b[2])/m.dy))
 for yy=math.max(0,iy-1),math.min(m.ny-1,iy+1)do
  for xx=math.max(0,ix-1),math.min(m.nx-1,ix+1)do
   local first=(yy*m.nx+xx)*2+1
   for index=first,first+1 do
    local tr=m.triangles[index];local a,u,v=barycentric(f.vertices,tr,x,y)
    if a then
     local p,q,r=m.vertices[tr[1]],m.vertices[tr[2]],m.vertices[tr[3]]
     return p.x*a+q.x*u+r.x*v,p.y*a+q.y*u+r.y*v
    end
   end
  end
 end
 return x,y
end
function T.forwardSource(g,x,y)return T.forward(T.frame(g),x,y)end
function T.inverseSource(g,x,y)return T.inverse(T.frame(g),x,y)end
function T.forwardWorld(g,x,y)
 local sx,sy=T.forwardSource(g,x*.5,(y-512)*.5)
 return sx*2,sy*2+512
end
function T.inverseWorld(g,x,y)
 local sx,sy=T.inverseSource(g,x*.5,(y-512)*.5)
 return sx*2,sy*2+512
end
function T.displayPosition(g,e)
 local x,y=require('war.Motion').position(g,e)
 return T.forwardWorld(g,x,y)
end
-- Unchanged camera projection belongs to View/R. Only world commands use this.
function T.commandPoint(R,g,x,y)
 local wx,wy=R.unproject(g,x,y)
 return T.inverseWorld(g,wx,wy)
end
return T
