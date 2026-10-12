-- Visual-only organ boundary contracts, independent of native raster quality.
local Q={}
function Q.run()
 local O=require('war.OrganBoundaries');local M=require('war.ReferenceMap');local results={}
 local function test(name,fn) local ok,err=pcall(fn);results[#results+1]={name=name,pass=ok,error=ok and '' or tostring(err)} end
 test('十二器官完整边界、连接口与大肠中央内孔明确',function()
  assert(#O.ids()==12)
  for _,id in ipairs(O.ids()) do
   local r=O.get(id);assert(#r.outlinePaths>0 and #r.interiorPaths>0 and #r.rimPaths>0 and #r.connections>0)
   for _,p in ipairs(r.outlinePaths) do assert(#p.points>=12) end
   for _,port in ipairs(r.connections) do
    assert(not O.contains(id,port[1]*2,port[2]*2+512))
    for _,path in ipairs(r.rimPaths) do for _,p in ipairs(path.points) do
     assert((p[1]-port[1])^2+(p[2]-port[2])^2>=(port[3]-.8)^2,'membrane closes a connection')
    end end
   end
  end
  assert(#O.get('large_intestine').cavityPaths==1)
  assert(not O.contains('large_intestine',507*2,687*2+512))
  assert(O.contains('small_intestine',507*2,687*2+512,2))
 end)
 test('安全内侧拒绝支气管、脑干和未知器官',function()
  for _,p in ipairs({{'lung_r',438,370},{'lung_l',581,370},{'brain',509,109},{'kidney_r',431,611},{'kidney_l',587,611}}) do
   assert(O.clearance(p[1],p[2]*2,p[3]*2+512)==0,p[1])
  end
  assert(not O.contains('missing',0,0) and #O.paths('missing')==0)
  for _,id in ipairs(O.ids()) do
   local r=O.get(id);local b=r.bounds;local accepted=0
   for sy=b[2]+3,b[4]-3,7 do for sx=b[1]+3,b[3]-3,7 do
    local wx,wy=sx*2,sy*2+512
    if O.contains(id,wx,wy,3) then
     accepted=accepted+1
     for i=0,11 do local angle=i*math.pi/6
      assert(O.contains(id,wx+3*math.cos(angle),wy+3*math.sin(angle)),id..' patch crossed membrane')
     end
    end
   end end
   assert(accepted>0,id..' has no usable interior')
  end
 end)
 test('心肌内黄色冠脉与高亮主连接拒绝纹理覆盖',function()
  -- Exact source-pixel samples: RGB (251,204,132), (254,213,136), (254,190,116).
  for _,p in ipairs({{512,401},{527,418},{530,427}}) do
   assert(O.clearance('heart',p[1]*2,p[2]*2+512)==0,'coronary foreground was not protected')
   assert(not O.contains('heart',p[1]*2,p[2]*2+512,1))
  end
  assert(O.contains('heart',490*2,412*2+512,1),'normal myocardium was removed')
 end)
 test('肝内绿色胆囊及胆管保留固定前景',function()
  -- Actual source greens: gallbladder body and the adjacent bile-duct branch.
  for _,p in ipairs({{444,545},{438,545},{452,546},{464,545}}) do
   assert(O.clearance('liver',p[1]*2,p[2]*2+512)==0,'gallbladder covered by liver tissue')
   assert(not O.contains('liver',p[1]*2,p[2]*2+512,1))
  end
  assert(O.contains('liver',450*2,508*2+512,2),'normal liver tissue was removed')
 end)
 test('心肾组织边界消除像素台阶且保留可用面积',function()
  for _,id in ipairs({'heart','kidney_r'}) do
   local total=0
   for _,path in ipairs(O.paths(id)) do
    local points=path.points;local area=0
    for i,p in ipairs(points) do local q=points[i%#points+1];area=area+p[1]*q[2]-q[1]*p[2] end
    area=math.abs(area)*.5;total=total+area*(path.hole and -1 or 1)
    -- Tiny islands are irrelevant to the main membrane; substantial boundaries
    -- must turn continuously instead of reproducing rounded pixel stair steps.
    if area>100 then for i,p in ipairs(points) do
     local q,r=points[i%#points+1],points[(i+1)%#points+1]
     local ax,ay,bx,by=q[1]-p[1],q[2]-p[2],r[1]-q[1],r[2]-q[2]
     local cosine=(ax*bx+ay*by)/math.sqrt((ax*ax+ay*ay)*(bx*bx+by*by))
     assert(cosine>math.cos(id=='kidney_r' and .12 or .30),'pixel staircase returned: '..id)
    end end
   end
   -- At least 97% of the original safe area, including protected interior gaps.
   assert(total>(id=='heart' and 2091.95 or 1538.10)*.97,'excessive erosion: '..id)
  end
 end)
 test('膜绘制固定、缩放渐入、裁剪、旧版与状态恢复',function()
  local names={'nvgSave','nvgRestore','nvgLineJoin','nvgLineCap','nvgBeginPath','nvgMoveTo','nvgQuadTo','nvgLineTo','nvgStrokeWidth','nvgStrokeColor','nvgRGBA','nvgStroke'}
  local old={};for _,name in ipairs(names) do old[name]=_G[name];_G[name]=function() end end
  local strokes,depth,maxAlpha=0,0,0;local positions={}
  _G.nvgSave=function() depth=depth+1 end;_G.nvgRestore=function() depth=depth-1 end
  _G.nvgStroke=function() strokes=strokes+1 end
  _G.nvgRGBA=function(r,g,b,a) maxAlpha=math.max(maxAlpha,a);return {} end
  _G.nvgMoveTo=function(vg,x,y) positions[#positions+1]=x;positions[#positions+1]=y end
  local ok,err=pcall(function()
   local R={vg={},project=function(g,x,y) return x*g.zoom*32,y*g.zoom*32 end};local g={zoom=.06,realTime=0}
   O.draw(R,g,{anatomyVersion=4},0,2048,512,3584);assert(strokes==0)
   g.zoom=.061;O.draw(R,g,{anatomyVersion=4},0,2048,512,3584);assert(maxAlpha<=1 and depth==0)
   strokes=0;positions={};g.zoom=.2
   local r=O.draw(R,g,{anatomyVersion=4},0,2048,512,3584);assert(r.organs==12 and strokes==24 and depth==0)
   local fixed=table.concat(positions,',');positions={};g.realTime=900
   O.draw(R,g,{anatomyVersion=4},0,2048,512,3584);assert(fixed==table.concat(positions,','))
   strokes=0;O.draw(R,g,{anatomyVersion=3},0,2048,512,3584);assert(strokes==0)
   O.draw(R,g,{anatomyVersion=4},0,10,0,10);assert(strokes==0 and depth==0)
  end)
  for _,name in ipairs(names) do _G[name]=old[name] end
  assert(ok,err)
 end)
 test('边界查询不改定位多边形或消耗随机数',function()
  local before={};for _,o in ipairs(M.organs) do for _,p in ipairs(o.points) do before[#before+1]=p[1];before[#before+1]=p[2] end end
  local random=math.random;math.random=function() error('visual RNG use') end
  local ok,err=pcall(function()
   for _,id in ipairs(O.ids()) do O.get(id);O.paths(id);O.paths(id,true);O.contains(id,1024,1600,2) end
  end)
  math.random=random;assert(ok,err)
  local after={};for _,o in ipairs(M.organs) do for _,p in ipairs(o.points) do after[#after+1]=p[1];after[#after+1]=p[2] end end
  assert(table.concat(before,',')==table.concat(after,','))
 end)
 local passed=0;for _,r in ipairs(results) do if r.pass then passed=passed+1 end end
 return {passed=passed,total=#results,results=results}
end
return Q
