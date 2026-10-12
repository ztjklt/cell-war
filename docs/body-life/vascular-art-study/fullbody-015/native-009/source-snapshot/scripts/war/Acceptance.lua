-- Historical anatomy-v2 fixtures are explicit; ReferenceAcceptance covers the new default.
-- Pure Lua regression suite. Does not access live accounts, cloud or game windows.
-- Run with Lua 5.4; call require('war.Acceptance').run() from an isolated runtime.
local D,U,W,E,C,P,Sim,V,Save,A,F=require("war.Data"),require("war.Util"),require("war.World"),require("war.Economy"),require("war.Commands"),require("war.Path"),require("war.Simulation"),require("war.Survival"),require("war.Save"),require("war.AI"),require("war.Combat")
local QA={}
local B=D.factions[1]
local function expect(ok,text) if not ok then error(text,2) end end
local function advance(s,n) for _=1,n do Sim.step(s,.1) end end
local function worker(s,f) return U.nearest(s,D.factions[f].x,D.factions[f].y,function(e) return e.faction==f and e.kind=="worker" end) end
local function pad(s,kind,f)
 local b=D.factions[f];local offset=D.buildings[kind].size%2==0 and 0 or .5
 for r=4,14 do for y=b.y-r,b.y+r do for x=b.x-r,b.x+r do if W.canBuild(s,kind,x+offset,y+offset,f) then return x+offset,y+offset end end end end
 error("no free build pad")
end
function QA.run()
 local results={};local function test(name,fn) local ok,err=pcall(fn);results[#results+1]={name=name,pass=ok,error=ok and "" or tostring(err)} end
 test("随机种子与出生资源",function()
  local s=Sim.new(104729,"sandbox",2);local q=Sim.new(104729,"sandbox",2)
  expect(s.mapWidth==2048 and s.mapHeight==4096 and s.chunkStride==64 and s.chunkRows==128,"map size")
  for y=1,D.MAP_HEIGHT,127 do for x=1,D.MAP,127 do expect(W.terrain(s,x,y)==W.terrain(q,x,y),"seed must reproduce terrain") end end
  for f,v in ipairs(D.factions) do
   expect(W.walkable(s,v.x-4,v.y+4,f),"spawn must be traversable")
   for _,kind in ipairs({"food","wood","stone"}) do local found=false;for _,r in pairs(s.resources) do if r.kind==kind and U.dist(v,r)<15 then found=true end end;expect(found,"missing starter resource") end
  end
 end)
 test("暂停队列与执行时资源检查",function()
  local s=Sim.new(101,"sandbox",2);local u=worker(s,1);local x,y=pad(s,"house",1);local wood=s.factions[1].stock.wood
  C.submit(s,{kind="build",faction=1,building="house",x=x,y=y,ids={u.id}})
  expect(s.time==0 and s.factions[1].stock.wood==wood and E.count(s,1,"house")==0,"queued action changed paused state")
  s.factions[1].stock.wood=0;C.process(s);expect(E.count(s,1,"house")==0,"unaffordable queued construction accepted")
  s.factions[1].stock.wood=wood;expect(C.execute(s,{kind="build",faction=1,building="house",x=x,y=y,ids={u.id}}),"build rejected")
  expect(s.factions[1].stock.wood==wood-30,"incorrect resource charge");advance(s,900)
  local b=U.nearest(s,x,y,function(e) return e.kind=="house" and e.faction==1 end);expect(b.complete,"worker failed to reach construction range")
  expect(not W.walkable(s,math.floor(b.x),math.floor(b.y),1),"building did not block path")
 end)
 test("采集、运输、枯竭与取消退款",function()
  local s=Sim.new(102,"sandbox",2);local u=worker(s,1);local key=U.key(B.x+6,B.y-1);local before=E.stock(s,1,"wood")
  expect(C.execute(s,{kind="gather",faction=1,ids={u.id},target=key}),"gather rejected");advance(s,900)
  expect(E.stock(s,1,"wood")>before,"cargo never delivered")
  local x,y=pad(s,"house",1);local wood=E.stock(s,1,"wood")
  local ok,id=C.execute(s,{kind="build",faction=1,building="house",x=x,y=y,ids={u.id}});expect(ok,"build failed")
  C.execute(s,{kind="cancel",faction=1,target=id});expect(E.stock(s,1,"wood")==wood-30+22,"refund mismatch")
 end)
 test("人口限制、训练与研究",function()
  local s=Sim.new(103,"sandbox",2);local core=U.nearest(s,B.x,B.y,function(e) return e.faction==1 and e.kind=="core" end)
  expect(C.execute(s,{kind="train",faction=1,target=core.id,unit="worker"}),"first worker rejected")
  expect(not C.execute(s,{kind="train",faction=1,target=core.id,unit="worker"}),"queued population not reserved")
  advance(s,180);expect(E.population(s,1,false)==10,"unit failed to train")
  C.spawn(s,"building","house",1,B.x-7,B.y-8,true);local lab=C.spawn(s,"building","lab",1,B.x-6,B.y-3,true)
  expect(C.execute(s,{kind="research",faction=1,target=lab.id,tech="tier2"}),"research rejected")
  advance(s,750);expect(s.factions[1].tier==2,"tier not unlocked")
  local edge=C.spawn(s,"building","core",1,D.MAP-1.5,D.MAP-1.5,true);edge.rally={x=D.MAP-1.5,y=D.MAP-1.5};W.rebuild(s)
  edge.queue={{unit="worker",remaining=0,total=16,cost={wood=12,food=8}}};require("war.Production").update(s,.1)
  expect(#edge.queue==1,"production created a cell in deep water")
  for y=D.MAP-8,D.MAP-1 do for x=D.MAP-8,D.MAP-1 do s.tiles[U.key(x,y)]=1 end end
  require("war.Production").update(s,.1)
  expect(#edge.queue==0,"edge production remained blocked despite free terrain")
  for _,e in pairs(s.entities) do expect(e.x<=D.MAP and e.y<=D.MAP_HEIGHT,"unit spawned beyond map edge") end
 end)
 test("稳态周期、腐败、饥饿与荧光",function()
  local s=Sim.new(104,"sandbox",2);for i=1,4 do s.time=(i-1)*8*360;expect(select(3,V.clock(s))==i,"season mismatch") end
  s.time=4*8*360;expect(select(3,V.clock(s))==1,"season does not repeat")
  s.time=4*360;E.spoil(s);expect(E.food(s,1)==0,"expired food retained")
  E.add(s,1,"food",10);s.factions[1].tech.storage=true;s.time=s.time+4*360;E.spoil(s);expect(E.food(s,1)==10,"storage did not preserve food")
  local u=worker(s,1);u.satiety=0;u.x,u.y=B.x+38,B.y-6;u.hp=90;s.factions[1].food={};V.update(s,1);expect(u.hp<90,"hunger did not damage")
  s.time=300;local fire=U.nearest(s,B.x,B.y,function(e) return e.faction==1 and e.kind=="fire" end);u.x,u.y=fire.x,fire.y;u.sanity=50;u.satiety=80;V.update(s,1);expect(u.sanity>50,"light did not restore sanity")
  u.temp=22;for _=1,360 do V.update(s,1) end;expect(u.temp<35,"autumn campfire caused overheating")
  u.x,u.y=B.x+38,B.y-6;u.sanity=0;s.time=300
  for _=1,42 do V.update(s,1) end;expect(E.count(s,0,"shadow")>0,"low sanity did not create a threat")
  s.time=7000;u.wet=0;V.update(s,10);expect(u.wet>0,"spring rain did not cause wetness")
 end)
 test("培养床、灼伤处理与维修",function()
  local s=Sim.new(105,"sandbox",2);local u=worker(s,1);local b=C.spawn(s,"building","farm",1,B.x-2,B.y+8,true);u.x,u.y=B.x-2,B.y+9;s.factions[1].food={};W.rebuild(s)
  C.execute(s,{kind="farm",faction=1,ids={u.id},target=b.id});advance(s,250);expect(E.food(s,1)==0 and u.cargo.food==8,"farm bypassed hauling")
  advance(s,70);expect(E.food(s,1)>0,"farm harvest never delivered")
  b.fire=1;C.execute(s,{kind="extinguish",faction=1,ids={u.id},target=b.id});advance(s,80);expect(b.fire==0,"fire not extinguished")
  b.hp=80;C.execute(s,{kind="repair",faction=1,ids={u.id},target=b.id});advance(s,120);expect(b.hp>80,"repair ineffective")
 end)
 test("不可达寻路与目标失效",function()
  local s=Sim.new(106,"sandbox",2);local u=worker(s,1)
  for y=B.y+2,B.y+7 do for x=B.x-4,B.x+1 do if x==B.x-4 or x==B.x+1 or y==B.y+2 or y==B.y+7 then C.spawn(s,"building","wall",1,x+.5,y+.5,true) end end end
  u.x,u.y=B.x-1.5,B.y+4.5;W.rebuild(s);P.request(s,u,B.x+18,B.y+4)
  for _=1,600 do P.update(s,500) end;expect(u.pathFailed and not u.pathPending,"sealed unit did not report path failure")
  u.orders={{kind="attack",target=999999}};require("war.Workers").update(s,u,.1);expect(#u.orders==0,"dead target not removed")
 end)
 test("返营重寻路与环境效率",function()
  local s=Sim.new(112,"sandbox",2);local u=worker(s,1)
  P.request(s,u,B.x+38,B.y+4);local token=u.orderToken
  C.go(s,u,B.x,B.y,.1,1)
  expect(u.orderToken>token and u.pathGoal.x==B.x,"return reused outbound path")
  local r=s.resources[U.key(B.x+6,B.y-1)];u.x,u.y=r.x,r.y;u.orders={{kind="gather",target=U.key(B.x+6,B.y-1)}};u.pathPending=false;u.path={};u.pathFailed=false;u.temp=-1
  require("war.Workers").update(s,u,.1);local cold=u.work
  u.work=0;u.temp=20;require("war.Workers").update(s,u,.1)
  expect(cold<u.work,"cold did not reduce work rate")
  u.x,u.y=B.x+4,B.y;u.hp=50;u.temp=20;u.returning=true;u.satiety=20;u.cargo={food=8};u.delivering=true;s.factions[1].food={}
  advance(s,200);expect(E.food(s,1)>0 and not next(u.cargo) and u.satiety>50,"hungry worker withheld carried food")
  u.orders={{kind="gather",target=U.key(B.x+6,B.y-1)}};u.x,u.y=B.x+4,B.y;u.returning=true;u.hp=20;u.satiety=100
  local before=u.hp;require("war.Survival").update(s,10);expect(u.hp>before,"returning unit did not rest with a pending order")
 end)
 test("敌方迷雾与自主发展",function()
  local s=Sim.new(107,"sandbox",2);A.think(s,2);expect(next(s.factions[2].ai.known)==nil,"AI discovered unseen camp")
  local e=U.nearest(s,B.x,B.y,function(b) return b.kind=="core" and b.faction==1 end);W.reveal(s,2,e.x,e.y,4);A.think(s,2)
  expect(s.factions[2].ai.known[tostring(e.id)]~=nil,"AI did not remember scouted camp")
  advance(s,2500);expect(E.count(s,2,"house")>0 and E.count(s,2,"farm")>0,"AI did not develop economy")
 end)
 test("存档往返与损坏保护",function()
  local s=Sim.new(108,"sandbox",2);advance(s,850);local snap=Save.snapshot(s);local restored=Save.restore(snap)
  expect(s.time==restored.time and s.rng==restored.rng,"time/RNG mismatch")
  expect(E.stock(s,2,"wood")==E.stock(restored,2,"wood"),"stock mismatch")
  expect(E.count(s,1)==E.count(restored,1),"entity mismatch")
  expect(packSeen==nil,"unexpected global")
  snap.version=900;expect(not pcall(Save.restore,snap),"bad version accepted")
  snap.version=D.VERSION;snap.factions[1].seen="bad";expect(not pcall(Save.restore,snap),"corrupt fog accepted")
  snap=Save.snapshot(s);local _,entity=next(snap.entities);entity.hp="broken"
  expect(not pcall(Save.restore,snap),"corrupt health accepted")
  snap=Save.snapshot(s);snap.factions[1].food[1].amount="broken"
  expect(not pcall(Save.restore,snap),"corrupt food batch accepted")
 end)
 test("云存档回调、失败重试与超时",function()
  local s=Sim.new(109,"sandbox",2);local callbacks={};local original=clientCloud
  clientCloud={Set=function(_,key,row,events) callbacks.events=events;callbacks.row=row;callbacks.key=key end}
  Save.busy=false;Save.pending=false;Save.write(s,1);expect(Save.busy and Save.status~="已保存","reported success before callback")
  callbacks.events.error(-1,"offline");expect(not Save.busy and Save.pending,"failure lost pending snapshot")
  local u=worker(s,1);u.pathPending=true;Save.retry(s);expect(u.pathPending,"save retry modified active pathfinding")
  callbacks.events.ok();expect(not Save.busy and not Save.pending,"success not acknowledged")
  Save.write(s,2);Save.update(21);expect(not Save.busy and Save.pending,"timeout not released")
  local late=callbacks.events;late.ok();expect(Save.pending~=false,"late callback acknowledged expired request")
  clientCloud.Get=function() end;local timeoutDelivered=false
  Save.read(1,function(state) timeoutDelivered=state==false end);Save.update(21)
  expect(timeoutDelivered and not Save.busy,"read timeout left the UI waiting forever")
  Save.busy=false;Save.pending=false;clientCloud=original
 end)
 test("基地重建、战败与胜利",function()
  local s=Sim.new(110,"sandbox",2);local core=U.nearest(s,B.x,B.y,function(e) return e.faction==1 and e.kind=="core" end);core.hp=0;advance(s,11)
  expect(s.outcome=="playing","core loss ended game prematurely");expect(E.count(s,1,"store")>0,"core ruins lost delivery capability")
  for _,e in pairs(s.entities) do if e.faction==1 then e.hp=0 end end;advance(s,11);expect(s.outcome=="defeat","wipe did not end game")
  s=Sim.new(111,"sandbox",2);for _,e in pairs(s.entities) do if e.faction==2 or e.faction==3 then e.hp=0 end end;advance(s,11);expect(s.outcome=="victory","enemy elimination not recognized")
  s=Sim.new(113,"sandbox",2);for _,e in pairs(s.entities) do if e.faction==2 and e.kind=="core" then e.hp=0 end end
  W.rebuild(s);A.think(s,2);expect(E.count(s,2,"core")==1,"AI did not start rebuilding its core")
 end)
 test("鼠标框选、触屏拖镜头与命令追加",function()
  local oldUI,oldInput=package.loaded["urhox-libs/UI"],package.loaded["war.Input"]
  local oldGraphics,oldKeys,oldLeft,oldRight=graphics,input,MOUSEB_LEFT,MOUSEB_RIGHT
  local ok,err=pcall(function()
   package.loaded["urhox-libs/UI"]={GetScale=function() return 1 end};package.loaded["war.Input"]=nil
   graphics={GetDPR=function() return 1 end};input={GetKeyDown=function() return false end};MOUSEB_LEFT=1;MOUSEB_RIGHT=4
   local I,R=require("war.Input"),require("war.Render");local s=Sim.new(114,"sandbox",2)
   local g={state=s,started=true,selection={},groups={{},{},{}},camera={x=B.x,y=B.y},zoom=1,pointer={},box=false,append=false,mode=false,placement=false}
   local x1,y1,x2,y2=math.huge,math.huge,-math.huge,-math.huge
   for _,u in pairs(s.entities) do if u.kind=="worker" and u.faction==1 then local x,y=R.project(g,u.x,u.y);x1=math.min(x1,x-10);x2=math.max(x2,x+10);y1=math.min(y1,y-10);y2=math.max(y2,y+10) end end
   I.down(g,{x=x1,y=y1,isPrimary=true,pointerId=1,pointerType="mouse",button=1});I.up(g,{x=x2,y=y2,pointerId=1})
   expect(#I.ids(g)==6 and g.camera.x==B.x,"mouse box selection moved camera or missed units")
   g.selection={};I.down(g,{x=x1,y=y1,isPrimary=true,pointerId=1,pointerType="touch",button=1});I.up(g,{x=x2,y=y2,pointerId=1})
   expect(#I.ids(g)==0 and g.camera.x~=B.x,"touch drag selected instead of panning")
   local u=worker(s,1);C.order(s,u,{kind="move",x=45,y=90});C.order(s,u,{kind="guard",x=46,y=90},true);expect(#u.orders==2,"append discarded previous command")
   local farm=C.spawn(s,"building","farm",1,B.x,B.y+6,true);g.selection={[u.id]=true};local px,py=R.project(g,farm.x,farm.y)
   I.tap(g,px,py,false);expect(s.commands[#s.commands].kind=="farm" and s.commands[#s.commands].target==farm.id,"touch tap selected farm instead of assigning worker")
  end)
  package.loaded["urhox-libs/UI"]=oldUI;package.loaded["war.Input"]=oldInput;graphics=oldGraphics;input=oldKeys;MOUSEB_LEFT=oldLeft;MOUSEB_RIGHT=oldRight
  expect(ok,tostring(err))
 end)
 test("大世界地形、分块加载与跨区寻路",function()
  local s=Sim.new(1,"sandbox",2);local loaded=0;for _ in pairs(s.generated) do loaded=loaded+1 end
  expect(loaded<32,"entire world eagerly populated")
  local found={};for y=8,D.MAP_HEIGHT,32 do for x=8,D.MAP,32 do found[W.terrain(s,x,y)]=true end end
  for t=1,16 do expect(found[t],"biome missing: "..t) end
  expect(not W.walkable(s,1,1,1) and not W.walkable(s,10,10,1),"ocean did not block land cells")
  for _,base in ipairs(D.factions) do expect(W.land(s,base.x,base.y),"colony spawn blocked") end
  local u=worker(s,1);local target={x=D.factions[2].x-8,y=D.factions[2].y+8};C.order(s,u,{kind="move",x=target.x,y=target.y})
  local arrived=false
  for i=1,18000 do P.update(s,500);if C.go(s,u,target.x,target.y,.2,.8) then arrived=true;break end;if i%30==0 then W.rebuild(s) end end
  expect(arrived and not u.pathFailed,"cross-biome hierarchical route failed")
  local before=loaded;W.ensureArea(s,900,500,18);local after=0;for _ in pairs(s.generated) do after=after+1 end
  expect(after>before,"new frontier did not create resource chunks")
 end)
 test("区块资源增量存档与稀疏迷雾",function()
  local s=Sim.new(2,"sandbox",2);W.ensureArea(s,600,700,20);W.reveal(s,1,600,700,12)
  local key=U.key(B.x+6,B.y-1);s.resources[key].amount=77
  local snap=Save.snapshot(s);local count=0;for _ in pairs(snap.resources) do count=count+1 end
  expect(count==1,"untouched resources bloated the snapshot")
  local restored=Save.restore(snap)
  expect(restored.resources[key].amount==77 and restored.factions[1].seen[U.key(600,700)],"frontier/resource progress lost")
  for id in pairs(s.generated) do expect(restored.generated[id],"explored chunk missing") end
  local copy=Save.snapshot(restored);expect(copy.factions[1].seen==snap.factions[1].seen,"sparse fog changed after restore")
 end)
 test("人体器官分布、组织多样性与血管通行",function()
  local s=Sim.new(1,"sandbox",2)
  for _,r in ipairs({{1024,300,5},{700,1265,7},{755,1775,9}}) do
   local n=0;for y=r[2]-12,r[2]+12,4 do for x=r[1]-12,r[1]+12,4 do if W.terrain(s,x,y)==r[3] then n=n+1 end end end
   expect(n>=12,"organ habitat missing")
  end
  local n=W.vessels(s).nodes[9];expect(W.terrain(s,math.floor(n.x),math.floor(n.y))==13,"central blood route missing")
  for _,seed in ipairs({1,7,73,2026,183947}) do
   local found={};for y=8,D.MAP_HEIGHT,32 do for x=8,D.MAP,32 do found[W.tile(x,y,seed)]=true end end
   for t=1,16 do expect(found[t],"tissue missing: "..t.." seed "..seed) end
  end
 end)
 test("组织存档与旧版大地图拓扑兼容",function()
  local s=Sim.new(73,"sandbox",2);local snap=Save.snapshot(s);expect(snap.terrainStyle=="body","new game lost body identity")
  local body=Save.restore(snap);expect(body.terrainStyle=="body","body map type lost")
  snap.terrainStyle="broken";expect(not pcall(Save.restore,snap),"invalid tissue generator accepted")
  local old=W.generate(73,nil,"body-v3");local migrated=Save.restore(Save.snapshot(old))
  expect(migrated.terrainStyle=="body-v3" and migrated.mapWidth==1024,"legacy dimensions changed")
  for y=4,1024,64 do for x=4,1024,64 do expect(W.terrain(migrated,x,y)==require("war.AnatomyV3").tile(x,y,73),"legacy body geometry changed") end end
  local again=Save.restore(Save.snapshot(migrated));expect(again.terrainStyle=="body-v3","second restore replaced legacy map")
 end)
 test("逐帧移动、变速、暂停与状态替换",function()
  local M=require("war.Motion")
  for _,fps in ipairs({30,60,120}) do for _,speed in ipairs({1,2}) do
   local e={id=1,category="unit",x=220,y=510,age=0};local s={time=0,entities={[1]=e}}
   local g={state=s,accumulator=0};M.reset(g);local previous=false;local maxError=0
   for frame=1,fps*2 do
    g.accumulator=g.accumulator+speed/fps
    while g.accumulator>=D.STEP-1e-9 do
     M.capture(g);e.x=e.x+2.4*D.STEP;s.time=s.time+D.STEP;g.accumulator=g.accumulator-D.STEP
    end
    local x=M.position(g,e)
    if frame>fps/4 and previous then
     local delta=x-previous;expect(delta>0,"visible movement stalled between ticks")
     maxError=math.max(maxError,math.abs(delta-2.4*speed/fps))
    end
    previous=x
   end
   expect(maxError<1e-7,"frame-rate-dependent movement")
   local x,y=M.position(g,e);local t=M.time(g)
   for _=1,20 do local a,b=M.position(g,e);expect(a==x and b==y and M.time(g)==t,"pause advanced visual state") end
   g.state={time=0,entities={[1]={id=1,category="unit",x=600,y=600}}}
   expect(M.position(g,g.state.entities[1])==600,"replaced state reused old pose")
  end end
 end)
 test("路径点连续消耗与禁止穿角",function()
  local s=W.generate(4,nil,nil,nil,2);s.entities={};W.rebuild(s)
  for y=490,540 do for x=208,260 do s.tiles[U.key(x,y)]=1 end end
  local e=C.spawn(s,"unit","scout",1,220.5,510.5);W.rebuild(s)
  e.pathGoal={x=228.5,y=510.5};e.pathResolved={x=228.5,y=510.5}
  e.path={{x=221.5,y=510.5},{x=222.5,y=510.5},{x=223.5,y=510.5},{x=224.5,y=510.5},{x=225.5,y=510.5},{x=226.5,y=510.5},{x=227.5,y=510.5},{x=228.5,y=510.5}}
  for _=1,16 do s.time=s.time+.1;local x=e.x;C.go(s,e,228.5,510.5,.1,.3);expect(e.x>x,"waypoint consumed an empty tick") end
  s.tiles[U.key(241,520)]=14
  expect(not P.clear(s,240.5,520.5,241.5,521.5,1),"diagonal clipped blocked corner")
  expect(not P.clear(s,240.5,520.5,242.5,520.5,1),"long segment crossed blocked tile")
  s.tiles[U.key(241,520)]=1
  expect(P.clear(s,240.5,520.5,242.5,520.5,1),"clear route rejected")
 end)
 test("渲染沿拐角路径且不写入存档",function()
  local M=require("war.Motion");local s=Sim.new(5,"sandbox",2);local e=worker(s,1)
  for id,u in pairs(s.entities) do if u.category=="unit" and id~=e.id then s.entities[id]=nil end end;W.rebuild(s)
  local g={state=s,accumulator=0};M.reset(g);M.capture(g)
  local x,y=e.x,e.y;e.x=x+.1;M.record(e);e.y=y+.1;M.record(e)
  g.accumulator=.025;local a,b=M.position(g,e);expect(math.abs(a-x-.05)<1e-8 and b==y,"render cut across a corner")
  g.accumulator=.075;a,b=M.position(g,e);expect(math.abs(a-x-.1)<1e-8 and math.abs(b-y-.05)<1e-8,"second corner segment wrong")
  local snap=Save.snapshot(s);local saved=snap.entities[tostring(e.id)]
  expect(not saved.motion and not saved.trail and not saved.distance,"visual interpolation polluted saves")
  local restored=Save.restore(snap);expect(restored.entities[e.id].x==e.x,"moving save lost position")
 end)
 test("正俯视投影、平移与缩放锚点",function()
  local R,View=require("war.Render"),require("war.View")
  local oldW,oldH=R.w,R.h
  local ok,err=pcall(function()
   for _,viewport in ipairs({{960,540},{1280,800},{1920,1080}}) do
    R.w,R.h=viewport[1],viewport[2]
    for _,zoom in ipairs({.24,1,2.8}) do
     local g={camera={x=512,y=512},zoom=zoom}
     local cx,cy=R.project(g,512,512);local rx,ry=R.project(g,513,512);local dx,dy=R.project(g,512,513)
     expect(rx>cx and ry==cy and dx==cx and dy>cy,"world axes are not screen aligned")
     for _,point in ipairs({{480.2,529.7},{1,1},{1024,1024}}) do
      local x,y=R.project(g,point[1],point[2]);local wx,wy=R.unproject(g,x,y)
      expect(math.abs(wx-point[1])+math.abs(wy-point[2])<1e-8,"projection roundtrip drift")
     end
     local px,py=R.project(g,520,505);R.pan(g,64,-32);local ax,ay=R.project(g,520,505)
     expect(math.abs(ax-px-64)+math.abs(ay-py+32)<1e-8,"pan moves in wrong screen direction")
     local wx,wy=R.unproject(g,330,240);R.zoom(g,1.17,330,240);local bx,by=R.unproject(g,330,240)
     expect(math.abs(wx-bx)+math.abs(wy-by)<1e-8,"zoom lost pointer anchor")
     local x1,x2,y1,y2=View.bounds(g,R.w,R.h,4)
     expect(x1>=1 and y1>=1 and x2<=D.MAP and y2<=D.MAP,"culling bounds escape map")
    end
   end
  end)
  R.w,R.h=oldW,oldH;expect(ok,tostring(err))
 end)
 test("细胞旋转冻结、尺寸约束与缓慢转向",function()
  local Cells,Frames,M=require("war.Cells"),require("war.CellFrames"),require("war.Motion")
  local a=Cells.pose(18,7,.7,.4)
  for _=1,10 do local b=Cells.pose(18,7,.7,.4)
   expect(a.frame==b.frame and a.blend==b.blend and a.rotation==b.rotation and a.sx==b.sx,"paused cell animation advances")
  end
  for i=0,100 do
   local p=Cells.pose(i*.071,7,.7,.4)
   expect(p.frame==0 and p.blend==0,"static portrait should rotate without atlas blending")
   expect(p.sx>=.97 and p.sx<=1 and p.sy==p.sx,"breathing exceeds collision radius")
   local nextPose=Cells.pose(i*.071+.1,7,.7,.4)
   expect(nextPose.rotation>p.rotation and nextPose.rotation-p.rotation<.02,"rotation should be slow and continuous")
   local q=Cells.pose(i*.071+Frames.period,7,.7,.4)
   expect(p.frame==q.frame and math.abs(p.blend-q.blend)<1e-8,"sprite loop discontinuity")
  end
  local e={id=1,category="unit",x=512,y=512};local g={state={time=0,entities={[1]=e}},accumulator=0}
  M.reset(g);M.capture(g);e.y=e.y+.3;g.accumulator=D.STEP
  local speed,angle=M.activity(g,e)
  expect(speed>0 and angle>0 and angle<=1.5*D.STEP,"turn jumps instead of slowly rotating")
 end)
 local passed=0;for _,r in ipairs(results) do if r.pass then passed=passed+1 end end
 return {passed=passed,total=#results,results=results}
end
-- Optional native-preview fixture. Never loaded by the shipping entry point.
function QA.stress(seed)
 local s=Sim.new(seed or 104729,"sandbox",2)
 for f,base in ipairs(D.factions) do
  for j=1,5 do C.spawn(s,"building","house",f,base.x-15+j*3,base.y+13,true) end
  for j=1,31 do
   local kind=j<=8 and "worker" or (j%3==0 and "archer" or "spear")
   local e=C.spawn(s,"unit",kind,f,base.x+3+(j%7)*.75,base.y+5+math.floor(j/7)*.75,true)
   C.order(s,e,{kind="guard",x=e.x,y=e.y})
  end
 end
 W.rebuild(s);W.fog(s);return s
end
function QA.soak(days,seed,onDay)
 local s=Sim.new(seed or 104729,"sandbox",2);local maxEntities,maxJobs,maxMemory=0,0,0;local lastDay=0;local transitions={}
 -- Player autoplay is a test driver, using the same public commands as the two opponents.
 -- Victory retains the same world; defeat is reported as a test failure, never bypassed.
 for i=1,(days or 64)*3600 do
  if i%60==0 then
   A.think(s,1)
   -- Test driver keeps the player army protecting its workers while the two
   -- production AIs retain their normal scouting, invasion and retreat logic.
   local base=U.nearest(s,B.x,B.y,function(e) return e.faction==1 and e.kind=="core" and U.alive(e) end)
   if base then
    local threat=U.nearest(s,base.x,base.y,function(e) return e.faction~=1 and U.alive(e) and W.visible(s,1,e) and U.dist(base,e)<12 end)
    for _,u in pairs(s.entities) do if u.faction==1 and u.category=="unit" and u.kind~="worker" and u.kind~="scout" then
     if threat then C.execute(s,{kind="attack",faction=1,ids={u.id},target=threat.id})
     else C.order(s,u,{kind="guard",x=base.x+math.cos(u.id*2.4)*5,y=base.y+math.sin(u.id*2.4)*5}) end
    end end
   end
  end
  Sim.step(s,.1)
  local day=math.floor(s.time/360)+1
  if day~=lastDay then
   lastDay=day;local season=select(3,V.clock(s));transitions[season]=true
   local count=0;for _,e in pairs(s.entities) do count=count+1;expect(e.x==e.x and e.y==e.y and e.hp==e.hp,"non-finite entity") end
   maxEntities=math.max(maxEntities,count);maxJobs=math.max(maxJobs,#P.jobs);collectgarbage("collect");maxMemory=math.max(maxMemory,collectgarbage("count"))
   for f=1,3 do local pop,cap=E.population(s,f,false);expect(pop<=40,"population exceeds cap");expect(cap<=40,"housing exceeds cap") end
   if onDay then onDay(day,s,maxMemory) end
  end
  expect(s.outcome~="defeat","autoplay defeated on day "..day)
 end
 expect(s.time>=days*360-.2,"time stopped during soak")
 for i=1,4 do expect(transitions[i],"season omitted") end
 local factions={}
 for f,fa in ipairs(s.factions) do
  local known=0;for _ in pairs(fa.ai.known or {}) do known=known+1 end
  factions[f]={population=E.population(s,f,false),units=E.count(s,f),tier=fa.tier,knownBuildings=known,lost=fa.lost}
 end
 collectgarbage("collect")
 return {days=days,time=s.time,outcome=s.outcome,maxEntities=maxEntities,maxPathJobs=maxJobs,maxMemoryKB=maxMemory,finalMemoryKB=collectgarbage("count"),factions=factions}
end
return QA
