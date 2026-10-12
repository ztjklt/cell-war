-- Optional isolated repair for exact endpoints which do not coincide with the
-- planner's half-integer lattice. The entity physically walks each connector.
local M={}
function M.attachForTest(P,C,W)
 local request=P.request
 local stats={startConnectors=0,goalConnectors=0,unresolvedStarts=0,unresolvedGoals=0}
 local function nearby(s,e,x,y,lane,fromExact)
  local best,bestDistance=nil,math.huge
  for dy=-3,3 do for dx=-3,3 do
   local cx,cy=math.floor(x)+dx+.5,math.floor(y)+dy+.5
   local distance=(cx-x)^2+(cy-y)^2
   if distance<bestDistance and W.walkable(s,math.floor(cx),math.floor(cy),e.faction)then
    local legal=P.clear(s,cx,cy,cx,cy,e.faction,lane,lane)
    if legal then
     local connected=fromExact and P.clear(s,x,y,cx,cy,e.faction,lane,lane)or
      not fromExact and P.clear(s,cx,cy,x,y,e.faction,lane,lane)
     if connected then best={x=cx,y=cy,lane=lane};bestDistance=distance end
    end
   end
  end end
  return best
 end
 P.request=function(s,e,x,y,forceFine)
  request(s,e,x,y,forceFine)
  if not e.pathPending then return end
  local order=e.orders and e.orders[1];local desired=order and order.vesselLane
  if desired==nil or not order.x or (order.x-x)^2+(order.y-y)^2>1e-6 then return end
  local index,job=nil,nil
  for i,j in ipairs(P.jobs)do if j.id==e.id and j.token==e.orderToken and j.phase=='fine'and not j.routeIndex then index,job=i,j;break end end
  if not job or job.visits~=0 then return end
  local lane=e.vesselLane or 0
  if not P.clear(s,e.x,e.y,job.sx+.5,job.sy+.5,e.faction,lane,lane)then
   local prefix=nearby(s,e,e.x,e.y,lane,true)
   if prefix then
    table.remove(P.jobs,index)
    e.pathPending=false;e.pathFailed=false;e.path={prefix};e.pathIndex=1
    e.pathGoal={x=x,y=y};e.pathResolved={x=x,y=y,adjusted=false};e.longRoute=nil
    stats.startConnectors=stats.startConnectors+1;return
   end
   stats.unresolvedStarts=stats.unresolvedStarts+1
  end
  if not P.clear(s,job.gx+.5,job.gy+.5,x,y,e.faction,desired,desired)then
   local target=nearby(s,e,x,y,desired,false)
   if target then
    job.gx,job.gy=math.floor(target.x),math.floor(target.y);job.goalLane=desired
    -- The pending job has not yet expanded; only its root heuristic exists.
    for _,n in ipairs(job.open)do n.f=n.g+math.sqrt((n.x-job.gx)^2+(n.y-job.gy)^2)end
    e.pathResolved={x=x,y=y,adjusted=false}
    stats.goalConnectors=stats.goalConnectors+1
    -- When this exact safe lattice waypoint is reached, the normal request
    -- installs the final swept segment to the unchanged order destination.
   else stats.unresolvedGoals=stats.unresolvedGoals+1 end
  end
 end
 return function()P.request=request end,stats
end
return M
