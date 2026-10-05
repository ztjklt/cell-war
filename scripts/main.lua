-- Based on the official templates/scaffold-2d.lua lifecycle.
-- Standalone RTS: Lua simulation + NanoVG world + urhox-libs/UI widgets.
local UI=require("urhox-libs/UI")
local Sim=require("war.Simulation")
local D=require("war.Data")
local Motion=require("war.Motion")
local R,H,I,Save,Audio=require("war.Render"),require("war.HUD"),require("war.Input"),require("war.Save"),require("war.Audio")
local game={state={},selection={},groups={{},{},{}},camera={x=D.factions[1].x,y=D.factions[1].y},zoom=1,started=false,paused=false,speed=1,accumulator=0,realTime=0,pointer={wx=D.factions[1].x,wy=D.factions[1].y},box=false,append=false,placement=false,mode=false,tab=false,modal=false,fps=0,frameCount=0,frameTime=0}
function Start()
 engine.maxFps=60;engine.maxInactiveFps=30
 graphics.windowTitle="细胞战争"
 input.mouseMode=MM_ABSOLUTE
 game.state=Sim.new(math.floor(os.time()%2000000000))
 Motion.reset(game)
 game.newGame=function() game.state=Sim.new(math.floor(os.time()%2000000000));game.selection={};game.groups={{},{},{}};game.camera={x=D.factions[1].x,y=D.factions[1].y};game.started=true;game.paused=false;game.defeatShown=false;game.accumulator=0;H.sidebar(game) end
 game.replaceState=function(state) game.state=state;game.selection={};game.groups={{},{},{}};game.accumulator=0;game.started=true;game.defeatShown=false;R.home(game);H.refs.menu:SetVisible(false) end
 R.init();H.create(game);Audio.init();game.audio=Audio.play;Audio.play("ambient")
 SubscribeToEvent(R.vg,"NanoVGRender","HandleWorldRender")
 SubscribeToEvent("Update","HandleUpdate")
 SubscribeToEvent("KeyDown","HandleKeyDown")
 SubscribeToEvent("MouseWheel","HandleWheel")
 print("[细胞战争] READY | world=body | map=1024 | biomes=16 | controllable=cells | factions=3 | fixedStep=0.1")
end
function Stop() Audio.stop();R.close();UI.Shutdown() end
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
  while game.accumulator>=D.STEP and steps<8 do Motion.capture(game);Sim.step(game.state,D.STEP);game.accumulator=game.accumulator-D.STEP;steps=steps+1 end
  if game.state.needsAutosave then game.state.needsAutosave=false;Save.write(game.state,0) end
 end
 if game.motionState~=game.state then Motion.reset(game) end
 game.flowTime=Motion.time(game)
 if game.marker and game.realTime%10<.1 then game.marker=false end
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
