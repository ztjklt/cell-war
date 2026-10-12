-- Explicit native heart gameplay QA. Not loaded by main or normal gameplay.
-- Fixture spawn is the only initial placement. Every recorded passage uses
-- Commands and the unmodified main Update loop at speed 1; no manual step/time.
local Q={}
---@type Node|nil
local ownerNode=nil
---@type LuaScriptObject|nil
local receiver=nil
local cases={
 {id='tricuspid',kind='move',from={497,382,203},to={499,426,204},passage=207,maxSeconds=80},
 {id='pulmonary',kind='move',from={499,426,204},to={510,355,2},passage=208,maxSeconds=100},
 {id='mitral',kind='move',from={538,382,205},to={536,426,206},passage=209,maxSeconds=80},
 {id='aortic',kind='move',from={536,426,206},to={533,375,150},passage=210,maxSeconds=100},
 {id='systemic_return',kind='move',from={483,379,1},to={497,382,203},passage=1,maxSeconds=60},
 {id='pulmonary_return_l',kind='move',from={545,414,8},to={538,382,205},passage=8,maxSeconds=100},
 {id='four_chamber_combat',kind='combat',maxSeconds=12},
 {id='septum_negative',kind='negative',maxSeconds=12},
}
Q.cases=cases
function Q.start(g,R,HUD,options)
 assert(not receiver,'HeartNativeGameplay already owns an Update receiver')
 local opts=options or{};local out=opts.outputDir or'qa/heart-native/gameplay-v1-001'
 local cases={}
 for _,case in ipairs(Q.cases)do
  if not opts.caseIds or opts.caseIds[case.id]then cases[#cases+1]=case end
 end
 assert(#cases>0,'native gameplay case selection is empty')
 local F,C,W,O,H,M,A,T,UI=require('war.FullBodyBattlefield'),require('war.Commands'),require('war.World'),
  require('war.OrganBattlefield'),require('war.HeartBattlefield'),require('war.Motion'),require('war.FullBodyMapArt'),
  require('war.HeartDisplayTransform'),require('urhox-libs/UI')
 for _,p in ipairs({'qa','qa/heart-native',out})do assert(fileSystem:DirExists(p)or fileSystem:CreateDir(p),p)end
 local function write(name,value)
  local f=File(out..'/'..name,FILE_WRITE);assert(f and f:IsOpen(),'native QA report unavailable: '..name)
  f:WriteString(cjson.encode(value));f:Close()
 end
 local result={schema='heart-native-gameplay/v1',runId=tostring(os.time())..'-'..tostring(GetTime():GetFrameNumber()),
  outputDir=out,cases={},errors={},speed=1,timeCompression=1,manualSimulationSteps=0,
  recordingUsesNormalMainLoop=true,nativeEvidence=true,completed=false,finished=false,
  manifestSha256=require('war.FullBodyMapArtData').manifestSha256,
  geometrySha256=H.data.geometrySha256,dpr=graphics:GetDPR(),physicalWidth=graphics:GetWidth(),physicalHeight=graphics:GetHeight()}
 if opts.startMode~='current'then g.replaceState(F.new(opts.seed or 73))end
 assert(F.enabled(g.state),'native gameplay QA requires the real fullbody state')
 g.paused=true;g.speed=1;g.fogDisabled=true;g.selection={};g.zoom=opts.zoom or .15
 if HUD.closeModal then HUD.closeModal(g)end
 graphics:Raise();write('ack.json',{schema='heart-gameplay-ack/v1',runId=result.runId,index=0,stage='unused'})
 local index,stage,frame,draws,startDraws,startTime,startVisual,writeTime=0,'new',0,0,0,0,0,0
 local actors={};local finished=false;local oldRecord=M.record
 ---@type table|nil
 local row=nil
 local function coords(e)
  local x,y=T.displayPosition(g,e)
  return{id=e.id,kind=e.kind,faction=e.faction,x=e.x,y=e.y,source={e.x*.5,(e.y-512)*.5},lane=e.vesselLane,
   displayWorld={x=x,y=y},hp=e.hp,orders=#e.orders,simulationTime=g.state.time,tick=g.state.tick}
 end
 local function positions()
  local v={};for _,e in ipairs(actors)do v[#v+1]=coords(e)end;return v
 end
 local function current(terminal)
  local v={schema='heart-native-gameplay-current/v1',runId=result.runId,index=index,total=#cases,id=row and row.id,
   stage=stage,recording=stage=='record',finished=finished,wallTime=os.time(),simulationTime=g.state.time,tick=g.state.tick,
   speed=g.speed,simulationElapsed=g.state.time-startTime,visualElapsed=g.realTime-startVisual,
   coords=positions(),passageVisited=row and row.passageVisited or{},chamberHp=row and row.chamberHp or{},negative=row and row.negative,
   camera={x=g.camera.x,y=g.camera.y},zoom=g.zoom,draws=draws,terminalReady=terminal and draws-startDraws>=2 or false,
   driverArrivalVerified=row and row.completed or false,manifestSha256=result.manifestSha256}
  write('current.json',v);return v
 end
 local function ack(expected)
  if not fileSystem:FileExists(out..'/ack.json')then return nil end
  local f=File(out..'/ack.json',FILE_READ);if not f or not f:IsOpen()then return nil end
  local raw=f:ReadLine();f:Close();local ok,v=pcall(cjson.decode,raw)
  if ok and type(v)=='table'and v.schema=='heart-gameplay-ack/v1'and v.runId==result.runId
   and v.index==index and v.stage==expected then return v end
 end
 local function captureRecord(e)
  oldRecord(e)
  if stage~='record'or not row or not row.actorIds[tostring(e.id)]then return end
  row.passageVisited[tostring(e.vesselLane)]=true
  local previous=row.trace[#row.trace]
  if not previous or previous.id~=e.id or previous.x~=e.x or previous.y~=e.y or previous.lane~=e.vesselLane then
   row.trace[#row.trace+1]={id=e.id,x=e.x,y=e.y,lane=e.vesselLane,hp=e.hp,time=g.state.time,tick=g.state.tick}
  end
 end
 M.record=captureRecord
 _HeartNativeGameplayEvents=ScriptObject()
 ownerNode=Node();receiver=ownerNode:CreateScriptObject('_HeartNativeGameplayEvents')
 assert(receiver,'native gameplay event receiver unavailable')
 local function finish(reason)
  if finished then return end;finished=true;stage='finished';M.record=oldRecord;g.paused=true
  result.finished=true;result.completed=reason=='all-cases';result.reason=reason
  result.passed=0;for _,v in ipairs(result.cases)do if v.completed then result.passed=result.passed+1 end end
  result.total=#cases;result.finalSimulationTime=g.state.time;result.finalTick=g.state.tick
  if receiver then receiver:UnsubscribeFromAllEvents()end;receiver=nil;ownerNode=nil
  write('report.json',result);current(false);print('[HeartNativeGameplay] FINISHED '..reason..' '..result.passed..'/'..#cases)
 end
 Q.stop=function()finish('cancelled')end
 local function spawn(kind,faction,source,lane)
  local e=assert(C.spawn(g.state,'unit',kind,faction,source[1]*2,source[2]*2+512),'fixture spawn rejected')
  assert(math.abs(e.x-source[1]*2)+math.abs(e.y-source[2]*2-512)<1e-6,'fixture point was relocated')
  -- An explicitly tagged initial blood volume may share the same projection
  -- with another volume. No recorded position/lane is assigned after this.
  e.vesselLane=lane;assert(O.pointAllowed(g.state,e,e.x,e.y,lane),'fixture volume invalid')
  actors[#actors+1]=e;row.actorIds[tostring(e.id)]=true;row.starts[#row.starts+1]=coords(e);return e
 end
 local function resetFixtures()
  g.paused=true;g.accumulator=0;g.selection={};g.state.entities={};g.state.commands={};g.state.effects={}
  require('war.OrganTraffic').reset(g.state);require('war.Path').reset();W.rebuild(g.state);actors={}
 end
 local function advance()
  if index>=#cases then finish('all-cases');return end;index=index+1
  resetFixtures();local config=cases[index];stage='ready';frame=0;startDraws=draws
  row={id=config.id,index=index,kind=config.kind,expectedPassage=config.passage,starts={},trace={},commands={},
   actorIds={},passageVisited={},chamberHp={},frames=0,completed=false,fixturePlaneTagsBeforeRecording=true}
  result.cases[#result.cases+1]=row
  if config.kind=='move'then
   spawn('scout',1,config.from,config.from[3]);g.selection[actors[1].id]=true
   g.camera={x=(config.from[1]+config.to[1]),y=(config.from[2]+config.to[2])+512}
  elseif config.kind=='combat'then
   for _,c in ipairs(H.data.chambers)do
    local a=spawn('siege',1,c.centerSource,c.laneIndex)
    local b=spawn('virus',0,{c.centerSource[1]+1.25,c.centerSource[2]},c.laneIndex)
    row.chamberHp[c.id]={targetId=b.id,attackerId=a.id,before=b.hp,after=b.hp,damage=0};g.selection[a.id]=true
   end
   g.camera={x=1036,y=1334}
  else
   local a=spawn('siege',1,{522.0149020570162,449.7082166306879},204)
   local b=spawn('virus',0,{524.4432717476649,448.1353226323538},206)
   row.negative={targetId=b.id,attackerId=a.id,before=b.hp,after=b.hp,attackerBefore=a.hp,attackerAfter=a.hp,
    ventricularSweepBlocked=not O.sweep(g.state,a,a.x,a.y,b.x,b.y,204,206),
    atrialSweepBlocked=not O.sweep(g.state,a,497*2,382*2+512,538*2,382*2+512,203,205),
    attackInRange=math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)<9,
    lineOfFireBlocked=H.combatClear(g.state,a,b)==false}
   g.camera={x=1046.5,y=1409.5};g.selection[a.id]=true
  end
  W.rebuild(g.state);W.fog(g.state);M.reset(g);HUD.sidebar(g)
  startTime,startVisual=g.state.time,g.realTime;current(false);write('report.json',result)
  print('[HeartNativeGameplay] READY '..index..' '..config.id)
 end
 local function begin()
  local config=cases[index];local armed=assert(ack('arm'));row.armAck=armed
  if config.kind=='move'then
   local t=config.to;local accepted=C.execute(g.state,{kind='move',faction=1,ids={actors[1].id},x=t[1]*2,y=t[2]*2+512,lane=t[3]})
   assert(accepted,'native move rejected');local o=assert(actors[1].orders[1]);row.goal={x=o.x,y=o.y,lane=o.lane}
   row.commands[1]={kind='move',accepted=true,id=actors[1].id,goal=row.goal}
  elseif config.kind=='combat'then
   for _,p in pairs(row.chamberHp)do
    local accepted=C.execute(g.state,{kind='attack',faction=1,ids={p.attackerId},target=p.targetId})
    assert(accepted,'native chamber attack rejected');row.commands[#row.commands+1]={kind='attack',accepted=true,id=p.attackerId,target=p.targetId}
   end
  else
   local p=row.negative;local accepted=C.execute(g.state,{kind='attack',faction=1,ids={p.attackerId},target=p.targetId})
   assert(accepted,'native septum attack rejected');row.commands[1]={kind='attack',accepted=true,id=p.attackerId,target=p.targetId}
  end
  startTime,startVisual=g.state.time,g.realTime;g.accumulator=0;g.paused=false;stage='record';frame=0
  for _,e in ipairs(actors)do captureRecord(e)end
  current(false);write('report.json',result);print('[HeartNativeGameplay] RECORD '..index..' '..config.id)
 end
 local function terminal()
  row.completed=true;row.simulationSeconds=g.state.time-startTime;row.wallVisualSeconds=g.realTime-startVisual
  row.ends=positions();g.paused=true;stage='terminal';startDraws=draws;startVisual=g.realTime
  write('report.json',result);current(true);print('[HeartNativeGameplay] TERMINAL '..index..' '..row.id)
 end
 receiver:SubscribeToEvent('NanoVGRender',function()draws=draws+1 end)
 receiver:SubscribeToEvent('Update',function(_,_,event)
  local ok,err=pcall(function()
   frame=frame+1
   if stage=='new'then advance();return end
   assert(g.speed==1,'speed changed during normal 1x native QA')
   if stage=='ready'then
    if frame%6==0 then current(false)end
    if draws-startDraws>=2 and A.ready(R.vg,g.state)and A.ready(UI.GetNVGContext(),g.state)and ack('arm')then begin()end
    assert(g.realTime-startVisual<120,'native capture arm timeout');return
   end
   if stage=='terminal'then
    local state=current(true);local v=ack('terminal')
    if state.terminalReady and v then row.terminalAck=v;write('report.json',result);advance();return end
    assert(g.realTime-startVisual<120,'terminal capture ack timeout');return
   end
   if stage~='record'then return end
   local config=cases[index];row.frames=row.frames+1
   row.lastTimeStep=event and event:GetFloat('TimeStep')or nil
   row.actualCoords=positions();local elapsed=g.state.time-startTime
   if config.kind=='move'then
    local e=actors[1];local goal=row.goal;local distance=math.sqrt((e.x-goal.x)^2+(e.y-goal.y)^2)
    local previous=row.previousFrame;row.previousFrame={x=e.x,y=e.y}
    if previous then row.movedDistanceWorld=(row.movedDistanceWorld or 0)+math.sqrt((e.x-previous.x)^2+(e.y-previous.y)^2)end
    assert(O.pointAllowed(g.state,e,e.x,e.y,e.vesselLane),'native move left its volume')
    if #e.orders==0 and elapsed>.2 then
     assert(distance<.075 and e.vesselLane==goal.lane and e.hp>0,'native exact arrival invalid')
     assert(row.passageVisited[tostring(config.passage)],'native route missed named passage')
     assert((row.movedDistanceWorld or 0)>0,'native route has no movement')
     row.arrival={distanceWorld=distance,lane=e.vesselLane,passage=config.passage,passageVisited=true};terminal();return
    end
   elseif config.kind=='combat'then
    for _,p in pairs(row.chamberHp)do local e=g.state.entities[p.targetId];p.after=e and e.hp or 0;p.damage=p.before-p.after end
    if elapsed>=2 then
     for _,p in pairs(row.chamberHp)do assert(p.damage>0,'native chamber combat did not damage target')end
     terminal();return
    end
   else
    local p=row.negative;local a,b=g.state.entities[p.attackerId],g.state.entities[p.targetId]
    p.after=b and b.hp or 0;p.attackerAfter=a and a.hp or 0
    if elapsed>=2 then
     assert(p.ventricularSweepBlocked and p.atrialSweepBlocked and p.attackInRange and p.lineOfFireBlocked,'invalid septum test')
     assert(p.after==p.before and p.attackerAfter==p.attackerBefore,'native attack crossed a septal wall')
     terminal();return
    end
   end
   if g.realTime-writeTime>=.15 then writeTime=g.realTime;current(false)end
   assert(g.realTime-startVisual<config.maxSeconds,'native normal 1x timeout '..config.id)
  end)
  if not ok then result.errors[#result.errors+1]=tostring(err);finish('driver-error')end
 end)
 write('report.json',result);write('current.json',{schema='heart-native-gameplay-current/v1',runId=result.runId,stage='new',index=0,finished=false})
 print('[HeartNativeGameplay] START cases='..#cases..' normal=1x');return result
end
return Q
