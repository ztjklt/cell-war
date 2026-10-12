-- Bounded, non-destructive stream: each presentation consumer owns its cursor.
local U,K=require("war.Util"),require("war.CombatConfig")
local B={}
function B.emit(s,kind,data)
 s.combatEvents=s.combatEvents or {};s.combatEventSeq=(s.combatEventSeq or 0)+1
 local event=U.copy(data or {});event.kind=kind;event.seq=s.combatEventSeq;event.time=s.time
 s.combatEvents[#s.combatEvents+1]=event
 if #s.combatEvents>K.eventsLimit then table.remove(s.combatEvents,1) end
 return event
end
function B.since(s,cursor)
 local events={};for _,event in ipairs(s.combatEvents or {}) do if event.seq>(cursor or 0) then events[#events+1]=U.copy(event) end end
 local first=s.combatEvents and s.combatEvents[1]
 return events,s.combatEventSeq or 0,first~=nil and (cursor or 0)<first.seq-1
end
return B
