-- Based on the official templates/scaffold-2d.lua lifecycle.
-- Standalone RTS: Lua simulation + NanoVG world + urhox-libs/UI widgets.
local UI=require("urhox-libs/UI")
local Sim=require("war.Simulation")
local D=require("war.Data")
local Motion=require("war.Motion")
local R,H,I,Save,Audio=require("war.Render"),require("war.HUD"),require("war.Input"),require("war.Save"),require("war.Audio")
local game={state={},selection={},groups={{},{},{}},camera={x=D.factions[1].x,y=D.factions[1].y},zoom=1,started=false,paused=false,fogDisabled=false,speed=1,accumulator=0,realTime=0,pointer={wx=D.factions[1].x,wy=D.factions[1].y},box=false,append=false,placement=false,mode=false,tab=false,modal=false,fps=0,frameCount=0,frameTime=0}
function Start()
 engine.maxFps=60;engine.maxInactiveFps=30
 graphics.windowTitle="细胞战争"
 input.mouseMode=MM_ABSOLUTE
 game.state=Sim.new(math.floor(os.time()%2000000000))
 Motion.reset(game)
 game.newGame=function(mode) mode=mode or (game.state.campaign and "campaign" or "sandbox");assert(mode=="campaign" or mode=="sandbox","未知游戏模式");game.vesselSurvey=false;game.state=Sim.new(math.floor(os.time()%2000000000),mode);R.prepare(game.state);game.selection={};game.groups={{},{},{}};game.camera={x=D.factions[1].x,y=D.factions[1].y};game.zoom=1;game.started=true;game.paused=false;game.defeatShown=false;game.victoryShown=false;game.accumulator=0;game.mode=false;game.placement=false;game.tab=false;H.lastLayout="";H.sidebar(game);R.home(game) end
 game.replaceState=function(state) game.vesselSurvey=false;game.state=state;R.prepare(game.state);game.selection={};game.groups={{},{},{}};game.accumulator=0;game.started=true;game.paused=false;game.defeatShown=false;game.victoryShown=false;game.mode=false;game.placement=false;game.tab=false;H.lastLayout="";H.sidebar(game);R.home(game);H.refs.menu:SetVisible(false) end
 R.init();R.prepare(game.state);H.create(game);R.home(game);Audio.init();game.audio=Audio.play;Audio.play("ambient")
 SubscribeToEvent(R.vg,"NanoVGRender","HandleWorldRender")
 SubscribeToEvent("Update","HandleUpdate")
 SubscribeToEvent("KeyDown","HandleKeyDown")
 SubscribeToEvent("MouseWheel","HandleWheel")
 print("[细胞战争] READY | view=topdown2d | world=body | map=2048x4096 | vessels=12 | walls=sealed | mode=campaign | event=nasal | nasalTerrain=2 | zones=3 | controllable=cells | fixedStep=0.1")
end
function Stop() Audio.stop();require("war.Cells").release(UI.GetNVGContext());require("war.UIArt").release(UI.GetNVGContext());require("war.OrganArt").release(UI.GetNVGContext());require("war.BrainRig").release(UI.GetNVGContext());R.close();UI.Shutdown() end
---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType,eventData)
 local dt=math.min(.25,eventData:GetFloat("TimeStep"));game.realTime=game.realTime+dt
 game.frameCount=game.frameCount+1;game.frameTime=game.frameTime+dt
 if game.frameTime>=1 then game.fps=math.floor(game.frameCount/game.frameTime);game.frameTime=0;game.frameCount=0 end
 I.update(game,dt);Save.update(dt)
 if game.started and not game.paused and not game.modal then
  game.accumulator=math.min(game.accumulator+dt*game.speed,1)
  local steps=0
  local deadline=os.clock()+.006
  -- Carry unfinished fixed steps to the next frame instead of a long catch-up burst.
  while game.accumulator>=D.STEP and steps<8 and (steps==0 or os.clock()<deadline) do Motion.capture(game);Sim.step(game.state,D.STEP);game.accumulator=game.accumulator-D.STEP;steps=steps+1 end
  if game.state.needsAutosave then game.state.needsAutosave=false;Save.write(game.state,0) end
 end
 if game.motionState~=game.state then Motion.reset(game) end
 game.flowTime=Motion.time(game)
 if game.marker and game.realTime-(game.marker.born or 0)>.9 then game.marker=false end
 H.update(game,dt)
end
function HandleWorldRender() R.draw(game) end
---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType,eventData) I.key(game,eventData:GetInt("Key")) end
function HandleWheel(eventType,eventData)
 if game.started and not game.modal then
  local p=input:GetMousePosition();local dpr=graphics:GetDPR();local x,y=p.x/dpr,p.y/dpr
  local widget=UI.GetHoveredWidget()
  if not widget or widget.props.id=="worldInput" then R.zoom(game,1.12^eventData:GetInt("Wheel"),x,y) end
 end
end
