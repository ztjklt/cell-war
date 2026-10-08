-- Tests observable geometry, real movement and campaign behaviour of the new default.
local Q={}
function Q.run()
 local S,W,C,P,U,Save,D,M,G,Camp,T,R=require('war.Simulation'),require('war.World'),require('war.Commands'),require('war.Path'),require('war.Util'),require('war.Save'),require('war.Data'),require('war.ReferenceMap'),require('war.TracheaTerrain'),require('war.Campaign'),require('war.Territory'),require('war.Reinforcements')
 local results={};local function test(name,fn) local ok,err=pcall(fn);results[#results+1]={name=name,pass=ok,error=ok and '' or tostring(err)} end
 local function empty() local s=S.new(73);s.entities={};W.rebuild(s);return s end
 test('原图等比例映射，头、手指、脚趾和器官位于身体内',function()
  local x,y=M.world(512,768);assert(x==1024 and y==2048)
  x,y=M.source(x,y);assert(x==512 and y==768)
  assert(#M.organs==12 and not M.byId.spleen and not M.byId.mouth)
  for _,o in ipairs(M.organs) do assert(M.contains(M.outline,o.x,o.y),o.id) end
  for _,p in ipairs({{512,60},{201,865},{248,859},{792,869},{330,1463},{398,1483},{685,1463},{628,1485}}) do local wx,wy=M.world(p[1],p[2]);assert(M.contains(M.outline,wx,wy),'lost finger/toe '..p[1]) end
 end)
 test('新开局为气管守卫，八名守卫都在合法气管格内',function()
  for _,seed in ipairs({1,73,2026}) do local s=S.new(seed);assert(s.version==8 and s.anatomyVersion==3 and s.campaign.event.id=='trachea' and s.campaign.terrainVersion==3)
   local count=0;for _,e in pairs(s.entities) do count=count+1;assert(e.faction==1 and W.land(s,math.floor(e.x),math.floor(e.y)) and e.vesselLane==0) end
   assert(count==8 and next(s.resources)==nil and #W.vessels(s).edges==0 and #G.airways==15)
   for _,z in ipairs(G.zones) do assert(T.zone(z.x,z.y,s) and W.land(s,z.x,z.y)) end
  end
 end)
 test('气管纵向三区连通，真实单位往返不穿管壁',function()
  local s=empty();local e=C.spawn(s,'unit','scout',1,G.home.x,G.home.y);assert(e)
  for _,target in ipairs({G.entry,G.home}) do
   assert(C.execute(s,{kind='move',faction=1,ids={e.id},x=target.x,y=target.y}))
   local arrived=false
   for _=1,1600 do s.time=s.time+.1;W.rebuild(s);P.update(s,500);require('war.Workers').update(s,e,.1)
    assert(G.allowed(e.x,e.y));if U.dist(e,target)<1.2 then arrived=true;break end
   end;assert(arrived,'longitudinal route unreachable')
  end
  assert(not P.clear(s,G.home.x,G.home.y,G.home.x+30,G.home.y,1,0))
 end)
 test('全身结构可浏览，锁区仍拒绝移动、攻击目标、出生与寻路',function()
  local s=S.new(73);local e=s.entities[next(s.entities)];local lung=M.byId.lung_r
  assert(not Camp.allowed(s,lung.x,lung.y));assert(not C.execute(s,{kind='move',faction=1,ids={e.id},x=lung.x,y=lung.y}))
  assert(not C.spawn(s,'unit','virus',2,lung.x,lung.y))
  P.request(s,e,lung.x,lung.y);assert(e.pathFailed)
  assert(not W.canBuild(s,'house',G.home.x,G.home.y,1))
  local outside={id=999,category='unit',kind='virus',faction=2,x=G.bounds.x-2,y=e.y,hp=30,maxHp=30};s.entities[999]=outside;W.rebuild(s);s.factions[1].visible[U.key(outside.x,outside.y)]=true
  assert(not C.execute(s,{kind='attack',faction=1,ids={e.id},target=999}))
  local hp=outside.hp;assert(not require('war.Combat').fight(s,e,outside,.1,true) and outside.hp==hp)
 end)
 test('三波在10、45、90秒派发总计24病毒，全部从上段进入',function()
  local s=empty();for _=1,1100 do Camp.beforeStep(s,.1) end
  assert(s.campaign.event.wave==3 and s.campaign.event.pendingViruses==0)
  local count=0;for _,e in pairs(s.entities) do count=count+1;assert(e.kind=='virus' and T.zone(e.x,e.y,s)==1 and W.land(s,math.floor(e.x),math.floor(e.y))) end;assert(count==24)
 end)
 test('真实模拟中的病毒沿气管推进，不沿旧鼻道寻路',function()
  local s=empty();local e=C.spawn(s,'unit','virus',2,G.entry.x,G.entry.y);assert(e)
  s.campaign.event.wave=3
  for _=1,850 do S.step(s,.1) end
  assert(e.y>G.entry.y+100 and G.allowed(e.x,e.y) and not e.pathFailed)
 end)
 test('三区争夺、双方暂停及下段屏障失守优先失败',function()
  local s=empty();C.spawn(s,'unit','spear',1,G.zones[1].x,G.zones[1].y)
  for _=1,400 do T.update(s,.1) end;assert(s.campaign.event.zones[1].control==100)
  local ev=s.campaign.event;ev.zones[3].control=-99;ev.wave=3;ev.secure=19.9
  C.spawn(s,'unit','virus',2,G.zones[3].x,G.zones[3].y);Camp.afterStep(s,.2)
  assert(ev.status=='failed' and s.outcome=='defeat')
 end)
 test('调援消耗、冷却、到达与10秒回复保持原规则',function()
  local s=S.new(73);assert(R.request(s));assert(not R.request(s));assert(R.population(s)==10)
  for _=1,31 do S.step(s,.1) end;assert(#s.campaign.reinforcements.queue==0 and R.population(s)==10)
  local count=0;for _,e in pairs(s.entities) do count=count+1;assert(G.allowed(e.x,e.y)) end;assert(count==10)
  s.campaign.reinforcements.supply=0;s.campaign.reinforcements.regen=0
  for _=1,100 do R.update(s,.1) end;assert(s.campaign.reinforcements.supply==1)
 end)
 test('20秒稳固胜利，奖励不重复，下一关双肺暂不开启',function()
  local s=empty();local ev=s.campaign.event;ev.wave=3
  for _,z in ipairs(ev.zones) do z.control=100;z.owner=1 end
  for _=1,199 do Camp.afterStep(s,.1) end;assert(ev.status=='active');Camp.afterStep(s,.1)
  assert(ev.status=='completed' and s.campaign.completed.trachea and s.campaign.stage==2 and s.campaign.awaitingContent)
  local reward=s.factions[1].stock.relic;Camp.succeed(s);assert(reward==1 and s.factions[1].stock.relic==reward)
  assert(not Camp.start(s,'lungs') and #Camp.randomCandidates(s)==0)
 end)
 test('移动中v8读档、失败重试及旧v7鼻腔检查点保持各自几何',function()
  local s=S.new(73);local e=s.entities[next(s.entities)]
  C.execute(s,{kind='move',faction=1,ids={e.id},x=G.entry.x,y=G.entry.y});for _=1,50 do S.step(s,.1) end
  local q=Save.restore(Save.snapshot(s));assert(q.anatomyVersion==3 and q.entities[e.id].x==e.x and q.entities[e.id].y==e.y and #q.entities[e.id].orders==1)
  Camp.fail(q);q=Camp.retry(q);assert(q.time==0 and q.campaign.event.id=='trachea' and q.campaign.event.status=='active')
  local old=S.new(73,'campaign',2);local snap=Save.snapshot(old);snap.version=7;snap.campaign.checkpoint.version=7
  q=Save.restore(snap);assert(q.anatomyVersion==2 and q.campaign.event.id=='nasal' and #W.vessels(q).edges==12)
  Camp.fail(q);q=Camp.retry(q);assert(q.campaign.event.id=='nasal' and q.time==0)
 end)
 test('沙盒出生区可建设和采集，AI使用新的阵营出生点',function()
  local s=S.new(73,'sandbox');for i,b in ipairs(W.starts(s)) do
   assert(W.land(s,b.x,b.y),'blocked colony '..i);W.reveal(s,i,b.x,b.y,20)
   local pad=false;for y=b.y-12,b.y+12,2 do for x=b.x-12,b.x+12,2 do if W.canBuild(s,'house',x+.5,y+.5,i) then pad=true end end end;assert(pad,'no construction pad '..i)
  end
  local b=W.starts(s)[1];local e=U.nearest(s,b.x,b.y,function(v) return v.faction==1 and v.kind=='worker' end)
  local key=U.key(b.x+6,b.y-1);local before=require('war.Economy').stock(s,1,'wood')
  C.order(s,e,{kind='gather',target=key});for _=1,600 do S.step(s,.1) end
  assert(require('war.Economy').stock(s,1,'wood')>before,'resource delivery failed')
  require('war.AI').think(s,2)
 end)
 test('三次血管曲线与采样一致、交叉不允许换道',function()
  local s=W.generate(73);W.rebuild(s);local net=W.vessels(s);assert(net.version==3 and #net.edges>80)
  local checked=0
  for id,e in ipairs(net.edges) do
   for _,p in ipairs(e.points) do assert(M.contains(M.outline,p[1],p[2]),'vessel exits body: '..e.name) end
   assert(e.arc[1]==0 and e.arc[#e.points]==e.length)
   for i=2,#e.points do local a,b=e.points[i-1],e.points[i];assert((a[1]-b[1])^2+(a[2]-b[2])^2<=16.001) end
   for _,p in ipairs(e.points) do for _,other in ipairs(net.sample(p[1],p[2]).lanes) do if other~=id then local b=net.edges[other]
    if e.a~=b.a and e.a~=b.b and e.b~=b.a and e.b~=b.b then
     checked=checked+1;for _,option in ipairs(net.options(p[1],p[2],p[1],p[2],id)) do assert(option~=other) end
    end
   end end end
  end;assert(checked>0,'no crossing checked')
 end)
 test('新地图膜口双向通行、非膜口管壁封闭',function()
  local s=W.generate(73);W.rebuild(s);local net=W.vessels(s);local passed=0
  for i=#net.gates-2,#net.gates do local g=net.gates[i];local e=net.edges[g.edge]
   local ox,oy=g.px+g.nx*(e.width*.5+6),g.py+g.ny*(e.width*.5+6)
   assert(W.land(s,math.floor(ox),math.floor(oy)),'access outside body')
   local ok,lane=P.clear(s,ox,oy,g.px,g.py,1,0);assert(ok and lane==g.edge,'new gate entry')
   local back,zero=P.clear(s,g.px,g.py,ox,oy,1,g.edge);assert(back and zero==0,'new gate exit')
   local tx,ty=-g.ny,g.nx
   assert(not P.clear(s,ox+tx*12,oy+ty*12,g.px+tx*12,g.py+ty*12,1,0),'ordinary wall admits entry')
   passed=passed+1
  end;assert(passed==3)
 end)
 test('v6原鼻腔地形与检查点恢复原规则',function()
  local old=S.new(73,'campaign',1);old.entities={};old.campaign.terrainVersion=nil;W.rebuild(old)
  assert(C.spawn(old,'unit','spear',1,1222,472));Camp.checkpoint(old)
  local snap=Save.snapshot(old);snap.version=6;snap.anatomyVersion=nil;snap.campaign.checkpoint.version=6;snap.campaign.checkpoint.anatomyVersion=nil
  local q=Save.restore(snap);assert(q.anatomyVersion==1 and q.campaign.event.id=='nasal')
  local N=require('war.CampaignData').forState(q);assert(N.entry.x==1134 and #N.stages==5 and #N.waves==3)
  Camp.checkpoint(q);Camp.fail(q);q=Camp.retry(q);assert(q.campaign.event.id=='nasal' and q.campaign.terrainVersion==nil)
 end)
 test('桌面与手机横竖屏气管全景不被HUD遮挡',function()
  local Render=require('war.Render');local s=S.new(73)
  for _,size in ipairs({{1440,900},{844,390},{430,932},{360,780}}) do Render.w,Render.h=size[1],size[2]
   local g={state=s,camera={x=0,y=0},zoom=1};Render.nasalOverview(g)
   local x,y=Render.project(g,G.bounds.x,G.bounds.y);local xx,yy=Render.project(g,G.bounds.x+G.bounds.w,G.bounds.y+G.bounds.h)
   local layout=require('war.UIModel').layout(Render.w,Render.h)
   assert(x>=10 and xx<=Render.w-10 and y>=90 and yy<=Render.h-layout.dock-12)
  end
 end)
 test('损坏版本与气管事件混用被拒绝，顾问无鼻腔残留提示',function()
  local s=S.new(73);local snap=Save.snapshot(s);snap.version=7;assert(not pcall(Save.restore,snap))
  snap=Save.snapshot(s);snap.campaign.event.id='nasal';assert(not pcall(Save.restore,snap))
  snap.campaign.terrainVersion=2;assert(not pcall(Save.restore,snap))
  for _,topic in ipairs({'status','defense','supply'}) do local text=require('war.BrainAdvisor').reply(s,topic).text;assert(not text:find('鼻腔') and not text:find('鼻甲') and not text:find('咽喉')) end
 end)
 local passed=0;for _,r in ipairs(results) do if r.pass then passed=passed+1 end end
 return {passed=passed,total=#results,results=results}
end
return Q
