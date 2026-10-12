-- Opt-in study adapter. The production entry never installs this module.
-- Reuse the real planner, commands and collision solver; keep all geometry fixed.
local M={}
function M.attachForTest(P,C,W)
 local originalClear,originalRequest,originalGo=P.clear,P.request,C.go
 ---@type table|false
 local active=false
 local stats={directRoutes=0,laneSelections=0,centerlineRoutes=0}
 P.request=function(s,e,x,y,forceFine)
  local permitted=not s.campaign or require('war.Campaign').allowed(s,x,y)
  -- Exact endpoints avoid forcing a legal short tissue move onto an illegal
  -- half-integer grid center. Long or obstructed routes retain the real A*.
  if permitted and not e.pathPending and not e.longRoute and (x-e.x)^2+(y-e.y)^2<=16*16 then
   local ok,lane=originalClear(s,e.x,e.y,x,y,e.faction,e.vesselLane)
   if ok then
    e.pathGoal={x=x,y=y};e.pathResolved={x=x,y=y,adjusted=false}
    e.path={{x=x,y=y,lane=lane}};e.pathIndex=1;e.pathPending=false;e.pathFailed=false
    stats.directRoutes=stats.directRoutes+1;return
   end
  end
  -- At a narrow vessel bend, the grid smoother's chord can lose clearance
  -- between samples. Reuse the graph's centerline and its existing junctions.
  if permitted and not e.pathPending and not e.longRoute and (e.vesselLane or 0)>0 and W.hasVessels(s) and (x-e.x)^2+(y-e.y)^2<=16*16 then
   local net=W.vessels(s)
   if net.initial(x,y)>0 then
    local route=net.route(e.x,e.y,x,y,e.vesselLane)
    local path={};local px,py,lane=e.x,e.y,e.vesselLane;local valid=route and #route<=128;local length=0
    if valid then for _,p in ipairs(route)do
     length=length+math.sqrt((p.x-px)^2+(p.y-py)^2)
     if length>64 then valid=false;break end
     if p.lane~=lane and originalClear(s,px,py,px,py,e.faction,lane,p.lane) then
      path[#path+1]={x=px,y=py,lane=p.lane};lane=p.lane
     end
     if not originalClear(s,px,py,p.x,p.y,e.faction,lane,p.lane) then valid=false;break end
     path[#path+1]={x=p.x,y=p.y,lane=p.lane};px,py,lane=p.x,p.y,p.lane
    end end
    if valid then
     e.pathGoal={x=x,y=y};e.pathResolved={x=x,y=y,adjusted=false};e.path=path
     e.pathIndex=1;e.pathPending=false;e.pathFailed=false;stats.centerlineRoutes=stats.centerlineRoutes+1;return
    end
   end
  end
  return originalRequest(s,e,x,y,forceFine)
 end
 P.clear=function(s,x,y,tx,ty,f,lane,desiredLane)
  local ok,chosen=originalClear(s,x,y,tx,ty,f,lane,desiredLane)
  if not ok or desiredLane~=nil or not active or not W.hasVessels(s) then return ok,chosen end
  ---@type table?
  local p=active.path[active.pathIndex or 1]
  if not p or (p.x-tx)^2+(p.y-ty)^2>16*16 then return ok,chosen end
  -- A planned segment can have several reachable lane states. Keeping the old
  -- lane greedily may miss the shared junction. Select a reachable state that
  -- can still finish this waypoint; never invent a connection or teleport.
  if originalClear(s,tx,ty,p.x,p.y,f,chosen,p.lane) then return ok,chosen end
  local net=W.vessels(s);local sample=net.sample(tx,ty)
  local candidates={0};for _,id in ipairs(sample.lanes)do candidates[#candidates+1]=id end
  if sample.gate then candidates[#candidates+1]=sample.gate.edge end
  if p.lane~=nil then candidates[#candidates+1]=p.lane end
  table.sort(candidates)
  for _,candidate in ipairs(candidates)do
   if candidate~=chosen and originalClear(s,x,y,tx,ty,f,lane,candidate) and originalClear(s,tx,ty,p.x,p.y,f,candidate,p.lane) then
    stats.laneSelections=stats.laneSelections+1;return true,candidate
   end
  end
  return ok,chosen
 end
 C.go=function(s,e,...)
  local previous=active;active=e
  local result=table.pack(pcall(originalGo,s,e,...));active=previous
  if not result[1]then error(result[2],0)end
  return table.unpack(result,2,result.n)
 end
 return function()P.clear=originalClear;P.request=originalRequest;C.go=originalGo end,stats
end
return M
