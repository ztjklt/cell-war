-- Pure-Lua checks for the battle HUD layout model and the camera framing that relies on it.
-- Devices are given in CSS px; UI units follow UI.Scale.DEFAULT (DPR density adaptive).
local Q={}
local devices={
 {"桌面 1440x900",1440,900},{"真机窗口 1249x702",1249,702},{"平板 1024x768",1024,768},
 {"手机横屏 844x390",844,390},{"小手机横屏 667x375",667,375},
 {"手机竖屏 430x932",430,932},{"手机竖屏 360x780",360,780},
}
local function density(w,h) return math.max(.625,math.min(1,math.sqrt(math.min(w,h)/720))) end
function Q.run()
 local M=require('war.UIModel');local results={}
 local function test(name,fn) local ok,err=pcall(fn);results[#results+1]={name=name,pass=ok,error=ok and '' or tostring(err)} end
 local function inside(r,w,h) return r.x>=-.5 and r.y>=-.5 and r.x+r.w<=w+.5 and r.y+r.h<=h+.5 and r.w>0 and r.h>0 end
 for _,dev in ipairs(devices) do
  local name,cssW,cssH=dev[1],dev[2],dev[3];local d=density(cssW,cssH);local w,h=cssW/d,cssH/d
  for _,tall in ipairs({true,false}) do
   local L=M.battle(w,h,d,tall);local tag=name..(tall and " 竖长战场" or " 横宽战场")
   local parts={bar=L.bar,gauge=L.gauge,left=L.left,right=L.right,chip=L.chip,advisor=L.advisor,stage=L.stage}
   test(tag.." 各区域在屏幕内",function()
    for key,r in pairs(parts) do assert(inside(r,w,h),key..' 越界 '..string.format('%.0f,%.0f %.0fx%.0f',r.x,r.y,r.w,r.h)) end
   end)
   test(tag.." 各区域互不重叠",function()
    local keys={'bar','gauge','left','right','chip','advisor','stage'}
    for i=1,#keys do for j=i+1,#keys do
     assert(not M.overlap(parts[keys[i]],parts[keys[j]]),keys[i]..' 与 '..keys[j]..' 重叠')
    end end
   end)
   test(tag.." 按钮实际尺寸",function()
    local minPrimary=L.phone and 44 or 40
    assert(L.primary*d>=minPrimary-.01,'主按钮 '..L.primary*d)
    assert(L.secondary*d>=36-.01,'次按钮 '..L.secondary*d)
    assert(L.bar.h*d>=44-.01,'顶栏 '..L.bar.h*d)
   end)
  end
 end
 test("手机横屏 844x390 战场可视高度不低于 300",function()
  local d=density(844,390);local L=M.battle(844/d,390/d,d,true)
  assert(not L.stacked,'横屏不应叠放');assert(L.stage.h*d>=300,'stage '..L.stage.h*d)
 end)
 test("竖屏改为上下叠放，横屏保持左右分开",function()
  for _,dev in ipairs(devices) do local d=density(dev[2],dev[3]);local L=M.battle(dev[2]/d,dev[3]/d,d,true)
   assert(L.stacked==(dev[3]>dev[2]),dev[1]..' stacked='..tostring(L.stacked))
  end
 end)
 -- Camera framing in world pixels (CSS px), the same space the HUD writes into g.stage.
 local R=require('war.Render');local S=require('war.Simulation')
 local function world(r,d) return {x=r.x*d,y=r.y*d,w=r.w*d,h=r.h*d} end
 local function framed(g,x1,y1,x2,y2,stage,what)
  local ax,ay=R.project(g,x1,y1);local bx,by=R.project(g,x2,y2)
  assert(ax>=stage.x-1 and bx<=stage.x+stage.w+1 and ay>=stage.y-1 and by<=stage.y+stage.h+1,
   string.format('%s 超出可视区 (%.0f,%.0f)-(%.0f,%.0f) stage (%.0f,%.0f %.0fx%.0f)',what,ax,ay,bx,by,stage.x,stage.y,stage.w,stage.h))
 end
 for _,case in ipairs({{"气管",S.new(73)},{"旧鼻腔",S.new(73,"campaign",2)}}) do
  local s=case[2];local b=require('war.CampaignData').forState(s).bounds --[[@as {x:number,y:number,w:number,h:number}]]
  local tall=b.h>b.w
  for _,dev in ipairs(devices) do
   test(case[1].." 全景落在可视区 "..dev[1],function()
    local d=density(dev[2],dev[3]);R.w,R.h=dev[2],dev[3]
    local g={state=s,camera={x=0,y=0},zoom=1,stage=world(M.battle(dev[2]/d,dev[3]/d,d,tall).stage,d)}
    R.nasalOverview(g);framed(g,b.x,b.y,b.x+b.w,b.y+b.h,g.stage,'战场')
   end)
  end
 end
 for _,dev in ipairs(devices) do
  test("气管回营时屏障与出生点可见 "..dev[1],function()
   local s=S.new(73);local d=density(dev[2],dev[3]);R.w,R.h=dev[2],dev[3]
   local g={state=s,camera={x=0,y=0},zoom=1,stage=world(M.battle(dev[2]/d,dev[3]/d,d,true).stage,d)}
   R.home(g);local home=require('war.TracheaTerrain').home
   framed(g,home.x-4,home.y-4,home.x+4,home.y+4,g.stage,'出生点')
  end)
 end
 test("没有 HUD 数据时按密度 1 回退",function()
  local s=S.new(73);R.w,R.h=1440,900;local g={state=s,camera={x=0,y=0},zoom=1}
  R.nasalOverview(g);local b=require('war.CampaignData').forState(s).bounds --[[@as {x:number,y:number,w:number,h:number}]]
  framed(g,b.x,b.y,b.x+b.w,b.y+b.h,M.battle(1440,900,1,true).stage,'战场')
 end)
 local passed=0;for _,r in ipairs(results) do if r.pass then passed=passed+1 end end
 return {passed=passed,total=#results,results=results}
end
return Q
