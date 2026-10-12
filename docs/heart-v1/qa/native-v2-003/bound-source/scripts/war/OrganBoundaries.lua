-- Fixed source-derived visual membranes. This module never changes gameplay geometry.
-- Source coordinates remain on the 1024 x 1536 atlas; public queries use world units.
local Data=require('war.OrganBoundariesData')
local O={enabled=true,last={organs=0,segments=0},sourceSha256=Data.sourceSha256}
local order={'brain','lung_r','lung_l','liver','stomach','pancreas','kidney_r','kidney_l','large_intestine','small_intestine','bladder','heart'}
local styles={brain={153,69,102},lung_r={159,75,105},lung_l={159,75,105},heart={142,51,63},
 liver={127,69,56},stomach={180,100,69},pancreas={176,118,50},kidney_r={147,64,67},kidney_l={147,64,67},
 large_intestine={175,86,95},small_intestine={179,95,101},bladder={183,116,50}}
local cache={}
local function prepare(id)
 if cache[id] then return cache[id] end
 local source=Data.organs[id];if not source then return nil end
 local r={id=id,outlinePaths=source.outlinePaths,interiorPaths=source.interiorPaths,rimPaths={},bounds=source.bounds,connections=source.connections,cavityPaths=source.cavityPaths}
 for _,points in ipairs(source.rimPaths) do
  local path={points=points,x1=math.huge,y1=math.huge,x2=-math.huge,y2=-math.huge}
  for _,p in ipairs(points) do path.x1,path.y1,path.x2,path.y2=math.min(path.x1,p[1]),math.min(path.y1,p[2]),math.max(path.x2,p[1]),math.max(path.y2,p[2]) end
  r.rimPaths[#r.rimPaths+1]=path
 end
 -- Cache segment endpoints once for interior queries used by texture patch caches.
 r.segments={}
 for _,path in ipairs(r.interiorPaths) do
  local previous=path.points[#path.points]
  for _,p in ipairs(path.points) do
   local dx,dy=p[1]-previous[1],p[2]-previous[2]
   r.segments[#r.segments+1]={previous[1],previous[2],p[1],p[2],dx,dy,dx*dx+dy*dy}
   previous=p
  end
 end
 cache[id]=r;return r
end
-- Returned paths are immutable shared visual data, all in source-pixel coordinates.
function O.get(id) return prepare(id) end
function O.paths(id,outline)
 local r=prepare(id);return r and (outline and r.outlinePaths or r.interiorPaths) or {}
end
function O.ids() return order end
-- Conservative interior clearance. Zero means outside/on a protected boundary;
-- positive distance is in world units and includes foreground holes/attachments.
function O.clearance(id,worldX,worldY)
 local r=prepare(id);if not r then return 0 end
 local x,y=worldX*.5,(worldY-512)*.5;local b=r.bounds
 if x<=b[1] or x>=b[3] or y<=b[2] or y>=b[4] then return 0 end
 local inside=false;local distance=math.huge
 for _,e in ipairs(r.segments) do
  if (e[2]>y)~=(e[4]>y) and x<e[5]*(y-e[2])/(e[4]-e[2])+e[1] then inside=not inside end
  local t=e[7]>0 and math.max(0,math.min(1,((x-e[1])*e[5]+(y-e[2])*e[6])/e[7])) or 0
  local dx,dy=x-e[1]-e[5]*t,y-e[2]-e[6]*t
  distance=math.min(distance,dx*dx+dy*dy)
 end
 -- 0.75 source px reserve covers polygon simplification and edge pixel coverage.
 return inside and math.max(0,math.sqrt(distance)-.75)*2 or 0
end
function O.contains(id,worldX,worldY,margin)
 local d=O.clearance(id,worldX,worldY);return d>0 and d>=(margin or 0)
end
local function smooth(v) v=math.max(0,math.min(1,v));return v*v*(3-2*v) end
local function visible(p,x1,x2,y1,y2) return p.x1<=x2 and p.x2>=x1 and p.y1<=y2 and p.y2>=y1 end
local function path(vg,p,ox,oy,z)
 local first=p[1];nvgMoveTo(vg,ox+first[1]*z,oy+first[2]*z)
 for i=2,#p-1 do local a,b=p[i],p[i+1]
  nvgQuadTo(vg,ox+a[1]*z,oy+a[2]*z,ox+(a[1]+b[1])*.5*z,oy+(a[2]+b[2])*.5*z)
 end
 local last=p[#p];nvgLineTo(vg,ox+last[1]*z,oy+last[2]*z)
end
function O.draw(R,g,s,x1,x2,y1,y2)
 O.last={organs=0,segments=0}
 if not O.enabled or not s or s.anatomyVersion~=4 or g.zoom<=.06 then return O.last end
 local fade=smooth((g.zoom-.06)/.08);local z=64*g.zoom;local vg=R.vg
 local sx1,sx2,sy1,sy2=x1*.5,x2*.5,(y1-512)*.5,(y2-512)*.5
 local ox,oy=R.project(g,0,512)
 nvgSave(vg);nvgLineJoin(vg,NVG_ROUND);nvgLineCap(vg,0)
 for _,id in ipairs(order) do local r=prepare(id);local b=r.bounds
  if b[1]<=sx2 and b[3]>=sx1 and b[2]<=sy2 and b[4]>=sy1 then
   local count=0;nvgBeginPath(vg)
   for _,p in ipairs(r.rimPaths) do
    if visible(p,sx1,sx2,sy1,sy2) then path(vg,p.points,ox,oy,z);count=count+1 end
   end
   if count>0 then
    local c=styles[id]
    -- Two restrained membrane layers replace hard polygon outlines. The source
    -- organ silhouette, locations and all connection gaps stay fixed.
    nvgStrokeWidth(vg,math.min(2.4,z*.48));nvgStrokeColor(vg,nvgRGBA(c[1],c[2],c[3],math.floor(63*fade)));nvgStroke(vg)
    nvgStrokeWidth(vg,math.min(.85,z*.16));nvgStrokeColor(vg,nvgRGBA(255,226,190,math.floor(108*fade)));nvgStroke(vg)
    O.last.organs=O.last.organs+1;O.last.segments=O.last.segments+count
   end
  end
 end
 nvgRestore(vg);return O.last
end
return O
