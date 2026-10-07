-- Real navigation, collision and combat checks for the expanded nasal battlefield.
local S,W,P,C,U,G,Save=require('war.Simulation'),require('war.World'),require('war.Path'),require('war.Commands'),require('war.Util'),require('war.NasalTerrain'),require('war.Save')
local Q={}
local function empty() local s=S.new(73);s.entities={};W.rebuild(s);return s end
local function move(s,e,x,y)
 C.execute(s,{kind='move',faction=1,ids={e.id},x=x,y=y})
 for _=1,1600 do
  s.time=s.time+.1;W.rebuild(s);P.update(s,500);require('war.Workers').update(s,e,.1)
  assert(not G.blocked(e.x,e.y) and W.land(s,math.floor(e.x),math.floor(e.y)),'crossed a ridge or wall')
  if U.dist(e,{x=x,y=y})<1.2 then return end
 end
 error('destination unreachable: '..x..','..y)
end
function Q.run()
 local results={};local function test(name,fn) local ok,err=pcall(fn);results[#results+1]={name=name,pass=ok,error=ok and '' or tostring(err)} end
 test('左右鼻道与上中下鼻甲、鼻中隔共同阻挡',function()
  local s=empty();assert(#G.obstacles==7)
  assert(not W.land(s,1174,403) and not W.land(s,1173,421) and not W.land(s,1173,459) and not W.land(s,1174,477))
  assert(not P.clear(s,1180,430,1180,450,1,0),'septum crossed')
  for _,p in ipairs(G.landmarks) do assert(W.land(s,math.floor(p.x),math.floor(p.y)),p.name..' inaccessible') end
 end)
 test('全部可行走格可从后鼻调入口到达',function()
  local s=empty();local x,y=math.floor(G.home.x),math.floor(G.home.y)
  local q={{x=x,y=y,lane=W.lane(s,x+.5,y+.5)}};local seen={[U.key(x,y)..':'..q[1].lane]=true};local reached={};local head=1
  while head<=#q do local n=q[head];head=head+1;reached[U.key(n.x,n.y)]=true
   for _,d in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do local tx,ty=n.x+d[1],n.y+d[2]
    if W.land(s,tx,ty) then local ok,lane=P.clear(s,n.x+.5,n.y+.5,tx+.5,ty+.5,1,n.lane)
     local key=U.key(tx,ty)..':'..tostring(lane)
     if ok and not seen[key] then seen[key]=true;q[#q+1]={x=tx,y=ty,lane=lane} end
    end
   end
  end
  local total=0
  for yy=G.bounds.y,G.bounds.y+G.bounds.h-1 do for xx=G.bounds.x,G.bounds.x+G.bounds.w-1 do
   if W.land(s,xx,yy) then total=total+1;assert(reached[U.key(xx,yy)],'isolated tile '..xx..','..yy) end
  end end
  assert(total>20000,'incomplete battlefield')
 end)
 test('实际细胞经膜口穿行血管、绕鼻甲走遍左右鼻腔',function()
  local s=empty();local e=C.spawn(s,'unit','scout',1,G.home.x,G.home.y);assert(e and e.vesselLane>0)
  for _,p in ipairs({G.entries[2],{x=1188,y=410},G.entries[1],{x=1188,y=472},{x=1262,y=440},G.home}) do move(s,e,p.x,p.y) end
 end)
 test('血管壁不可横穿，指定交换膜口可以进出',function()
  local s=empty();local v=W.vessels(s)
  assert(not P.clear(s,1188,376,1188,388,1,2),'sealed wall crossed')
  for _,gate in ipairs(v.gates) do
   local ok=P.clear(s,gate.px,gate.py,gate.x+gate.nx*2.5,gate.y+gate.ny*2.5,1,gate.edge)
   assert(ok,gate.name..' blocked')
  end
 end)
 test('鼻甲和封闭管壁阻挡攻击，开放黏膜内可以交战',function()
  local s=empty();local F=require('war.Combat')
  local a=C.spawn(s,'unit','siege',1,1174,399);local b=C.spawn(s,'unit','virus',2,1174,407)
  assert(a and b and U.dist(a,b)<=9);local hp=b.hp;F.fight(s,a,b,.1,false);assert(b.hp==hp,'shot through concha')
  local c=C.spawn(s,'unit','archer',1,1188,376);local d=C.spawn(s,'unit','virus',2,1188,382)
  assert(c and d and U.dist(c,d)<=7);hp=d.hp;F.fight(s,c,d,.1,false);assert(d.hp==hp,'shot through vessel wall')
  local e=C.spawn(s,'unit','spear',1,1188,472);local f=C.spawn(s,'unit','virus',2,1189.5,472)
  assert(e and f);F.fight(s,e,f,.1,false);assert(f.hp<f.maxHp,'open combat blocked')
 end)
 test('新地形存读档与失败重试保持几何和血管通路',function()
  local s=S.new(73);C.execute(s,{kind='reinforce',faction=1});local q=Save.restore(Save.snapshot(s))
  assert(q.campaign.terrainVersion==2 and #W.vessels(q).edges==12 and #q.campaign.reinforcements.queue==1)
  require('war.Campaign').fail(q);q=require('war.Campaign').retry(q)
  assert(q.campaign.terrainVersion==2 and q.time==0)
  local count=0;for _,e in pairs(q.entities) do count=count+1;assert(W.land(q,math.floor(e.x),math.floor(e.y))) end;assert(count==8)
 end)
 test('全身血管显示保留，鼻腔通路与锁定规则不受影响',function()
  local V=require('war.Vessels');local s=S.new(73);local body=V.forDisplay(s)
  assert(body.version==2 and #body.edges>120)
  assert(W.vessels(s)~=body and #W.vessels(s).edges==12)
  local outside=false
  for _,e in ipairs(body.edges) do for _,p in ipairs(e.points) do
   if not G.allowed(p[1],p[2]) and body.sample(p[1],p[2]).biome>0 then
    outside=true;assert(not W.land(s,math.floor(p[1]),math.floor(p[2])),'locked body became walkable')
   end
  end end
  assert(outside,'body circulation missing')
  local restored=Save.restore(Save.snapshot(s))
  assert(V.forDisplay(restored)==body and #W.vessels(restored).edges==12)
 end)
 test('三波分左右鼻腔调入且病毒路线随存档保留',function()
  local s=empty();local Camp=require('war.Campaign')
  for _=1,1100 do Camp.beforeStep(s,.1) end
  assert(s.campaign.event.wave==3 and s.campaign.event.pendingViruses==0)
  local counts={0,0}
  for _,e in pairs(s.entities) do
   assert(e.kind=='virus' and W.land(s,math.floor(e.x),math.floor(e.y)))
   counts[e.viralSide]=counts[e.viralSide]+1
  end
  assert(counts[1]==11 and counts[2]==13,'both nostrils not invaded')
  local q=Save.restore(Save.snapshot(s))
  for id,e in pairs(s.entities) do assert(q.entities[id].viralSide==e.viralSide,'viral side lost') end
 end)
 test('鼻腔全景适配桌面与手机可见区域',function()
  local R=require('war.Render');local s=S.new(73)
  for _,size in ipairs({{1440,900},{844,390},{430,932},{360,780}}) do
   R.w,R.h=size[1],size[2];local g={state=s,camera={x=0,y=0},zoom=1};R.nasalOverview(g)
   local left,top=R.project(g,G.bounds.x,G.bounds.y);local right,bottom=R.project(g,G.bounds.x+G.bounds.w,G.bounds.y+G.bounds.h)
   local l=require('war.UIModel').layout(R.w,R.h)
   assert(left>=10 and right<=R.w-10 and top>=90 and bottom<=R.h-l.dock-12,'battlefield under HUD')
  end
 end)
 local passed=0;for _,r in ipairs(results) do if r.pass then passed=passed+1 end end
 return {passed=passed,total=#results,results=results}
end
return Q
