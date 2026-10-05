-- Render snapshots are separate from saved simulation state. One tick of latency
-- gives continuous movement without predicting through walls or hidden enemies.
local D,U=require("war.Data"),require("war.Util")
local M={trails=setmetatable({},{__mode="k"})}
function M.reset(g) g.motion={};g.motionState=g.state;g.flowTime=g.state.time;M.trails=setmetatable({},{__mode="k"}) end
function M.capture(g)
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
function M.position(g,e)
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
function M.time(g) return math.max(0,g.state.time-D.STEP+math.min(g.accumulator or 0,D.STEP)) end
function M.activity(g,e)
 local p=g.motion and g.motion[e.id]
 if not p then return 0,0 end
 local dx,dy=e.x-p.x,e.y-p.y
 local target=U.clamp(math.sqrt(dx*dx+dy*dy)/D.STEP/3.6,0,1)
 local angle=target>.001 and math.atan((dx+dy)*.5,dx-dy) or (p.angle or 0)
 local a=U.clamp((g.accumulator or 0)/D.STEP,0,1)
 local turn=math.atan(math.sin(angle-(p.angle or angle)),math.cos(angle-(p.angle or angle)))
 return (p.speed or target)+(target-(p.speed or target))*a,(p.angle or angle)+turn*a
end
return M
