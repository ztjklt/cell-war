-- Isolated regressions for the GitHub gameplay update. No live cloud or file writes.
local Q={}
function Q.run()
 local S,W,C,P,U,Save,Camp,N,Registry,Level=require('war.Simulation'),require('war.World'),require('war.Commands'),require('war.Path'),require('war.Util'),require('war.Save'),require('war.Campaign'),require('war.CampaignData'),require('war.MapRegistry'),require('war.ChangeLevel')
 local results={}
 local function test(name,fn) local ok,err=pcall(fn);results[#results+1]={name=name,pass=ok,error=ok and '' or tostring(err)} end
 local function complete(s) local ev=s.campaign.event;ev.wave=#N.forState(s).waves;for _,z in ipairs(ev.zones) do z.control=100;z.owner=1 end;Camp.succeed(s) end
 test('多单位目标一致，替换命令清空队列，当前命令不可删除',function()
  local s=S.new(73);local ids={};for id in pairs(s.entities) do ids[#ids+1]=id end;table.sort(ids)
  local home=N.forState(s).home
  assert(C.execute(s,{kind='move',ids=ids,x=home.x,y=home.y}))
  for _,id in ipairs(ids) do local e=s.entities[id];assert(e.orders[1].x==home.x and e.orders[1].y==home.y) end
  C.execute(s,{kind='guard',ids=ids,x=home.x,y=home.y,append=true})
  assert(not C.removeQueued(s,ids,1));assert(C.removeQueued(s,ids,2))
  C.execute(s,{kind='guard',ids=ids,x=home.x,y=home.y,append=true})
  C.execute(s,{kind='move',ids=ids,x=home.x,y=home.y})
  for _,id in ipairs(ids) do assert(#s.entities[id].orders==1) end
 end)
 test('单击敌方显示资料，点己方清除资料，双击只选附近同类',function()
  local s=S.new(73);local I,R=require('war.Input'),require('war.Render')
  ---@type table?
  local spear
  for _,e in pairs(s.entities) do if e.kind=='spear' then spear=e;break end end
  local far=C.spawn(s,'unit','spear',1,N.forState(s).entry.x,N.forState(s).entry.y)
  local enemy=C.spawn(s,'unit','virus',2,N.forState(s).entry.x,N.forState(s).entry.y+8)
  local g={state=s,selection={},camera={x=0,y=0},zoom=1,append=false,mode=false,placement=false}
  local priorPick,priorProject,priorInput=I.pick,R.unproject,input
  input={GetKeyDown=function() return false end};R.unproject=function() return enemy.x,enemy.y end
  local ok,err=pcall(function()
   I.pick=function() return enemy end;I.tap(g,0,0,false);assert(g.inspectTarget==enemy)
   I.pick=function() return spear end;I.tap(g,0,0,false);assert(not g.inspectTarget)
   assert(I.doubleSelect(g,0,0));local count=0
   for id in pairs(g.selection) do count=count+1;assert(s.entities[id].kind=='spear' and id~=far.id) end
   assert(count==6)
  end)
  I.pick,R.unproject,input=priorPick,priorProject,priorInput;assert(ok,err)
 end)
 test('清场才能跳波，最后一波不可跳，存档不重复派发',function()
  local s=S.new(73);assert(Camp.skipWave(s));Camp.beforeStep(s,.1)
  assert(s.campaign.event.wave==1 and not Camp.canSkipWave(s))
  local q=Save.restore(Save.snapshot(s));local ev=q.campaign.event
  assert(ev.wave==1 and ev.pendingViruses==s.campaign.event.pendingViruses)
  ev.pendingViruses=0;ev.spawnQueue={};for id,e in pairs(q.entities) do if e.faction==2 then q.entities[id]=nil end end
  assert(Camp.skipWave(q));Camp.beforeStep(q,.1);assert(ev.wave==2)
  ev.wave=#N.forState(q).waves;assert(not Camp.canSkipWave(q))
 end)
 test('出口需要通关和半数部队，未开放地图不能进入',function()
  local s=S.new(73);local trigger=Registry.transitionTargets('trachea_01')[1];local ids={}
  for id in pairs(s.entities) do ids[#ids+1]=id end;table.sort(ids)
  local function inside(e) e.x,e.y=trigger.x+trigger.w*.5,trigger.y+trigger.h*.5 end
  for _,id in ipairs(ids) do inside(s.entities[id]) end
  assert(not Level.find(s));complete(s)
  for _,id in ipairs(ids) do local e=s.entities[id];e.x,e.y=N.forState(s).home.x,N.forState(s).home.y end
  for i=1,3 do inside(s.entities[ids[i]]) end;assert(not Level.find(s))
  inside(s.entities[ids[4]]);assert(Level.find(s)==trigger)
  assert(not S.changeMap(s,'blood_01'))
 end)
 test('换地图保留兵力血量和进度，清除旧路线，出生无重叠',function()
  local s=S.new(73);complete(s);s.time=35;s.tick=350
  local old={};for id,e in pairs(s.entities) do e.hp=e.maxHp-7;e.longRoute={points={{x=e.x,y=e.y}},index=1};e.pathGoal={x=e.x,y=e.y};e.returning=true;e.delivering=true;old[id]=U.copy(e) end
  local q,err=S.changeMap(s,'lungs_01');assert(q,err)
  assert(q.time==35 and q.tick==350 and q.campaign.completed.trachea_01 and q.campaign.visited_maps.lungs_01)
  assert(q.factions[1].stock.relic==1)
  local units=require('war.CellCollision').units(q)
  for id,e in pairs(q.entities) do
   assert(old[id] and old[id].hp==e.hp and old[id].kind==e.kind)
   assert(N.forState(q).allowed(e.x,e.y) and e.vesselLane==0)
   assert(#e.orders==0 and #e.path==0 and not e.pathGoal and not e.longRoute and not e.returning and not e.delivering)
   assert(require('war.CellCollision').free(units,e,e.x,e.y))
  end
  local restored=Save.restore(Save.snapshot(q));assert(restored.campaign.map_id=='lungs_01')
  for id,e in pairs(q.entities) do assert(restored.entities[id].hp==e.hp) end
 end)
 test('换地图控制器完成后镜头有效，清空旧敌方资料卡',function()
  local s=S.new(73);complete(s)
  local R=require('war.Render');local previous=R.prepare;R.prepare=function() end
  local g={state=s,started=true,paused=false,selection={},inspectTarget={hp=100},camera={x=0,y=0},zoom=1}
  Level.request(g,Registry.transitionTargets('trachea_01')[1]);local ok,err=pcall(Level.update,g,.3);R.prepare=previous;assert(ok,err)
  assert(type(g.camera.x)=='number' and type(g.camera.y)=='number' and not g.inspectTarget)
  Level.update(g,.4);assert(not g.transition and not g.paused)
 end)
 test('双肺三波28只病毒正确分区，失败区域为左右肺',function()
  local s=assert(S.changeMap(S.new(73),'lungs_01'));s.entities={};W.rebuild(s)
  for _=1,1400 do Camp.beforeStep(s,.1) end
  local count=0;for _,e in pairs(s.entities) do count=count+1;assert(e.viralZone>=1 and e.viralZone<=3 and N.forState(s).allowed(e.x,e.y)) end
  assert(count==28 and s.campaign.event.pendingViruses==0)
  local ev=s.campaign.event;ev.zones[1].control=-100;Camp.afterStep(s,0);assert(ev.status=='active')
  ev.zones[2].control=-100;Camp.afterStep(s,0);assert(ev.status=='failed')
 end)
 test('出生暂时失败不丢失待派发病毒',function()
  local s=S.new(73);local previous=C.spawn;C.spawn=function() return nil end
  local ok,err=pcall(Camp.beforeStep,s,10);C.spawn=previous;assert(ok,err)
  local ev=s.campaign.event;assert(ev.pendingViruses==6 and #ev.spawnQueue==6)
  Camp.beforeStep(s,.1);assert(ev.pendingViruses==5 and #ev.spawnQueue==5)
 end)
 local passed=0;for _,r in ipairs(results) do if r.pass then passed=passed+1 end end
 return {passed=passed,total=#results,results=results}
end
return Q
