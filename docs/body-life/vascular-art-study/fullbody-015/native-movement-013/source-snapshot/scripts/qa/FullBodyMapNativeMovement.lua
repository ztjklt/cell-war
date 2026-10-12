-- Actual commands and the normal 1x update loop; external authorized window capture.
local Q={}
function Q.start(g,R,H,options)
 local opts=options or{};local out=opts.outputDir or'qa/organ-atlas-native/fullbody-movement-001'
 local F,C,W,S,D,M,A=require('war.FullBodyBattlefield'),require('war.Commands'),require('war.World'),
  require('war.Simulation'),require('war.Data'),require('war.Motion'),require('war.FullBodyMapArt')
 local Traffic=require('war.OrganTraffic')
 local function trafficSnapshot()
  local stats=Traffic.stats(g.state);if stats.expired==nil then stats.expired=0 end
  assert(type(stats.activePairs)=='number'and stats.activePairs>=0 and stats.activePairs%1==0,'invalid actual traffic count')
  assert(type(stats.expired)=='number'and stats.expired>=0 and stats.expired%1==0,'invalid actual traffic expiry count')
  return stats
 end
 local timeout=opts.recordingTimeoutSeconds or 120
 assert(type(timeout)=='number'and timeout>0 and timeout<=360,'invalid native recording deadline')
 local UI,O=require('urhox-libs/UI'),require('war.OrganBattlefield');local cases=opts.cases or require('qa.FullBodyMapNativeMovementData')
 assert(type(cases)=='table'and #cases>0,'empty movement case set')
 if opts.cases then
  assert(opts.expectedCaseCount==#cases,'private case count declaration mismatch')
  assert(type(opts.caseDataSha256)=='string'and #opts.caseDataSha256==64 and not opts.caseDataSha256:find('[^0-9a-f]'),'private data SHA required')
 end
 if opts.originalNoFastSetup then
  for _,config in ipairs(cases)do for _,actor in ipairs(config.actors)do assert(not actor.setupSource,'original traffic cases cannot use accelerated setup')end end
 end
 for _,p in ipairs({'qa','qa/organ-atlas-native',out})do assert(fileSystem:DirExists(p)or fileSystem:CreateDir(p))end
 local result={schema='fullbody-native-real-movement/v1',cases={},errors={},speed=1,timeCompression=1,
  declaredCaseCount=#cases,caseDataSha256=opts.caseDataSha256,
  dpr=graphics:GetDPR(),physicalWidth=graphics:GetWidth(),physicalHeight=graphics:GetHeight(),recordingTimeoutSeconds=timeout,requireTrafficSettled=true}
 local function write(name,v)local f=File(out..'/'..name,FILE_WRITE);assert(f and f:IsOpen());f:WriteString(cjson.encode(v));f:Close()end
 local function position(e)return{id=e.id,kind=e.kind,x=e.x,y=e.y,lane=e.vesselLane or 0,
  orders=#e.orders,time=g.state.time,tick=g.state.tick,transit=e.gastricTransit}end
 local index,frame,setupIndex,setupBudget,stage=0,0,1,0,'new'
 ---@class FullBodyNativeCaptureReady
 ---@field nonce string
 ---@field ownerPid number
 ---@class FullBodyNativeMotionCase
 ---@field frames table[]
 ---@field movedDistanceWorld number[]
 ---@field movementFrames number[]
 ---@field commands {id:number,accepted:boolean,requested:{x:number,y:number,lane:number},resolved:{x:number,y:number,lane:number}}[]
 ---@field captureReady FullBodyNativeCaptureReady|nil
 ---@field idleStarts {id:integer,x:number,y:number,lane:number,orders:integer}[]|nil
 ---@field idleArrivals table[]|nil
 ---@field namedGateRetention {pathChecks:integer,actualAnchorSeenInPath:boolean,actualAnchorReached:boolean}|nil
 ---@field [string] any
 ---@type FullBodyNativeMotionCase|nil
 local row=nil
 local actors,startTime,startVisual,oldRecord={},0,0,M.record
 local idleActors={}
 -- The external collector must be ready before the normal 1x loop starts.
 local function captureArmed()
  if not row then return false end
  if not fileSystem:FileExists(out..'/capture-ready.json')then return false end
  local f=File(out..'/capture-ready.json',FILE_READ)
  if not f or not f:IsOpen()then return false end
  local raw=f:ReadLine();f:Close();local valid,armed=pcall(cjson.decode,raw)
  local matches=valid and type(armed)=='table'and armed.schema=='fullbody-native-capture-ready/v1'
   and armed.stateRunId==row.stateRunId and armed.index==index
   and armed.manifestSha256==require('war.FullBodyMapArtData').manifestSha256
   and type(armed.nonce)=='string'and #armed.nonce==32 and not armed.nonce:find('[^0-9a-f]')
   and type(armed.ownerPid)=='number'and armed.ownerPid>0 and armed.ownerPid%1==0
  if matches and opts.cases then matches=armed.declaredCaseCount==#cases and armed.caseDataSha256==opts.caseDataSha256 and armed.id==row.id end
  if matches then row.captureReady=armed end
  return matches
 end
 local finished=false
 local draws,terminalDraws,terminalFrame,terminalStarted=0,0,nil,0
 local function verifyNormalRecording()
  assert(g.speed==1 and g.paused==false,'recording must stay on normal1x unpaused main loop')
  row.normalSpeedChecks=(row.normalSpeedChecks or 0)+1
  row.recordingActualSpeed=g.speed;row.recordingActualPaused=g.paused
  result.actualSpeed=g.speed;result.actualPaused=g.paused
 end
 local function verifyIdle()
  if not row.idleStarts then return end
  for i,e in ipairs(idleActors)do local p=row.idleStarts[i]
   assert(g.state.entities[e.id]==e and e.hp>0 and e.x==p.x and e.y==p.y and e.vesselLane==p.lane
    and #e.orders==p.orders and not e.gastricTransit,'idle scout position/plane/order changed')
  end
  row.idleChecks=(row.idleChecks or 0)+1
 end
 local function inspectGate(e)
  local gate=row and row.config.requiredGate;if not gate or not actors[1]or e.id~=actors[1].id then return end
  local p=gate.tissueAnchorWorld;local check=row.namedGateRetention
  if (e.x-p[1])^2+(e.y-p[2])^2<=.075^2 then check.actualAnchorReached=true end
  if e.vesselLane==0 and not e.gastricTransit and not check.actualAnchorReached and
   #(e.path or{})>0 and not e.pathPending and not e.pathFailed then
   local present=false
   for i=e.pathIndex or 1,#e.path do local q=e.path[i]
    if (q.x-p[1])^2+(q.y-p[2])^2<=1e-8 then present=true end
   end
   check.pathChecks=check.pathChecks+1
   assert(present,'named tissue anchor omitted before actual approach')
   check.actualAnchorSeenInPath=true
  end
 end
 M.record=function(e)
  if row and stage=='record'then verifyNormalRecording()end
  oldRecord(e)
  if row and stage=='record'and g.state.entities[e.id]==e then
   verifyIdle();inspectGate(e);row.trace[#row.trace+1]=position(e)
  end
 end
 _FullBodyMovementEvents=ScriptObject()
 local node=Node();local receiver=node:CreateScriptObject('_FullBodyMovementEvents')
 receiver:SubscribeToEvent('NanoVGRender',function()draws=draws+1 end)
 local function finish(reason)
  if finished then return end;finished=true;M.record=oldRecord;g.paused=true
  result.completed=reason=='all-cases';result.reason=reason;result.resources=A.stats()
  receiver:UnsubscribeFromAllEvents();write('report.json',result)
  write('current.json',{stage='finished',recording=false,wallTime=os.time(),reason=reason})
  print('[FullBodyMovement] '..reason)
 end
 local function advance()
  index=index+1;if not cases[index]then finish('all-cases');return end
  stage='ready';write('current.json',{stage='ready',recording=false,index=index,wallTime=os.time()})
  local config=cases[index];local s=F.new(73);s.entities={};s.commands={};W.rebuild(s)
  g.replaceState(s);H.closeModal(g);g.paused=true;g.speed=1;g.zoom=.15;g.selection={}
  actors={};idleActors={};frame=0;setupIndex=1;setupBudget=0;stage='ready'
  row={id=config.id,index=index,total=#cases,config=config,starts={},trace={},frames={},setupCommands={},commands={},
   stateRunId=tostring(os.time())..'/'..index,readyDraws=draws,
   setupUsesFixedStepPreparation=not opts.originalNoFastSetup,recordingUsesNormalMainLoop=true,recordingTimeoutSeconds=timeout,requireTrafficSettled=true,movedDistanceWorld={},movementFrames={}}
  write('current.json',{stage='ready',recording=false,stateRunId=row.stateRunId,index=index,id=row.id,total=#cases,declaredCaseCount=#cases,caseDataSha256=opts.caseDataSha256,wallTime=os.time()})
  result.cases[#result.cases+1]=row
  if opts.populateIdle then
   idleActors=assert(opts.populateIdle(s,config,C,W),'idle population must return a list')
   row.idleStarts={};for _,e in ipairs(idleActors)do row.idleStarts[#row.idleStarts+1]=position(e)end
   row.idlePopulationBeforeActiveActors=true
  end
  if config.requiredGate then row.namedGateRetention={pathChecks=0,actualAnchorSeenInPath=false,actualAnchorReached=false}end
  for i,a in ipairs(config.actors)do
   local p=a.setupSource
   local e=assert(C.spawn(s,'unit',a.kind,1,p and p[1]*2 or a.x,p and p[2]*2+512 or a.y),'spawn rejected')
   assert(e.vesselLane==(p and 0 or a.lane),'spawn plane mismatch')
   if a.expectedId then assert(e.id==a.expectedId and e.x==a.x and e.y==a.y,'active identity/spawn was changed')end
   if opts.originalNoFastSetup then
    assert(e.x==a.x and e.y==a.y and e.id==(opts.expectedFirstActorId or 25)+i-1 and #e.orders==0,'original start position/id/order changed')
   end
   actors[i]=e;g.selection[e.id]=true;row.starts[#row.starts+1]=position(e)
  end
  W.rebuild(s)
  local a=config.actors[1];local goal=config.group or a;g.camera={x=(a.x+(goal.tx or goal.x))*.5,y=(a.y+(goal.ty or goal.y))*.5};H.sidebar(g);graphics:Raise()
  -- Publish this case before recording; the window collector must be able to
  -- bind moving frames to the current case rather than wait for its terminal.
  write('report.json',result)
 end
 receiver:SubscribeToEvent('Update',function()
  local ok,err=pcall(function()
   frame=frame+1
   if stage=='new'then advance();return end
   if stage=='ready'then
    if frame%15==0 then write('current.json',{stage='ready',recording=false,stateRunId=row.stateRunId,index=index,id=row.id,total=#cases,declaredCaseCount=#cases,caseDataSha256=opts.caseDataSha256,wallTime=os.time()})end
    if frame>=120 and draws-row.readyDraws>=2 and A.ready(R.vg,g.state)and A.ready(UI.GetNVGContext(),g.state)and captureArmed()then
     row.recordingCaptureArmed=true
     stage='setup';write('current.json',{stage='setup',recording=false,stateRunId=row.stateRunId,index=index,id=row.id,total=#cases,declaredCaseCount=#cases,caseDataSha256=opts.caseDataSha256,wallTime=os.time()})
    elseif frame>1800 then error('resource timeout')end
    return
   end
   local config=cases[index]
   if stage=='terminal'then
    assert(terminalFrame and row.completed,'terminal arrival was not verified')
    terminalFrame.terminalReady=draws-terminalDraws>=2
    terminalFrame.terminalRenderedFrames=draws-terminalDraws
    terminalFrame.wallTime=os.time();terminalFrame.visualElapsed=g.realTime-startVisual
    write('current.json',terminalFrame)
    if terminalFrame.terminalReady and fileSystem:FileExists(out..'/terminal-ack.json')then
     local f=File(out..'/terminal-ack.json',FILE_READ)
     if f and f:IsOpen()then
      local raw=f:ReadLine();f:Close();local valid,ack=pcall(cjson.decode,raw)
      -- Decoded JSON is validated by captureArmed before it is stored here.
      ---@type any
      local captureReady=row.captureReady
      if valid and type(ack)=='table'and ack.stateRunId==row.stateRunId and ack.index==index
       and ack.terminal==true and type(ack.pngSha256)=='string'and #ack.pngSha256==64
       and not ack.pngSha256:find('[^0-9a-f]')
       and type(ack.pngPath)=='string'and type(ack.pngRuntimePath)=='string'
       and captureReady and ack.captureNonce==captureReady.nonce
       and ack.ownerPid==captureReady.ownerPid and ack.runtimeMirrorSha256==ack.pngSha256
       and ack.pngRuntimePath==out..'/terminal-case-'..index..'.png'
       and fileSystem:FileExists(ack.pngRuntimePath)
       and(not opts.cases or ack.declaredCaseCount==#cases and ack.caseDataSha256==opts.caseDataSha256)then
       verifyIdle();row.terminalScreenshot=ack;write('report.json',result);advance();return
      end
     end
    end
    assert(g.realTime-terminalStarted<120,'terminal screenshot acknowledgement timeout')
    return
   end
   if stage=='setup'then
    local a=config.actors[setupIndex];local e=actors[setupIndex]
    if not a then
     M.reset(g);row.setupElapsed=setupBudget;row.preparedStarts={}
     if config.group then
      local ids={};for _,actor in ipairs(actors)do ids[#ids+1]=actor.id;row.preparedStarts[#row.preparedStarts+1]=position(actor)end
      local c=config.group
      local accepted=C.execute(g.state,{kind='move',faction=1,ids=ids,x=c.x,y=c.y,lane=c.lane})
      assert(accepted==true,'joint group movement rejected')
      row.groupCommand={accepted=accepted,ids=ids,requested={x=c.x,y=c.y,lane=c.lane},actualExecuteCalls=1}
      for _,actor in ipairs(actors)do
       local order=assert(actor.orders[1],'joint group lacks actual formation goal')
       row.commands[#row.commands+1]={id=actor.id,accepted=accepted,requested={x=c.x,y=c.y,lane=c.lane},
        resolved={x=order.x,y=order.y,lane=order.lane},jointGroup=true}
      end
     else
     for i,actor in ipairs(actors)do
      local c=config.actors[i];row.preparedStarts[#row.preparedStarts+1]=position(actor)
      local accepted=C.execute(g.state,{kind='move',faction=1,ids={actor.id},x=c.tx,y=c.ty,lane=c.targetLane})
      assert(accepted==true,'movement command rejected')
      local order=assert(actor.orders[1],'accepted movement lacks order')
      row.commands[#row.commands+1]={id=actor.id,accepted=accepted,requested={x=c.tx,y=c.ty,lane=c.targetLane},
       resolved={x=order.x,y=order.y,lane=order.lane}}
     end
     end
     g.accumulator=0;g.paused=false;startTime=g.state.time;startVisual=g.realTime
     row.startSimulationTime=startTime;row.startVisualTime=startVisual;stage='record';frame=0;return
    end
    if not a.setupSource then setupIndex=setupIndex+1;return end
    if not row.setupCommands[setupIndex]then
     local accepted=C.execute(g.state,{kind='move',faction=1,ids={e.id},x=a.x,y=a.y,lane=a.lane})
     assert(accepted==true,'setup command rejected');row.setupCommands[setupIndex]={accepted=true};setupBudget=0
    end
    for _=1,20 do if #e.orders==0 then break end;S.step(g.state,D.STEP);setupBudget=setupBudget+D.STEP end
    assert(setupBudget<300,'setup timeout')
    if #e.orders==0 then
     assert(e.vesselLane==a.lane and not e.gastricTransit and(e.x-a.x)^2+(e.y-a.y)^2<.075^2,'actual setup failed')
     setupIndex=setupIndex+1
    end
    return
   end
   if stage=='record'then
    verifyNormalRecording();verifyIdle();for _,e in ipairs(actors)do inspectGate(e)end
    local positions={};local complete=true
    local previous=row.frames[#row.frames]
    for i,e in ipairs(actors)do
     positions[#positions+1]=position(e);if #e.orders>0 then complete=false end
     if previous then local p=previous.positions[i];local distance=math.sqrt((e.x-p.x)^2+(e.y-p.y)^2)
      row.movedDistanceWorld[i]=(row.movedDistanceWorld[i]or 0)+distance
      if distance>1e-8 then row.movementFrames[i]=(row.movementFrames[i]or 0)+1 end
     end
    end
    local ordersComplete=complete;local trafficStats=trafficSnapshot()
    assert(type(trafficStats.activePairs)=='number'and trafficStats.activePairs>=0 and trafficStats.activePairs%1==0,'invalid actual traffic state')
    assert(trafficStats.expired==0,'traffic expiry during normal recording')
    local trafficSettled=trafficStats.activePairs==0;complete=complete and trafficSettled
    row.trafficChecks=(row.trafficChecks or 0)+1;row.latestTrafficStats=trafficStats
    local elapsed=g.state.time-startTime;local visual=g.realTime-startVisual
    assert(type(config.maxTime)=='number'and elapsed<=config.maxTime+1e-9,'original case simulation budget exceeded '..row.id)
    row.originalSimulationBudgetSeconds=config.maxTime
    local f={index=index,total=#cases,id=row.id,stage='record',recording=true,stateRunId=row.stateRunId,
     wallTime=os.time(),visualElapsed=visual,simulationElapsed=elapsed,
     camera={x=g.camera.x,y=g.camera.y},zoom=g.zoom,positions=positions,complete=complete,ordersComplete=ordersComplete,trafficStats=trafficStats,trafficSettled=trafficSettled,
     worldReady=A.ready(R.vg,g.state),uiReady=A.ready(UI.GetNVGContext(),g.state),
     declaredCaseCount=#cases,caseDataSha256=opts.caseDataSha256,actualSpeed=g.speed,actualPaused=g.paused}
    row.frames[#row.frames+1]=f
    if frame%6==0 then write('current.json',f)end
    if complete and visual>=17 then
     row.durationSeconds=visual;row.simulationSeconds=elapsed;row.arrivals={}
     for i,e in ipairs(actors)do local a=config.actors[i];local requested=config.group or{lane=a.targetLane,organId=a.targetOrgan};local goal=row.commands[i].resolved
      assert(goal.lane==requested.lane,'resolved plane differs from requested plane')
      local distance=math.sqrt((e.x-goal.x)^2+(e.y-goal.y)^2);local organ=O.organAt(g.state,e,e.x,e.y)
      local organMatches=requested.lane~=0 or organ==requested.organId
      assert(e.hp>0 and g.state.entities[e.id]==e and distance<=.075 and e.vesselLane==requested.lane
       and not e.gastricTransit and organMatches and O.pointAllowed(g.state,e,e.x,e.y,requested.lane),'invalid arrival '..e.id)
      assert((row.movedDistanceWorld[i]or 0)>0 and(row.movementFrames[i]or 0)>0,'no actual movement '..e.id)
      row.arrivals[#row.arrivals+1]={id=e.id,distanceWorld=distance,laneMatches=true,organMatches=true,organId=organ}
     end
     if row.idleStarts then row.idleArrivals={};for _,e in ipairs(idleActors)do row.idleArrivals[#row.idleArrivals+1]=position(e)end end
     if row.namedGateRetention then assert(row.namedGateRetention.actualAnchorSeenInPath and row.namedGateRetention.actualAnchorReached,'named gate evidence incomplete')end
     assert(trafficSnapshot().activePairs==0 and trafficSnapshot().expired==0,'active or expired traffic remains at accepted arrival')
     row.finalTrafficStats=trafficSnapshot();row.trafficSettled=true
     row.completed=true;g.paused=true;stage='terminal';terminalDraws=draws;terminalStarted=g.realTime
     f.terminal=true;f.terminalReady=false;f.driverArrivalVerified=true;f.goals=row.commands
     terminalFrame=f;write('report.json',result);write('current.json',f)
    elseif visual>timeout then error('normal 1x movement timeout '..row.id)end
   end
  end)
  if not ok then result.errors[#result.errors+1]=tostring(err);finish('driver-error')end
 end)
 write('report.json',result);return result
end
return Q
