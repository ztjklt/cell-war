-- Native timed comparison after all textures are decoded; no screenshot API.
-- Frame dt includes the engine frame, while renderCpuMs is CPU submission only.
local Q={}
local function percentile(rows,p)
 table.sort(rows);return rows[math.max(1,math.ceil(#rows*p))]or 0
end
function Q.start(g,R,options)
 local opts=options or{};local A=require('war.FullBodyMapArt')
 local UI,Save=require('urhox-libs/UI'),require('war.Save')
 local out=opts.outputDir or'qa/organ-atlas-native/fullbody-performance-001'
 for _,p in ipairs({'qa','qa/organ-atlas-native',out})do assert(fileSystem:DirExists(p)or fileSystem:CreateDir(p))end
 local camera=opts.camera or{x=1036,y=1492}
 g.startFullBodyMap();g.paused=true;g.zoom=.15;g.camera={x=camera.x,y=camera.y};graphics:Raise()
 local oldInactive=engine.maxInactiveFps;engine.maxInactiveFps=60
 local frozenTime,frozenTick,frozenRng=g.state.time,g.state.tick,g.state.rng
 local old,frame,phase,ready=R.draw,0,1,false
 local result={schema='fullbody-native-timing/v1',zoom=.15,camera={x=camera.x,y=camera.y},phases={},dpr=graphics:GetDPR(),
  physicalWidth=graphics:GetWidth(),physicalHeight=graphics:GetHeight(),
  samplesPerPhase=180,warmupPerPhase=60,GPUTimeMeasured=false,
  scope='Native engine frame dt plus Lua render CPU submission; capped at 60 FPS; same camera and loaded resources.'}
 local phases={false,true,true,false};local latestCpu=0
 R.draw=function(...)
  local t=os.clock();local r=table.pack(old(...));latestCpu=(os.clock()-t)*1000
  return table.unpack(r,1,r.n)
 end
 _FullBodyPerformanceEvents=ScriptObject()
 local node=Node();local receiver=node:CreateScriptObject('_FullBodyPerformanceEvents')
 local function write()
  local f=File(out..'/report.json',FILE_WRITE);assert(f and f:IsOpen());f:WriteString(cjson.encode(result));f:Close()
 end
 local function finish(reason)
  A.disabled=false;R.draw=old;engine.maxInactiveFps=oldInactive;receiver:UnsubscribeFromAllEvents()
  result.completed=reason=='complete';result.reason=reason
  result.simulationUnchanged=g.state.time==frozenTime and g.state.tick==frozenTick and g.state.rng==frozenRng
  result.resources=A.stats();write();print('[FullBodyPerformance] '..reason)
 end
 receiver:SubscribeToEvent('Update',function(_,_,event)
  local dtEvent=event --[[@as UpdateEventData]]
  local ok,err=pcall(function()
   frame=frame+1
   if not ready then
    if frame>=120 and A.ready(R.vg,g.state)and A.ready(UI.GetNVGContext(),g.state)then
     ready=true;frame=0;A.disabled=not phases[phase]
     result.phases[phase]={enabled=phases[phase],frameMs={},renderCpuMs={}}
    elseif frame>1800 then finish('resources-timeout')end
    return
   end
   local row=result.phases[phase]
   if frame>60 then
    row.frameMs[#row.frameMs+1]=dtEvent:GetFloat('TimeStep')*1000
    row.renderCpuMs[#row.renderCpuMs+1]=latestCpu
   end
   if frame>=240 then
    row.frameP95Ms=percentile(row.frameMs,.95);row.renderCpuP95Ms=percentile(row.renderCpuMs,.95)
    write();phase=phase+1;frame=0
    if phase>#phases then finish('complete');return end
    A.disabled=not phases[phase];result.phases[phase]={enabled=phases[phase],frameMs={},renderCpuMs={}}
   end
  end)
  if not ok then result.error=tostring(err);finish('driver-error')end
 end)
 print('[FullBodyPerformance] START');return result
end
return Q
