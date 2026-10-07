-- Two-scale incremental A*: 16-cell terrain routes, then local building-aware paths.
local D,U,W=require("war.Data"),require("war.Util"),require("war.World")
local Vessels=require("war.Vessels")
local P={jobs={},cursor=1};local directions={{1,0},{0,1},{-1,0},{0,-1},{1,1},{-1,1},{1,-1},{-1,-1}}
local function push(h,item) h[#h+1]=item;local i=#h;while i>1 do local p=math.floor(i/2);if h[p].f<=item.f then break end h[i]=h[p];i=p end h[i]=item end
local function pop(h) local root=h[1];local last=table.remove(h);if #h>0 then local i=1;while i*2<=#h do local c=i*2;if c+1<=#h and h[c+1].f<h[c].f then c=c+1 end;if last.f<=h[c].f then break end h[i]=h[c];i=c end h[i]=last end return root end
function P.reset() P.jobs={};P.cursor=1 end
-- Supercover segment: crossing diagonally requires both adjacent cells clear.
-- A -> B is a swept point; corners and narrow gaps must never be cut.
---@return boolean, table<number,boolean>
local function trace(s,x,y,tx,ty,f,lane,occupancy)
 local count=math.max(1,math.ceil(math.max(math.abs(tx-x),math.abs(ty-y))*4))
 local px,py=x,y;local states={[lane or W.lane(s,x,y)]=true}
 for i=1,count do
  local ax,ay=x+(tx-x)*i/count,y+(ty-y)*i/count;local cx,cy=math.floor(ax),math.floor(ay)
  local valid=occupancy and W.walkable(s,cx,cy,f) or not occupancy and W.land(s,cx,cy)
  if not valid then return false,{} end
  local fx,fy=math.floor(px),math.floor(py)
  if cx~=fx and cy~=fy and (not W.walkable(s,cx,fy,f) or not W.walkable(s,fx,cy,f)) then return false,{} end
  if W.hasVessels(s) then
   local reachable={}
   for current in pairs(states) do for _,nextLane in ipairs(W.vessels(s).options(px,py,ax,ay,current)) do reachable[nextLane]=true end end
   if not next(reachable) then return false,{} end;states=reachable
  end
  px,py=ax,ay
 end
 return true,states
end
function P.clear(s,x,y,tx,ty,f,lane,desiredLane)
 local ok,states=trace(s,x,y,tx,ty,f,lane,true);if not ok then return false end
 if desiredLane~=nil then if states[desiredLane] then return true,desiredLane else return false end end
 if states[lane or 0] then return true,lane or 0 end
 local best=math.huge;for n in pairs(states) do best=math.min(best,n) end;return true,best
end
local function smooth(s,e,work,deadline)
 local path=work.path
 local lane=work.lane or e.vesselLane or W.lane(s,e.x,e.y)
 local out=work.out or {};local x,y=work.x or e.x,work.y or e.y;local i=work.index or 1
 while i<=#path do
  if deadline and os.clock()>=deadline then work.lane,work.out,work.x,work.y,work.index=lane,out,x,y,i;return nil end
  local far=i
  -- Bounded lookahead keeps large route completion within its frame budget.
  for j=i+1,math.min(#path,i+12) do
   if not P.clear(s,x,y,path[j].x,path[j].y,e.faction,lane,path[j].lane) then break end
   far=j
  end
  local p=path[far];out[#out+1]=p;local _,nextLane=P.clear(s,x,y,p.x,p.y,e.faction,lane,p.lane);lane=nextLane or lane;x,y=p.x,p.y;i=far+1
 end
 return out
end
local function finishFine(s,e,j,path,lane)
 e.pathPending=false;e.path=path;e.pathIndex=1
 -- Preserve the exact fractional destination, including its final safe segment.
 if not j.routeIndex and math.floor(j.requestX)==j.gx and math.floor(j.requestY)==j.gy then
  local last=e.path[#e.path] or {x=e.x,y=e.y}
  if P.clear(s,last.x,last.y,j.requestX,j.requestY,e.faction,lane) then e.path[#e.path+1]={x=j.requestX,y=j.requestY} end
 end
 if j.routeIndex and e.longRoute then e.longRoute.index=j.routeIndex+1 end
end
local function lineLand(s,x,y,tx,ty)
 local steps=math.ceil(math.max(math.abs(tx-x),math.abs(ty-y)))
 for i=0,steps do local a=steps>0 and i/steps or 0;if not W.land(s,math.floor(x+(tx-x)*a),math.floor(y+(ty-y)*a)) then return false end end
 return true
end
local function anchor(s,x,y)
 local ax=U.clamp(8+math.floor((x-8)/16+.5)*16,8,D.width(s)-8);local ay=U.clamp(8+math.floor((y-8)/16+.5)*16,8,D.height(s)-8)
 local best,dd=false,math.huge
 for dy=-2,2 do for dx=-2,2 do local xx,yy=ax+dx*16,ay+dy*16;local d=(x-xx)^2+(y-yy)^2
  if d<dd and W.land(s,xx,yy) and lineLand(s,x,y,xx+.5,yy+.5) then best,dd={x=xx,y=yy},d end
 end end return best
end
local function job(s,e,sx,sy,gx,gy,phase,limit,routeIndex,goalLane)
 local lane=e.vesselLane or W.lane(s,e.x,e.y);local k=U.key(sx,sy)..":"..lane;e.pathPending=true;e.pathFailed=false;e.path={}
 P.jobs[#P.jobs+1]={id=e.id,token=e.orderToken,sx=sx,sy=sy,gx=gx,gy=gy,phase=phase,limit=limit,routeIndex=routeIndex,goalLane=goalLane,requestX=e.pathGoal.x,requestY=e.pathGoal.y,open={{k=k,x=sx,y=sy,lane=lane,g=0,f=((sx-gx)^2+(sy-gy)^2)^.5}},g={[k]=0},parent={},points={[k]={x=sx+.5,y=sy+.5,lane=lane}},closed={},visits=0}
end
function P.request(s,e,x,y,forceFine)
 if s.campaign and not require("war.Campaign").allowed(s,x,y) then e.path={};e.pathPending=false;e.pathFailed=true;U.message(s,"这片组织尚未开放",e.faction);return end
 if e.pathPending then return end
 if s.campaign and s.campaign.terrainVersion==2 then forceFine=true end
 e.pathGoal={x=x,y=y}
 e.vesselLane=e.vesselLane or W.lane(s,e.x,e.y)
 local gx,gy=math.floor(U.clamp(x,2,D.width(s)-1)),math.floor(U.clamp(y,2,D.height(s)-1))
 local adjusted=not W.walkable(s,gx,gy,e.faction)
 if adjusted then
  local best,dd=false,math.huge
  for yy=gy-5,gy+5 do for xx=gx-5,gx+5 do if W.walkable(s,xx,yy,e.faction) then
   local d=(xx+.5-x)^2+(yy+.5-y)^2+((xx-e.x)^2+(yy-e.y)^2)*.0001
   if d<dd then best,dd={x=xx,y=yy},d end
  end end end
  if not best then e.path={};e.pathFailed=true;U.message(s,"目标位于深水或无法通行的区域",e.faction);return end
  ---@cast best {x:number,y:number}
  gx,gy=best.x,best.y
 end
 e.pathResolved={x=gx+.5,y=gy+.5,adjusted=adjusted}
 local route=e.longRoute
 if route and ((route.x-x)^2+(route.y-y)^2>1 or not route.points[route.index]) then e.longRoute=nil;route=nil end
 if route then local p=route.points[route.index];job(s,e,math.floor(e.x),math.floor(e.y),math.floor(p.x),math.floor(p.y),"fine",24000,route.index,p.lane);return end
 if not forceFine and W.hasVessels(s) and (gx-e.x)^2+(gy-e.y)^2>160*160 then
  local points=W.vessels(s).route(e.x,e.y,gx+.5,gy+.5,e.vesselLane)
  if points then e.longRoute={points=points,index=1,x=x,y=y};P.request(s,e,x,y);return end
 end
 if not forceFine and (gx-e.x)^2+(gy-e.y)^2>80*80 then
  local a,b=anchor(s,e.x,e.y),anchor(s,gx+.5,gy+.5)
  if a and b then
   e.routeEnd={x=gx+.5,y=gy+.5};job(s,e,a.x,a.y,b.x,b.y,"macro",4096);return
  end
 end
 job(s,e,math.floor(e.x),math.floor(e.y),gx,gy,"fine",forceFine and 60000 or 24000)
end
function P.update(s,budget,seconds)
 -- The runtime yields between expansions; tests may omit the time slice for deterministic completion.
 local deadline=seconds and os.clock()+seconds
 local expansions=0
 while budget>0 and #P.jobs>0 do
  if P.cursor>#P.jobs then P.cursor=1 end
  local j=P.jobs[P.cursor];local e=s.entities[j.id];local done=false
  for _=1,math.min(budget,48) do
   if deadline and expansions%4==0 and os.clock()>=deadline then break end
   budget=budget-1
   expansions=expansions+1
   if not U.alive(e) or e.orderToken~=j.token then done=true;break end
   if j.smoothing then
    local path=smooth(s,e,j.smoothing,deadline)
    if path then finishFine(s,e,j,path,j.smoothing.finishLane);done=true end
    break
   end
   if #j.open==0 or j.visits>j.limit then
    e.pathPending=false
    if j.phase=="macro" then e.pathFailed=true;U.message(s,"远路暂不可达，请选择通行口或附近落脚点",e.faction)
    else e.pathFailed=true;U.message(s,"道路不通，细胞等待新命令",e.faction) end
    done=true;break
   end
   local n=pop(j.open)
   if not j.closed[n.k] then
    j.closed[n.k]=true;j.visits=j.visits+1
    if n.x==j.gx and n.y==j.gy and (j.goalLane==nil or n.lane==j.goalLane) then
     local reverse={};local k=n.k
     while k and j.parent[k] do local point=j.points[k];reverse[#reverse+1]={x=point.x,y=point.y,lane=point.lane};k=j.parent[k] end
     local path={};for i=#reverse,1,-1 do path[#path+1]=reverse[i] end
     if j.phase=="macro" then
      e.pathPending=false
      table.insert(path,1,{x=j.sx+.5,y=j.sy+.5});path[#path+1]=e.routeEnd
      e.longRoute={points=path,index=1,x=j.requestX,y=j.requestY};P.request(s,e,j.requestX,j.requestY)
     else
      j.smoothing={path=path,finishLane=n.lane}
      break
     end
     done=true;break
    end
    local stride=j.phase=="macro" and 16 or 1
    for _,v in ipairs(directions) do
     local x,y=n.x+v[1]*stride,n.y+v[2]*stride;local valid
     if j.phase=="macro" then valid=W.land(s,x,y) and lineLand(s,n.x+.5,n.y+.5,x+.5,y+.5)
     else valid=W.walkable(s,x,y,e.faction) and (v[1]==0 or v[2]==0 or (W.walkable(s,n.x+v[1],n.y,e.faction) and W.walkable(s,n.x,n.y+v[2],e.faction))) end
     if valid then
      local ok,lanes=trace(s,n.x+.5,n.y+.5,x+.5,y+.5,e.faction,n.lane,j.phase~="macro")
      if ok then for lane in pairs(lanes) do
       local k=U.key(x,y)..":"..lane;local g=n.g+stride*((v[1]~=0 and v[2]~=0) and 1.41421356 or 1)
       if not j.closed[k] and (not j.g[k] or g<j.g[k]) then
        j.g[k]=g;j.parent[k]=n.k;j.points[k]={x=x+.5,y=y+.5,lane=lane};push(j.open,{k=k,x=x,y=y,lane=lane,g=g,f=g+math.sqrt((x-j.gx)^2+(y-j.gy)^2)})
       end
      end end
     end
    end
   end
  end
  if done then table.remove(P.jobs,P.cursor) else P.cursor=P.cursor+1 end
  if deadline and os.clock()>=deadline then return end
 end
end
return P
