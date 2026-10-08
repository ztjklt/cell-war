local N,U,T,R=require("war.CampaignData"),require("war.Util"),require("war.Territory"),require("war.Reinforcements")
local C={}
function C.create(version)
 local trachea=version==3
 return {stage=1,terrainVersion=trachea and 3 or 2,completed={},unlocked={[trachea and "trachea" or "nasal"]=true},randomEnabled=false,rewards={},reinforcements=R.new(version),
  event={id=trachea and "trachea" or "nasal",status="active",phase="defend",elapsed=0,wave=0,pendingViruses=0,spawnTimer=0,secure=0,zones=T.new(trachea and {campaign={event={id="trachea"}}} or {campaign={terrainVersion=2,event={id="nasal"}}})}}
end
function C.allowed(s,x,y)
 return not s.campaign or s.campaign.unlocked.body or (s.campaign.unlocked.nasal or s.campaign.unlocked.trachea) and T.zone(x,y,s)~=nil
end
function C.unlock(s,regions) for _,id in ipairs(regions or {}) do s.campaign.unlocked[id]=true end end
function C.checkpoint(s)
 s.campaign.checkpoint=require("war.Save").snapshot(s,true)
end
function C.start(s,id)
 local N=N.forState(s)
 if not s.campaign then return false,"当前是沙盒记录" end
 local spec=N.stages[s.campaign.stage] --[[@as table?]]
 if not spec or spec.id~=id or not spec.implemented then return false,"此事件尚未开放" end
 s.campaign.event={id=id,status="active",phase="defend",elapsed=0,wave=0,pendingViruses=0,spawnTimer=0,secure=0,zones=T.new(s)}
 s.outcome="playing";C.checkpoint(s);return true
end
function C.fail(s)
 s.campaign.event.status="failed";s.outcome="defeat";U.message(s,s.campaign.event.id=="trachea" and "气管失守：下段屏障已被病毒完全夺下" or "鼻腔失守：后鼻屏障已被病毒完全夺下")
end
function C.succeed(s)
 local N=N.forState(s)
 local c=s.campaign;local spec=N.stages[c.stage] --[[@as table]]
 if c.event.status~="active" then return end
 c.event.status="completed";c.completed[spec.id]=true;C.unlock(s,spec.unlocks)
 if not c.rewards[spec.id] then
  for k,n in pairs(spec.reward or {}) do require("war.Economy").add(s,1,k,n) end
  c.rewards[spec.id]=true
 end
 c.stage=c.stage+1;c.randomEnabled=c.stage>#N.stages;c.awaitingContent=N.stages[c.stage] and not N.stages[c.stage].implemented or false
 c.reinforcements.queue={};s.needsAutosave=true
 U.message(s,c.event.id=="trachea" and "气管已夺回 · 下一事件：双肺净化（尚未开放）" or "鼻腔已夺回 · 下一事件：咽喉防线（尚未开放）")
end
function C.randomCandidates(s)
 local N=N.forState(s)
 local out={};if not s.campaign or not s.campaign.randomEnabled then return out end
 local stages=N.stages --[[@as table[] ]]
 for _,stage in ipairs(stages) do if s.campaign.unlocked.body or s.campaign.unlocked[stage.region] then out[#out+1]=stage.region end end
 return out
end
function C.retry(s)
 if not s.campaign or s.campaign.event.status~="failed" or not s.campaign.checkpoint then return false end
 local checkpoint=U.copy(s.campaign.checkpoint);local restored=require("war.Save").restore(checkpoint,true)
 restored.campaign.checkpoint=checkpoint;return restored
end
function C.virus(s,e,dt)
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
function C.beforeStep(s,dt)
 local N=N.forState(s)
 local ev=s.campaign.event;if ev.status~="active" then return end
 ev.elapsed=ev.elapsed+dt;R.update(s,dt)
 while ev.wave<#N.waves and ev.elapsed>=N.waves[ev.wave+1].at-.000001 do
  ev.wave=ev.wave+1;ev.pendingViruses=ev.pendingViruses+N.waves[ev.wave].count
  U.message(s,"病毒入侵 · 第 "..ev.wave.." / "..#N.waves.." 波")
 end
 ev.phase=ev.wave==#N.waves and "counterattack" or "defend"
 ev.spawnTimer=ev.spawnTimer-dt
 if ev.pendingViruses>0 and ev.spawnTimer<=0 then
  local geometry=N.forState(s);local entry=geometry.entry
  if geometry.entries then
   local entries=geometry.entries --[[@as table]]
   entry=entries[ev.wave==2 and 2 or ev.wave==3 and ev.pendingViruses%2+1 or 1]
  end
  local e=require("war.Commands").spawn(s,"unit","virus",2,entry.x,entry.y+(ev.pendingViruses%5-2)*2)
  if e then
   if geometry.entries then e.viralSide=entry==geometry.entries[2] and 2 or 1 end
   ev.pendingViruses=ev.pendingViruses-1;ev.spawnTimer=.7
  end
 end
end
function C.afterStep(s,dt)
 local N=N.forState(s)
 local ev=s.campaign.event;if ev.status~="active" then return end
 T.update(s,dt)
 -- Failure always wins a same-step tie, including during the secure timer.
 if ev.zones[3].control<=-100 then C.fail(s);return end
 local safe=ev.wave==#N.waves and ev.pendingViruses==0
 for _,z in ipairs(ev.zones) do if z.control<100 or z.contested then safe=false end end
 for _,e in pairs(s.entities) do if U.alive(e) and e.kind=="virus" then safe=false;break end end
 ev.secure=safe and ev.secure+dt or 0
 if ev.secure>=N.secureSeconds-.000001 then C.succeed(s) end
end
return C
