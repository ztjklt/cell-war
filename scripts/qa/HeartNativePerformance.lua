-- Explicit native benchmark only. It never starts a preview or creates images.
-- A uses the same atlas panels as B, through HeartArt's opt-in static quad path.
local Q={}
---@type Node|nil
local ownerNode=nil
---@type LuaScriptObject|nil
local receiver=nil
local function canonical(v)
 if type(v)~='table'then return cjson.encode(v)end
 local keys={};for k in pairs(v)do keys[#keys+1]=k end
 table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
 local out={};for _,k in ipairs(keys)do out[#out+1]=cjson.encode(tostring(k))..':'..canonical(v[k])end
 return '{'..table.concat(out,',')..'}'
end
local function percentile(values,p)
 local copy={};for i,v in ipairs(values)do copy[i]=v end
 table.sort(copy);return copy[math.max(1,math.ceil(#copy*p))]or 0
end
local function summary(values)
 local n=#values;local sorted={};local total=0
 for i,v in ipairs(values)do sorted[i]=v;total=total+v end
 table.sort(sorted)
 local middle=n>0 and (n%2==1 and sorted[(n+1)//2]or (sorted[n//2]+sorted[n//2+1])*.5)or 0
 return {count=n,medianMs=middle,p95Ms=percentile(values,.95),meanMs=n>0 and total/n or 0}
end
local function compare(a,b)
 local ac,bc,af,bf=summary(a.cpu),summary(b.cpu),summary(a.frame),summary(b.frame)
 local function ratio(x,y)return y>0 and x/y or 0 end
 local r={A={cpu=ac,frame=af},B={cpu=bc,frame=bf},
  cpuMedianRatio=ratio(bc.medianMs,ac.medianMs),cpuP95Ratio=ratio(bc.p95Ms,ac.p95Ms),
  frameP95Ratio=ratio(bf.p95Ms,af.p95Ms),thresholdRatio=1.05}
 r.baselineValid=ac.medianMs>0 and ac.p95Ms>0 and af.p95Ms>0
 r.pass=r.baselineValid and r.cpuMedianRatio<=1.05 and r.cpuP95Ratio<=1.05 and r.frameP95Ratio<=1.05
 return r
end
local function append(out,values)for _,v in ipairs(values)do out[#out+1]=v end end
function Q.start(g,R,H,options)
 assert(not receiver,'HeartNativePerformance is already running')
 local opts=options or {}
 local A,T,Art,Save,UI=require('war.FullBodyMapArt'),require('war.HeartDisplayTransform'),
  require('war.HeartArt'),require('war.Save'),require('urhox-libs/UI')
 assert(A.enabled(g.state)and T.enabled(g.state),'benchmark requires the current fullbody heart map')
 assert(not g.modal,'benchmark requires a closed modal')
 local OUT=opts.outputDir or 'qa/heart-native/performance-001'
 for _,p in ipairs({'qa','qa/heart-native',OUT})do assert(fileSystem:DirExists(p)or fileSystem:CreateDir(p),p)end
 local function write(name,value)
  local file=File(OUT..'/'..name,FILE_WRITE);assert(file and file:IsOpen(),name)
  file:WriteString(cjson.encode(value));file:Close()
 end
 local uiVG=UI.GetNVGContext();assert(uiVG~=R.vg,'two distinct NanoVG contexts required')
 local before={paused=g.paused,camera=g.camera,cameraX=g.camera.x,cameraY=g.camera.y,
  zoom=g.zoom,selection=g.selection,static=g.heartStaticDiagnostic,time=g.heartDisplayTime,
  intensity=g.heartDisplayIntensity,bodyLife=g.bodyLifeEnabled,inactiveFps=engine.maxInactiveFps}
 local frozen=canonical(Save.snapshot(g.state));local rng=g.state.rng
 local visibility=canonical(g.state.factions[1].visible)
 local oldDraw,oldCreate,oldDelete=R.draw,nvgCreateImage,nvgDeleteImage
 local index,draws,readyFrames,updateFrame,lastCaptured,updates,lastProgress=0,0,0,-1,-1,0,0
 local dtMs=0;local started,finished=false,false
 ---@type table|nil
 local block=nil
 ---@type table|nil
 local initialResources=nil
 local source=opts.sourcePoint or {518,411};local zoom=opts.zoom or .15
 local camera={x=source[1]*2,y=source[2]*2+512}
 local evidence={schema='heart-native-abba-performance/v1',nativeEvidence=true,outputDir=OUT,
  runId=tostring(os.time()),blocks={},roundComparisons={},errors={},
  sequence={'A','B','B','A','A','B','B','A'},warmupFrames=60,measureFrames=120,
  thresholdRatio=1.05,sourcePoint=source,zoom=zoom,
  physicalWidth=graphics:GetWidth(),physicalHeight=graphics:GetHeight(),dpr=graphics:GetDPR(),
  api=graphics:GetApiName(),scope='Paused fullbody map; whole-world R.draw CPU submission and raw Update timestep.',
  limits={'CPU submission does not isolate GPU time. Update timestep includes frame pacing and UI.',
   'A uses the same textures, alpha, panels and layer order as B; only the heart mesh and its moving hole become identity.',
   'Any ratio above 1.05 is a failure; timing noise is recorded without converting a failure into a pass.',
   'HeartArt.last.triangles is logical mesh coverage after exact batching; actualFills and submittedTriangles separately record native submission work.'}}
 local createsWarm,createsMeasured,deletesWarm,deletesMeasured=0,0,0,0
 local function resourceState()
  local function context(vg)
   local h=A.handles[vg]or {};local count=0
   for _,id in pairs(h)do if id>0 then count=count+1 end end
   return {images=count,handles=canonical(h)}
  end
  return {world=context(R.vg),ui=context(uiVG),stats=A.stats(),
   worldReady=A.ready(R.vg,g.state),uiReady=A.ready(uiVG,g.state)}
 end
 local function checkResources(current)
  return current.worldReady and current.uiReady and current.world.images==42 and current.ui.images==42
   and current.stats.contexts==2 and current.stats.images==84
   and (not initialResources or (current.world.handles==initialResources.world.handles
    and current.ui.handles==initialResources.ui.handles))
 end
 local function enforce()
  g.paused=true;g.camera.x,g.camera.y=camera.x,camera.y;g.zoom=zoom
  g.heartDisplayTime=nil;g.heartDisplayIntensity=1;g.bodyLifeEnabled=true
  g.heartStaticDiagnostic=not block or block.mode=='A'
 end
 local finish,advance
 finish=function(reason)
  if finished then return end;finished=true
  R.draw=oldDraw;nvgCreateImage=oldCreate;nvgDeleteImage=oldDelete
  if receiver then receiver:UnsubscribeFromAllEvents()end
  receiver=nil;ownerNode=nil
  evidence.finishedReason=reason;evidence.completed=reason=='all-blocks-measured'
  evidence.finalSnapshotUnchanged=canonical(Save.snapshot(g.state))==frozen
  evidence.finalRngUnchanged=g.state.rng==rng
  evidence.finalVisibilityUnchanged=canonical(g.state.factions[1].visible)==visibility
  evidence.finalResources=resourceState();evidence.resourcesStable=checkResources(evidence.finalResources)
  evidence.imageCreateCalls={warmup=createsWarm,measured=createsMeasured}
  evidence.imageDeleteCalls={warmup=deletesWarm,measured=deletesMeasured}
  local pool={A={cpu={},frame={}},B={cpu={},frame={}}}
  for _,row in ipairs(evidence.blocks)do append(pool[row.mode].cpu,row.cpuRawMs);append(pool[row.mode].frame,row.eventTimeStepRawMs)end
  if #pool.A.cpu>0 and #pool.B.cpu>0 then evidence.aggregate=compare(pool.A,pool.B)end
  for round=1,2 do
   local p={A={cpu={},frame={}},B={cpu={},frame={}}}
   for _,row in ipairs(evidence.blocks)do if row.round==round then
    append(p[row.mode].cpu,row.cpuRawMs);append(p[row.mode].frame,row.eventTimeStepRawMs)
   end end
   if #p.A.cpu>0 and #p.B.cpu>0 then evidence.roundComparisons[round]=compare(p.A,p.B)end
  end
  local invariant=evidence.finalSnapshotUnchanged and evidence.finalRngUnchanged
   and evidence.finalVisibilityUnchanged and evidence.resourcesStable
   and createsMeasured==0 and deletesMeasured==0
  local performance=evidence.aggregate and evidence.aggregate.pass or false
  for _,r in ipairs(evidence.roundComparisons)do performance=performance and r.pass end
  evidence.pass=evidence.completed and #evidence.blocks==8 and invariant and performance and #evidence.errors==0
  evidence.status=evidence.pass and 'PASS'or 'FAIL'
  g.paused=before.paused;g.camera=before.camera;g.camera.x,g.camera.y=before.cameraX,before.cameraY
  g.zoom=before.zoom;g.selection=before.selection
  g.heartStaticDiagnostic=before.static;g.heartDisplayTime=before.time
  g.heartDisplayIntensity=before.intensity;g.bodyLifeEnabled=before.bodyLife
  engine.maxInactiveFps=before.inactiveFps;T.beginFrame(g)
  if H and H.sidebar then
   local ok,err=pcall(H.sidebar,g)
   if not ok then evidence.errors[#evidence.errors+1]='restore sidebar: '..tostring(err);evidence.pass=false;evidence.status='FAIL'end
  end
  evidence.restored=true;write('report.json',evidence);write('current.json',{finished=true,status=evidence.status,reason=reason})
  print('[HeartPerformance] FINISHED '..evidence.status..' '..reason)
  if opts.onFinish then
   local ok,err=pcall(opts.onFinish,evidence)
   if not ok then evidence.errors[#evidence.errors+1]='onFinish: '..tostring(err);evidence.pass=false;evidence.status='FAIL';write('report.json',evidence)end
  end
 end
 advance=function()
  index=index+1
  if not evidence.sequence[index]then finish('all-blocks-measured');return end
  block={index=index,round=(index-1)//4+1,mode=evidence.sequence[index],drawFrames=0,
   cpuRawMs={},eventTimeStepRawMs={},sampleFrameNumbers={},heartbeatTimes={},
   minAreaRatio=1,maxOffsetSource=0,minHeartTriangles=math.huge,maxHeartTriangles=0,
   minActualHeartFills=math.huge,maxActualHeartFills=0,minSubmittedHeartTriangles=math.huge,maxSubmittedHeartTriangles=0}
  enforce();write('current.json',{index=index,total=8,mode=block.mode,round=block.round,warmup=60,measure=120})
 end
 _HeartNativePerformanceEvents=ScriptObject()
 ownerNode=Node();receiver=ownerNode:CreateScriptObject('_HeartNativePerformanceEvents')
 assert(receiver,'native performance event receiver unavailable')
 nvgCreateImage=function(...)
  if block and block.drawFrames>=60 then createsMeasured=createsMeasured+1 else createsWarm=createsWarm+1 end
  return oldCreate(...)
 end
 nvgDeleteImage=function(...)
  if block and block.drawFrames>=60 then deletesMeasured=deletesMeasured+1 else deletesWarm=deletesWarm+1 end
  return oldDelete(...)
 end
 R.draw=function(...)
  enforce()
  local begun=os.clock();local result=table.pack(pcall(oldDraw,...));local cpu=(os.clock()-begun)*1000
  if not result[1]then evidence.errors[#evidence.errors+1]=tostring(result[2]);finish('render-error');error(result[2],0)end
  draws=draws+1
  if started and not finished and block and updateFrame~=lastCaptured then
   lastCaptured=updateFrame;lastProgress=updates;block.drawFrames=block.drawFrames+1
   if block.drawFrames>60 then
    local f=T.frame(g);local triangles=Art.last.triangles
    block.cpuRawMs[#block.cpuRawMs+1]=cpu
    block.eventTimeStepRawMs[#block.eventTimeStepRawMs+1]=dtMs
    block.sampleFrameNumbers[#block.sampleFrameNumbers+1]=updateFrame
    block.heartbeatTimes[#block.heartbeatTimes+1]=f.time
    block.minAreaRatio=math.min(block.minAreaRatio,f.minAreaRatio)
    block.maxOffsetSource=math.max(block.maxOffsetSource,f.maxOffsetSource)
    block.minHeartTriangles=math.min(block.minHeartTriangles,triangles)
    block.maxHeartTriangles=math.max(block.maxHeartTriangles,triangles)
    local fills=Art.last.actualFills or 0;local submitted=Art.last.visibleTriangles or triangles
    block.minActualHeartFills=math.min(block.minActualHeartFills,fills);block.maxActualHeartFills=math.max(block.maxActualHeartFills,fills)
    block.minSubmittedHeartTriangles=math.min(block.minSubmittedHeartTriangles,submitted);block.maxSubmittedHeartTriangles=math.max(block.maxSubmittedHeartTriangles,submitted)
    if #block.cpuRawMs==120 then
     block.cpu=summary(block.cpuRawMs);block.frame=summary(block.eventTimeStepRawMs)
     block.resources=resourceState();block.resourcesStable=checkResources(block.resources)
     block.snapshotUnchanged=canonical(Save.snapshot(g.state))==frozen
     block.rngUnchanged=g.state.rng==rng
     block.visibilityUnchanged=canonical(g.state.factions[1].visible)==visibility
     local geometry=block.minAreaRatio>=.7
     if block.mode=='A'then geometry=geometry and block.maxHeartTriangles==0 and block.maxOffsetSource==0
     else geometry=geometry and block.minHeartTriangles==384 and block.maxHeartTriangles==384
      and block.maxOffsetSource>=.6 and block.heartbeatTimes[120]>block.heartbeatTimes[1]end
     block.valid=block.resourcesStable and block.snapshotUnchanged and block.rngUnchanged
      and block.visibilityUnchanged and geometry and dtMs>0
     evidence.blocks[#evidence.blocks+1]=block
     if not block.valid then evidence.errors[#evidence.errors+1]='Block '..index..' failed resource/state/real-time/quad-mesh checks'end
     write('report.json',evidence)
     print('[HeartPerformance] BLOCK '..index..' '..block.mode..' cpuP95='..block.cpu.p95Ms..' frameP95='..block.frame.p95Ms)
     advance()
    end
   end
  end
  return table.unpack(result,2,result.n)
 end
 engine.maxInactiveFps=60;g.selection={};enforce()
 if opts.raise~=false then graphics:Raise()end
 receiver:SubscribeToEvent('Update',function(_,_,event)
  local ok,err=pcall(function()
   updates=updates+1
   updateFrame=GetTime():GetFrameNumber();dtMs=event:GetFloat('TimeStep')*1000;enforce()
   if started and updates-lastProgress>600 then finish('render-progress-timeout');return end
   if not started then
    readyFrames=readyFrames+1
    if readyFrames>=120 and A.ready(R.vg,g.state)and A.ready(uiVG,g.state)then
     initialResources=resourceState();evidence.initialResources=initialResources
     if not checkResources(initialResources)then finish('resource-count-mismatch');return end
     started=true;advance()
    elseif readyFrames>1800 then finish('resources-timeout')end
   end
  end)
  if not ok then evidence.errors[#evidence.errors+1]=tostring(err);finish('driver-error')end
 end)
 Q.stop=function()finish('cancelled')end
 write('report.json',evidence);print('[HeartPerformance] START ABBA ABBA warm60 measure120')
 return evidence
end
return Q
