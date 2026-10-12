-- Opt-in native heartbeat/seam driver; external Cocoa window captures use ack.txt.
-- No game screenshot API, asset generation, simulation steps, or native auto-entry.
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
function Q.start(g,R,H,options)
 assert(not receiver,'HeartNativeProbe is already running')
 local opts=options or {}
 local OUT=opts.outputDir or 'qa/heart-native/heart-v1-001'
 local A,T,Art,Save,UI=require('war.FullBodyMapArt'),require('war.HeartDisplayTransform'),
  require('war.HeartArt'),require('war.Save'),require('urhox-libs/UI')
 for _,p in ipairs({'qa','qa/heart-native',OUT})do assert(fileSystem:DirExists(p)or fileSystem:CreateDir(p),p)end
 local function write(name,value)
  local f=File(OUT..'/'..name,FILE_WRITE);assert(f and f:IsOpen(),name)
  f:WriteString(cjson.encode(value));f:Close()
 end
 local ack=File(OUT..'/ack.txt',FILE_WRITE);assert(ack and ack:IsOpen())
 ack:WriteString('0\n');ack:Close()
 if opts.startMode~='current'then g.startFullBodyMap()end
 assert(T.enabled(g.state),'heartbeat probe needs fullbody or active heart trial')
 g.paused=true;g.selection={};graphics:Raise()
 local frozen=canonical(Save.snapshot(g.state))
 local visibility=canonical(g.state.factions[1].visible)
 local phases={0,.10,.30,.49,.59,.90};local steps={}
 for _,zoom in ipairs({.15,.12,.22})do for _,phase in ipairs(phases)do
  steps[#steps+1]={label='heart-z'..zoom..'-p'..phase,zoom=zoom,time=phase}
 end end
 if opts.steps then steps=opts.steps end
 local source=opts.sourcePoint or {518,411}
 local fixedCamera={x=source[1]*2,y=source[2]*2+512}
 local evidence={schema='heart-native-external-capture/v1',outputDir=OUT,phases={},errors={},
  runId=tostring(os.time()),sourcePoint=source,expectedTriangles=384,
  api=graphics:GetApiName(),physicalWidth=graphics:GetWidth(),physicalHeight=graphics:GetHeight(),dpr=graphics:GetDPR(),
  nativeEvidence=true,screenshotsCapturedBy='external Cocoa game-window capture',
  scope='Paused fullbody/heart trial; all captures follow stable rendered-frame ack; CPU submission is not GPU time.'}
 local old=R.draw;local oldInactiveFps=engine.maxInactiveFps;engine.maxInactiveFps=60
 local index,frames,draws,lastDraw=0,0,0,0
 local started,published,finished=false,false,false
 local cpuSamples,frameSamples={},{}
 local fixedZoom,fixedTime=.15,0
 R.draw=function(...)
  g.camera.x,g.camera.y=fixedCamera.x,fixedCamera.y;g.zoom=fixedZoom
  local liveTime=g.realTime;g.realTime=fixedTime
  local begun=os.clock();T.beginFrame(g)
  local result=table.pack(old(...))
  local cpu=(os.clock()-begun)*1000;draws=draws+1
  if started and frames>=30 and not published then cpuSamples[#cpuSamples+1]=cpu end
  g.realTime=liveTime
  return table.unpack(result,1,result.n)
 end
 _HeartNativeProbeEvents=ScriptObject()
 ownerNode=Node();receiver=ownerNode:CreateScriptObject('_HeartNativeProbeEvents')
 assert(receiver,'native event receiver unavailable')
 local function finish(reason)
  if finished then return end;finished=true
  R.draw=old;engine.maxInactiveFps=oldInactiveFps
  if receiver then receiver:UnsubscribeFromAllEvents()end
  receiver=nil;ownerNode=nil
  evidence.finishedReason=reason;evidence.completed=reason=='all-phases-captured'
  evidence.finalSnapshotUnchanged=canonical(Save.snapshot(g.state))==frozen
  evidence.finalVisibilityUnchanged=canonical(g.state.factions[1].visible)==visibility
  evidence.finalResourceStats=A.stats();write('report.json',evidence)
  print('[HeartNative] FINISHED '..reason)
  if opts.onFinish then
   local ok,err=pcall(opts.onFinish,evidence)
   if not ok then evidence.errors[#evidence.errors+1]='onFinish: '..tostring(err);write('report.json',evidence)end
  end
 end
 Q.stop=function()finish('cancelled')end
 local function advance()
  index=index+1;local step=steps[index]
  if not step then finish('all-phases-captured');return end
  H.closeModal(g);g.paused=true;g.selection={}
  fixedZoom,fixedTime=step.zoom,step.time
  g.camera.x,g.camera.y=fixedCamera.x,fixedCamera.y;g.zoom=fixedZoom
  H.sidebar(g)
  if opts.beforeView then opts.beforeView(step)end
  frames=0;lastDraw=draws;published=false;cpuSamples={};frameSamples={}
 end
 receiver:SubscribeToEvent('Update',function(_,_,event)
  local ok,err=pcall(function()
   frames=frames+1
   if not started then
    if frames>=120 and A.ready(R.vg,g.state)and A.ready(UI.GetNVGContext(),g.state)then started=true;advance()
    elseif frames>1800 then finish('resources-timeout')end
    return
   end
   if frames>18000 then finish('capture-ack-timeout');return end
   if frames>=30 and not published then frameSamples[#frameSamples+1]=event:GetFloat('TimeStep')*1000 end
   if frames>=90 and draws-lastDraw>=60 and not published then
    local f=T.frame(g);local step=steps[index]
    local row={runId=evidence.runId,index=index,total=#steps,label=step.label,stable=true,
     ackExpected=evidence.runId..':'..index,zoom=fixedZoom,camera=fixedCamera,phase=step.time,
     frame=GetTime():GetFrameNumber(),wallTime=os.time(),draws=draws,phaseDraws=draws-lastDraw,
     renderedHeartbeatTime=f.time,renderedHeartbeatPhase=f.sample.phase,fps=g.fps,
     simulationTime=g.state.time,tick=g.state.tick,rng=g.state.rng,
     worldReady=A.ready(R.vg,g.state),uiReady=A.ready(UI.GetNVGContext(),g.state),
     fullbodyStats=A.stats(),heartDrawTriangles=Art.last.triangles,heartActualFills=Art.last.actualFills,heartSubmittedTriangles=Art.last.visibleTriangles,meshTriangles=#f.mesh.triangles,
     meshSafe=f.safe,minAreaRatio=f.minAreaRatio,frameP95Ms=percentile(frameSamples,.95),
     maxOffsetSource=f.maxOffsetSource,maxOffsetLogicalPixels=f.maxOffsetSource*64*fixedZoom,
     fixedSections=#f.mesh.sections,pinnedMeshVertices=f.mesh.pinnedVertices,
     renderCpuP95Ms=percentile(cpuSamples,.95),renderCpuSamples=#cpuSamples,
     snapshotUnchanged=canonical(Save.snapshot(g.state))==frozen,
     visibilityUnchanged=canonical(g.state.factions[1].visible)==visibility}
    evidence.phases[#evidence.phases+1]=row;write('report.json',evidence);write('current.json',row)
    published=true;print('[HeartNative] CAPTURE_READY '..index..' '..row.label)
   elseif published and fileSystem:FileExists(OUT..'/ack.txt')then
    local f=File(OUT..'/ack.txt',FILE_READ)
    if f and f:IsOpen()then
     local value=f:ReadLine();f:Close()
     if tonumber(value)==index or value==evidence.runId..':'..index then advance()end
    end
   end
  end)
  if not ok then evidence.errors[#evidence.errors+1]=tostring(err);finish('driver-error')end
 end)
 write('report.json',evidence);print('[HeartNative] START phases='..#steps)
 return evidence
end
return Q
