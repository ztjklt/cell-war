class_name WarHUD
extends CanvasLayer

signal command_mode_changed(kind: String)
signal focus_requested(point: Vector2,zoom: float)
signal overview_requested
signal zoom_requested(factor: float)
signal restart_requested(mode: String)
var game: WarSimulation
var world: WarWorldView
var camera: Camera2D
var root: Control
var stats: Label
var status: Label
var selection: Label
var details: Label
var orders_box: VBoxContainer
var panel: PanelContainer
var menu: PanelContainer
var menu_body: VBoxContainer
var pause_button: Button
var speed_button: Button
var layer_button: Button
var overview_button: Button
var inspection: WarInspectionMarker
var scenario: Label
var _timer := 0.0
var _selection_rows: Array[Dictionary] = []
var _selection_rows_entity := -1
var production_feedback: Label
var production_pending: Label
var production_buttons: Array[Dictionary] = []
var resource_station_labels: Dictionary = {}
var organ_buttons: Array[Dictionary] = []
var organ_feedback: Label
var organ_reserves: Label
var organ_button: Button
var medicine_balance: Label
var medicine_feedback: Label
var medicine_cards: Dictionary = {}
var medicine_pending: VBoxContainer
var medicine_pending_rows: Dictionary = {}
var _visual_selection := ""
var _saved_pause := false
var title_box: VBoxContainer
var title_label: Label
var subtitle_label: Label
var compact_selection: Label
var toolbar: HFlowContainer
var navigation: WarMinimap
var vision_menu: PanelContainer
var systemic_panel: PanelContainer
var zoom_tools: HBoxContainer
var advisor: WarBrainRig
var append_orders := false
var box_mode := false
var resource_values: Dictionary = {}
var wheel: WarCommandWheel
var home: Control
var cover_preview: WarCoverPreview
var menu_shade: ColorRect
var selection_health: ProgressBar
var selection_emblem: WarSelectionEmblem
var action_buttons: Dictionary = {}
var dialogue: WarAdvisorDialogue
var battle: WarBattleHUD
var life_dialogue: WarLifeDialogue
var progress_panel: PanelContainer
var tutorial_text: Label
var goal_text: Label
var tutorial_meter: ProgressBar
var outcome_shown := ""
var focus_button: Button
var _focus_cycle_id := -1
const PAPER := WarUISkin.INK
const MUTED := WarUISkin.MUTED
const TEAL := Color("668d73")
const RESOURCE_LABELS := {"wood":"蛋白质量","oxygen":"氧气量","food":"葡萄糖量"}
const STATES := {"idle":"待命","move":"移动","attack":"攻击","buff":"摇花增益","scanning":"侦察标记","harvest":"采集","build":"建造","recovering":"恢复","fatigued":"疲劳","dead":"阵亡"}
const ORDERS := {"move":"移动","attackmove":"进攻推进","attack":"集中攻击","guard":"驻守","retreat":"撤退","hold":"原地防守","harvest":"采集运输","gather":"采集运输","build":"建造","repair":"维修","farm":"培育葡萄糖","extinguish":"灭火","supplyroute":"循环运输"}
const FARM_GUIDE := "选择红细胞 → 右键已完成的己方培养床 → 培育葡萄糖；产出后自动运回补给点并继续。"

func setup(sim: WarSimulation,view: WarWorldView,view_camera: Camera2D) -> void:
	game = sim
	world = view
	camera = view_camera
	root = Control.new()
	root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = WarUISkin.theme()
	add_child(root)
	_build_header()
	_build_sidebar()
	_build_bottom()
	status.add_theme_color_override("font_color",Color("14211b"))
	var note := WarUISkin.panel(Color(WarUISkin.CREAM,.96),3,6)
	note.set_border_width_all(0)
	note.content_margin_top = 2; note.content_margin_bottom = 2
	status.add_theme_stylebox_override("normal",note)
	_build_menu()
	_build_home()
	battle = WarBattleHUD.new()
	root.add_child(battle)
	battle.setup(self)
	dialogue = WarAdvisorDialogue.new()
	root.add_child(dialogue)
	dialogue.setup(self)
	life_dialogue = WarLifeDialogue.new()
	root.add_child(life_dialogue)
	life_dialogue.setup(self)
	life_dialogue.incoming_message.connect(func(): dialogue.new_life_message())
	root.move_child(life_dialogue,0)
	_build_progress()
	wheel = WarCommandWheel.new()
	root.add_child(wheel)
	wheel.setup(self)
	_apply_facets(root)
	game.message_changed.connect(func(text):
		status.text = text
		if is_instance_valid(production_feedback): production_feedback.text = text
		if is_instance_valid(organ_feedback): organ_feedback.text = text
		if is_instance_valid(medicine_feedback): medicine_feedback.text = text)
	game.state_replaced.connect(func(): _selection_rows_entity = -2; outcome_shown = "")
	get_viewport().size_changed.connect(_layout)
	_layout()

func _apply_facets(node: Node) -> void:
	for child in node.get_children():
		if child == home or child == life_dialogue or child == cover_preview: continue
		if child is PanelContainer: WarUISkin.facet_panel(child)
		_apply_facets(child)

static func style(color: Color,radius: int) -> StyleBoxFlat:
	return WarUISkin.panel(color,radius,10)

func accent_button(node: Button,color := TEAL) -> void:
	WarUISkin.apply_button(node,"primary" if color != TEAL else "sage")

func label(text: String,size := 14,color := PAPER) -> Label:
	var node := Label.new()
	node.text = text
	if size >= 14: node.add_theme_font_override("font",WarUISkin.DISPLAY)
	node.add_theme_font_size_override("font_size",roundi(size*4.0/3))
	node.add_theme_color_override("font_color",color)
	return node

func button(text: String,callback: Callable,parent: Node) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size.y = 44
	node.add_theme_font_size_override("font_size",16)
	node.focus_mode = Control.FOCUS_NONE
	node.pressed.connect(callback)
	WarUISkin.apply_button(node)
	parent.add_child(node)
	return node

func cost_text(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for kind in ["wood","oxygen","food"]:
		if cost.has(kind):
			var amount := float(cost[kind])
			parts.append(str(WarData.config().Data.names[kind])+" "+(str(roundi(amount)) if is_equal_approx(amount,roundf(amount)) else String.num(amount,1)))
	return " / ".join(parts)

func _organ_service() -> WarOrganFunctions:
	return game.get("organ_functions") as WarOrganFunctions

func _training_cost(building: Dictionary,kind: String) -> Dictionary:
	var service := _organ_service()
	return service.training_cost(building,kind) if service != null else WarData.spec(kind).get("cost",{})

func _pending_resource_costs(faction: int) -> Dictionary:
	var reserved := {}
	for command in game.state.get("commands",[]):
		var cost := {}
		if command.action in ["train","research"]:
			var target := game.entity(int(command.get("target",0)))
			if target.is_empty() or int(target.faction) != faction: continue
			cost = WarData.config().Data.tech.get(command.get("tech",""),{}).get("cost",{}) if command.action == "research" else _training_cost(target,str(command.unit))
		elif command.action == "organ_action":
			var actor := game.entity(int(command.get("actor",0)))
			if actor.is_empty() or int(actor.faction) != faction: continue
			cost = WarOrganFunctions.data().actions.get(command.get("organAction",""),{}).get("cost",{})
		for kind in cost: reserved[kind] = float(reserved.get(kind,0))+float(cost[kind])
	return reserved

func _build_header() -> void:
	var top := HBoxContainer.new()
	top.name = "Header"
	top.add_theme_constant_override("separation",4)
	root.add_child(top)
	title_box = VBoxContainer.new()
	title_label = label("细胞战争",21,PAPER)
	subtitle_label = label("C E L L   W A R",8,TEAL)
	title_box.add_child(title_label)
	title_box.add_child(subtitle_label)
	title_box.visible = false
	top.add_child(title_box)
	for kind in ["wood","oxygen","food"]:
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel",style(WarUISkin.CREAM,18))
		top.add_child(card)
		var row := HBoxContainer.new()
		card.add_child(row)
		var icon := WarResourceIcon.new()
		icon.kind = kind
		icon.custom_minimum_size = Vector2(38,38)
		row.add_child(icon)
		var column := VBoxContainer.new()
		row.add_child(column)
		var caption := label(RESOURCE_LABELS[kind],10,MUTED)
		column.add_child(caption)
		var value := label("0",15,PAPER)
		value.add_theme_font_override("font",WarUISkin.BUTTON)
		column.add_child(value)
		resource_values[kind] = {"value":value,"caption":caption,"card":card}
	stats = label("",14,PAPER)
	stats.visible = false
	top.add_child(stats)
	toolbar = HFlowContainer.new()
	toolbar.name = "Toolbar"
	toolbar.add_theme_constant_override("h_separation",5)
	toolbar.add_theme_constant_override("v_separation",5)
	root.add_child(toolbar)
	pause_button = button("Ⅱ 暂停",func(): game.paused = not game.paused,toolbar)
	pause_button.custom_minimum_size.x = 92
	speed_button = button("1×",func(): game.speed = 2 if game.speed == 1 else 1,toolbar)
	button("全图",func(): overview_requested.emit(),toolbar)
	button("地图",show_map,toolbar)
	button("存档",show_saves,toolbar)
	button("≡",toggle_menu,toolbar)
	advisor = WarBrainRig.new()
	advisor.z_index = 8
	root.add_child(advisor)

func _build_sidebar() -> void:
	panel = PanelContainer.new()
	panel.name = "Sidebar"
	panel.add_theme_stylebox_override("panel",style(WarUISkin.CREAM,18))
	root.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",4)
	panel.add_child(column)
	selection = label("胞群指挥",16,PAPER)
	var identity := HBoxContainer.new()
	identity.add_theme_constant_override("separation",10)
	column.add_child(identity)
	selection_emblem = WarSelectionEmblem.new()
	selection_emblem.world = world
	selection_emblem.custom_minimum_size = Vector2(54,54)
	identity.add_child(selection_emblem)
	selection.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	identity.add_child(selection)
	details = label("选中细胞查看状态",10,MUTED)
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	selection_health = ProgressBar.new()
	selection_health.show_percentage = false
	selection_health.custom_minimum_size.y = 5
	for key in ["background","fill"]:
		var skin := style(WarUISkin.OAT if key == "background" else TEAL,3)
		skin.set_content_margin_all(0); skin.shadow_size = 0
		selection_health.add_theme_stylebox_override(key,skin)
	column.add_child(selection_health)
	selection_health.hide()
	focus_button = button("定位下一枚细胞 · C",func(): focus_cell(not game.selected.is_empty()),column)
	focus_button.tooltip_text = "F 定位当前选中细胞；C 选择并定位下一枚己方细胞"
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 32
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var contents := VBoxContainer.new()
	contents.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(contents)
	contents.add_child(details)
	orders_box = VBoxContainer.new()
	orders_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contents.add_child(orders_box)
	organ_button = button("器官协作",show_organ_actions,contents)
	organ_button.hide()
	var map_shell := PanelContainer.new()
	map_shell.name = "Navigation"
	map_shell.z_index = 15
	map_shell.add_theme_stylebox_override("panel",style(WarUISkin.CREAM,18))
	root.add_child(map_shell)
	navigation = WarMinimap.new()
	navigation.game = game
	navigation.camera = camera
	navigation.world = world
	navigation.moved.connect(func(p): inspection.mark(world.command_point(p)); focus_requested.emit(p,camera.zoom.x))
	map_shell.add_child(navigation)
	inspection = WarInspectionMarker.new()
	inspection.world = world
	inspection.z_index = 8
	root.add_child(inspection)
	overview_button = button("",func(): overview_requested.emit(),root)
	overview_button.name = "ReturnOverview"
	overview_button.tooltip_text = "返回全局"
	overview_button.z_index = 15
	var overview_icon := WarOverviewIcon.new()
	overview_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overview_button.add_child(overview_icon)
	layer_button = button("",func(): vision_menu.visible = not vision_menu.visible,root)
	layer_button.z_index = 15
	var eye := WarVisionEye.new()
	eye.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer_button.add_child(eye)
	vision_menu = PanelContainer.new()
	vision_menu.z_index = 16
	vision_menu.name = "Vision"
	vision_menu.visible = false
	vision_menu.add_theme_stylebox_override("panel",style(WarUISkin.CREAM,18))
	root.add_child(vision_menu)
	var vision := VBoxContainer.new()
	vision_menu.add_child(vision)
	vision.add_child(label("视野设置",14,PAPER))
	vision.add_child(label("地图视野",12,TEAL))
	var grid := GridContainer.new()
	grid.columns = 3
	vision.add_child(grid)
	for i in 7:
		var index := i
		var btn := button(WarWorldView.MODE_NAMES[i],func(): world.layer = index,grid)
		btn.custom_minimum_size = Vector2(76,34)
	vision.add_child(label("战斗视野",12,TEAL))
	button("辅助视野",func(): world.assisted = true,vision)
	button("纯净视野",func(): world.assisted = false,vision)
	systemic_panel = PanelContainer.new()
	systemic_panel.name = "Systemic"
	systemic_panel.add_theme_stylebox_override("panel",style(WarUISkin.CREAM,18))
	root.add_child(systemic_panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation",7)
	systemic_panel.add_child(body)
	body.add_child(label("循环防线 · 右肺",16,PAPER))
	scenario = label("",12,TEAL)
	scenario.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(scenario)
	var controls := GridContainer.new()
	controls.columns = 2
	body.add_child(controls)
	button("隔离右肺",func():
		var q := game.scenarios.systemic()
		if not q.is_empty(): game.submit_player({"action":"isolate","closed":not q.get("isolated",false)}),controls)
	button("恢复自动运输",func():
		var q := game.scenarios.systemic()
		if not q.is_empty(): game.submit_player({"action":"unit_order","unit":int(q.courier),"order":{"kind":"supplyroute"}}),controls)
	button("肺部前线",func():
		var q := game.scenarios.systemic()
		if not q.is_empty(): focus_requested.emit(WarData.point(q.center),.28*32),controls)
	button("心脏补给点",func():
		var q := game.scenarios.systemic()
		if not q.is_empty(): focus_requested.emit(WarData.point(q.heart),.1*32),controls)
	button("重试防线",func(): restart_requested.emit("systemic"),controls)
	button("定位运输队",func():
		var q := game.scenarios.systemic()
		if not q.is_empty(): focus_requested.emit(WarData.point(game.entity(int(q.courier))),.15*32),controls)
	var hint := label("清除感染灶与残余病毒；隔离会切断双向运输。",11,MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(hint)

func _build_bottom() -> void:
	# Bottom command dock is replaced by the contextual wheel.
	var bottom := Control.new()
	bottom.name = "Bottom"
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.hide()
	root.add_child(bottom)
	compact_selection = label("",13,PAPER)
	compact_selection.hide()
	root.add_child(compact_selection)
	status = label("",11,PAPER)
	status.name = "Notice"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(status)
	zoom_tools = HBoxContainer.new()
	zoom_tools.add_theme_constant_override("separation",5)
	root.add_child(zoom_tools)
	button("＋",func(): zoom_requested.emit(1.7),zoom_tools)
	button("－",func(): zoom_requested.emit(1/1.7),zoom_tools)
	button("首页",return_home,zoom_tools)
	button("地图",show_map,zoom_tools)

func _action(action: String) -> void:
	match action:
		"build": show_build()
		"worker","army":
			game.selected.clear()
			for e in game.units():
				if e.faction == 1 and (e.kind == "worker" if action == "worker" else e.kind != "worker"): game.selected.append(int(e.id))
			game.state.selectedOnce = true
		"stop","retreat": game.issue(action)
		"cancel": game.selected.clear(); command_mode_changed.emit("")
		"append": append_orders = not append_orders
		"box": box_mode = not box_mode
		"rally":
			var e := game.entity(game.selected[0]) if not game.selected.is_empty() else {}
			if e.get("category","") == "building" and e.get("complete",false): command_mode_changed.emit("rally")
			else: game.notify("先选中一座已完工的生产建筑")
		_: command_mode_changed.emit(action)

func show_map() -> void:
	_clear_menu("人体地图")
	var map := WarMinimap.new()
	map.game = game; map.world = world; map.camera = camera; map.overview = true
	map.custom_minimum_size = Vector2(minf(560,get_viewport().get_visible_rect().size.x-64),420)
	map.moved.connect(func(p): close_menu(); inspection.mark(world.command_point(p)); focus_requested.emit(p,camera.zoom.x))
	menu_body.add_child(map)
	button("查看全图",func(): close_menu(); overview_requested.emit(),menu_body)
	_open_menu()

func _build_menu() -> void:
	menu_shade = ColorRect.new()
	menu_shade.name = "ModalShade"
	menu_shade.color = Color(.3,.22,.16,.25)
	menu_shade.z_index = 999
	menu_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	menu_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_shade.hide()
	root.add_child(menu_shade)
	menu = PanelContainer.new()
	menu.name = "Menu"
	menu.z_index = 1000
	menu.mouse_filter = Control.MOUSE_FILTER_STOP
	menu.add_theme_stylebox_override("panel",style(WarUISkin.CREAM,18))
	menu.visible = false
	root.add_child(menu)
	var scroll := ScrollContainer.new()
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	scroll.custom_minimum_size = Vector2(450,470)
	menu.add_child(scroll)
	menu_body = VBoxContainer.new()
	menu_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu_body.add_theme_constant_override("separation",9)
	scroll.add_child(menu_body)

func _clear_menu(title: String) -> void:
	production_feedback = null; production_pending = null; production_buttons.clear()
	resource_station_labels.clear()
	organ_feedback = null; organ_reserves = null; organ_buttons.clear()
	medicine_balance = null; medicine_feedback = null; medicine_cards.clear()
	medicine_pending = null; medicine_pending_rows.clear()
	for child in menu_body.get_children():
		menu_body.remove_child(child)
		child.queue_free()
	menu_body.add_child(label(title,23))
	button("返回封面" if home != null and home.visible else "返回游戏",close_menu,menu_body)

func _open_menu() -> void:
	if wheel != null: wheel.close()
	if not menu.visible: _saved_pause = game.paused
	game.paused = true
	menu.visible = true
	menu_shade.show()
	# Cover, HUD, and modal all share this Control tree. Keep the modal last so
	# its controls receive pointer events even while the opaque cover is visible.
	root.move_child(menu_shade,-1)
	root.move_child(menu,-1)
	_layout()

func close_menu() -> void:
	menu.visible = false
	menu_shade.hide()
	game.paused = _saved_pause

func toggle_menu() -> void:
	if menu.visible:
		close_menu()
		return
	_clear_menu("战术暂停")
	if game.life.enabled(): button("生活事件一览 · 40",show_life_events,menu_body)
	button("细胞与编队",show_command_tools,menu_body)
	button("建设与生产",show_build,menu_body)
	if game.organ_resources.enabled(): button("器官补给与运输",show_resource_stations,menu_body)
	if _organ_service() != null and _organ_service().enabled(): button("器官协作",show_organ_actions,menu_body)
	if game.life.enabled(): button("药品补给",show_medicine_supply,menu_body)
	button("选择战场",show_battlefields,menu_body)
	button("返回首页",return_home,menu_body)
	button("本地存档",show_saves,menu_body)
	button("开局指引",func(): show_original_copy("startGuide"),menu_body)
	button("指挥手册",show_help,menu_body)
	button("显示与声音设置",show_cover_settings,menu_body)
	_open_menu()

func resource_station_name(resource: Dictionary) -> String:
	return str(WarOrganResources.data().art.get(resource.get("kind",""),{}).get("name","采集站"))

func resource_organ_name(resource: Dictionary) -> String:
	return str(game.navigation.organs.get(resource.get("organId",""),{}).get("name","组织"))

func resource_station_text(resource: Dictionary) -> String:
	var state_text := "敌军占用 · 已停工" if resource.get("contested",false) else ("库存已满" if float(resource.amount) >= float(resource.max) else "安全补充中")
	var rate := "安全时每秒恢复 %s" % String.num(float(resource.get("regen",0)),1)
	return "%s · %s\n站内库存 %.0f / %.0f\n%s · %s" % [resource_station_name(resource),resource_organ_name(resource),float(resource.amount),float(resource.max),state_text,rate]

func resource_delivery_text(worker: Dictionary,resource := {}) -> String:
	var courier := worker.duplicate()
	if not courier.get("delivering",false) and not resource.is_empty():
		courier.x = resource.x; courier.y = resource.y
	var point := game.economy._delivery_point(courier)
	var destination := "心脏补给点"
	for entity in game.entities():
		if entity.category != "building" or int(entity.faction) != int(worker.faction) or not entity.kind in ["core","store"]: continue
		if entity.hp > 0 and entity.get("complete",false) and WarData.point(entity).distance_to(point) < .1:
			var organ: String = game.navigation.organ_at(point,"worker")
			destination = str(game.navigation.organs.get(organ,{}).get("name",""))+" · "+str(WarData.spec(entity.kind).name)
			break
	return ("运输中 → " if worker.get("delivering",false) else "装满后运往 → ")+destination

func show_resource_stations() -> void:
	_clear_menu("器官补给与运输")
	var guide := label("选择红细胞，右键点击采集站后选择采集。空库存时会等候补充；敌军占用时暂停采集与恢复。装满后优先送往同器官的核心胞巢或储运囊，没有本地补给点则运往心脏。上方资源量只统计已入库的物资。\n"+FARM_GUIDE,12,MUTED)
	guide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu_body.add_child(guide)
	for spec in WarOrganResources.data().sources:
		var resource: Dictionary = game.state.resources.get(spec.id,{})
		if resource.is_empty(): continue
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel",style(WarUISkin.OAT,12))
		menu_body.add_child(card)
		var column := VBoxContainer.new(); card.add_child(column)
		var info := label(resource_station_text(resource),12,PAPER)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(info)
		resource_station_labels[spec.id] = info
		var point := WarData.point(resource)
		button("观察 · "+resource_organ_name(resource)+resource_station_name(resource),func(): close_menu(); focus_requested.emit(world.display_point(point),18),column)
	_open_menu()

func show_command_tools() -> void:
	_clear_menu("细胞与编队")
	button("选择红细胞",func(): _action("worker"); close_menu(),menu_body)
	button("选择作战细胞",func(): _action("army"); close_menu(),menu_body)
	button("定位当前选择 · F",func(): focus_cell(false); close_menu(),menu_body)
	button("下一枚己方细胞 · C",func(): focus_cell(true); close_menu(),menu_body)
	button("追加命令："+("开启" if append_orders else "关闭"),func(): append_orders = not append_orders; show_command_tools(),menu_body)
	button("框选模式："+("开启" if box_mode else "关闭"),func(): box_mode = not box_mode; close_menu(),menu_body)
	for i in 3:
		var index := i
		var row := HBoxContainer.new()
		menu_body.add_child(row)
		button("保存编队 %d" % (i+1),func(): game.groups[index] = game.selected.duplicate(),row)
		button("召回编队 %d" % (i+1),func():
			game.selected.clear()
			for id in game.groups[index]:
				if not game.entity(int(id)).is_empty(): game.selected.append(int(id))
			close_menu(),row)
	_open_menu()

func focus_cell(next := false) -> void:
	var candidates: Array = game.units().filter(func(e): return int(e.faction) == 1 and float(e.hp) > 0)
	candidates.sort_custom(func(a,b): return int(a.id) < int(b.id))
	if candidates.is_empty():
		game.notify("当前没有可定位的己方细胞")
		return
	var chosen: Dictionary = {}
	if not next and not game.selected.is_empty():
		var selected := game.entity(int(game.selected[0]))
		if not selected.is_empty() and int(selected.faction) == 1 and selected.category == "unit" and selected.hp > 0:
			chosen = selected
	if chosen.is_empty():
		for entity in candidates:
			if int(entity.id) > _focus_cycle_id:
				chosen = entity
				break
		if chosen.is_empty(): chosen = candidates[0]
		game.selected.assign([int(chosen.id)])
		game.state.selectedOnce = true
	_focus_cycle_id = int(chosen.id)
	focus_requested.emit(WarData.point(chosen),18)
	game.notify("已定位 · "+str(WarData.spec(chosen.kind).name))

func show_battlefields() -> void:
	_clear_menu("选择战场")
	for item in [["人体生存 · 生活决策","life"],["全身地图","fullbody"],["右肺交战","lung_skirmish"],["循环防线","systemic"],
		["鼻腔战役","nasal_01"],["气管战役","trachea_01"],["双肺战役","lungs_01"],
		["三阵营沙盒","sandbox"],["器官战场试验","organ_trial"],["胃部战场试验","gastric_trial"],["细胞动作测试","cell_test"]]:
		var which: String = item[1]
		button(item[0],func(): close_menu(); restart_requested.emit(which),menu_body)
	if game.mode == "cell_test":
		for entry in [["空载移动","empty"],["携氧移动","oxygen"],["携糖移动","glucose"],["建造动作","build"],["开火动作","shoot"],["受击动作","hit"],["阵亡动作","death"]]:
			var task: String = entry[1]
			button(entry[0],func(): close_menu(); game.scenarios.cell_action(task),menu_body)
	if game.is_campaign():
		var ev: Dictionary = game.state.campaign.event
		var next_wave := button("下一波",func(): close_menu(); game.submit_player({"action":"skip_wave"}),menu_body)
		next_wave.disabled = ev.status != "active" or int(ev.wave) >= game.navigation.campaign.waves.size() or int(ev.pendingViruses) > 0 or game.units().any(func(e): return e.kind == "virus")
		next_wave.tooltip_text = "清除当前波次后可提前开始下一波" if ev.status == "active" else "本场战役已结束"
		button("关闭挂机指挥" if game.state.campaign.get("autoplay",false) else "开启挂机指挥",func():
			game.state.campaign.autoplay = not game.state.campaign.get("autoplay",false)
			close_menu(),menu_body)
	if not game.scenarios.systemic().is_empty():
		button("开放右肺" if game.scenarios.systemic().get("isolated",false) else "隔离右肺",func():
			game.submit_player({"action":"isolate","closed":not game.scenarios.systemic().get("isolated",false)})
			close_menu(),menu_body)
	if not game.scenarios.systemic().is_empty():
		button("恢复红细胞循环运输",func():
			var courier := game.entity(int(game.scenarios.systemic().courier))
			if not courier.is_empty(): game.order(courier,{"kind":"supplyroute"})
			close_menu(),menu_body)
	button("本地存档",show_saves,menu_body)
	if game.selected.size() == 1:
		var cell := game.entity(game.selected[0])
		if not cell.is_empty() and cell.get("category","") == "unit" and game.navigation._box_has(game.navigation.organs.heart.sourceBox,WarData.point(cell)):
			for oid in game.navigation.organs:
				if oid in ["heart","pancreas","bladder"]: continue
				var destination: String = oid
				button("心脏转运 → "+str(game.navigation.organs[oid].name),func():
					if game.scenarios.transfer(cell,destination):
						close_menu()
						focus_requested.emit(WarData.point(cell),18),menu_body)
	button("开局指引",func(): show_original_copy("startGuide"),menu_body)
	button("指挥手册",show_help,menu_body)
	button("路线显示：开 / 关",func(): world.show_paths = not world.show_paths; close_menu(),menu_body)
	button("声音：开 / 关",func(): AudioServer.set_bus_mute(0,not AudioServer.is_bus_mute(0)),menu_body)
	_open_menu()

func show_saves() -> void:
	_clear_menu("本地存档")
	if FileAccess.file_exists(WarSave.life_auto_path()):
		button("继续人体生存 · 独立自动存档",func():
			if WarSave.read_life_auto(game) == OK:
				close_menu(); home.hide(); _layout(); overview_requested.emit(),menu_body)
	for slot in 4:
		var index := slot
		var row := HBoxContainer.new()
		menu_body.add_child(row)
		row.add_child(label("自动槽" if slot == 0 else "槽位 %d" % slot))
		var load_btn := button("读取",func():
			var result := WarSave.read_slot(game,index)
			if result == OK:
				close_menu()
				home.hide()
				_layout()
				if game.life.enabled(): overview_requested.emit()
				else: focus_requested.emit(game.scenarios.home(),18)
			else: game.notify("读取失败："+error_string(result)),row)
		var save_btn := button("保存",func():
			var result := WarSave.write(game,index)
			load_btn.disabled = not FileAccess.file_exists(WarSave.path(index))
			if result != OK: game.notify("保存失败："+error_string(result)),row)
		row.move_child(save_btn,1)
		load_btn.disabled = not FileAccess.file_exists(WarSave.path(slot))
	_open_menu()

func show_life_events() -> void:
	_clear_menu("生活事件一览 · 40")
	var note := label("查看本人和外部人员的全部对话与选项。预览不结算金钱、机能或时间；条件事件会在对应生活经历后出现。",12,MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; menu_body.add_child(note)
	for i in WarLifeRun.catalogue().size():
		var item: Dictionary = WarLifeRun.catalogue()[i]
		var id: String = item.id
		button("%02d · %s · %s" % [i+1,item.category,item.title],func():
			close_menu(); life_dialogue.show_preview(id),menu_body)
	_open_menu()

func show_medicine_supply() -> void:
	_clear_menu("药品补给")
	medicine_balance = label("生活金钱 %d" % int(game.life.state().money),15,TEAL)
	medicine_balance.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu_body.add_child(medicine_balance)
	medicine_feedback = label("菜单已暂停 · 购买只入库存，派遣需选中一枚己方红细胞；返回并恢复时间后执行。" if game.medicine_supply.released() else "购买与派遣暂未开放。",12,MUTED)
	medicine_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; menu_body.add_child(medicine_feedback)
	medicine_pending = VBoxContainer.new(); menu_body.add_child(medicine_pending)
	var definitions: Array = WarData.read("medicines").entries.duplicate()
	definitions.sort_custom(func(a,b): return a.id == "fever_pain_relief" and b.id != "fever_pain_relief")
	for definition in definitions:
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel",style(WarUISkin.OAT,12)); menu_body.add_child(card)
		var column := VBoxContainer.new(); card.add_child(column)
		column.add_child(label(str(definition.displayName),15,PAPER))
		var text := label(" ".join(definition.confirmedRules) if definition.id == "fever_pain_relief" else "尚未实装 · 当前仅可查看角色资料。",12,MUTED)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; column.add_child(text)
		var inventory := label("" if definition.id == "fever_pain_relief" else "尚未实装",12,TEAL)
		inventory.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(inventory)
		var condition := label("",12,MUTED)
		condition.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; column.add_child(condition)
		var controls := HBoxContainer.new(); column.add_child(controls)
		var buy := button("购买暂未开放" if definition.id == "fever_pain_relief" else "尚未实装",_request_medicine_purchase if definition.id == "fever_pain_relief" else func(): pass,controls)
		buy.disabled = true; buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var deploy: Button
		if definition.id == "fever_pain_relief":
			deploy = button("派遣暂未开放",_show_medicine_deployment,controls)
			deploy.disabled = true; deploy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		medicine_cards[definition.id] = {"buy":buy,"deploy":deploy,"inventory":inventory,"condition":condition,"definition":definition}
	_refresh_medicine_menu()
	_open_menu()

func _medicine_requests() -> Array:
	return game.state.commands.filter(func(command): return command.get("action","") in ["medicine_buy","medicine_deploy"])

func _medicine_selected_worker() -> int:
	if game.selected.size() != 1: return 0
	var actor := game.entity(int(game.selected[0]))
	return int(actor.id) if actor.get("kind","") == "worker" and int(actor.get("faction",0)) == 1 and float(actor.get("hp",0)) > 0 else 0

func _medicine_buy_error(quote: Dictionary) -> String:
	if not quote.get("ok",false): return str(quote.get("reason","药品尚未开放"))
	var money := 0; var quantity := 0
	for command in _medicine_requests():
		if command.action == "medicine_buy": money += int(command.unitPrice)*int(command.quantity); quantity += int(command.quantity)
	if int(game.life.state().money)-money < int(quote.cost): return "金钱不足（待执行购买已预留）"
	if game.medicine_supply.count()+quantity+1 > int(WarMedicineHelpers.data().tuning.inventoryLimit): return "待执行购买已占用库存容量"
	if _medicine_requests().size() >= int(WarMedicineHelpers.data().tuning.queueLimit): return "药品操作队列已满"
	return ""

func _medicine_deploy_error(quote: Dictionary) -> String:
	if not quote.get("ok",false): return str(quote.get("reason","当前无法派遣"))
	var pending := _medicine_requests().filter(func(command): return command.action == "medicine_deploy").size()
	if game.medicine_supply.count()-pending <= 0: return "库存已被待执行派遣预留"
	var active := game.units().filter(func(entity): return entity.kind == WarMedicineSupply.MEDICINE).size()
	if active+pending >= int(WarMedicineHelpers.data().tuning.activeHelperLimit): return "待执行派遣已占用助手名额"
	if _medicine_requests().size() >= int(WarMedicineHelpers.data().tuning.queueLimit): return "药品操作队列已满"
	return ""

func _request_medicine_purchase() -> void:
	var quote := game.medicine_supply.quote_purchase(WarMedicineSupply.MEDICINE,1)
	var reason := _medicine_buy_error(quote)
	if not reason.is_empty(): game.notify(reason); return
	var result := game.medicine_supply.queue_purchase(WarMedicineSupply.MEDICINE,1)
	game.notify("已排队购买 1 份退烧止痛药 · 恢复时间后入库存" if result.ok else str(result.reason))
	_refresh_medicine_menu()

func _show_medicine_deployment() -> void:
	var actor := _medicine_selected_worker()
	var quote := game.medicine_supply.quote_deployment(actor)
	var reason := _medicine_deploy_error(quote)
	if not reason.is_empty(): game.notify(reason); return
	_clear_menu("确认派遣")
	medicine_feedback = label("",12,MUTED); medicine_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var organ := str(game.navigation.organs.get(quote.organ,{}).get("name","组织"))
	var text := label("在"+organ+"中，选中的红细胞身旁派遣一位降温消防员。\n消耗库存 1 份；助手持续 %.0f 模拟秒，暂停时冻结。\n取消不消耗库存；进入战场后的助手到期或阵亡不返还药品。" % float(WarMedicineHelpers.data().tuning.helperLifetimeSeconds),14,PAPER)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; menu_body.add_child(text)
	menu_body.add_child(medicine_feedback)
	button("确认派遣 · 消耗库存 1",_queue_medicine_deployment.bind(actor),menu_body)
	button("取消派遣",show_medicine_supply,menu_body)
	_open_menu()

func _queue_medicine_deployment(actor: int) -> void:
	var quote := game.medicine_supply.quote_deployment(actor)
	var reason := _medicine_deploy_error(quote)
	if not reason.is_empty(): game.notify(reason); return
	var result := game.medicine_supply.queue_deployment(actor)
	if result.ok:
		show_medicine_supply()
		game.notify("已排队派遣 · 恢复时间后进入战场")
	else: game.notify(str(result.reason))
	_refresh_medicine_menu()

func _cancel_medicine_request(request: Dictionary) -> void:
	var result := game.medicine_supply.cancel_queued(request)
	var reason := str(result.get("reason",""))
	game.notify("已取消待执行药品操作 · 未扣金钱或库存" if result.get("cancelled",false) else (reason if not reason.is_empty() else "请求已执行，无法取消"))
	_refresh_medicine_menu()

func _refresh_medicine_menu() -> void:
	if not is_instance_valid(medicine_balance): return
	var pending := _medicine_requests()
	var reserved := 0; var deployments := 0
	for command in pending:
		if command.action == "medicine_buy": reserved += int(command.unitPrice)*int(command.quantity)
		else: deployments += 1
	medicine_balance.text = "生活金钱 %d · 待执行购买预留 %d" % [int(game.life.state().money),reserved]
	if medicine_cards.has(WarMedicineSupply.MEDICINE):
		var card: Dictionary = medicine_cards[WarMedicineSupply.MEDICINE]
		var buy_quote := game.medicine_supply.quote_purchase(WarMedicineSupply.MEDICINE,1)
		var buy_error := _medicine_buy_error(buy_quote)
		var deploy_quote := game.medicine_supply.quote_deployment(_medicine_selected_worker())
		var deploy_error := _medicine_deploy_error(deploy_quote)
		var active := game.units().filter(func(entity): return entity.kind == WarMedicineSupply.MEDICINE).size()
		card.inventory.text = "库存 %d · 待派遣 %d · 在场助手 %d / %d\n助手持续 %.0f 模拟秒" % [game.medicine_supply.count(),deployments,active,int(WarMedicineHelpers.data().tuning.activeHelperLimit),float(WarMedicineHelpers.data().tuning.helperLifetimeSeconds)]
		card.buy.text = "购买 1 份 · 金钱 %d" % int(buy_quote.unitPrice) if game.medicine_supply.released() else "购买暂未开放"
		card.buy.disabled = not buy_error.is_empty(); card.buy.tooltip_text = buy_error
		card.deploy.text = "派遣 · 消耗库存 1" if game.medicine_supply.released() else "派遣暂未开放"
		card.deploy.disabled = not deploy_error.is_empty(); card.deploy.tooltip_text = deploy_error
		card.condition.text = "购买 · "+("可排队" if buy_error.is_empty() else buy_error)+"\n派遣 · "+("可确认" if deploy_error.is_empty() else deploy_error)
	if medicine_pending == null: return
	var keep := {}
	for command in pending:
		var request: Dictionary = command.get("request",{})
		var key := str(request.get("runId",""))+":"+str(request.get("sequence",0))
		keep[key] = true
		if not medicine_pending_rows.has(key):
			var caption := "取消待执行购买" if command.action == "medicine_buy" else "取消待执行派遣"
			medicine_pending_rows[key] = button(caption+" · "+str(request.get("sequence",0)),_cancel_medicine_request.bind(request.duplicate(true)),medicine_pending)
	for key in medicine_pending_rows.keys():
		if not keep.has(key):
			medicine_pending.remove_child(medicine_pending_rows[key]); medicine_pending_rows[key].queue_free(); medicine_pending_rows.erase(key)

func show_help() -> void:
	show_original_copy("help")

func show_original_copy(page: String) -> void:
	var context := game.mode if game.is_campaign() else "sandbox"
	var copy: Dictionary = WarData.read("ui_copy")[context][page]
	_clear_menu(copy.title)
	menu_body.add_child(label(copy.subtitle,13,TEAL))
	for section in copy.sections:
		menu_body.add_child(label(section[0],15,TEAL))
		# Keep the frozen original copy intact while describing current desk controls.
		var content := str(section[1]).replace("拖动空地移动镜头","点击地图选定观察坐标，再按 Q 平滑拉近").replace("WASD 移动镜头，","")
		if page == "help" and section[0].begins_with("03"):
			content += " 点击地图记录观察坐标，Q 向该坐标拉近、E 拉远；眼睛左侧的取景图标返回全局。"
		var text := label(content,12,MUTED)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		menu_body.add_child(text)
	if page == "help": button("器官分工与补给",show_organ_guide,menu_body)
	_open_menu()

func show_organ_guide() -> void:
	_clear_menu("器官分工与补给")
	var introduction := label("器官作用以组织地面为准。红细胞在器官内停下后，可从选中面板或右键指令进入器官协作。肺、胃和肠道的物资由采集站提供，必须由红细胞采集并运输入库。",12,MUTED)
	introduction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; menu_body.add_child(introduction)
	var data := WarOrganFunctions.data()
	for id in data.organs:
		var organ: Dictionary = data.organs[id]
		menu_body.add_child(label(str(organ.name)+" · "+" / ".join(organ.functions),15,TEAL))
		var paragraphs := PackedStringArray()
		for spec in WarOrganResources.data().sources:
			if spec.organ == id:
				paragraphs.append("%s：容量 %.0f，安全时每秒补充 %s；敌军占用时停工。" % [str(WarOrganResources.data().art[spec.kind].name),float(spec.capacity),String.num(float(spec.refillPerSecond),1)])
		for action in data.actions.values():
			if action.organ == id: paragraphs.append(str(action.description)+" 冷却 %d 秒。" % roundi(action.cooldown))
		if id in ["kidney_l","kidney_r"]: paragraphs.append(str(data.kidney.cost))
		if id == "brain": paragraphs.append("组织内已完成的研究站，研究速度提高 %.0f%%。" % ((float(organ.researchRate)-1)*100))
		if id == "heart": paragraphs.append("强力细胞需要先到心脏组织，再使用现有器官转运入口前往其他器官。")
		if id == "liver": paragraphs.append("强力细胞由肝组织中的对应生产建筑培育，训练入口保留在建设与生产。")
		var text := label("\n".join(paragraphs),12,MUTED)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; menu_body.add_child(text)
	_open_menu()

func _organ_cost_text(spec: Dictionary) -> String:
	var parts := PackedStringArray()
	var resources := cost_text(spec.get("cost",{}))
	if not resources.is_empty(): parts.append(resources)
	if spec.get("glycogenCost",0) > 0: parts.append("糖原 %.0f" % float(spec.glycogenCost))
	if spec.get("wasteCost",0) > 0: parts.append("净化杂质 %.0f" % float(spec.wasteCost))
	return " / ".join(parts) if not parts.is_empty() else "无需额外资源"

func _organ_gain_text(spec: Dictionary) -> String:
	var parts := PackedStringArray()
	var resources := cost_text(spec.get("gain",{}))
	if not resources.is_empty(): parts.append(resources)
	if spec.get("glycogenGain",0) > 0: parts.append("糖原 +%.0f" % float(spec.glycogenGain))
	if spec.has("attackSpeedMultiplier"): parts.append("作战单位攻速 +%.0f%% · %.0f 秒" % [(float(spec.attackSpeedMultiplier)-1)*100,float(spec.duration)])
	if spec.has("trainingFoodMultiplier"): parts.append("新训练葡萄糖费用 -%.0f%% · %.0f 秒" % [(1-float(spec.trainingFoodMultiplier))*100,float(spec.duration)])
	return " / ".join(parts)

func _organ_action_error(action: String,actor_id: int,quote: Dictionary) -> String:
	if not quote.get("ok",false): return str(quote.get("reason","操作不可用"))
	var actor := game.entity(actor_id)
	if actor.is_empty() or int(actor.faction) != 1: return "请选择自己的红细胞或研究站"
	var reserved := _pending_resource_costs(1)
	var spec: Dictionary = WarOrganFunctions.data().actions[action]
	var glycogen_cost := 0.0; var glycogen_gain := 0.0; var waste_cost := 0.0
	for command in game.state.get("commands",[]):
		if command.action != "organ_action": continue
		var queued_actor := game.entity(int(command.get("actor",0)))
		if queued_actor.is_empty() or int(queued_actor.faction) != 1: continue
		if command.organAction == action: return "这项器官操作已排队"
		var pending: Dictionary = WarOrganFunctions.data().actions.get(command.organAction,{})
		glycogen_cost += float(pending.get("glycogenCost",0)); glycogen_gain += float(pending.get("glycogenGain",0)); waste_cost += float(pending.get("wasteCost",0))
	var service := _organ_service()
	var stock := service.faction_state(1)
	if float(stock.glycogen)-glycogen_cost < float(spec.get("glycogenCost",0)) or float(stock.waste)-waste_cost < float(spec.get("wasteCost",0)): return "糖原或净化杂质已被待执行项目预留"
	if float(stock.glycogen)+glycogen_gain+float(spec.get("glycogenGain",0)) > float(WarOrganFunctions.data().limits.glycogen): return "待执行封存项目已占用糖原容量"
	for kind in spec.cost:
		if game.economy.stock(1,kind)-float(reserved.get(kind,0)) < float(spec.cost[kind]): return "缺少"+str(WarData.config().Data.names[kind])+"（待执行项目已预留）"
	return ""

func show_organ_actions() -> void:
	_clear_menu("器官协作")
	organ_feedback = label("菜单已暂停 · 选择操作排队，返回游戏并恢复时间后执行。",12,PAPER)
	organ_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; menu_body.add_child(organ_feedback)
	organ_reserves = label("",12,TEAL); menu_body.add_child(organ_reserves)
	var service := _organ_service()
	if service != null and game.selected.size() == 1:
		var id := int(game.selected[0])
		var entity := game.entity(id)
		var at := service.organ(entity)
		if not at.is_empty():
			var organ: Dictionary = WarOrganFunctions.data().organs[at]
			menu_body.add_child(label(str(organ.name)+" · "+" / ".join(organ.functions),15,TEAL))
		for quote in service.available_actions(id,1):
			var action: String = quote.action
			var spec: Dictionary = WarOrganFunctions.data().actions[action]
			var card := PanelContainer.new(); card.add_theme_stylebox_override("panel",style(WarUISkin.OAT,12)); menu_body.add_child(card)
			var column := VBoxContainer.new(); card.add_child(column)
			column.add_child(label(str(spec.name),15,PAPER))
			var text := label("消耗 · "+_organ_cost_text(spec)+"\n获得 · "+_organ_gain_text(spec)+"\n"+str(spec.description)+"\n冷却 %.0f 秒" % float(spec.cooldown),12,MUTED)
			text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; column.add_child(text)
			var condition := label("",12,TEAL); condition.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; column.add_child(condition)
			var control := button("排队 · "+str(spec.name),_request_organ_action.bind(action,id),column)
			organ_buttons.append({"action":action,"actor":id,"button":control,"condition":condition})
	if organ_buttons.is_empty():
		var hint := label("选择本地红细胞，在对应器官的组织内停下后操作；脑组织内已完成的研究站也能主动指挥。",12,MUTED)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; menu_body.add_child(hint)
	button("查看十二器官分工",show_organ_guide,menu_body)
	_refresh_organ_menu()
	_open_menu()

func _request_organ_action(action: String,actor_id: int) -> void:
	var service := _organ_service()
	if service == null: return
	var quote := {}
	for option in service.available_actions(actor_id,1):
		if option.action == action: quote = option; break
	var reason := _organ_action_error(action,actor_id,quote)
	if not reason.is_empty(): game.notify(reason); return
	game.submit_player({"action":"organ_action","organAction":action,"actor":actor_id})
	game.notify("已排队："+str(WarOrganFunctions.data().actions[action].name)+" · 恢复时间后执行")
	_refresh_organ_menu()

func _refresh_organ_menu() -> void:
	var service := _organ_service()
	if service == null or not is_instance_valid(organ_reserves): return
	var stock := service.faction_state(1)
	var limits: Dictionary = WarOrganFunctions.data().limits
	organ_reserves.text = "糖原储备 %.0f / %.0f · 净化杂质 %.0f / %.0f" % [float(stock.glycogen),float(limits.glycogen),float(stock.waste),float(limits.waste)]
	for entry in organ_buttons:
		var quote := {}
		for option in service.available_actions(entry.actor,1):
			if option.action == entry.action: quote = option; break
		var reason := _organ_action_error(entry.action,entry.actor,quote)
		entry.condition.text = "可排队 · 恢复时间后执行" if reason.is_empty() else reason+(" · 剩余 %.0f 秒" % ceilf(float(quote.cooldownRemaining)) if float(quote.get("cooldownRemaining",0)) > 0 else "")
		entry.button.disabled = not reason.is_empty()
		entry.button.tooltip_text = entry.condition.text

func show_build() -> void:
	_clear_menu("建设与增殖")
	production_feedback = label("点击训练或研究，加入待执行队列。",12,PAPER)
	production_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu_body.add_child(production_feedback)
	production_pending = label("",11,TEAL)
	production_pending.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu_body.add_child(production_pending)
	var has_worker := false
	var has_building := false
	for id in game.selected:
		var e := game.entity(id)
		if e.get("kind","") == "worker": has_worker = true
		if e.get("category","") == "building":
			has_building = true
			for kind in WarData.config().Data.unitOrder:
				if WarData.spec(kind).get("at","") == e.kind:
					var target_id := int(e.id)
					var unit: String = kind
					var text := "训练 · "+str(WarData.spec(kind).name)+" · "+cost_text(_training_cost(e,kind))
					var control := button(text,func(): _request_production(target_id,unit,false),menu_body)
					production_buttons.append({"button":control,"text":text,"target":target_id,"kind":unit,"research":false})
			if e.kind == "lab":
				for kind in WarData.config().Data.tech:
					var target_id := int(e.id)
					var tech: String = kind
					var price := cost_text(WarData.config().Data.tech[kind].cost)
					var text := "研究 · "+str(WarData.config().Data.tech[kind].name)+(" · "+price if not price.is_empty() else "")
					var control := button(text,func(): _request_production(target_id,tech,true),menu_body)
					production_buttons.append({"button":control,"text":text,"target":target_id,"kind":tech,"research":true})
	if has_worker:
		var guide := label(FARM_GUIDE,12,MUTED)
		guide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; menu_body.add_child(guide)
		for kind in WarData.config().Data.buildOrder:
			var building: String = kind
			button(str(WarData.spec(kind).name)+" · "+cost_text(WarData.spec(kind).cost),func(): close_menu(); command_mode_changed.emit("build:"+building),menu_body)
	elif not has_building:
		menu_body.add_child(label("选择红细胞可建设，选择生产建筑可训练。",13))
	_refresh_production_menu()
	_open_menu()

func _production_commands(faction: int) -> Array[Dictionary]:
	var pending: Array[Dictionary] = []
	for command in game.state.get("commands",[]):
		if not command.get("action","") in ["train","research"]: continue
		var target := game.entity(int(command.get("target",0)))
		if not target.is_empty() and int(target.faction) == faction: pending.append(command)
	return pending

func _production_error(target: Dictionary,kind: String,research: bool) -> String:
	if target.is_empty() or target.get("category","") != "building" or int(target.get("faction",0)) != 1 or float(target.get("hp",0)) <= 0: return "请选择自己的生产建筑"
	if not target.get("complete",false): return "建筑尚未完工"
	var faction := int(target.faction)
	var fa: Dictionary = game.state.factions[faction-1]
	var pending := _production_commands(faction)
	var spec: Dictionary = WarData.config().Data.tech.get(kind,{}) if research else WarData.spec(kind)
	if spec.is_empty(): return "该生产项目不可用"
	if int(fa.tier) < int(spec.get("tier",1)): return "需要先完成科技研究"
	if research:
		if target.kind != "lab": return "请选择核酸研究站"
		if fa.tech.get(kind,false): return "这项研究已经完成"
		if fa.get("researching",false): return "已有研究正在进行"
		for command in pending:
			if command.action == "research": return "这项研究已排队" if command.tech == kind else "已有研究等待执行"
	else:
		if spec.get("at","") != target.kind: return "这座建筑不能训练该细胞"
		var reserved_population := 0
		var queued_here: int = target.queue.size()
		for command in pending:
			if int(command.target) == int(target.id): queued_here += 1
			if command.action == "train": reserved_population += int(WarData.spec(command.unit).get("pop",0))
		if queued_here >= 6: return "生产队列已满（最多 6 项）"
		var population := game.economy.population(faction)
		if population.x+reserved_population+int(spec.get("pop",0)) > population.y: return "人口已满，需要更多栖息泡"
		if kind in ["heavy","siege"]:
			var liver: bool = game.navigation.organ_at(WarData.point(target)) == "liver"
			if game.mode == "sandbox": liver = game.survival.biome(WarData.point(target)).get("detail","") == "liver"
			if not liver: return "强力细胞只能在肝脏训练"
	var reserved := _pending_resource_costs(faction)
	var actual_cost: Dictionary = spec.get("cost",{}) if research else _training_cost(target,kind)
	for resource in actual_cost:
		if game.economy.stock(faction,resource)-float(reserved.get(resource,0)) < float(actual_cost[resource]):
			return "缺少"+str(WarData.config().Data.names[resource])+("（待执行项目已预留）" if float(reserved.get(resource,0)) > 0 else "")
	return ""

func _request_production(target_id: int,kind: String,research: bool) -> void:
	var reason := _production_error(game.entity(target_id),kind,research)
	if not reason.is_empty():
		game.notify(reason)
		return
	var command := {"action":"research" if research else "train","target":target_id}
	command["tech" if research else "unit"] = kind
	game.submit_player(command)
	var name: String = WarData.config().Data.tech[kind].name if research else WarData.spec(kind).name
	game.notify("已排队："+name+" · 恢复时间后执行")
	_refresh_production_menu()

func _refresh_production_menu() -> void:
	if not is_instance_valid(production_pending): return
	var pending := _production_commands(1)
	production_pending.text = "待执行 %d 项 · 返回游戏并恢复时间后开始" % pending.size() if not pending.is_empty() else "菜单已暂停战术时间 · 返回游戏后继续"
	for entry in production_buttons:
		var count := 0
		for command in pending:
			if int(command.target) == entry.target and command.get("tech" if entry.research else "unit","") == entry.kind: count += 1
		var text: String = entry.text
		if not entry.research:
			var target := game.entity(entry.target)
			if not target.is_empty(): text = "训练 · "+str(WarData.spec(entry.kind).name)+" · "+cost_text(_training_cost(target,entry.kind))
		entry.button.text = text+(" · 待执行 %d" % count if count > 0 else "")

func _layout() -> void:
	if root == null: return
	var size := get_viewport().get_visible_rect().size
	var narrow := size.x < 720
	var short := size.y < 570
	var top := 94 if size.x < 1100 else 82
	var brain_size := 88 if short else (104 if size.x < 400 else 116) if narrow else 176
	advisor.position = Vector2(12,8)
	advisor.size = Vector2.ONE*brain_size
	var map_width := 128 if narrow else (152 if short else 168)
	var map_height := 110 if short else (118 if narrow else 140)
	var reserve := map_width+20
	var map_shell: Control = root.get_node("Navigation")
	map_shell.position = Vector2(size.x-12-map_width,12)
	map_shell.size = Vector2(map_width,map_height)
	layer_button.position = Vector2(size.x-56,20+map_height)
	layer_button.size = Vector2(44,44)
	layer_button.text = ""
	overview_button.position = layer_button.position-Vector2(50,0)
	overview_button.size = layer_button.size
	var field := WarDeskMapFrame.rect_for(size)
	inspection.position = field.position
	inspection.size = field.size
	vision_menu.position = Vector2(maxf(12,size.x-12-280),72+map_height)
	vision_menu.size = Vector2(minf(size.x-24,280),330)
	var header: Control = root.get_node("Header")
	var status_width := maxf(80,minf(size.x-brain_size-reserve-36,550))
	header.position = Vector2(size.x-status_width-reserve-12,10)
	header.size = Vector2(status_width,58)
	toolbar.position = Vector2(size.x-minf(397,size.x-reserve-12)-reserve,top+18)
	toolbar.size = Vector2(minf(397,size.x-reserve-12),44)
	if narrow:
		header.visible = false
		toolbar.position = Vector2(12,map_height+76)
		toolbar.size.x = size.x-24
		toolbar.size.y = 70
	else: header.visible = true
	for child in toolbar.get_children():
		child.show()
		child.custom_minimum_size = Vector2((size.x-34)/3 if narrow else (92 if child == pause_button else 44),30 if narrow else 44)
		child.add_theme_font_size_override("font_size",13 if narrow else 16)
	panel.visible = true
	panel.position = Vector2(16,size.y-(156 if narrow else 148))
	panel.size = Vector2(size.x-32 if narrow else 300,140 if narrow else 132)
	root.get_node("Bottom").hide()
	zoom_tools.position = Vector2(16,panel.position.y-106)
	zoom_tools.visible = not narrow
	systemic_panel.visible = not game.scenarios.systemic().is_empty()
	systemic_panel.position = Vector2(12,maxf(top+18,brain_size+18))
	systemic_panel.size = Vector2(minf(size.x-24,302),0)
	if narrow: systemic_panel.visible = false
	status.position = Vector2(16,size.y-(206 if narrow else 194))
	status.size = Vector2(minf(470,size.x-32),42)
	status.show()
	menu.size = Vector2(minf(650,size.x-24),minf(760,size.y-24))
	menu.position = (size-menu.size)*.5
	menu.get_child(0).custom_minimum_size = Vector2.ZERO
	if progress_panel != null:
		progress_panel.position = Vector2(12 if narrow else size.x-minf(410,status_width)-reserve-12,toolbar.position.y+toolbar.size.y+8)
		progress_panel.size = Vector2(size.x-24 if narrow else minf(410,status_width),0)
	if wheel != null and wheel.visible: wheel.reflow()
	if battle != null:
		battle.visible = game.is_campaign()
		if game.is_campaign():
			header.hide(); toolbar.hide(); zoom_tools.hide(); systemic_panel.hide()
			battle.layout(size,map_height+64,reserve)
	if game.life.enabled(): _layout_life(size)

func _layout_life(size: Vector2) -> void:
	var narrow := size.x < 720
	var width := minf(300,size.x-24)
	# Commands stay on the left; outside-life messages occupy the right-hand phone.
	panel.position = Vector2(12,size.y-156)
	panel.size = Vector2(width,140)
	status.position = Vector2(12,panel.position.y-54)
	status.size = Vector2(width,46)
	systemic_panel.position.x = 12
	zoom_tools.position = Vector2(16,panel.position.y-106)
	if narrow:
		advisor.size = Vector2(96,96)
		var map_shell: Control = root.get_node("Navigation")
		map_shell.position = Vector2(size.x-116,8); map_shell.size = Vector2(104,90)
		layer_button.position = Vector2(size.x-50,104); layer_button.size = Vector2(38,32)
		overview_button.position = layer_button.position-Vector2(44,0); overview_button.size = layer_button.size
		toolbar.position = Vector2(size.x-148,142); toolbar.size = Vector2(136,36)
		for child in toolbar.get_children():
			child.visible = child == pause_button or child == speed_button or child.text == "≡"
			child.custom_minimum_size = Vector2(40,32)
		pause_button.text = "▶" if game.paused else "Ⅱ"
	else:
		for child in toolbar.get_children(): child.show()
	if life_dialogue != null: life_dialogue.layout()

func _process(delta: float) -> void:
	if systemic_panel != null and systemic_panel.visible: systemic_panel.size.y = systemic_panel.get_combined_minimum_size().y
	if progress_panel != null and progress_panel.visible: progress_panel.size.y = progress_panel.get_combined_minimum_size().y
	if game == null or game.state.is_empty(): return
	_timer += delta
	if _timer < .15: return
	_timer = 0
	progress_panel.visible = game.mode == "sandbox" and not home.visible and not (get_viewport().get_visible_rect().size.x < 720 and dialogue.active)
	if game.mode == "sandbox":
		var step := clampi(int(game.state.get("tutorial",1)),1,6)
		tutorial_text.text = WarData.read("progress").tutorials[step-1]
		tutorial_meter.value = step
		var outcome: String = game.state.get("outcome","playing")
		goal_text.text = "内域已控制 · 自由探索仍在继续" if outcome == "victory" else ("胞群已失去活性 · 可读取记录" if outcome == "defeat" else "目标 · 维持稳态，击败两个敌群")
		if outcome in ["victory","defeat"] and outcome != outcome_shown and not menu.visible and not home.visible:
			outcome_shown = outcome
			show_outcome(outcome)
	pause_button.text = ("▶" if game.paused else "Ⅱ") if game.life.enabled() and get_viewport().get_visible_rect().size.x < 720 else ("▶ 继续" if game.paused else "Ⅱ 暂停")
	speed_button.text = "%d×" % int(game.speed)
	layer_button.tooltip_text = "视野设置 · "+WarWorldView.MODE_NAMES[world.layer]
	var systemic := game.scenarios.systemic()
	for kind in resource_values:
		var refs: Dictionary = resource_values[kind]
		refs.card.visible = systemic.is_empty() or kind != "wood"
		refs.caption.text = RESOURCE_LABELS[kind]
		refs.card.tooltip_text = "已运抵补给点的"+str(WarData.config().Data.names[kind])+"；采集站库存和红细胞携带物另计。" if game.organ_resources.enabled() else ""
		var amount := int(systemic.get(kind,systemic.get("glucose",0)) if not systemic.is_empty() else game.economy.stock(1,kind))
		if amount != refs.get("last",-1):
			if refs.has("tween"): refs.tween.kill()
			var value_label: Label = refs.value
			var previous := int(value_label.text)
			refs.last = amount
			refs.tween = create_tween()
			refs.tween.tween_method(func(value: float): value_label.text = str(roundi(value)),float(previous),float(amount),.22)
	if game.is_campaign():
		var c: Dictionary = game.state.campaign
		scenario.text = "%s\n第 %d 波 / %d · 补给 %d\n%s" % [game.navigation.campaign.name,int(c.event.wave),game.navigation.campaign.waves.size(),int(c.reinforcements.supply),{"active":"防守中","completed":"已夺回","failed":"防线失守"}.get(c.event.status,"")]
	else:
		var q := game.scenarios.systemic()
		scenario.text = "人体地图 · %02d:%02d\n沿关口进入血管，前往其他器官" % [int(game.state.time)/60,int(game.state.time)%60]
		if not q.is_empty():
			scenario.text = "氧气量 %.0f · 葡萄糖量 %.0f\n心脏存粮 %.0f\n病毒 %d\n%s · 累计送达 %.0f" % [float(q.oxygen),float(q.glucose),float(q.heartGlucose),int(q.get("livingEnemies",3)),q.get("courierState","等待出发"),float(q.delivered)]
	var key := str(game.selected)
	if key != _visual_selection:
		_visual_selection = key
		var surface := panel.get_node("_FacetSurface") as WarFacetSurface
		surface.pulse()
	var selected_entities: Array = []
	for id in game.selected:
		var e := game.entity(id)
		if not e.is_empty(): selected_entities.append(e)
	selection.text = "胞群指挥" if selected_entities.is_empty() else (str(WarData.spec(selected_entities[0].kind).name) if selected_entities.size() == 1 else "已选择 %d 个细胞" % selected_entities.size())
	selection_emblem.entities = selected_entities
	compact_selection.text = selection.text
	if focus_button != null: focus_button.text = "定位下一枚细胞 · C" if selected_entities.is_empty() else "定位选中 · F"
	selection_health.visible = selected_entities.size() == 1
	if selected_entities.is_empty(): details.text = "选择细胞后，点目标位置展开指令"
	elif selected_entities.size() > 1: details.text = "点击目标位置选择指令\nCtrl / ⌘ + 数字保存编队"
	for entry in action_buttons.values():
		if entry.action == "append": entry.button.set_pressed_no_signal(append_orders)
		if entry.action == "box": entry.button.set_pressed_no_signal(box_mode)
	if selected_entities.size() == 1:
		var e: Dictionary = selected_entities[0]
		selection_health.max_value = float(e.maxHp)
		selection_health.value = float(e.hp)
		var lane := int(e.get("vesselLane",0))
		details.text = "生命 %.1f / %.1f · %s\n%s · 命令 %d 项" % [float(e.hp),float(e.maxHp),_display_state(e),("心腔内" if lane >= 203 and lane <= 210 else "血管内") if lane > 0 else "组织地面",e.orders.size()]
		if e.has("combatReserve"): details.text += "\n作战储备 %.1f" % float(e.combatReserve)
		if e.kind == "b_cell": details.text += "\n摇花范围 %.0f · 队友攻速 ×2" % float(WarBCells.data().aura.radius)
		elif game.b_cells.speed_multiplier(e) > 1: details.text += "\n摇花增益 · 攻速 ×2"
		if e.kind == "dendritic_cell": details.text += "\n侦察范围 %.0f · 标记 %d 个敌人\n敌方移速、攻速均降低30%%" % [float(WarDendriticCells.data().scan.radius),game.dendritic.marked_count(e)]
		elif game.dendritic.marked(e): details.text += "\n侦察减速 · 移速×0.7 · 攻速×0.7"
		for kind in e.get("cargo",{}): details.text += "\n%s · %.0f" % [str(WarData.config().Data.names.get(kind,kind)),float(e.cargo[kind])]
		if e.kind == "worker" and game.organ_resources.enabled():
			var resource: Dictionary = {}
			for order in e.orders:
				if order.kind in ["harvest","gather"]:
					resource = game.state.resources.get(str(order.get("resource","")),{}); break
			if resource.get("organSource",false):
				details.text += "\n"+resource_station_text(resource)+"\n"+resource_delivery_text(e,resource)
			elif e.get("delivering",false): details.text += "\n"+resource_delivery_text(e)
		compact_selection.text += " · 生命 %.0f/%.0f" % [float(e.hp),float(e.maxHp)]
	for id in resource_station_labels:
		var resource: Dictionary = game.state.resources.get(id,{})
		if not resource.is_empty() and is_instance_valid(resource_station_labels[id]): resource_station_labels[id].text = resource_station_text(resource)
	_sync_selection_rows(selected_entities)
	_refresh_production_menu()
	var service := _organ_service()
	organ_button.visible = service != null and selected_entities.size() == 1 and not service.available_actions(int(selected_entities[0].id),1).is_empty()
	if organ_button.visible: organ_button.text = "器官协作 · "+str(WarOrganFunctions.data().organs[service.organ(selected_entities[0])].name)
	_refresh_organ_menu()
	_refresh_medicine_menu()

func _display_state(entity: Dictionary) -> String:
	var state: String = entity.get("combatState","idle")
	if entity.get("category","") == "building" and float(entity.get("fire",0)) > 0: return "燃烧"
	if entity.get("kind","") == "worker" and not entity.get("orders",[]).is_empty():
		if entity.orders[0].kind == "farm":
			if entity.get("delivering",false): return "运输"
			if state == "build": return "培育"
		elif entity.orders[0].kind == "extinguish" and state == "build": return "灭火"
	return str(STATES.get(state,"待命"))

func _cancel_selection_item(entity_id: int,item: Dictionary,production: bool) -> void:
	var entity := game.entity(entity_id)
	if entity.is_empty(): return
	var items: Array = entity.queue if production else entity.orders
	var index := -1
	for i in items.size():
		if is_same(items[i],item): index = i; break
	if index < 0: return
	if production:
		game.economy.cancel_production(entity,index)
		game.notify("已取消生产，返还 75% 资源")
	elif index > 0:
		entity.orders.remove_at(index)
		game.notify("已取消后续行动")
	else: game.notify("这项行动已开始")

func _sync_selection_rows(entities: Array) -> void:
	var entity_id := int(entities[0].id) if entities.size() == 1 else -1
	if _selection_rows_entity != entity_id:
		for entry in _selection_rows:
			orders_box.remove_child(entry.button); entry.button.queue_free()
		_selection_rows.clear()
		_selection_rows_entity = entity_id
	if entity_id < 0: return
	var entity: Dictionary = entities[0]
	var next_rows: Array[Dictionary] = []
	for production in [false,true]:
		var items: Array = entity.queue if production else entity.orders
		for i in items.size():
			var item: Dictionary = items[i]
			var row := {}
			for entry in _selection_rows:
				if entry.production == production and is_same(entry.item,item): row = entry; break
			if row.is_empty():
				var control := button("",func(): _cancel_selection_item(entity_id,item,production),orders_box)
				row = {"button":control,"item":item,"production":production}
			if production:
				var name: String = WarData.spec(item.unit).name if item.has("unit") else WarData.config().Data.tech[item.tech].name
				row.button.text = "%s · %d秒  ×" % [name,ceili(item.remaining)]
				row.button.disabled = false
				row.button.tooltip_text = "取消生产，返还 75% 资源"
			else:
				row.button.text = "%d · %s%s" % [i+1,ORDERS.get(item.kind,"行动"),"" if i == 0 else "  ×"]
				row.button.disabled = i == 0
				row.button.tooltip_text = "当前行动进行中" if i == 0 else "取消这项后续行动"
			next_rows.append(row)
	for entry in _selection_rows:
		if not next_rows.any(func(row): return row.button == entry.button):
			orders_box.remove_child(entry.button); entry.button.queue_free()
	for i in next_rows.size(): orders_box.move_child(next_rows[i].button,i)
	_selection_rows = next_rows

func _build_progress() -> void:
	progress_panel = PanelContainer.new(); root.add_child(progress_panel)
	progress_panel.add_theme_stylebox_override("panel",style(WarUISkin.CREAM,14))
	var column := VBoxContainer.new(); progress_panel.add_child(column)
	goal_text = label("目标 · 维持稳态，击败两个敌群",13)
	goal_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; column.add_child(goal_text)
	tutorial_text = label("",11,TEAL)
	tutorial_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; column.add_child(tutorial_text)
	tutorial_meter = ProgressBar.new(); tutorial_meter.show_percentage = false
	tutorial_meter.min_value = 0; tutorial_meter.max_value = 6; tutorial_meter.custom_minimum_size.y = 4
	for key in ["background","fill"]:
		var skin := style(WarUISkin.OAT if key == "background" else TEAL,2); skin.set_content_margin_all(0)
		tutorial_meter.add_theme_stylebox_override(key,skin)
	column.add_child(tutorial_meter)
	progress_panel.hide()

func show_outcome(outcome: String) -> void:
	_clear_menu("最后一处荧光熄灭了" if outcome == "defeat" else "生命的边界，已被拓宽")
	var text := "你的单位和生产建筑已全部损失。\n读取已有记录，再次点亮这片内域。" if outcome == "defeat" else "两个敌群已失去战斗能力。余烬胞群控制了内域。\n继续探索与扩建，或将这段远征保存为记录。"
	var body := label(text,13,MUTED); body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; menu_body.add_child(body)
	if outcome == "defeat":
		button("读取记录",show_saves,menu_body)
		button("建立新胞群",func(): close_menu(); restart_requested.emit("sandbox"),menu_body)
	else:
		button("继续探索",close_menu,menu_body)
		button("保存记录",show_saves,menu_body)
	_open_menu()

func _build_home() -> void:
	home = WarCover.new()
	home.z_index = 80
	home.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	home.visible = false
	root.add_child(home)
	# The opaque cover owns the frame; stop the large map compositor behind it.
	home.visibility_changed.connect(func():
		world.visible = not home.visible
		world.process_mode = Node.PROCESS_MODE_DISABLED if home.visible else Node.PROCESS_MODE_INHERIT)
	(home as WarCover).action_requested.connect(_cover_action)
	cover_preview = WarCoverPreview.new()
	cover_preview.z_index = 95
	root.add_child(cover_preview)
	cover_preview.closed.connect(func(): (home as WarCover).buttons[1].grab_focus())

func _cover_action(action: String) -> void:
	match action:
		"start": home.hide(); restart_requested.emit("life")
		"preview": cover_preview.open()
		"tutorial": show_original_copy("startGuide")
		"settings": show_cover_settings()

func show_cover_settings() -> void:
	_clear_menu("设置")
	var settings := _settings()
	var sound_title := label("声音",16,PAPER)
	menu_body.add_child(sound_title)
	var volume_text := label("主音量：%d%%" % roundi(settings.volume()),13,MUTED)
	menu_body.add_child(volume_text)
	var volume := HSlider.new()
	volume.min_value = 0; volume.max_value = 100; volume.step = 1; volume.value = settings.volume()
	volume.custom_minimum_size = Vector2(360,32)
	volume.value_changed.connect(func(value):
		settings.set_volume(value)
		volume_text.text = "主音量：%d%%" % roundi(value))
	menu_body.add_child(volume)
	var mute := CheckButton.new()
	mute.text = "静音"; mute.button_pressed = settings.muted(); mute.focus_mode = Control.FOCUS_NONE
	mute.toggled.connect(settings.set_muted)
	menu_body.add_child(mute)
	menu_body.add_child(HSeparator.new())
	menu_body.add_child(label("显示",16,PAPER))
	var fullscreen := button("全屏："+("开" if settings.fullscreen() else "关"),func():
		settings.set_fullscreen(not settings.fullscreen(),get_window())
		show_cover_settings(),menu_body)
	fullscreen.tooltip_text = "切换窗口化与全屏显示"
	var sync := button("垂直同步："+("开" if settings.vsync() else "关"),func():
		settings.set_vsync(not settings.vsync())
		show_cover_settings(),menu_body)
	sync.tooltip_text = "开启后减少画面撕裂；关闭可降低输入延迟"
	var fps := button("帧率上限：%d" % settings.fps(),func():
		var targets := [30,60,120]
		settings.set_fps(targets[(targets.find(settings.fps())+1)%targets.size()])
		show_cover_settings(),menu_body)
	fps.tooltip_text = "依次切换 30、60、120 帧"
	var paths := button("路线显示："+("开" if settings.show_paths() else "关"),func():
		settings.set_show_paths(not settings.show_paths())
		world.show_paths = settings.show_paths()
		show_cover_settings(),menu_body)
	paths.tooltip_text = "显示或隐藏单位的移动路线"
	button("恢复默认设置",func(): settings.reset(get_window()); world.show_paths = settings.show_paths(); show_cover_settings(),menu_body)
	menu_body.add_child(HSeparator.new())
	menu_body.add_child(label("游戏入口",16,PAPER))
	button("本地存档 / 继续记录",show_saves,menu_body)
	button("人体生存 · 小脑生活决策",func(): close_menu(); home.hide(); restart_requested.emit("life"),menu_body)
	button("选择战场",show_battlefields,menu_body)
	button("全身沙盒",func(): close_menu(); home.hide(); restart_requested.emit("sandbox"),menu_body)
	button("指挥手册",show_help,menu_body)
	_open_menu()

func _settings() -> WarSettings:
	var scene := get_tree().current_scene
	return scene.settings as WarSettings

func return_home() -> void:
	close_menu()
	if cover_preview != null: cover_preview.hide()
	vision_menu.hide()
	world.layer = 0
	game.paused = true
	game.selected.clear()
	home.show()
