-- Cached closed curves from a sparse occupancy mask; rendering only.
local D=require('war.Data')
local C={}
local vertexStride=D.INDEX_STRIDE+2
-- Cells occupy [x,x+step] x [y,y+step]. Directed borders keep holes distinct.
function C.build(cells,step)
 local edges={}
 local function key(x,y) return y*vertexStride+x end
 local function edge(x,y,tx,ty)
  local k=key(x,y);local row=edges[k];if not row then row={};edges[k]=row end
  row[#row+1]={x=x,y=y,tx=tx,ty=ty,k=key(tx,ty)}
 end
 for k,p in pairs(cells) do local x,y=p[1],p[2]
  if not cells[(y-step)*vertexStride+x] then edge(x,y,x+step,y) end
  if not cells[y*vertexStride+x+step] then edge(x+step,y,x+step,y+step) end
  if not cells[(y+step)*vertexStride+x] then edge(x+step,y+step,x,y+step) end
  if not cells[y*vertexStride+x-step] then edge(x,y+step,x,y) end
 end
 local out={}
 while next(edges) do
  local first=next(edges);local k=first;local points={};local guard=0
  repeat
   local row=edges[k];if not row then break end
   local e=table.remove(row);if #row==0 then edges[k]=nil end
   points[#points+1]={e.x,e.y};k=e.k;guard=guard+1
  until k==first or guard>1000000
  if k==first and #points>=3 then
   local reduced={};local area=0;local x1,y1,x2,y2=math.huge,math.huge,-math.huge,-math.huge
   for i,p in ipairs(points) do local a,b=points[(i-2)%#points+1],points[i%#points+1]
    area=area+p[1]*b[2]-b[1]*p[2]
    if (p[1]-a[1])*(b[2]-p[2])~=(p[2]-a[2])*(b[1]-p[1]) then reduced[#reduced+1]=p end
    x1,y1,x2,y2=math.min(x1,p[1]),math.min(y1,p[2]),math.max(x2,p[1]),math.max(y2,p[2])
   end
   if #reduced>=3 then out[#out+1]={points=reduced,hole=area<0,x1=x1,y1=y1,x2=x2,y2=y2} end
  end
 end
 return out
end
function C.key(x,y) return y*vertexStride+x end
-- Clip before NanoVG tessellation: offscreen curves must not consume a near-view budget.
function C.clip(p,x1,x2,y1,y2)
 if not C.intersects(p,x1,x2,y1,y2) then return false end
 if p.x1>=x1 and p.x2<=x2 and p.y1>=y1 and p.y2<=y2 then return p end
 local points=p.points
 for _,plane in ipairs({{1,x1,1},{1,x2,-1},{2,y1,1},{2,y2,-1}}) do
  local out={};local axis,value,sign=plane[1],plane[2],plane[3]
  local a=points[#points];if not a then return false end
  for _,b in ipairs(points) do
   local insideA=(a[axis]-value)*sign>=0;local insideB=(b[axis]-value)*sign>=0
   if insideA~=insideB then local t=(value-a[axis])/(b[axis]-a[axis]);out[#out+1]={a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t} end
   if insideB then out[#out+1]=b end;a=b
  end
  points=out
 end
 if #points<3 then return false end
 return {points=points,hole=p.hole,x1=x1,x2=x2,y1=y1,y2=y2}
end
function C.path(vg,p,ox,oy,scale,invert,x1,x2,y1,y2)
 if x1 then p=C.clip(p,x1,x2,y1,y2);if not p then return end end
 local a,b=p.points[#p.points],p.points[1]
 nvgMoveTo(vg,ox+(a[1]+b[1])*.5*scale,oy+(a[2]+b[2])*.5*scale)
 for i,q in ipairs(p.points) do local r=p.points[i%#p.points+1]
  nvgQuadTo(vg,ox+q[1]*scale,oy+q[2]*scale,ox+(q[1]+r[1])*.5*scale,oy+(q[2]+r[2])*.5*scale)
 end
 nvgClosePath(vg);nvgPathWinding(vg,(p.hole~=not not invert) and NVG_HOLE or NVG_SOLID)
end
function C.intersects(p,x1,x2,y1,y2) return p.x1<=x2 and p.x2>=x1 and p.y1<=y2 and p.y2>=y1 end
return C
