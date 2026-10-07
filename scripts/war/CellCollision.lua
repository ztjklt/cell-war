-- Circular membranes share one radius with the artwork. No RNG is used here.
local D,U,W,P=require('war.Data'),require('war.Util'),require('war.World'),require('war.Path')
local K={gap=.002,maxRadius=34/32}
function K.radius(e) return D.cellRadii[type(e)=='table' and e.kind or e] or 19/32 end
function K.units(s)
 local list={}
 for _,e in pairs(s.entities) do if e.category=='unit' and (e.hp==nil or e.hp>0) then list[#list+1]=e end end
 table.sort(list,function(a,b) return a.id<b.id end);return list
end
function K.free(list,e,x,y)
 for _,v in ipairs(list) do if v.id~=e.id then local r=K.radius(e)+K.radius(v)+K.gap
  if (x-v.x)^2+(y-v.y)^2<r*r-1e-10 then return false end
 end end;return true
end
function K.find(s,e,x,y,list,limit)
 list=list or K.units(s)
 local function valid(px,py)
  return (not s.tiles or W.walkable(s,math.floor(px),math.floor(py),e.faction)) and K.free(list,e,px,py)
 end
 if valid(x,y) then return x,y end
 for ring=1,math.floor((limit or 8)*2) do
  local r=ring*.5;local count=math.max(12,math.ceil(r*math.pi*4))
  for i=0,count-1 do local angle=i*math.pi*2/count;local px,py=x+math.cos(angle)*r,y+math.sin(angle)*r
   -- Relocation stays in the same vessel compartment as the requested spawn.
   local connected=not s.tiles or not W.hasVessels(s)
   if not connected then
    if e.vesselLane~=nil then connected=P.clear(s,x,y,px,py,e.faction,e.vesselLane)
    else connected=W.lane(s,px,py)==W.lane(s,x,y) end
   end
   if valid(px,py) and connected then return px,py end
  end
 end
end
local function clear(s,e,x,y,tx,ty,lane)
 if not s.tiles then return true,lane end
 return P.clear(s,x,y,tx,ty,e.faction,lane)
end
-- Sweep the whole displacement, then slide along the contacted membrane.
local function sweep(s,e,tx,ty)
 local x,y,lane=e.x,e.y,e.vesselLane
 local candidates=W.neighbors(s,x,y,K.radius(e)+K.maxRadius+math.sqrt((tx-x)^2+(ty-y)^2)+1)
 table.sort(candidates,function(a,b) return a.id<b.id end)
 local dx,dy=tx-x,ty-y
 for _=1,4 do
  local a=dx*dx+dy*dy;if a<1e-12 then break end
  local hit,t=nil,1
  for _,v in ipairs(candidates) do if v.id~=e.id and v.category=='unit' and U.alive(v) then
   local ox,oy=x-v.x,y-v.y;local r=K.radius(e)+K.radius(v)+K.gap
   local dot=ox*dx+oy*dy;local c=ox*ox+oy*oy-r*r
   if dot<0 then local disc=dot*dot-a*c
    if disc>=0 then local contact=math.max(0,(-dot-math.sqrt(disc))/a)
     if contact<=t then hit,t=v,contact end
    end
   end
  end end
  local safe=hit and math.max(0,t-.00001/math.sqrt(a)) or 1
  local nx,ny=x+dx*safe,y+dy*safe;local ok,nextLane=clear(s,e,x,y,nx,ny,lane)
  if not ok then break end
  x,y,lane=nx,ny,nextLane
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
 return x,y,lane
end
function K.move(s,e,tx,ty)
 local x,y,lane=sweep(s,e,tx,ty)
 local dx,dy=tx-e.x,ty-e.y;local length=math.sqrt(dx*dx+dy*dy)
 local distance=math.sqrt((x-e.x)^2+(y-e.y)^2)
 if length<=1 and distance<length*.15 then
  local best=distance
  for _,angle in ipairs({math.pi/3,-math.pi/3,math.pi/2,-math.pi/2,math.pi*2/3,-math.pi*2/3}) do
   local c,ss=math.cos(angle),math.sin(angle)
   local ax,ay,al=sweep(s,e,e.x+dx*c-dy*ss,e.y+dx*ss+dy*c)
   local moved=math.sqrt((ax-e.x)^2+(ay-e.y)^2)
   local score=moved+((ax-e.x)*dx+(ay-e.y)*dy)/math.max(length,1e-8)*.15
   if score>best then best=score;x,y,lane=ax,ay,al end
  end
 end
 return x,y,lane
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
   local dx,dy=a.x-b.x,a.y-b.y;local d=math.sqrt(dx*dx+dy*dy);local r=K.radius(a)+K.radius(b)+K.gap
   if d<r-.000001 then
    changed=true
    if d<1e-8 then local angle=(a.id*17+b.id*31)*.618;dx,dy=math.cos(angle),math.sin(angle) else dx,dy=dx/d,dy/d end
    local push=(r-d)*.5+.000001
    local okA,laneA=clear(s,a,a.x,a.y,a.x+dx*push,a.y+dy*push,a.vesselLane)
    local okB,laneB=clear(s,b,b.x,b.y,b.x-dx*push,b.y-dy*push,b.vesselLane)
    if okA then a.x,a.y,a.vesselLane=a.x+dx*push,a.y+dy*push,laneA end
    if okB then b.x,b.y,b.vesselLane=b.x-dx*push,b.y-dy*push,laneB end
   end
  end)
  if not changed then return end
 end
 -- Only pathological coincident saves/crowds need placement after relaxation.
 local placed={}
 for _,e in ipairs(list) do
  if not K.free(placed,e,e.x,e.y) then
   local x,y=K.find(s,e,e.x,e.y,placed,32)
   if x then
    local lane=e.vesselLane
    if s.tiles then local ok,nextLane=P.clear(s,e.x,e.y,x,y,e.faction,lane);if ok then lane=nextLane end end
    e.x,e.y,e.vesselLane=x,y,lane
   end
  end
  placed[#placed+1]=e
 end
end
return K
