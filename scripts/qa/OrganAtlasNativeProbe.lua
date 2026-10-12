-- Opt-in observation of the actual visible battlefield. No synthetic draw or movement.
-- CPU os.clock(), engine Update interval and GPU work are different measurements.
local P={}
---@type table<string,any>|nil
local active=nil
---@type table<string,any>|nil
local lastReport=nil
local serial=0
local ORGANS={'brain','lung_r','lung_l','liver','stomach','pancreas','kidney_r','kidney_l','large_intestine','small_intestine','bladder','heart'}
local function finite(v) return type(v)=='number' and v==v and v~=math.huge and v~=-math.huge end
local function safeCall(fn,...)
 local result=table.pack(pcall(fn,...))
 if not result[1] then return nil,tostring(result[2]) end
 return table.unpack(result,2,result.n)
end
local function stamp()
 local t=GetTime and GetTime()
 if not t then return {} end
 local wall,err=safeCall(function() return t:GetSystemTime() end)
 local frame=safeCall(function() return t:GetFrameNumber() end)
 return {wallMs=finite(wall) and wall or nil,frame=frame,error=err}
end
local function size()
 local w,h,d=safeCall(function() return graphics:GetWidth(),graphics:GetHeight(),graphics:GetDPR() end)
 return {physicalWidth=w,physicalHeight=h,dpr=d,logicalWidth=finite(w) and finite(d) and d>0 and w/d or nil,
  logicalHeight=finite(h) and finite(d) and d>0 and h/d or nil}
end
local function visible(s)
 local g=s.game
 if not g.started then return false,'not-started' end
 if not g.state or g.state.organBattlefieldVersion~=1 then return false,'not-organ-trial' end
 if g.modal then return false,'modal-overlay' end
 local refs=s.hud and s.hud.refs
 if refs and refs.menu and refs.menu:IsVisible() then return false,'opaque-menu' end
 if refs and refs.play and not refs.play:IsVisible() then return false,'play-ui-hidden' end
 if input and input.IsMinimized and input:IsMinimized() then return false,'window-minimized' end
 return true
end
local function inc(t,k) t[k]=(t[k] or 0)+1 end
local function percentiles(samples)
 if #samples==0 then return {status='UNDETERMINED',count=0} end
 local a={};local total=0
 for i,v in ipairs(samples) do a[i]=v;total=total+v end
 table.sort(a)
 return {status='MEASURED',count=#a,min=a[1],max=a[#a],mean=total/#a,
  p50=a[math.max(1,math.ceil(#a*.5))],p95=a[math.max(1,math.ceil(#a*.95))],p99=a[math.max(1,math.ceil(#a*.99))]}
end
local function frameView(s)
 local g=s.game;local now=stamp()
 return {frame=now.frame,wallMs=now.wallMs,zoom=g.zoom,camera={x=g.camera.x,y=g.camera.y},
  realTime=g.realTime,simulationTime=g.state.time,paused=g.paused,speed=g.speed,
  anatomyVersion=g.state.anatomyVersion,organBattlefieldVersion=g.state.organBattlefieldVersion,
  organIds=g.state.organBattlefieldIds,size=size(),
  inputHasFocus=input and input.HasFocus and input:HasFocus(),
  inputMinimized=input and input.IsMinimized and input:IsMinimized()}
end
local function uiContext(s)
 local ok,UI=pcall(require,'urhox-libs/UI')
 if not ok then return nil,tostring(UI) end
 return safeCall(function()return UI.GetNVGContext()end)
end
local function imageDimensions(row,vg,image,expected)
 row.expectedWidth=expected and expected[1];row.expectedHeight=expected and expected[2]
 if type(nvgImageSize)~='function' then row.status='UNDETERMINED';row.reason='nvgImageSize binding unavailable';return end
 local w,h=safeCall(nvgImageSize,vg,image);row.width=w;row.height=h
 if w==nil and type(h)=='string' then row.status='UNDETERMINED';row.error=h;return end
 if not finite(w) or not finite(h) or w<=0 or h<=0 then
  row.status='FAIL';row.reason='Native image dimensions are not positive';return
 end
 row.actualDimensionsMeasured=true
 if not finite(row.expectedWidth) or not finite(row.expectedHeight) or row.expectedWidth<=0 or row.expectedHeight<=0 then
  row.status='UNDETERMINED';row.reason='Expected pixelSize metadata unavailable';return
 end
 row.matchesExpectedDimensions=w==row.expectedWidth and h==row.expectedHeight
 row.status=row.matchesExpectedDimensions and 'MEASURED' or 'LOADING_PLACEHOLDER'
 if not row.matchesExpectedDimensions then row.reason='Native dimensions have not reached the authored pixelSize; a positive handle alone does not prove the asset is loaded.' end
end
local function snapshotResources(s,label,options)
 options=options or {}
 local ui,uiError=uiContext(s)
 local entries={};local world=s.render.vg
 local contexts={{label='world',vg=world},{label='ui',vg=ui}}
 local total,failures,unknown,loading=0,0,0,0
 for _,c in ipairs(contexts) do
  if not c.vg then
   unknown=unknown+1;entries[#entries+1]={context=c.label,status='UNDETERMINED',reason='context unavailable'}
  else
   local atlas=s.atlas.handles[c.vg]
   local expectTrial=not options.expectReleased and not options.observeOnly
   local manifest=(atlas or expectTrial and s.game.state.organBattlefieldVersion==1) and require('war.OrganAtlasArtData') or nil
   for _,id in ipairs(manifest and manifest.order or {}) do
    local image=atlas and atlas[id];local d=manifest.organs[id]
    local pixels=rawget(d,'pixelSize') --[[@as number[]?]]
    local row={context=c.label,contextIdentity=tostring(c.vg),organId=id,handle=image,resource=d.resource,sourceBox=d.sourceBox,
     expectedWidth=pixels and pixels[1],expectedHeight=pixels and pixels[2]}
    if type(image)~='number' or image<=0 then
     row.status='FAIL';row.reason='native image handle is not positive';failures=failures+1
    else
     imageDimensions(row,c.vg,image,pixels)
     if row.status=='FAIL' then failures=failures+1
     elseif row.status=='UNDETERMINED' then unknown=unknown+1
     elseif row.status=='LOADING_PLACEHOLDER' then loading=loading+1 end
    end
    if type(image)=='number' and image>0 then total=total+1 end
    entries[#entries+1]=row
   end
   local image=s.gastric.handles[c.vg]
   if image~=nil or expectTrial and (s.game.state.gastricBattlefieldVersion==1 or s.game.state.organBattlefieldVersion==1) then
    local row={context=c.label,contextIdentity=tostring(c.vg),organId='stomach',handle=image,
     resource='image/anatomy-reference/vascular-study/stomach-playable/battlefield.png',sourceBox=s.gastric.sourceBox,
     expectedWidth=s.gastric.pixelSize and s.gastric.pixelSize[1],expectedHeight=s.gastric.pixelSize and s.gastric.pixelSize[2]}
    if type(image)~='number' or image<=0 then row.status='FAIL';failures=failures+1
    else
     imageDimensions(row,c.vg,image,s.gastric.pixelSize)
     if row.status=='FAIL' then failures=failures+1
     elseif row.status=='UNDETERMINED' then unknown=unknown+1
     elseif row.status=='LOADING_PLACEHOLDER' then loading=loading+1 end
    end
    if type(image)=='number' and image>0 then total=total+1 end
    entries[#entries+1]=row
   end
  end
 end
 if options.expectReleased and total>0 then failures=failures+1 end
 s.maxObservedImages=math.max(s.maxObservedImages,total)
 local r={label=label,stamp=stamp(),view=frameView(s),entries=entries,positiveImages=total,
  failures=failures,unknown=unknown,loadingImages=loading,uiContextError=uiError,
  allExpectedDimensionsReached=failures==0 and unknown==0 and loading==0,
  expectation=options.expectReleased and 'intentionally-released-zero' or options.observeOnly and 'lifecycle-observation' or 'current-mode-complete',
  status=failures>0 and 'FAIL' or unknown>0 and 'UNDETERMINED' or loading>0 and 'LOADING_PLACEHOLDER' or 'MEASURED'}
 if #s.resourceSnapshots<s.maxRecords then s.resourceSnapshots[#s.resourceSnapshots+1]=r else inc(s.droppedRecords,'resourceSnapshots') end
 return r
end
function P.inspectResources(label,options)
 if not active then return nil,'probe not enabled' end
 return snapshotResources(active,label or 'manual',options)
end
local function summaryPhase(p)
 return {label=p.label,organId=p.organId,requestedZoom=p.zoom,artEnabled=p.artEnabled,start=p.start,finish=p.finish,
  wallTimeMs=p.start.wallMs and p.finish and p.finish.wallMs and p.finish.wallMs-p.start.wallMs or nil,
  warmupFrames=p.warmupFrames,requestedSampleFrames=p.sampleFrames,validFrames=#p.cpu,
  discarded=p.discarded,rawUpdateTimestepMs=p.dt,worldRenderCpuSubmissionMs=p.cpu,
  updateIntervalStatsMs=percentiles(p.dt),worldRenderCpuStatsMs=percentiles(p.cpu),
  frames=p.frames,captures=p.captures,completion=p.completion or 'INCOMPLETE'}
end
function P.report()
 local s=active
 if not s then return lastReport end
 local phases={};for _,p in ipairs(s.phases) do phases[#phases+1]=summaryPhase(p) end
 return {schema='organ-atlas-native-probe/v1',status='UNDETERMINED',runId=s.runId,
  started=s.started,finished=s.finished,reason=s.reason,outputDir=s.outputDir,
  observation='Actual R.draw, existing world/UI NanoVG handles, raw Update event and displayed framebuffer.',
  nativeVisualAcceptance='UNDETERMINED',nativeGpuExecutionTiming='UNDETERMINED',nativeGpuMemory='UNDETERMINED',
  worldRenderCpuClock='os.clock process CPU; Lua/tessellation/native API submission; excludes later GPU execution and UI widget rendering.',
  updateClock='Unclamped Update event TimeStep; engine pacing, FPS caps, smoothing, scheduling and probe overhead remain included. Not a GPU query.',
  wallClock='Time:GetSystemTime milliseconds; separate from process CPU.',
  captureEvent=s.captureEvent,engineSettings=s.engineSettings,phases=phases,
  resources=s.resourceSnapshots,lifecycle=s.lifecycle,maxObservedImages=s.maxObservedImages,
  droppedRecords=s.droppedRecords,io=s.io,errors=s.errors,mutatesSimulation=false,
  presentationChangesOnly=true,createsNanoVGContext=false,startsRuntime=false,
  screenshotWorkExcludedFromCpuSamples=true,screenshotAndFollowingUpdatesExcluded=2,
  runtimeBindings={nvgImageSize=type(nvgImageSize),image=type(Image),takeScreenShot='Graphics:TakeScreenShot',savePNG='Image:SavePNG'},
  limitations={'No GPU execution query or allocator measurement is exposed by the inspected public bindings.',
   'CPU submission and Update P95 are observed values, not proof of the requested native performance delta.',
   'The actual exported PNG must be opened and inspected before accepting visual quality or framebuffer capture timing.',
   'The probe never resizes a window, sets graphics mode, commands a cell, changes state flags, pauses simulation or rewrites Save.'}}
end
local function makeDirs(path)
 if not fileSystem then return false,'FileSystem unavailable' end
 local prefix=path:sub(1,1)=='/' and '/' or ''
 for part in path:gmatch('[^/]+') do
  prefix=prefix..part..'/'
  local ok,err=safeCall(function()return fileSystem:DirExists(prefix) or fileSystem:CreateDir(prefix)end)
  if not ok then return false,err or ('CreateDir failed: '..prefix) end
 end
 return true
end
local function writeReport(s)
 local report=P.report();local path=s.outputDir..'/report.json'
 local ok,err=pcall(function()
  local text=cjson.encode(report);local file=File(path,FILE_WRITE)
  if not file:IsOpen() then error('File not open: '..path) end
  local written=file:WriteString(text);file:Close()
  if written==false then error('WriteString failed: '..path) end
 end)
 s.io.report={path=path,saved=ok,error=not ok and tostring(err) or nil}
 print('[OrganAtlasNativeProbe] report '..path..' saved='..tostring(ok)..(not ok and (' error='..tostring(err)) or ''))
 return ok
end
function P.beginPhase(label,options)
 local s=active;if not s then return false,'probe not enabled' end
 options=options or {}
 local now=stamp();local prior=s.phase
 if prior and not prior.finish then prior.finish=now;prior.completion='INTERRUPTED' end
 local p={label=label or ('phase-'..(#s.phases+1)),organId=options.organId,zoom=options.zoom,artEnabled=options.artEnabled,
  start=now,warmupFrames=options.warmupFrames or s.warmupFrames,sampleFrames=options.sampleFrames or s.sampleFrames,
  visibleFrames=0,cpu={},dt={},frames={},discarded={},captures={}}
 s.phases[#s.phases+1]=p;s.phase=p;s.lastDrawFrame=nil
 snapshotResources(s,'phase-start-'..p.label)
 return true
end
local function setView(s,step)
 local found=false;for _,id in ipairs(s.game.state.organBattlefieldIds or {}) do if id==step.organId then found=true end end
 if step.organId and not found then return false,'organ is not active: '..step.organId end
 local box=step.organId=='stomach' and s.gastric.sourceBox or step.organId and require('war.OrganAtlasArtData').organs[step.organId].sourceBox
 local x,y=step.x,step.y
 if box then x,y=box[1]+box[3],box[2]+box[4]+512 end
 if not finite(x) or not finite(y) or not finite(step.zoom) or step.zoom<=0 then return false,'invalid presentation coordinates' end
 s.game.camera.x=x;s.game.camera.y=y;s.game.zoom=step.zoom
 return true
end
local function nextStep(s)
 s.sequenceIndex=s.sequenceIndex+1;local step=s.sequence and s.sequence[s.sequenceIndex]
 if not step then P.finish('sequence-complete');return end
 local ok,err=setView(s,step)
 if not ok then s.errors[#s.errors+1]=err;P.finish('invalid-sequence');return end
 P.beginPhase(step.label,{organId=step.organId,zoom=step.zoom,warmupFrames=step.warmupFrames,sampleFrames=step.sampleFrames})
 s.nextStepPending=false
 print('[OrganAtlasNativeProbe] visible phase '..step.label..' zoom='..step.zoom)
end
function P.startSequence(options)
 local s=active;if not s then return false,'probe not enabled' end
 local ok,why=visible(s);if not ok then return false,'visible battlefield required: '..why end
 options=options or {};local steps={}
 for _,id in ipairs(options.organIds or ORGANS) do
  local d=id=='stomach' or require('war.OrganAtlasArtData').organs[id]
  if not d then return false,'unknown organ: '..tostring(id) end
  for _,z in ipairs(options.zooms or {.15,.085,.12,.149,.151}) do
   steps[#steps+1]={label=id..'-z'..tostring(z),organId=id,zoom=z,
    warmupFrames=options.warmupFrames,sampleFrames=options.sampleFrames}
  end
 end
 if options.wholeBody~=false then steps[#steps+1]={label='whole-body-z.006',zoom=.006,x=1024,y=2048,
  warmupFrames=options.warmupFrames,sampleFrames=options.sampleFrames} end
 s.sequence=steps;s.sequenceIndex=0;s.captureEnabled=options.capture~=false;nextStep(s)
 return true
end
function P.capture(label)
 local s=active;if not s then return false,'probe not enabled' end
 local ok,why=visible(s);if not ok then return false,why end
 s.capturePending=label or (s.phase and s.phase.label or 'manual');return true
end
function P.observeUpdate(rawDt)
 local s=active;if not s then return end
 s.updateSerial=s.updateSerial+1;s.rawDt=rawDt
 if s.nextStepPending then
  local ok=visible(s);if ok then nextStep(s) end
 end
end
function P.afterFrame()
 local s=active;if not s then return end
 local p=s.phase;local label=s.capturePending
 if not label and p and #p.cpu>=p.sampleFrames and not p.finish then
  if s.captureEnabled then
   -- Capture on the next actual drawn frame so the screenshot frame itself
   -- and its following intervals are absent from performance samples.
   s.capturePending=p.label;return
  else p.finish=stamp();p.completion='SAMPLED';s.nextStepPending=s.sequence~=nil end
 end
 if not label then return end
 local show,why=visible(s)
 if not show then if p then inc(p.discarded,'capture-'..why) end;return end
 if not s.lastRendered or s.lastRendered.phase~=p or s.lastRendered.updateSerial~=s.updateSerial then return end
 local g=s.game;local old=s.lastRendered.view
 if old.zoom~=g.zoom or old.camera.x~=g.camera.x or old.camera.y~=g.camera.y then
  if p then inc(p.discarded,'view-changed-after-render') end;return
 end
 local path=s.outputDir..'/'..label:gsub('[^%w%._%-]','_')..'.png'
 local row={label=label,path=path,view=old,event=s.captureEvent,stamp=stamp()}
 local ok,err=pcall(function()
  local image=Image();row.captured=graphics:TakeScreenShot(image)
  if row.captured then
   row.width=image:GetWidth();row.height=image:GetHeight()
   row.saved=image:SavePNG(path)
   row.matchesPhysicalSize=row.width==old.size.physicalWidth and row.height==old.size.physicalHeight
  end
 end)
 row.error=not ok and tostring(err) or nil
 row.status=ok and row.captured and row.saved and row.matchesPhysicalSize and 'CAPTURED_NOT_REVIEWED' or 'UNDETERMINED'
 if p then p.captures[#p.captures+1]=row end
 s.io.captures[#s.io.captures+1]=row;s.capturePending=nil;s.excludeThroughUpdate=s.updateSerial+2
 print('[OrganAtlasNativeProbe] screenshot '..path..' captured='..tostring(row.captured)..' saved='..tostring(row.saved)..' size='..tostring(row.width)..'x'..tostring(row.height)..(row.error and (' error='..row.error) or ''))
 if p and #p.cpu>=p.sampleFrames and not p.finish then
  p.finish=stamp();p.completion=row.status;s.nextStepPending=s.sequence~=nil
  print(string.format('[OrganAtlasNativeProbe] phase %s n=%d cpuP95ms=%.4f rawUpdateP95ms=%.4f',p.label,#p.cpu,percentiles(p.cpu).p95 or -1,percentiles(p.dt).p95 or -1))
  writeReport(s)
 end
end
local function installLifecycle(s,module,name)
 for _,op in ipairs({'prepare','release'}) do
  local old=module[op]
  local wrapper=function(vg,...)
   local started=os.clock();local results=table.pack(old(vg,...))
   local row={module=name,operation=op,contextIdentity=tostring(vg),cpuMs=(os.clock()-started)*1000,
    view=frameView(s),resources=snapshotResources(s,name..'-'..op,{observeOnly=true})}
   if #s.lifecycle<s.maxRecords then s.lifecycle[#s.lifecycle+1]=row else inc(s.droppedRecords,'lifecycle') end
   return table.unpack(results,1,results.n)
  end
  module[op]=wrapper;s.wrappers[#s.wrappers+1]={module=module,key=op,original=old,wrapper=wrapper}
 end
end
function P.start(game,options)
 options=options or {}
 if options.enabled~=true then return false,'Explicit enabled=true is required' end
 if active then return false,'probe already active' end
 if type(os.clock)~='function' then return false,'os.clock unavailable; CPU submission cannot be measured' end
 local R,H=options.render or require('war.Render'),options.hud or require('war.HUD')
 serial=serial+1
 local s={game=game,render=R,hud=H,atlas=require('war.OrganAtlasArt'),gastric=require('war.GastricArt'),
  runId=options.runId or ('native-'..os.time()..'-'..serial),outputDir=options.outputDir or 'qa/organ-atlas-native',
  captureEvent=options.captureEvent or 'EndFrame',warmupFrames=options.warmupFrames or 30,sampleFrames=options.sampleFrames or 120,
  maxRecords=options.maxRecords or 20000,updateSerial=0,rawDt=nil,excludeThroughUpdate=0,
  started=stamp(),phases={},resourceSnapshots={},lifecycle={},wrappers={},errors={},io={captures={}},
  droppedRecords={},maxObservedImages=0,captureEnabled=true,
  originalPresentation={x=game.camera.x,y=game.camera.y,zoom=game.zoom},
  engineSettings={maxFps=engine and engine.maxFps,maxInactiveFps=engine and engine.maxInactiveFps,
   timeStepSmoothing=engine and engine.timeStepSmoothing,vSync=graphics and graphics.vSync}}
 if s.captureEvent~='EndFrame' and s.captureEvent~='EndRendering' then return false,'captureEvent must be EndFrame or EndRendering' end
 active=s
 local ok,err=makeDirs(s.outputDir);s.io.directory={path=s.outputDir,created=ok,error=err}
 if not ok then print('[OrganAtlasNativeProbe] output directory unavailable: '..tostring(err)) end
 installLifecycle(s,s.atlas,'OrganAtlasArt');installLifecycle(s,s.gastric,'GastricArt')
 local original=R.draw
 local wrapper=function(g,...)
  local started=os.clock();local result=table.pack(pcall(original,g,...));local cpu=(os.clock()-started)*1000
  if not result[1] then s.errors[#s.errors+1]=tostring(result[2]);P.finish('R.draw-error');error(result[2],0) end
  local p=s.phase
  if p and not p.finish then
   local shown,why=visible(s)
   if not shown then inc(p.discarded,why)
   elseif s.lastDrawFrame==s.updateSerial then inc(p.discarded,'duplicate-draw-within-update')
   else
    s.lastDrawFrame=s.updateSerial;p.visibleFrames=p.visibleFrames+1
    if p.visibleFrames<=p.warmupFrames then inc(p.discarded,'warmup')
    elseif s.capturePending then inc(p.discarded,'screenshot-frame')
    elseif s.updateSerial<=s.excludeThroughUpdate then inc(p.discarded,'screenshot-overhead')
    elseif input and input.HasFocus and not input:HasFocus() then inc(p.discarded,'window-unfocused')
    elseif not finite(s.rawDt) or s.rawDt<=0 then inc(p.discarded,'invalid-raw-update-timestep')
    elseif #p.cpu<s.maxRecords then
     p.cpu[#p.cpu+1]=cpu;p.dt[#p.dt+1]=s.rawDt*1000;p.frames[#p.frames+1]=frameView(s)
    else inc(p.discarded,'bounded-record-limit') end
   end
  end
  s.lastRendered={phase=p,updateSerial=s.updateSerial,view=frameView(s)}
  return table.unpack(result,2,result.n)
 end
 R.draw=wrapper;s.wrappers[#s.wrappers+1]={module=R,key='draw',original=original,wrapper=wrapper}
 -- An isolated receiver prevents removing/replacing main's global Update handler.
 _OrganAtlasNativeProbeEvents=ScriptObject()
 s.eventNode=Node();s.receiver=s.eventNode:CreateScriptObject('_OrganAtlasNativeProbeEvents')
 s.receiver:SubscribeToEvent('Update',function(_,_,event)P.observeUpdate(event:GetFloat('TimeStep'))end)
 s.receiver:SubscribeToEvent(s.captureEvent,function()P.afterFrame()end)
 snapshotResources(s,'probe-start')
 print('[OrganAtlasNativeProbe] enabled run='..s.runId..' output='..s.outputDir..' visible='..tostring(visible(s)))
 return true
end
function P.finish(reason)
 local s=active;if not s then return lastReport end
 local now=stamp();s.finished=now;s.reason=reason or 'manual-finish'
 if s.phase and not s.phase.finish then s.phase.finish=now;s.phase.completion='INCOMPLETE' end
 snapshotResources(s,'probe-finish');writeReport(s)
 for _,w in ipairs(s.wrappers) do if w.module[w.key]==w.wrapper then w.module[w.key]=w.original else s.errors[#s.errors+1]='wrapper changed externally: '..w.key end end
 if s.receiver then s.receiver:UnsubscribeFromAllEvents() end
 s.game.camera.x=s.originalPresentation.x;s.game.camera.y=s.originalPresentation.y;s.game.zoom=s.originalPresentation.zoom
 lastReport=P.report();active=nil
 print('[OrganAtlasNativeProbe] finished '..s.reason..'; GPU timing/memory and visual acceptance remain unconfirmed')
 return lastReport
end
P.stop=P.finish
return P
