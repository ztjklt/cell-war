-- Exact source-coordinate boundary queries. Prepared BVHs accelerate the same
-- segment distances and even/odd polygon rule; no rasterization or simplification.
local G={}
local function segment(a,b,r,id)
 local dx,dy=b[1]-a[1],b[2]-a[2]
 return {ax=a[1],ay=a[2],bx=b[1],by=b[2],dx=dx,dy=dy,length2=dx*dx+dy*dy,
  minX=math.min(a[1],b[1]),maxX=math.max(a[1],b[1]),minY=math.min(a[2],b[2]),maxY=math.max(a[2],b[2]),radius=r or 0,id=id}
end
local function tree(items)
 if #items==0 then return false end
 local n={minX=math.huge,minY=math.huge,maxX=-math.huge,maxY=-math.huge,radius=0}
 for _,s in ipairs(items)do n.minX=math.min(n.minX,s.minX);n.maxX=math.max(n.maxX,s.maxX);n.minY=math.min(n.minY,s.minY);n.maxY=math.max(n.maxY,s.maxY);n.radius=math.max(n.radius,s.radius)end
 if #items<=8 then n.items=items;return n end
 local x=n.maxX-n.minX>=n.maxY-n.minY
 table.sort(items,function(a,b)local aa=x and a.minX+a.maxX or a.minY+a.maxY;local bb=x and b.minX+b.maxX or b.minY+b.maxY;if aa==bb then return a.id<b.id end;return aa<bb end)
 local left,right={},{};local middle=math.floor(#items/2)
 for i,s in ipairs(items)do if i<=middle then left[#left+1]=s else right[#right+1]=s end end
 n.left=tree(left);n.right=tree(right);return n
end
local function lower(n,x,y)
 local dx=math.max(n.minX-x,0,x-n.maxX);local dy=math.max(n.minY-y,0,y-n.maxY)
 return math.sqrt(dx*dx+dy*dy)-n.radius
end
local function distance(s,x,y)
 local t=s.length2>1e-16 and math.max(0,math.min(1,((x-s.ax)*s.dx+(y-s.ay)*s.dy)/s.length2)) or 0
 local dx,dy=x-s.ax-t*s.dx,y-s.ay-t*s.dy;return math.sqrt(dx*dx+dy*dy)-s.radius
end
local function nearest(n,x,y,best)
 if not n or lower(n,x,y)>best then return best end
 if n.items then for _,s in ipairs(n.items)do best=math.min(best,distance(s,x,y))end;return best end
 local a,b=n.left,n.right;if lower(a,x,y)>lower(b,x,y)then a,b=b,a end
 best=nearest(a,x,y,best);return nearest(b,x,y,best)
end
local function parity(n,x,y)
 if not n or y<n.minY or y>=n.maxY or x>=n.maxX then return false end
 local inside=false
 if n.items then
  for _,s in ipairs(n.items)do if (s.ay>y)~=(s.by>y) and x<s.dx*(y-s.ay)/s.dy+s.ax then inside=not inside end end
 else inside=parity(n.left,x,y)~=parity(n.right,x,y)end
 return inside
end
local function closed(points,items)
 local a=points[#points]
 for _,b in ipairs(points)do
  if a[1]~=b[1] or a[2]~=b[2] then items[#items+1]=segment(a,b,0,#items+1)end;a=b
 end
end
function G.prepare(model)
 local out={zones={},source=model}
 for id,z in pairs(model.zones)do
  local boundary,obstacles,food={},{},{}
  for _,r in ipairs(z.outlines)do closed(r.points,boundary)end
  for _,eid in ipairs(z.forbiddenEdges or {})do local e=assert(model.edges[eid],eid)
   for i=2,#e.points do obstacles[#obstacles+1]=segment(e.points[i-1],e.points[i],e.width*.5,#obstacles+1)end
  end
  if id=='stomach' then for _,ring in ipairs(model.food or {})do local items={};closed(ring,items);food[#food+1]=tree(items)end end
  out.zones[id]={boundary=tree(boundary),obstacles=tree(obstacles),food=food}
 end
 return out
end
function G.clearance(prepared,zone,x,y)
 local z=prepared.zones[zone];if not z then return -math.huge end
 local d=nearest(z.boundary,x,y,math.huge)
 if not parity(z.boundary,x,y)then return -d end
 d=nearest(z.obstacles,x,y,d)
 for _,ring in ipairs(z.food)do local f=nearest(ring,x,y,math.huge);if parity(ring,x,y)then f=-f end;d=math.min(d,f)end
 return d
end
-- Compatibility adapter for isolated acceptance and integration. Model geometry
-- must remain immutable while installed; other models retain their original query.
function G.attachForTest(Base,Collision,model)
 local prepared=G.prepare(model);local oldBase,oldCollision=Base.clearance,Collision.clearance
 local function query(m,zone,x,y)if m==model then return G.clearance(prepared,zone,x,y)end;return oldBase(m,zone,x,y)end
 Base.clearance=query;Collision.clearance=query
 return function()Base.clearance=oldBase;Collision.clearance=oldCollision end,prepared
end
return G
