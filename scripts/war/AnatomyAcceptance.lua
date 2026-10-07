-- Behavioral checks for the anterior organ map and its circulation/navigation contract.
local Q={}
function Q.run()
 local W,V,O,A,P,C,S,Save,D,U=require('war.World'),require('war.Vessels'),require('war.Organs'),require('war.AnatomyV2'),require('war.Path'),require('war.Commands'),require('war.Simulation'),require('war.Save'),require('war.Data'),require('war.Util')
 local results={};local function test(name,fn) local ok,err=pcall(fn);results[#results+1]={name=name,pass=ok,error=ok and '' or tostring(err)} end
 local s=W.generate(73);W.rebuild(s);local v=W.vessels(s)
 local function reach(start,goal,banned)
  local queue={start};local seen={[start]=true};local cursor=1
  while queue[cursor] do local n=queue[cursor];cursor=cursor+1;if n==goal then return true end
   for _,e in ipairs(v.edges) do if e.a==n and not seen[e.b] and not (banned and banned[e.b]) then seen[e.b]=true;queue[#queue+1]=e.b end end
  end
  return false
 end
 test('每个器官都有供血、聚合交换区和回流',function()
  assert(#O.list==13 and v.version==2 and #v.edges>120)
  local ids={};for _,n in ipairs(v.nodes) do assert(not ids[n.id],'duplicate stable node ID');ids[n.id]=true end
  for _,o in ipairs(O.list) do
   assert(o.ports.artery and o.ports.vein and #o.regions>=1)
   assert(reach((o.id=='lung_r' or o.id=='lung_l') and 2 or 6,o.ports.artery))
   assert(reach(o.ports.artery,o.ports.vein) and reach(o.ports.vein,1))
   for _,p in ipairs(o.contour) do assert(A.field(o.x+p[1]*o.rx,o.y+p[2]*o.ry)<=1,'organ protrudes: '..o.id) end
  end
 end)
 test('肺循环与冠脉形成正确的定向环路和氧合状态',function()
  for _,p in ipairs({{1,2},{2,5},{5,36},{5,38},{37,3},{39,3},{3,4},{4,6},{6,52},{52,53},{53,33},{33,1}}) do assert(reach(p[1],p[2])) end
  for _,e in ipairs(v.edges) do
   if e.a==5 or (e.a==2 and e.b==5) then assert(e.oxygen=='low') end
   if (e.a==37 or e.a==39) and e.b==3 then assert(e.oxygen=='high') end
  end
  assert(not reach(2,3,{[36]=true,[38]=true}),'pulmonary bypass')
 end)
 test('胃肠脾胰必须先经肝脏，再回下腔静脉',function()
  for _,id in ipairs({'stomach','spleen','pancreas','small_intestine','large_intestine'}) do
   local n=O.byId[id].ports.vein;assert(reach(n,32) and reach(32,40) and reach(40,41) and reach(41,16))
   assert(not reach(n,1,{[40]=true}),'portal bypass: '..id)
  end
  local region=O.byId.large_intestine.regions[2];assert(not reach(region.b,1,{[40]=true}))
 end)
 test('主动脉弓左右不对称，椎动脉汇入基底与六段脑底环',function()
  local function direct(a,b) for _,e in ipairs(v.edges) do if e.a==a and e.b==b then return true end end;return false end
  assert(direct(7,19) and direct(19,20) and direct(19,22) and direct(7,21) and direct(7,23))
  assert(direct(24,26) and direct(25,26) and direct(26,27))
  local count=0;for _,e in ipairs(v.edges) do if e.name=='脑底动脉环' then count=count+1;assert(reach(e.b,e.a)) end end;assert(count==6)
 end)
 test('曲线采样保持管腔连续，所有主路线位于身体内',function()
  for id,e in ipairs(v.edges) do
   assert(e.arc[1]==0 and e.arc[#e.points]==e.length)
   for i=2,#e.points do local a,b=e.points[i-1],e.points[i]
    assert((b[1]-a[1])^2+(b[2]-a[2])^2<=16.000001)
    assert(P.clear(s,a[1],a[2],b[1],b[2],1,id),'blocked bend '..id)
    assert(A.field(b[1]/v.scale,b[2]/v.scale)<=1,'vessel outside silhouette')
   end
   for _,cubic in ipairs(e.cubics) do for j=0,16 do local t=j/16;local q=1-t
    local x=q^3*cubic[1][1]+3*q*q*t*cubic[2][1]+3*q*t*t*cubic[3][1]+t^3*cubic[4][1]
    local y=q^3*cubic[1][2]+3*q*q*t*cubic[2][2]+3*q*t*t*cubic[3][2]+t^3*cubic[4][2]
    assert(v.distance(id,x,y)<=.250001,'curve approximation error')
   end end
  end
 end)
 test('组织膜口双向通行，普通管壁与心腔隔壁封闭',function()
  for _,g in ipairs(v.gates) do local e=v.edges[g.edge];local x,y=g.px+g.nx*(e.width*.5+11),g.py+g.ny*(e.width*.5+11)
   local ok,lane=P.clear(s,x,y,g.px,g.py,1,0);assert(ok and lane==g.edge,'gate entry '..g.name)
   local back,l=P.clear(s,g.px,g.py,x,y,1,g.edge);assert(back and l==0,'gate exit '..g.name)
  end
  assert(W.terrain(s,1089,1510)==17 and not W.land(s,1089,1510),'septum open')
  assert(not P.clear(s,v.nodes[1].x,v.nodes[1].y,v.nodes[3].x,v.nodes[3].y,1,12),'atrial shortcut')
  local e=v.edges[75];local a,b=e.points[60],e.points[61];local dx,dy=b[1]-a[1],b[2]-a[2];local len=math.sqrt(dx*dx+dy*dy)
  assert(not P.clear(s,a[1],a[2],a[1]-dy/len*(e.width*.5+12),a[2]+dx/len*(e.width*.5+12),1,75),'wall crossed')
 end)
 test('非共享节点的平面交叉不能换道',function()
  local count=0
  for id,e in ipairs(v.edges) do local p=e.points[math.floor(#e.points/2)]
   for _,other in ipairs(v.sample(p[1],p[2]).lanes) do if other~=id then
    local b=v.edges[other]
    if e.a~=b.a and e.a~=b.b and e.b~=b.a and e.b~=b.b then
     count=count+1;for _,lane in ipairs(v.options(p[1],p[2],p[1],p[2],id)) do assert(lane~=other) end
    end
   end end
  end
  assert(count>0,'crossing fixture absent')
 end)
 test('跨器官路线与移动中 v7 存读档保留新增通路',function()
  P.reset();local edge=#v.edges;local e=v.edges[edge];local p=e.points[math.floor(#e.points/2)]
  local unit=C.spawn(s,'unit','spear',1,p[1],p[2],true);assert(unit);unit.vesselLane=edge;W.rebuild(s)
  local goal=e.points[#e.points];C.order(s,unit,{kind='move',x=goal[1],y=goal[2]})
  for _=1,30 do s.time=s.time+.1;P.update(s,1000);C.go(s,unit,goal[1],goal[2],.1,.7) end
  local snap=Save.snapshot(s);local q=Save.restore(snap);local restored=q.entities[unit.id]
  assert(q.anatomyVersion==2 and snap.version==7 and restored.vesselLane==edge and restored.x==unit.x and restored.y==unit.y and #restored.orders==1)
  assert(v.route(unit.x,unit.y,O.byId.brain.x*.5,O.byId.brain.y*.5,edge),'cross-organ route missing')
  local arrived=false;for _=1,1000 do q.time=q.time+.1;P.update(q,1000);if C.go(q,restored,goal[1],goal[2],.1,.7) then arrived=true;break end end;assert(arrived,'restored moving unit stuck')
  snap.entities[tostring(unit.id)].vesselLane=#v.edges+1;assert(not pcall(Save.restore,snap),'unknown lane accepted')
 end)
 test('v6 记录仍保留旧生成器、坐标和 120 条边',function()
  local old=S.new(73,'sandbox',1);local snap=Save.snapshot(old);snap.version=6;snap.anatomyVersion=nil
  local q=Save.restore(snap);assert(q.anatomyVersion==1 and #W.vessels(q).edges==120)
  for y=16,D.MAP_HEIGHT,113 do for x=16,D.MAP,101 do assert(W.terrain(old,x,y)==W.terrain(q,x,y)) end end
  local again=Save.restore(Save.snapshot(q));assert(again.anatomyVersion==1)
  for id,e in pairs(old.entities) do assert(q.entities[id].x==e.x and q.entities[id].y==e.y and q.entities[id].vesselLane==e.vesselLane) end
 end)
 test('13 个器官剖面按逻辑尺寸平滑切换，缩放不改通行',function()
  assert(O.blend(180)==0 and O.blend(270)==.5 and O.blend(360)==1)
  local before=Save.snapshot(s);local previous=0;for n=0,500 do local blend=O.blend(n);assert(blend>=previous and blend>=0 and blend<=1);previous=blend end
  local after=Save.snapshot(s);assert(before.anatomyVersion==after.anatomyVersion and before.tick==after.tick)
  for _,b in ipairs(D.factions) do local count=0;W.reveal(s,1,b.x,b.y,20)
   for y=b.y-14,b.y+14 do for x=b.x-14,b.x+14 do if W.canBuild(s,'house',x+.5,y+.5,1) then count=count+1 end end end;assert(count>30,'camp lacks build space')
  end
 end)
 local passed=0;for _,r in ipairs(results) do if r.pass then passed=passed+1 end end
 return {passed=passed,total=#results,results=results}
end
return Q
