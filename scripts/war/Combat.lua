local D,U,W,C,E=require("war.Data"),require("war.Util"),require("war.World"),require("war.Commands"),require("war.Economy")
local F={}
local K,Status,Events,Organs=require("war.CombatConfig"),require("war.CombatStatus"),require("war.CombatEvents"),require("war.OrganRules")
function F.enemy(s,e,r,buildings)
 local best --[[@as table|false]];best=false
 local dd=math.huge
 for _,t in ipairs(W.neighbors(s,e.x,e.y,r)) do if U.alive(t) and t.faction~=e.faction and (t.faction~=0 or e.faction~=0) and (t.category=="unit" or buildings) and (e.faction==0 or W.visible(s,e.faction,t)) and (not s.campaign or require("war.Campaign").allowed(s,t.x,t.y)) then
  local d=U.dist(e,t);if d<r and (d<dd or d==dd and (not best or t.id<best.id)) then best,dd=t,d end
 end end return best,dd
end
function F.damage(s,e,t,damage,options)
 options=options or {}
 if not U.alive(t) or damage<=0 then return false end
 if not options.raw then
 if t.kind=="heavy" then damage=damage*.65 end
 if e and e.kind=="siege" and t.category=="building" then damage=damage*2.4 end
 local fa=e and s.factions[e.faction];if fa and fa.tech.weapons then damage=damage*1.25 end
 if e then damage=damage*Status.multiplier(e,"attackMultiplier")*Organs.attackMultiplier(s,e) end
 end
 local amount=math.min(t.hp,damage);t.hp=math.max(0,t.hp-damage);t.lastAttacker=e and e.id;t.hitTime=s.time
 Events.emit(s,"damage",{source=e and e.id,target=t.id,amount=amount,hp=t.hp,maxHp=t.maxHp,x=e and e.x or t.x,y=e and e.y or t.y,tx=t.x,ty=t.y,cause=options.cause or "attack",attackStyle=options.attackStyle or (e and U.dist(e,t)>3 and "arrow" or "hit")})
 if t.hp<=0 and t.checkpointId and require('war.VascularCheckpoints').defeated(s,e,t)then
  Events.emit(s,'checkpoint_control',{source=e and e.id,target=t.id,breached=t.breached});W.rebuild(s);return true,amount
 end
 if t.hp<=0 then
  Status.setState(s,t,"dead");Events.emit(s,"death",{source=e and e.id,target=t.id})
  if t.kind=="nest" and e and e.faction>0 then U.message(s,"感染巢已清除",e.faction) end
  if t.category=="building" and t.faction>0 then for _,q in ipairs(t.queue) do if q.tech then s.factions[t.faction].researching=nil end end end
  if t.faction==1 then U.message(s,(D.units[t.kind] or D.buildings[t.kind]).name.."已倒下") end
  W.rebuild(s)
 end
 return true,amount
end
function F.hit(s,e,t,damage)
 if not U.alive(e) or not U.alive(t) or e.faction==t.faction then return false end
 return F.damage(s,e,t,damage)
end
function F.knockback(s,e,t,distance)
 if t.category~="unit" or not U.alive(t) then return false end
 local dx,dy=t.x-e.x,t.y-e.y;local length=math.sqrt(dx*dx+dy*dy)
 if length<.00001 then dx,dy,length=1,0,1 end
 local fromX,fromY=t.x,t.y
 -- Small swept segments cannot cross a wall or jump another membrane.
 for _=1,math.ceil(distance/.2) do
  local step=math.min(.2,distance);if step<=0 then break end
  local x,y=U.clamp(t.x+dx/length*step,2,D.width(s)-1),U.clamp(t.y+dy/length*step,2,D.height(s)-1)
  if s.campaign and not require("war.Campaign").allowed(s,x,y) then break end
  if not require("war.Path").clear(s,t.x,t.y,x,y,t.faction,t.vesselLane) then break end
  local nx,ny,lane=require("war.CellCollision").move(s,t,x,y)
  t.x,t.y,t.vesselLane=nx,ny,lane;distance=distance-step
  if math.abs(nx-x)+math.abs(ny-y)>.01 then break end
 end
 C.resetPath(t);t.cellDetour=nil;t.travelSpeed=0;require("war.Motion").record(t);W.rebuild(s)
 Events.emit(s,"knockback",{source=e.id,target=t.id,x=fromX,y=fromY,tx=t.x,ty=t.y})
 return true
end
function F.launch(s,e,t,damage,config)
 s.combatProjectiles=s.combatProjectiles or {}
 if #s.combatProjectiles>=K.projectilesLimit then return false end
 s.nextProjectileId=(s.nextProjectileId or 0)+1
 local dx,dy=t.x-e.x,t.y-e.y;local length=math.sqrt(dx*dx+dy*dy);if length<.00001 then return false end
 -- Fixed direction, no homing. Damage is settled only on impact.
 local p={id=s.nextProjectileId,source=e.id,faction=e.faction,sourceKind=e.kind,x=e.x,y=e.y,dx=dx/length,dy=dy/length,speed=config.speed,ttl=config.ttl,damage=damage,targetKinds=U.copy(config.targetKinds)}
 s.combatProjectiles[#s.combatProjectiles+1]=p
 Events.emit(s,"projectile_spawn",{projectile=p.id,source=e.id,target=t.id,x=p.x,y=p.y,dx=p.dx,dy=p.dy,speed=p.speed})
 return true
end
function F.updateProjectiles(s,dt)
 local projectiles=s.combatProjectiles or {}
 for i=#projectiles,1,-1 do
  local p=projectiles[i];local distance=p.speed*math.min(dt,p.ttl);local remove=false
  for _=1,math.ceil(distance/.2) do
   local step=math.min(.2,distance);local nx,ny=p.x+p.dx*step,p.y+p.dy*step
   if nx<2 or ny<2 or nx>D.width(s)-1 or ny>D.height(s)-1 or (s.campaign and not require("war.Campaign").allowed(s,nx,ny)) or not require("war.Path").clear(s,p.x,p.y,nx,ny,p.faction) then remove=true;break end
   local hit --[[@as table|false]];hit=false
   local best=math.huge
   for _,t in ipairs(W.neighbors(s,nx,ny,2)) do
    if U.alive(t) and t.faction~=p.faction and t.category=="unit" and (not p.targetKinds or p.targetKinds[t.kind]) then
     local d=U.dist(t,{x=nx,y=ny});if d<=require("war.CellCollision").radius(t) and (d<best or d==best and t.id<hit.id) then hit,best=t,d end
    end
   end
   p.x,p.y=nx,ny;distance=distance-step
   if hit then
    local source=s.entities[p.source] or {id=p.source,faction=p.faction,kind=p.sourceKind,x=p.x,y=p.y}
    F.damage(s,source,hit,p.damage,{cause="projectile"});Events.emit(s,"projectile_impact",{projectile=p.id,target=hit.id,x=p.x,y=p.y});remove=true;break
   end
  end
  p.ttl=p.ttl-dt
  if remove or p.ttl<=0 then Events.emit(s,"projectile_removed",{projectile=p.id,x=p.x,y=p.y});table.remove(projectiles,i) end
 end
end
function F.contacts(s,e)
 local profile=D.units[e.kind] --[[@as table?]]
 local contact=profile and profile.contact;if not contact then return end
 e.contactHits=e.contactHits or {};local touching={}
 for _,t in ipairs(W.neighbors(s,e.x,e.y,3)) do
  if U.alive(t) and t.category=="unit" and t.faction~=e.faction and U.dist(e,t)<=require("war.CellCollision").radius(e)+require("war.CellCollision").radius(t)+.03 then
   local key=tostring(t.id);touching[key]=true
   if not e.contactHits[key] and s.time>=(e.nextContactHit or 0) then
    F.damage(s,e,t,contact.damage,{cause="collision",raw=true});F.knockback(s,e,t,contact.knockback);e.nextContactHit=s.time+contact.cool
   end
  end
 end
 e.contactHits=touching
end
function F.fight(s,e,t,dt,chase)
 if not U.alive(e) or not U.alive(t) or e.faction==t.faction then return false end
 if s.campaign and (not require("war.Campaign").allowed(s,e.x,e.y) or not require("war.Campaign").allowed(s,t.x,t.y)) then return false end
 local d=D.units[e.kind] or D.buildings[e.kind];local radius=(t.category=="building" and (D.buildings[t.kind].size or 1)*.5 or 0)
 local aim=t
 if t.checkpointId then
  local anchor,reach=require('war.VascularCheckpoints').attackAnchor(s,e,t)
  if anchor==false then return false end
  if anchor then aim=anchor;radius=reach end
 end
 local clear=not (s.campaign and (s.campaign.terrainVersion==2 or s.campaign.terrainVersion==3 or s.campaign.terrainVersion==4)) or require("war.Path").clear(s,e.x,e.y,t.x,t.y,e.faction,e.vesselLane)
 if t.checkpointId then clear=require('war.OrganBattlefield').sweep(s,e,e.x,e.y,aim.x,aim.y,e.vesselLane,aim.vesselLane)==true end
 local heartClear=require('war.HeartBattlefield').combatClear(s,e,aim)
 if heartClear~=nil then clear=heartClear end
 if not t.checkpointId and d.projectile and d.projectile.targetKinds and not d.projectile.targetKinds[t.kind] then return false end
 if U.dist(e,aim)<=d.range+radius and clear then
  Status.setState(s,e,"attack")
  if e.cooldown<=0 then
   if d.projectile and not t.checkpointId then if F.launch(s,e,t,d.damage,d.projectile) then e.cooldown=d.cool end
   else F.damage(s,e,t,d.damage,{attackStyle=d.attackStyle});e.cooldown=d.cool end
  end
  return true
 elseif chase and e.category=="unit" then C.go(s,e,aim.x,aim.y,dt,clear and d.range+radius-.1 or .5,aim.vesselLane);return true end return false
end
function F.updateTower(s,b,dt)
 b.cooldown=math.max(0,b.cooldown-dt);if b.complete and b.kind=="tower" then local d=D.buildings.tower;local t=F.enemy(s,b,d.range,true);if t and require('war.HeartBattlefield').combatClear(s,b,t)~=false then F.fight(s,b,t,dt,false) end end
end
return F
