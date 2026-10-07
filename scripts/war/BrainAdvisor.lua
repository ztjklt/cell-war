-- Read-only dialogue from the current game. Advisor memory stays outside saves.
local U,N,T=require("war.Util"),require("war.CampaignData"),require("war.Territory")
local B={portrait="image/brain-advisor/reference-portrait.png",
 icon="image/brain-advisor/reference-portrait.png",name="小脑",role="脑细胞 · 人体联络员"}

local function troops(s)
 local count,hurt=0,0
 for _,e in pairs(s.entities) do
  if U.alive(e) and e.faction==1 and e.category=="unit" then
   count=count+1;if e.hp<e.maxHp*.4 then hurt=hurt+1 end
  end
 end
 return count,hurt
end
local function danger(ev)
 local z=ev.zones[3]
 return z and (z.control<60 or z.hostile>0)
end
function B.reply(s,topic)
 local count,hurt=troops(s)
 local c=s.campaign
 if not c then
  local day,_,season,phase=require("war.Survival").clock(s)
  local E,D=require("war.Economy"),require("war.Data")
  if topic=="supply" then return {title="胞群补给",text="当前可用葡萄糖 "..math.floor(E.food(s,1)).."。让工细胞采集并运回胞巢，安排培养床生产，远征前检查补给。旧记录的沙盒没有鼻腔调援功能。"} end
  if topic=="defense" then return {title="稳态建议",text="胞群目前有 "..count.." 名细胞，其中 "..hurt.." 名生命低于 40%。受伤单位适合回营休整。保留工细胞和生产建筑，逐步发展，再组织进攻。"} end
  return {title="人体内域情况",text="我是小脑，你的脑细胞联络员。这份记录处于沙盒，第 "..day.." 天，当前是「"..D.seasons[season].."」的"..phase.."期。你有 "..count.." 名细胞。温度、饱食与精神会影响它们的状态；这是游戏中的胞群稳态。"}
 end
 local ev,r=c.event,c.reinforcements
 if topic=="supply" then
  local waiting=0;for _,q in ipairs(r.queue) do waiting=waiting+q.remaining end
  local text="补给现有 "..r.supply.." / "..N.supply.max.."。"
  if ev.status~="active" then text=text.."这次战斗已经结束，调援暂停。"
  else
   text=text.."每 "..N.supply.period.." 秒回复 1 点；每次消耗 "..N.supply.cost.." 点调来 "..N.supply.count.." 个白细胞，"..N.supply.arrival.." 秒后抵达，冷却 "..N.supply.cooldown.." 秒。"
   text=text..(r.cooldown>0 and "当前还需冷却 "..math.ceil(r.cooldown).." 秒。" or r.supply<N.supply.cost and "现在补给不足，先守住防线等待回复。" or "现在可以点击底部「调援 +2」。")
  end
  if waiting>0 then text=text.."已有 "..waiting.." 名援军调入中。" end
  return {title="援军补给",text=text}
 end
 if topic=="defense" then
  local text
  if ev.status=="failed" then text="后鼻屏障已完全失守。这次防守失败了。关闭对话后可重试事件，恢复事件开始时的部队与补给。"
  elseif ev.status=="completed" then text="鼻腔已经夺回，部队和已完成记录会保留。咽喉、双肺、肠道与血流的后续事件尚未开放。"
  elseif danger(ev) then text="优先回防后鼻屏障！那里有病毒进入或控制正在下降。让白细胞清除敌军、留在区域内夺回控制，补给充足时调援。完全失守会结束本次事件。"
  elseif ev.secure>0 then text="全部区域已净化，正在稳固："..math.floor(ev.secure).." / "..N.secureSeconds.." 秒。维持区域完全控制，防止病毒重新进入。"
  elseif ev.phase=="counterattack" then text="三波入侵都已启动。守住后方，逐步清除病毒并夺回三块区域。全部控制后还需稳定 "..N.secureSeconds.." 秒；双方同在区域时争夺进度会暂停。"
  else text="先守住后鼻屏障，再反攻入口黏膜。选择白细胞，点击进攻目标；可沿上下鼻道绕开鼻甲，也可从黄色膜口走血管侧路。" end
  return {title="防线建议",text=text.."当前有 "..count.." 名免疫细胞，"..hurt.." 名生命低于 40%。"}
 end
 local text=ev.status=="completed" and "好消息，鼻腔已夺回！" or ev.status=="failed" and "鼻腔防线失守了。" or "人体的鼻腔正在遭遇病毒入侵。"
 text=text.."入侵已启动 "..ev.wave.." / "..#N.waves.." 波。"
 for i,z in ipairs(ev.zones) do
  text=text..N.zones[i].name.."："..T.status(z).."。"
 end
 if ev.status=="active" and ev.wave<#N.waves then text=text.."下一波约 "..math.max(0,math.ceil(N.waves[ev.wave+1].at-ev.elapsed)).." 秒后开始。" end
 return {title="人体当前情况",text=text.."其余器官的事件尚未开放；当前没有它们的感染监测数据。"}
end

-- Observe edges once, prioritizing danger. No timers advance while paused/in a modal.
function B.poll(g,dt)
 if g.brainState~=g.state then
  g.brainState=g.state;g.brainMemory={};g.brainBubble=false;g.brainBubbleTime=0;g.brainIntro=0
 end
 if not g.started or g.paused or g.modal then return end
 g.brainBubbleTime=math.max(0,(g.brainBubbleTime or 0)-dt)
 if g.brainBubbleTime==0 then g.brainBubble=false end
 local s,m=g.state,g.brainMemory
 local message=false
 if s.campaign then
  local ev=s.campaign.event;local urgent=danger(ev)
  if urgent and not m.danger and ev.status=="active" then message="后鼻屏障告急！先回防，再调援。"
  elseif ev.wave~=m.wave and ev.wave>0 and ev.status=="active" then message="第 "..ev.wave.." 波病毒已入侵。点我查看防线建议。"
  elseif ev.secure>0 and not m.secure then message="鼻腔已净化！继续稳守 "..N.secureSeconds.." 秒。"
  else
   for i,z in ipairs(ev.zones) do
    if z.control==100 and m.zones and m.zones[i]<100 then message=N.zones[i].name.."已完全夺回！";break end
   end
  end
  m.danger=urgent;m.wave=ev.wave;m.secure=ev.secure>0;m.zones={}
  for i,z in ipairs(ev.zones) do m.zones[i]=z.control end
 end
 g.brainIntro=(g.brainIntro or 0)+dt
 if not m.introduced and g.brainIntro>=1 then
  m.introduced=true
  message=message or "我是小脑，负责汇报人体情况。点击我，或在下方选个话题和我聊聊。"
 end
 if message then g.brainBubble=message;g.brainBubbleTime=8 end
end
return B
