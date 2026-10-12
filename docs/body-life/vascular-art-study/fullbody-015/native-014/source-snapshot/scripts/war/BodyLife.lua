-- Visual-only anatomy. Source coordinates, anchors and gameplay geometry stay fixed.
local U=require('war.Util')
local M=require('war.ReferenceMap')
local Motion=require('war.BodyLifeMotion')
local Masks=require('war.BodyLifeMasks')
local Regions=require('war.BodyLifeRegions')
local Assets=require('war.BodyLifeAssets')
local B={enabled=true,intensity=1,images=setmetatable({},{__mode='k'}),packs=setmetatable({},{__mode='k'}),
 last={triangles=0,organs=0,flow=0},maxTriangles=384}
B.sample=Motion.sample
B.offset=Motion.offset
B.specs=Motion.specs
-- The accepted runtime scope is heartbeat and vessel flow only.
local order={'heart'}
local meshes={}
local function smooth(x) x=U.clamp(x,0,1);return x*x*(3-2*x) end
local function interior(key,x,y)
 local found=false
 for _,path in ipairs(Regions[key] or {}) do
  if M.contains(path.points or path,x,y) then
   if path.hole then return false end;found=true
  end
 end
 return found
end
local function weight(key,s,x,y)
 local edge=math.min(x-s.x,s.x+s.w-x,y-s.y,s.y+s.h-y)
 if edge<=0 then return 0 end
 -- Pixel-derived interior masks exclude source pigment belonging to foreground.
 for _,p in ipairs({{0,0},{-3,0},{3,0},{0,-3},{0,3}}) do if not interior(key,x+p[1],y+p[2]) then return 0 end end
 for _,path in ipairs(Masks[key] or {}) do if M.contains(path,x,y) then return 0 end end
 return smooth(edge/14)
end
function B.mesh(key,level)
 local cacheKey=key..':'..tostring(level or 1)
 if meshes[cacheKey] then return meshes[cacheKey] end
 level=level or 1
 local original=Motion.specs[key];if not original then return end
 local s={};for k,v in pairs(original) do s[k]=v end
 if level==0 then s.nx,s.ny=3,3
 elseif level==1 then s.nx,s.ny=3,4 end
 if key=='heart' then s.nx,s.ny=5,4
 elseif key=='lung_r' or key=='lung_l' then s.nx,s.ny=4,5 end
 if key=='large_intestine' then s.nx,s.ny=12,9 end
 local mesh={id=key,spec=s,vertices={},triangles={},target={}}
 for iy=0,s.ny do for ix=0,s.nx do
  local x,y=s.x+s.w*ix/s.nx,s.y+s.h*iy/s.ny
  if (key=='lung_r' or key=='lung_l' or key=='stomach' or key=='small_intestine') and ix>0 and ix<s.nx and iy>0 and iy<s.ny and weight(key,s,x,y)==0 then
   -- A regular grid can land on a fixed branch or outside curved tissue. Relocate
   -- interior source vertices within their own small cell neighborhood once.
   -- < 1/4 cell jitter preserves source triangle orientation and shared edges.
   local bx,by,best=x,y,math.huge
   for _,fy in ipairs({0,-.11,.11,-.22,.22}) do for _,fx in ipairs({0,-.11,.11,-.22,.22}) do
    local xx,yy=x+fx*s.w/s.nx,y+fy*s.h/s.ny
    local distance=fx*fx+fy*fy
    if distance<best and weight(key,s,xx,yy)>0 then bx,by,best=xx,yy,distance end
   end end
   x,y=bx,by
  end
  mesh.vertices[#mesh.vertices+1]={x=x,y=y,weight=weight(key,s,x,y),adjacent={}}
  mesh.target[#mesh.target+1]={x=x,y=y}
 end end
 local function add(a,b,c)
  local va,vb,vc=mesh.vertices[a],mesh.vertices[b],mesh.vertices[c]
  local ux,uy,vx,vy=vb.x-va.x,vb.y-va.y,vc.x-va.x,vc.y-va.y
  local det=ux*vy-uy*vx
  local tr={a,b,c,ix=vy/det,iy=-uy/det,jx=-vx/det,jy=ux/det,
   active=va.weight+vb.weight+vc.weight>0}
  mesh.triangles[#mesh.triangles+1]=tr
  for _,i in ipairs({a,b,c}) do local adj=mesh.vertices[i].adjacent;adj[#adj+1]=#mesh.triangles end
 end
 for iy=0,s.ny-1 do for ix=0,s.nx-1 do
  local a=iy*(s.nx+1)+ix+1;local b=a+1;local c=a+s.nx+1;local d=c+1
  add(a,b,d);add(a,d,c)
 end end
 meshes[cacheKey]=mesh;return mesh
end
function B.prepare(vg)
 if B.images[vg]~=nil then return B.images[vg] end
 local pack={ids={},ready=true}
 for _,kind in ipairs({'source','tissue','foreground'}) do
  local path=Assets[kind]
  if path then
   local id=nvgCreateImage(vg,path,NVG_IMAGE_GENERATE_MIPMAPS)
   pack[kind]=id
   if not id or id<=0 then pack.ready=false else pack.ids[#pack.ids+1]=id end
  end
 end
 if not pack.ready then
  for _,id in ipairs(pack.ids) do nvgDeleteImage(vg,id) end
  pack.ids={};B.images[vg]=-1
 else B.images[vg]=pack.source end
 B.packs[vg]=pack
 for _,key in ipairs(order) do B.mesh(key,0);B.mesh(key,1);B.mesh(key,2) end
 return B.images[vg]
end
function B.release(vg)
 local pack=B.packs[vg]
 if pack then for _,id in ipairs(pack.ids) do nvgDeleteImage(vg,id) end end
 B.images[vg]=nil;B.packs[vg]=nil
end
function B.ready(vg,g,s)
 return B.enabled and g.bodyLifeEnabled~=false and s.anatomyVersion==4 and B.prepare(vg)>0
end
-- Kept public for geometry acceptance. Cached source inverses are used during draw.
function B.affine(a,b,c,p,q,r)
 local ux,uy,vx,vy=b.x-a.x,b.y-a.y,c.x-a.x,c.y-a.y
 local det=ux*vy-uy*vx;if math.abs(det)<1e-8 then return end
 local xx,xy,yx,yy=q.x-p.x,q.y-p.y,r.x-p.x,r.y-p.y
 local aa,bb=(xx*vy-yx*uy)/det,(xy*vy-yy*uy)/det
 local cc,dd=(yx*ux-xx*vx)/det,(yy*ux-xy*vx)/det
 if aa*dd-bb*cc<=.1 then return end
 return aa,bb,cc,dd,p.x-aa*a.x-cc*a.y,p.y-bb*a.x-dd*a.y
end
local function triangle(vg,image,mesh,tr)
 local a,b,c=mesh.vertices[tr[1]],mesh.vertices[tr[2]],mesh.vertices[tr[3]]
 local p,q,r=mesh.target[tr[1]],mesh.target[tr[2]],mesh.target[tr[3]]
 local ux,uy,vx,vy=q.x-p.x,q.y-p.y,r.x-p.x,r.y-p.y
 local aa,bb=ux*tr.ix+vx*tr.iy,uy*tr.ix+vy*tr.iy
 local cc,dd=ux*tr.jx+vx*tr.jy,uy*tr.jx+vy*tr.jy
 if aa*dd-bb*cc<=.1 then return false end
 nvgSave(vg);nvgTransform(vg,aa,bb,cc,dd,p.x-aa*a.x-cc*a.y,p.y-bb*a.x-dd*a.y)
 nvgBeginPath(vg);nvgMoveTo(vg,a.x,a.y);nvgLineTo(vg,b.x,b.y);nvgLineTo(vg,c.x,c.y);nvgClosePath(vg)
 nvgFillPaint(vg,nvgImagePattern(vg,0,0,1024,1536,0,image,1));nvgFill(vg);nvgRestore(vg)
 return true
end
local function restoreForeground(vg,pack)
 nvgShapeAntiAlias(vg,1)
 if pack.foreground then
  nvgBeginPath(vg);nvgRect(vg,0,0,1024,1536)
  nvgFillPaint(vg,nvgImagePattern(vg,0,0,1024,1536,0,pack.foreground,1));nvgFill(vg)
 else
  nvgBeginPath(vg)
  for _,key in ipairs({'lung_r','lung_l','heart'}) do for _,path in ipairs(Masks[key] or {}) do
   nvgMoveTo(vg,path[1][1],path[1][2]);for i=2,#path do nvgLineTo(vg,path[i][1],path[i][2]) end;nvgClosePath(vg)
  end end
  nvgFillPaint(vg,nvgImagePattern(vg,0,0,1024,1536,0,pack.source,1));nvgFill(vg)
 end
end
local function restoreOutsideInterior(vg,pack,key,spec)
 -- A zero-weight vertex alone does not pin pixels between vertices. Restore
 -- every non-interior source pixel, including concavities and tiny vessel holes.
 nvgShapeAntiAlias(vg,1)
 nvgBeginPath(vg);nvgRect(vg,spec.x,spec.y,spec.w,spec.h);nvgPathWinding(vg,NVG_SOLID)
 for _,path in ipairs(Regions[key] or {}) do
  local p=path.points or path
  nvgMoveTo(vg,p[1][1],p[1][2]);for i=2,#p do nvgLineTo(vg,p[i][1],p[i][2]) end;nvgClosePath(vg)
  nvgPathWinding(vg,path.hole and NVG_SOLID or NVG_HOLE)
 end
 nvgFillPaint(vg,nvgImagePattern(vg,0,0,1024,1536,0,pack.source,1));nvgFill(vg)
 nvgShapeAntiAlias(vg,0)
end
function B.draw(R,g,s,x1,x2,y1,y2)
 B.last.triangles=0;B.last.organs=0
 if not B.ready(R.vg,g,s) or g.zoom>=.15 then return end
 local pack=B.packs[R.vg]
 local ox,oy=R.project(g,0,512);local scale=64*g.zoom;local t=g.realTime or 0
 nvgSave(R.vg);nvgTranslate(R.vg,ox,oy);nvgScale(R.vg,scale,scale);nvgShapeAntiAlias(R.vg,0)
 for _,key in ipairs(order) do
  local o=M.byId[key]
  local allowed=not g.bodyLifeMini or key=='heart' or key=='lung_r' or key=='lung_l'
  if allowed and o.x1<=x2 and o.x2>=x1 and o.y1<=y2 and o.y2>=y1 then
   local mesh=B.mesh(key,1);local changed=false;local sampled=Motion.sample(t,key)
   local tissue=pack.tissue and (not Assets.tissueOrgans or Assets.tissueOrgans[key])
   local texture=tissue and pack.tissue or pack.source
   -- Lay down the registered texture even at a zero-displacement phase or tiny
   -- LOD. Otherwise the lungs flash back to the original at each cycle boundary.
   if tissue then
    nvgBeginPath(R.vg);nvgRect(R.vg,mesh.spec.x,mesh.spec.y,mesh.spec.w,mesh.spec.h)
    nvgFillPaint(R.vg,nvgImagePattern(R.vg,0,0,1024,1536,0,texture,1));nvgFill(R.vg)
   end
   if Motion.lod(mesh.spec.h*scale,g.zoom)>0 then
    for i,v in ipairs(mesh.vertices) do
     local dx,dy=Motion.offset(key,v,mesh.spec,t,scale,g.zoom,sampled)
     dx,dy=dx*math.min(1,B.intensity),dy*math.min(1,B.intensity)
     mesh.target[i].x,mesh.target[i].y=v.x+dx,v.y+dy
     mesh.target[i].moved=dx~=0 or dy~=0
     changed=changed or math.abs(dx)+math.abs(dy)>1e-7
    end
    if changed then
     for _,tr in ipairs(mesh.triangles) do
      -- Opaque source/registered tissue already covers identity triangles.
      -- Keep every actual displacement, including subpixel movement.
      local moved=mesh.target[tr[1]].moved or mesh.target[tr[2]].moved or mesh.target[tr[3]].moved
      if tr.active and moved and B.last.triangles<B.maxTriangles and triangle(R.vg,texture,mesh,tr) then B.last.triangles=B.last.triangles+1 end
     end
     B.last.organs=B.last.organs+1
    end
   end
   if tissue or changed then restoreOutsideInterior(R.vg,pack,key,mesh.spec) end
  end
 end
 if B.last.triangles>0 and pack.foreground then restoreForeground(R.vg,pack) end
 nvgRestore(R.vg)
end
function B.perfusion(R,g,s,x1,x2,y1,y2)
 if not B.ready(R.vg,g,s) then return end
 return require('war.BodyLifeShading').draw(R,g,s,{x1,x2,y1,y2},{mini=g.bodyLifeMini,intensity=B.intensity})
end
return B
