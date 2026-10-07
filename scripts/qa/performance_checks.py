"""CPU cache/navigation regressions; engine bindings are stubbed, not native FPS."""
from pathlib import Path
import json,re
from lupa.lua54 import LuaRuntime
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute("package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={}")
source='\n'.join(p.read_text() for p in Path('scripts/war').glob('*.lua'))
for name in set(re.findall(r'\b(nvg\w+)\s*\(',source)):lua.execute(f'{name}=function(...) return 0 end')
for name in set(re.findall(r'\bNVG_\w+',source)):lua.globals()[name]=1
results=lua.execute('''
local W,S,P,C,U,D=require('war.World'),require('war.SmoothTerrain'),require('war.Path'),require('war.Commands'),require('war.Util'),require('war.Data')
local s=W.generate(73);W.rebuild(s);local b=D.factions[1]
local e=C.spawn(s,'unit','worker',1,b.x+7.5,b.y+7.5);assert(e);W.rebuild(s);W.fog(s)
local R=require('war.Render');R.vg={};R.font=1;R.w,R.h=1920,1080
local g={state=s,camera={x=e.x,y=e.y},zoom=1,selection={},accumulator=0,realTime=0,started=true}
local results={}
local function test(name,fn)local ok,err=pcall(fn);results[#results+1]={name=name,pass=ok,error=ok and '' or tostring(err)}end
local function fog()S.fog(R,g,s,1,D.width(s),1,D.height(s))end
local seen,visible
fog();seen,visible=S.caches[s].seen,S.caches[s].visible
 test('静止视野复用迷雾轮廓',function()
  local revision=s.fogRevision;W.fog(s);fog();assert(s.fogRevision==revision);assert(S.caches[s].seen==seen and S.caches[s].visible==visible)
 end)
 test('已探索区域内移动仅重建可见轮廓',function()
  W.reveal(s,1,e.x,e.y,20);fog();seen=S.caches[s].seen;visible=S.caches[s].visible
  e.x=e.x+1;W.fog(s);fog();assert(S.caches[s].seen==seen);assert(S.caches[s].visible~=visible)
 end)
 test('直接揭示新区域同时更新两层迷雾',function()
  seen,visible=S.caches[s].seen,S.caches[s].visible;W.reveal(s,1,e.x+60,e.y,3);fog()
  assert(S.caches[s].seen~=seen and S.caches[s].visible~=visible)
 end)
 test('空间索引与逐个膜口查询一致',function()
  local V=require('war.Vessels')
  for _,net in ipairs({W.vessels(s),V.forDisplay(s),V.forScale(1)})do
   for _,gate in ipairs(net.gates)do for _,offset in ipairs({0,.99,1.01})do for i=0,7 do
    local angle=i*math.pi/4;local x,y=gate.x+math.cos(angle)*gate.radius*offset,gate.y+math.sin(angle)*gate.radius*offset
    local expected;for _,q in ipairs(net.gates)do if (q.x-x)^2+(q.y-y)^2<=q.radius*q.radius then expected=q;break end end
    assert(net.gateAt(nil,x,y)==expected,'indexed gate changed')
   end end end
  end
 end)
 test('寻路可暂停继续，取消旧任务，待寻路状态可存读',function()
  P.reset();P.request(s,e,e.x+5,e.y+5,true);local j=P.jobs[1];assert(j)
  P.update(s,500,0);assert(P.jobs[1]==j and j.visits==0 and e.pathPending)
  local snap=require('war.Save').snapshot(s)
  for i=1,2000 do P.update(s,500,.0001);if not e.pathPending then break end end
  assert(not e.pathPending and not e.pathFailed and #e.path>0,'time slices never completed')
  local x,y,lane=e.x,e.y,e.vesselLane
  for _,p in ipairs(e.path)do local ok,nextLane=P.clear(s,x,y,p.x,p.y,e.faction,lane,p.lane);assert(ok);x,y,lane=p.x,p.y,nextLane end
  local restored=require('war.Save').restore(snap);assert(restored.entities[e.id] and not restored.entities[e.id].pathPending)
  P.request(s,e,e.x+4,e.y,true);C.order(s,e,{kind='move',x=e.x,y=e.y});P.update(s,500,.003);assert(#P.jobs==0)
 end)
 test('主菜单跳过隐藏世界绘制并保留逻辑尺寸',function()
  graphics={GetWidth=function()return 3840 end,GetHeight=function()return 2160 end,GetDPR=function()return 2 end}
  local old=S.draw;local calls=0;S.draw=function()calls=calls+1 end
  g.started=false;R.draw(g);assert(calls==0 and R.w==1920 and R.h==1080);g.started=true;S.draw=old
 end)
return results
''')
rows=[dict(row.items()) for row in results.values()]
Path('docs/performance-checks.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2))
print(json.dumps(rows,ensure_ascii=False))
assert all(r['pass'] for r in rows)
