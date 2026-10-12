-- Isolated compartment clearance study. Production collision remains untouched.
-- A declared membrane is an aperture in its own vessel wall on both sides.
local Base=require('war.PassageCollisionStudy')
local M={prepare=Base.prepare,clearance=Base.clearance}
function M.allowed(model,context,net,x,y,lane)
 if lane and lane>0 then
  local edge=net.edges[lane];if not edge then return false end
  local radius=context.radius or 0
  if net.distance(lane,x,y)<=edge.width*.5-radius-.02 then return true end
  -- Conservative erosion of each existing aperture disk. This admits no new
  -- gates and never treats a projected crossing as a connection.
  for _,gate in ipairs(net.gates)do
   if gate.edge==lane and gate.radius>radius+.02 and
    (x-gate.x)^2+(y-gate.y)^2<=(gate.radius-radius-.02)^2 then return true end
  end
  return false
 end
 if not context.tissueEdges then return Base.allowed(model,context,net,x,y,lane)end
 local radius=context.radius or 0
 for id in pairs(net.sampleBuckets[math.floor(x/32)..':'..math.floor(y/32)] or {})do
  if context.tissueEdges[id] then
   local edge=net.edges[id]
   if net.distance(id,x,y,true)<edge.width*.5+1.4+radius+.02 then
    local gate=net.gateAt(id,x,y)
    if not gate or math.sqrt((x-gate.x)^2+(y-gate.y)^2)>gate.radius-radius-.02 then return false end
   end
  end
 end
 return not context.zone or Base.clearance(model,context.zone,x/2,(y-512)/2)>=radius*.5+.02
end
-- Optional tissueEdges is an explicit experimental layer contract, not inferred
-- from drawing alpha/depth. Omit it to preserve the former all-vessel wall rule.
function M.attachForTest(model,context,net,W)
 local original=net.options
 local function tissueSample(x,y)
  x,y=math.floor(x)+.5,math.floor(y)+.5
  local lanes,wall=0,false
  for id in pairs(net.sampleBuckets[math.floor(x/32)..':'..math.floor(y/32)]or{})do
   if context.tissueEdges[id]then
    local distance=net.distance(id,x,y,true)
    if net.inside(id,x,y,-.8,distance)then lanes=lanes+1
    elseif net.inside(id,x,y,1.4,distance)and not net.gateAt(id,x,y)then wall=true end
   end
  end
  return lanes,wall
 end
 net.options=function(x,y,tx,ty,lane)
  local candidates=original(x,y,tx,ty,lane)
  if context.tissueEdges then
   local filtered={}
   for _,nextLane in ipairs(candidates)do
    if (lane~=0 or nextLane==0 or context.tissueEdges[nextLane]) and
       (nextLane~=0 or lane==0 or context.tissueEdges[lane])then filtered[#filtered+1]=nextLane end
   end
   candidates=filtered
   if lane==0 then
    -- Ignore only explicitly excluded projected vessels; an actual same-layer
    -- lumen or sealed wall still excludes tissue, even if another tube overlaps.
    local count,wall=tissueSample(tx,ty)
    if count==0 and not wall then candidates[#candidates+1]=0 end
   end
  end
  local out,seen={},{};local radius=context.radius
  -- Both endpoints reserve half this actual sample step, so their clearance
  -- neighborhoods cover its entire sweep. Short frames need no diagonal maximum.
  context.radius=(radius or 0)+math.sqrt((tx-x)^2+(ty-y)^2)*.5
  local startAllowed=M.allowed(model,context,net,x,y,lane)
  for _,nextLane in ipairs(candidates)do
   if startAllowed and not seen[nextLane] and M.allowed(model,context,net,tx,ty,nextLane)then out[#out+1]=nextLane;seen[nextLane]=true end
  end
  context.radius=radius;return out
 end
 local originalLand=W and W.land
 if W then W.land=function(s,x,y)
  if originalLand(s,x,y)then return true end
  if not context.tissueEdges or not context.zone or W.terrain(s,x,y)~=17 then return false end
  local D=require('war.Data')
  if x<2 or y<2 or x>D.width(s)-1 or y>D.height(s)-1 or
     not require('war.Campaign').allowed(s,x+.5,y+.5)then return false end
  -- A terrain cell can be bypassed only if it is demonstrably a projected
  -- vessel wall. Never override bones, body borders, or arbitrary blocked tiles.
  if not net.sample(x+.5,y+.5).wall then return false end
  local count,wall=tissueSample(x+.5,y+.5)
  if count>0 or wall then return false end
  return M.allowed(model,context,net,x+.5,y+.5,0)
 end end
 return function()net.options=original;if W then W.land=originalLand end end
end
return M
