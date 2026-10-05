-- Two-scale incremental A*: 16-cell terrain routes, then local building-aware paths.
local D,U,W=require("war.Data"),require("war.Util"),require("war.World")
local P={jobs={},cursor=1};local directions={{1,0},{0,1},{-1,0},{0,-1},{1,1},{-1,1},{1,-1},{-1,-1}}
local function push(h,item) h[#h+1]=item;local i=#h;while i>1 do local p=math.floor(i/2);if h[p].f<=item.f then break end h[i]=h[p];i=p end h[i]=item end
local function pop(h) local root=h[1];local last=table.remove(h);if #h>0 then local i=1;while i*2<=#h do local c=i*2;if c+1<=#h and h[c+1].f<h[c].f then c=c+1 end;if last.f<=h[c].f then break end h[i]=h[c];i=c end h[i]=last end return root end
function P.reset() P.jobs={};P.cursor=1 end
-- Supercover segment: crossing diagonally requires both adjacent cells clear.
-- A -> B is a swept point; corners and narrow gaps must never be cut.
function P.clear(s,x,y,tx,ty,f)
 local count=math.max(1,math.ceil(math.max(math.abs(tx-x),math.abs(ty-y))*4))
 local px,py=math.floor(x),math.floor(y)
 for i=1,count do
  local cx,cy=math.floor(x+(tx-x)*i/count),math.floor(y+(ty-y)*i/count)
  if not W.walkable(s,cx,cy,f) then return false end
  if cx~=px and cy~=py and (not W.walkable(s,cx,py,f) or not W.walkable(s,px,cy,f)) then return false end
  px,py=cx,cy
 end
 return true
end
local function smooth(s,e,path)
 local out={};local x,y=e.x,e.y;local i=1
 while i<=#path do
  local far=i
  -- Bounded lookahead keeps large route completion within its frame budget.
  for j=i+1,math.min(#path,i+12) do
   if not P.clear(s,x,y,path[j].x,path[j].y,e.faction) then break end
   far=j
  end
  local p=path[far];out[#out+1]=p;x,y=p.x,p.y;i=far+1
 end
 return out
end
local function lineLand(s,x,y,tx,ty)
 local steps=math.ceil(math.max(math.abs(tx-x),math.abs(ty-y)))
 for i=0,steps do local a=steps>0 and i/steps or 0;if not W.land(s,math.floor(x+(tx-x)*a),math.floor(y+(ty-y)*a)) then return false end end
 return true
end
local function anchor(s,x,y)
 local ax=U.clamp(8+math.floor((x-8)/16+.5)*16,8,D.MAP-8);local ay=U.clamp(8+math.floor((y-8)/16+.5)*16,8,D.MAP-8)
 local best,dd=false,math.huge
 for dy=-2,2 do for dx=-2,2 do local xx,yy=ax+dx*16,ay+dy*16;local d=(x-xx)^2+(y-yy)^2
  if d<dd and W.land(s,xx,yy) and lineLand(s,x,y,xx+.5,yy+.5) then best,dd={x=xx,y=yy},d end
 end end return best
end
local function job(s,e,sx,sy,gx,gy,phase,limit,routeIndex)
 local k=U.key(sx,sy);e.pathPending=true;e.pathFailed=false;e.path={}
 P.jobs[#P.jobs+1]={id=e.id,token=e.orderToken,sx=sx,sy=sy,gx=gx,gy=gy,phase=phase,limit=limit,routeIndex=routeIndex,requestX=e.pathGoal.x,requestY=e.pathGoal.y,open={{k=k,x=sx,y=sy,g=0,f=((sx-gx)^2+(sy-gy)^2)^.5}},g={[k]=0},parent={},closed={},visits=0}
end
function P.request(s,e,x,y,forceFine)
 if e.pathPending then return end
 e.pathGoal={x=x,y=y}
 local gx,gy=math.floor(U.clamp(x,2,D.MAP-1)),math.floor(U.clamp(y,2,D.MAP-1))
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
 if route then local p=route.points[route.index];job(s,e,math.floor(e.x),math.floor(e.y),math.floor(p.x),math.floor(p.y),"fine",24000,route.index);return end
 if not forceFine and (gx-e.x)^2+(gy-e.y)^2>80*80 then
  local a,b=anchor(s,e.x,e.y),anchor(s,gx+.5,gy+.5)
  if a and b then
   e.routeEnd={x=gx+.5,y=gy+.5};job(s,e,a.x,a.y,b.x,b.y,"macro",4096);return
  end
 end
 job(s,e,math.floor(e.x),math.floor(e.y),gx,gy,"fine",forceFine and 60000 or 24000)
end
function P.update(s,budget)
 while budget>0 and #P.jobs>0 do
  if P.cursor>#P.jobs then P.cursor=1 end
  local j=P.jobs[P.cursor];local e=s.entities[j.id];local done=false
  for _=1,math.min(budget,48) do
   budget=budget-1
   if not U.alive(e) or e.orderToken~=j.token then done=true;break end
   if #j.open==0 or j.visits>j.limit then
    e.pathPending=false
    if j.phase=="macro" then P.request(s,e,j.requestX,j.requestY,true)
    else e.pathFailed=true;U.message(s,"道路不通，细胞等待新命令",e.faction) end
    done=true;break
   end
   local n=pop(j.open)
   if not j.closed[n.k] then
    j.closed[n.k]=true;j.visits=j.visits+1
    if n.x==j.gx and n.y==j.gy then
     local reverse={};local k=n.k
     while k and k~=U.key(j.sx,j.sy) do local x,y=U.xy(k);reverse[#reverse+1]={x=x+.5,y=y+.5};k=j.parent[k] end
     local path={};for i=#reverse,1,-1 do path[#path+1]=reverse[i] end
     e.pathPending=false
     if j.phase=="macro" then
      table.insert(path,1,{x=j.sx+.5,y=j.sy+.5});path[#path+1]=e.routeEnd
      e.longRoute={points=path,index=1,x=j.requestX,y=j.requestY};P.request(s,e,j.requestX,j.requestY)
     else
      e.path=smooth(s,e,path);e.pathIndex=1
      if j.routeIndex and e.longRoute then e.longRoute.index=j.routeIndex+1 end
     end
     done=true;break
    end
    local stride=j.phase=="macro" and 16 or 1
    for _,v in ipairs(directions) do
     local x,y=n.x+v[1]*stride,n.y+v[2]*stride;local valid
     if j.phase=="macro" then valid=W.land(s,x,y) and lineLand(s,n.x+.5,n.y+.5,x+.5,y+.5)
     else valid=W.walkable(s,x,y,e.faction) and (v[1]==0 or v[2]==0 or (W.walkable(s,n.x+v[1],n.y,e.faction) and W.walkable(s,n.x,n.y+v[2],e.faction))) end
     if valid then
      local k=U.key(x,y);local g=n.g+stride*((v[1]~=0 and v[2]~=0) and 1.41421356 or 1)
      if not j.closed[k] and (not j.g[k] or g<j.g[k]) then j.g[k]=g;j.parent[k]=n.k;push(j.open,{k=k,x=x,y=y,g=g,f=g+math.sqrt((x-j.gx)^2+(y-j.gy)^2)}) end
     end
    end
   end
  end
  if done then table.remove(P.jobs,P.cursor) else P.cursor=P.cursor+1 end
 end
end
return P
