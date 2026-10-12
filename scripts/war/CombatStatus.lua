local U,K,Events=require("war.Util"),require("war.CombatConfig"),require("war.CombatEvents")
local B={}
function B.setState(s,e,state)
 if e.resolvingCombatState and state~="dead" then e.nextCombatState=state;return end
 if e.combatState==state then return end
 local old=e.combatState or "idle";e.combatState=state
 Events.emit(s,"state",{target=e.id,from=old,to=state})
end
function B.apply(s,e,kind,options)
 if not U.alive(e) or not K.statuses[kind] then return false end
 local status=U.copy(options or {});status.kind=kind
 if status.duration and status.duration<=0 then return false end
 e.statuses=e.statuses or {};e.statuses[kind]=status
 Events.emit(s,"status_added",{target=e.id,status=kind,duration=status.duration})
 return true
end
function B.remove(s,e,kind)
 if not e.statuses or not e.statuses[kind] then return false end
 e.statuses[kind]=nil;Events.emit(s,"status_removed",{target=e.id,status=kind});return true
end
function B.multiplier(e,field)
 local factor=1
 for kind,status in pairs(e.statuses or {}) do factor=factor*(status[field] or K.statuses[kind] and K.statuses[kind][field] or 1) end
 return factor
end
function B.update(s,e,dt)
 local kinds={};for kind in pairs(e.statuses or {}) do kinds[#kinds+1]=kind end;table.sort(kinds)
 for _,kind in ipairs(kinds) do
  local status=e.statuses[kind];local active=math.min(dt,status.duration or dt)
  local rate=status.damagePerSecond or K.statuses[kind] and K.statuses[kind].damagePerSecond
  if rate and rate>0 then require("war.Combat").damage(s,s.entities[status.source],e,rate*active,{cause=kind,raw=true}) end
  if not U.alive(e) then return end
  if status.duration then status.duration=status.duration-dt;if status.duration<=0 then B.remove(s,e,kind) end end
 end
end
return B
