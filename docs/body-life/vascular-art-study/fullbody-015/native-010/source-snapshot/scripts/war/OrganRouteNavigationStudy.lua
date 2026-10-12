-- Isolated explicit-compartment navigation study; never installed by production.
-- All waypoints use unchanged vessel centerlines and are swept by real Path.clear.
local M={}
local function centerRoute(net,x,y,tx,ty,lane,goalLane)
 local function connector(id,px,py)
  local _,cx,cy,index,t=net.distance(id,px,py)
  return {edge=id,x=cx,y=cy,index=index,t=t}
 end
 local a,b=connector(lane,x,y),connector(goalLane,tx,ty)
 local function portion(c,toEnd)
  local edge=net.edges[c.edge];local out={{x=c.x,y=c.y,lane=c.edge}};local length=0
  if toEnd then for i=c.index+1,#edge.points do out[#out+1]={x=edge.points[i][1],y=edge.points[i][2],lane=c.edge}end
  else for i=c.index,1,-1 do out[#out+1]={x=edge.points[i][1],y=edge.points[i][2],lane=c.edge}end end
  for i=2,#out do length=length+math.sqrt((out[i].x-out[i-1].x)^2+(out[i].y-out[i-1].y)^2)end
  return out,length
 end
 local ea,eb=net.edges[lane],net.edges[goalLane]
 if lane==goalLane then
  local out={{x=a.x,y=a.y,lane=lane}}
  local sa=ea.arc[a.index]+a.t*(ea.arc[a.index+1]-ea.arc[a.index])
  local sb=ea.arc[b.index]+b.t*(ea.arc[b.index+1]-ea.arc[b.index])
  if sb>=sa then for i=a.index+1,b.index do out[#out+1]={x=ea.points[i][1],y=ea.points[i][2],lane=lane}end
  else for i=a.index,b.index+1,-1 do out[#out+1]={x=ea.points[i][1],y=ea.points[i][2],lane=lane}end end
  out[#out+1]={x=b.x,y=b.y,lane=lane};out[#out+1]={x=tx,y=ty,lane=lane};return out
 end
 local ap,al=portion(a,false);local aq,ar=portion(a,true)
 local dist={[ea.a]=al,[ea.b]=ar};local prev={};local open={[ea.a]=true,[ea.b]=true}
 while next(open)do
  local current,dd=nil,math.huge
  for id in pairs(open)do if dist[id]<dd then current,dd=id,dist[id]end end
  open[current]=nil
  for _,id in ipairs(net.nodes[current].edges)do
   local edge=net.edges[id];local other=edge.a==current and edge.b or edge.a;local d=dd+edge.length
   if not dist[other] or d<dist[other] then dist[other]=d;prev[other]={from=current,edge=id};open[other]=true end
  end
 end
 local bp,bl=portion(b,false);local bq,br=portion(b,true)
 local finish=(dist[eb.a]or math.huge)+bl<(dist[eb.b]or math.huge)+br and eb.a or eb.b
 if not dist[finish]then return false end
 local chain={};local start=finish
 while prev[start]do chain[#chain+1]={from=prev[start].from,to=start,edge=prev[start].edge};start=prev[start].from end
 local out={};for _,p in ipairs(start==ea.a and ap or aq)do out[#out+1]=p end
 for i=#chain,1,-1 do
  local c=chain[i];local edge=net.edges[c.edge]
  if c.from==edge.a then for j=1,#edge.points do out[#out+1]={x=edge.points[j][1],y=edge.points[j][2],lane=c.edge}end
  else for j=#edge.points,1,-1 do out[#out+1]={x=edge.points[j][1],y=edge.points[j][2],lane=c.edge}end end
 end
 local tail=finish==eb.a and bp or bq
 for i=#tail,1,-1 do out[#out+1]=tail[i]end
 out[#out+1]={x=tx,y=ty,lane=goalLane};return out
end
function M.attachForTest(P,C,W)
 local fineRequest=P.request
 local uninstall,priorStats=require('war.PassageNavigationStudy').attachForTest(P,C,W)
 local request,go,clear=P.request,C.go,P.clear
 local stats={centerlineRoutes=0,directRoutes=0,rejectedCenterlines=0,explicitRequests=0,prior=priorStats}
 local function goal(e,x,y)
  local order=e.orders and e.orders[1]
  if order and order.vesselLane~=nil and order.x and (order.x-x)^2+(order.y-y)^2<.000001 then return order.vesselLane end
 end
 local function install(e,x,y,path)
  e.pathGoal={x=x,y=y};e.pathResolved={x=x,y=y,adjusted=false};e.path=path
  e.pathIndex=1;e.pathPending=false;e.pathFailed=false;e.longRoute=nil
 end
 P.request=function(s,e,x,y,forceFine)
  local desired=goal(e,x,y)
  if desired==nil then return request(s,e,x,y,forceFine)end
  if e.pathPending then return end
  if s.campaign and not require('war.Campaign').allowed(s,x,y)then return request(s,e,x,y,forceFine)end
  stats.explicitRequests=stats.explicitRequests+1
  if clear(s,e.x,e.y,x,y,e.faction,e.vesselLane,desired)then
   install(e,x,y,{{x=x,y=y,lane=desired}});stats.directRoutes=stats.directRoutes+1;return
  end
  if desired>0 and (e.vesselLane or 0)>0 and W.hasVessels(s)then
   local route=centerRoute(W.vessels(s),e.x,e.y,x,y,e.vesselLane,desired)
   local px,py,lane=e.x,e.y,e.vesselLane;local valid=route~=false
   ---@cast route table
   if valid then for _,p in ipairs(route)do
    if not clear(s,px,py,p.x,p.y,e.faction,lane,p.lane)then valid=false;break end
    px,py,lane=p.x,p.y,p.lane
   end end
   if valid then install(e,x,y,route);stats.centerlineRoutes=stats.centerlineRoutes+1;return end
   stats.rejectedCenterlines=stats.rejectedCenterlines+1
  end
  -- Keep the real fine A*, but require the requested compartment at its goal.
  fineRequest(s,e,x,y,true)
  for _,job in ipairs(P.jobs)do if job.id==e.id and job.token==e.orderToken then job.goalLane=desired end end
 end
 C.go=function(s,e,x,y,dt,stopRange)
  local desired=goal(e,x,y)
  if desired~=nil and e.vesselLane~=desired then return go(s,e,x,y,dt,-.001)end
  return go(s,e,x,y,dt,stopRange)
 end
 return function()P.request=request;C.go=go;uninstall()end,stats
end
return M
