-- Explicit, temporary native QA entry. Never required by normal gameplay.
-- Drives the existing trial, commands and popup; captures the actual framebuffer.
local Q={}
-- File API transparently maps relative paths to the project's isolated storage.
local OUT='qa/organ-atlas-native/run-004'
local function canonical(value)
 if type(value)~='table' then return cjson.encode(value) end
 local keys={};for k in pairs(value) do keys[#keys+1]=k end
 table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
 local rows={};for _,k in ipairs(keys)do rows[#rows+1]=cjson.encode(tostring(k))..':'..canonical(value[k])end
 return '{'..table.concat(rows,',')..'}'
end
function Q.start(g,R,H)
 local P=require('qa.OrganAtlasNativeProbe')
 local A,GA=require('war.OrganAtlasArt'),require('war.GastricArt')
 local O,Save=require('war.OrganBattlefield'),require('war.Save')
 local UI=require('urhox-libs/UI')
 local oldAtlas,oldGastric=A.draw,GA.draw
 local art=true
 A.draw=function(...)if art then return oldAtlas(...)end;return false end
 GA.draw=function(...)if art then return oldGastric(...)end;return false end
 g.startOrganTrial();g.paused=true;g.debugFps=true
 g.selection={};for id in pairs(g.state.entities)do g.selection[id]=true end
 pcall(function()graphics:Raise()end)
 local evidence={schema='organ-atlas-native-harness/v1',outputDir=OUT,
  trialEntry='game.startOrganTrial',automaticNativeStartAuthorized=true,
  baseline=Save.snapshot(g.state),checks={},captures={},resourceCycles={},errors={},
  limitations={'Only this physical window/DPR is native evidence; other sizes remain offline/browser checks.',
   'World rendering CPU and engine Update interval are separate from GPU execution timing.'}}
 local frozen=canonical(evidence.baseline)
 local initialVisibility=canonical(g.state.factions[1].visible)
 local ok,err=P.start(g,{enabled=true,render=R,hud=H,outputDir=OUT,runId='run-004',captureEvent='EndRendering',warmupFrames=30,sampleFrames=120})
 assert(ok,err)
 local function write()
  local f=File(OUT..'/harness.json',FILE_WRITE);assert(f and f:IsOpen());f:WriteString(cjson.encode(evidence));f:Close()
 end
 local function stillFrozen(label)
  local row={label=label,saveUnchanged=canonical(Save.snapshot(g.state))==frozen,
   visibilityUnchanged=canonical(g.state.factions[1].visible)==initialVisibility,
   simulationTime=g.state.time,tick=g.state.tick,rng=g.state.rng,realTime=g.realTime}
  row.status=row.saveUnchanged and row.visibilityUnchanged and 'PASS' or 'FAIL'
  evidence.checks[#evidence.checks+1]=row
 end
 local steps={}
 local ids={'liver','stomach','brain','lung_r','lung_l','pancreas','kidney_r','kidney_l','large_intestine','small_intestine','bladder','heart'}
 for _,id in ipairs(ids)do
  local d=O.organ(id);local b=d.sourceBox;local room=d.rooms[1].centerSource
  for _,z in ipairs({.15,.085,.12,.149,.151})do
   steps[#steps+1]={label=id..'-z'..z,organId=id,zoom=z,x=room[1]*2,y=room[2]*2+512,frames=60}
  end
  steps[#steps+1]={label=id..'-whole-organ',organId=id,box=b,x=b[1]+b[3],y=b[2]+b[4]+512,frames=60}
 end
 for _,pair in ipairs({{'liver',.15},{'stomach',.15},{'stomach',.12},{'whole-body',.006}})do
  local id,z=pair[1],pair[2];local d=id~='whole-body' and O.organ(id)
  local p=d and d.rooms[1].centerSource or {512,768}
  for _,enabled in ipairs({false,true,false,true})do
   steps[#steps+1]={label='perf-'..id..'-z'..z..'-'..(enabled and 'on' or 'off')..'-'..(#steps+1),
    organId=d and id or nil,zoom=z,x=p[1]*2,y=p[2]*2+512,artEnabled=enabled,frames=240}
  end
 end
 local index,frames,stage,stageFrames,firstCapture=0,0,'warmup',0,false
 local function advance()
  stillFrozen('before-phase-'..(index+1));index=index+1
  local step=steps[index]
  if not step then stage='popup';stageFrames=0;art=true;H.mapMenu(g);stillFrozen('popup-open');return end
  art=step.artEnabled~=false
  if step.box then
   local b=step.box;local layout=g.stage or {w=R.w,h=R.h}
   step.zoom=math.min(layout.w/(64*(b[3]-b[1])),layout.h/(64*(b[4]-b[2])))*.86
  end
  g.camera.x,g.camera.y=step.x,step.y;g.zoom=step.zoom
  P.beginPhase(step.label,{organId=step.organId,zoom=step.zoom,artEnabled=art,warmupFrames=30,sampleFrames=step.frames})
  stageFrames=0
  print('[OrganAtlasNativeHarness] phase '..index..'/'..#steps..' '..step.label..' focus='..tostring(input:HasFocus()))
 end
 local function capture(label)
  local image=Image();local row={label=label,frame=GetTime():GetFrameNumber(),realTime=g.realTime,
   simulationTime=g.state.time,modal=g.modal,focus=input:HasFocus(),path=OUT..'/'..label..'.png'}
  row.captured=graphics:TakeScreenShot(image);row.saved=row.captured and image:SavePNG(row.path)
  row.physicalWidth,row.physicalHeight=graphics:GetWidth(),graphics:GetHeight();row.dpr=graphics:GetDPR()
  evidence.captures[#evidence.captures+1]=row
  print('[OrganAtlasNativeHarness] capture '..label..' saved='..tostring(row.saved));write()
 end
 _OrganAtlasNativeHarnessEvents=ScriptObject()
 local node=Node();local receiver=node:CreateScriptObject('_OrganAtlasNativeHarnessEvents')
 receiver:SubscribeToEvent('Update',function()
  local good,errorMessage=pcall(function()
   frames=frames+1;stageFrames=stageFrames+1
   if stage=='warmup' and stageFrames>=120 and stageFrames%20==0 then
    evidence.initialResources=P.inspectResources('loaded-before-sequence')
    if evidence.initialResources.status=='MEASURED' and A.ready(R.vg,g.state) and A.ready(UI.GetNVGContext(),g.state)then
     stage='sequence';advance()
    elseif stageFrames>=900 then error('Full-resolution textures did not load within 900 frames')end
   elseif stage=='sequence' then
    if not firstCapture and stageFrames==40 then P.capture('first-visible-liver');firstCapture=true end
    if stageFrames%20==0 then
     local report=P.report();local phase=report.phases[#report.phases]
     if phase and phase.completion~='INCOMPLETE' then advance()
     elseif stageFrames>=900 then
      -- Keep visual evidence if focus prevents meaningful performance sampling.
      P.capture(steps[index].label..'-focus-timeout');evidence.errors[#evidence.errors+1]='Focus/sample timeout: '..steps[index].label
      advance()
     end
    end
   elseif stage=='popup' and stageFrames>=240 then
    stillFrozen('popup-after-four-seconds');H.closeModal(g);stage='resources';stageFrames=0
   elseif stage=='resources' then
    if stageFrames%10==1 then
     local ui=UI.GetNVGContext()
     A.release(R.vg);GA.release(R.vg);A.release(ui);GA.release(ui)
     local count=0;for _,h in pairs(A.handles)do for _,v in pairs(h)do if v>0 then count=count+1 end end end
     for _,v in pairs(GA.handles)do if v>0 then count=count+1 end end
     local row={cycle=#evidence.resourceCycles+1,afterRelease=count,
      released=P.inspectResources('released-cycle-'..(#evidence.resourceCycles+1),{expectReleased=true})}
     R.prepare(g.state);H.prepareBattlefield(g.state)
     row.afterPrepare=P.inspectResources('resource-cycle-'..row.cycle)
     evidence.resourceCycles[#evidence.resourceCycles+1]=row
     if #evidence.resourceCycles>=25 then
      stillFrozen('after-25-context-cycles');stage='done';art=true
      evidence.completed=true;evidence.finalResources=P.inspectResources('final-reprepared')
      evidence.probe=P.finish('all-native-harness-stages-finished')
      A.draw=oldAtlas;GA.draw=oldGastric
      g.paused=false;g.debugFps=false;g.zoom=.15
      local p=O.organ('stomach').rooms[1].centerSource;g.camera.x,g.camera.y=p[1]*2,p[2]*2+512
      write();receiver:UnsubscribeFromAllEvents()
      print('[OrganAtlasNativeHarness] COMPLETE; original drawing restored, stomach trial available')
     end
    end
   end
  end)
  if not good then
   evidence.errors[#evidence.errors+1]=tostring(errorMessage);evidence.completed=false
   P.finish('harness-error');A.draw=oldAtlas;GA.draw=oldGastric;write();receiver:UnsubscribeFromAllEvents()
   print('[OrganAtlasNativeHarness] ERROR '..tostring(errorMessage))
  end
 end)
 receiver:SubscribeToEvent('EndFrame',function()
  if stage=='popup' and (stageFrames==40 or stageFrames==180)then capture('native-map-popup-'..stageFrames)end
 end)
 print('[OrganAtlasNativeHarness] explicit native acceptance scheduled, paused real trial; totalPhases='..#steps)
end
return Q
