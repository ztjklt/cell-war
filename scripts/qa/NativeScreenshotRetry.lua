-- Explicit temporary diagnostic entry; never loaded by normal gameplay.
local Q={}
function Q.start(g,R,H)
 local out='qa/organ-atlas-native/screenshot-retry-001'
 local A=require('war.OrganAtlasArt')
 local UI=require('urhox-libs/UI')
 local evidence={schema='native-screenshot-retry/v1',captures={},errors={},outputDir=out,
  scope='Actual native trial framebuffer; test PNG is only a file-write control.'}
 local function write()
  local f=File(out..'/report.json',FILE_WRITE)
  assert(f and f:IsOpen(),'Cannot open diagnostic report')
  f:WriteString(cjson.encode(evidence));f:Close()
 end
 local function safe(label,fn)
  local ok,result=pcall(fn)
  if not ok then evidence.errors[#evidence.errors+1]={label=label,error=tostring(result)} end
  return ok and result or nil
 end
 safe('create-directory',function()
  for _,p in ipairs({'qa','qa/organ-atlas-native',out})do
   assert(fileSystem:DirExists(p) or fileSystem:CreateDir(p),p)
  end
  return true
 end)
 g.startOrganTrial();g.paused=true
 safe('raise-window',function()graphics:Raise();return true end)
 evidence.api=safe('api-name',function()return graphics:GetApiName()end)
 evidence.initialized=safe('initialized',function()return graphics:IsInitialized()end)
 evidence.deviceLost=safe('device-lost',function()return graphics:IsDeviceLost()end)
 evidence.gpuTiming=safe('gpu-timing',function()return graphics:GetGpuTimingStatsString()end)
 evidence.requestScreenShotBinding=safe('async-binding',function()return type(graphics.RequestScreenShot)end)
 evidence.startFrame=GetTime():GetFrameNumber()
 evidence.width,evidence.height,evidence.dpr=graphics:GetWidth(),graphics:GetHeight(),graphics:GetDPR()
 evidence.control={path=out..'/file-write-control.png',isGameScreenshot=false}
 safe('control-png',function()
  local image=Image();evidence.control.allocated=image:SetSize(32,32,3)
  image:Clear(Color(.35,.6,.4));evidence.control.saved=image:SavePNG(evidence.control.path)
  return true
 end)
 local steps={{event='Update',warm=180},{event='PreEndFrame',warm=45},
  {event='EndFrame',warm=45},{event='EndRendering',warm=45},
  {event='PostRenderUpdate',warm=45},{event='BeginRendering',warm=45}}
 local index,frames,draws,ready=1,0,0,false
 local old=R.draw
 R.draw=function(...)
  local result=table.pack(old(...));draws=draws+1
  return table.unpack(result,1,result.n)
 end
 _NativeScreenshotRetryEvents=ScriptObject()
 local node=Node();local receiver=node:CreateScriptObject('_NativeScreenshotRetryEvents')
 local function finish(reason)
  evidence.finishedReason=reason;evidence.finalFrame=GetTime():GetFrameNumber();evidence.actualWorldDraws=draws
  evidence.pngCount=0;for _,row in ipairs(evidence.captures)do if row.saved then evidence.pngCount=evidence.pngCount+1 end end
  R.draw=old;receiver:UnsubscribeFromAllEvents();write()
  print('[NativeScreenshotRetry] FINISHED reason='..reason..' gamePng='..evidence.pngCount..' control='..tostring(evidence.control.saved))
 end
 local function capture(event)
  local step=steps[index]
  if not ready or not step or step.event~=event or frames<step.warm then return end
  local row={event=event,frame=GetTime():GetFrameNumber(),draws=draws,focus=input:HasFocus(),
   minimized=input:IsMinimized(),initialized=graphics:IsInitialized(),deviceLost=graphics:IsDeviceLost(),
   atlasWorldReady=A.ready(R.vg,g.state),atlasUiReady=A.ready(UI.GetNVGContext(),g.state),
   path=out..'/'..index..'-'..event..'.png'}
  local started=os.time();local cpu=os.clock()
  local ok,err=pcall(function()
   local image=Image();row.captured=graphics:TakeScreenShot(image)
   row.width,row.height=image:GetWidth(),image:GetHeight()
   if row.captured then row.saved=image:SavePNG(row.path)end
  end)
  row.elapsedWholeSeconds=os.time()-started;row.cpuMs=(os.clock()-cpu)*1000
  row.error=not ok and tostring(err) or nil
  evidence.captures[#evidence.captures+1]=row
  print('[NativeScreenshotRetry] event='..event..' captured='..tostring(row.captured)..' saved='..tostring(row.saved)..' elapsedWholeSeconds='..row.elapsedWholeSeconds)
  index=index+1;frames=0;write()
  if not steps[index]then finish('all-six-stages-attempted')end
 end
 receiver:SubscribeToEvent('Update',function()
  frames=frames+1
  if not ready and frames>=120 then
   ready=A.ready(R.vg,g.state) and A.ready(UI.GetNVGContext(),g.state)
   if ready then frames=0;evidence.readyFrame=GetTime():GetFrameNumber();write()end
  end
  if GetTime():GetFrameNumber()-evidence.startFrame>1500 then finish('bounded-timeout');return end
  capture('Update')
 end)
 for _,event in ipairs({'PreEndFrame','EndFrame','EndRendering','PostRenderUpdate','BeginRendering'})do
  local name=event
  receiver:SubscribeToEvent(name,function()capture(name)end)
 end
 write();print('[NativeScreenshotRetry] START api='..tostring(evidence.api)..' control='..tostring(evidence.control.saved))
 return evidence
end
return Q
