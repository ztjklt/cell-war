local UI=require("urhox-libs/UI")
local D,U,R,I,C,E,V,Save=require("war.Data"),require("war.Util"),require("war.Render"),require("war.Input"),require("war.Commands"),require("war.Economy"),require("war.Survival"),require("war.Save")
local Cells,W=require("war.Cells"),require("war.World")
local BodyArt=require("war.BodyArt")
local H={root=false,refs={},lastTab=false,lastSelection="",tick=0}
local T={ink={24,32,28,245},surface={38,46,37,242},paper={224,217,187,255},muted={160,166,141,255},gold={200,167,103,255},teal={104,163,139,255},border={99,109,79,160}}
local function label(text,size,color,props)
 local p={text=text,fontSize=size or 13,fontColor=color or T.paper,maxLines=1};for k,v in pairs(props or {}) do p[k]=v end return UI.Label(p)
end
local function panel(props)
 local p={backgroundColor=T.ink,borderWidth=1,borderColor=T.border,borderRadius=3};for k,v in pairs(props) do p[k]=v end return UI.Panel(p)
end
local function btn(text,action,width,accent)
 return UI.Button{text=text,height=38,width=width or 68,fontSize=12,borderRadius=2,padding=5,backgroundColor=accent and {83,117,86,255} or {47,57,45,255},textColor=T.paper,hoverBackgroundColor={89,109,78,255},borderWidth=1,borderColor=T.border,onClick=action}
end
local function textRef(name,text,size,color) local l=label(text,size,color);H.refs[name]=l;return l end
function H.toggle(g,tab) g.tab=g.tab==tab and false or tab;g.placement=false;H.sidebar(g) end
function H.closeModal(g) if H.refs.modal then H.refs.modal:RemoveAllChildren();H.refs.modal:SetVisible(false) end;g.modal=false end
function H.dialog(g,title,lines,buttons)
 H.closeModal(g);g.modal=true;local rows={label(title,25,T.paper,{marginBottom=8})}
 for _,text in ipairs(lines) do rows[#rows+1]=label(text,13,T.muted,{flexShrink=1}) end
 local b={};for _,spec in ipairs(buttons or {}) do b[#b+1]=btn(spec[1],spec[2],spec[3] or 130,spec[4]) end
 rows[#rows+1]=UI.Panel{flexDirection="row",flexWrap="wrap",gap=8,marginTop=18,children=b}
 H.refs.modal:AddChild(panel{width="90%",maxWidth=540,padding=26,gap=8,children=rows});H.refs.modal:SetVisible(true)
end
function H.help(g)
 H.dialog(g,"指挥手册",{
  "活跃期采集、培育与扩建；休息期保持荧光和补给。",
  "手机：单击选兵，拖动移镜头，双指缩放；框选按钮切换选区。",
  "电脑：拖动框选，右键下令；Shift追加命令，方向键移镜头。",
  "点击资源采集、培养床培育、未完工建筑施工、着火建筑灭火。",
  "空格战术暂停；A进攻移动，S停止，R撤退，B建造，H回营。",
  "Ctrl+1/2/3保存编队，1/2/3选编队；手机编队按钮长按保存。",
  "核心胞巢训练工细胞；分裂兵巢、毒囊孵化池和巨噬孵化池训练对应军队。",
  "主基地被毁可重建；单位和生产建筑全部损失才结束。",
 },{{"返回胞群",function() H.closeModal(g) end,160,true}})
end
function H.saveMenu(g)
 local lines={Save.status,"手动槽位保留你的选择；自动槽位在每个黎明更新。","以“已保存”提示为准；保存失败时游戏继续，可稍后重试。"}
 local buttons={}
 for slot=1,3 do local k=slot;buttons[#buttons+1]={"保存 "..slot,function() Save.write(g.state,k);H.closeModal(g) end,100};buttons[#buttons+1]={"读取 "..slot,function() Save.read(k,function(state,msg) if state then g.replaceState(state);H.closeModal(g) else U.message(g.state,msg);H.closeModal(g) end end) end,100} end
 buttons[#buttons+1]={"读自动槽",function() Save.read(0,function(state,msg) if state then g.replaceState(state);H.closeModal(g) else U.message(g.state,msg);H.closeModal(g) end end) end,105}
 buttons[#buttons+1]={"重试保存",function() Save.retry(g.state);H.closeModal(g) end,105}
 buttons[#buttons+1]={"返回",function() H.closeModal(g) end,90}
 H.dialog(g,"胞群记录",lines,buttons)
end
function H.mapMenu(g)
 H.closeModal(g);g.modal=true
 local vw,vh=UI.GetViewportSize();local overview=false;local toggle
 local map=UI.Panel{flexGrow=1,flexBasis=0,height="100%",backgroundColor={23,31,27,255},onTap=function(e)
  g.camera.x,g.camera.y=R.mapPoint(H.refs.fullMap:GetAbsoluteLayout(),e.x,e.y);H.closeModal(g)
 end}
 H.refs.fullMap=map
 map.Render=function(self,vg) R.minimap(vg,g,self:GetAbsoluteLayout(),overview) end
 local legendRows={}
 for _,biome in ipairs(D.biomes) do local c=biome.color
  legendRows[#legendRows+1]=UI.Panel{height=16,flexDirection="row",gap=7,alignItems="center",children={UI.Panel{width=11,height=11,backgroundColor={c[1],c[2],c[3],255}},label(biome.name,11,T.paper)}}
 end
 toggle=btn("组织总览",function() overview=not overview;toggle:SetText(overview and "探索地图" or "组织总览") end,110)
 local box=panel{width="92%",maxWidth=960,height=math.min(vh*.91,780),padding=14,gap=8,children={
  UI.Panel{height=30,flexDirection="row",justifyContent="space-between",children={label("人体内域 · 1024 × 1024",21,T.paper),btn("×",function() H.closeModal(g) end,35)}},
  label("点击地图定位镜头 · 组织总览不显示未发现的敌方 · M打开地图",11,T.muted),
  UI.Panel{flexGrow=1,flexBasis=0,flexDirection="row",gap=12,children={map,UI.ScrollView{width=150,scrollY=true,children={UI.Panel{gap=3,children=legendRows}}}}},
  UI.Panel{height=38,flexDirection="row",gap=8,children={toggle,btn("返回胞群",function() R.home(g);H.closeModal(g) end,110,true),btn("继续探索",function() H.closeModal(g) end,110)}},
 }}
 H.refs.modal:AddChild(box);H.refs.modal:SetVisible(true)
end
function H.card(title,desc,cost,image,action,disabled)
 local detail={label(title,15,T.paper),label(desc,11,T.muted),label(cost,10,T.gold)}
 local children={}
 if type(image)=="table" and image.cell then
  local icon=UI.Panel{width=62,height=66,pointerEvents="none"}
  icon.Render=function(self,vg) local l=self:GetAbsoluteLayout();Cells.draw(vg,image.cell,1,l.x+l.w*.5,l.y+l.h*.78,.95,0,0) end
  children[#children+1]=icon
 elseif type(image)=="table" and image.building then
  local icon=UI.Panel{width=62,height=66,pointerEvents="none"}
  icon.Render=function(self,vg) local l=self:GetAbsoluteLayout();local old=R.vg;R.vg=vg;BodyArt.structure(R,{zoom=.58},{kind=image.building,faction=1,complete=true,lit=true,fire=0},l.x+l.w*.5,l.y+l.h*.78);R.vg=old end
  children[#children+1]=icon
 elseif image then children[#children+1]=UI.Panel{width=62,height=66,backgroundImage=image,backgroundFit="contain",pointerEvents="none"} end
 children[#children+1]=UI.Panel{flexGrow=1,flexBasis=0,gap=5,pointerEvents="none",children=detail}
 local card=panel{padding=8,height=88,flexDirection="row",alignItems="center",gap=8,backgroundColor=disabled and {37,42,34,255} or T.surface,onTap=function() action() end,children=children}
 return card
end
function H.sidebar(g)
 local host=H.refs.sidebar;if not host then return end;host:RemoveAllChildren();H.lastTab=g.tab;H.lastSelection=""
 if not g.tab then host:SetVisible(false);return end
 host:SetVisible(true)
 local title=({build="胞群蓝图",train="军队与生产",tech="研究与发展"})[g.tab] or "胞群蓝图"
 host:AddChild(UI.Panel{height=40,flexDirection="row",justifyContent="space-between",alignItems="center",children={label(title,18),btn("×",function() g.tab=false;g.placement=false;H.sidebar(g) end,36)}})
 local list=UI.ScrollView{flexGrow=1,flexBasis=0,scrollY=true,children={}}
 local body=UI.Panel{gap=6,paddingRight=4}

 if g.tab=="build" then
  body:AddChild(label("先选工细胞，再选蓝图并点击地图",11,T.muted))
  for _,kind in ipairs(D.buildOrder) do local k=kind;local d=D.buildings[k];local image={building=k}
   body:AddChild(H.card(d.name.."  ·  T"..d.tier,d.desc,U.costText(d.cost),image,function()
    local worker=false;for _,id in ipairs(I.ids(g)) do local e=g.state.entities[id];if e.kind=="worker" then worker=true end end
    if not worker then I.selectKind(g,"worker") end
    if g.state.factions[1].tier<d.tier then U.message(g.state,"需要科技等级 "..d.tier);return end
    g.placement=k;g.mode=false;g.tab=false;H.sidebar(g);U.message(g.state,"放置"..d.name.." · 点击地图确认 / Esc取消")
   end,g.state.factions[1].tier<d.tier))
  end
 elseif g.tab=="train" then
  for _,kind in ipairs(D.unitOrder) do local k=kind;local d=D.units[k]
   body:AddChild(H.card(d.name.."  ·  "..d.pop.."人口",D.buildings[d.at].name.." / "..d.train.."秒 / T"..d.tier,U.costText(d.cost),{cell=k},function()
    local selected=I.ids(g)[1];local b=selected and g.state.entities[selected]
    if not b or b.kind~=d.at or not b.complete then b=U.nearest(g.state,g.camera.x,g.camera.y,function(e) return e.faction==1 and e.kind==d.at and e.complete end) end
    if b then C.submit(g.state,{kind="train",faction=1,target=b.id,unit=k});U.message(g.state,"训练命令已下达"..(g.paused and "，恢复后执行" or "")) else U.message(g.state,"需要建造"..D.buildings[d.at].name) end
   end,g.state.factions[1].tier<d.tier))
  end
 elseif g.tab=="tech" then
  body:AddChild(label("当前科技：T"..g.state.factions[1].tier,13,T.gold))
  for _,kind in ipairs({"tier2","tier3","storage","insulation","weapons"}) do local k=kind;local d=D.tech[k];local done=g.state.factions[1].tech[k]
   body:AddChild(H.card(d.name..(done and " · 已完成" or ""),d.desc,U.costText(d.cost),false,function()
    local b=U.nearest(g.state,g.camera.x,g.camera.y,function(e) return e.faction==1 and e.kind=="lab" and e.complete end)
    if b then C.submit(g.state,{kind="research",faction=1,target=b.id,tech=k});U.message(g.state,"研究命令已下达") else U.message(g.state,"需要核酸研究站") end
   end,done))
  end
 end
 list:AddChild(body);host:AddChild(list)
end
function H.create(g)
 UI.Init{theme="default-dark",scale=UI.Scale.DEFAULT}
 H.refs={};H.root=UI.Panel{width="100%",height="100%",pointerEvents="box-none",children={}}
 local inputLayer=UI.Panel{id="worldInput",position="absolute",left=0,top=0,right=0,bottom=0,
  onPointerDown=function(e) I.down(g,e) end,onPointerMove=function(e) I.move(g,e) end,onPointerUp=function(e) I.up(g,e) end,onPointerCancel=function() g.drag=false end,
  onPinchStart=function() g.drag=false;g.pinchStart=g.zoom end,
  onPinchMove=function(e) local factor=UI.GetScale()/graphics:GetDPR();local scale=(g.pinchStart or g.zoom)*e.scale/g.zoom;R.zoom(g,scale,e.centerX*factor,e.centerY*factor) end,
  onPinchEnd=function() g.drag=false end}
 H.root:AddChild(inputLayer)
 local safe=UI.SafeAreaView{position="absolute",left=0,top=0,right=0,bottom=0,pointerEvents="box-none",children={}}
 H.root:AddChild(safe)
 local resources={}
 for _,k in ipairs(D.resources) do
  resources[#resources+1]=UI.Panel{flexGrow=1,gap=2,pointerEvents="none",children={label(D.names[k],10,T.muted),textRef(k,"0",15,k=="food" and T.gold or T.paper)}}
 end
 local top=panel{position="absolute",left=12,right=12,top=10,height=74,padding=10,flexDirection="row",gap=16,alignItems="center",children={
  UI.Panel{width=142,flexShrink=0,pointerEvents="none",gap=4,children={label("细胞战争",20,T.paper),label("CELL  WAR",8,T.gold)}},
  UI.Panel{flexGrow=1,flexBasis=0,flexDirection="row",gap=8,children=resources},
  UI.Panel{width=184,flexShrink=0,gap=4,pointerEvents="none",children={textRef("clock","第1天 · 平衡",12,T.gold),textRef("phase","活跃 · 余烬胞群",10,T.muted)}},
 }}
 safe:AddChild(top)
 local pause=btn("Ⅱ 暂停",function() g.paused=not g.paused end,88,true);H.refs.pause=pause
 local speed=btn("1×",function() g.speed=g.speed==1 and 2 or 1 end,48);H.refs.speed=speed
 safe:AddChild(UI.Panel{position="absolute",right=12,top=94,flexDirection="row",gap=6,children={pause,speed,btn("地图",function() H.mapMenu(g) end,56),btn("存档",function() H.saveMenu(g) end,56),btn("?",function() H.help(g) end,38)}})
 safe:AddChild(panel{position="absolute",left=12,top=94,padding=8,gap=4,pointerEvents="none",maxWidth=380,children={textRef("goal","目标 · 生存、扩张，击败两个敌营",12,T.paper),textRef("tutorial","01 选择一名工细胞",11,T.gold)}})
 safe:AddChild(UI.Panel{position="absolute",left=12,bottom=157,flexDirection="row",gap=6,children={btn("＋",function() R.zoom(g,1.2) end,36),btn("－",function() R.zoom(g,1/1.2) end,36),btn("回营",function() R.home(g) end,56)}})
 local sidebar=panel{position="absolute",left=12,top=160,bottom=205,width=338,padding=12,gap=8,visible=false};H.refs.sidebar=sidebar;safe:AddChild(sidebar)
 local selected=panel{width=226,padding=12,gap=5,children={textRef("selected","胞群指挥",17,T.paper),textRef("selectedDetail","选中单位查看状态",11,T.muted),textRef("selectedStats","人口 9 / 10",11,T.gold),textRef("queue","点击资源可采集",10,T.muted)}}
 H.refs.selectionCard=selected
 local boxes=btn("框选",function() g.box=not g.box end,57);H.refs.box=boxes
 local append=btn("追加",function() g.append=not g.append end,57);H.refs.append=append
 local rows={
  UI.Panel{flexDirection="row",gap=5,flexWrap="wrap",children={btn("建造",function() H.toggle(g,"build") end,60,true),btn("训练",function() H.toggle(g,"train") end,60),btn("科技",function() H.toggle(g,"tech") end,60),btn("工细胞",function() I.selectKind(g,"worker") end,57),btn("军队",function() I.selectKind(g,"army") end,57),boxes,append}},
  UI.Panel{flexDirection="row",gap=5,flexWrap="wrap",children={btn("移动",function() g.mode="move";U.message(g.state,"点击目的地") end,60),btn("进攻",function() g.mode="attackmove";U.message(g.state,"点击进攻目的地") end,60),btn("驻守",function() g.mode="guard";U.message(g.state,"点击驻守位置") end,60),btn("撤退",function() I.issue(g,"retreat") end,57),btn("停止",function() I.issue(g,"stop") end,57),btn("集结",function() g.mode="rally";U.message(g.state,"选中生产建筑，点击集结点") end,57),btn("取消",function() local id=I.ids(g)[1];if id then C.submit(g.state,{kind="cancel",faction=1,target=id}) end;g.placement=false;g.mode=false end,57)}},
 }
 local groups={}
 for j=1,3 do local k=j;local b=btn("编队 "..j,function() I.group(g,k,false) end,66);b.props.onLongPressStart=function() I.group(g,k,true) end;groups[#groups+1]=b end
 rows[#rows+1]=UI.Panel{flexDirection="row",gap=5,children={groups[1],groups[2],groups[3],textRef("fps","",10,T.muted)}}
 local commands=UI.Panel{flexGrow=1,flexBasis=0,padding=8,gap=5,children=rows}
 local map=UI.Panel{width=136,height=126,onTap=function(e)
   local l=H.refs.map:GetAbsoluteLayout();g.camera.x,g.camera.y=R.mapPoint(l,e.x,e.y)
  end}
 map.Render=function(self,vg) R.minimap(vg,g,self:GetAbsoluteLayout()) end;H.refs.map=map
 local dock=panel{position="absolute",left=12,right=12,bottom=12,height=136,flexDirection="row",gap=8,padding=4,children={selected,commands,map}}
 H.refs.dock=dock;safe:AddChild(dock)
 local notice=label("",12,T.paper,{position="absolute",bottom=158,left=150,right=150,textAlign="center",pointerEvents="none"});H.refs.notice=notice;safe:AddChild(notice)
 local modal=UI.Panel{position="absolute",left=0,right=0,top=0,bottom=0,backgroundColor={13,19,16,215},justifyContent="center",alignItems="center",visible=false};H.refs.modal=modal
 local menu=UI.Panel{position="absolute",left=0,right=0,top=0,bottom=0,backgroundColor={15,24,19,170},justifyContent="center",paddingLeft="10%",children={}}
 H.refs.menu=menu
 menu:AddChild(UI.Panel{width="75%",maxWidth=590,gap=15,children={
  label("SURVIVE  /  BUILD  /  CONQUER",12,T.gold,{letterSpacing=3}),
  label("细胞战争",62,T.paper),
  label("一具身体，就是整个世界。",20,T.paper),
  label("在巨人体内建立胞群，穿过血管与器官组织。",14,T.muted),
  label("1024 × 1024 大世界 · 16种组织地貌 · 六类细胞 · 生存与军团",12,T.muted),
  UI.Panel{flexDirection="row",gap=10,marginTop=16,children={btn("建立胞群  →",function() g.started=true;menu:SetVisible(false) end,178,true),btn("读取存档",function() H.saveMenu(g) end,110),btn("指挥手册",function() H.help(g) end,110)}},
  label("单人长期沙盒    /    战术暂停    /    巨人体内的细胞战争",10,T.gold,{marginTop=15}),
 }})
 safe:AddChild(menu);safe:AddChild(modal) -- move modal above menu (AddChild reparents safely)
 UI.SetRoot(H.root)
 g.openMap=function() H.mapMenu(g) end;g.refreshSidebar=function() H.sidebar(g) end;g.closeModal=function() H.closeModal(g) end
end
function H.update(g,dt)
 H.tick=H.tick+dt;if H.tick<.2 then return end;H.tick=0
 local s=g.state;local refs=H.refs;local day,fraction,season,phase=V.clock(s)
 for _,k in ipairs(D.resources) do refs[k]:SetText(tostring(math.floor(E.stock(s,1,k)))) end
 refs.clock:SetText("第"..day.."天 · "..D.seasons[season].." "..((day-1)%8+1).."/8")
 local key=U.key(g.camera.x,g.camera.y);local region=s.factions[1].seen[key] and D.biomes[W.terrain(s,math.floor(g.camera.x),math.floor(g.camera.y))].name or "未探索"
 refs.phase:SetText(phase.." · "..region.." · "..math.floor((1-fraction)*360).."秒")
 refs.pause:SetText(g.paused and "▶ 继续" or "Ⅱ 暂停");refs.speed:SetText(g.speed.."×");refs.box:SetText(g.box and "框选 ✓" or "框选");refs.append:SetText(g.append and "追加 ✓" or "追加")
 local ids=I.ids(g);local e=ids[1] and s.entities[ids[1]];local pop,cap=E.population(s,1,false)
 if e then
  local d=e.category=="unit" and D.units[e.kind] or D.buildings[e.kind]
  refs.selected:SetText(#ids>1 and (#ids.."个细胞已选中") or e.salvaged and "残存储运囊" or d.name)
  if e.category=="unit" then
   refs.selectedDetail:SetText("生命 "..math.floor(e.hp).."/"..e.maxHp.."  饱食 "..math.floor(e.satiety))
   refs.selectedStats:SetText("温度 "..math.floor(e.temp).."°  精神 "..math.floor(e.sanity).."  人口 "..pop.."/"..cap)
   local names={gather="采集",build="施工",farm="培育",repair="维修",guard="驻守",move="移动",attack="攻击",attackmove="进攻",extinguish="灭火"}
   local o=e.orders[1];refs.queue:SetText(e.pathFailed and "道路不通 · 等待指令" or e.delivering and "运输物资 → 储运囊" or (o and (names[o.kind] or o.kind).." · 队列"..#e.orders or "待命 · 点击地图下令"))
  else
   refs.selectedDetail:SetText("耐久 "..math.floor(e.hp).."/"..e.maxHp..(e.complete and "" or " · 施工"..math.floor(e.progress*100).."%"))
   refs.selectedStats:SetText(d.desc or "");local q=e.queue[1];refs.queue:SetText(q and ((q.unit and D.units[q.unit].name or D.tech[q.tech].name).." · "..math.ceil(q.remaining).."秒 · 队列"..#e.queue) or "空闲 · 训练/科技查看生产")
  end
 else refs.selected:SetText("胞群指挥");refs.selectedDetail:SetText("点击选兵 · 拖动移镜头");refs.selectedStats:SetText("人口 "..pop.." / "..cap.."  · 科技 T"..s.factions[1].tier);refs.queue:SetText(Save.status) end
 local tutorials={"01 选择工细胞 · 单击或按下工细胞按钮","02 点击蛋白束或钙晶，采集并送回胞巢","03 建造第二座荧光腺，扩大休息期安全区","04 建造培养床，安排工细胞生产食物","05 建分裂兵巢并训练第一支军队","06 探索器官 · 发展科技 · 进攻敌群"}
 refs.tutorial:SetText(tutorials[s.tutorial] or tutorials[6])
 refs.goal:SetText(s.outcome=="victory" and "已控制内域 · 可继续沙盒" or s.outcome=="defeat" and "胞群全灭 · 读取手动存档" or "目标 · 维持稳态，击败两个敌群")
 refs.notice:SetText(g.placement and ("放置 "..D.buildings[g.placement].name.." · 点击地图确认") or g.mode and "选择命令目的地" or s.messageTime>0 and s.message or g.paused and "战术暂停 · 下达的命令将在恢复后执行" or "")
 local liveUnits=0;for _,u in pairs(s.entities) do if u.category=="unit" and u.faction>0 and U.alive(u) then liveUnits=liveUnits+1 end end
 refs.fps:SetText(string.format("%d FPS  ·  %d单位",g.fps or 0,liveUnits))
 if H.lastTab~=g.tab then H.sidebar(g) end
 local viewW=select(1,UI.GetViewportSize())
 refs.selectionCard:SetStyle({width=viewW<1050 and 170 or 226})
 if s.outcome=="defeat" and not g.defeatShown then g.defeatShown=true;H.dialog(g,"最后一处荧光熄灭了",{"你的单位和生产建筑已全部损失。","已有手动存档仍保留，可读取后重新指挥。"},{{"读取存档",function() H.saveMenu(g) end,130,true},{"建立新营地",function() g.newGame();H.closeModal(g) end,150}}) end
end
return H
