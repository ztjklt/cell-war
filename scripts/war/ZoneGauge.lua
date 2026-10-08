-- Campaign zone gauge, ordered like the battlefield: entry first, barrier last.
-- Labels refresh with the HUD tick; the tug bar and alert ring redraw every frame
-- from live zone data. Viruses push from the entry side, immune cells from the barrier side.
-- Tapping a card centers the camera on that zone (actions.select).
local UI=require("urhox-libs/UI")
local T=require("war.UITheme")
local Z={}
---@param z table
---@return number[]
function Z.color(z)
 if z.contested then return T.hud.contested end
 if z.owner==2 then return T.hud.hostile elseif z.owner==1 then return T.hud.friendly end
 return T.hud.neutral
end
---@param z table
---@return string
function Z.status(z)
 if z.contested then return "争夺中" end
 return (z.control>=0 and "免疫 " or "病毒 ")..math.floor(math.abs(z.control)+.5).."%"
end
---@param z table
---@return string
function Z.presence(z)
 if z.friendly==0 and z.hostile==0 then return "无人" end
 return "我 "..z.friendly.." · 敌 "..z.hostile
end
-- Same rule as BrainAdvisor: the barrier is losing control or has viruses inside.
local function danger(ev,i,z) return ev.status=="active" and i==#ev.zones and (z.control<60 or z.hostile>0) end
---@class WarZoneGauge
---@field cards table[]
---@field state {vertical:boolean}
---@field root Widget
---@field header Widget
---@field list Widget
---@field zoomRow Widget
---@field overview Button
---@field home Button
---@field zoomIn Button
---@field zoomOut Button

---@param g table
---@param actions table
---@return WarZoneGauge
function Z.create(g,actions)
 ---@type {vertical:boolean}
 local state={vertical=true}
 local refs={cards={},state=state}
 local function tool(text,fn) return T.button(text,fn,nil,false,{flexShrink=0,paddingHorizontal=2}) end
 refs.overview=tool("气管图",actions.overview);refs.home=tool("回营",actions.home)
 refs.zoomIn=tool("＋",actions.zoomIn);refs.zoomOut=tool("－",actions.zoomOut)
 refs.zoomRow=UI.Panel{flexDirection="row",gap=4,pointerEvents="box-none",children={refs.zoomIn,refs.zoomOut}}
 refs.header=UI.Panel{gap=4,pointerEvents="box-none",children={refs.overview,refs.home,refs.zoomRow}}
 refs.list=UI.Panel{gap=6,pointerEvents="box-none"}
 for i=1,3 do
  local name=T.label("",12,T.paper,{lineHeight=1.1})
  local status=T.label("",12,T.hud.friendly,{lineHeight=1.1})
  local presence=T.label("",11,T.muted,{lineHeight=1.1})
  local card=T.hudPanel{paddingVertical=4,paddingLeft=8,paddingRight=14,gap=1,borderRadius=12,
   justifyContent="center",children={name,status,presence},onTap=function() actions.select(i) end}
  local base=card.Render
  ---@param vg NVGContextWrapper
  function card:Render(vg)
   base(self,vg)
   local c=g.state.campaign;local ev=c and c.event;local z=ev and ev.zones[i]
   if not z then return end
   local l=self:GetAbsoluteLayout();if l.w<=0 or l.h<=0 then return end
   local f=math.max(0,math.min(1,(z.control+100)/200))
   local bad,good=T.hud.hostile,T.hud.friendly
   nvgSave(vg)
   nvgBeginPath(vg)
   if state.vertical then nvgRoundedRect(vg,l.x+l.w-9,l.y+6,4,l.h-12,2) else nvgRoundedRect(vg,l.x+8,l.y+l.h-6,l.w-16,3,1.5) end
   nvgFillColor(vg,nvgRGBA(bad[1],bad[2],bad[3],190));nvgFill(vg)
   local span=state.vertical and (l.h-12)*f or (l.w-16)*f
   if span>.5 then
    nvgBeginPath(vg)
    if state.vertical then nvgRoundedRect(vg,l.x+l.w-9,l.y+l.h-6-span,4,span,2)
    else nvgRoundedRect(vg,l.x+l.w-8-span,l.y+l.h-6,span,3,1.5) end
    nvgFillColor(vg,nvgRGBA(good[1],good[2],good[3],235));nvgFill(vg)
   end
   ---@type number[]?
   local warn=nil
   if z.contested then warn=T.hud.contested elseif danger(ev,i,z) then warn=bad end
   if warn then
    local alpha=math.floor(120+90*math.sin((g.realTime or 0)*6))
    nvgBeginPath(vg);nvgRoundedRect(vg,l.x+1,l.y+1,l.w-2,l.h-2,11)
    nvgStrokeWidth(vg,2);nvgStrokeColor(vg,nvgRGBA(warn[1] or 0,warn[2] or 0,warn[3] or 0,alpha));nvgStroke(vg)
   end
   nvgRestore(vg)
  end
  refs.cards[i]={card=card,name=name,status=status,presence=presence,last={}}
  refs.list:AddChild(card)
 end
 refs.root=UI.Panel{position="absolute",gap=6,pointerEvents="box-none",children={refs.header,refs.list}}
 return refs --[[@as WarZoneGauge]]
end
-- L: UIModel.battle layout; mouse: show +/- (touch zooms with two fingers).
---@param refs WarZoneGauge
---@param L table
---@param mouse boolean
---@param overviewText string
---@param showTools boolean camera tools on top of the gauge (false when they sit in the status bar)
function Z.layout(refs,L,mouse,overviewText,showTools)
 local r=L.gauge;local vertical=r.vertical;refs.state.vertical=vertical
 local pt=L.pt;local h=L.header;local gap=L.gap
 refs.root:SetStyle{left=r.x,top=r.y,width=r.w,height=r.h,flexDirection=vertical and "column" or "row",gap=gap}
 refs.header:SetStyle{flexDirection=vertical and "column" or "row",gap=gap,width=vertical and r.w or "auto",alignItems="stretch"}
 refs.overview:SetText(overviewText)
 for _,b in ipairs({refs.overview,refs.home}) do b:SetStyle{height=h,width=vertical and r.w or pt(58),fontSize=pt(12)} end
 for _,b in ipairs({refs.zoomIn,refs.zoomOut}) do b:SetStyle{height=h,width=vertical and (r.w-gap)/2 or pt(36),fontSize=pt(14)} end
 refs.header:SetVisible(showTools);refs.zoomRow:SetVisible(mouse)
 local tools=showTools and (mouse and 3 or 2) or 0
 local listH=vertical and r.h-(h*tools+gap*tools) or r.h
 local cardH=vertical and math.min(pt(92),(listH-gap*2)/3) or r.h
 refs.list:SetStyle{flexDirection=vertical and "column" or "row",gap=gap,flexGrow=1,flexBasis=0}
 for _,e in ipairs(refs.cards) do
  e.card:SetStyle{height=cardH,width=vertical and r.w or "auto",flexGrow=vertical and 0 or 1,flexBasis=vertical and "auto" or 0,
   paddingLeft=pt(8),paddingRight=vertical and pt(13) or pt(8),paddingVertical=pt(3)}
  e.name:SetStyle{fontSize=pt(L.phone and 11 or 12)};e.status:SetStyle{fontSize=pt(11)};e.presence:SetStyle{fontSize=pt(10)}
 end
end
local function set(entry,key,label,text,color)
 local last=entry.last
 if last[key]~=text then last[key]=text;label:SetText(text) end
 if color and last[key.."c"]~=color then last[key.."c"]=color;label:SetStyle{fontColor=color} end
end
---@param refs WarZoneGauge
---@param g table
---@param N table campaign geometry (zone names)
function Z.update(refs,g,N)
 local ev=g.state.campaign.event
 for i,e in ipairs(refs.cards) do
  local z,def=ev.zones[i],N.zones[i]
  if z and def then
   local c=Z.color(z)
   set(e,"name",e.name,def.name)
   set(e,"status",e.status,Z.status(z),z.contested and T.hud.contested or z.control>=0 and T.hud.friendly or T.hud.hostile)
   set(e,"presence",e.presence,Z.presence(z))
   if e.last.border~=c then e.last.border=c;e.card:SetStyle{borderColor={c[1],c[2],c[3],150}} end
  end
 end
end
return Z
