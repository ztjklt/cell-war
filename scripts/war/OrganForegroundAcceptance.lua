-- Fixed selective foreground contracts; source-pigment coverage is audited offline.
local Q={}
function Q.run()
 local F=require('war.OrganForeground');local results={}
 local function test(name,fn) local ok,err=pcall(fn);results[#results+1]={name=name,pass=ok,error=ok and '' or tostring(err)} end
 test('仅胸部蓝前景和冠脉两组完整轮廓',function()
  local groups=F.prepare();assert(#groups==2)
  assert(groups[1].kind=='blue' and groups[2].kind=='coronary')
  for _,g in ipairs(groups) do
   local roi=g.kind=='blue' and {360,656,270,490} or {478,556,390,458}
   assert(#g.paths>0)
   for _,p in ipairs(g.paths) do
    assert(#p.points>=3)
    for _,v in ipairs(p.points) do assert(v[1]>=roi[1] and v[1]<=roi[2] and v[2]>=roi[3] and v[2]<=roi[4]) end
   end
  end
 end)
 test('两次渐变fill、无stroke、旧版与视口裁剪',function()
  local names={'nvgSave','nvgRestore','nvgBeginPath','nvgMoveTo','nvgLineTo','nvgClosePath','nvgPathWinding',
   'nvgFillPaint','nvgLinearGradient','nvgRGBA','nvgFill','nvgStroke'}
  local old={};for _,name in ipairs(names) do old[name]=_G[name];_G[name]=function() end end
  local depth,fills,gradients,alpha=0,0,0,0;local positions={}
  _G.nvgSave=function() depth=depth+1 end;_G.nvgRestore=function() depth=depth-1 end
  _G.nvgMoveTo=function(vg,x,y) positions[#positions+1]=x;positions[#positions+1]=y end
  _G.nvgLineTo=_G.nvgMoveTo
  _G.nvgRGBA=function(r,g,b,a) alpha=math.max(alpha,a);return {} end
  _G.nvgLinearGradient=function() gradients=gradients+1;return {} end
  _G.nvgFill=function() fills=fills+1 end
  _G.nvgStroke=function() error('fixed foreground must not use a stroke') end
  local random=math.random;math.random=function() error('foreground changed random state') end
  local ok,err=pcall(function()
   local R={vg={},project=function(g,x,y) return x*32*g.zoom,y*32*g.zoom end};local g={zoom=.14,realTime=0};local s={anatomyVersion=4}
   F.draw(R,g,s,0,2048,512,3584);assert(fills==0)
   g.zoom=.4;F.draw(R,g,s,0,2048,512,3584)
   assert(fills==2 and gradients==2 and depth==0 and alpha==255)
   local fixed=table.concat(positions,',');positions={};g.realTime=600;R.vg={}
   F.draw(R,g,s,0,2048,512,3584);assert(fixed==table.concat(positions,','))
   fills=0;F.draw(R,g,{anatomyVersion=3},0,2048,512,3584);assert(fills==0)
   F.draw(R,g,s,0,40,0,40);assert(fills==0)
   F.draw(R,g,s,840,898,1200,1280);assert(fills==1 and depth==0)
  end)
  math.random=random;for _,name in ipairs(names) do _G[name]=old[name] end
  assert(ok,err)
 end)
 local passed=0;for _,r in ipairs(results) do if r.pass then passed=passed+1 end end
 return {passed=passed,total=#results,results=results}
end
return Q
