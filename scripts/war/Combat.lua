local D,U,W,C,E=require("war.Data"),require("war.Util"),require("war.World"),require("war.Commands"),require("war.Economy")
local F={}
function F.enemy(s,e,r,buildings)
 local best,dd=false,math.huge
 for _,t in ipairs(W.neighbors(s,e.x,e.y,r)) do if U.alive(t) and t.faction~=e.faction and (t.faction~=0 or e.faction~=0) and (t.category=="unit" or buildings) and (e.faction==0 or W.visible(s,e.faction,t)) then
  local d=U.dist(e,t);if d<r and d<dd then best,dd=t,d end
 end end return best,dd
end
function F.hit(s,e,t,damage)
 if t.kind=="heavy" then damage=damage*.65 end
 if e.kind=="siege" and t.category=="building" then damage=damage*2.4 end
 local fa=s.factions[e.faction];if fa and fa.tech.weapons then damage=damage*1.25 end
 t.hp=t.hp-damage;t.lastAttacker=e.id;t.hitTime=s.time
 if #s.effects<80 then s.effects[#s.effects+1]={x=e.x,y=e.y,tx=t.x,ty=t.y,ttl=.3,kind=U.dist(e,t)>3 and "arrow" or "hit"} end
 if t.hp<=0 then
  t.hp=0
  if t.kind=="nest" and e.faction>0 then E.add(s,e.faction,"relic",4);U.message(s,"巢穴已清除，获得4件遗物",e.faction) end
  if t.category=="building" and t.faction>0 then for _,q in ipairs(t.queue) do if q.tech then s.factions[t.faction].researching=nil end end end
  if t.faction==1 then U.message(s,(D.units[t.kind] or D.buildings[t.kind]).name.."已倒下") end
  W.rebuild(s)
 end
end
function F.fight(s,e,t,dt,chase)
 local d=D.units[e.kind] or D.buildings[e.kind];local radius=(t.category=="building" and (D.buildings[t.kind].size or 1)*.5 or 0)
 local clear=not (s.campaign and s.campaign.terrainVersion==2) or require("war.Path").clear(s,e.x,e.y,t.x,t.y,e.faction,e.vesselLane)
 if U.dist(e,t)<=d.range+radius and clear then
  if e.cooldown<=0 then F.hit(s,e,t,d.damage);e.cooldown=d.cool end
  return true
 elseif chase and e.category=="unit" then C.go(s,e,t.x,t.y,dt,clear and d.range+radius-.1 or .5);return true end return false
end
function F.updateTower(s,b,dt)
 b.cooldown=math.max(0,b.cooldown-dt);if b.complete and b.kind=="tower" then local t=F.enemy(s,b,10,true);if t and b.cooldown<=0 then F.hit(s,b,t,19);b.cooldown=1.5 end end
end
return F
