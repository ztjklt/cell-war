-- Visual animation contracts; this suite does not claim native GPU/visual acceptance.
local Q={}
function Q.run()
 local B=require('war.BodyLife');local results={}
 local configuredLayers=0;local assets=require('war.BodyLifeAssets')
 for _,kind in ipairs({'source','tissue','foreground'}) do if assets[kind] then configuredLayers=configuredLayers+1 end end
 local function test(name,fn) local ok,err=pcall(fn);results[#results+1]={name=name,pass=ok,error=ok and '' or tostring(err)} end
 test('采样独立于帧率、暂停与模拟倍速',function()
  for _,fps in ipairs({30,60,120}) do
   for frame=0,fps*15 do local t=frame/fps;local a=B.sample(t,'heart');local b=B.sample(t,'heart')
    assert(a.beat==b.beat and a.breath==b.breath)
   end
  end
  assert(math.abs(B.sample(.13,'heart').beat-B.sample(10.13,'heart').beat)<1e-10)
  assert(math.abs(B.sample(1.92,'lung_r').breath-B.sample(6.72,'lung_r').breath)<1e-10)
 end)
 for _,key in ipairs({'heart','lung_r','lung_l','stomach','small_intestine','large_intestine'}) do
  test(key..' 固定锚点、像素幅度及网格不翻折',function()
   local m=B.mesh(key)
   for _,zoom in ipairs({.003,.0074,.032,.084,.10,.149,.15,.6}) do
    local scale=64*zoom
    for frame=0,120 do local target={}
     for i,v in ipairs(m.vertices) do
      local dx,dy=B.offset(key,v,m.spec,frame/25,scale,zoom)
      if v.weight==0 or zoom>=.15 then assert(dx==0 and dy==0) end
      assert(math.sqrt(dx*dx+dy*dy)*scale<=(key=='heart' and 1.5 or key:find('lung') and 2 or 1)+1e-8)
      target[i]={x=v.x+dx,y=v.y+dy}
     end
     for _,tr in ipairs(m.triangles) do
      local a,b,c=m.vertices[tr[1]],m.vertices[tr[2]],m.vertices[tr[3]]
      local aa,bb,cc,dd,tx,ty=B.affine(a,b,c,target[tr[1]],target[tr[2]],target[tr[3]])
      assert(aa and aa*dd-bb*cc>.1)
      for _,index in ipairs(tr) do local v,p=m.vertices[index],target[index]
       assert(math.abs(aa*v.x+cc*v.y+tx-p.x)<1e-7 and math.abs(bb*v.x+dd*v.y+ty-p.y)<1e-7)
      end
     end
    end
   end
  end)
 end
 test('每种器官存在有效活动网格且整体候选三角不超预算',function()
  local total=0
  for _,key in ipairs({'heart','lung_r','lung_l','stomach','small_intestine','large_intestine'}) do
   local mesh=B.mesh(key);total=total+#mesh.triangles;local moved=false
   for frame=0,240 do
    for _,v in ipairs(mesh.vertices) do
     local x,y=B.offset(key,v,mesh.spec,frame*.05,2.56,.04)
     moved=moved or math.abs(x)+math.abs(y)>1e-7
    end
   end
   assert(moved,key..' has no active vertices')
  end
  assert(total<=B.maxTriangles)
 end)
 test('图像按世界/UI上下文缓存并成对释放',function()
  local create,delete=_G.nvgCreateImage,_G.nvgDeleteImage;local created,deleted=0,0
  _G.nvgCreateImage=function() created=created+1;return created end
  _G.nvgDeleteImage=function() deleted=deleted+1 end
  local ok,err=pcall(function()
   local a,b={},{};B.prepare(a);B.prepare(a);B.prepare(b);assert(created==2*configuredLayers)
   B.release(a);B.release(a);B.release(b);assert(deleted==2*configuredLayers)
  end)
  _G.nvgCreateImage,_G.nvgDeleteImage=create,delete;assert(ok,err)
 end)
 test('缺图缓存失败结果并保持静态回退',function()
  local create,delete=_G.nvgCreateImage,_G.nvgDeleteImage;local attempts=0
  _G.nvgCreateImage=function() attempts=attempts+1;return -1 end
  _G.nvgDeleteImage=function() error('invalid image released') end
  local ok,err=pcall(function() local vg={};assert(B.prepare(vg)==-1 and B.prepare(vg)==-1 and attempts==configuredLayers);B.release(vg) end)
  _G.nvgCreateImage,_G.nvgDeleteImage=create,delete;assert(ok,err)
 end)
 local passed=0;for _,r in ipairs(results) do if r.pass then passed=passed+1 end end
 return {passed=passed,total=#results,results=results}
end
return Q
