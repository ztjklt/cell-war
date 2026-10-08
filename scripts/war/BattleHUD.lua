-- Campaign battle HUD: slim status bar on top, zone gauge on the right edge,
-- unit selection in the bottom-left thumb zone, orders and reinforcement in the
-- bottom-right thumb zone; the battlefield keeps the free middle (UIModel.battle).
-- Reads live state; changes the game only through Input / Commands / Render camera.
local UI=require("urhox-libs/UI")
local T,M,FX=require("war.UITheme"),require("war.UIModel"),require("war.UIMotion")
local I,C,U,D=require("war.Input"),require("war.Commands"),require("war.Util"),require("war.Data")
local R,Z=require("war.Render"),require("war.ZoneGauge")
local CampaignData,Reinforce=require("war.CampaignData"),require("war.Reinforcements")
local Platform=require("urhox-libs.Platform.PlatformUtils")
local B={}
local label=T.label
local function rect(widget,r) widget:SetStyle{left=r.x,top=r.y,width=r.w,height=r.h} end
local function clock(seconds)
 local s=math.max(0,math.ceil(seconds));return string.format("%d:%02d",math.floor(s/60),s%60)
end
-- Button whose content is labels, so the text color can follow the button tone.
local function richButton(fn,accent,parts,props)
 local p={flexDirection="row",justifyContent="center",alignItems="center",gap=4,paddingHorizontal=4,children=parts}
 for k,v in pairs(props or {}) do p[k]=v end
 return T.button(nil,fn,nil,accent,p)
end
-- tone: "normal" | "armed" | "disabled"; accent buttons keep their gradient when enabled.
local function setTone(entry,tone)
 if entry.tone==tone then return end
 entry.tone=tone;entry.button:SetDisabled(tone=="disabled")
 if not entry.accent then T.tone(entry.button,tone=="armed") end
 local color=tone=="disabled" and T.quiet or (tone=="armed" or entry.accent) and T.hud.onAccent or T.paper
 for _,l in ipairs(entry.labels or {}) do l:SetStyle{fontColor=color} end
end
local function setText(entry,key,widget,text)
 entry.last=entry.last or {}
 if entry.last[key]~=text then entry.last[key]=text;widget:SetText(text) end
end
-- Supply pips: filled pips are ready supply; the next pip fills while supply regenerates.
local function pips(g)
 local p=UI.Panel{width=57,height=14,flexShrink=0,pointerEvents="none"}
 ---@param vg NVGContextWrapper
 function p:Render(vg)
  local c=g.state.campaign;if not c then return end
  local N=CampaignData.forState(g.state);local r=c.reinforcements;local n=N.supply.max
  local l=self:GetAbsoluteLayout();if l.w<=0 then return end
  local gap=l.w*.05;local w=(l.w-gap*(n-1))/n;local teal=T.hud.friendly
  for i=1,n do
   local x=l.x+(i-1)*(w+gap)
   nvgBeginPath(vg);nvgRoundedRect(vg,x,l.y,w,l.h,math.min(3,w*.35))
   if i<=r.supply then nvgFillColor(vg,nvgRGBA(teal[1],teal[2],teal[3],235)) else nvgFillColor(vg,nvgRGBA(200,212,232,170)) end
   nvgFill(vg)
   if i==r.supply+1 and c.event.status=="active" then
    local f=math.max(0,math.min(1,r.regen/N.supply.period))
    if f>.02 then
     nvgBeginPath(vg);nvgRoundedRect(vg,x,l.y+l.h*(1-f),w,l.h*f,math.min(3,w*.35))
     nvgFillColor(vg,nvgRGBA(teal[1],teal[2],teal[3],110));nvgFill(vg)
    end
   end
  end
 end
 return p
end
---@param g table
---@param H WarHUD
---@param play Widget
---@return table refs widgets and per-button tone state, also stored as H.battle
function B.create(g,H,play)
 local refs={entries={}}
 H.battle=refs
 g.pointerKind=g.pointerKind or (Platform.IsTouchSupported() and "touch" or "mouse")
 local function entry(key,button,labels,accent) local e={button=button,labels=labels,accent=accent};refs.entries[key]=e;return e end
 local function plain(key,text,fn,accent)
  local b=T.button(text,fn,nil,accent,{flexShrink=0,paddingHorizontal=4});entry(key,b,nil,accent);return b
 end
 -- Top bar: pause / speed / wave clock / supply / menu.
 refs.pause=plain("pause","Ⅱ 暂停",function() g.paused=not g.paused end)
 refs.speed=plain("speed","1×",function() g.speed=g.speed==1 and 2 or 1 end)
 refs.waveTitle=label("",12,T.muted,{lineHeight=1.1});refs.waveTime=label("",18,T.paper,{fontWeight="bold",lineHeight=1.1})
 local wave=UI.Panel{justifyContent="center",flexShrink=1,pointerEvents="none",children={refs.waveTitle,refs.waveTime}}
 refs.supplyLabel=label("补给",12,T.muted);refs.pips=pips(g);refs.supplyText=label("",13,T.paper)
 local supply=UI.Panel{flexDirection="row",alignItems="center",gap=6,flexShrink=0,pointerEvents="none",children={refs.supplyLabel,refs.pips,refs.supplyText}}
 refs.menuButton=plain("menu","≡",function() B.toggle(g,H,"menu") end)
 -- Camera tools: in the bar on wide screens, on top of the zone gauge when the bar wraps.
 local function stageCenter() local st=R.stage(g,true);return st.x+st.w*.5,st.y+st.h*.5 end
 local actions={
  overview=function() R.nasalOverview(g) end,home=function() R.home(g) end,
  zoomIn=function() local x,y=stageCenter();R.zoom(g,1.2,x,y) end,
  zoomOut=function() local x,y=stageCenter();R.zoom(g,1/1.2,x,y) end,
  select=function(i)
   local z=CampaignData.forState(g.state).zones[i] --[[@as {x:number,y:number}?]]
   if z then R.focus(g,z.x,z.y) end
  end}
 refs.barOverview=plain("barOverview","气管图",actions.overview);refs.barHome=plain("barHome","回营",actions.home)
 refs.barZoomIn=plain("barZoomIn","＋",actions.zoomIn);refs.barZoomOut=plain("barZoomOut","－",actions.zoomOut)
 refs.tools=UI.Panel{flexDirection="row",alignItems="center",gap=6,flexShrink=0,pointerEvents="box-none",
  children={refs.barOverview,refs.barHome,refs.barZoomIn,refs.barZoomOut}}
 refs.rowA=UI.Panel{flexDirection="row",alignItems="center",gap=8,flexGrow=1,flexShrink=1,pointerEvents="box-none",children={refs.pause,refs.speed,wave}}
 refs.rowB=UI.Panel{flexDirection="row",alignItems="center",gap=10,flexShrink=0,pointerEvents="box-none",children={supply,refs.tools,refs.menuButton}}
 refs.bar=T.hudPanel{position="absolute",flexDirection="row",alignItems="center",children={refs.rowA,refs.rowB}}
 -- Menu: the modal screens keep pausing the simulation; the dropdown itself does not.
 local function item(key,text,fn) return plain(key,text,function() B.closePopups(g,H);fn() end) end
 refs.menuItems={item("map","地图",function() H.mapMenu(g) end),item("progress","人体进程",function() H.campaignMenu(g) end),
  item("save","存档",function() H.saveMenu(g) end),item("help","指挥手册",function() H.help(g) end)}
 refs.menu=T.hudPanel{position="absolute",zIndex=12,visible=false,padding=6,gap=6,children=refs.menuItems}
 -- Zone gauge: battlefield order, tap a card to look there.
 refs.gauge=Z.create(g,actions)
 -- Bottom-left: select by type, control groups, box / append switches.
 local function pick(kind) return function() I.selectKind(g,kind);if g.audio then g.audio("command") end end end
 local function pad(key,text,fn,grow)
  local b=T.button(text,fn,nil,false,{flexGrow=grow or 1,flexBasis=0,flexShrink=1,paddingHorizontal=2});entry(key,b);return b
 end
 refs.all=pad("all","全军",pick("army"),1.1);refs.spear=pad("spear","白细胞",pick("spear"),1.2);refs.scout=pad("scout","血小板",pick("scout"),1.2)
 refs.groups={}
 for k=1,3 do local index=k
  local b=pad("group"..k,"编"..k,function() I.group(g,index,false) end)
  b.props.onLongPressStart=function() I.group(g,index,true) end;refs.groups[k]=b
 end
 refs.more=pad("more","更多",function() B.toggle(g,H,"more") end)
 refs.leftA=UI.Panel{flexDirection="row",gap=6,pointerEvents="box-none",children={refs.all,refs.spear,refs.scout}}
 refs.leftB=UI.Panel{flexDirection="row",gap=6,pointerEvents="box-none",children={refs.groups[1],refs.groups[2],refs.groups[3],refs.more}}
 refs.left=UI.Panel{position="absolute",gap=6,pointerEvents="box-none",children={refs.leftA,refs.leftB}}
 refs.box=plain("box","框选",function() g.box=not g.box end)
 refs.append=plain("append","追加",function() g.append=not g.append end)
 refs.morePanel=T.hudPanel{position="absolute",zIndex=12,visible=false,flexDirection="row",gap=6,padding=6,children={refs.box,refs.append}}
 -- Selection summary above the left pad.
 refs.chipText=label("",12,T.paper,{flexGrow=1,flexShrink=1})
 refs.chipHp=UI.ProgressBar{value=1,max=1,height=4,width=56,flexShrink=0,fillColor=T.hud.friendly}
 refs.chip=T.hudPanel{position="absolute",flexDirection="row",alignItems="center",gap=8,paddingHorizontal=10,borderRadius=10,pointerEvents="none",visible=false,children={refs.chipText,refs.chipHp}}
 -- Bottom-right: reinforcement (cooldown ring) and orders with key caps for mouse players.
 refs.reinforceTitle=label("调援 +2 白细胞",14,T.hud.onAccent,{fontWeight="bold",lineHeight=1.1})
 refs.reinforceSub=label("",11,T.hud.onAccent,{lineHeight=1.1})
 local reinforceText=UI.Panel{gap=1,pointerEvents="none",children={refs.reinforceTitle,refs.reinforceSub}}
 refs.reinforce=richButton(function() C.submit(g.state,{kind="reinforce",faction=1}) end,true,{reinforceText},{justifyContent="flex-start"})
 entry("reinforce",refs.reinforce,{refs.reinforceTitle,refs.reinforceSub},true)
 local base=refs.reinforce.Render
 ---@param vg NVGContextWrapper
 function refs.reinforce:Render(vg)
  base(self,vg)
  local c=g.state.campaign;if not c then return end
  local N=CampaignData.forState(g.state);local r=c.reinforcements
  local l=self:GetAbsoluteLayout();local cx,cy,rad=l.x+l.h*.42,l.y+l.h*.5,l.h*.22
  local color=self.props.disabled and {150,162,184} or {250,253,255}
  nvgBeginPath(vg);nvgCircle(vg,cx,cy,rad);nvgStrokeWidth(vg,2.5);nvgStrokeColor(vg,nvgRGBA(color[1],color[2],color[3],70));nvgStroke(vg)
  local f=r.cooldown>0 and 1-r.cooldown/N.supply.cooldown or 1
  if f>.01 then
   nvgBeginPath(vg);nvgArc(vg,cx,cy,rad,-math.pi*.5,-math.pi*.5+math.pi*2*f,NVG_CW)
   nvgStrokeWidth(vg,2.5);nvgStrokeColor(vg,nvgRGBA(color[1],color[2],color[3],230));nvgStroke(vg)
  end
 end
 refs.commands={}
 local function command(key,text,hint,fn)
  local title=label(text,13,T.paper);local capText=label(hint or "",10,T.muted)
  local cap=UI.Panel{borderWidth=1,borderColor=T.hud.border,borderRadius=4,paddingHorizontal=3,pointerEvents="none",children={capText}}
  local b=richButton(fn,false,{title,cap},{flexGrow=1,flexBasis=0,flexShrink=1})
  local e=entry(key,b,{title,capText});e.cap=cap;e.hint=hint;refs.commands[#refs.commands+1]=e
  if key=="attackmove" or key=="guard" then e.mode=key end
  return b
 end
 local function mode(name) return function() H.commandMode(g,name) end end
 refs.rightB=UI.Panel{flexDirection="row",gap=6,pointerEvents="box-none",children={
  command("attackmove","进攻","A",mode("attackmove")),command("guard","驻守",nil,mode("guard")),
  command("retreat","撤退","R",function() I.issue(g,"retreat") end),command("stop","停止","S",function() I.issue(g,"stop") end)}}
 refs.right=UI.Panel{position="absolute",gap=6,pointerEvents="box-none",children={refs.reinforce,refs.rightB}}
 -- Toast under the status bar, apart from the advisor's strips on the left.
 refs.notice=label("",13,T.paper,{textAlign="center",whiteSpace="normal",maxLines=2})
 refs.noticeBox=T.hudPanel{position="absolute",zIndex=11,visible=false,pointerEvents="none",paddingHorizontal=14,paddingVertical=8,borderRadius=12,children={refs.notice}}
 refs.fps=label("",11,T.quiet,{position="absolute",textAlign="center",visible=false})
 refs.root=UI.Panel{position="absolute",left=0,top=0,right=0,bottom=0,zIndex=6,pointerEvents="box-none",visible=false,children={
  refs.bar,refs.gauge.root,refs.chip,refs.left,refs.right,refs.fps,refs.noticeBox,refs.menu,refs.morePanel}}
 play:AddChild(refs.root)
 g.closeBattlePopups=function() return B.closePopups(g,H) end
 return refs
end
-- Close the menu dropdown and the switch panel; true when one was open (Esc uses this).
function B.closePopups(_g,H)
 local refs=H.battle;if not refs then return false end
 local open=refs.menu:IsVisible() or refs.morePanel:IsVisible()
 refs.menu:SetVisible(false);refs.morePanel:SetVisible(false)
 return open
end
function B.toggle(g,H,which)
 local refs=H.battle --[[@as table]]
 local panel=(which=="menu" and refs.menu or refs.morePanel) --[[@as Widget]]
 local show=not panel:IsVisible();B.closePopups(g,H);panel:SetVisible(show)
 if show then FX.enter(panel,6) end
end
-- w,h: UI units inside the safe area. Returns the layout for the advisor.
---@param H WarHUD
---@param g table
function B.layout(H,g,w,h,safe)
 local refs=H.battle --[[@as table]]
 local s=g.state
 local bounds=CampaignData.forState(s).bounds --[[@as {x:number,y:number,w:number,h:number}]]
 local d=UI.GetScale()/graphics:GetDPR()
 local L=M.battle(w,h,d,bounds.h>bounds.w);local pt=L.pt;local mouse=g.pointerKind=="mouse"
 refs.L=L;refs.root:SetVisible(true)
 -- Camera framing works in world pixels (CSS px), from the screen origin.
 g.stage={x=(safe.left+L.stage.x)*d,y=(safe.top+L.stage.y)*d,w=L.stage.w*d,h=L.stage.h*d}
 -- Top bar.
 local two=L.barRows==2;local inner=L.bar.h-(two and pt(8) or 0)
 local barBtn=two and (inner-pt(4))/2 or inner-pt(8)
 rect(refs.bar,L.bar)
 refs.bar:SetStyle{flexDirection=two and "column" or "row",alignItems=two and "stretch" or "center",justifyContent="center",
  paddingHorizontal=pt(8),paddingVertical=two and pt(4) or 0,gap=two and pt(4) or pt(14)}
 refs.rowA:SetStyle{gap=pt(8),flexGrow=two and 0 or 1}
 refs.rowB:SetStyle{gap=pt(10),justifyContent=two and "space-between" or "flex-start"}
 refs.pause:SetStyle{height=barBtn,width=pt(L.phone and 64 or 78),fontSize=pt(13)}
 refs.speed:SetStyle{height=barBtn,width=pt(40),fontSize=pt(13)}
 refs.menuButton:SetStyle{height=barBtn,width=pt(44),fontSize=pt(18)}
 refs.waveTitle:SetStyle{fontSize=pt(11)};refs.waveTime:SetStyle{fontSize=pt(two and 14 or 16)}
 -- Camera tools live in a single-row bar; a wrapped bar leaves them on the tall zone gauge.
 local toolsInBar=not two;local overviewText=s.campaign.event.id=="trachea" and "气管图" or "鼻腔图"
 refs.tools:SetVisible(toolsInBar);refs.tools:SetStyle{gap=pt(6)}
 refs.barOverview:SetText(overviewText)
 refs.barOverview:SetStyle{height=barBtn,width=pt(64),fontSize=pt(13)};refs.barHome:SetStyle{height=barBtn,width=pt(52),fontSize=pt(13)}
 for _,b in ipairs({refs.barZoomIn,refs.barZoomOut}) do b:SetStyle{height=barBtn,width=pt(38),fontSize=pt(15)};b:SetVisible(mouse) end
 refs.supplyLabel:SetStyle{fontSize=pt(12)};refs.supplyText:SetStyle{fontSize=pt(13)}
 refs.pips:SetStyle{width=pt(57),height=pt(14)}
 -- Menu dropdown under the menu button.
 local menuW=pt(mouse and 176 or 160)
 refs.menu:SetStyle{left=L.bar.x+L.bar.w-menuW,top=L.bar.y+L.bar.h+L.gap,width=menuW,padding=pt(6),gap=pt(6)}
 local keys={map="  M",help="",progress="",save=""}
 for i,key in ipairs({"map","progress","save","help"}) do
  local b=refs.menuItems[i] --[[@as Button]]
  b:SetStyle{height=L.secondary,width=menuW-pt(12),fontSize=pt(13)}
  b:SetText(({map="地图",progress="人体进程",save="存档",help="指挥手册"})[key]..(mouse and keys[key] or ""))
 end
 -- Zone gauge.
 Z.layout(refs.gauge,L,mouse,overviewText,not toolsInBar)
 -- Thumb pads.
 rect(refs.left,L.left);rect(refs.right,L.right)
 for _,row in ipairs({refs.leftA,refs.leftB,refs.rightB}) do row:SetStyle{gap=L.gap} end
 refs.left:SetStyle{gap=L.gap};refs.right:SetStyle{gap=L.gap}
 for _,b in ipairs({refs.all,refs.spear,refs.scout}) do b:SetStyle{height=L.primary,fontSize=pt(14)} end
 for _,b in ipairs({refs.groups[1],refs.groups[2],refs.groups[3],refs.more}) do b:SetStyle{height=L.secondary,fontSize=pt(13)} end
 refs.reinforce:SetStyle{height=L.primary,width=L.right.w,paddingLeft=L.primary*.8}
 refs.reinforceTitle:SetStyle{fontSize=pt(14)};refs.reinforceSub:SetStyle{fontSize=pt(11)}
 for _,e in ipairs(refs.commands) do
  e.button:SetStyle{height=L.secondary};e.labels[1]:SetStyle{fontSize=pt(13)};e.labels[2]:SetStyle{fontSize=pt(10)}
  e.cap:SetVisible(mouse and e.hint~=nil)
 end
 -- Switches above the left pad: box select only matters for touch (mouse drag already boxes).
 refs.box:SetVisible(not mouse)
 local moreW=pt(mouse and 104 or 196)
 refs.morePanel:SetStyle{left=L.left.x,top=L.chip.y-L.gap-L.secondary-pt(12),width=moreW,padding=pt(6),gap=pt(6)}
 for _,b in ipairs({refs.box,refs.append}) do b:SetStyle{height=L.secondary,width=pt(92),fontSize=pt(13)} end
 -- Selection chip, toast and debug counter.
 rect(refs.chip,L.chip);refs.chip:SetStyle{paddingHorizontal=pt(10),gap=pt(8)}
 refs.chipText:SetStyle{fontSize=pt(12)};refs.chipHp:SetStyle{width=pt(56),height=pt(4)}
 local noticeW=math.min(L.notice.w,pt(520))
 refs.noticeBox:SetStyle{left=L.notice.x+(L.notice.w-noticeW)*.5,top=L.notice.y,width=noticeW,paddingHorizontal=pt(14),paddingVertical=pt(7)}
 refs.notice:SetStyle{fontSize=pt(13)}
 refs.fps:SetStyle{left=L.stage.x,top=L.stage.y+L.stage.h-pt(18),width=L.stage.w,fontSize=pt(11)}
 -- Advisor strips stay in the left column, above the selection chip.
 L.chatWidth=math.min(356,(L.stacked and L.gauge.vertical) and L.gauge.x-L.gap-L.margin or L.stacked and L.stage.w or L.stage.x-L.gap-L.margin)
 L.chatBottom=L.chip.y-L.gap
 print(string.format("[BattleHUD] layout %.0fx%.0f density=%.3f phone=%s stacked=%s rows=%d stage=%.0f,%.0f %.0fx%.0f",
  w,h,d,tostring(L.phone),tostring(L.stacked),L.barRows,g.stage.x,g.stage.y,g.stage.w,g.stage.h))
 return L
end
function B.enter(H)
 local refs=H.battle;if not refs then return end
 FX.enter(refs.bar,8);FX.enter(refs.gauge.root,10);FX.enter(refs.left,14);FX.enter(refs.right,14)
end
-- HUD tick (5 Hz): text, counts and button states; pips, gauge bars and rings draw every frame.
---@param H WarHUD
---@param g table
function B.update(H,g)
 local refs=H.battle;local s=g.state;local c=s.campaign;if not refs or not c then return end
 local N=CampaignData.forState(s);local ev,r=c.event,c.reinforcements;local e=refs.entries
 local waves=#N.waves
 -- Wave clock.
 local title,time,color
 if ev.status=="completed" then title,time,color="战斗结束","已夺回",T.hud.friendly
 elseif ev.status=="failed" then title,time,color="战斗结束","失守",T.hud.hostile
 elseif ev.secure>0 then title,time,color="全域净化","稳固 "..math.floor(ev.secure).." / "..N.secureSeconds.." 秒",T.hud.friendly
 elseif ev.wave<waves then
  local left=N.waves[ev.wave+1].at-ev.elapsed
  title=ev.wave==0 and "备战" or "第 "..ev.wave.." / "..waves.." 波"
  time=(ev.wave==0 and "首波 " or "下一波 ")..clock(left);color=left<=5 and T.hud.hostile or T.paper
 else
  local viruses=ev.pendingViruses
  for _,u in pairs(s.entities) do if U.alive(u) and u.kind=="virus" then viruses=viruses+1 end end
  title="第 "..waves.." / "..waves.." 波";time=viruses>0 and "残敌 "..viruses or "夺回全部区域";color=T.paper
 end
 setText(refs,"waveTitle",refs.waveTitle,title);setText(refs,"waveTime",refs.waveTime,time)
 if refs.waveColor~=color then refs.waveColor=color;refs.waveTime:SetStyle{fontColor=color} end
 setText(refs,"supply",refs.supplyText,r.supply.." / "..N.supply.max)
 -- Pause / speed.
 setText(refs,"pause",refs.pause,g.paused and "▶ 继续" or "Ⅱ 暂停");setTone(e.pause,g.paused and "armed" or "normal")
 setText(refs,"speed",refs.speed,g.speed.."×");setTone(e.speed,g.speed>1 and "armed" or "normal")
 -- Zone gauge.
 Z.update(refs.gauge,g,N)
 -- Army counts and the current selection.
 local army,kinds=0,{}
 for _,u in pairs(s.entities) do if U.alive(u) and u.faction==1 and u.category=="unit" then
  kinds[u.kind]=(kinds[u.kind] or 0)+1;if u.kind~="worker" then army=army+1 end
 end end
 local ids=I.ids(g);local picked,hp,maxHp=0,0,0;local selected={}
 for _,id in ipairs(ids) do local u=s.entities[id];selected[u.kind]=(selected[u.kind] or 0)+1;hp=hp+u.hp;maxHp=maxHp+u.maxHp;picked=picked+1 end
 local only=function(kind) return picked>0 and selected[kind]==picked end
 setText(refs,"all",refs.all,"全军 "..army);setTone(e.all,picked>0 and picked==army and not selected.worker and "armed" or "normal")
 setText(refs,"spear",refs.spear,"白细胞 "..(kinds.spear or 0));setTone(e.spear,only("spear") and selected.spear==(kinds.spear or 0) and "armed" or "normal")
 setText(refs,"scout",refs.scout,"血小板 "..(kinds.scout or 0));setTone(e.scout,only("scout") and selected.scout==(kinds.scout or 0) and "armed" or "normal")
 for k=1,3 do
  local n=0;for _,id in ipairs(g.groups[k] or {}) do local u=s.entities[id];if U.alive(u) and u.faction==1 then n=n+1 end end
  setText(refs,"group"..k,refs.groups[k],"编"..k..(n>0 and "·"..n or ""))
 end
 setTone(e.more,(refs.morePanel:IsVisible() or g.box or g.append) and "armed" or "normal")
 setTone(e.box,g.box and "armed" or "normal");setTone(e.append,g.append and "armed" or "normal")
 refs.chip:SetVisible(picked>0)
 if picked>0 then
  local parts={"已选 "..picked}
  for _,kind in ipairs(D.unitOrder) do if selected[kind] then parts[#parts+1]=D.units[kind].name.." "..selected[kind] end end
  setText(refs,"chip",refs.chipText,table.concat(parts," · "))
  local f=maxHp>0 and hp/maxHp or 0;refs.chipHp:SetValue(f)
  local low=f<.35;if refs.chipLow~=low then refs.chipLow=low;refs.chipHp:SetStyle{fillColor=low and T.hud.hostile or T.hud.friendly} end
 end
 -- Orders: greyed until something is selected; target-picking modes stay solid.
 for _,cmd in ipairs(refs.commands) do
  setTone(cmd,picked==0 and "disabled" or cmd.mode and g.mode==cmd.mode and "armed" or "normal")
 end
 -- Reinforcement.
 local ok=Reinforce.available(s);local waiting=0
 for _,q in ipairs(r.queue) do waiting=waiting+q.remaining end
 local sub=ok and "消耗 "..N.supply.cost.." 补给" or ev.status~="active" and "战斗结束" or r.cooldown>0 and "冷却 "..math.ceil(r.cooldown).." 秒"
  or r.supply<N.supply.cost and "补给不足 · 还差 "..(N.supply.cost-r.supply) or "人口已满"
 if waiting>0 then sub=sub.." · "..waiting.." 名调入中" end
 setText(refs,"reinforceTitle",refs.reinforceTitle,"调援 +"..N.supply.count.." 白细胞")
 setText(refs,"reinforceSub",refs.reinforceSub,sub);setTone(e.reinforce,ok and "normal" or "disabled")
 -- Debug counter (F3 or `).
 refs.fps:SetVisible(g.debugFps==true)
 if g.debugFps then
  local units=0;for _,u in pairs(s.entities) do if u.category=="unit" and u.faction>0 and U.alive(u) then units=units+1 end end
  refs.fps:SetText(string.format("%d FPS · %d 单位",g.fps or 0,units))
 end
end
return B
