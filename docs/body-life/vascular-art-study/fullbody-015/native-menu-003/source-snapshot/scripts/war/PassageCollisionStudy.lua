-- Isolated acceptance helper only. Never required by the game entry or save code.
-- Radius is a world-space radius; source pixels are half a world unit.
local M={}
local function distance(x,y,a,b)
 local dx,dy=b[1]-a[1],b[2]-a[2];if dx*dx+dy*dy<1e-16 then return math.sqrt((x-a[1])^2+(y-a[2])^2)end;local t=math.max(0,math.min(1,((x-a[1])*dx+(y-a[2])*dy)/(dx*dx+dy*dy)))
 return math.sqrt((x-a[1]-t*dx)^2+(y-a[2]-t*dy)^2)
end
local function poly(poly,x,y)
 local inside=false;local nearest=math.huge;local a=poly[#poly]
 for _,b in ipairs(poly)do
  if (a[2]>y)~=(b[2]>y) and x<(b[1]-a[1])*(y-a[2])/(b[2]-a[2])+a[1] then inside=not inside end
  if a[1]~=b[1] or a[2]~=b[2] then nearest=math.min(nearest,distance(x,y,a,b))end;a=b
 end
 return inside,nearest
end
function M.prepare(data)
 local out={zones={},edges={},food=data.foodUnion}
 for _,e in ipairs(data.edges)do out.edges[e.id]=e end
 for _,z in ipairs(data.zones)do out.zones[z.id]=z end
 return out
end
-- Returns physical surface clearance in source pixels. No visual alpha or zoom is consulted.
function M.clearance(model,zoneId,x,y)
 local z=model.zones[zoneId];if not z then return -math.huge end
 local inside=false;local margin=math.huge
 for _,r in ipairs(z.outlines)do local hit,d=poly(r.points,x,y);if hit then inside=not inside end;margin=math.min(margin,d)end
 if not inside then return -margin end
 for _,id in ipairs(z.forbiddenEdges)do local e=model.edges[id]
  for i=2,#e.points do margin=math.min(margin,distance(x,y,e.points[i-1],e.points[i])-e.width*.5)end
 end
 if zoneId=='stomach' then for _,ring in ipairs(model.food)do local hit,d=poly(ring,x,y);margin=math.min(margin,hit and -d or d)end end
 return margin
end
function M.allowed(model,context,net,x,y,lane)
 local radius=context.radius or 0
 if lane and lane>0 then
  -- Blood is an existing independent compartment, never a food/air/urine lane.
  local edge=net.edges[lane];if not edge then return false end
  return net.distance(lane,x,y)<=edge.width*.5-radius-0.02
 end
 if not context.zone then return true end
 -- Tissue disks must also clear existing vessel walls. Preserve only real gate
 -- apertures, and erode their opening by this same radius.
 local bucket=math.floor(x/32)..':'..math.floor(y/32)
 for id in pairs(net.sampleBuckets[bucket] or {})do
  local edge=net.edges[id]
  if net.distance(id,x,y,true)<edge.width*.5+1.4+radius+.02 then
   local gate=net.gateAt(id,x,y)
   if not gate or math.sqrt((x-gate.x)^2+(y-gate.y)^2)>gate.radius-radius then return false end
  end
 end
 return M.clearance(model,context.zone,x/2,(y-512)/2)>=radius*.5+.02
end
function M.attachForTest(model,context,net)
 local original=net.options
 net.options=function(x,y,tx,ty,lane)
  local out={};for _,nextLane in ipairs(original(x,y,tx,ty,lane))do
   -- Path.trace samples <=sqrt(2)/4 world apart. Reserve half that diagonal spacing in the
   -- clearance test to cover the disk sweep between sample points conservatively.
   local radius=context.radius;context.radius=(radius or 0)+math.sqrt(2)/8
   local okay=M.allowed(model,context,net,tx,ty,nextLane)
   context.radius=radius
   if okay then out[#out+1]=nextLane end
  end;return out
 end
 return function()net.options=original end
end
return M
