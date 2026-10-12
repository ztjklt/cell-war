-- Historical anatomy-v2 fixtures are explicit; ReferenceAcceptance covers the new default.
-- Geometry, fog, cache and resolution regressions for the continuous surface.
local QA={}
function QA.run()
 local C,D,U,W,S=require('war.Contour'),require('war.Data'),require('war.Util'),require('war.World'),require('war.SmoothTerrain')
 local results={};local function test(name,fn) local ok,err=pcall(fn);results[#results+1]={name=name,pass=ok,error=ok and '' or tostring(err)} end
 test('轮廓保留内部空洞，裁剪排除屏幕外几何',function()
  local cells={};for y=1,3 do for x=1,3 do if not (x==2 and y==2) then cells[C.key(x,y)]={x,y} end end end
  local paths=C.build(cells,1);assert(#paths==2,'ring holes lost');local holes=0
  for _,p in ipairs(paths) do if p.hole then holes=holes+1 end;assert(not C.clip(p,10,20,10,20),'offscreen contour retained') end
  assert(holes==1,'wrong ring winding')
  local p={points={{-100,-100},{100,-100},{100,100},{-100,100}},hole=false,x1=-100,y1=-100,x2=100,y2=100}
  local clipped=C.clip(p,-2,2,-3,3);assert(clipped and #clipped.points==4)
  for _,q in ipairs(clipped.points) do assert(q[1]>=-2 and q[1]<=2 and q[2]>=-3 and q[2]<=3) end
 end)
 test('地图曲线按世界和种子缓存，旧尺寸仍可准备',function()
  for _,s in ipairs({W.generate(73,nil,nil,nil,2),W.generate(73,false,'body-v4')}) do
   S.prepare(s);local a=S.caches[s].body;assert(#a>0);S.prepare(s);assert(S.caches[s].body==a,'zoom should not rebuild body')
   for _,p in ipairs(a) do assert(p.x1>=0 and p.x2<=D.width(s) and p.y1>=0 and p.y2<=D.height(s)) end
  end
 end)
 test('远景保留二次曲线，取消大格矩形，DPR 不改变投影',function()
  local R,View=require('war.Render'),require('war.View');local s=W.generate(73,nil,nil,nil,2);W.rebuild(s)
  local g={state=s,camera={x=D.width(s)*.5,y=D.height(s)*.5},zoom=View.minZoom(s,1280,800),selection={},fogDisabled=true,vesselSurvey=true,accumulator=0,realTime=0}
  local oldGraphics,oldVG,oldQuad,oldRect=graphics,R.vg,nvgQuadTo,nvgRect;local originals={};local names={'nvgBeginPath','nvgMoveTo','nvgLineTo','nvgBezierTo','nvgClosePath','nvgPathWinding','nvgLineCap','nvgLineJoin','nvgEllipse','nvgCircle','nvgFillColor','nvgStrokeColor','nvgStrokeWidth','nvgFillPaint','nvgFill','nvgStroke','nvgSave','nvgRestore','nvgTranslate','nvgScale','nvgRotate','nvgBeginFrame','nvgEndFrame','nvgFontFaceId','nvgFontSize','nvgTextAlign','nvgText','nvgIntersectScissor','nvgRGBA','nvgLinearGradient','nvgRadialGradient','NVG_SOLID','NVG_HOLE','NVG_ROUND','NVG_ALIGN_CENTER','NVG_ALIGN_MIDDLE'}
  local quad,rect=0,0
  for _,name in ipairs(names) do originals[name]=_G[name];_G[name]=function() return {} end end
  NVG_SOLID=1;NVG_HOLE=2;NVG_ROUND=1;NVG_ALIGN_CENTER=1;NVG_ALIGN_MIDDLE=2
  nvgQuadTo=function() quad=quad+1 end;nvgRect=function() rect=rect+1 end;R.vg={}
  local ok,err=pcall(function()
   local lastX,lastY
   for _,dpr in ipairs({1,2,3}) do graphics={GetDPR=function() return dpr end,GetWidth=function() return 1280*dpr end,GetHeight=function() return 800*dpr end}
    R.draw(g);local x,y=R.project(g,1000,2000);if lastX then assert(x==lastX and y==lastY,'DPR shifted camera') end;lastX,lastY=x,y
   end
   assert(quad>100 and rect<20,'far view reverted to rectangles')
  end)
  graphics,R.vg,nvgQuadTo,nvgRect=oldGraphics,oldVG,oldQuad,oldRect;for _,name in ipairs(names) do _G[name]=originals[name] end;assert(ok,err)
 end)
 local passed=0;for _,r in ipairs(results) do if r.pass then passed=passed+1 end end
 return {passed=passed,total=#results,results=results}
end
return QA
