-- Circular membranes share one radius with the artwork. No RNG is used here.
local D,U,W,P=require('war.Data'),require('war.Util'),require('war.World'),require('war.Path')
local K={gap=.002,maxRadius=34/32}
function K.radius(e) return D.cellRadii[type(e)=='table' and e.kind or e] or 19/32 end
function K.units(s)
 local list={}
 for _,e in pairs(s.entities) do if e.category=='unit' and (e.hp==nil or e.hp>0) then list[#list+1]=e end end
 table.sort(list,function(a,b) return a.id<b.id end);return list
end
local function samePlane(s,a,b)
 if not s or not require('war.OrganBattlefield').enabled(s) then return true end
 local heart=require('war.HeartBattlefield').samePlane(s,a,b)
 if heart~=nil then return heart end
 if a.gastricTransit or b.gastricTransit then return true end
 return (a.vesselLane or 0)==(b.vesselLane or 0)
end
function K.free(list,e,x,y,s)
 for _,v in ipairs(list) do if v.id~=e.id and samePlane(s,e,v) then local r=K.radius(e)+K.radius(v)+K.gap
  if (x-v.x)^2+(y-v.y)^2<r*r-1e-10 then return false end
 end end;return true
end
function K.find(s,e,x,y,list,limit)
 list=list or K.units(s)
 local function valid(px,py)
  local G=require('war.OrganBattlefield')
  if G.enabled(s) then
   local lane=e.vesselLane or G.lane(s,e,px,py)
   return G.pointAllowed(s,e,px,py,lane) and K.free(list,e,px,py,s)
  end
  return (not s.tiles or W.walkable(s,math.floor(px),math.floor(py),e.faction)) and K.free(list,e,px,py)
 end
 if valid(x,y) then return x,y end
 for ring=1,math.floor((limit or 8)*2) do
  local r=ring*.5;local count=math.max(12,math.ceil(r*math.pi*4))
  for i=0,count-1 do local angle=i*math.pi*2/count;local px,py=x+math.cos(angle)*r,y+math.sin(angle)*r
   -- Relocation stays in the same vessel compartment as the requested spawn.
   local connected=not s.tiles or not W.hasVessels(s)
   if not connected then
    if e.vesselLane~=nil then connected=P.clear(s,x,y,px,py,e.faction,e.vesselLane,nil,e)
    else connected=W.lane(s,px,py)==W.lane(s,x,y) end
   end
   if valid(px,py) and connected then return px,py end
  end
 end
end
local function clear(s,e,x,y,tx,ty,lane,desiredLane)
 if not s.tiles then return true,lane end
 return P.clear(s,x,y,tx,ty,e.faction,lane,desiredLane,e)
end
-- Sweep the whole displacement, then slide along the contacted membrane.
local function sweep(s,e,tx,ty,desiredLane)
 local probe=setmetatable({gastricTransit=e.gastricTransit},{__index=e})
 local x,y,lane=e.x,e.y,e.vesselLane
 local candidates=W.neighbors(s,x,y,K.radius(e)+K.maxRadius+math.sqrt((tx-x)^2+(ty-y)^2)+1)
 table.sort(candidates,function(a,b) return a.id<b.id end)
 local dx,dy=tx-x,ty-y
 for _=1,4 do
  local a=dx*dx+dy*dy;if a<1e-12 then break end
  local hit,t=nil,1
  for _,v in ipairs(candidates) do if v.id~=e.id and v.category=='unit' and U.alive(v) and samePlane(s,probe,v) then
   local ox,oy=x-v.x,y-v.y;local r=K.radius(e)+K.radius(v)+K.gap
   local dot=ox*dx+oy*dy;local c=ox*ox+oy*oy-r*r
   if dot<0 then local disc=dot*dot-a*c
    if disc>=0 then local contact=math.max(0,(-dot-math.sqrt(disc))/a)
     if contact<=t then hit,t=v,contact end
    end
   end
  end end
  local safe=hit and math.max(0,t-.00001/math.sqrt(a)) or 1
  local nx,ny=x+dx*safe,y+dy*safe;local ok,nextLane,transit=clear(s,probe,x,y,nx,ny,lane,desiredLane)
  if not ok then break end
  x,y,lane=nx,ny,nextLane;probe.gastricTransit=transit or false
  if not hit then break end
  local hx,hy=x-hit.x,y-hit.y;local length=math.sqrt(hx*hx+hy*hy)
  if length<1e-8 then break end
  hx,hy=hx/length,hy/length
  dx,dy=dx*(1-safe),dy*(1-safe);local inward=math.min(0,dx*hx+dy*hy)
  local rx,ry=dx-hx*inward,dy-hy*inward
  if rx*rx+ry*ry<.02*(dx*dx+dy*dy) then
   local slide=math.sqrt(dx*dx+dy*dy)*.65;rx,ry=-hy*slide,hx*slide
  end
  dx,dy=rx,ry
 end
 return x,y,lane,probe.gastricTransit or nil
end

function K.namedGatePoint(s,e,p)
 if not p then return false end
 if p.gateId or p.gate or p.transition then return true end
 local O=require('war.OrganBattlefield');local owner=O.organAt(s,e,e.x,e.y)
 if not owner then return false end
 local profile=O.radius(e)<=.21875 and 'scout'or'siege'
 for _,gate in ipairs(O.organ(owner).gateContracts[profile]or{})do
  for _,source in ipairs({gate.tissueAnchorSource,gate.pipeAnchorSource})do
   if source and(p.x-source[1]*2)^2+(p.y-source[2]*2-512)^2<=1e-8 then return true end
  end
 end
 return false
end


-- Private diagnostic prototype: ordinary movement must also clear idle cells.
-- Only temporary path points change; player orders, goals, and idle units stay.
function K.idleDetour(s,e,target,skipBlockedWaypoint)
 if e.gastricTransit or e.vesselLane~=0 or not target or target.lane~=0 then return nil end
 local O=require('war.OrganBattlefield')
 if not O.enabled(s) then return nil end
 local owner=O.organAt(s,e,e.x,e.y)
 if not owner or owner=='heart' or owner=='lung_r' or owner=='lung_l' then return nil end
 if O.organAt(s,e,target.x,target.y)~=owner then return nil end
 local function distance(px,py,x,y,tx,ty)
  local dx,dy=tx-x,ty-y;local ll=dx*dx+dy*dy
  local t=ll>0 and math.max(0,math.min(1,((px-x)*dx+(py-y)*dy)/ll))or 0
  return math.sqrt((px-x-dx*t)^2+(py-y-dy*t)^2)
 end
 local blockers,units={},K.units(s)
 for _,v in ipairs(units)do
  if v.id~=e.id and samePlane(s,e,v) and #(v.orders or{})==0 then
   local radius=K.radius(e)+K.radius(v)+K.gap
   if distance(v.x,v.y,e.x,e.y,target.x,target.y)<radius+.02 then
    blockers[#blockers+1]={unit=v,radius=radius,
     distance=(v.x-e.x)^2+(v.y-e.y)^2}
   end
  end
 end
 table.sort(blockers,function(a,b)
  if a.distance==b.distance then return a.unit.id<b.unit.id end
  return a.distance<b.distance
 end)

 if #blockers==0 and not skipBlockedWaypoint then return nil end
 if #blockers>4 then return nil end
 local known={};for _,b in ipairs(blockers)do known[b.unit.id]=true end
 -- An idle cell beside the requested segment can obstruct the tangential
 -- route. Include the complete nearby connected set of expanded membranes.
 local index=1
 while index<=#blockers do
  local current=blockers[index]
  for _,v in ipairs(units)do
   if v.id~=e.id and not known[v.id] and samePlane(s,e,v) and #(v.orders or{})==0 then
    local radius=K.radius(e)+K.radius(v)+K.gap
    if (v.x-current.unit.x)^2+(v.y-current.unit.y)^2<(radius+current.radius+.15)^2 then
     known[v.id]=true;blockers[#blockers+1]={unit=v,radius=radius,
      distance=(v.x-e.x)^2+(v.y-e.y)^2}
     if #blockers>4 then return nil end
    end
   end
  end
  index=index+1
 end

 local nodes={{x=e.x,y=e.y},{x=target.x,y=target.y}}
 for _,b in ipairs(blockers)do
  local radius=(b.radius+.035)/math.cos(math.pi/16)
  for i=0,15 do
   local angle=i*math.pi/8
   local x,y=b.unit.x+math.cos(angle)*radius,b.unit.y+math.sin(angle)*radius
   if O.organAt(s,e,x,y)==owner and O.pointAllowed(s,e,x,y,e.vesselLane) and K.free(units,e,x,y,s)then
    nodes[#nodes+1]={x=x,y=y,lane=e.vesselLane}
   end
  end
 end
 local function edge(a,b)
  for _,v in ipairs(units)do if v.id~=e.id and samePlane(s,e,v)then
   if distance(v.x,v.y,a.x,a.y,b.x,b.y)<K.radius(e)+K.radius(v)+K.gap then return false end
  end end
  -- Full swept disk against the real authored walls and exact current plane.
  return P.clear(s,a.x,a.y,b.x,b.y,e.faction,e.vesselLane,e.vesselLane,e)
 end
 local costs,previous,visited={[1]=0},{},{}
 for _=1,#nodes do
  local at,best=nil,math.huge
  for i,c in pairs(costs)do if not visited[i] and(c<best or c==best and(not at or i<at))then at,best=i,c end end
  if not at then break end
  if at==2 then
   local backwards={};local index=previous[2]
   while index and index~=1 do backwards[#backwards+1]=nodes[index];index=previous[index]end
   local path={};for i=#backwards,1,-1 do path[#path+1]=backwards[i]end
   return path
  end
  visited[at]=true
  for i,node in ipairs(nodes)do if not visited[i] and i~=at then
   local a=nodes[at];local c=best+math.sqrt((a.x-node.x)^2+(a.y-node.y)^2)
   if c<(costs[i] or math.huge) and edge(a,node)then costs[i]=c;previous[i]=at end
  end end
 end
 return nil
end

function K.move(s,e,tx,ty,desiredLane)
 local x,y,lane,transit=sweep(s,e,tx,ty,desiredLane)
 local dx,dy=tx-e.x,ty-e.y;local length=math.sqrt(dx*dx+dy*dy)
 local distance=math.sqrt((x-e.x)^2+(y-e.y)^2)
 if length<=1 and distance<length*.15 then
  local best=distance
  for _,angle in ipairs({math.pi/3,-math.pi/3,math.pi/2,-math.pi/2,math.pi*2/3,-math.pi*2/3}) do
   local c,ss=math.cos(angle),math.sin(angle)
   local ax,ay,al,at=sweep(s,e,e.x+dx*c-dy*ss,e.y+dx*ss+dy*c,desiredLane)
   local moved=math.sqrt((ax-e.x)^2+(ay-e.y)^2)
   local score=moved+((ax-e.x)*dx+(ay-e.y)*dy)/math.max(length,1e-8)*.15
   if score>best then best=score;x,y,lane,transit=ax,ay,al,at end
  end
 end
 return x,y,lane,transit
end
local function pairsNear(list,visit)
 local bins={}
 for _,e in ipairs(list) do
  local bx,by=math.floor(e.x/3),math.floor(e.y/3)
  for yy=by-1,by+1 do for xx=bx-1,bx+1 do
   for _,v in ipairs(bins[xx..':'..yy] or {}) do visit(e,v) end
  end end
  local key=bx..':'..by;bins[key]=bins[key] or {};bins[key][#bins[key]+1]=e
 end
end
-- Repair legacy saves and constrain interpolation without touching simulation RNG.
function K.resolve(s,list)
 list=list or K.units(s)
 for _=1,24 do
  local changed=false
  pairsNear(list,function(a,b)
   if not samePlane(s,a,b) then return end
   local dx,dy=a.x-b.x,a.y-b.y;local d=math.sqrt(dx*dx+dy*dy);local r=K.radius(a)+K.radius(b)+K.gap
   if d<r-.000001 then
    changed=true
    if d<1e-8 then local angle=(a.id*17+b.id*31)*.618;dx,dy=math.cos(angle),math.sin(angle) else dx,dy=dx/d,dy/d end
    local push=(r-d)*.5+.000001
    local okA,laneA,transitA=clear(s,a,a.x,a.y,a.x+dx*push,a.y+dy*push,a.vesselLane)
    local okB,laneB,transitB=clear(s,b,b.x,b.y,b.x-dx*push,b.y-dy*push,b.vesselLane)
    if okA then a.x,a.y,a.vesselLane,a.gastricTransit=a.x+dx*push,a.y+dy*push,laneA,transitA end
    if okB then b.x,b.y,b.vesselLane,b.gastricTransit=b.x-dx*push,b.y-dy*push,laneB,transitB end
   end
  end)
  if not changed then return end
 end
 -- Only pathological coincident saves/crowds need placement after relaxation.
 local placed={}
 for _,e in ipairs(list) do
  if not K.free(placed,e,e.x,e.y,s) then
   local x,y=K.find(s,e,e.x,e.y,placed,32)
   if x then
    local lane=e.vesselLane
    if s.tiles then local ok,nextLane=P.clear(s,e.x,e.y,x,y,e.faction,lane,nil,e);if ok then lane=nextLane end end
    e.x,e.y,e.vesselLane=x,y,lane
   end
  end
  placed[#placed+1]=e
 end
end
return K
