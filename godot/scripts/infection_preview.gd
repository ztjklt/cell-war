class_name WarInfectionPreview
extends CanvasLayer
## Review controls exist only when explicitly opening the infection art preview.
var main
var panel: PanelContainer
var info: Label
var selector: OptionButton
var range_button: Button
var ground_button: Button

func setup(owner_node) -> void:
	main = owner_node
	layer = 3
	var shell := Control.new()
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shell.theme = WarUISkin.theme()
	add_child(shell)
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel",WarUISkin.painted_panel(Color.WHITE,18,10))
	shell.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",9)
	panel.add_child(column)
	var title := Label.new(); title.text = "感染区域 · 地表预览"
	title.add_theme_font_size_override("font_size",18); column.add_child(title)
	selector = OptionButton.new(); WarUISkin.apply_button(selector); column.add_child(selector)
	var zones: Array = main.world.infections.data.zones
	for zone in zones: selector.add_item(zone.name)
	selector.item_selected.connect(func(index): show_organ(zones[index].organ))
	info = Label.new(); info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size",13); column.add_child(info)
	var row := HBoxContainer.new(); column.add_child(row)
	button("看整个范围",func(): overview(),row)
	button("近看感染地板",func(): closeup(),row)
	button("换一个合法落点",func(): next_placement(),column)
	button("换一种铺法",func(): main.world.infections.paving_variation += 1,column)
	range_button = button("隐藏候选范围",func(): toggle_range(),column)
	ground_button = button("对比健康地面",func(): toggle_ground(),column)
	var hint := Label.new()
	hint.text = "青色范围：可能发生感染的区域\n地面薄斑可拼铺成不同的不规则范围\n细线：通往紫色关口的实际路线\n\n本次预览保持暂停，尚未启动刷怪。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size",12); column.add_child(hint)
	button("退出地表预览",func():
		main.world.infections.enabled = false
		queue_free(),column)
	get_viewport().size_changed.connect(layout)
	layout()
	show_organ("lung_r")

func button(text: String,action: Callable,parent: Control) -> Button:
	var node := Button.new(); node.text = text
	WarUISkin.apply_button(node)
	node.custom_minimum_size.y = 34
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.pressed.connect(action); parent.add_child(node)
	return node

func layout() -> void:
	var size := get_viewport().get_visible_rect().size
	panel.position = Vector2(12,200 if size.y >= 760 else 110)
	panel.size = Vector2(minf(310,size.x-24),0)

func _process(_delta: float) -> void:
	if panel != null: panel.size.y = panel.get_combined_minimum_size().y

func show_organ(organ: String) -> void:
	main.world.infections.select(organ)
	main.world.infections.enabled = true
	main.world.infections.ground_visible = true
	main.world.assisted = true
	for i in main.world.infections.data.zones.size():
		if main.world.infections.data.zones[i].organ == organ: selector.select(i)
	update_info()
	overview()

func next_placement() -> void:
	var model: WarInfectionZones = main.world.infections
	model.select(model.zone.organ,model.placement_index+1)
	update_info()
	overview()

func update_info() -> void:
	var model: WarInfectionZones = main.world.infections
	var patch := model.placement()
	info.text = "%s · 落点 %d / %d\n地板边缘距最近关口 %.0f\n通往目标关口的路线 %.0f" % [model.zone.name,model.placement_index+1,model.zone.placements.size(),float(patch.gateGap),float(patch.routeLength)]
	range_button.text = "隐藏候选范围" if main.world.assisted else "显示候选范围"
	ground_button.text = "对比健康地面" if model.ground_visible else "显示感染地板"

func overview() -> void:
	var rect: Rect2 = main.world.infections.overview_bounds()
	var room: Vector2 = main.get_viewport_rect().size-Vector2(530,270)
	var zoom := minf(room.x/maxf(1,rect.size.x),room.y/maxf(1,rect.size.y))*.9
	main.focus(rect.get_center()-Vector2(130/maxf(1,zoom),0),zoom)

func closeup() -> void:
	main.focus(WarData.point(main.world.infections.placement().center)-Vector2(4,0),24)

func toggle_range() -> void:
	main.world.assisted = not main.world.assisted
	update_info()

func toggle_ground() -> void:
	main.world.infections.ground_visible = not main.world.infections.ground_visible
	update_info()
