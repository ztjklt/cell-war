-- Map-owned geometry adapter. No pancreas, bladder, or spleen gameplay is defined here.
local D,U,W,K=require("war.Data"),require("war.Util"),require("war.World"),require("war.CombatConfig")
local Status,Events=require("war.CombatStatus"),require("war.CombatEvents")
local O={}
O.at=require("war.OrganRegions").at
function O.isKidney(organ) return organ=="kidney" or organ=="kidney_l" or organ=="kidney_r" end
function O.isIntestine(organ) return organ=="small_intestine" or organ=="large_intestine" end
function O.moveMultiplier(s,e)
 return O.isIntestine(O.at(s,e.x,e.y)) and K.intestine.moveMultiplier or 1
end
function O.canTrain(s,kind,x,y)
 return not K.strongCells[kind] or O.at(s,x,y)=="liver"
end
function O.update(s,e,dt)
 if e.category~="unit" or not U.alive(e) then return end
 local organ=O.at(s,e.x,e.y);e.organ=organ
 if K.strongCells[e.kind] and organ=="heart" then e.requiresHeart=false end
 if e.faction<=0 or not O.isKidney(organ) then e.kidneyProgress=0;return end
 local needs=e.hp<e.maxHp or e.impurities and e.impurities>0
 for kind in pairs(e.statuses or {}) do if K.statuses[kind] and K.statuses[kind].clearOrgan=="kidney" then needs=true end end
 if not needs then return end
 Status.setState(s,e,"recovering");e.kidneyProgress=(e.kidneyProgress or 0)+dt
 if e.kidneyProgress<K.kidney.cleanseSeconds then return end
 local kinds={};for kind in pairs(e.statuses or {}) do if K.statuses[kind] and K.statuses[kind].clearOrgan=="kidney" then kinds[#kinds+1]=kind end end
 table.sort(kinds);for _,kind in ipairs(kinds) do Status.remove(s,e,kind) end
 if (e.impurities or 0)>0 then e.impurities=0;Events.emit(s,"cleansed",{target=e.id}) end
 -- Only the fraction of this step after cleansing may restore health.
 local healDt=math.min(dt,e.kidneyProgress-K.kidney.cleanseSeconds)
 local amount=math.min(e.maxHp-e.hp,K.kidney.healPerSecond*healDt)
 if amount>0 then e.hp=e.hp+amount;Events.emit(s,"heal",{target=e.id,amount=amount,hp=e.hp,maxHp=e.maxHp,cause="kidney"}) end
end
function O.attackMultiplier(s,e)
 if not K.combatCells[e.kind] then return 1 end
 for _,b in ipairs(W.neighbors(s,e.x,e.y,K.aura.radius)) do
  if U.alive(b) and b.category=="building" and b.kind==K.aura.building and b.complete and b.attackAura and b.faction==e.faction and U.dist(e,b)<=K.aura.radius then return K.aura.attackMultiplier end
 end
 return 1 -- Identical facilities do not stack.
end
function O.canLeaveLiver(s,e,x,y)
 return not K.strongCells[e.kind] or not (e.requiresHeart or O.at(s,e.x,e.y)=="liver") or O.at(s,x,y)=="liver" or O.at(s,x,y)=="heart"
end
function O.canStep(s,e,x,y,goalX,goalY)
 if not K.strongCells[e.kind] or not (e.requiresHeart or O.at(s,e.x,e.y)=="liver") then return true end
 return O.at(s,goalX,goalY)=="heart" or O.at(s,x,y)=="liver"
end
-- Map owner calls this after choosing a destination. Entry into heart is required.
function O.transfer(s,e,x,y)
 if not U.alive(e) or e.category~="unit" or O.at(s,e.x,e.y)~="heart" then return false,"not_in_heart" end
 if x<2 or y<2 or x>D.width(s)-1 or y>D.height(s)-1 then return false,"outside_map" end
 local organ=O.at(s,x,y)
 if not organ or organ=="heart" or organ=="pancreas" or organ=="bladder" or organ=="spleen" then return false,"invalid_destination" end
 if s.campaign and not require("war.Campaign").allowed(s,x,y) then return false,"locked_destination" end
 local lane=W.lane(s,x,y);local proxy=U.copy(e);proxy.vesselLane=lane
 local nx,ny=require("war.CellCollision").find(s,proxy,x,y)
 if not nx or O.at(s,nx,ny)~=organ then return false,"no_safe_landing" end
 local fromX,fromY=e.x,e.y;e.x,e.y=nx,ny;e.vesselLane=W.lane(s,nx,ny)
 require("war.Commands").resetPath(e);e.cellDetour=nil;e.travelSpeed=0
 e.requiresHeart=false;require("war.Motion").trails[e]=nil;W.rebuild(s)
 Events.emit(s,"transfer",{target=e.id,x=fromX,y=fromY,tx=nx,ty=ny,organ=organ});return true
end
return O
