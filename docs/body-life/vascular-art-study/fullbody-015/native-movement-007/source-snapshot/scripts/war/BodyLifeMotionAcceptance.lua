-- Pure mathematical contracts; these do not stand in for native visual testing.
local A={}
function A.run()
 local M=require('war.BodyLifeMotion');local results={}
 local function test(name,fn) local ok,err=pcall(fn);results[#results+1]={name=name,pass=ok,error=ok and '' or tostring(err)} end
 local function equal(a,b) return math.abs(a-b)<1e-9 end
 test('周期在 30/60/120 FPS 采样中一致，且不读取随机数',function()
  local random=math.random;math.random=function() error('visual math read RNG') end
  local ok,err=pcall(function()
   for id,period in pairs({heart=1,lung_r=4.8,stomach=8,small_intestine=10,large_intestine=12}) do
    for _,fps in ipairs({30,60,120}) do
     for frame=0,fps*12 do
      local t=frame/fps;local a,b=M.sample(t,id),M.sample(t+period,id)
      assert(equal(a.phase,b.phase))
      if id=='heart' then assert(equal(a.beat,b.beat)) elseif id=='lung_r' then assert(equal(a.breath,b.breath)) end
      assert(#a.segments==#b.segments)
      for i,s in ipairs(a.segments) do assert(s.index==b.segments[i].index and equal(s.weight,b.segments[i].weight)) end
     end
    end
   end
  end)
  math.random=random;assert(ok,err)
 end)
 test('心跳快收缩、回弹、停顿，呼吸 40/60 比例',function()
  assert(equal(M.sample(.13,'heart').beat,-1))
  assert(equal(M.sample(.39,'heart').beat,.32))
  assert(equal(M.sample(.8,'heart').beat,0))
  assert(equal(M.sample(0,'lung_r').breath,0))
  assert(equal(M.sample(1.92,'lung_r').breath,1))
  assert(equal(M.sample(4.8,'lung_r').breath,0))
 end)
 test('胃肠相邻段依次推进，最多两段且周期边界连续',function()
  for id,period in pairs({stomach=8,small_intestine=10,large_intestine=12}) do
   local last=0;local seen={}
   for frame=0,period*120-1 do
    local segments=M.activeSegments(frame/120,id);assert(#segments<=2)
    local total=0
    for _,s in ipairs(segments) do total=total+s.weight;seen[s.index]=true;assert(s.weight>0 and s.weight<=1) end
    assert(total<=1+1e-10)
    if #segments==2 then assert(segments[2].index==segments[1].index+1) end
    if #segments>0 then assert(segments[1].index>=last);last=segments[1].index end
   end
   for i=1,#M.paths[id] do assert(seen[i]) end
   for _,t in ipairs({0,period-1e-7,period+1e-7}) do
    local total=0;for _,s in ipairs(M.activeSegments(t,id)) do total=total+s.weight end
    assert(total<1e-8)
   end
  end
 end)
 test('网格总预算、固定边界、像素幅度及全相位不翻折',function()
  local triangles=0
  for id,s in pairs(M.specs) do
   triangles=triangles+2*s.nx*s.ny
   for _,zoom in ipairs({.003,.0074,.032,.084,.1,.149,.15,.6}) do
    local scale=64*zoom
    for frame=0,1440 do
     local t=frame/120;local q=M.sample(t,id);local target={}
     for iy=0,s.ny do for ix=0,s.nx do
      local border=ix==0 or ix==s.nx or iy==0 or iy==s.ny
      local v={x=s.x+s.w*ix/s.nx,y=s.y+s.h*iy/s.ny,weight=border and 0 or 1}
      local dx,dy=M.offset(id,v,s,t,scale,zoom,q)
      if border or zoom>=.15 or s.h*scale<=16 then assert(dx==0 and dy==0) end
      local cap=id=='heart' and 1.5 or ((id=='lung_r' or id=='lung_l') and 2 or 1)
      assert(math.sqrt(dx*dx+dy*dy)*scale<=cap+1e-9)
      target[#target+1]={x=v.x+dx,y=v.y+dy}
     end end
     local function positive(a,b,c) return (b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x)>1e-5 end
     for iy=0,s.ny-1 do for ix=0,s.nx-1 do
      local a=iy*(s.nx+1)+ix+1;local b=a+1;local c=a+s.nx+1;local d=c+1
      assert(positive(target[a],target[b],target[d]) and positive(target[a],target[d],target[c]))
     end end
    end
   end
  end
  assert(triangles<=384)
 end)
 test('小器官灌流低幅、相位差固定且膀胱跟随呼吸',function()
  for frame=0,1200 do
   local t=frame/120
   for _,id in ipairs({'brain','liver','pancreas','kidney_r','kidney_l','bladder'}) do assert(math.abs(M.sample(t,id).perfusion)<=.03) end
   assert(equal(M.sample(t,'bladder').perfusion,M.sample(t+4.8,'bladder').perfusion))
   assert(equal(M.sample(t,'kidney_r').perfusion,M.sample(t+1,'kidney_r').perfusion))
  end
  assert(not equal(M.sample(.1,'kidney_r').perfusion,M.sample(.1,'kidney_l').perfusion))
 end)
 test('消化收缩局限于移动段，远离活动组织保持固定',function()
  for id,s in pairs(M.specs) do if M.paths[id] then
   local moved=false
   for frame=0,120 do
    local t=frame/10
    local dx,dy=M.offset(id,{x=s.x-100,y=s.y-100,weight=1},s,t,2,.03)
    assert(dx==0 and dy==0)
    for _,p in ipairs(M.paths[id]) do
     local x,y=M.offset(id,{x=p[1]+4,y=p[2]+4,weight=1},s,t,2,.03)
     moved=moved or math.abs(x)+math.abs(y)>1e-6
    end
   end
   assert(moved)
  end end
 end)
 local passed=0;for _,r in ipairs(results) do if r.pass then passed=passed+1 end end
 return {passed=passed,total=#results,results=results}
end
return A
