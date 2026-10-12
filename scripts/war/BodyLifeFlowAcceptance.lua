-- Pure display contracts, no claim of native visual/performance acceptance.
local Q={}
function Q.run()
 local F=require('war.BodyLifeFlow');local D=require('war.BodyLifeFlowData')
 local results={};local s={anatomyVersion=4,time=421,rng=371,campaign=nil}
 local function test(name,fn) local ok,err=pcall(fn);results[#results+1]={name=name,pass=ok,error=ok and '' or tostring(err)} end
 test('血流逐段颜料、显示方向与隐藏边契约',function()
  local c=F.prepare(s);local reversed,overridden=0,0
  for id,e in ipairs(c.net.edges) do
   local d=D.edges[id];assert(d.name==e.name)
   if e.hidden then assert(#d.spans==0) end
   if e.system=='vein' and d.flowSign==-1 then reversed=reversed+1 end
   for _,p in ipairs(d.spans) do
    assert(p[1]>=0 and p[2]<=e.length and p[2]>p[1] and p[3]>0)
    assert(p[4]==1 or p[4]==-1);assert(p[5]==1 or p[5]==-1)
    local system=p[4]==1 and 'artery' or 'vein'
    if system~=e.system then overridden=overridden+1;assert(p[5]==-d.flowSign) else assert(p[5]==d.flowSign) end
   end
  end
  assert(reversed==16 and overridden>0)
  local byName={};for _,e in pairs(c.edges) do byName[e.curve.name]=e end
  assert(byName['heart.v → cava_upper'].flowSign==-1)
  assert(byName['head_r.v → heart.v'].flowSign==1)
  assert(byName['wrist_r.v → elbow_r.v'].flowSign==1)
  assert(byName['elbow_r.v → wrist_r.v'].flowSign==-1)
 end)
 test('血流预算、小地图简化与全身区域覆盖',function()
  local seen={}
  for frame=0,180 do
   local t=frame/12
   local far=F.sample(s,t,.007,0,2048,512,3584)
   local near=F.sample(s,t,.4,0,2048,512,3584)
   local mini=F.sample(s,t,.007,0,2048,512,3584,{mini=true})
   assert(#far.streaks<=24 and #far.cells==0 and #near.cells<=48 and #near.streaks==0)
   assert(#mini.streaks<=6 and #mini.cells==0)
   for _,p in ipairs(far.streaks) do seen[p.region]=true end
  end
  for i=1,6 do assert(seen[i],'missing region '..i) end
 end)
 test('全身尺度优先稳定宽长段而非短碎闪点',function()
  local regionStats={};for i=1,6 do regionStats[i]={count=0,width=0,length=0,lanes={}} end
  for frame=0,179 do
   local r=F.sample(s,frame/12,.006,0,2048,512,3584)
   assert(#r.streaks<=24)
   for _,p in ipairs(r.streaks) do
    local a=regionStats[p.region];a.count=a.count+1
    a.width=a.width+p.width*.192;a.length=a.length+(p.b-p.a)*.192
    a.lanes[p.edge..':'..p.span]=true
    local span=F.prepare(s).edges[p.edge].spans[p.span]
    assert(p.a>=span.a and p.b<=span.b and p.width==span.width)
   end
  end
  for _,a in ipairs(regionStats) do
   local count=0;for _ in pairs(a.lanes) do count=count+1 end
   assert(a.count>0 and count<=4,'viewport lane selection changed with time')
   assert(a.width/a.count>.43,'atlas flow too narrow to resolve')
   assert(a.length/a.count>2.9,'atlas flow remains a short flashing dot')
  end
 end)
 test('静态视口lane缓存精确命中且八项环形有界',function()
  local cache=F.prepare(s)
  local function sample(x,options) return F.sample(s,2.375,.006,x,1931.125,601.25,3451.5,options) end
  local function signature(r)
   local p={};for _,v in ipairs(r.streaks) do p[#p+1]=table.concat({v.edge,v.span,v.head,v.a,v.b,v.alpha},',') end
   return table.concat(p,';')
  end
  local first=signature(sample(101.125));local builds=cache.laneBuilds
  for i=1,20 do sample(101.125) end
  assert(cache.laneBuilds==builds,'stationary view reselected lanes')
  sample(101.125+1e-10);assert(cache.laneBuilds==builds+1,'nearby pan aliased bounds')
  sample(101.125,{mini=true});assert(cache.laneBuilds==builds+2,'mini budget reused full lanes')
  for i=1,12 do sample(102.25+i) end
  local count=0;for _,lanes in pairs(cache.laneCache) do count=count+1;assert(#lanes<=24) end
  assert(count==8 and #cache.laneKeys==8 and cache.laneCursor>=1 and cache.laneCursor<=8)
  assert(first==signature(sample(101.125)),'eviction changed playback phase or lane selection')
 end)
 test('真实时钟决定相位、视口不重置、模拟与图不变',function()
  local c=F.prepare(s);local original=c.net.edges[18];local a,b,system=original.a,original.b,original.system
  local geometry={}
  for id,e in ipairs(c.net.edges) do
   local p={e.a,e.b,e.system,e.length,e.width}
   for _,q in ipairs(e.points) do p[#p+1]=q[1];p[#p+1]=q[2] end
   geometry[id]=table.concat(p,',')
  end
  local function signature(r)
   local parts={}
   for _,p in ipairs(r.streaks) do parts[#parts+1]=table.concat({p.edge,p.span,p.head,p.a,p.b,p.flowSign},',') end
   return table.concat(parts,';')
  end
  local first=signature(F.sample(s,3.125,.007,0,2048,512,3584))
  F.sample(s,24,.5,850,1000,1000,1500)
  assert(first==signature(F.sample(s,3.125,.007,0,2048,512,3584)))
  for _,fps in ipairs({30,60,120}) do
   local t=15*fps/fps
   assert(F.phase(t,45,1,false)==F.phase(15,45,1,false))
  end
  for _,sign in ipairs({-1,1}) do
   local x,spacing=F.phase(1.234,45,sign,false);local y=F.phase(1.235,45,sign,false)
   assert(math.abs(((y-x)*sign)%spacing-.032)<1e-8)
  end
  assert(s.time==421 and s.rng==371 and original.a==a and original.b==b and original.system==system)
  for id,e in ipairs(c.net.edges) do
   local p={e.a,e.b,e.system,e.length,e.width}
   for _,q in ipairs(e.points) do p[#p+1]=q[1];p[#p+1]=q[2] end
   assert(geometry[id]==table.concat(p,','))
  end
 end)
 test('交接总预算48、逐项连续淡入与强度开关',function()
  local function values(r)
   local map={}
   for _,kind in ipairs({'streaks','cells'}) do
    for _,p in ipairs(r[kind]) do map[kind..':'..p.edge..':'..p.span..':'..p.head]=p.alpha end
   end
   return map
  end
  for step=0,160 do
   local zoom=.17+step*.001
   local a=F.sample(s,3.125,zoom,0,2048,512,3584)
   local b=F.sample(s,3.125,zoom+1e-7,0,2048,512,3584)
   assert(#a.streaks+#a.cells<=48 and #b.streaks+#b.cells<=48)
   local av,bv=values(a),values(b)
   for key,alpha in pairs(av) do assert(math.abs(alpha-(bv[key] or 0))<.001) end
   for key,alpha in pairs(bv) do assert(math.abs(alpha-(av[key] or 0))<.001) end
  end
  local full=values(F.sample(s,3.125,.25,0,2048,512,3584))
  local dim=values(F.sample(s,3.125,.25,0,2048,512,3584,{intensity=.25}))
  for key,alpha in pairs(full) do assert(math.abs(dim[key]-alpha*.25)<1e-10) end
  local zero=F.sample(s,3.125,.25,0,2048,512,3584,{intensity=0})
  assert(#zero.streaks==0 and #zero.cells==0)
 end)
 test('每条亮纹一次渐变stroke、最大24且绘制状态恢复',function()
  local names={'nvgSave','nvgRestore','nvgLineCap','nvgLineJoin','nvgBeginPath','nvgMoveTo','nvgLineTo',
   'nvgStrokeWidth','nvgStrokePaint','nvgLinearGradient','nvgRGBA','nvgStroke','nvgTranslate','nvgRotate'}
  local old={};for _,name in ipairs(names) do old[name]=_G[name];_G[name]=function() end end
  local depth,strokes,gradients,paints,lines=0,0,0,0,0
  _G.nvgSave=function() depth=depth+1 end
  _G.nvgRestore=function() depth=depth-1;assert(depth>=0) end
  _G.nvgRGBA=function(r,g,b,a) assert(a>=0 and a<=255);return {r,g,b,a} end
  _G.nvgLinearGradient=function(vg,x,y,tx,ty,a,b) gradients=gradients+1;return {a=a,b=b} end
  _G.nvgStrokePaint=function(vg,paint) paints=paints+1;assert(paint.a and paint.b) end
  _G.nvgLineTo=function() lines=lines+1 end
  _G.nvgStroke=function() strokes=strokes+1 end
  local ok,err=pcall(function()
   local R={vg={},project=function(g,x,y) return x*g.zoom*32,y*g.zoom*32 end,ellipse=function() end}
   local g={zoom=.007,realTime=1.2}
   local r=F.draw(R,g,s,0,2048,512,3584)
   assert(strokes==r.streaks and strokes>0 and strokes<=24)
   assert(gradients==strokes and paints==strokes and lines>strokes and depth==0)
   strokes,gradients,paints,lines=0,0,0,0;g.zoom=.25
   r=F.draw(R,g,s,0,2048,512,3584)
   assert(strokes==r.streaks and r.streaks+r.cells<=48 and depth==0)
   strokes=0;F.draw(R,g,s,0,2048,512,3584,{intensity=0})
   assert(strokes==0 and depth==0)
  end)
  for _,name in ipairs(names) do _G[name]=old[name] end
  assert(ok,err)
 end)
 test('显示层兼容旧版、裁剪、开关、尺寸与方向',function()
  assert(F.prepare({anatomyVersion=3})==nil)
  assert(#F.sample({anatomyVersion=3},0,1,0,2048,512,3584).cells==0)
  local b=F.sample(s,4,.4,760,880,2400,2700)
  for _,p in ipairs(b.cells) do
   assert(p.x>=760 and p.x<=880 and p.y>=2400 and p.y<=2700)
   assert(p.radius>=0 and p.radius<=p.width*.32)
  end
  local enabled=F.enabled;F.enabled=false
  local r=F.sample(s,4,.007,0,2048,512,3584);F.enabled=enabled
  assert(#r.cells==0 and #r.streaks==0)
 end)
 local passed=0;for _,r in ipairs(results) do if r.pass then passed=passed+1 end end
 return {passed=passed,total=#results,results=results}
end
return Q
