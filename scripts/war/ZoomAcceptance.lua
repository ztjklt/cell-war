-- Render-budget regression checks; no-op NanoVG counts commands, not native FPS.
local QA={}
function QA.run()
 local D,U,W,R,View,Art,Save,I=require('war.Data'),require('war.Util'),require('war.World'),require('war.Render'),require('war.View'),require('war.TerrainArt'),require('war.Save'),require('war.Input')
 local originals={};local function replace(name,fn) originals[name]=_G[name];_G[name]=fn end
 local counters={fill=0,stroke=0,rect=0,terrain=0,generate=0}
 for _,name in ipairs({'nvgPathWinding','nvgLineCap','nvgLineJoin','nvgIntersectScissor','nvgBeginPath','nvgMoveTo','nvgLineTo','nvgBezierTo','nvgQuadTo','nvgClosePath','nvgCircle','nvgArc','nvgEllipse','nvgStrokeWidth','nvgFillColor','nvgStrokeColor','nvgFillPaint','nvgFontFaceId','nvgFontSize','nvgTextAlign','nvgText','nvgSave','nvgRestore','nvgTranslate','nvgRotate','nvgScale','nvgBeginFrame','nvgEndFrame'}) do replace(name,function() end) end
 replace('nvgRect',function() counters.rect=counters.rect+1 end)
 replace('nvgFill',function() counters.fill=counters.fill+1 end)
 replace('nvgStroke',function() counters.stroke=counters.stroke+1 end)
 replace('nvgRGBA',function(r,g,b,a) return {r,g,b,a} end)
 replace('nvgLinearGradient',function() return {} end);replace('nvgRadialGradient',function() return {} end)
 replace('NVG_SOLID',1);replace('NVG_HOLE',2);replace('NVG_ROUND',1);replace('NVG_IMAGE_GENERATE_MIPMAPS',1);replace('NVG_ALIGN_CENTER',1);replace('NVG_ALIGN_MIDDLE',2)
 replace('graphics',{GetDPR=function() return 1 end,GetWidth=function() return 1920 end,GetHeight=function() return 1080 end})
 local terrain,ensure,oldVG=W.terrain,W.ensureChunk,R.vg
 W.terrain=function(...) counters.terrain=counters.terrain+1;return terrain(...) end
 W.ensureChunk=function(...) counters.generate=counters.generate+1;return ensure(...) end
 R.vg={}
 local s=require('war.Simulation').new(73,'sandbox')
 local g={state=s,camera={x=1187,y=1753},zoom=.24,selection={},accumulator=0,realTime=0,vesselSurvey=true,fogDisabled=true}
 local results={};local function test(name,fn) local ok,err=pcall(fn);results[#results+1]={name=name,pass=ok,error=ok and '' or tostring(err)} end
 local function expect(ok,message) assert(ok,message) end
 local function reset() counters={fill=0,stroke=0,rect=0,terrain=0,generate=0} end
 local function equal(a,b)
  if type(a)~='table' then return a==b end;if type(b)~='table' then return false end
  for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
  for k in pairs(b) do if a[k]==nil then return false end end;return true
 end
 test('缩小、全身与平移时绘制量不随地图格数爆炸',function()
  for _,zoom in ipairs({.5,.24,.1,.03,View.minZoom(s,1920,1080)}) do
   g.zoom=zoom
   for _,p in ipairs({{1187,1753},{1024,2048},{1350,3650}}) do
    g.camera.x,g.camera.y=p[1],p[2];reset();R.draw(g)
    expect(counters.terrain<=96 and counters.generate==0,'zoom performed unbounded generation/query work')
    expect(counters.fill<250 and counters.stroke<300 and counters.rect<4000,'zoom exceeded geometry budget')
   end
  end
 end)
 test('远景与全身总览不修改资源、探索、随机数或存档',function()
  local before=Save.snapshot(s)
  for _,zoom in ipairs({.24,.01,.003}) do g.zoom=zoom;R.draw(g);R.minimap(R.vg,g,{x=10,y=10,w=600,h=800},true) end
  expect(equal(before,Save.snapshot(s)),'camera changed saved gameplay state')
 end)
 test('大地图与旧地图均能缩到全貌，指针缩放锚点保持',function()
  for _,state in ipairs({s,W.generate(73,false,'body-v3')}) do
   local min=View.minZoom(state,1920,1080)
   expect(D.width(state)*32*min<=1920 and D.height(state)*32*min<=1080,'whole map does not fit')
   g.state=state;g.zoom=.24;g.camera={x=D.width(state)*.5,y=D.height(state)*.5}
   local wx,wy=R.unproject(g,1030,510);R.zoom(g,.8,1030,510);local ax,ay=R.unproject(g,1030,510)
   expect(math.abs(wx-ax)<.0001 and math.abs(wy-ay)<.0001,'zoom anchor moved')
  end
  g.state=s
 end)
 test('重新放大恢复近景，回营恢复可操作比例',function()
  g.camera={x=1149,y=1750};g.zoom=1;reset();R.draw(g)
  expect(R.terrainStride==1 and counters.terrain<=64 and counters.stroke>0,'near geometry or bounded detail was not restored')
  g.zoom=View.minZoom(s,1920,1080);R.home(g);expect(g.zoom>=.14,'home kept unreadable strategic zoom')
 end)
 test('战略视图可以点选玩家单位，敌方仍受迷雾限制',function()
  ---@type {x:number,y:number}|false
  local own=false;for _,e in pairs(s.entities) do if e.faction==1 and e.category=='unit' then own=e;break end end
  local ally=own --[[@as {x:number,y:number}]]
  g.camera={x=ally.x,y=ally.y};g.zoom=.01;g.fogDisabled=false;g.vesselSurvey=false
  local px,py=R.project(g,ally.x,ally.y);local picked=I.pick(g,px+2,py+2)
  expect(picked and picked.faction==1,'strategic marker cannot be selected')
  for _,e in pairs(s.entities) do if e.faction==2 then g.camera={x=e.x,y=e.y};px,py=R.project(g,e.x,e.y);expect(not I.pick(g,px,py),'hidden enemy marker selectable');break end end
 end)
 W.terrain,W.ensureChunk,R.vg=terrain,ensure,oldVG
 for name,value in pairs(originals) do _G[name]=value end
 -- Nil originals do not appear in a Lua table; remove every test-only binding.
 for _,name in ipairs({'NVG_SOLID','NVG_HOLE','NVG_ROUND','NVG_IMAGE_GENERATE_MIPMAPS','NVG_ALIGN_CENTER','NVG_ALIGN_MIDDLE','graphics','nvgPathWinding','nvgLineCap','nvgLineJoin','nvgIntersectScissor','nvgBeginPath','nvgMoveTo','nvgLineTo','nvgBezierTo','nvgQuadTo','nvgClosePath','nvgCircle','nvgArc','nvgEllipse','nvgStrokeWidth','nvgFillColor','nvgStrokeColor','nvgFillPaint','nvgFontFaceId','nvgFontSize','nvgTextAlign','nvgText','nvgSave','nvgRestore','nvgTranslate','nvgRotate','nvgScale','nvgBeginFrame','nvgEndFrame','nvgRect','nvgFill','nvgStroke','nvgRGBA','nvgLinearGradient','nvgRadialGradient'}) do if originals[name]==nil then _G[name]=nil end end
 local passed=0;for _,r in ipairs(results) do if r.pass then passed=passed+1 end end
 return {passed=passed,total=#results,results=results}
end
return QA
