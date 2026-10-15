-- Isolated Lua 5.4 regressions; never loaded by the game entry point.
local D,U,W,C,F,E=require("war.Data"),require("war.Util"),require("war.World"),require("war.Commands"),require("war.Combat"),require("war.Economy")
local K,Status,Organs,Events=require("war.CombatConfig"),require("war.CombatStatus"),require("war.OrganRules"),require("war.CombatEvents")
local QA={}
local function expect(ok,message) assert(ok,message) end
local function near(a,b) return math.abs(a-b)<.00001 end
local function fixture()
 local s=W.generate(131,nil,"continent","sandbox",1);s.entities={};s.resources={};s.newChunks={}
 for y=80,140 do for x=80,140 do s.tiles[U.key(x,y)]=1;for _,fa in ipairs(s.factions) do fa.visible[U.key(x,y)]=true;fa.seen[U.key(x,y)]=true end end end
 W.rebuild(s);return s
end
local function unit(s,kind,f,x,y) local e=C.spawn(s,"unit",kind,f,x or 100,y or 100);W.rebuild(s);expect(e,"spawn failed");return e end
local function area(s,biome) for y=80,140 do for x=80,140 do s.tiles[U.key(x,y)]=biome end end end
function QA.run()
 local results={};local function test(name,fn) local ok,err=pcall(fn);results[#results+1]={name=name,pass=ok,error=ok and "" or tostring(err)} end
 test("独立角色与待定角色",function()
  expect(D.units.spear.hp==150 and D.units.neutrophil.hp==4,"legacy health changed")
  expect(D.units.herpes.speed<D.units.spear.speed*.2,"herpes is not slow")
  expect(not D.units.cancer_agile and not K.pendingRoles.cancer_agile.enabled,"invented cancer stats")
 end)
 test("两次独立碰撞倒下且持续接触不连伤",function()
  local s=fixture();local a=unit(s,"herpes",2);local b=unit(s,"neutrophil",1,101.27,100)
  F.contacts(s,a);expect(b.hp==2 and b.x>101.27,"first collision or knockback")
  b.x,b.y=101.27,100;W.rebuild(s);F.contacts(s,a);expect(b.hp==2,"repeated contact damage")
  b.x=105;W.rebuild(s);F.contacts(s,a);s.time=2;b.x=101.27;W.rebuild(s);F.contacts(s,a)
  expect(b.hp==0,"second collision should kill")
 end)
 test("碰撞固定伤害不受攻击增益影响",function()
  local s=fixture();local a=unit(s,"herpes",2);local b=unit(s,"neutrophil",1,101.27,100);s.factions[2].tech.weapons=true;Status.apply(s,a,"attack_boost")
  F.contacts(s,a);expect(b.hp==2,"collision damage was amplified")
 end)
 test("飞行物延迟结算且死亡来源仍能命中",function()
  local s=fixture();local a=unit(s,"herpes",2);local b=unit(s,"neutrophil",1,105,100)
  F.fight(s,a,b,.1,false);expect(b.hp==4 and #s.combatProjectiles==1,"instant projectile damage")
  s.entities[a.id]=nil
  for _=1,8 do F.updateProjectiles(s,.1) end
  expect(b.hp==3 and #s.combatProjectiles==0,"projectile did not hit")
 end)
 test("飞行物可躲避且不误伤非目标角色",function()
  local s=fixture();local a=unit(s,"herpes",2);local b=unit(s,"neutrophil",1,105,100);local red=unit(s,"worker",1,103,100)
  F.fight(s,a,red,.1,false);expect(not s.combatProjectiles,"shot non-neutrophil")
  F.fight(s,a,b,.1,false);b.y=103;W.rebuild(s)
  for _=1,35 do F.updateProjectiles(s,.1) end
  expect(b.hp==4 and red.hp==red.maxHp and #s.combatProjectiles==0,"undodgeable or wrong-target projectile")
 end)
 test("飞行物与击退不能穿墙",function()
  local s=fixture();local a=unit(s,"herpes",2);local b=unit(s,"neutrophil",1,105,100)
  F.fight(s,a,b,.1,false);for y=80,140 do s.tiles[U.key(103,y)]=14 end
  for _=1,15 do F.updateProjectiles(s,.1) end
  expect(b.hp==4,"projectile crossed wall")
  b.x=102;W.rebuild(s);F.knockback(s,a,b,5);expect(b.x<103,"knockback crossed wall")
 end)
 test("幽门螺杆菌复用近战冷却",function()
  local s=fixture();local a=unit(s,"helicobacter",2);local b=unit(s,"neutrophil",1,101.3,100)
  F.fight(s,a,b,.1,false);expect(b.hp==3,"melee damage");F.fight(s,a,b,.1,false);expect(b.hp==3,"cooldown ignored")
  local events=Events.since(s,0);expect(events[#events].attackStyle=="flagellum","missing presentation style")
 end)
 test("增益只提高攻击且同类区域不叠加",function()
  local s=fixture();local a=unit(s,"spear",1);local b=unit(s,"virus",2,102,100)
  for i=1,2 do local building=C.spawn(s,"building","clinic",1,98,98+i,true);building.attackAura=true end
  W.rebuild(s);local max=a.maxHp;F.hit(s,a,b,10);expect(near(b.hp,87.5) and a.maxHp==max,"aura stacked or health increased")
  a.x=120;W.rebuild(s);F.hit(s,a,b,10);expect(near(b.hp,77.5),"aura persists outside")
 end)
 test("毒素、减速与到期移除",function()
  local s=fixture();local b=unit(s,"worker",1);Status.apply(s,b,"toxin",{duration=.25});Status.apply(s,b,"slow",{duration=.1})
  Status.update(s,b,.1);expect(not b.statuses.slow and near(b.hp,b.maxHp-.1),"status first step")
  Status.update(s,b,.2);expect(not b.statuses.toxin and near(b.hp,b.maxHp-.25),"toxin exceeded duration")
 end)
 test("肾外营地与旧修复腺均不回血",function()
  local s=fixture();local b=unit(s,"worker",1);C.spawn(s,"building","core",1,100,102,true);C.spawn(s,"building","clinic",1,100,103,true);W.rebuild(s)
  b.hp=50;require("war.Survival").update(s,1);Organs.update(s,b,1);expect(b.hp==50,"outside kidney healed")
 end)
 test("肾脏先清毒和疲劳再恢复，离开重置进度",function()
  local s=fixture();local b=unit(s,"worker",1);area(s,24);b.hp=50;b.impurities=3;Status.apply(s,b,"toxin");Status.apply(s,b,"fatigue")
  Organs.update(s,b,1);expect(b.hp==50 and b.statuses.toxin,"early cleanse")
  area(s,1);Organs.update(s,b,.1);area(s,24);Organs.update(s,b,1);expect(b.hp==50,"progress persisted outside")
  Organs.update(s,b,1);expect(not b.statuses.toxin and not b.statuses.fatigue and b.impurities==0,"cleanse failed")
  Organs.update(s,b,1);expect(near(b.hp,51.1),"kidney healing")
 end)
 test("肠道统一减速、非肠道无区域减速",function()
  local s=fixture();local b=unit(s,"worker",1);area(s,11);expect(Organs.moveMultiplier(s,b)==K.intestine.moveMultiplier,"small intestine speed")
  area(s,25);expect(Organs.moveMultiplier(s,b)==K.intestine.moveMultiplier,"large intestine speed")
  area(s,1);expect(Organs.moveMultiplier(s,b)==1,"outside speed")
 end)
 test("来源葡萄糖消费和腐败不会留下虚假额度",function()
  local s=fixture();s.factions[1].food={};E.add(s,1,"food",20);E.add(s,1,"food",20,"stomach")
  expect(E.stomachGlucose(s,1)==20,"source lost")
  expect(E.pay(s,1,{food=12},true) and E.stomachGlucose(s,1)==8 and E.food(s,1)==28,"source payment")
  s.time=D.DAY*4;E.spoil(s);expect(E.stomachGlucose(s,1)==0,"spoiled source remained")
 end)
 test("强力细胞训练限制与心脏转运前置条件",function()
  local s=fixture();local b=unit(s,"heavy",1);expect(not Organs.canTrain(s,"heavy",100,100),"training outside liver")
  area(s,9);expect(Organs.canTrain(s,"heavy",100,100),"liver training rejected")
  b.requiresHeart=true;s.tiles[U.key(120,100)]=1
  expect(not Organs.canLeaveLiver(s,b,120,100),"direct liver exit")
  expect(not Organs.transfer(s,b,120,100),"transfer outside heart")
 end)
 test("明确攻击目标优先于附近敌人",function()
  local s=fixture();local a=unit(s,"spear",1);local nearby=unit(s,"virus",2,101.5,100);local target=unit(s,"virus",2,100,101.8)
  C.order(s,a,{kind="attack",target=target.id});require("war.Workers").update(s,a,.1)
  expect(target.hp<target.maxHp and nearby.hp==nearby.maxHp,"focus fire hijacked")
 end)
 test("死亡目标不能重复伤害或领取奖励",function()
  local s=fixture();local a=unit(s,"spear",1);local b=C.spawn(s,"building","nest",0,105,100,true);b.hp=1
  F.hit(s,a,b,10);local stock=E.stock(s,1,"relic");expect(stock==0 and not s.factions[1].stock.relic,"suspended kill reward")
  expect(not F.hit(s,a,b,10) and E.stock(s,1,"relic")==stock,"duplicate kill")
 end)
 test("事件多消费者与有界缓存",function()
  local s=fixture();for i=1,K.eventsLimit+2 do Events.emit(s,"test",{value=i}) end
  local a,cursor,gap=Events.since(s,0);local b=Events.since(s,0);expect(#a==K.eventsLimit and #b==#a and gap,"stream destructive or unbounded")
  a[1].value=-1;expect(b[1].value~=-1,"consumer changed stream");expect(#Events.since(s,cursor)==0,"cursor replay")
 end)
 test("飞行物状态与疲劳存档往返",function()
  local s=fixture();local a=unit(s,"herpes",2);local b=unit(s,"neutrophil",1,105,100);Status.apply(s,b,"fatigue");F.fight(s,a,b,.1,false)
  local Save=require("war.Save");local copy=Save.restore(Save.snapshot(s))
  expect(copy.entities[b.id].statuses.fatigue and #copy.combatProjectiles==1,"combat save dropped state")
  for y=80,140 do for x=80,140 do copy.tiles[U.key(x,y)]=1 end end
  for _=1,8 do F.updateProjectiles(copy,.1) end
  expect(copy.entities[b.id].hp<4,"restored projectile failed")
 end)
 test("增益设施需胃部来源，完工后建造者疲劳",function()
  local s=fixture();local red=unit(s,"worker",1);s.factions[1].tier=3
  expect(not C.execute(s,{kind="build",faction=1,building="clinic",x=105,y=105,ids={red.id}}),"ordinary food built aura")
  E.add(s,1,"food",K.aura.stomachGlucoseCost,"stomach")
  local ok,id=C.execute(s,{kind="build",faction=1,building="clinic",x=105,y=105,ids={red.id}})
  expect(ok and E.stomachGlucose(s,1)==0,"stomach cost")
  local b=s.entities[id];expect(b.attackAura and not b.complete,"facility state")
  red.x,red.y=103.5,105;b.progress=.9999;W.rebuild(s);require("war.Workers").update(s,red,.1)
  expect(b.complete and red.statuses.fatigue,"construction did not fatigue builder")
 end)
 test("取消增益设施按比例返还胃部来源",function()
  local s=fixture();local red=unit(s,"worker",1);s.factions[1].tier=3;E.add(s,1,"food",20,"stomach")
  local ok,id=C.execute(s,{kind="build",faction=1,building="clinic",x=105,y=105,ids={red.id}});expect(ok,"facility rejected")
  C.execute(s,{kind="cancel",target=id,faction=1});expect(E.stomachGlucose(s,1)==15,"source refund lost")
 end)
 test("真实器官几何与心脏安全落点接口",function()
  local s=W.generate(131,nil,"body","sandbox",3);s.entities={};s.newChunks={};W.rebuild(s)
  local map=require("war.ReferenceMap")
  local function position(id)
   local organ=map.byId[id]
   for y=math.ceil(organ.y1),organ.y2,2 do for x=math.ceil(organ.x1),organ.x2,2 do if Organs.at(s,x+.5,y+.5)==id and W.walkable(s,x,y,1) then return x+.5,y+.5 end end end
   error("no safe organ cell")
  end
  local hx,hy=position("heart");local kx,ky=position("kidney_r");local lx,ly=position("liver")
  expect(Organs.isKidney(Organs.at(s,kx,ky)) and Organs.canTrain(s,"heavy",lx,ly),"organ identification")
  local e=unit(s,"heavy",1,hx,hy);e.requiresHeart=true
  expect(Organs.transfer(s,e,kx,ky) and not e.requiresHeart and Organs.isKidney(Organs.at(s,e.x,e.y)),"heart transfer failed")
  expect(not Organs.transfer(s,e,lx,ly),"repeat transfer outside heart")
 end)
 test("状态机事件不在持续移动时反复空闲切换",function()
  local s=fixture();local e=unit(s,"worker",1);C.order(s,e,{kind="move",x=115,y=100})
  local Sim=require("war.Simulation");for _=1,5 do Sim.step(s,.1) end
  local count=0;for _,event in ipairs(Events.since(s,0)) do if event.kind=="state" and event.target==e.id and event.to=="moving" then count=count+1 end end
  expect(count==1 and e.combatState=="moving","spurious moving transitions")
 end)
 test("肠道新生成葡萄糖资源产出提高",function()
  local s=fixture();s.resources={};s.generated={};s.newChunks={};area(s,11)
  for cy=3,3 do for cx=3,3 do W.ensureChunk(s,cx,cy) end end
  local found=false;for _,r in pairs(s.resources) do if r.kind=="food" and Organs.isIntestine(Organs.at(s,r.x,r.y)) then found=true;expect(r.max==85*K.intestine.glucoseMultiplier,"intestine quantity") end end
  expect(found,"no intestine glucose generated")
 end)
 test("损坏新增战斗存档被拒绝",function()
  local s=fixture();local e=unit(s,"worker",1);Status.apply(s,e,"fatigue");local Save=require("war.Save");local snap=Save.snapshot(s)
  snap.entities[tostring(e.id)].statuses.fatigue.moveMultiplier="broken";expect(not pcall(Save.restore,snap),"corrupt status accepted")
  snap=Save.snapshot(s);snap.combatProjectiles="broken";expect(not pcall(Save.restore,snap),"corrupt projectiles accepted")
 end)
 return results
end
return QA
