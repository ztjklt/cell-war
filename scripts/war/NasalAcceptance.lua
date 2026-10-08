-- Historical anatomy-v2 fixtures are explicit; ReferenceAcceptance covers the new default.
-- Isolated Lua regression: never writes live cloud slots or changes a game window.
local Sim,C,W,U,T,Camp,Save,R,N=require("war.Simulation"),require("war.Commands"),require("war.World"),require("war.Util"),require("war.Territory"),require("war.Campaign"),require("war.Save"),require("war.Reinforcements"),require("war.LegacyCampaignData")
local Q={}
local function expect(v,message) assert(v,message) end
local function advance(s,n) for _=1,n do Sim.step(s,.1) end end
local function empty() local s=Sim.new(73,"campaign",2);s.entities={};W.rebuild(s);return s end
function Q.run()
 local results={};local function test(name,fn) local ok,err=pcall(fn);results[#results+1]={name=name,pass=ok,error=ok and "" or tostring(err)} end
 test("开局兵力、资源与鼻腔连通",function()
  for _,seed in ipairs({11,73,101,999,654321}) do
   local s=Sim.new(seed,"campaign",2);local white,platelet=0,0
   for _,e in pairs(s.entities) do expect(e.faction==1 and W.walkable(s,math.floor(e.x),math.floor(e.y),1),"invalid spawn");if e.kind=="spear" then white=white+1 elseif e.kind=="scout" then platelet=platelet+1 end end
   expect(white==6 and platelet==2 and next(s.resources)==nil,"starter roster")
   for _,z in ipairs(N.zones) do expect(W.walkable(s,math.floor(z.x),math.floor(z.y),1),"blocked region destination") end
   expect(s.campaign.terrainVersion==2 and #W.vessels(s).gates==5,"missing vascular terrain")
   expect(s.campaign.event.zones[1].owner==2 and s.campaign.event.zones[3].owner==1,"ownership")
  end
 end)
 test("单人40秒翻转与中立阶段",function()
  local s=empty();C.spawn(s,"unit","spear",1,N.zones[1].x,N.zones[1].y)
  for _=1,200 do T.update(s,.1) end
  expect(math.abs(s.campaign.event.zones[1].control)<.00001 and s.campaign.event.zones[1].owner==0,"neutralization")
  for _=1,200 do T.update(s,.1) end
  expect(s.campaign.event.zones[1].control==100 and s.campaign.event.zones[1].owner==1,"capture time")
 end)
 test("三人20秒翻转、速度封顶",function()
  local s=empty();for i=1,5 do C.spawn(s,"unit","spear",1,N.zones[1].x+i*2,N.zones[1].y) end
  for _=1,199 do T.update(s,.1) end;expect(s.campaign.event.zones[1].control==99,"capture rate")
  T.update(s,.1);expect(s.campaign.event.zones[1].control==100,"capture cap")
 end)
 test("双方暂停、无人保留与死亡不计数",function()
  local s=empty();local f=C.spawn(s,"unit","spear",1,N.zones[1].x,N.zones[1].y-2);local h=C.spawn(s,"unit","virus",2,N.zones[1].x+5,N.zones[1].y-2)
  T.update(s,20);expect(s.campaign.event.zones[1].control==-100 and s.campaign.event.zones[1].contested,"contest")
  h.hp=0;T.update(s,2);expect(s.campaign.event.zones[1].control==-90,"dead virus counted")
  f.hp=0;T.update(s,10);expect(s.campaign.event.zones[1].control==-90 and not s.campaign.event.zones[1].contested,"empty decay")
 end)
 test("完整失守触发失败、胜败同帧优先失败",function()
  local s=empty();local ev=s.campaign.event;ev.wave=3;ev.secure=19.9
  C.spawn(s,"unit","virus",2,N.zones[3].x,N.zones[3].y);ev.zones[3].control=-99
  Camp.afterStep(s,.1);expect(ev.status=="active","partial capture failed")
  Camp.afterStep(s,.1);expect(ev.status=="failed" and s.outcome=="defeat" and not s.campaign.completed.nasal,"failure priority")
  local time=s.time;advance(s,10);expect(s.time==time,"defeat continued")
 end)
 test("调援执行校验、重复请求与预留人口",function()
  local s=Sim.new(73,"campaign",2);C.submit(s,{kind="reinforce",faction=1});C.submit(s,{kind="reinforce",faction=1})
  expect(s.campaign.reinforcements.supply==4,"paused request spent supply")
  C.process(s);expect(s.campaign.reinforcements.supply==2 and #s.campaign.reinforcements.queue==1,"duplicate charge")
  expect(R.population(s)==10,"reservation")
  advance(s,31);expect(R.population(s)==10 and #s.campaign.reinforcements.queue==0,"arrival")
  for _,e in pairs(s.entities) do expect(Camp.allowed(s,e.x,e.y),"reinforcement escaped") end
  local r=s.campaign.reinforcements;r.cooldown=0;r.supply=6
  for i=1,30 do C.spawn(s,"unit","spear",1,1200+(i%10)*3,450+math.floor(i/10)*3) end
  expect(not R.request(s) and r.supply==6,"population exceeded")
  r.supply=1;expect(not R.request(s),"missing supply")
 end)
 test("补给回复、暂停与固定模拟时间",function()
  local a,b=Sim.new(73,"campaign",2),Sim.new(73,"campaign",2);a.campaign.reinforcements.supply=0;b.campaign.reinforcements.supply=0
  advance(a,100);for _=1,50 do Sim.step(b,.1);Sim.step(b,.1) end
  expect(a.campaign.reinforcements.supply==1 and b.campaign.reinforcements.supply==1,"time scaling")
  expect(a.time==b.time,"fixed steps")
 end)
 test("锁区检查覆盖命令、寻路、出生和建造",function()
  local s=Sim.new(73,"campaign",2);local id=next(s.entities);local e=s.entities[id]
  expect(not C.execute(s,{kind="move",faction=1,ids={id},x=1024,y=1800}),"locked move")
  expect(not C.execute(s,{kind="build",faction=1,ids={id},building="core",x=N.home.x,y=N.home.y}),"construction opened")
  expect(C.spawn(s,"unit","spear",1,1024,1800)==nil,"locked spawn")
  require("war.Path").request(s,e,1024,1800);expect(e.pathFailed and #e.path==0,"locked path")
  expect(not W.land(s,1024,1800) and not W.canBuild(s,"core",N.home.x,N.home.y,1),"locked land")
  C.execute(s,{kind="retreat",faction=1,ids={id}})
  ---@type table[]
  local orders=e.orders
  expect(orders[1].kind=="move" and orders[1].x==N.home.x,"retreat")
 end)
 test("三波有限入侵且无需经营",function()
  local s=Sim.new(73,"campaign",2);advance(s,1100)
  expect(s.campaign.event.wave==3 and s.campaign.event.pendingViruses==0,"wave dispatch")
  for _,e in pairs(s.entities) do expect(e.category=="unit" and e.satiety==100 and e.temp==22 and e.sanity==100,"survival leaked") end
  expect(not s.factions[2].lost and next(s.resources)==nil,"sandbox logic leaked")
 end)
 test("进攻寻路连接三个区域",function()
  local s=empty();local e=C.spawn(s,"unit","scout",1,N.home.x,N.home.y)
  expect(C.execute(s,{kind="move",faction=1,ids={e.id},x=N.entry.x,y=N.entry.y}),"move refused")
  -- No waves for this geometric test; still run the real path and collision code.
  for _=1,1200 do s.time=s.time+.1;W.rebuild(s);require("war.Path").update(s,500);require("war.Workers").update(s,e,.1) end
  expect(U.dist(e,N.entry)<2 and not e.pathFailed,"nasal route unreachable")
 end)
 test("战斗存读档不重复波次或援军",function()
  local s=Sim.new(73,"campaign",2);advance(s,480);C.execute(s,{kind="reinforce",faction=1})
  local snap=Save.snapshot(s);expect(snap.campaign.checkpoint and not snap.campaign.checkpoint.campaign.checkpoint,"recursive checkpoint")
  local q=Save.restore(snap);expect(q.campaign.event.wave==2 and q.campaign.reinforcements.supply==s.campaign.reinforcements.supply and #q.campaign.reinforcements.queue==1,"round trip")
  advance(s,400);advance(q,400)
  expect(q.campaign.event.wave==s.campaign.event.wave and q.nextId==s.nextId and #q.campaign.reinforcements.queue==0 and q.campaign.reinforcements.supply==s.campaign.reinforcements.supply,"duplicate dispatch")
 end)
 test("失败重试恢复世界且此前记录保持",function()
  local s=Sim.new(73,"campaign",2);s.campaign.completed.prior=true;s.campaign.unlocked.prior=true;Camp.checkpoint(s)
  advance(s,480);Camp.fail(s);local q=Camp.retry(Save.restore(Save.snapshot(s)))
  expect(q.time==0 and q.campaign.event.status=="active" and q.campaign.event.wave==0 and R.population(q)==8 and q.campaign.reinforcements.supply==4,"retry mismatch")
  expect(q.campaign.completed.prior and q.campaign.unlocked.prior,"prior progress lost")
  expect(q.campaign.checkpoint and not q.campaign.checkpoint.campaign.checkpoint,"retry recursion")
 end)
 test("胜利20秒稳固、奖励仅一次、后续不开空关",function()
  local s=empty();local ev=s.campaign.event;ev.wave=3
  for _,z in ipairs(ev.zones) do z.control=100;z.owner=1 end
  for _=1,199 do Camp.afterStep(s,.1) end;expect(ev.status=="active","early victory")
  Camp.afterStep(s,.1);expect(ev.status=="completed" and s.campaign.stage==2 and s.campaign.awaitingContent,"completion")
  local reward=s.factions[1].stock.relic;Camp.succeed(s);expect(s.factions[1].stock.relic==reward and reward==1,"double reward")
  expect(not Camp.start(s,"throat") and #Camp.randomCandidates(s)==0 and not s.campaign.unlocked.throat,"empty encounter")
  local q=Save.restore(Save.snapshot(s));expect(q.campaign.completed.nasal and q.campaign.stage==2,"completion persistence")
 end)
 test("损坏战役数据保留拒绝语义",function()
  local snap=Save.snapshot(Sim.new(73,"campaign",2));snap.campaign.event.zones[3].control=0/0;expect(not pcall(Save.restore,snap),"NaN accepted")
  snap=Save.snapshot(Sim.new(73,"campaign",2));snap.campaign.checkpoint.campaign.checkpoint={};expect(not pcall(Save.restore,snap),"nested checkpoint accepted")
  snap=Save.snapshot(Sim.new(73,"campaign",2));snap.campaign=nil;expect(not pcall(Save.restore,snap),"campaign vanished")
 end)
 test("v5沙盒往返保持三阵营和人体地形",function()
  local s=Sim.new(73,"sandbox",1);local snap=Save.snapshot(s);snap.version=5;snap.mode=nil
  local q=Save.restore(snap);expect(not q.campaign and q.mode=="sandbox" and q.mapWidth==2048,"legacy mode")
  expect(W.terrain(q,1190,472)==W.terrain(s,1190,472),"legacy terrain changed")
  advance(q,20);local r=Save.restore(Save.snapshot(q));expect(not r.campaign and r.tick==20,"legacy resave")
 end)
 local passed=0;for _,r in ipairs(results) do if r.pass then passed=passed+1 end end
 return {passed=passed,total=#results,results=results}
end
return Q
