-- Temporary read-only observer for the explicitly requested native mouse test.
local Q={}
---@type Node|nil
local node=nil
---@type LuaScriptObject|nil
local receiver=nil
---@param g any
---@param R any
function Q.start(g,R)
 local last=-1
 _RedCellNativeObservationEvents=ScriptObject()
 node=Node();receiver=node:CreateScriptObject('_RedCellNativeObservationEvents')
 receiver:SubscribeToEvent('Update',function()
  if g.realTime-last<.5 then return end;last=g.realTime
  local units={}
  for _,e in pairs(g.state.entities)do
   if e.faction==1 and e.kind=='worker'then
    local x,y=R.project(g,e.x,e.y)
    units[#units+1]={id=e.id,x=e.x,y=e.y,lane=e.vesselLane,hp=e.hp,
     selected=g.selection[e.id]==true,orders=e.orders,screenX=x,screenY=y,
     pathFailed=e.pathFailed,routeReason=e.gastricRouteReason,transit=e.gastricTransit}
   end
  end
  local mouse=input:GetMousePosition()
  local row={time=g.state.time,tick=g.state.tick,zoom=g.zoom,camera=g.camera,
   paused=g.paused,width=R.w,height=R.h,dpr=graphics:GetDPR(),cells=units,
   mouseX=mouse.x,mouseY=mouse.y,drag=g.drag,selectionCount=#require('war.Input').ids(g)}
  print('[RedCellNativeObservation] '..cjson.encode(row))
 end)
end
return Q
