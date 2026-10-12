-- Pure Lua mathematics; native screenshots and frame time are separate checks.
local A={}
local function near(a,b,tolerance)return math.abs(a-b)<(tolerance or 1e-8)end
function A.run(contract)
 local M=require('war.HeartMotion');local T=require('war.HeartDisplayTransform')
 local original=T.contract;T.configure(contract or original)
 local accepted=T.contract;local rows={}
 local metrics={maxRoundTrip=0,minAreaRatio=1,maxOffsetSource=0,maxAnchorError=0}
 local function test(name,fn)
  local ok,err=pcall(fn);rows[#rows+1]={name=name,pass=ok,error=ok and ''or tostring(err)}
 end
 test('fullbody and an active heart trial opt in without affecting other trials',function()
  assert(T.enabled({anatomyVersion=4,fullbodyBattlefieldVersion=1}))
  assert(T.enabled({anatomyVersion=4,organBattlefieldVersion=1,organBattlefieldIds={'heart'}}))
  assert(not T.enabled({anatomyVersion=4,organBattlefieldVersion=1,organBattlefieldIds={'liver'}}))
  assert(not T.enabled({anatomyVersion=4,fullbodyBattlefieldVersion=1,heartDisplayEnabled=false}))
  local m=T.mesh;assert(T.configure(accepted)==m,'same-contract setup rebuilt the mesh')
 end)
 test('atria contract before ventricles, with periodic smooth recovery',function()
  assert(near(M.sample(.10).atrial,-1)and near(M.sample(.10).ventricular,0))
  assert(near(M.sample(.30).ventricular,-1))
  for _,fps in ipairs({30,60,120})do for frame=0,fps*3 do
   local a,b=M.sample(frame/fps),M.sample(frame/fps+M.period)
   assert(near(a.atrial,b.atrial)and near(a.ventricular,b.ventricular))
  end end
  local before,after=M.sample(1-1e-7),M.sample(1+1e-7)
  assert(near(before.atrial,after.atrial)and near(before.ventricular,after.ventricular))
 end)
 test('every phase preserves orientation and exact forward/inverse registration',function()
  local b=T.mesh.sourceBox
  for step=0,240 do
   local f=T.makeFrame(step/120)
   assert(f.safe and f.minAreaRatio>=.7,'unsafe cardiac area ratio');metrics.minAreaRatio=math.min(metrics.minAreaRatio,f.minAreaRatio)
   metrics.maxOffsetSource=math.max(metrics.maxOffsetSource,f.maxOffsetSource)
   for iy=0,17 do for ix=0,13 do
    local x,y=b[1]+(b[3]-b[1])*ix/13,b[2]+(b[4]-b[2])*iy/17
    local xx,yy=T.forward(f,x,y);local rx,ry=T.inverse(f,xx,yy)
    local error=math.sqrt((rx-x)^2+(ry-y)^2)
    local offset=math.sqrt((xx-x)^2+(yy-y)^2)
    metrics.maxRoundTrip=math.max(metrics.maxRoundTrip,error)
    metrics.maxOffsetSource=math.max(metrics.maxOffsetSource,offset)
    assert(error<1e-7,'inverse differs from the displayed triangle')
    assert(offset<=M.maxOffsetSource+1e-8,'motion exceeds collar guard')
   end end
  end
  assert(metrics.maxOffsetSource>=.6,'cardiac motion is too small for .15 inspection')
  metrics.maxOffsetLogicalPixelsAt015=metrics.maxOffsetSource*64*.15
 end)
 test('remote vessel sections remain fixed across their complete width',function()
  ---@type table[]
  local connectors=accepted.connectors
  if not connectors or #connectors==0 then
   local c={sourceBox=accepted.sourceBox,chambers=accepted.chambers,
    grid=accepted.grid,edgeFadeSource=accepted.edgeFadeSource,connectors={
    {id='cava',anchorSource={486,358},inwardSource={0,1},halfWidthSource=4,blendLengthSource=16},
    {id='aorta',anchorSource={529,345},inwardSource={0,1},halfWidthSource=4,blendLengthSource=16},
    {id='pulmonary_artery',anchorSource={476,401},inwardSource={1,0},halfWidthSource=4,blendLengthSource=16},
    {id='pulmonary_vein',anchorSource={555,401},inwardSource={-1,0},halfWidthSource=4,blendLengthSource=16},
   }}
   T.configure(c);connectors=c.connectors
  end
  assert(#connectors>=4,'four physiological vessel families require contracts')
  metrics.fixedProximalSections=#connectors
  metrics.fixedCrossBoxSections=0
  for _,c in ipairs(T.mesh.sections)do if c.kind=='crossBox'then metrics.fixedCrossBoxSections=metrics.fixedCrossBoxSections+1 end end
  metrics.fixedSections=#T.mesh.sections
  local same=true;for i=1,4 do if accepted.sourceBox[i]~=M.crossBoxSourceBox[i]then same=false end end
  if same then assert(metrics.fixedCrossBoxSections==13,'registered global routes missing fixed sections')end
  for step=0,120 do
   local f=T.makeFrame(step/120);assert(f.safe)
   for _,c in ipairs(T.mesh.sections)do
    local p,q=c.points[1],c.points[2]
    for i=0,32 do
     local x,y=p[1]+(q[1]-p[1])*i/32,p[2]+(q[2]-p[2])*i/32
     local xx,yy=T.forward(f,x,y);local error=math.sqrt((xx-x)^2+(yy-y)^2)
     metrics.maxAnchorError=math.max(metrics.maxAnchorError,error)
     assert(error<1e-8,'vessel section separated from external texture')
    end
   end
  end
  T.configure(accepted)
 end)
 test('all neighboring triangle edges use one continuous display map',function()
  local mesh=T.mesh;local edges={};local shared={}
  for _,tr in ipairs(mesh.triangles)do for j=1,3 do
   local a,b=tr[j],tr[j%3+1];if a>b then a,b=b,a end
   local key=a..':'..b
   if edges[key]then shared[#shared+1]={a,b}else edges[key]=true end
  end end
  metrics.sharedMeshEdges=#shared;metrics.maxSeamError=0
  for step=0,60 do
   local f=T.makeFrame(step/60)
   for _,edge in ipairs(shared)do
    local p,q=mesh.vertices[edge[1]],mesh.vertices[edge[2]]
    local a,b=f.vertices[edge[1]],f.vertices[edge[2]]
    for i=0,4 do
     local t=i/4;local x,y=T.forward(f,p.x+(q.x-p.x)*t,p.y+(q.y-p.y)*t)
     local error=math.sqrt((x-(a.x+(b.x-a.x)*t))^2+(y-(a.y+(b.y-a.y)*t))^2)
     metrics.maxSeamError=math.max(metrics.maxSeamError,error)
     assert(error<1e-8,'two adjacent triangle displays disagree')
    end
   end
  end
 end)
 test('actual chamber walls visibly contract at .15 before elastic recovery',function()
  metrics.chamberWallMotion={}
  for _,c in ipairs(accepted.chambers or {})do
   local phase=c.kind=='atrium'and .10 or .30
   local f=T.makeFrame(phase);local maximum,total,count=0,0,0
   for _,ring in ipairs(c.rings or {})do for _,p in ipairs(ring.outer or {})do
    local x,y=T.forward(f,p[1],p[2]);local d=math.sqrt((x-p[1])^2+(y-p[2])^2)
    maximum=math.max(maximum,d);total=total+d;count=count+1
   end end
   if count>0 then
    assert(maximum>=.6 and maximum<=M.maxOffsetSource+1e-8,'chamber wall amplitude outside visible range')
    metrics.chamberWallMotion[#metrics.chamberWallMotion+1]={id=c.id,phase=phase,
     maxSource=maximum,meanSource=total/count,maxLogicalPixelsAt015=maximum*64*.15}
   end
  end
 end)
 test('mesh perimeter and surrounding anatomy remain fixed',function()
  local b=T.mesh.sourceBox
  for step=0,60 do
   local f=T.makeFrame(step/60)
   for i=0,20 do
    local x,y=b[1]+(b[3]-b[1])*i/20,b[2]+(b[4]-b[2])*i/20
    for _,p in ipairs({{x,b[2]},{x,b[4]},{b[1],y},{b[3],y},{b[1]-20,y},{x,b[4]+20}})do
     local xx,yy=T.forward(f,p[1],p[2]);assert(near(xx,p[1])and near(yy,p[2]))
    end
   end
  end
 end)
 test('overview and .15 retain the same heartbeat and input uses the displayed frame',function()
  local b=T.mesh.sourceBox;local x,y=(b[1]+b[3])*.5+9,(b[2]+b[4])*.5+17
  local g={state={anatomyVersion=4,fullbodyBattlefieldVersion=1},realTime=.30,zoom=.02}
  T.beginFrame(g);local ax,ay=T.forwardSource(g,x,y)
  g.zoom=.15;T.beginFrame(g);local bx,by=T.forwardSource(g,x,y)
  assert(near(ax,bx)and near(ay,by),'zoom erased or changed heartbeat')
  local old=T.frame(g);g.realTime=.59
  assert(T.frame(g)==old,'input sampled an undisplayed heartbeat')
  local rx,ry=T.inverseSource(g,ax,ay);assert(near(rx,x)and near(ry,y))
  T.beginFrame(g);assert(T.frame(g)~=old)
  local wx,wy=T.forwardWorld(g,x*2,y*2+512)
  local lx,ly=T.inverseWorld(g,wx,wy);assert(near(lx,x*2)and near(ly,y*2+512))
  g.heartDisplayTime=.10;g.heartDisplayIntensity=.5
  local half=T.beginFrame(g);local whole=T.makeFrame(.10)
  assert(near(half.time,.10)and near(half.maxOffsetSource,whole.maxOffsetSource*.5))
  g.bodyLifeEnabled=false;assert(T.beginFrame(g).maxOffsetSource==0)
  g.bodyLifeEnabled=true;g.heartStaticDiagnostic=true
  local identity=T.beginFrame(g);g.realTime=g.realTime+1
  assert(identity.time==0 and identity.maxOffsetSource==0 and T.beginFrame(g)==identity)
  local px,py=T.forwardSource(g,x,y);assert(near(px,x)and near(py,y))
 end)
 test('disabled motion is identity and visual math never reads simulation RNG',function()
  local random=math.random;math.random=function()error('cardiac display read RNG')end
  local ok,why=pcall(function()
   for step=0,120 do assert(T.makeFrame(step/120).safe)end
   local f=T.makeFrame(.30,0)
   for _,p in ipairs(T.mesh.vertices)do
    local x,y=T.forward(f,p.x,p.y);assert(near(x,p.x)and near(y,p.y))
   end
  end)
  math.random=random;assert(ok,why)
 end)
 T.configure(original)
 local passed=0;for _,r in ipairs(rows)do if r.pass then passed=passed+1 end end
 return {schema='heart-display-math/v1',nativeEvidence=false,passed=passed,total=#rows,
  metrics=metrics,rows=rows,limits={'Native seams, point selection and frame time require window acceptance.'}}
end
return A
