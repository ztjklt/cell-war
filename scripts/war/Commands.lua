-- Common commands for touch, keyboard and AI; validation happens on execution.
local D,U,W,E,P=require("war.Data"),require("war.Util"),require("war.World"),require("war.Economy"),require("war.Path")
local C={}
local Motion=require("war.Motion")
local Collision=require("war.CellCollision")
function C.spawn(s,category,kind,f,x,y,complete)
 if s.campaign and (category~="unit" or not require("war.Campaign").allowed(s,x,y)) then return nil end
 local d=(category=="unit" and D.units[kind] or D.buildings[kind]) --[[@as table]]
 if category=="unit" then
  x,y=U.clamp(x,2,D.width(s)-1),U.clamp(y,2,D.height(s)-1)
  if not s.occupancy then W.rebuild(s) end
  x,y=Collision.find(s,{id=s.nextId,kind=kind,faction=f},x,y)
  if not x then return nil end
 end
 local e={id=s.nextId,category=category,kind=kind,faction=f,x=x,y=y,hp=d.hp,maxHp=d.hp,complete=complete~=false,progress=complete==false and 0 or 1,orders={},orderToken=0,path={},pathIndex=1,queue={},rally={x=x+3,y=y+3},satiety=100,temp=22,sanity=100,cooldown=0,work=0,cargo={},fire=0,wet=0,age=0}
 e.vesselLane=category=="unit" and W.lane(s,x,y) or 0;s.nextId=s.nextId+1;s.entities[e.id]=e;if category=="building" then W.rebuild(s) end;return e
end
function C.submit(s,c) s.commands[#s.commands+1]=U.copy(c) end
function C.order(s,e,o,append)
 if s.campaign and o.x and o.y and not require("war.Campaign").allowed(s,o.x,o.y) then return false end
 if not append then
  e.cellDetour=nil;e.contactStall=0;e.orders={};e.path={};e.longRoute=nil;e.pathGoal=nil;e.pathResolved=nil;e.routeEnd=nil;e.pathPending=false;e.pathFailed=false;e.travelSpeed=0;e.orderToken=e.orderToken+1
 end
 e.orders[#e.orders+1]=U.copy(o)
end
-- Remove an order that has not started yet. The first order is intentionally
-- protected because it may already be moving, fighting, or performing work.
function C.removeQueued(s,ids,index)
 if not index or index<=1 then return false end
 local changed=false
 for _,id in ipairs(ids or {}) do
  local e=s.entities[id]
  if U.alive(e) and e.faction==1 and e.orders and e.orders[index] then
   table.remove(e.orders,index);changed=true
  end
 end
 return changed
end
function C.execute(s,c)
 local f=c.faction or 1;local fa=s.factions[f];if not fa or fa.lost then return false end
 local kind=c.kind
 if s.campaign then
  if s.campaign.event.status=="failed" then return false end
  if kind=="reinforce" then return f==1 and require("war.Reinforcements").request(s) end
  if ({build=true,train=true,research=true,gather=true,farm=true,repair=true,rally=true,extinguish=true,cancel=true})[kind] then U.message(s,require("war.MapRegistry").isTrachea(s) and "气管事件仅开放战术指挥" or "鼻腔事件仅开放战术指挥",f);return false end
  if kind=="attack" and c.target then local t=s.entities[c.target];if t and not require("war.Campaign").allowed(s,t.x,t.y) then return false end end
  if c.x and c.y and not require("war.Campaign").allowed(s,c.x,c.y) then U.message(s,"这片组织尚未开放",f);return false end
 end
 if kind=="build" then
  local d=D.buildings[c.building] --[[@as table?]]
  if not d or not d.cost then return false end
  if fa.tier<d.tier then U.message(s,"需要科技等级 "..d.tier,f);return false end
  local offset=d.size%2==0 and 0 or .5
  local x,y=math.floor(c.x)+offset,math.floor(c.y)+offset
  local ok,why=W.canBuild(s,c.building,x,y,f);if not ok then U.message(s,why,f);return false end
  local workers={} for _,id in ipairs(c.ids or {}) do local u=s.entities[id];if U.alive(u) and u.faction==f and u.kind=="worker" then workers[#workers+1]=u end end
  if #workers==0 then U.message(s,"请先选择红细胞",f);return false end
  ok,why=E.pay(s,f,d.cost);if not ok then U.message(s,why,f);return false end
  local b=C.spawn(s,"building",c.building,f,x,y,false);b.hp=math.max(30,d.hp*.15)
  W.rebuild(s)
  for _,u in ipairs(workers) do C.order(s,u,{kind="build",target=b.id},c.append) end
  U.message(s,"开始建造"..d.name,f);return true,b.id
 elseif kind=="train" or kind=="research" then
  local b=s.entities[c.target];if not U.alive(b) or b.faction~=f or b.category~="building" or not b.complete then return false end
  if #b.queue>=6 then U.message(s,"生产队列已满",f);return false end
  if kind=="train" then
   local d=D.units[c.unit] --[[@as table?]]
   if not d or d.at~=b.kind or fa.tier<d.tier then U.message(s,"建筑或科技条件不足",f);return false end
   local pop,cap=E.population(s,f,true);if pop+d.pop>cap then U.message(s,"人口不足，请建造住宅（上限40）",f);return false end
   local ok,why=E.pay(s,f,d.cost);if not ok then U.message(s,why,f);return false end
   b.queue[#b.queue+1]={unit=c.unit,remaining=d.train,total=d.train,cost=U.copy(d.cost)}
  else
   local d=D.tech[c.tech] --[[@as table?]]
   if b.kind~="lab" or not d or fa.tier<d.tier or fa.tech[c.tech] or fa.researching then U.message(s,"研究条件不足或已有研究进行中",f);return false end
   if c.tech=="tier2" and fa.tier>=2 or c.tech=="tier3" and fa.tier>=3 then return false end
   local ok,why=E.pay(s,f,d.cost);if not ok then U.message(s,why,f);return false end
   fa.researching=c.tech;b.queue[#b.queue+1]={tech=c.tech,remaining=d.time,total=d.time,cost=U.copy(d.cost)}
  end return true
 elseif kind=="cancel" then
  local b=s.entities[c.target];if not U.alive(b) or b.faction~=f or b.category~="building" then return false end
  if not b.complete then E.refund(s,f,D.buildings[b.kind].cost,.75);b.hp=0;W.rebuild(s)
  elseif #b.queue>0 then local q=table.remove(b.queue);E.refund(s,f,q.cost,1);if q.tech then fa.researching=nil end end return true
 elseif kind=="rally" then
  local b=s.entities[c.target];if U.alive(b) and b.faction==f and b.category=="building" then b.rally={x=U.clamp(c.x,2,D.width(s)-1),y=U.clamp(c.y,2,D.height(s)-1)};return true end return false
 end
 local n=0
 for i,id in ipairs(c.ids or {}) do
  local e=s.entities[id]
  if U.alive(e) and e.faction==f and e.category=="unit" then
   local o={kind=kind,target=c.target,x=c.x,y=c.y}
   if kind=="attack" then local t=s.entities[c.target];if not U.alive(t) or t.faction==f or not W.visible(s,f,t) then o.kind="attackmove" end end
   if kind=="gather" then local r=s.resources[c.target];if not r or r.amount<=0 or not fa.seen[c.target] then o.kind="move" else o.x,o.y=r.x,r.y end end
   if kind=="retreat" then local b=U.nearest(s,e.x,e.y,function(v) return v.faction==f and v.category=="building" and v.complete and D.buildings[v.kind].supply end);if b then o.kind="move";o.x,o.y=b.rally.x,b.rally.y end end
   if kind=="retreat" and s.campaign then local home=require("war.CampaignData").forState(s).home;o.kind="move";o.x,o.y=home.x,home.y end
   -- Every selected unit receives the exact same destination. Collision.resolve
   -- keeps the formation from overlapping while moving, instead of silently
   -- changing each unit's move target into parallel lanes.
   if kind=="move" or o.kind=="attackmove" then o.x=U.clamp(o.x or e.x,2,D.width(s)-1);o.y=U.clamp(o.y or e.y,2,D.height(s)-1) end
   if s.campaign and o.x and o.y and not require("war.Campaign").allowed(s,o.x,o.y) then o.x,o.y=c.x or e.x,c.y or e.y end
   if kind=="stop" then e.orders={};e.path={};e.longRoute=nil;e.pathPending=false;e.orderToken=e.orderToken+1
   elseif (kind=="gather" or kind=="build" or kind=="repair" or kind=="farm" or kind=="extinguish") and e.kind~="worker" then
   else C.order(s,e,o,c.append);n=n+1 end
  end
 end return n>0
end
function C.process(s)
 local pending=s.commands;s.commands={}
 for _,c in ipairs(pending) do C.execute(s,c) end
end
function C.completeOrder(e) table.remove(e.orders,1);e.path={};e.pathPending=false;e.pathFailed=false;e.pathIndex=1;e.orderToken=e.orderToken+1;e.work=0 end
function C.go(s,e,x,y,dt,stopRange)
 local d=math.sqrt((x-e.x)^2+(y-e.y)^2)
 if d<=(stopRange or .7) then return true end
 if (stopRange or .7)<=1 and e.pathResolved and e.pathResolved.adjusted and e.pathGoal and (x-e.pathGoal.x)^2+(y-e.pathGoal.y)^2<1 and U.dist(e,e.pathResolved)<.9 then return true end
 -- Supply returns and combat chases may interrupt the current work destination.
 if e.pathGoal and (x-e.pathGoal.x)^2+(y-e.pathGoal.y)^2>1 then
  e.path={};e.longRoute=nil;e.pathIndex=1;e.pathPending=false;e.pathFailed=false;e.orderToken=e.orderToken+1
 end
 if e.pathFailed then return false end
 if not e.pathPending and (not e.path[e.pathIndex or 1]) then P.request(s,e,x,y) end
 local factor=(e.satiety<20 or e.sanity<25 or e.temp<5 or e.temp>35) and .65 or 1
 local terrain=D.biomes[W.terrain(s,math.floor(e.x),math.floor(e.y))]
 local speed=D.units[e.kind].speed*factor*(terrain.move or 1)
 if s.time-(e.lastTravel or -10)>dt*1.5 then e.travelSpeed=0 end
 -- Short acceleration and arrival easing, expressed in seconds.
 local wanted=speed*U.clamp((d-(stopRange or .7))/.7,.22,1)
 e.travelSpeed=(e.travelSpeed or 0)+(wanted-(e.travelSpeed or 0))*(1-math.exp(-dt/0.14));e.lastTravel=s.time
 local budget=e.travelSpeed*dt
 for _=1,16 do
  local p=e.path[e.pathIndex or 1];if not p then break end
  local dx,dy=p.x-e.x,p.y-e.y;local pd=math.sqrt(dx*dx+dy*dy)
  if pd<.0001 then
   if p.lane~=nil then local ok,preferred=P.clear(s,e.x,e.y,e.x,e.y,e.faction,e.vesselLane,p.lane);if ok then e.vesselLane=preferred end end
   e.pathIndex=(e.pathIndex or 1)+1
  else
   local step=math.min(pd,budget);local nx,ny=e.x+dx/pd*step,e.y+dy/pd*step
   if e.cellDetour then nx,ny=e.x+e.cellDetour.x*step,e.y+e.cellDetour.y*step end
   local clear,lane=P.clear(s,e.x,e.y,nx,ny,e.faction,e.vesselLane,step>=pd-.0001 and p.lane or nil)
   if not clear then
    if e.cellDetour then e.cellDetour=nil;e.contactStall=0 end
    e.stuck=(e.stuck or 0)+dt
    if e.stuck>1 then e.path={};e.pathPending=false;e.pathIndex=1;e.orderToken=e.orderToken+1;e.stuck=0 end
    break
   end
   nx,ny,lane=Collision.move(s,e,nx,ny)
   if p.lane~=nil and (p.x-nx)^2+(p.y-ny)^2<.00000001 then
    local ok,preferred=P.clear(s,e.x,e.y,nx,ny,e.faction,e.vesselLane,p.lane);if ok then lane=preferred end
   end
   local moved=math.sqrt((nx-e.x)^2+(ny-e.y)^2)
   if e.cellDetour then
    e.cellDetour.remaining=e.cellDetour.remaining-moved
    if e.cellDetour.remaining<=0 or moved<step*.05 then e.cellDetour=nil end
   else
    local remaining=math.sqrt((p.x-nx)^2+(p.y-ny)^2)
    e.contactStall=remaining>pd-step*.15 and (e.contactStall or 0)+1 or 0
    if e.contactStall>=6 then
     local side=e.id%2==0 and 1 or -1
     e.cellDetour={x=-dy/pd*side,y=dx/pd*side,remaining=2.5};e.contactStall=0
    end
   end
   e.x,e.y=nx,ny;e.vesselLane=lane;Motion.record(e);e.stuck=0;budget=budget-step
   if (p.x-e.x)^2+(p.y-e.y)^2<.00000001 then e.pathIndex=(e.pathIndex or 1)+1 end
   if budget<.0001 or U.dist(e,{x=x,y=y})<=(stopRange or .7) then break end
  end
 end
 return false
end
return C
