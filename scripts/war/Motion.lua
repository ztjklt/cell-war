-- Render snapshots are separate from saved simulation state. One tick of latency
-- gives continuous movement without predicting through walls or hidden enemies.
local D,U=require("war.Data"),require("war.Util")
local M={trails=setmetatable({},{__mode="k"})}
function M.reset(g) g.contactKey=nil;g.motion={};g.motionState=g.state;g.flowTime=g.state.time;M.trails=setmetatable({},{__mode="k"}) end
function M.capture(g)
 g.contactKey=nil
 if g.motionState~=g.state then M.reset(g) end
 for id in pairs(g.motion) do if not g.state.entities[id] then g.motion[id]=nil end end
 for id,e in pairs(g.state.entities) do if e.category=="unit" then
  local speed,angle=M.activity(g,e)
  local p={x=e.x,y=e.y,speed=speed,angle=angle,trail={{x=e.x,y=e.y}},distance=0}
  g.motion[id]=p;M.trails[e]=p
 end end
end
function M.record(e)
 local p=M.trails[e];if not p then return end
 local last=p.trail[#p.trail];local d=math.sqrt((e.x-last.x)^2+(e.y-last.y)^2)
 if d>.000001 then p.trail[#p.trail+1]={x=e.x,y=e.y};p.distance=p.distance+d end
end
local function interpolated(g,e)
 local p=g.motion and g.motionState==g.state and g.motion[e.id]
 if e.category~="unit" or not p or (e.x-p.x)^2+(e.y-p.y)^2>9 then return e.x,e.y end
 local a=U.clamp((g.accumulator or 0)/D.STEP,0,1)
 -- Follow every swept movement segment when a tick crosses a tight corner.
 if p.distance>0 then
  local endPoint=p.trail[#p.trail]
  if math.abs(endPoint.x-e.x)+math.abs(endPoint.y-e.y)<.0001 then
   local remaining=p.distance*a
   for i=2,#p.trail do local from,to=p.trail[i-1],p.trail[i];local d=math.sqrt((to.x-from.x)^2+(to.y-from.y)^2)
    if remaining<=d then local t=remaining/d;return from.x+(to.x-from.x)*t,from.y+(to.y-from.y)*t end
    remaining=remaining-d
   end
   return e.x,e.y
  end
 end
 return p.x+(e.x-p.x)*a,p.y+(e.y-p.y)*a
end
function M.position(g,e)
 if e.category~="unit" then return e.x,e.y end
 local key=tostring(g.state)..":"..tostring(g.state.tick)..":"..tostring(g.accumulator)..":"..tostring(g.motion)
 if g.contactKey~=key then
  local K=require("war.CellCollision");local list={};g.contactPositions={}
  for _,u in ipairs(K.units(g.state)) do local x,y=interpolated(g,u)
   local point={id=u.id,kind=u.kind,x=x,y=y,faction=u.faction,vesselLane=u.vesselLane};list[#list+1]=point;g.contactPositions[u.id]=point
  end
  K.resolve(g.state,list);g.contactKey=key
 end
 local p=g.contactPositions[e.id];return p and p.x or e.x,p and p.y or e.y
end
function M.time(g) return math.max(0,g.state.time-D.STEP+math.min(g.accumulator or 0,D.STEP)) end
function M.activity(g,e)
 local p=g.motion and g.motion[e.id]
 if not p then return 0,0 end
 local dx,dy=e.x-p.x,e.y-p.y
 local target=U.clamp(math.sqrt(dx*dx+dy*dy)/D.STEP/3.6,0,1)
 local angle=target>.001 and math.atan(dy,dx) or (p.angle or 0)
 local a=U.clamp((g.accumulator or 0)/D.STEP,0,1)
 local turn=math.atan(math.sin(angle-(p.angle or angle)),math.cos(angle-(p.angle or angle)))
 turn=U.clamp(turn,-1.5*D.STEP,1.5*D.STEP)
 return (p.speed or target)+(target-(p.speed or target))*a,(p.angle or angle)+turn*a
end
return M
