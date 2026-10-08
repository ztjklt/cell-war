-- Half-Life style map transition controller. It owns the pause/loading window.
local Registry=require("war.MapRegistry")
local C={}

local function playerInside(s,trigger)
 local inside,total=0,0
 for _,e in pairs(s.entities) do
  if e.hp>0 and e.faction==1 and e.category=="unit" and e.kind~="worker" then
   total=total+1
   if Registry.containsTrigger(trigger,e.x,e.y) then inside=inside+1 end
  end
 end
 if total==0 then return false end
 return inside>=math.max(1,math.ceil(total*.5))
end

function C.find(s)
 if not s.campaign then return end
 local current=Registry.currentId(s);local def=Registry.definition(current)
 if not def or not def.exits then return end
 if s.campaign.transition then return end
 for _,trigger in ipairs(def.exits) do
  local targetReady=Registry.implemented(trigger.target)
  if targetReady and (not trigger.requiresComplete or s.campaign.event.status=="completed") and playerInside(s,trigger) then return trigger end
 end
end

function C.request(g,trigger)
 if g.transition or not trigger then return false end
 local stage=Registry.stage(trigger.target)
 g.transition={phase="loading",timer=0,target=trigger.target,spawn=trigger.targetSpawn or "entry",label=trigger.name or "进入下一关",targetName=stage and stage.name or trigger.target}
 g.paused=true;g.selection={};g.mode=false;g.placement=false;return true
end

function C.update(g,dt)
 if not g.started then return end
 if not g.transition then
  local trigger=C.find(g.state);if trigger then C.request(g,trigger) end
  return
 end
 local tr=g.transition;tr.timer=tr.timer+dt
 if tr.phase=="loading" and tr.timer>=.2 then
  local Sim=require("war.Simulation")
  local state,err=Sim.changeMap(g.state,tr.target,tr.spawn)
  if not state then
   g.transition=nil;g.paused=false;g.state.message=err or "地图加载失败";g.state.messageTime=3;return
  end
  g.state=state;g.transition.phase="fadein";g.transition.timer=0;g.accumulator=0;g.selection={};g.groups={{},{},{}};g.inspectTarget=false;g.lastTap=false;local home=Registry.forState(state).home;g.camera={x=home.x,y=home.y};g.zoom=1
  require("war.Motion").reset(g);require("war.Render").prepare(state);if g.refreshSidebar then g.refreshSidebar() end;require("war.Render").home(g)
 elseif tr.phase=="fadein" and tr.timer>=.35 then
  g.transition=nil;g.paused=false
 end
end

function C.draw(R,g)
 if not g.transition then return end
 R.rect(0,0,R.w,R.h,{14,18,28},225)
 R.text(R.w*.5,R.h*.5,"正在进入下一关",28,{239,244,255})
 if g.transition.targetName then R.text(R.w*.5,R.h*.5+34,g.transition.targetName,15,{167,192,210}) end
end

return C
