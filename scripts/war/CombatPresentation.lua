-- Compatibility consumer for the existing renderer. Logic never creates visual effects.
local Events=require("war.CombatEvents")
local P={}
function P.update(s)
 local events,cursor=Events.since(s,s.combatPresentationCursor)
 s.combatPresentationCursor=cursor
 for _,event in ipairs(events) do
  if event.kind=="damage" and event.x and #s.effects<80 then
   s.effects[#s.effects+1]={x=event.x,y=event.y,tx=event.tx,ty=event.ty,ttl=.3,kind=event.attackStyle or "hit"}
  end
 end
end
return P
