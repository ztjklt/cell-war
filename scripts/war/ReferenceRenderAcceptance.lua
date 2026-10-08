-- Exercise the real renderer with a command-count backend; this is not native FPS evidence.
local Q={}
function Q.run()
 local R,W,S,U,Save,A=require('war.Render'),require('war.World'),require('war.Simulation'),require('war.Util'),require('war.Save'),require('war.ReferenceArt')
 local results={};local function test(name,fn) local ok,err=pcall(fn);results[#results+1]={name=name,pass=ok,error=ok and '' or tostring(err)} end
 local originals={};local bindings={};local calls=0;local frame={}
 local function bind(name,value) bindings[#bindings+1]=name;originals[name]=_G[name];_G[name]=value end
 for _,name in ipairs({'nvgBeginPath','nvgMoveTo','nvgLineTo','nvgBezierTo','nvgQuadTo','nvgClosePath','nvgRect','nvgEllipse','nvgCircle','nvgLineCap','nvgLineJoin','nvgStrokeWidth','nvgFillColor','nvgStrokeColor','nvgFillPaint','nvgFill','nvgStroke','nvgSave','nvgRestore','nvgTranslate','nvgScale','nvgRotate','nvgPathWinding','nvgEndFrame','nvgIntersectScissor','nvgFontFaceId','nvgFontSize','nvgTextAlign','nvgText'}) do bind(name,function() calls=calls+1 end) end
 for _,name in ipairs({'NVG_SOLID','NVG_HOLE','NVG_ROUND','NVG_ALIGN_CENTER','NVG_ALIGN_MIDDLE','NVG_IMAGE_GENERATE_MIPMAPS'}) do bind(name,1) end
 bind('nvgRGBA',function() return {} end);bind('nvgLinearGradient',function() return {} end);bind('nvgRadialGradient',function() return {} end);bind('nvgImagePattern',function() return {} end)
 bind('nvgCreateImage',function() return 1 end);bind('nvgDeleteImage',function() end)
 bind('nvgBeginFrame',function(_,w,h,dpr) frame={w,h,dpr} end)
 local function viewport(w,h,dpr) _G.graphics={GetWidth=function() return w*dpr end,GetHeight=function() return h*dpr end,GetDPR=function() return dpr end} end
 bind('graphics',{})
 local oldVG,oldW,oldH=R.vg,R.w,R.h;R.vg={}
 local s=S.new(73);local g={state=s,selection={},camera={x=1023,y=1050},zoom=1,accumulator=0,realTime=0,started=true,fogDisabled=false}
 local function same(a,b)
  if type(a)~='table' then return a==b end;if type(b)~='table' then return false end
  for k,v in pairs(a) do if not same(v,b[k]) then return false end end;for k in pairs(b) do if a[k]==nil then return false end end;return true
 end
 test('DPR 1/2/3 使用逻辑画幅、真实像素比及相同投影',function()
  for _,size in ipairs({{1920,1080},{844,390},{430,932}}) do local previous
   for dpr=1,3 do viewport(size[1],size[2],dpr);R.draw(g);assert(frame[1]==size[1] and frame[2]==size[2] and frame[3]==dpr)
    local x,y=R.project(g,1024,1050);local current={x,y,A.last.regions,A.last.details}
    if previous then assert(same(previous,current),'DPR changes geometry') end;previous=current
   end
  end
 end)
 test('连续缩放裁剪、绘制预算和缓存有界，浏览不改存档',function()
  viewport(1440,900,2);local before=Save.snapshot(s)
  for i=0,36 do g.zoom=.003+(2.8-.003)*i/36;g.camera={x=i%3==0 and 1023 or 1004,y=i%3==0 and 1050 or 1942};calls=0;R.draw(g)
   assert(A.last.details<=256 and (A.last.flow or 0)<=48 and A.last.regions<800,'unbounded visible geometry')
   assert(calls<30000,'command budget exceeded')
  end
  local count=0;for _ in pairs(A.detailCache) do count=count+1 end;assert(count<=1024)
  assert(same(before,Save.snapshot(s)),'view modified simulation state')
 end)
 test('全身浏览及强制旧全图标志不泄露敌人和未发现资源',function()
  local C,Cells,B=require('war.Commands'),require('war.Cells'),require('war.BodyArt');local oldCell,oldResource=Cells.draw,B.resource
  local seenCells,seenResources={},{};Cells.draw=function(_,_,_,_,_,_,_,id) seenCells[id]=true end;B.resource=function(_,_,_,r) seenResources[U.key(r.x,r.y)]=true end
  local ok,err=pcall(function()
   local q=W.generate(73);W.rebuild(q);local own=C.spawn(q,'unit','scout',1,1020,1050);local enemy=C.spawn(q,'unit','virus',2,1027,1055);assert(own and enemy)
   local k1,k2=U.key(1024,1060),U.key(1026,1060);q.resources={[k1]={kind='wood',amount=10,x=1024,y=1060},[k2]={kind='wood',amount=10,x=1026,y=1060}}
   q.factions[1].visible={};q.factions[1].seen={[k1]=true};g.state=q;g.fogDisabled=true;g.zoom=1;g.camera={x=1023,y=1050};viewport(1280,900,1);R.draw(g)
   assert(seenCells[own.id] and not seenCells[enemy.id],'hidden enemy drawn')
   assert(seenResources[k1] and not seenResources[k2],'undiscovered resource drawn')
  end)
  Cells.draw,B.resource=oldCell,oldResource;g.state=s;g.fogDisabled=false;assert(ok,err)
 end)
 test('回营近景在手机竖屏保留两侧管壁和可选单位比例',function()
  for _,size in ipairs({{1440,900},{844,390},{430,932},{360,780}}) do viewport(size[1],size[2],1);R.w,R.h=size[1],size[2];R.home(g)
   local x=R.project(g,1004,g.camera.y);local xx=R.project(g,1040,g.camera.y)
   assert(g.zoom>=.14 and x>=0 and xx<=R.w,'airway walls outside phone view')
  end
 end)
 R.vg,R.w,R.h=oldVG,oldW,oldH;for _,name in ipairs(bindings) do _G[name]=originals[name] end
 local passed=0;for _,r in ipairs(results) do if r.pass then passed=passed+1 end end;return {passed=passed,total=#results,results=results}
end
return Q
