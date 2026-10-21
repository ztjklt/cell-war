class_name WarCoverPreview
extends Control
## Read-only character archive, sharing the live game's cream/cocoa UI skin.
signal closed
var page := "characters"
var panel: PanelContainer
var body: VBoxContainer
var grid: GridContainer
var map_canvas: MapCanvas
var character_count := 0
var close_button: Button
var character_tab: Button
var map_tab: Button
var character_view: VBoxContainer
var map_view: VBoxContainer
var filters: HBoxContainer
var search: LineEdit
var count_label: Label
var split: HBoxContainer
var roster: ScrollContainer
var detail_scroll: ScrollContainer
var detail: VBoxContainer
var presentation: BoxContainer
var visual: VBoxContainer
var information: VBoxContainer
var detail_back: Button
var detail_name_row: HBoxContainer
var detail_role_row: HBoxContainer
var short_heading: Label
var title_label: Label
var role_label: Label
var status_label: Label
var summary_label: Label
var mechanism_box: VBoxContainer
var stats_grid: GridContainer
var note_label: Label
var player: WarCataloguePlayer
var previous_action_button: Button
var next_action_button: Button
var action_picker: OptionButton
var pause_button: Button
var replay_button: Button
var playback_label: Label
var progress_bar: ProgressBar
var index_label: Label
var previous_button: Button
var next_button: Button
var entries: Array = []
var filtered: Array = []
var category := "all"
var selected_id := ""
var mobile_detail := false
var compact := false
var portrait_cache: Dictionary = {}
var category_buttons: Dictionary = {}
const CATEGORY_NAMES := {"all":"全部","cells":"细胞","pathogens":"病原体","medicines":"药物"}

class MapCanvas extends Control:
	var textures := WarTextures.new()
	var region := Rect2(0,0,1024,1536)
	var tiles: Array = []
	var loaded_count := 0
	func _ready() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		textures.budget = 64*1024*1024
		visibility_changed.connect(func():
			set_process(is_visible_in_tree())
			if not is_visible_in_tree(): textures.close())
		resized.connect(queue_redraw)
		select_region("fullbody")
	func select_region(id: String) -> void:
		region = Rect2(0,0,1024,1536)
		var organs: Dictionary = WarData.read("organs")
		if id == "lungs":
			region = organ_box(organs.lung_l).merge(organ_box(organs.lung_r))
		elif organs.has(id): region = organ_box(organs[id])
		if id != "fullbody": region = region.grow(18)
		tiles.clear()
		var art: Dictionary = WarData.read("art")
		for layer in ["foundation","organs","blood"]:
			for tile in art[layer]:
				var spec: Dictionary = tile.levels["4"]
				var b: Array = spec.sourceBox
				var box := Rect2(b[0],b[1],b[2]-b[0],b[3]-b[1])
				if region.intersects(box): tiles.append({"path":spec.resource,"box":box})
		queue_redraw()
	func organ_box(organ: Dictionary) -> Rect2:
		var b: Array = organ.sourceBox
		return Rect2(b[0],b[1],b[2]-b[0],b[3]-b[1])
	func _process(_delta: float) -> void:
		for tile in tiles: textures.request(tile.path)
		textures.update()
		queue_redraw()
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO,size),Color("fffcf6"))
		var fit := minf((size.x-16)/region.size.x,(size.y-16)/region.size.y)
		draw_set_transform(size*.5-region.get_center()*fit,0,Vector2.ONE*fit)
		loaded_count = 0
		for tile in tiles:
			var texture := textures.get_texture(tile.path)
			if texture:
				draw_texture_rect(texture,tile.box,false)
				loaded_count += 1
		draw_set_transform_matrix(Transform2D.IDENTITY)
	func _exit_tree() -> void:
		textures.close()

func _ready() -> void:
	name = "CharacterPreview"
	theme = WarUISkin.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(.18,.22,.18,.68)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(center)
	panel = PanelContainer.new(); center.add_child(panel)
	panel.add_theme_stylebox_override("panel",WarUISkin.panel(WarUISkin.CREAM,22,20))
	body = VBoxContainer.new(); body.add_theme_constant_override("separation",12); panel.add_child(body)
	var header := HBoxContainer.new(); body.add_child(header)
	var title := _label("角色档案",30)
	title.add_theme_font_override("font",WarUISkin.DISPLAY)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; header.add_child(title)
	close_button = _button("返回封面",close); close_button.name = "ReturnToCover"; header.add_child(close_button)
	var tabs := HBoxContainer.new(); body.add_child(tabs)
	character_tab = _button("角色预览",show_characters); character_tab.toggle_mode = true; _selected_style(character_tab); tabs.add_child(character_tab)
	map_tab = _button("地图预览",show_maps); map_tab.toggle_mode = true; _selected_style(map_tab); tabs.add_child(map_tab)
	entries = WarData.read("character_catalogue").entries
	character_count = entries.size()
	_build_characters()
	_build_maps()
	resized.connect(_layout)
	visibility_changed.connect(func(): set_process(is_visible_in_tree()))
	_layout()
	show_characters()
	hide()

func _build_characters() -> void:
	character_view = VBoxContainer.new(); character_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	character_view.add_theme_constant_override("separation",10); body.add_child(character_view)
	filters = HBoxContainer.new(); character_view.add_child(filters)
	for key in CATEGORY_NAMES:
		var button := _button(CATEGORY_NAMES[key],func(): set_category(key))
		button.name = "Filter_"+key; button.toggle_mode = true; _selected_style(button)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		filters.add_child(button); category_buttons[key] = button
	var search_row := HBoxContainer.new(); character_view.add_child(search_row)
	search = LineEdit.new(); search.name = "CharacterSearch"; search.placeholder_text = "搜索名称、定位或机制"
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL; search.custom_minimum_size.y = 40
	search.add_theme_stylebox_override("normal",WarUISkin.panel(Color("fffcf5"),10,10))
	search.add_theme_stylebox_override("focus",WarUISkin.button_box("focus"))
	search.add_theme_color_override("font_color",WarUISkin.INK)
	search.add_theme_color_override("font_placeholder_color",WarUISkin.MUTED)
	search_row.add_child(search)
	search_row.add_child(_button("清空",func(): search.text = ""; _rebuild_roster()))
	search.text_changed.connect(func(_text): _rebuild_roster())
	count_label = _label("",13); character_view.add_child(count_label)
	split = HBoxContainer.new(); split.add_theme_constant_override("separation",18)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL; character_view.add_child(split)
	roster = ScrollContainer.new(); roster.name = "CharacterRoster"
	roster.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	roster.follow_focus = true; split.add_child(roster)
	grid = GridContainer.new(); grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",8); grid.add_theme_constant_override("v_separation",8)
	roster.add_child(grid)
	detail_scroll = ScrollContainer.new(); detail_scroll.name = "CharacterDetails"
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.follow_focus = true; split.add_child(detail_scroll)
	detail = VBoxContainer.new(); detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation",10); detail_scroll.add_child(detail)
	detail_back = _button("返回列表",_return_to_roster)
	detail_name_row = HBoxContainer.new(); detail.add_child(detail_name_row)
	title_label = _label("",28); title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.add_theme_font_override("font",WarUISkin.DISPLAY)
	detail_name_row.add_child(title_label)
	detail_role_row = HBoxContainer.new(); detail_role_row.add_theme_constant_override("separation",12); detail.add_child(detail_role_row)
	role_label = _label("",15); role_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; detail_role_row.add_child(role_label)
	status_label = _label("",12); status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_label.add_theme_color_override("font_color",WarUISkin.MUTED); detail_role_row.add_child(status_label)
	presentation = BoxContainer.new(); presentation.add_theme_constant_override("separation",20); detail.add_child(presentation)
	visual = VBoxContainer.new(); visual.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	visual.add_theme_constant_override("separation",10); presentation.add_child(visual)
	information = VBoxContainer.new(); information.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	information.add_theme_constant_override("separation",12); presentation.add_child(information)
	var stage := PanelContainer.new(); stage.add_theme_stylebox_override("panel",WarUISkin.panel(Color("f3ecd9"),18,8)); visual.add_child(stage)
	player = WarCataloguePlayer.new(); player.name = "CharacterArtwork"
	player.custom_minimum_size.y = 270; stage.add_child(player)
	player.playback_changed.connect(_refresh_playback)
	var action_row := HBoxContainer.new(); visual.add_child(action_row)
	previous_action_button = _button("‹",func(): step_action(-1)); previous_action_button.tooltip_text = "上一个动作"
	previous_action_button.custom_minimum_size.x = 36; action_row.add_child(previous_action_button)
	action_picker = OptionButton.new(); action_picker.name = "ActionPicker"
	action_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_picker.custom_minimum_size.y = 42; action_picker.fit_to_longest_item = false
	WarUISkin.apply_button(action_picker,"",false); action_row.add_child(action_picker)
	next_action_button = _button("›",func(): step_action(1)); next_action_button.tooltip_text = "下一个动作"
	next_action_button.custom_minimum_size.x = 36; action_row.add_child(next_action_button)
	action_picker.item_selected.connect(func(index): player.select_mode(index); _refresh_playback())
	var playback_row := HBoxContainer.new(); visual.add_child(playback_row)
	pause_button = _button("暂停",func(): player.toggle_playing()); pause_button.name = "PauseAnimation"; WarUISkin.apply_button(pause_button,"sage",false); playback_row.add_child(pause_button)
	replay_button = _button("重播",func(): player.restart()); playback_row.add_child(replay_button)
	playback_label = _label("",12); playback_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	playback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; playback_row.add_child(playback_label)
	progress_bar = ProgressBar.new(); progress_bar.show_percentage = false; progress_bar.custom_minimum_size.y = 5
	visual.add_child(progress_bar)
	short_heading = _label("",16); information.add_child(short_heading)
	summary_label = _label("",16); information.add_child(summary_label)
	information.add_child(_label("机能与机制",20))
	mechanism_box = VBoxContainer.new(); mechanism_box.add_theme_constant_override("separation",8); information.add_child(mechanism_box)
	stats_grid = GridContainer.new(); stats_grid.columns = 3
	stats_grid.add_theme_constant_override("h_separation",8); stats_grid.add_theme_constant_override("v_separation",8); information.add_child(stats_grid)
	note_label = _label("",13); note_label.add_theme_color_override("font_color",WarUISkin.MUTED); information.add_child(note_label)
	var nav := HBoxContainer.new(); character_view.add_child(nav)
	nav.add_child(detail_back)
	previous_button = _button("‹ 上一个",func(): step_character(-1)); nav.add_child(previous_button)
	index_label = _label("",13); index_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	index_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; nav.add_child(index_label)
	next_button = _button("下一个 ›",func(): step_character(1)); nav.add_child(next_button)
	_rebuild_roster()

func _build_maps() -> void:
	map_view = VBoxContainer.new(); map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL; body.add_child(map_view)
	var choices := HFlowContainer.new(); map_view.add_child(choices)
	for entry in [["全身地图","fullbody"],["心脏","heart"],["双肺","lungs"],["小肠","small_intestine"]]:
		var id: String = entry[1]
		var button := _button(entry[0],func(): map_canvas.select_region(id))
		choices.add_child(button)
	map_canvas = MapCanvas.new(); map_canvas.name = "RuntimeMapPreview"
	map_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_view.add_child(map_canvas)
	map_view.add_child(_label("观察真实地图 · 全身 / 心脏 / 双肺 / 小肠",13))
	map_view.hide()

func open() -> void:
	show()
	show_characters()
	close_button.grab_focus()

func close() -> void:
	hide()
	closed.emit()

func show_characters() -> void:
	page = "characters"
	character_view.show(); map_view.hide()
	character_tab.set_pressed_no_signal(true); map_tab.set_pressed_no_signal(false)
	_layout()

func show_maps() -> void:
	page = "maps"
	character_view.hide(); map_view.show()
	character_tab.set_pressed_no_signal(false); map_tab.set_pressed_no_signal(true)
	_layout()

func set_category(value: String) -> void:
	category = value
	mobile_detail = false
	_rebuild_roster()

func _rebuild_roster() -> void:
	for child in grid.get_children(): grid.remove_child(child); child.queue_free()
	filtered.clear()
	var query := search.text.strip_edges().to_lower()
	for entry in entries:
		if category != "all" and entry.category != category: continue
		var haystack := (str(entry.name)+" "+str(entry.role)+" "+str(entry.summary)+" "+" ".join(entry.mechanics)).to_lower()
		if not query.is_empty() and not haystack.contains(query): continue
		filtered.append(entry)
	for entry in filtered:
		var id: String = entry.id
		var card := _button("",func(): select_character(id,true))
		_selected_style(card,true)
		card.name = "Card_"+id; card.set_meta("entry_id",id); card.toggle_mode = true
		card.custom_minimum_size = Vector2(126,146); card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.tooltip_text = entry.name+" · "+entry.role
		grid.add_child(card)
		var column := VBoxContainer.new(); column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		column.offset_left = 8; column.offset_top = 8; column.offset_right = -8; column.offset_bottom = -8
		card.add_child(column)
		var art := TextureRect.new(); art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.texture = _portrait(entry.portrait); art.custom_minimum_size.y = 88
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		column.add_child(art)
		var label := _label(entry.name,14); label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; column.add_child(label)
		var tag := _label(str(entry.role).split(" / ")[0],11); tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.add_theme_color_override("font_color",WarUISkin.MUTED); column.add_child(tag)
	for key in category_buttons:
		category_buttons[key].set_pressed_no_signal(key == category)
	count_label.text = "%d 个角色 · %s" % [filtered.size(),"查看形象、动作与机制" if search.text.is_empty() else "搜索结果"]
	previous_button.disabled = filtered.size() <= 1; next_button.disabled = filtered.size() <= 1
	if filtered.is_empty():
		var empty := _label("没有匹配的角色\n试试其他名称，或清空搜索。",16)
		empty.custom_minimum_size.x = 260; grid.add_child(empty)
		mobile_detail = false
		index_label.text = "暂无结果"
	else:
		var found := false
		for entry in filtered:
			if entry.id == selected_id: found = true; break
		select_character(selected_id if found else str(filtered[0].id),false)
	roster.scroll_vertical = 0
	_layout()

func _portrait(path: String) -> Texture2D:
	if not portrait_cache.has(path):
		var original := load(path) as Texture2D
		var atlas := AtlasTexture.new(); atlas.atlas = original
		atlas.region = original.get_image().get_used_rect()
		portrait_cache[path] = atlas
	return portrait_cache[path]

func select_character(id: String,from_card := false) -> void:
	var index := -1
	for i in filtered.size():
		if filtered[i].id == id: index = i; break
	if index < 0: return
	selected_id = id
	var entry: Dictionary = filtered[index]
	title_label.text = entry.name; role_label.text = entry.role
	status_label.text = entry.status
	short_heading.text = entry.name+" · "+entry.status
	summary_label.text = entry.summary
	note_label.text = entry.note
	for child in mechanism_box.get_children(): mechanism_box.remove_child(child); child.queue_free()
	for i in entry.mechanics.size():
		var row := HBoxContainer.new(); mechanism_box.add_child(row)
		var number := _label("%02d" % (i+1),13); number.custom_minimum_size.x = 26
		number.add_theme_color_override("font_color",WarUISkin.MUTED); row.add_child(number)
		var label := _label(entry.mechanics[i],14); label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(label)
	for child in stats_grid.get_children(): stats_grid.remove_child(child); child.queue_free()
	if not str(entry.kind).is_empty():
		var spec: Dictionary = WarData.spec(entry.kind)
		for pair in [["生命","hp"],["单次伤害","damage"],["移动速度","speed"],["射程","range"],["攻击间隔","cool"],["视野","vision"]]:
			var tile := PanelContainer.new(); tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tile.add_theme_stylebox_override("panel",WarUISkin.panel(WarUISkin.OAT,10,10)); stats_grid.add_child(tile)
			var column := VBoxContainer.new(); tile.add_child(column)
			column.add_child(_label(pair[0],11))
			var value := str(spec.get(pair[1],"—"))
			if entry.kind in ["b_cell","dendritic_cell"] and pair[1] in ["range","cool"]: value = "—"
			column.add_child(_label(value+(" 秒" if pair[1] == "cool" and value != "—" else ""),18))
		stats_grid.tooltip_text = "当前单位基础配置；局内状态、增益与血流会改变实际表现。"
	action_picker.clear()
	action_picker.add_item("全动作循环 · %d 组" % entry.actions.size())
	action_picker.add_item("角色立绘")
	for action in entry.actions: action_picker.add_item(action.name)
	action_picker.set_item_disabled(0,entry.actions.is_empty())
	previous_action_button.disabled = entry.actions.is_empty(); next_action_button.disabled = entry.actions.is_empty()
	player.select(entry)
	action_picker.select(player.mode)
	_refresh_playback()
	index_label.text = "%02d / %02d" % [index+1,filtered.size()]
	for card in grid.get_children():
		if card is Button: card.set_pressed_no_signal(card.get_meta("entry_id","") == id)
	detail_scroll.scroll_vertical = 0
	if from_card: mobile_detail = true
	_layout()
	if from_card and compact: detail_back.grab_focus()

func step_character(direction: int) -> void:
	if filtered.is_empty(): return
	var index := 0
	for i in filtered.size():
		if filtered[i].id == selected_id: index = i; break
	select_character(filtered[posmod(index+direction,filtered.size())].id,compact)

func _return_to_roster() -> void:
	mobile_detail = false
	_layout()
	var card := grid.get_node_or_null("Card_"+selected_id) as Button
	if card: card.grab_focus()

func step_action(direction: int) -> void:
	if player.entry.actions.is_empty(): return
	var index := posmod(player.mode+direction,action_picker.item_count)
	action_picker.select(index)
	player.select_mode(index)

func _selected_style(button: Button,subtle := false) -> void:
	var box := WarUISkin.panel(WarUISkin.SAGE.lightened(.68) if subtle else WarUISkin.SAGE.lightened(.3),14,8)
	box.border_color = WarUISkin.SAGE; box.set_border_width_all(2)
	button.add_theme_stylebox_override("pressed",box)

func _refresh_playback() -> void:
	if pause_button == null: return
	var action := player.current_action()
	pause_button.disabled = action.is_empty(); replay_button.disabled = action.is_empty()
	pause_button.text = "暂停" if player.playing else "播放"
	progress_bar.visible = not action.is_empty()
	if action.is_empty(): playback_label.text = "立绘展示"

func _process(_delta: float) -> void:
	if page != "characters" or not detail_scroll.visible: return
	var action := player.current_action()
	if action.is_empty(): return
	playback_label.text = "%s · %d / %d" % [action.name,player.frame_index+1,action.frames.size()]
	progress_bar.value = minf(100,100*player.elapsed/float(action.duration))

func _layout() -> void:
	if panel == null: return
	compact = size.x < 760 or size.y < 500
	var margin := 10.0 if compact else 24.0
	panel.custom_minimum_size = Vector2(minf(size.x-margin*2,1180),minf(size.y-margin*2,840))
	var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
	if style.content_margin_left != (12 if compact else 20): style.set_content_margin_all(12 if compact else 20)
	if split == null: return
	roster.custom_minimum_size.x = 0 if compact else 304
	roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL if compact else Control.SIZE_FILL
	roster.visible = not compact or not mobile_detail or filtered.is_empty()
	detail_scroll.visible = not filtered.is_empty() and (not compact or mobile_detail)
	detail_back.visible = compact and mobile_detail
	filters.visible = not compact or not mobile_detail
	search.get_parent().visible = not compact or not mobile_detail
	count_label.visible = not compact or not mobile_detail
	var short_landscape := size.y < 500 and size.x >= 760
	detail_name_row.visible = not short_landscape; detail_role_row.visible = not short_landscape
	short_heading.visible = short_landscape
	presentation.vertical = size.x < 760 or (size.x < 1100 and not short_landscape)
	player.custom_minimum_size.y = 120 if short_landscape else (200 if compact else 220)
	stats_grid.columns = 2 if compact else 3
	for button in category_buttons.values():
		button.add_theme_font_size_override("font_size",16 if compact else 19)

func _input(event: InputEvent) -> void:
	if not visible or not event.is_pressed(): return
	if event.is_action_pressed("ui_cancel"):
		if page == "characters" and compact and mobile_detail: _return_to_roster()
		else: close()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.keycode == KEY_TAB:
		# Keep keyboard navigation inside this modal, including after tab switches.
		var controls: Array[Control] = []
		for child in find_children("*","Control",true,false):
			if child.is_visible_in_tree() and child.focus_mode == Control.FOCUS_ALL:
				if child is BaseButton and child.disabled: continue
				controls.append(child)
		if not controls.is_empty():
			var index := controls.find(get_viewport().gui_get_focus_owner())
			controls[posmod(index+(-1 if event.shift_pressed else 1),controls.size())].grab_focus()
		get_viewport().set_input_as_handled()

func _label(text: String,font_size: int) -> Label:
	var label := Label.new(); label.text = text
	label.add_theme_font_size_override("font_size",font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(text: String,callback: Callable) -> Button:
	var button := Button.new(); button.text = text; button.custom_minimum_size.y = 40
	WarUISkin.apply_button(button,"",false)
	button.pressed.connect(callback)
	return button
