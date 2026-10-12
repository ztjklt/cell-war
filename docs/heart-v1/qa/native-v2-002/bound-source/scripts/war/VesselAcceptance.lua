-- Pure Lua checks for vessel walls, gate detours, projected crossings and v5 saves.
local D,U,W,C,P,V,Save,R=require('war.Data'),require('war.Util'),require('war.World'),require('war.Commands'),require('war.Path'),require('war.Vessels'),require('war.Save'),require('war.Render')
local QA={}
function QA.run()
 local results={}
 local function test(name,fn) local ok,err=pcall(fn);results[#results+1]={name=name,pass=ok,error=ok and '' or tostring(err)} end
 local function expect(ok,message) assert(ok,message) end
 local gate=V.gates[#V.gates-2] --[[@as VesselGate]]
 local edge=V.edges[gate.edge] --[[@as VesselEdge]]
 local tx,ty=-gate.ny,gate.nx
 local ox,oy=gate.px+gate.nx*(edge.width*.5+10),gate.py+gate.ny*(edge.width*.5+10)
 test('普通管壁阻止穿越，通行口双向开放',function()
  local s=W.generate(73,nil,nil,nil,1);W.rebuild(s)
  expect(not P.clear(s,ox+tx*25,oy+ty*25,gate.px+tx*25,gate.py+ty*25,1,0),'crossed sealed wall')
  local ok,lane=P.clear(s,ox,oy,gate.px,gate.py,1,0)
  expect(ok and lane==gate.edge,'gate entry failed')
  local back,backLane=P.clear(s,gate.px,gate.py,ox,oy,1,gate.edge)
  expect(back and backLane==0,'gate exit failed')
 end)
 test('通行口外缘的小数坐标可退出管腔',function()
  local s=W.generate(73,nil,nil,nil,1);W.rebuild(s)
  local g=V.gates[#V.gates-1] --[[@as VesselGate]]
  local x,y=g.x+5.63572471176,g.y+4.8838147124
  expect(V.sample(x,y).gate==g,'gate fringe fixture missing')
  expect(P.clear(s,x,y,x+1,y+1,1,g.edge),'fractional gate exit stuck')
  local lastX,lastY,lane=x,y,g.edge
  for i=1,24 do local nx,ny=x+i*.25,y+i*.25;local ok,nextLane=P.clear(s,lastX,lastY,nx,ny,1,lane);expect(ok,'gate fringe exit blocked');lastX,lastY,lane=nx,ny,nextLane end
  expect(lane==0,'exit did not return to tissue')
 end)
 test('调兵命令绕行通行口，逐帧不穿墙',function()
  P.reset();local s=W.generate(73,nil,nil,nil,1);W.rebuild(s)
  local x,y=ox+tx*25,oy+ty*25;local gx,gy=gate.px+tx*25,gate.py+ty*25
  local e=C.spawn(s,'unit','spear',1,x,y,true);W.rebuild(s)
  P.request(s,e,gx,gy)
  for _=1,250 do if not e.pathPending then break end;P.update(s,1000) end
  expect(not e.pathPending and not e.pathFailed and #e.path>0,'no gate detour')
  local entered=false;local arrived=false
  for i=1,2400 do
   local px,py,lane=e.x,e.y,e.vesselLane;s.time=s.time+.1;P.update(s,500)
   arrived=C.go(s,e,gx,gy,.1,.7)
   expect(P.clear(s,px,py,e.x,e.y,1,lane),'movement crossed sealed bank')
   entered=entered or (lane==0 and e.vesselLane==gate.edge)
   if i%5==0 then W.rebuild(s) end
   if arrived then break end
  end
  expect(arrived and entered and e.vesselLane==gate.edge,'unit failed to enter at gate')
 end)
 test('平面交叉血管不能直接换道',function()
  local count=0
  local function cross(p,q,r,z)
   local ax,ay=q[1]-p[1],q[2]-p[2];local bx,by=z[1]-r[1],z[2]-r[2];local det=ax*by-ay*bx
   if math.abs(det)<.0001 then return end
   local dx,dy=r[1]-p[1],r[2]-p[2];local a=(dx*by-dy*bx)/det;local b=(dx*ay-dy*ax)/det
   if a>.05 and a<.95 and b>.05 and b<.95 then return p[1]+ax*a,p[2]+ay*a end
  end
  for a,ea in ipairs(V.edges) do for b=a+1,#V.edges do local eb=V.edges[b]
   if ea.a~=eb.a and ea.a~=eb.b and ea.b~=eb.a and ea.b~=eb.b then
    for i=2,#ea.points do for j=2,#eb.points do local x,y=cross(ea.points[i-1],ea.points[i],eb.points[j-1],eb.points[j])
     if x then count=count+1;for _,lane in ipairs(V.options(x,y,x,y,a)) do expect(lane~=b,'projected crossing connected unrelated tubes') end end
    end end
   end
  end end
  expect(count>10,'crossing fixture missing')
 end)
 test('管腔、管壁、通行口禁止建筑',function()
  local s=W.generate(73,nil,nil,nil,1);W.rebuild(s)
  for _,p in ipairs({{gate.px,gate.py},{gate.x+tx*25,gate.y+ty*25},{gate.x,gate.y}}) do
   s.factions[1].seen[U.key(p[1],p[2])]=true
   local ok,why=W.canBuild(s,'house',p[1],p[2],1)
   expect(not ok and why=='血管内、管壁与通行口不能建造','vessel building admitted')
  end
 end)
 test('全身尺寸、下半身索引与总览定位',function()
  local s=W.generate(73,nil,nil,nil,1);W.rebuild(s)
  expect(D.width(s)==2048 and D.height(s)==4096,'rectangle missing')
  expect(U.key(2048,4096)==16775168 and U.key(10,3500)~=U.key(10,1452),'lower body keys collide')
  expect(not W.land(s,2049,3500) and not W.land(s,1024,4097),'map boundary admitted')
  local l={x=10,y=20,w=600,h=800};local px,py,w,h,scale=R.mapArea(l,s)
  expect(math.abs(w/h-.5)<.0001,'overview distorted')
  local x,y=R.mapPoint(l,px+1450*scale,py+3750*scale,s)
  expect(math.abs(x-1450)<.001 and math.abs(y-3750)<.001,'overview click misplaced')
 end)
 test('血管内存档恢复保留通路和管壁限制',function()
  local s=W.generate(73,nil,nil,nil,1);W.rebuild(s);local e=C.spawn(s,'unit','spear',1,gate.px+tx*25,gate.py+ty*25,true)
  s.factions[1].seen[U.key(1450,3750)]=true
  local restored=Save.restore(Save.snapshot(s));local v=restored.entities[e.id]
  expect(v.vesselLane==gate.edge and restored.factions[1].seen[U.key(1450,3750)],'saved lane or lower body fog lost')
  expect(not P.clear(restored,v.x,v.y,ox+tx*25,oy+ty*25,1,v.vesselLane),'restored unit crossed wall')
 end)
 local passed=0;for _,r in ipairs(results) do if r.pass then passed=passed+1 end end
 return {passed=passed,total=#results,results=results}
end
return QA
