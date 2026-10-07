-- Native UrhoX equivalents of React Bits spotlight/entrance and Magic UI counters.
-- Visual values only: commands always read the simulation's actual stock.
local UI=require("urhox-libs/UI")
local F={}
function F.enter(widget,offset)
 widget:Animate{keyframes={[0]={opacity=0,translateY=offset or 12},[1]={opacity=1,translateY=0}},duration=.36,easing="easeOut",fillMode="forwards"}
end
function F.counter(H,key,label,target)
 H.uiCounters=H.uiCounters or {}
 local item=H.uiCounters[key]
 if not item then
  H.uiCounters[key]={label=label,value=target,from=target,target=target,time=.28,last=target}
  label:SetText(tostring(target));return
 end
 item.label=label
 if item.target~=target then
  item.from=item.value;item.target=target;item.time=0
  if target==0 then item.value=0;item.time=.28;item.last=0;label:SetText("0") end
 end
end
function F.update(H,dt)
 for _,item in pairs(H.uiCounters or {}) do
  if item.time<.28 then
   item.time=math.min(.28,item.time+math.max(0,dt))
   local ease=1-(1-item.time/.28)^3
   item.value=item.from+(item.target-item.from)*ease
   local value=math.floor(item.value+.5)
   if value~=item.last then item.label:SetText(tostring(value));item.last=value end
  end
 end
end
-- Decorate the native render method; retain its hit target and child rendering.
-- No allocated images/fonts or extra UI trees per frame.
function F.spotlight(widget,dark)
 local base=widget.Render
 ---@param vg NVGContextWrapper
 function widget:Render(vg)
  if base then base(self,vg) elseif self.RenderFullBackground then self:RenderFullBackground(vg) end
  if self.props.disabled or not input or not input.GetMousePosition then return end
  local l=self:GetAbsoluteLayout();if l.w<=0 or l.h<=0 then return end
  local mouse=input:GetMousePosition();local scale=UI.GetScale()
  local x,y=mouse.x/scale,mouse.y/scale
  if x<l.x or y<l.y or x>l.x+l.w or y>l.y+l.h then return end
  nvgSave(vg)
  nvgIntersectScissor(vg,l.x,l.y,l.w,l.h)
  nvgBeginPath(vg);nvgRoundedRect(vg,l.x,l.y,l.w,l.h,self.props.borderRadius or 14)
  local paint=nvgRadialGradient(vg,x,y,0,math.max(60,math.min(150,l.w)),
   dark and nvgRGBA(164,215,255,25) or nvgRGBA(122,177,246,35),nvgRGBA(122,177,246,0))
  nvgFillPaint(vg,paint);nvgFill(vg);nvgRestore(vg)
 end
 return widget
end
return F
