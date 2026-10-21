class_name WarBattleHUD
extends Control
## BattleHUD.lua / UIModel.battle: original corner pads and free battlefield.
var hud: WarHUD
var bar: PanelContainer
var left: VBoxContainer
var right: VBoxContainer
var gauge: BoxContainer
var chip: Label
var wave: Label
var supply: Label
var pause: Button
var speed: Button
var reinforce: Button
var cards: Array = []
var stage := Rect2()
var bar_body: BoxContainer
var row_a: HBoxContainer
var row_b: HBoxContainer
var tools: HBoxContainer
var gauge_tools: VBoxContainer
var gauge_root: BoxContainer

func setup(owner: WarHUD) -> void:
	hud = owner
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar = _panel()
	bar_body = BoxContainer.new(); bar.add_child(bar_body)
	row_a = HBoxContainer.new(); bar_body.add_child(row_a)
	row_b = HBoxContainer.new(); bar_body.add_child(row_b)
	row_a.add_theme_constant_override("separation",8)
	row_b.add_theme_constant_override("separation",10)
	pause = hud.button("Ⅱ 暂停",func(): hud.game.paused = not hud.game.paused,row_a)
	speed = hud.button("1×",func(): hud.game.speed = 2 if hud.game.speed == 1 else 1,row_a)
	hud.button("下一波",func(): hud.game.submit_player({"action":"skip_wave"}),row_a)
	hud.button("挂机",func(): hud.game.state.campaign.autoplay = not hud.game.state.campaign.get("autoplay",false),row_a)
	wave = hud.label("",11,WarHUD.PAPER); row_a.add_child(wave)
	wave.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wave.clip_text = true
	supply = hud.label("",12,WarHUD.TEAL); row_b.add_child(supply)
	supply.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools = HBoxContainer.new(); row_b.add_child(tools)
	_camera_tools(tools)
	hud.button("≡",hud.toggle_menu,row_b)
	left = VBoxContainer.new(); add_child(left)
	left.add_theme_constant_override("separation",6)
	var picks := HBoxContainer.new(); left.add_child(picks)
	for item in [["全军","army"],["白细胞","spear"],["血小板","scout"]]:
		var kind: String = item[1]
		var btn := hud.button(item[0],func(): _select_kind(kind),picks)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var groups := HBoxContainer.new(); left.add_child(groups)
	for i in 3:
		var index := i
		var btn := hud.button("编"+str(i+1),func():
			if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META): hud.game.groups[index] = hud.game.selected.duplicate()
			else:
				hud.game.selected.clear()
				for id in hud.game.groups[index]:
					if not hud.game.entity(int(id)).is_empty(): hud.game.selected.append(int(id)),groups)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud.button("更多",hud.toggle_menu,groups)
	right = VBoxContainer.new(); add_child(right)
	right.add_theme_constant_override("separation",6)
	reinforce = hud.button("调援 +2 白细胞",func(): hud.game.submit_player({"action":"reinforce"}),right)
	hud.accent_button(reinforce)
	var commands := HBoxContainer.new(); right.add_child(commands)
	for item in [["进攻","attackmove"],["驻守","guard"],["撤退","retreat"],["停止","stop"]]:
		var action: String = item[1]
		var btn := hud.button(item[0],func():
			if action in ["retreat","stop"]: hud.game.issue(action)
			else: hud.command_mode_changed.emit(action),commands)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip = hud.label("",12,WarHUD.PAPER); add_child(chip)
	gauge_root = BoxContainer.new(); add_child(gauge_root)
	gauge_root.add_theme_constant_override("separation",6)
	gauge_tools = VBoxContainer.new(); gauge_root.add_child(gauge_tools)
	hud.button("地图",func(): hud.overview_requested.emit(),gauge_tools)
	hud.button("回营",func(): _home(),gauge_tools)
	var zoom_row := HBoxContainer.new(); gauge_tools.add_child(zoom_row)
	for item in [["＋",1.2],["－",1/1.2]]:
		var factor: float = item[1]
		var btn := hud.button(item[0],func(): hud.focus_requested.emit(hud.camera.position,hud.camera.zoom.x*factor),zoom_row)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gauge = BoxContainer.new(); gauge_root.add_child(gauge)
	gauge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gauge.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gauge.add_theme_constant_override("separation",6)
	for i in 3:
		var index := i
		var card := _panel(gauge)
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var body := VBoxContainer.new(); card.add_child(body)
		var name := hud.label("",12,WarHUD.PAPER); body.add_child(name)
		var status := hud.label("",12,WarHUD.TEAL); body.add_child(status)
		var presence := hud.label("",11,WarHUD.MUTED); body.add_child(presence)
		var meter := ProgressBar.new(); meter.show_percentage = false; meter.min_value = -100; meter.max_value = 100
		meter.custom_minimum_size.y = 4; body.add_child(meter)
		card.gui_input.connect(func(event):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				var zone: Dictionary = hud.game.navigation.campaign.zones[index]
				hud.focus_requested.emit(WarData.point(zone),maxf(.14*32,hud.camera.zoom.x)))
		cards.append({"root":card,"name":name,"status":status,"presence":presence,"meter":meter})

func _camera_tools(parent: Node) -> void:
	hud.button("地图",func(): hud.overview_requested.emit(),parent)
	hud.button("回营",func(): _home(),parent)
	hud.button("＋",func(): hud.focus_requested.emit(hud.camera.position,hud.camera.zoom.x*1.2),parent)
	hud.button("－",func(): hud.focus_requested.emit(hud.camera.position,hud.camera.zoom.x/1.2),parent)

func _panel(parent: Node = null) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := WarHUD.style(WarUISkin.CREAM,14)
	style.set_content_margin_all(4)
	panel.add_theme_stylebox_override("panel",style)
	(parent if parent else self).add_child(panel)
	return panel

func _select_kind(kind: String) -> void:
	hud.game.selected.clear()
	for e in hud.game.units():
		if e.faction == 1 and (e.kind != "worker" if kind == "army" else e.kind == kind): hud.game.selected.append(int(e.id))

func _home() -> void:
	var home := hud.game.scenarios.home()
	hud.focus_requested.emit(home,maxf(.14*32,hud.camera.zoom.x))

func layout(view_size: Vector2,navigation_bottom: float,navigation_reserve: float) -> void:
	var phone := minf(view_size.x,view_size.y) < 600
	var margin := 10.0 if phone else 14.0
	var gap := 6.0 if phone else 8.0
	var primary := 44.0 if phone else 46.0
	var secondary := 38.0
	var advisor := (72.0 if view_size.y > view_size.x else 64.0) if phone else 112.0
	var bar_rect := Rect2(Vector2(margin+advisor+gap,margin),Vector2(view_size.x-(margin+advisor+gap)-margin-navigation_reserve,0))
	if bar_rect.size.x < 340: bar_rect.position = Vector2(margin,navigation_bottom+gap); bar_rect.size.x = view_size.x-2*margin
	var rows := 2 if bar_rect.size.x < 720 else 1
	bar_rect.size.y = (44 if phone else 52)*rows+gap*(rows-1)
	bar_body.vertical = rows == 2
	bar_body.add_theme_constant_override("separation",4 if rows == 2 else 14)
	tools.visible = rows == 1
	row_a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL if rows == 2 else Control.SIZE_SHRINK_END
	var widths := [64 if phone else 78,40,74 if phone else 82,60 if phone else 66]
	for i in 4:
		var btn: Button = row_a.get_child(i)
		btn.custom_minimum_size = Vector2(widths[i],(bar_rect.size.y-12)/2 if rows == 2 else bar_rect.size.y-8)
		btn.add_theme_font_size_override("font_size",17)
		_fit_button(btn)
	row_b.get_child(-1).custom_minimum_size = Vector2(44,(bar_rect.size.y-12)/2 if rows == 2 else bar_rect.size.y-8)
	_fit_button(row_b.get_child(-1))
	bar.position = bar_rect.position; bar.size = bar_rect.size
	# Unit orders live around the map target; retain only scenario reinforcement.
	left.hide()
	right.get_child(1).hide()
	chip.hide()
	var pad_width := 184.0 if phone else 216.0
	right.position = Vector2(view_size.x-margin-pad_width,view_size.y-margin-46)
	right.size = Vector2(pad_width,46)
	reinforce.custom_minimum_size = Vector2(pad_width,46)
	if phone:
		right.position.y = hud.panel.position.y-54
	var top := maxf(bar_rect.end.y+gap,margin+advisor+gap)
	var bounds: Dictionary = hud.game.navigation.campaign.bounds
	var tall: bool = bounds.h > bounds.w
	var gauge_rect: Rect2
	if tall:
		var gauge_top := maxf(top,navigation_bottom+gap)
		gauge_rect = Rect2(view_size.x-margin-100,gauge_top,100,maxf(160,minf(340,right.position.y-gap-gauge_top)))
		stage = Rect2(margin,top,view_size.x-margin*2-108,maxf(120,view_size.y-top-24))
	else:
		gauge_rect = Rect2(bar_rect.position.x,bar_rect.end.y+gap,bar_rect.size.x,52)
		var y := maxf(gauge_rect.end.y,navigation_bottom)+gap
		stage = Rect2(margin,y,view_size.x-2*margin,maxf(120,view_size.y-y-24))
	gauge_root.vertical = tall
	gauge.vertical = tall
	gauge_root.position = gauge_rect.position; gauge_root.size = gauge_rect.size
	gauge_tools.visible = rows == 2
	for child in gauge_tools.get_children():
		if child is Button:
			child.custom_minimum_size = Vector2(0,30 if phone else 34)
			child.add_theme_font_size_override("font_size",15)
			_fit_button(child)
		elif child is HBoxContainer:
			for btn in child.get_children():
				btn.custom_minimum_size = Vector2(0,30 if phone else 34)
				_fit_button(btn)
	for card in cards:
		card.name.add_theme_font_size_override("font_size",13 if phone else 16)
		card.status.add_theme_font_size_override("font_size",13 if phone else 15)
		card.presence.add_theme_font_size_override("font_size",11 if phone else 13)
		card.root.get_child(0).add_theme_constant_override("separation",0 if phone else 4)
	hud.advisor.position = Vector2.ONE*margin; hud.advisor.size = Vector2.ONE*advisor
	hud.status.position = Vector2(margin,hud.panel.position.y-48); hud.status.size.x = minf(420,view_size.x-24)

func _fit_button(btn: Button) -> void:
	for key in ["normal","hover","pressed","focus"]:
		var skin := btn.get_theme_stylebox(key).duplicate() as StyleBoxFlat
		skin.content_margin_left = 2; skin.content_margin_right = 2
		skin.content_margin_top = 0; skin.content_margin_bottom = 0
		btn.add_theme_stylebox_override(key,skin)

func _process(_delta: float) -> void:
	if hud == null or not hud.game.is_campaign(): return
	var campaign: Dictionary = hud.game.state.campaign
	var spec: Dictionary = hud.game.navigation.campaign
	var event: Dictionary = campaign.event
	pause.text = "▶ 继续" if hud.game.paused else "Ⅱ 暂停"
	speed.text = str(int(hud.game.speed))+"×"
	wave.text = "第 %d / %d 波" % [int(event.wave),spec.waves.size()]
	supply.text = "补给 %d / %d" % [int(campaign.reinforcements.supply),int(spec.supply.max)]
	reinforce.disabled = float(campaign.reinforcements.cooldown) > 0 or int(campaign.reinforcements.supply) < int(spec.supply.cost) or event.status != "active"
	chip.text = "已选择 %d 个细胞" % hud.game.selected.size() if not hud.game.selected.is_empty() else ""
	for i in mini(cards.size(),spec.zones.size()):
		var card: Dictionary = cards[i]
		var zone: Dictionary = event.zones[i]
		card.name.text = spec.zones[i].name
		card.status.text = ("争夺中" if zone.get("contested",false) else ("免疫 " if zone.control >= 0 else "病毒 ")+str(roundi(absf(zone.control)))+"%")
		card.presence.text = "我 %d · 敌 %d" % [int(zone.get("friendly",0)),int(zone.get("hostile",0))]
		card.meter.value = zone.control
		var color := WarHUD.TEAL if zone.owner == 1 else (Color("cf806a") if zone.owner == 2 else Color("a49aab"))
		if zone.get("contested",false): color = Color("9b783e")
		card.status.add_theme_color_override("font_color",color)
		var background := WarHUD.style(Color("cf806a"),2)
		var fill := WarHUD.style(WarHUD.TEAL,2)
		background.set_content_margin_all(0); fill.set_content_margin_all(0)
		card.meter.add_theme_stylebox_override("background",background)
		card.meter.add_theme_stylebox_override("fill",fill)
