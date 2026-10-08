local N,U,T,R=require("war.CampaignData"),require("war.Util"),require("war.Territory"),require("war.Reinforcements")
local Registry=require("war.MapRegistry")
local C={}
local function mapId(c)
 return c.map_id or (c.event and c.event.id=="nasal" and "nasal_01") or (c.event and c.event.id=="trachea" and "trachea_01") or (c.event and c.event.id) or "trachea_01"
end
local function stageFor(c)
 local stage=Registry.stage(mapId(c));if stage then return stage end
 local data=N.forState({campaign=c})
 for _,item in ipairs(data.stages or {}) do if item.id==c.event.id or item.region==c.event.id then return item end end
end
function C.create(version,mapIdOverride)
 local legacy=version~=3;local id=mapIdOverride or (legacy and "nasal_01" or "trachea_01");local eventId=legacy and "nasal" or (id=="trachea_01" and "trachea" or id)
 local seed={campaign={terrainVersion=legacy and 2 or 3,map_id=id,event={id=eventId}}};local stage=Registry.stage(id)
 return {stage=stage and stage.index or 1,map_id=id,current_map_id=id,previous_map_id=nil,visited_maps={[id]=true},map_progress={},terrainVersion=legacy and 2 or 3,completed={},unlocked={[legacy and "nasal" or "trachea"]=true},randomEnabled=false,rewards={},reinforcements=R.new(version),autoplay=false,autoplayTimer=0,event={id=eventId,map_id=id,status="active",phase="defend",elapsed=0,wave=0,pendingViruses=0,spawnTimer=0,spawnQueue={},secure=0,zones=T.new(seed)}}
end
function C.allowed(s,x,y)
 if not s.campaign then return true end
 local geometry=N.forState(s);return geometry.allowed and geometry.allowed(x,y) or T.zone(x,y,s)~=nil
end
function C.unlock(s,regions) for _,id in ipairs(regions or {}) do s.campaign.unlocked[id]=true end end
function C.checkpoint(s) s.campaign.checkpoint=require("war.Save").snapshot(s,true) end
function C.start(s,id)
 if not s.campaign then return false,"Campaign mode required" end
 local data=N.forState(s);local spec=data.stages[s.campaign.stage]
 if not spec or spec.id~=id or spec.implemented==false then return false,"Campaign map is not available" end
 s.campaign.event={id=id,map_id=id,status="active",phase="defend",elapsed=0,wave=0,pendingViruses=0,spawnTimer=0,spawnQueue={},secure=0,zones=T.new(s)};s.outcome="playing";C.checkpoint(s);return true
end
function C.enterMap(s,targetId)
 if not s.campaign or not Registry.exists(targetId) then return false,"Unknown campaign map" end
 if not Registry.implemented(targetId) then return false,"Campaign map is not available yet" end
 local c=s.campaign;local old=mapId(c);local stage=Registry.stage(targetId)
 c.previous_map_id=old;c.map_id=targetId;c.current_map_id=targetId;c.visited_maps=c.visited_maps or {};c.visited_maps[targetId]=true;c.map_progress=c.map_progress or {};c.stage=stage and stage.index or c.stage;c.terrainVersion=3;c.awaitingContent=false
 c.event={id=targetId,map_id=targetId,status="active",phase="defend",elapsed=0,wave=0,pendingViruses=0,spawnTimer=0,spawnQueue={},secure=0,zones=T.new(s)}
 return true,Registry.definition(targetId)
end
function C.fail(s)
 s.campaign.event.status="failed";s.outcome="defeat";U.message(s,"Campaign map lost: "..tostring(mapId(s.campaign)))
end
function C.canSkipWave(s)
 if not s or not s.campaign or not s.campaign.event then return false,"战役模式不可用" end
 local ev=s.campaign.event;local data=N.forState(s)
 if ev.status~="active" then return false,"当前战斗已结束" end
 if ev.wave>=#data.waves then return false,"已经是最后一波" end
 if ev.pendingViruses>0 then return false,"请先清除当前波次" end
 for _,e in pairs(s.entities) do if U.alive(e) and e.kind=="virus" then return false,"请先清除当前波次" end end
 return true
end
function C.skipWave(s)
 local ok,reason=C.canSkipWave(s);if not ok then return false,reason end
 local ev=s.campaign.event;local data=N.forState(s);ev.elapsed=math.max(ev.elapsed,data.waves[ev.wave+1].at);ev.spawnTimer=0
 U.message(s,"已跳过等待，第 "..(ev.wave+1).." 波即将到来");return true
end
function C.toggleAutoplay(s)
 if not s or not s.campaign or not s.campaign.event then return false,"战役模式不可用" end
 if s.campaign.event.status~="active" then return false,"当前战斗已结束" end
 s.campaign.autoplay=not s.campaign.autoplay;s.campaign.autoplayTimer=0
 U.message(s,s.campaign.autoplay and "挂机已开启：空闲细胞会自动驻守并拦截附近病毒" or "挂机已关闭：恢复手动指挥")
 return s.campaign.autoplay
end
function C.autopilot(s,dt)
 local c=s.campaign;if not c or not c.autoplay or c.event.status~="active" then return end
 c.autoplayTimer=(c.autoplayTimer or 0)-dt;if c.autoplayTimer>0 then return end;c.autoplayTimer=1
 local data=N.forState(s);local viruses={};local Commands=require("war.Commands")
 for _,v in pairs(s.entities) do if U.alive(v) and v.kind=="virus" then viruses[#viruses+1]=v end end
 for _,e in pairs(s.entities) do if U.alive(e) and e.faction==1 and e.category=="unit" then
  local o=e.orders and e.orders[1];local target=false;local distance=math.huge
  for _,v in ipairs(viruses) do local d=U.dist(e,v);if d<distance and d<=28 then target,distance=v,d end end
  if target and (not o or o.kind=="guard" or e.pathFailed) then
   Commands.order(s,e,{kind="attackmove",x=target.x,y=target.y})
  elseif (not o or e.pathFailed) and #data.zones>0 then
   local z=data.zones[((e.id-1)%#data.zones)+1]
   Commands.order(s,e,{kind="guard",x=z.x,y=z.y})
  end
 end end
end
function C.succeed(s)
 local data=N.forState(s);local c=s.campaign;local spec=stageFor(c) or data.stages[c.stage];if not spec or c.event.status~="active" then return end
 local key=mapId(c);local legacyKey=c.event.id
 c.event.status="completed";c.completed[key]=true
 if legacyKey=="trachea" or legacyKey=="nasal" then c.completed[legacyKey]=true end
 C.unlock(s,spec.unlocks)
 if not c.rewards[key] and not c.rewards[legacyKey] then
  for k,n in pairs(spec.reward or {}) do require("war.Economy").add(s,1,k,n) end
 end
 c.rewards[key]=true;c.rewards[legacyKey]=true
 local nextId=Registry.next(key);local current=Registry.stage(key)
 c.stage=math.min((current and current.index or c.stage)+1,Registry.stageCount()+1)
 c.randomEnabled=nextId==nil;c.awaitingContent=nextId and not Registry.implemented(nextId) or false
 c.reinforcements.queue={};s.needsAutosave=true
 U.message(s,nextId and ("地图已夺回 · 下一关："..Registry.stage(nextId).name..(c.awaitingContent and "（尚未开放）" or "，从地图出口进入")) or "战役已完成")
end
function C.randomCandidates(s)
 local data=N.forState(s);local out={};if not s.campaign or not s.campaign.randomEnabled then return out end
 for _,stage in ipairs(data.stages or {}) do if s.campaign.unlocked.body or s.campaign.unlocked[stage.region] then out[#out+1]=stage.region end end;return out
end
function C.retry(s)
 if not s.campaign or s.campaign.event.status~="failed" or not s.campaign.checkpoint then return false end
 local checkpoint=U.copy(s.campaign.checkpoint);local restored=require("war.Save").restore(checkpoint,true);restored.campaign.checkpoint=checkpoint;return restored
end
local function airwayVirus(s,e,dt)
 local F,Cmd=require("war.Combat"),require("war.Commands")
 local target=F.enemy(s,e,8,false)
 if target then F.fight(s,e,target,dt,true);return end
 local index=3
 for i,z in ipairs(s.campaign.event.zones) do if z.control>-100 then index=i;break end end
 local geometry=N.forState(s);local z=geometry.zones[index]
 if geometry.entries and not e.viralSide then e.viralSide=e.y<geometry.bounds.y+80 and 2 or 1 end
 local sideY=geometry.entries and e.viralSide==2 and (index==3 and 430 or 410) or z.y
 local x=z.x+(e.id%5-2)*1.6;local y=sideY+(math.floor(e.id/5)%5-2)*1.6
 if e.viralZone~=index or e.pathFailed then e.viralZone=index;e.pathFailed=false;e.pathPending=false;e.path={};e.longRoute=nil;e.orderToken=e.orderToken+1 end
 Cmd.go(s,e,x,y,dt,1)
end

function C.virus(s,e,dt)
 if Registry.currentId(s)~="lungs_01" then return airwayVirus(s,e,dt) end
 local F,Cmd=require("war.Combat"),require("war.Commands")
 local geometry=N.forState(s);local index=math.floor(e.viralZone or 1);local z=geometry.zones[index] or geometry.zones[1]
 if not z then return end
 local target=F.enemy(s,e,8,false)
 if target and T.zone(target.x,target.y,s)==index then F.fight(s,e,target,dt,true);return end
 local x=z.x+(e.id%5-2)*1.6;local y=z.y+(math.floor(e.id/5)%5-2)*1.6
 if e.pathFailed then e.pathFailed=false;e.pathPending=false;e.path={};e.longRoute=nil;e.orderToken=e.orderToken+1 end
 Cmd.go(s,e,x,y,dt,1)
end
local function enqueueWave(ev,wave,waveIndex)
 ev.spawnQueue=ev.spawnQueue or {}
 local zones=wave.zones or {wave.zone or wave.index or waveIndex or 1}
 for i=1,wave.count do ev.spawnQueue[#ev.spawnQueue+1]=zones[((i-1)%#zones)+1] end
 ev.pendingViruses=#ev.spawnQueue
 ev.spawnZone=zones[1]
end
function C.beforeStep(s,dt)
 local data=N.forState(s);local ev=s.campaign.event;if ev.status~="active" then return end;ev.elapsed=ev.elapsed+dt;R.update(s,dt)
 if ev.spawnQueue==nil then ev.spawnQueue={};if ev.pendingViruses>0 and ev.wave>0 then local legacyWave=data.waves[ev.wave];local zones=legacyWave and (legacyWave.zones or {legacyWave.zone or ev.wave}) or {ev.spawnZone or 1};for i=1,ev.pendingViruses do ev.spawnQueue[#ev.spawnQueue+1]=zones[((i-1)%#zones)+1] end end end
 while ev.wave<#data.waves and ev.elapsed>=data.waves[ev.wave+1].at-.000001 do ev.wave=ev.wave+1;enqueueWave(ev,data.waves[ev.wave],ev.wave);U.message(s,"Virus wave "..ev.wave.." / "..#data.waves) end
 ev.phase=ev.wave==#data.waves and "counterattack" or "defend";ev.spawnTimer=ev.spawnTimer-dt
 if ev.pendingViruses>0 and ev.spawnTimer<=0 then
  local geometry=N.forState(s);ev.spawnQueue=ev.spawnQueue or {}
  local index=ev.spawnQueue[1] or math.min(#geometry.zones,math.max(1,ev.spawnZone or ev.wave))
  local zone=geometry.zones[index] or geometry.zones[1]
  local x,y=zone.x+(ev.pendingViruses%5-2)*1.6,zone.y+(math.floor(ev.pendingViruses/5)%5-2)*1.6
  ---@type table?
  local entry
  if Registry.currentId(s)~="lungs_01" then
   entry=geometry.entry
   if geometry.entries then entry=geometry.entries[ev.wave==2 and 2 or ev.wave==3 and ev.pendingViruses%2+1 or 1] end
   x,y=entry.x,entry.y+(ev.pendingViruses%5-2)*2
  end
  local e=require("war.Commands").spawn(s,"unit","virus",2,x,y)
  if e then
   e.viralZone=index;e.viralWave=ev.wave
   if geometry.entries then e.viralSide=entry==geometry.entries[2] and 2 or 1 end
   table.remove(ev.spawnQueue,1);ev.pendingViruses=#ev.spawnQueue;ev.spawnTimer=.7
  end
 end
 C.autopilot(s,dt)
end
function C.afterStep(s,dt)
 local data=N.forState(s);local ev=s.campaign.event;if ev.status~="active" then return end;T.update(s,dt)
 for _,index in ipairs(data.failureZones or {#ev.zones}) do if ev.zones[index] and ev.zones[index].control<=-100 then C.fail(s);return end end
 local safe=ev.wave==#data.waves and ev.pendingViruses==0;for _,z in ipairs(ev.zones) do if z.control<100 or z.contested then safe=false end end;for _,e in pairs(s.entities) do if U.alive(e) and e.kind=="virus" then safe=false;break end end;ev.secure=safe and ev.secure+dt or 0;if ev.secure>=data.secureSeconds-.000001 then C.succeed(s) end
end
return C
