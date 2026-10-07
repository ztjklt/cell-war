local D,U,W,E,C,F=require("war.Data"),require("war.Util"),require("war.World"),require("war.Economy"),require("war.Commands"),require("war.Combat")
local J={}
local function delivery(s,e,dt)
 local b=U.nearest(s,e.x,e.y,function(v) return v.faction==e.faction and v.category=="building" and v.complete and D.buildings[v.kind].supply end)
 if not b then return false end
 if C.go(s,e,b.x,b.y,dt,(D.buildings[b.kind].size or 1)*.5+1) then
  for k,n in pairs(e.cargo) do E.add(s,e.faction,k,n);if e.faction==1 then s.delivered=(s.delivered or 0)+n end end
  e.cargo={};e.delivering=false;e.path={};e.pathIndex=1;e.pathPending=false;e.orderToken=e.orderToken+1
 end return true
end
function J.update(s,e,dt)
 e.age=e.age+dt;e.cooldown=math.max(0,e.cooldown-dt)
 local workDt=dt*((e.satiety<20 or e.sanity<25 or e.temp<5 or e.temp>35) and .55 or 1)
 if e.life then e.life=e.life-dt;if e.life<=0 then e.hp=0;return end end
 local o=e.orders[1]
 if s.campaign and e.kind=="virus" then require("war.Campaign").virus(s,e,dt);return end
 if not s.campaign and e.faction>0 and (e.returning or e.satiety<30 or e.hp<e.maxHp*.22) then
  local home=U.nearest(s,e.x,e.y,function(b) return b.faction==e.faction and b.category=="building" and b.complete and D.buildings[b.kind].supply end)
  if home and U.dist(e,home)>7 then
   e.returning=true;C.go(s,e,home.x,home.y,dt,5);return
  elseif e.returning and (e.satiety<65 or e.hp<e.maxHp*.35) then
   -- Hungry survivors must unload carried food before waiting to be fed.
   -- Otherwise an empty pantry can deadlock the last farmer at the camp.
   if next(e.cargo) then delivery(s,e,dt) end
   return
  elseif e.returning then e.returning=false;e.path={};e.pathIndex=1;e.pathPending=false;e.pathFailed=false;e.orderToken=e.orderToken+1 end
 end
 if e.sanity<8 and e.faction>0 and not (o and o.kind=="retreat") then
  local home=U.nearest(s,e.x,e.y,function(b) return b.faction==e.faction and b.category=="building" and b.complete and (b.kind=="fire" or b.kind=="core") end)
  if home then C.go(s,e,home.x,home.y,dt,3);return end
 end
 if e.faction==0 then
  local _,fraction=require("war.Survival").clock(s);local r=fraction>=.75 and 17 or 8
  local target=F.enemy(s,e,r,false)
  if target then F.fight(s,e,target,dt,true) elseif e.home and U.dist(e,e.home)>2 then C.go(s,e,e.home.x,e.home.y,dt,2) end return
 end
 -- Retaliate without discarding work queues; workers only fight a nearby attacker.
 local activeAttack=o and (o.kind=="attack" or o.kind=="attackmove")
 local t=F.enemy(s,e,e.kind=="worker" and 1.9 or (activeAttack and 10 or 5),activeAttack)
 if t and not (o and (o.kind=="move" or o.kind=="retreat")) then F.fight(s,e,t,dt,e.kind~="worker");return end
 if not o then if next(e.cargo) then delivery(s,e,dt) end return end
 if o.kind=="move" or o.kind=="attackmove" or o.kind=="retreat" then
  if C.go(s,e,o.x or e.x,o.y or e.y,dt,.75) then C.completeOrder(e) end
 elseif o.kind=="guard" then
  if U.dist(e,{x=o.x or e.x,y=o.y or e.y})>1.5 then C.go(s,e,o.x,o.y,dt,1) end
 elseif o.kind=="attack" then
  local target=s.entities[o.target]
  if not U.alive(target) then C.completeOrder(e)
  elseif not W.visible(s,e.faction,target) then C.completeOrder(e)
  else F.fight(s,e,target,dt,true) end
 elseif o.kind=="gather" then
  if e.delivering then delivery(s,e,dt);return end
  local r=s.resources[o.target]
  if not r or r.amount<=0 then
   if next(e.cargo) then e.delivering=true;delivery(s,e,dt)
   else
    local nearest,dd=false,math.huge
    for k,v in pairs(s.resources) do if v.kind==(r and r.kind or "wood") and v.amount>0 and s.factions[e.faction].seen[k] then local d=U.dist(e,v);if d<dd and d<25 then nearest,dd=k,d end end end
    if nearest then o.target=nearest;e.pathFailed=false else C.completeOrder(e) end
   end return
  end
  if C.go(s,e,r.x,r.y,dt,1.4) then
   e.work=e.work+workDt
   if e.work>=.7 then e.work=e.work-.7;local n=math.min(2,r.amount);r.amount=r.amount-n;e.cargo[r.kind]=(e.cargo[r.kind] or 0)+n
    if e.cargo[r.kind]>=14 or r.amount<=0 then e.delivering=true;e.path={};e.pathIndex=1;e.pathPending=false;e.orderToken=e.orderToken+1 end
   end
  end
 elseif o.kind=="build" or o.kind=="repair" or o.kind=="extinguish" or o.kind=="farm" then
  if o.kind=="farm" and e.delivering then delivery(s,e,dt);return end
  local b=s.entities[o.target]
  if not U.alive(b) or b.faction~=e.faction then C.completeOrder(e);return end
  if C.go(s,e,b.x,b.y,dt,(D.buildings[b.kind].size or 1)*.5+1) then
   if o.kind=="build" then
    if b.complete then
     C.completeOrder(e)
     if b.kind=="farm" then
      local staffed=false
      for _,v in pairs(s.entities) do if v.id~=e.id and v.orders and v.orders[1] and v.orders[1].kind=="farm" and v.orders[1].target==b.id then staffed=true end end
      if not staffed then C.order(s,e,{kind="farm",target=b.id}) end
     end
    else b.progress=math.min(1,b.progress+workDt/D.buildings[b.kind].time);b.hp=math.max(b.hp,b.maxHp*b.progress)
     if b.progress>=1 then b.complete=true;b.hp=b.maxHp;U.message(s,D.buildings[b.kind].name.."建造完成",b.faction);W.rebuild(s) end
    end
   elseif o.kind=="repair" then
    if b.hp>=b.maxHp then C.completeOrder(e) else e.work=e.work+workDt;if e.work>=1 then e.work=0;if E.pay(s,e.faction,{wood=1}) then b.hp=math.min(b.maxHp,b.hp+20) end end end
   elseif o.kind=="extinguish" then b.fire=math.max(0,b.fire-workDt*.2);if b.fire<=0 then C.completeOrder(e) end
   elseif b.kind=="farm" and b.complete then
    b.staffedUntil=s.time+1
    local _,_,season=require("war.Survival").clock(s)
    b.harvest=(b.harvest or 0)+workDt*D.climate[season].farmRate
    if b.harvest>=25 then
     b.harvest=b.harvest-25;e.cargo.food=(e.cargo.food or 0)+8;e.delivering=true;e.path={};e.pathIndex=1;e.pathPending=false;e.orderToken=e.orderToken+1
     if e.faction==1 then s.farmed=(s.farmed or 0)+8 end
    end
   else C.completeOrder(e) end
  end
 end
end
return J
