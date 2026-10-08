local UI=require("urhox-libs/UI")
local D,U,R,I,C,E,V,Save=require("war.Data"),require("war.Util"),require("war.Render"),require("war.Input"),require("war.Commands"),require("war.Economy"),require("war.Survival"),require("war.Save")
local Cells,W=require("war.Cells"),require("war.World")
local T,Art,M=require("war.UITheme"),require("war.UIArt"),require("war.UIModel")
local Brain=require("war.BrainUI")
local FX=require("war.UIMotion")
local Battle=require("war.BattleHUD")
---@class WarHUD
---@field refs table<string, any>
---@field cards table[]
---@field battle table|nil
---@field commandMode fun(g:table,mode:string)
local H={root=false,refs={},cards={},lastTab=false,tick=0,lastLayout="",modalKind=false}
local label,panel,btn=T.label,T.panel,T.button
local orderNames={gather="采集",build="施工",farm="培育",repair="修复",guard="驻守",move="移动",attack="攻击",attackmove="进攻移动",extinguish="灭火",rally="集结",retreat="撤退"}
local function orderQueueText(e)
 local orders=e and e.orders or {}
 if #orders==0 then return "命令队列\n空闲" end
 local lines={"命令队列"}
 for i,o in ipairs(orders) do
  lines[#lines+1]=i..". "..(orderNames[o.kind] or o.kind)
  if i>=5 then if #orders>i then lines[#lines+1]="… 还有 "..(#orders-i).." 项" end;break end
 end
 return table.concat(lines,"\n")
end
local function battleText(s,text)
 if not s.campaign or not require("war.MapRegistry").isTrachea(s) then return text end
 return text:gsub("后鼻屏障","下段屏障"):gsub("后鼻侧","气管下端"):gsub("鼻腔","气管"):gsub("咽喉防线","双肺净化"):gsub("咽喉尚未开放","双肺尚未开放")
end
local function textRef(name,text,size,color,props)
 local l=label(text,size,color,props);H.refs[name]=l;return l
end
local function row(children,props)
 local p={flexDirection="row",gap=8,alignItems="center",children=children}
 for k,v in pairs(props or {}) do p[k]=v end
 return UI.Panel(p)
end
local function icon(group,kind,size)
 local p=UI.Panel{width=size,height=size,flexShrink=0,pointerEvents="none"}
 ---@param vg NVGContextWrapper
 function p:Render(vg)
  local l=self:GetAbsoluteLayout();local side=math.min(l.w,l.h)
  if group=="cell" then Cells.draw(vg,kind,1,l.x+l.w/2,l.y+l.h/2,side/(Cells.radius(kind)*2.7),0,0)
  else Art.draw(vg,group,kind,l.x+l.w/2,l.y+l.h/2,side) end
 end
 return p
end
local function fadeIn(widget)
 FX.enter(widget)
end
function H.toggle(g,tab) if g.state.campaign then U.message(g.state,"后续事件开放生产");return end;g.tab=g.tab==tab and false or tab;g.placement=false;g.mode=false;H.sidebar(g) end
function H.closeModal(g)
 H.refs.mapFog=nil;H.refs.mapLegend=nil;H.refs.saveStatus=nil;H.refs.saveActions=nil;H.refs.saveSlots=nil;H.modalKind=false
 if H.refs.modal then H.refs.modal:RemoveAllChildren();H.refs.modal:SetVisible(false) end
 g.modal=false
end
-- Every modal has a bounded scrolling body; the dismiss button stays reachable.
function H.openPanel(g,title,subtitle,body,footer,width)
 H.closeModal(g);g.modal=true
 local box=panel{width="94%",maxWidth=width or 650,height="90%",maxHeight=760,padding=18,gap=12,children={
  row({UI.Panel{flexGrow=1,flexBasis=0,gap=4,children={label(title,23,T.paper),label(subtitle or "",11,T.muted,{whiteSpace="normal",maxLines=2})}},btn("×",function() H.closeModal(g) end,44)}, {alignItems="flex-start"}),
  UI.Panel{height=1,backgroundColor=T.border},
  UI.ScrollView{flexGrow=1,flexBasis=0,scrollY=true,children={body}},
  footer or row({btn("返回胞群",function() H.closeModal(g) end,150,true)},{justifyContent="flex-end",flexWrap="wrap"}),
 }}
 H.refs.modal:AddChild(box);H.refs.modal:SetVisible(true);fadeIn(box)
 return box
end
function H.dialog(g,title,lines,buttons)
 title=battleText(g.state,title)
 local mapped={};for i,text in ipairs(lines) do mapped[i]=battleText(g.state,text) end;lines=mapped
 local body=UI.Panel{gap=12,paddingVertical=8}
 for _,text in ipairs(lines) do body:AddChild(label(text,13,T.muted,{whiteSpace="normal",maxLines=6})) end
 local actions={}
 for _,spec in ipairs(buttons or {}) do actions[#actions+1]=btn(spec[1],spec[2],spec[3] or 130,spec[4]) end
 H.openPanel(g,title,"胞群指挥中心",body,row(actions,{flexWrap="wrap",justifyContent="flex-end"}))
end
-- The first screen after choosing a mode is a short, actionable briefing.
-- Keep it separate from the full handbook so new players understand the unit roles
-- and control groups before the battlefield starts accepting commands.
function H.startGuide(g)
 local campaign=g.state.campaign~=nil
 local body=UI.Panel{gap=10,paddingVertical=6}
 local function section(title,text)
  body:AddChild(panel{backgroundColor=T.surface,padding=12,gap=5,boxShadow={},children={
   label(title,15,T.teal),label(text,12,T.muted,{whiteSpace="normal",maxLines=5})
  }})
 end
 section("01  先认识三类细胞",
  "白细胞：主力战斗单位，用来清除病毒、进攻敌方并守住区域。血小板：速度快、视野大，适合先行侦察、快速占位和支援危险区域。红细胞：沙盒模式的采集与建设单位，负责搬运资源、修建和维持胞群。")
 section("02  编队 1 / 2 / 3",
  "选中单位后按 Ctrl+1、Ctrl+2 或 Ctrl+3 保存编队；之后按 1、2、3 立即召回对应编队。鼠标可拖动框选，手机端可连续点选或使用底部编队按钮。")
 section("03  第一个动作",
  campaign and "战役：先选白细胞守住防线，再让血小板探路；点击地图下达移动或进攻命令，遇到压力可按 R 撤回，按 S 停止。" or "沙盒：先选红细胞采集资源并送回胞巢，再建造生产设施；用编队键把采集队和战斗队分开管理。")
 local start=btn("开始行动",function() H.closeModal(g) end,130,true)
 local handbook=btn("查看指挥手册",function() H.help(g) end,140)
 H.openPanel(g,"开局指引",campaign and "战役模式 · 先守住，再反攻" or "全身沙盒 · 采集、建设与发展",body,row({handbook,start},{flexWrap="wrap",justifyContent="flex-end"}))
end
function H.help(g)
 local body=UI.Panel{gap=12}
 local sections={
  {"01  建立稳态","选择红细胞，点击蛋白束或钙晶采集。建造培养床并安排红细胞生产葡萄糖；荧光腺与补给维持休息期安全。"},
  {"02  触屏指挥","单击选兵，双击细胞选择附近同类，拖动空地移动镜头，双指缩放。开启框选后拖动选择部队；选中部队后点击目的地，或先选择移动 / 进攻。"},
  {"03  鼠标与键盘","左键拖动框选，双击细胞选择附近同类，右键下令；Shift 追加命令。方向键移动镜头，滚轮缩放。空格暂停，A 进攻，S 停止，R 撤退，B 建造，H 返回首页，M 地图。"},
  {"04  编队与生产","Ctrl+1/2/3 保存编队，1/2/3 召回；触屏长按编队按钮保存。核心胞巢培育红细胞，其他生产建筑训练对应兵种；选中建筑查看队列。"},
  {"05  血管与迷雾","管壁不可穿越，黄色膜通行口允许穿行。地图可点击定位；F 临时查看全图，再按一次恢复探索迷雾。"},
  {"06  生存与存档","活跃期扩建与采集，休息期保持温度、饱食与精神。每个黎明自动存档，也可使用三个手动槽。主基地被毁仍可重建；单位与生产建筑全部损失才结束。"},
 }
 if g.state.campaign then sections={
 {"01  守卫与反攻","入口黏膜已经感染。选择白细胞或军队，守住后鼻屏障，再反攻夺回三块组织区域。"},
 {"02  区域争夺","战斗单位进入整片区域即可争夺。双方在场时暂停进度，无人在场保留进度；清除敌军后继续夺回。"},
  {"03  指挥部队","电脑左键框选、双击细胞选择附近同类、右键下令，A 进攻、S 停止、R 回防，H 返回首页。手机选中细胞后点击目标，框选与追加在更多面板中。"},
 {"04  鼻道与血管","鼻甲与鼻中隔阻挡通行和攻击。上下黏膜道路可以绕行，血管是快速侧路；只有黄色膜口可以穿越管壁。点击「鼻腔图」查看整个战场，再缩放选择部队。"},
 {"05  调援","消耗 2 补给调来两个白细胞，3 秒后从后鼻侧进入。冷却 20 秒，每 10 秒回复 1 补给，上限 6，援军预留人口。"},
 {"06  胜败与重试","完成三波入侵、清除病毒并完全控制三块区域保持 20 秒即可成功。病毒完全夺下后鼻屏障就失败，可以重试本次事件。"},
 {"07  人体进程","鼻腔之后依次是咽喉、双肺、肠道和血流事件。后续内容尚未开放；关闭迷雾也不能进入锁定组织。"}} end
 if g.state.campaign and require("war.MapRegistry").isTrachea(g.state) then
  for _,item in ipairs(sections) do item[1]=battleText(g.state,item[1]);item[2]=battleText(g.state,item[2]) end
  sections[4]={"04  气管通道","沿纵向气管黏膜移动，管壁阻挡通行与攻击。上段入口、中段通道、下段屏障依次排列。点击「气管图」查看战场，打开地图可浏览全身，其余器官暂不可进入。"}
  sections[7]={"07  人体进程","气管之后是双肺、肠道和血流事件。后续内容尚未开放；全身可浏览，关闭迷雾也不能进入锁定组织。"}
 end
 for _,item in ipairs(sections) do body:AddChild(panel{backgroundColor=T.surface,padding=14,gap=7,boxShadow={},children={label(item[1],15,T.teal),label(item[2],12,T.muted,{whiteSpace="normal",maxLines=8})}}) end
 H.openPanel(g,"指挥手册","从一名红细胞，到一支远征胞群。",body)
end
local function readSlot(g,k)
 Save.read(k,function(state,msg)
  if state then g.replaceState(state);H.closeModal(g) else U.message(g.state,msg) end
 end)
end
function H.saveMenu(g)
 local body=UI.Panel{gap=10}
 local status=label(Save.status,12,T.teal)
 body:AddChild(status)
 local actions,slots={},{}
 for slot=0,3 do local k=slot;local known=Save.slots[k]
  local summary=label(known and "本次已保存 · 第"..known.day.."天" or k==0 and "每个黎明自动更新" or "独立槽位 · 可读取已有记录",11,T.muted)
  slots[k]=summary
  local load=btn("读取",function() readSlot(g,k) end,92)
  actions[#actions+1]=load
  local buttons={load}
  if k>0 and g.started then
   local save=btn("保存到此槽",function() Save.write(g.state,k) end,130,true)
   actions[#actions+1]=save;buttons[#buttons+1]=save
  end
  body:AddChild(panel{backgroundColor=T.surface,padding=14,gap=10,boxShadow={},children={
   row({icon("buildings",k==0 and "emblem" or "core",44),UI.Panel{flexGrow=1,flexBasis=0,gap=3,children={
    label(k==0 and "黎明自动记录" or "手动记录 0"..k,15),
    summary,
   }}}),row(buttons,{flexWrap="wrap"}),
  }})
 end
 local retry=btn("重试上次保存",function() Save.retry(g.state) end,150)
 actions[#actions+1]=retry;body:AddChild(retry)
 body:AddChild(label("以“已保存”提示为准。读取失败会保留当前胞群。",11,T.muted,{whiteSpace="normal",maxLines=3}))
 H.openPanel(g,"胞群记录","三个手动槽位，一份黎明自动记录。",body)
 H.refs.saveStatus=status;H.refs.saveActions=actions;H.refs.saveSlots=slots;H.refs.saveRetry=retry;H.modalKind="save"
end
function H.campaignMenu(g)
 local c=g.state.campaign;if not c then H.mapMenu(g);return end
 local body=UI.Panel{gap=12}
 local N=require("war.CampaignData").forState(g.state)
 for i,stage in ipairs(N.stages) do
  local status=c.completed[stage.id] and "已完成" or i==c.stage and stage.implemented and "进行中" or "尚未开放"
  body:AddChild(panel{padding=14,gap=5,children={label(i.." / "..#N.stages.." · "..stage.name,16,T.paper),label(status,12,c.completed[stage.id] and T.teal or T.gold)}})
 end
 body:AddChild(label(require("war.MapRegistry").isTrachea(g.state) and "全身地图可浏览。当前开放气管守卫，下一事件：双肺净化（尚未开放）。" or "完成前期五个事件后开放全人体随机攻防。当前仅鼻腔可玩。",12,T.muted,{whiteSpace="normal",maxLines=4}))
 H.openPanel(g,"人体进程","同一人体持续推进 · 已夺回组织与部队保留",body)
end
function H.mapMenu(g)
 H.closeModal(g);g.modal=true;H.modalKind="map"
 local vw=UI.GetViewportSize();local overview=g.state.campaign~=nil
 local map=UI.Panel{flexGrow=1,flexBasis=0,height="100%",backgroundColor=T.ink,onTap=function(e)
  g.camera.x,g.camera.y=R.mapPoint(H.refs.fullMap:GetAbsoluteLayout(),e.x,e.y,g.state);H.closeModal(g)
 end}
 H.refs.fullMap=map
 ---@param vg NVGContextWrapper
 function map:Render(vg) R.minimap(vg,g,self:GetAbsoluteLayout(),overview) end
 local legendRows={}
 for _,biome in ipairs(D.biomes) do local c=biome.color
  legendRows[#legendRows+1]=row({UI.Panel{width=9,height=9,borderRadius=3,backgroundColor={c[1],c[2],c[3],255}},label(biome.name,10,T.muted)},{height=22,gap=7})
 end
 local hint=label("",11,T.gold,{whiteSpace="normal",maxLines=2})
 local function updateHint()
  if g.state.campaign then hint:SetText(battleText(g.state,"鼻腔已开放 · 全身可浏览 · 其余组织暂不可进入"));return end
  if g.state.anatomyVersion==3 then hint:SetText("全身结构始终可浏览 · 敌人和未发现资源仍受迷雾限制");return end
  hint:SetText(g.fogDisabled and "全图查看 · 迷雾已临时关闭，恢复后继续探索" or overview and "组织总览 · 身体结构示意，黄色膜口允许通行" or "探索地图 · 未探索组织隐藏；切换总览查看身体结构")
 end
 updateHint()
 local toggle=btn(overview and "探索地图" or "组织总览",function() end,114)
 toggle.props.onClick=function() overview=not overview;toggle:SetText(overview and "探索地图" or "组织总览");T.active(toggle,overview);updateHint() end
 local fog=btn(g.fogDisabled and "恢复迷雾" or "查看全图",function() if g.state.anatomyVersion==3 then g.camera={x=1024,y=2048};g.zoom=require("war.View").minZoom(g.state,R.w,R.h) else I.toggleFog(g) end;updateHint() end,114);H.refs.mapFog=fog
 local legend=UI.ScrollView{width=vw<720 and 0 or 158,visible=vw>=720,scrollY=true,height="100%",children={UI.Panel{gap=2,children=legendRows}}}
 H.refs.mapLegend=legend
 local box=panel{width="94%",maxWidth=1060,height="93%",maxHeight=840,padding=16,gap=10,children={
  row({UI.Panel{flexGrow=1,flexBasis=0,gap=4,children={label("人体内域",24),label(D.width(g.state).." × "..D.height(g.state).." · "..#D.biomes.."类组织 · 点击地图定位",11,T.muted)}},btn("×",function() H.closeModal(g) end,44)}),
  row({map,legend},{flexGrow=1,flexBasis=0,alignItems="stretch"}),
  hint,
  row({toggle,fog,btn("返回首页",function() H.closeModal(g);if g.returnHome then g.returnHome() end end,114,true),btn("关闭地图",function() H.closeModal(g) end,114)},{flexWrap="wrap"}),
 }}
 H.refs.modal:AddChild(box);H.refs.modal:SetVisible(true);fadeIn(box)
end
function H.card(g,tab,kind)
 local d=tab=="build" and D.buildings[kind] or tab=="train" and D.units[kind] or D.tech[kind]
 local status=label("",10,T.teal)
 local image=icon(tab=="train" and "cell" or tab=="build" and "buildings" or "resources",kind,70)
 local desc=tab=="train" and (D.buildings[d.at].name.." · 人口 "..d.pop.." · 生命 "..d.hp) or d.desc
 local card=panel{height=146,padding=12,gap=8,backgroundColor=T.surface,boxShadow={},transition="backgroundColor 0.15s easeOut",children={
  row({image,UI.Panel{flexGrow=1,flexBasis=0,gap=5,pointerEvents="none",children={
   label(d.name,16),label("T"..d.tier.."  /  "..(tab=="build" and "生长" or tab=="train" and "培育" or "研究").." "..(d.time or d.train).."秒",10,T.gold),
   label(desc,11,T.muted,{whiteSpace="normal",maxLines=2}),
  }}}),
  label(M.cost(d.cost),10,T.muted,{whiteSpace="normal",maxLines=2}),status,
 }}
 card.props.onPointerEnter=function() card:SetStyle{backgroundColor=T.raised} end
 card.props.onPointerLeave=function() card:SetStyle{backgroundColor=T.surface} end
 card.props.onTap=function()
  local ok,why,producer=M.gate(g,tab,kind)
  if not ok then U.message(g.state,why);return end
  if tab=="build" then
   local worker=false;for _,id in ipairs(I.ids(g)) do if g.state.entities[id].kind=="worker" then worker=true end end
   if not worker then I.selectKind(g,"worker") end
   g.placement=kind;g.mode=false;g.tab=false;H.sidebar(g)
   U.message(g.state,"放置"..d.name.." · 点击地图确认 / Esc取消")
  else
   local building=producer --[[@as table]]
   local command={kind=tab=="train" and "train" or "research",faction=1,target=building.id}
   if tab=="train" then command.unit=kind else command.tech=kind end
   C.submit(g.state,command)
   U.message(g.state,d.name..(g.paused and " · 命令已排队，恢复后执行" or " · 已提交生产命令"))
  end
 end
 FX.spotlight(card)
 H.cards[#H.cards+1]={widget=card,status=status,tab=tab,kind=kind}
 return card
end
function H.sidebar(g)
 local host=H.refs.sidebar;if not host then return end
 host:RemoveAllChildren();H.cards={};H.lastTab=g.tab
 local battle=g.state.campaign~=nil
 H.refs.goalBox:SetVisible(not battle and not g.tab and not H.metrics.short);H.refs.zoomTools:SetVisible(not battle and not g.tab)
 if not g.tab then host:SetVisible(false);return end
 host:SetVisible(true)
 local title=({build="胞群蓝图",train="细胞培育",tech="核酸研究"})[g.tab]
 host:AddChild(row({UI.Panel{flexGrow=1,flexBasis=0,gap=4,children={label(title,21),label(g.tab=="build" and "选择蓝图 → 点击组织放置" or "条件与资源会实时更新",10,T.muted)}},btn("×",function() g.tab=false;g.placement=false;H.sidebar(g) end,42)}))
 local body=UI.Panel{gap=10,paddingRight=6,paddingTop=6,paddingBottom=8}
 local order=g.tab=="build" and D.buildOrder or g.tab=="train" and D.unitOrder or {"tier2","tier3","storage","insulation","weapons"}
 for _,kind in ipairs(order) do body:AddChild(H.card(g,g.tab,kind)) end
 host:AddChild(UI.ScrollView{flexGrow=1,flexBasis=0,scrollY=true,children={body}})
 fadeIn(host)
end
local function commandMode(g,mode)
 if #I.ids(g)==0 then U.message(g.state,"先选择单位，再下达命令");return end
 g.placement=false;g.mode=g.mode==mode and false or mode
end
H.commandMode=commandMode
function H.cancel(g)
 local hadAction=g.mode or g.placement or g.tab
 g.mode=false;g.placement=false;g.tab=false
 local ids=I.ids(g);local e=ids[1] and g.state.entities[ids[1]]
 if #ids>0 or g.inspectTarget then
  g.selection={};g.inspectTarget=false
  end
 if hadAction then
  H.sidebar(g)
  return
 end
 if e and e.category=="building" then C.submit(g.state,{kind="cancel",faction=1,target=e.id}) end
end
function H.more(g)
 local body=UI.Panel{gap=12}
 local function action(text,f) return btn(text,function() H.closeModal(g);f() end,140) end
 body:AddChild(label("战术指令",15,T.teal))
 body:AddChild(row({action("驻守",function() commandMode(g,"guard") end),action("撤退 [R]",function() I.issue(g,"retreat") end),action("设置集结点",function() H.rally(g) end),action("取消当前操作",function() H.cancel(g) end)},{flexWrap="wrap"}))
 body:AddChild(label("选择与编队",15,T.teal))
 body:AddChild(row({action(g.box and "关闭框选" or "开启框选",function() g.box=not g.box end),action(g.append and "关闭追加" or "追加命令",function() g.append=not g.append end)},{flexWrap="wrap"}))
 for j=1,3 do local k=j
  body:AddChild(row({label("编队 "..k,12,T.muted),action("选中编队",function() I.group(g,k,false) end),action("保存当前选择",function() I.group(g,k,true) end)},{flexWrap="wrap"}))
 end
 H.openPanel(g,"战术面板","空格暂停后也可以排列命令。",body)
end
function H.rally(g)
 local id=I.ids(g)[1];local e=id and g.state.entities[id]
 if not e or e.category~="building" or not e.complete then U.message(g.state,"先选中一座已完工的生产建筑");return end
 g.mode="rally";g.placement=false;U.message(g.state,"点击地图设置集结点")
end
function H.survey(g)
 if g.state.campaign then H.campaignMenu(g);return end
 if not W.hasVessels(g.state) then return end
 g.vesselSurvey=not g.vesselSurvey
 if g.vesselSurvey then
  local best,d=false,math.huge
  for _,v in ipairs(W.vessels(g.state).gates) do local dd=(v.x-g.camera.x)^2+(v.y-g.camera.y)^2;if dd<d then best,d=v,dd end end
  if best then local gate=best --[[@as VesselGate]];g.camera.x,g.camera.y=gate.px,gate.py;g.zoom=.36 end
 end
 U.message(g.state,g.vesselSurvey and "解剖通路 · 黄色膜口可通行" or "返回探索视图")
end
function H.commands(g,narrow)
 local host=H.refs.commands;host:RemoveAllChildren()
 H.refs.commandButtons={};H.refs.tabButtons={}
 local function command(text,key,f,accent)
  local b=btn(text,f,nil,accent,{flexGrow=1,flexBasis=0,flexShrink=1,height=42,fontSize=11})
  if key then H.refs.commandButtons[key]=b end;return b
 end
 local function tab(text,key)
  local b=command(text,key,function() H.toggle(g,key) end)
  H.refs.tabButtons[key]=b;return b
 end
 local first={tab("建造 [B]","build"),tab("训练","train"),tab("科技","tech"),command("红细胞",nil,function() I.selectKind(g,"worker") end),command("军队",nil,function() I.selectKind(g,"army") end)}
 if g.state.campaign then
  local reinforce=command("调援 +2", "reinforce",function() C.submit(g.state,{kind="reinforce",faction=1}) end,true)
  first={reinforce,command("白细胞",nil,function() I.selectKind(g,"spear") end),command("血小板",nil,function() I.selectKind(g,"scout") end),command("军队",nil,function() I.selectKind(g,"army") end)}
 end
 if not narrow then
  first[#first+1]=command("框选","box",function() g.box=not g.box end)
   first[#first+1]=command("追加命令","append",function() g.append=not g.append end)
 end
 host:AddChild(row(first))
 local second={command("移动","move",function() commandMode(g,"move") end),command("进攻 [A]","attackmove",function() commandMode(g,"attackmove") end)}
 if not narrow then second[#second+1]=command("驻守","guard",function() commandMode(g,"guard") end);second[#second+1]=command("撤退 [R]",nil,function() I.issue(g,"retreat") end) end
 second[#second+1]=command("停止 [S]",nil,function() I.issue(g,"stop") end)
 if not narrow and not g.state.campaign then second[#second+1]=command("集结","rally",function() H.rally(g) end) end
 second[#second+1]=command(narrow and "更多" or "取消",nil,function() if narrow then H.more(g) else H.cancel(g) end end)
 host:AddChild(row(second))
 local groups={}
 for j=1,3 do local k=j;local b=btn("编队 "..j,function() I.group(g,k,false) end,68,false,{height=32,fontSize=10})
  b.props.onLongPressStart=function() I.group(g,k,true) end;groups[#groups+1]=b
 end
 host:AddChild(row({groups[1],groups[2],groups[3],textRef("fps","",9,T.quiet,{flexGrow=1,textAlign="right"})}))
end
function H.layout(g)
 local vw,vh=UI.GetViewportSize();local safe=UI.GetSafeAreaInsets()
 local w,h=vw-safe.left-safe.right,vh-safe.top-safe.bottom
 local signature=string.format("%.0f:%.0f:%s:%s",w,h,tostring(g.state.campaign and g.state.campaign.event.id),tostring(g.pointerKind))
 if H.refs.mapLegend then H.refs.mapLegend:SetVisible(w>=720);H.refs.mapLegend:SetStyle{width=w>=720 and 158 or 0} end
 if signature==H.lastLayout then return end;H.lastLayout=signature
 local l=M.layout(w,h);local campaign=g.state.campaign~=nil
 if campaign then l.top=l.narrow and 130 or l.short and 92 or 96;l.toolbarY=l.top+8;l.goalY=l.top+(l.narrow and 53 or 8) end
 H.metrics=l;local refs=H.refs
 refs.brand:SetVisible(not l.flatResources)
 refs.top:SetStyle{height=l.top,flexDirection=l.compact and "column" or "row",gap=l.compact and 6 or 18}
 refs.brand:SetStyle{width=l.compact and "100%" or 172,height=l.compact and 24 or "100%",flexDirection=l.compact and "row" or "column"}
 refs.brandSub:SetVisible(not l.compact)
 refs.clockBox:SetVisible(not l.compact and not l.flatResources)
 refs.resourceGrid:SetStyle{width=l.compact and "100%" or "auto",flexGrow=l.resourceCompact and 0 or 1,flexBasis=l.resourceCompact and "auto" or 0,flexWrap=l.resourceCompact and "wrap" or "no-wrap",height=l.resourceCompact and 66 or l.flatResources and 48 or 58,gap=4}
 for _,metric in ipairs(refs.resourceMetrics) do metric:SetStyle{flexGrow=1,flexShrink=1,flexBasis=l.resourceCompact and "23%" or 0,height=l.resourceCompact and 31 or l.flatResources and 48 or 58} end
 for _,k in ipairs(D.resources) do refs[k]:SetStyle{fontSize=l.resourceCompact and 12 or 15} end
 for _,picture in ipairs(refs.resourceIcons) do picture:SetStyle{width=l.compact and 22 or 30,height=l.compact and 22 or 30} end
 refs.toolbar:SetStyle{top=l.toolbarY,justifyContent="flex-end"}
 for _,button in ipairs(refs.toolbar:GetChildren()) do button:SetStyle{flexGrow=l.narrow and 1 or 0,flexBasis=l.narrow and 0 or "auto",flexShrink=l.narrow and 1 or 0} end
 refs.goalBox:SetStyle{top=l.goalY,width=l.narrow and w-24 or l.compact and 310 or 410}
 refs.goalBox:SetVisible(not l.short and not g.tab)
 if campaign then refs.goalBox:SetStyle{width=l.narrow and w-24 or math.min(340,w*.39),padding=8,gap=4};refs.goal:SetStyle{fontSize=11};refs.tutorial:SetStyle{fontSize=10} end
 refs.resourceGrid:SetVisible(not campaign);refs.nasalGrid:SetVisible(campaign);refs.nasalGrid:SetStyle{width="100%",height=l.narrow and 110 or 70,gap=4}
 refs.brand:SetVisible(not campaign and not l.flatResources);refs.clockBox:SetVisible(not campaign and not l.compact and not l.flatResources)
 refs.surveyButton:SetText(campaign and "进程" or "通路")
 refs.fog:SetStyle{width=campaign and 72 or 60,minWidth=campaign and 56 or 0,paddingHorizontal=campaign and 2 or 8,fontSize=campaign and 11 or 12}
 refs.zoomTools:SetStyle{bottom=l.dock+26}
 refs.dock:SetStyle{height=l.dock,flexDirection=l.narrow and "column" or "row",gap=l.narrow and 4 or 12,padding=l.narrow and 10 or 12}
 refs.selectionCard:SetStyle{width=l.narrow and "100%" or l.selectionWidth,height=l.narrow and 100 or "100%",flexDirection="row",padding=l.narrow and 0 or 8}
 refs.portrait:SetStyle{width=l.narrow and 54 or l.short and 44 or 66,height=l.narrow and 54 or l.short and 44 or 66}
 refs.selectionText:SetStyle{gap=l.short and 2 or 4}
 refs.selected:SetStyle{fontSize=(l.short or l.narrow) and 14 or 16}
 refs.mapShell:SetVisible(not l.compact);refs.mapShell:SetStyle{width=l.mapWidth}
 refs.noticeBox:SetStyle{bottom=l.dock+26,left=l.narrow and 12 or 230,right=12}
 refs.sidebar:SetStyle{left=12,top=l.sidebarTop,bottom=l.sidebarBottom,width=math.min(l.narrow and w-24 or 390,w-24)}
 refs.menuTitle:SetStyle{fontSize=l.narrow and 42 or l.short and 48 or 64}
 refs.menuContent:SetStyle{width=l.narrow and "92%" or "56%",paddingLeft=l.narrow and 20 or 48,paddingTop=l.short and 22 or 56,paddingBottom=l.short and 16 or 30,gap=l.short and 10 or 18}
 refs.menuNarrative1:SetVisible(not l.short);refs.menuNarrative2:SetVisible(not l.short);refs.menuModes:SetVisible(not l.short);refs.menuSummary:SetVisible(not l.short)
 -- Keep the entire upper-left corner for the free-standing advisor.
 local brainSize=l.short and 88 or l.narrow and (w<400 and 104 or 116) or 176
 local statusWidth=math.min(w-brainSize-36,campaign and 660 or 850)
 refs.top:SetStyle{left=w-statusWidth-12,right=12,width=statusWidth,paddingLeft=10}
 refs.brand:SetVisible(false)
 refs.nasalCards:SetStyle{flexDirection=l.narrow and "column" or "row",alignItems="stretch",gap=4}
 for _,zone in ipairs(refs.zones) do
  zone.card:SetStyle{flexDirection=l.narrow and "row" or "column",alignItems=l.narrow and "center" or "stretch",height=l.narrow and 24 or "auto"}
  zone.title:SetStyle{width=l.narrow and 52 or "auto",fontSize=l.narrow and 9 or 11}
  zone.status:SetStyle{flexGrow=l.narrow and 1 or 0,flexBasis=l.narrow and 0 or "auto",fontSize=l.narrow and 9 or 10}
  zone.bar:SetVisible(not l.narrow)
 end
 local toolbarWidth=l.narrow and statusWidth or 397
 refs.toolbar:SetStyle{left=w-toolbarWidth-12,right=12,width=toolbarWidth,flexWrap=l.narrow and "wrap" or "no-wrap",gap=5}
 for _,button in ipairs(refs.toolbar:GetChildren()) do
  button:SetStyle{flexGrow=0,flexBasis=l.narrow and (statusWidth-10)/3 or "auto",height=l.narrow and 30 or 44,fontSize=l.narrow and 10 or 12,paddingHorizontal=l.narrow and 2 or 8}
 end
 local goalWidth=math.min(statusWidth,campaign and 340 or 410)
 refs.goalBox:SetStyle{left=w-goalWidth-12,right=12,top=l.toolbarY+(l.narrow and 74 or 52),width=goalWidth}
 -- Campaign battles use the thumb-zone battle HUD; the sandbox keeps the dock layout.
 for _,ref in ipairs({refs.top,refs.toolbar,refs.dock}) do ref:SetVisible(not campaign) end
 refs.zoomTools:SetVisible(not campaign and not g.tab)
 if campaign then refs.goalBox:SetVisible(false) end
 local battle=nil
 if campaign then battle=Battle.layout(H,g,w,h,safe) elseif H.battle then H.battle.root:SetVisible(false);g.stage=nil end
 H.commands(g,l.narrow)
 Brain.layout(H,l,w,h,battle)
end
function H.create(g)
 T.init();Cells.init(UI.GetNVGContext());Art.init(UI.GetNVGContext())
 H.refs={};H.lastLayout="";H.tick=0;H.uiCounters={};H.uiState=g.state;H.wasStarted=false
 H.root=UI.Panel{width="100%",height="100%",pointerEvents="box-none",children={}}
 local inputLayer=UI.Panel{id="worldInput",position="absolute",left=0,top=0,right=0,bottom=0,
  onPointerDown=function(e) I.down(g,e) end,onPointerMove=function(e) I.move(g,e) end,onPointerUp=function(e) I.up(g,e) end,onPointerCancel=function() g.drag=false end,
  onPinchStart=function() g.drag=false;g.pinchStart=g.zoom end,
  onPinchMove=function(e) local factor=UI.GetScale()/graphics:GetDPR();R.zoom(g,(g.pinchStart or g.zoom)*e.scale/g.zoom,e.centerX*factor,e.centerY*factor) end,
  onPinchEnd=function() g.drag=false end}
 H.root:AddChild(inputLayer)
 local safe=UI.SafeAreaView{position="absolute",left=0,top=0,right=0,bottom=0,pointerEvents="box-none",children={}}
 H.root:AddChild(safe)
 local play=UI.Panel{position="absolute",left=0,right=0,top=0,bottom=0,pointerEvents="box-none",visible=false,children={}}
 safe:AddChild(play);H.refs.play=play
 local resources,icons={},{}
 for _,k in ipairs(D.resources) do
  local picture=icon("resources",k,30);icons[#icons+1]=picture
  resources[#resources+1]=panel{flexGrow=1,flexBasis=0,backgroundColor=T.surface,borderRadius=10,borderWidth=0,boxShadow={},paddingHorizontal=6,pointerEvents="none",flexDirection="row",gap=4,alignItems="center",children={picture,UI.Panel{flexGrow=1,flexBasis=0,gap=1,children={label(D.names[k],8,T.muted,{lineHeight=1}),textRef(k,"0",15,k=="food" and T.gold or T.paper,{lineHeight=1})}}}}
 end
 H.refs.resourceMetrics=resources;H.refs.resourceIcons=icons
 local brand=UI.Panel{width=172,gap=3,justifyContent="center",pointerEvents="none",children={label("细胞战争",21),label("C E L L   W A R",8,T.teal)}}
 H.refs.brand=brand;H.refs.brandSub=brand:GetChildAt(2)
 local grid=row(resources,{flexGrow=1,flexBasis=0,gap=4});H.refs.resourceGrid=grid
 local clockBox=UI.Panel{width=176,gap=5,pointerEvents="none",children={textRef("clock","第1天 · 平衡",12,T.gold),textRef("phase","活跃 · 余烬胞群",10,T.muted)}};H.refs.clockBox=clockBox
 local top=UI.Panel{position="absolute",left=12,right=12,top=10,height=82,padding=10,flexDirection="row",gap=18,alignItems="center",children={brand,grid,clockBox}}
 local cards={};H.refs.zones={}
 for i,z in ipairs(require("war.CampaignData").forState(g.state).zones) do
  local title=label(z.name,11,T.paper,{lineHeight=1});local status=label("",10,T.teal,{lineHeight=1});local bar=UI.ProgressBar{value=100,max=100,height=4,fillColor=T.teal}
  local card=panel{flexGrow=1,flexBasis=0,padding=7,gap=4,borderRadius=14,pointerEvents="none",children={title,status,bar}}
  FX.spotlight(card)
  H.refs.zones[i]={status=status,bar=bar,title=title,card=card};cards[#cards+1]=card
 end
 local nasalCards=row(cards,{width="100%",flexGrow=1});H.refs.nasalCards=nasalCards
 local nasalGrid=UI.Panel{flexGrow=1,flexBasis=0,gap=4,visible=false,children={nasalCards,textRef("nasalSupply","补给 4 / 6 · 调援 +2 白细胞",10,T.teal,{whiteSpace="normal",maxLines=2,lineHeight=1.1})}}
 H.refs.nasalGrid=nasalGrid;top:AddChild(nasalGrid)
 H.refs.top=top;play:AddChild(top)
 Brain.attach(g,H,top,play)
 Battle.create(g,H,play)
 local pause=btn("Ⅱ 暂停",function() g.paused=not g.paused end,92);H.refs.pause=pause
 local speed=btn("1×",function() g.speed=g.speed==1 and 2 or 1 end,44);H.refs.speed=speed
 local fog=btn("全图",function() if g.state.campaign then R.nasalOverview(g) elseif g.state.anatomyVersion==3 then H.mapMenu(g) else I.toggleFog(g) end end,60);H.refs.fog=fog
 local toolbar=row({pause,speed,fog,btn("地图",function() H.mapMenu(g) end,60),btn("存档",function() H.saveMenu(g) end,60),btn("?",function() H.help(g) end,44)},{position="absolute",right=12,top=110,gap=5});H.refs.toolbar=toolbar;play:AddChild(toolbar)
 local goal=panel{position="absolute",left=12,top=110,width=410,padding=12,gap=6,pointerEvents="none",children={
  textRef("goal","目标 · 维持稳态，击败两个敌群",12,T.paper),
  textRef("tutorial","01 选择一名红细胞",11,T.teal,{whiteSpace="normal",maxLines=2}),
  UI.ProgressBar{value=1,max=6,height=3,fillColor=T.teal},
 }};H.refs.goalBox=goal;H.refs.tutorialProgress=goal:GetChildAt(3);play:AddChild(goal)
 FX.spotlight(goal)
 local zoom=row({btn("＋",function() R.zoom(g,1.2) end,44),btn("－",function() R.zoom(g,1/1.2) end,44),btn("返回首页",function() if g.returnHome then g.returnHome() end end,78),btn("通路",function() H.survey(g) end,60)},{position="absolute",left=12,bottom=194,gap=5});H.refs.zoomTools=zoom;H.refs.surveyButton=zoom:GetChildAt(4);play:AddChild(zoom)
 local sidebar=panel{position="absolute",left=12,top=188,bottom=196,width=390,padding=14,gap=10,zIndex=5,visible=false};H.refs.sidebar=sidebar;play:AddChild(sidebar)
 local portrait=UI.Panel{width=66,height=66,pointerEvents="none"}
 ---@param vg NVGContextWrapper
 function portrait:Render(vg)
  local l=self:GetAbsoluteLayout();local ids=I.ids(g);local e=ids[1] and g.state.entities[ids[1]]
  if e and e.category=="unit" then Cells.draw(vg,e.kind,1,l.x+l.w/2,l.y+l.h/2,math.min(l.w,l.h)/(Cells.radius(e.kind)*2.7),g.flowTime,0)
  else Art.draw(vg,"buildings",e and e.kind or "emblem",l.x+l.w/2,l.y+l.h/2,math.min(l.w,l.h)) end
 end
 H.refs.portrait=portrait
 local hp=UI.ProgressBar{height=4,value=1,max=1,fillColor=T.teal};H.refs.hp=hp
 local production=UI.ProgressBar{height=3,value=0,max=1,fillColor=T.gold};H.refs.production=production
 local selectedText=UI.Panel{flexGrow=1,flexBasis=0,gap=4,children={textRef("selected","胞群指挥",16),hp,textRef("selectedDetail","选中细胞查看状态",10,T.muted),textRef("selectedStats","人口 9 / 10",10,T.gold),textRef("queue","命令队列\n点击目标下令",9,T.muted,{whiteSpace="normal",maxLines=6,lineHeight=1.1}),production}}
 H.refs.selectionText=selectedText
 local selected=panel{flexDirection="row",width=244,height="100%",gap=8,pointerEvents="none",children={portrait,selectedText}};H.refs.selectionCard=selected
 local commands=panel{flexGrow=1,flexBasis=0,gap=6,padding=6};H.refs.commands=commands
 local map=UI.Panel{flexGrow=1,flexBasis=0,width="100%",onTap=function(e)
  g.camera.x,g.camera.y=R.mapPoint(H.refs.map:GetAbsoluteLayout(),e.x,e.y,g.state)
 end}
 ---@param vg NVGContextWrapper
 function map:Render(vg) R.minimap(vg,g,self:GetAbsoluteLayout()) end
 H.refs.map=map
 local mapShell=panel{width=150,padding=8,gap=4,children={label("内域导航  /  M",9,T.quiet),map}};H.refs.mapShell=mapShell
 local dock=UI.Panel{position="absolute",left=12,right=12,bottom=12,height=168,padding=12,flexDirection="row",gap=12,pointerEvents="box-none",children={selected,commands,mapShell}};H.refs.dock=dock;play:AddChild(dock)
 local notice=panel{position="absolute",bottom=194,left=230,right=12,paddingHorizontal=14,paddingVertical=9,visible=false,pointerEvents="none",borderColor={125,226,211,85},children={textRef("notice","",12,T.paper,{textAlign="center",whiteSpace="normal",maxLines=2})}}
 H.refs.noticeBox=notice;H.refs.notice=notice:GetChildAt(1);play:AddChild(notice)
 -- Full-bleed artwork sits outside the safe area; all interactive menu content stays inside it.
 local menu=UI.Panel{position="absolute",left=0,right=0,top=0,bottom=0,backgroundImage=Art.hero,backgroundFit="cover",children={}}
 H.refs.menu=menu;H.root:AddChild(menu)
 menu:AddChild(UI.Panel{position="absolute",left=0,right=0,top=0,bottom=0,backgroundGradient={direction="to-right",from={244,247,255,246},to={233,237,253,150}},pointerEvents="none"})
 local menuSafe=UI.SafeAreaView{position="absolute",left=0,right=0,top=0,bottom=0,pointerEvents="box-none",children={}}
 menu:AddChild(menuSafe)
 local content=UI.Panel{width="56%",maxWidth=700,gap=18,paddingLeft=48,paddingTop=56,paddingBottom=30,children={
  row({icon("buildings","emblem",44),label("微观生命  /  宏观战场",11,T.teal,{letterSpacing=2})}),
  textRef("menuTitle","细胞战争",64,T.paper),
  label("一具身体，就是整个世界。",20,T.paper,{whiteSpace="normal",maxLines=2}),
  label("病毒已侵入气管，下段屏障需要你的守卫。",13,T.muted,{whiteSpace="normal",maxLines=2}),
  label("调动免疫细胞，守住防线，再反攻夺回气管。",13,T.muted,{whiteSpace="normal",maxLines=3}),
  row({label("守卫",11,T.gold),label("/",11,T.quiet),label("调援",11,T.gold),label("/",11,T.quiet),label("夺回",11,T.gold)},{marginTop=8}),
  btn("守卫气管  →",function() g.newGame("campaign");menu:SetVisible(false);H.refs.play:SetVisible(true) end,230,true,{height=56,fontSize=16}),
  row({btn("全身沙盒",function() g.newGame("sandbox");menu:SetVisible(false);H.refs.play:SetVisible(true) end,126),btn("继续记录",function() H.saveMenu(g) end,126),btn("指挥手册",function() H.help(g) end,126)},{flexWrap="wrap"}),
  label("三块组织区域 · 自动争夺 · 战术暂停 · 失败重试",10,T.muted,{whiteSpace="normal",maxLines=3}),
 }}
 H.refs.menuContent=content
 H.refs.menuNarrative1=content:GetChildAt(4);H.refs.menuNarrative2=content:GetChildAt(5);H.refs.menuModes=content:GetChildAt(6);H.refs.menuSummary=content:GetChildAt(9)
 menuSafe:AddChild(UI.ScrollView{width="100%",height="100%",scrollY=true,children={content}})
 local modal=UI.Panel{position="absolute",left=0,right=0,top=0,bottom=0,backgroundColor={206,216,237,220},children={}}
 local modalSafe=UI.SafeAreaView{position="absolute",left=0,right=0,top=0,bottom=0,justifyContent="center",alignItems="center",visible=false,children={}}
 -- The scrim shares modal visibility; its safe-area content is the exposed modal host.
 H.refs.modalScrim=modal;modal:SetVisible(false);modal:AddChild(modalSafe);H.refs.modal=modalSafe
 H.root:AddChild(modal)
 UI.SetRoot(H.root)
 g.openMap=function() H.mapMenu(g) end;g.refreshSidebar=function() H.sidebar(g) end;g.closeModal=function() H.closeModal(g) end
 H.layout(g)
end
function H.update(g,dt)
 H.layout(g)
 if H.uiState~=g.state then H.uiCounters={};H.uiState=g.state;H.wasStarted=false end
 FX.update(H,dt)
 if g.started and not H.wasStarted then
  if g.state.campaign then Battle.enter(H) else FX.enter(H.refs.top,8);FX.enter(H.refs.toolbar,6);FX.enter(H.refs.goalBox,10);FX.enter(H.refs.dock,16) end
 end
 H.wasStarted=g.started
 Brain.update(g,H,dt)
 H.refs.modalScrim:SetVisible(g.modal)
 H.refs.play:SetVisible(g.started);H.refs.menu:SetVisible(not g.started)
 H.tick=H.tick+dt;if H.tick<.2 then return end;H.tick=0
 local s,refs=g.state,H.refs;local day,fraction,season,phase=V.clock(s)
 if s.campaign then Battle.update(H,g) end
 for _,k in ipairs(D.resources) do
  local amount=math.floor(E.stock(s,1,k));FX.counter(H,k,refs[k],amount);refs[k]:SetStyle{fontColor=amount==0 and T.danger or k=="food" and T.gold or T.paper}
 end
 refs.clock:SetText("第"..day.."天 · "..D.seasons[season])
 local key=U.key(g.camera.x,g.camera.y)
 local region=(s.anatomyVersion==3 or g.fogDisabled or s.factions[1].seen[key]) and D.biomes[W.terrain(s,math.floor(g.camera.x),math.floor(g.camera.y))].name or "未探索"
 refs.phase:SetText(phase.." · "..region)
  if s.campaign then local map=require("war.MapRegistry").stage(require("war.MapRegistry").currentId(s));if map then region=map.name.." / "..map.id end end
  if s.campaign then
  local ev=s.campaign.event;local r=s.campaign.reinforcements;local N=require("war.CampaignData").forState(s)
  for i,z in ipairs(ev.zones) do
   ---@type number[]
   local c=z.contested and T.gold or z.owner==2 and T.danger or T.teal
   refs.zones[i].title:SetText(i.." · "..N.zones[i].name)
   refs.zones[i].status:SetText(require("war.Territory").status(z).." "..math.floor(math.abs(z.control)).."%");refs.zones[i].status:SetStyle{fontColor=c}
   refs.zones[i].card:SetStyle{borderColor={c[1],c[2],c[3],65}}
   refs.zones[i].bar:SetValue((z.control+100)*.5);refs.zones[i].bar:SetStyle{fillColor=c}
  end
  local waiting=0;for _,q in ipairs(r.queue) do waiting=waiting+q.remaining end
  refs.nasalSupply:SetText(battleText(s,"入侵 "..ev.wave.." / 3 波 · 补给 "..r.supply.." / "..N.supply.max.." · "..(ev.status=="completed" and "鼻腔已夺回 · 咽喉尚未开放" or "回复 "..math.ceil(N.supply.period-r.regen).."秒 · "..(r.cooldown>0 and "调援冷却 "..math.ceil(r.cooldown).."秒" or "可调援")..(waiting>0 and " · "..waiting.."援军调入中" or ""))))
  local b=refs.commandButtons.reinforce;if b then local ok,why=require("war.Reinforcements").available(s);b:SetDisabled(not ok);b:SetText(ok and "调援 +2" or ev.status=="completed" and "战斗结束" or r.cooldown>0 and "冷却 "..math.ceil(r.cooldown).."s" or why) end
 end
 refs.fog:SetText(s.campaign and battleText(s,"鼻腔图") or g.fogDisabled and "迷雾" or "全图");T.active(refs.fog,not s.campaign and g.fogDisabled)
 if refs.mapFog then refs.mapFog:SetText(s.anatomyVersion==3 and "全身定位" or g.fogDisabled and "恢复迷雾" or "查看全图");T.active(refs.mapFog,g.fogDisabled) end
 refs.pause:SetText(g.paused and "▶ 继续" or "Ⅱ 暂停");T.active(refs.pause,g.paused);refs.speed:SetText(g.speed.."×")
 for tab,b in pairs(refs.tabButtons) do T.active(b,g.tab==tab) end
 for name,b in pairs(refs.commandButtons) do
  if name=="box" then T.active(b,g.box) elseif name=="append" then T.active(b,g.append)
  elseif name=="move" or name=="attackmove" or name=="guard" or name=="rally" then T.active(b,g.mode==name) end
 end
 local ids=I.ids(g);local inspect=g.inspectTarget
 if inspect and not U.alive(inspect) then g.inspectTarget=false;inspect=false end
 local e=(inspect and inspect.faction~=1 and inspect) or (ids[1] and s.entities[ids[1]]);local pop,cap=E.population(s,1,false)
 refs.production:SetVisible(false)
 if e then
 local d=e.category=="unit" and D.units[e.kind] or D.buildings[e.kind]
  local combat=(d.damage and d.range) and (" · 攻击 "..string.format("%.1f",d.range).." 格") or " · 不具备攻击能力"
  local enemy=e.faction~=1
  refs.selected:SetText(enemy and "敌方 · "..d.name or #ids>1 and (#ids.."个单位已选中") or e.salvaged and "残存储运囊" or d.name)
  refs.hp:SetValue(e.hp/e.maxHp);refs.hp:SetStyle{fillColor=e.hp/e.maxHp<.3 and T.danger or T.teal}
  if enemy then
   refs.selectedDetail:SetText("生命 "..math.floor(e.hp).."/"..e.maxHp..((d.damage and d.range) and (" · 攻击 "..string.format("%.1f",d.range).." 格 · 伤害 "..math.floor(d.damage)) or " · 不具备攻击能力"))
   refs.selectedStats:SetText("红圈=攻击范围 · 点击己方部队后可下令攻击")
   refs.queue:SetText("敌方单位 · 当前可见")
 elseif e.category=="unit" then
   refs.selectedDetail:SetText("生命 "..math.floor(e.hp).."/"..e.maxHp..combat..(s.campaign and "" or " · 饱食 "..math.floor(e.satiety)))
   local scoutInfo=e.kind=="scout" and ("瞭望 "..math.floor(d.vision or 0).." 格 · 敌方情报") or ""
   refs.selectedStats:SetText(s.campaign and (scoutInfo..(scoutInfo~="" and " · " or "").."免疫兵力 "..pop.." / "..cap.." · 红圈=反击范围") or scoutInfo..(scoutInfo~="" and " · " or "").."体温 "..math.floor(e.temp).."° · 精神 "..math.floor(e.sanity))
   refs.queue:SetText(e.pathFailed and "命令队列\n道路不通 · 重新下令\n"..orderQueueText(e):gsub("^命令队列\n","") or orderQueueText(e))
  else
   refs.selectedDetail:SetText("耐久 "..math.floor(e.hp).."/"..e.maxHp..combat)
   refs.selectedStats:SetText(e.complete and "人口 "..pop.."/"..cap.." · T"..s.factions[1].tier or "生长中 · "..math.floor(e.progress*100).."%")
   local q=e.queue[1];local _,pending=M.pending(s);local waiting=pending[e.id] or 0
   refs.queue:SetText(q and ((q.unit and D.units[q.unit].name or D.tech[q.tech].name).." · "..math.ceil(q.remaining).."秒 · "..(#e.queue+waiting).."项") or waiting>0 and "待执行 · "..waiting.."项生产命令" or "空闲 · 点击训练 / 科技")
   if q or not e.complete then refs.production:SetVisible(true);refs.production:SetValue(q and 1-q.remaining/q.total or e.progress) end
  end
 else
  refs.selected:SetText(s.campaign and "免疫守卫" or "余烬胞群");refs.hp:SetValue(cap>0 and pop/cap or 0);refs.hp:SetStyle{fillColor=pop>=cap and T.gold or T.teal}
  refs.selectedDetail:SetText("人口 "..pop.." / "..cap..(s.campaign and " · 免疫部队" or " · 科技 T"..s.factions[1].tier))
  refs.selectedStats:SetText(s.campaign and battleText(s,"守住后鼻屏障 · 夺回鼻腔") or phase.." · "..region);refs.queue:SetText(Save.status)
 end
 local tutorials={"01 选择红细胞 · 点击单位或红细胞按钮","02 点击蛋白束 / 钙晶，采集并送回胞巢","03 建造第二座荧光腺，扩大休息期安全区","04 建造培养床，安排红细胞生产食物","05 建造分裂兵巢，训练第一支军队","06 探索器官 · 发展科技 · 进攻敌群"}
 refs.tutorial:SetText(tutorials[s.tutorial] or tutorials[6]);refs.tutorialProgress:SetValue(math.min(s.tutorial or 1,6))
 refs.goal:SetText(s.outcome=="victory" and "内域已控制 · 自由探索仍在继续" or s.outcome=="defeat" and "胞群已失去活性 · 可读取记录" or "目标 · 维持稳态，击败两个敌群")
 if s.campaign then
  local ev=s.campaign.event
  refs.goal:SetText(battleText(s,ev.status=="failed" and "鼻腔失守 · 重试本次事件" or ev.status=="completed" and "鼻腔已夺回 · 下一事件尚未开放" or "鼻腔事件 · 守住后鼻屏障"))
  refs.tutorial:SetText(ev.status=="completed" and "已完成 1 / "..#require("war.CampaignData").forState(s).stages.." · 保留部队与记录" or ev.secure>0 and "全域净化 · 稳固 "..math.floor(ev.secure).." / 20 秒" or "入侵 "..ev.wave.." / 3 波 · "..(ev.phase=="defend" and "选择部队、守卫与调援" or "反攻夺回三块组织区域"))
  refs.tutorialProgress:SetValue(ev.wave*2)
 end
 local modes={move="移动",attackmove="进攻移动",guard="驻守",rally="集结点"}
 local notice=g.placement and "放置"..D.buildings[g.placement].name.." · 点击地图确认 / Esc取消" or g.mode and (modes[g.mode] or "指令").." · 点击地图选择目标 / Esc取消" or s.messageTime>0 and s.message or g.paused and "战术暂停 · 命令将在继续后执行" or ""
 -- Campaign notices use the battle HUD toast under the status bar; the sandbox keeps the dock toast.
 local box,text,battle=refs.noticeBox,refs.notice,H.battle
 if battle then
  if s.campaign then box,text=battle.noticeBox,battle.notice;refs.noticeBox:SetVisible(false) else battle.noticeBox:SetVisible(false) end
 end
 if notice~="" and notice~=H.lastNotice then FX.enter(box,8) end
 H.lastNotice=notice;text:SetText(notice);box:SetVisible(notice~="")
 local units=0;for _,u in pairs(s.entities) do if u.category=="unit" and u.faction>0 and U.alive(u) then units=units+1 end end
 refs.fps:SetText(string.format("%d FPS · %d单位",g.fps or 0,units))
 if H.lastTab~=g.tab then H.sidebar(g) end
 for _,card in ipairs(H.cards) do
  local ok,why=M.gate(g,card.tab,card.kind);card.status:SetText((ok and "＋ " or why=="已完成" and "✓ " or "· ")..why)
  card.status:SetStyle{fontColor=ok and T.teal or why=="已完成" and T.blue or T.gold}
  card.widget:SetStyle{borderColor=ok and T.border or {152,132,96,75}}
 end
 if refs.saveStatus then
  refs.saveStatus:SetText(Save.status)
  local failed=Save.status:find("失败") or Save.status:find("损坏") or Save.status:find("超时") or Save.status:find("未连接") or Save.status:find("无响应")
  refs.saveStatus:SetStyle{fontColor=failed and T.danger or T.teal}
  for slot,summary in pairs(refs.saveSlots) do
   local known=Save.slots[slot]
   summary:SetText(known and "已记录 · 第"..known.day.."天" or slot==0 and "每个黎明自动更新" or "独立槽位 · 可读取已有记录")
   summary:SetStyle{fontColor=known and T.teal or T.muted}
  end
  for _,b in ipairs(refs.saveActions) do b:SetDisabled(Save.busy) end
  refs.saveRetry:SetDisabled(Save.busy or not Save.pending)
 end
 if s.campaign and s.campaign.event.status=="failed" and not g.defeatShown then
  g.defeatShown=true;H.dialog(g,"鼻腔失守",{"病毒已完全夺下后鼻屏障。","重试会恢复本次事件开始时的部队、补给和组织状态。此前完成记录保持。"},{{"重试本次事件",function() local q=require("war.Campaign").retry(g.state);if q then H.closeModal(g);g.replaceState(q) end end,160,true},{"读取记录",function() H.saveMenu(g) end,120}})
 elseif s.campaign and s.campaign.event.status=="completed" and not g.victoryShown then
  g.victoryShown=true;H.dialog(g,"鼻腔已夺回",{"三块组织区域已经净化，后鼻屏障守卫成功。","下一事件：咽喉防线 · 尚未开放。部队留在当前人体，后续将逐步解锁全域。"},{{"继续指挥",function() H.closeModal(g) end,130,true},{"人体进程",function() H.campaignMenu(g) end,130},{"保存记录",function() H.saveMenu(g) end,130}})
 elseif not s.campaign and s.outcome=="defeat" and not g.defeatShown then
  g.defeatShown=true;H.dialog(g,"最后一处荧光熄灭了",{"你的单位和生产建筑已全部损失。","读取已有记录，再次点亮这片内域。"},{{"读取记录",function() H.saveMenu(g) end,140,true},{"建立新胞群",function() g.newGame();H.closeModal(g) end,150}})
 elseif not s.campaign and s.outcome=="victory" and not g.victoryShown then
  g.victoryShown=true;H.dialog(g,"生命的边界，已被拓宽",{"两个敌群已失去战斗能力。余烬胞群控制了内域。","继续探索与扩建，或将这段远征保存为记录。"},{{"继续探索",function() H.closeModal(g) end,140,true},{"保存记录",function() H.saveMenu(g) end,140}})
 end
end
return H
