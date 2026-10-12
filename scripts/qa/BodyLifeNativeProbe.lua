-- Opt-in local diagnostic. Not loaded by normal gameplay.
-- Capture the actual framebuffer after rendering, without desktop automation.
local P={}
function P.start(game,output)
 local frames=0
 local R=require('war.Render')
 local B=require('war.BodyLife')
 local originalDraw=R.draw
 -- Exercise native bindings behind the opaque startup menu. No game state is changed.
 R.draw=function(g)
  originalDraw(g)
  if frames<65 or frames>155 then return end
  local ok,err=pcall(function()
   local zoom=frames<95 and .013 or frames<125 and .04 or .1
   local view={zoom=zoom,camera={x=1024,y=1270},realTime=.13}
   nvgBeginFrame(R.vg,R.w,R.h,graphics:GetDPR())
   B.draw(R,view,g.state,0,2048,0,4096)
   nvgEndFrame(R.vg)
   if frames==70 or frames==100 or frames==130 then
    print('[BodyLifeNativeProbe] native draw zoom='..zoom..' organs='..B.last.organs..' triangles='..B.last.triangles)
   end
  end)
  if not ok then R.draw=originalDraw;print('[BodyLifeNativeProbe] draw failed: '..tostring(err)) end
 end
 local function capture(label)
  local image=Image()
  local captured=graphics:TakeScreenShot(image)
  local saved=captured and image:SavePNG(output:gsub('%.png$','-'..label..'.png'))
  print('[BodyLifeNativeProbe] '..label..' captured='..tostring(captured)..' saved='..tostring(saved))
 end
 local updateFrames,endFrames=0,0
 function BodyLifeNativeUpdateCapture()
  updateFrames=updateFrames+1
  if updateFrames==60 then capture('Update') end
 end
 function BodyLifeNativeEndCapture()
  endFrames=endFrames+1
  if endFrames==60 then capture('EndFrame') end
 end
 function BodyLifeNativeCapture()
  frames=frames+1
  if frames==160 then R.draw=originalDraw end
  if frames~=60 then return end
  local ok,err=pcall(function()
   capture('EndRendering')
   local world=B.prepare(R.vg)
   local ui=B.prepare(require('urhox-libs/UI').GetNVGContext())
   print('[BodyLifeNativeProbe] anatomy='..tostring(game.state.anatomyVersion)..
    ' started='..tostring(game.started)..' zoom='..tostring(game.zoom)..
    ' transform='..type(nvgTransform)..' antiAlias='..type(nvgShapeAntiAlias)..
    ' worldImage='..tostring(world)..' uiImage='..tostring(ui))
  end)
  if not ok then print('[BodyLifeNativeProbe] '..tostring(err)) end
 end
 SubscribeToEvent('EndRendering','BodyLifeNativeCapture')
 SubscribeToEvent('Update','BodyLifeNativeUpdateCapture')
 SubscribeToEvent('EndFrame','BodyLifeNativeEndCapture')
end
return P
