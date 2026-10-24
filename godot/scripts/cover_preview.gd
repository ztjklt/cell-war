class_name WarCoverPreview
extends Control
## Read-only collectible archive, using the approved cream/cocoa cell palette.
const CatalogueSkin = preload("res://scripts/catalogue_skin.gd")
const Stage = preload("res://scripts/catalogue_stage.gd")
const Motion = preload("res://scripts/catalogue_motion.gd")
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
var building_tab: Button
var character_view: VBoxContainer
var map_view: VBoxContainer
var building_view: VBoxContainer
var sidebar: VBoxContainer
var sidebar_tools: BoxContainer
var archive_header: HBoxContainer
var archive_tabs: HBoxContainer
var archive_subtitle: Label
var archive_number: Label
var stage: Control
var action_caption: Label
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
	theme = CatalogueSkin.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(.12,.18,.15,.94)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	# A plain host does not retain a transient child minimum after page changes.
	var center := Control.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(center)
	panel = PanelContainer.new(); center.add_child(panel)
	var paper := CatalogueSkin.panel(CatalogueSkin.PAPER,24,24)
	panel.add_theme_stylebox_override("panel",paper)
	body = VBoxContainer.new(); body.add_theme_constant_override("separation",14); panel.add_child(body)
	var header := HBoxContainer.new(); header.add_theme_constant_override("separation",16); body.add_child(header)
	archive_header = header
	var heading := VBoxContainer.new(); heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL; header.add_child(heading)
	heading.add_theme_constant_override("separation",3)
	var title := _label("角色档案",28); title.add_theme_font_override("font",WarUISkin.DISPLAY); heading.add_child(title)
	archive_subtitle = _label("C E L L   A T L A S   /   微观生命收藏馆",11)
	archive_subtitle.add_theme_color_override("font_color",CatalogueSkin.MUTED); heading.add_child(archive_subtitle)
	close_button = _button("返回封面",close); close_button.name = "ReturnToCover"
	CatalogueSkin.glyph(close_button,"close",true)
	close_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER; header.add_child(close_button)
	var tabs := HBoxContainer.new(); tabs.add_theme_constant_override("separation",8); body.add_child(tabs)
	archive_tabs = tabs
	character_tab = _button("角色预览",show_characters); character_tab.toggle_mode = true; _selected_style(character_tab); tabs.add_child(character_tab)
	map_tab = _button("地图预览",show_maps); map_tab.toggle_mode = true; _selected_style(map_tab); tabs.add_child(map_tab)
	building_tab = _button("建筑预览",show_buildings); building_tab.toggle_mode = true; _selected_style(building_tab); tabs.add_child(building_tab)
	CatalogueSkin.glyph(character_tab,"cell"); CatalogueSkin.glyph(map_tab,"map"); CatalogueSkin.glyph(building_tab,"building")
	for tab in [character_tab,map_tab,building_tab]: tab.custom_minimum_size.x = 100
	body.add_child(_rule())
	entries = WarData.read("character_catalogue").entries
	character_count = entries.size()
	_build_characters()
	_build_maps()
	_build_buildings()
	panel.minimum_size_changed.connect(func(): call_deferred("_fit_panel"))
	resized.connect(_layout)
	visibility_changed.connect(func(): set_process(is_visible_in_tree()))
	_layout()
	show_characters()
	hide()

func _build_characters() -> void:
	character_view = VBoxContainer.new(); character_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	character_view.add_theme_constant_override("separation",12); body.add_child(character_view)
	split = HBoxContainer.new(); split.add_theme_constant_override("separation",24)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL; character_view.add_child(split)
	sidebar = VBoxContainer.new(); sidebar.add_theme_constant_override("separation",12); split.add_child(sidebar)
	sidebar_tools = BoxContainer.new(); sidebar_tools.vertical = true; sidebar_tools.add_theme_constant_override("separation",12); sidebar.add_child(sidebar_tools)
	filters = HBoxContainer.new(); filters.add_theme_constant_override("separation",4); filters.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sidebar_tools.add_child(filters)
	for key in CATEGORY_NAMES:
		var button := _button(CATEGORY_NAMES[key],func(): set_category(key))
		button.name = "Filter_"+key; button.toggle_mode = true; _selected_style(button)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		filters.add_child(button); category_buttons[key] = button
	var search_row := HBoxContainer.new(); search_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sidebar_tools.add_child(search_row)
	search = LineEdit.new(); search.name = "CharacterSearch"; search.placeholder_text = "搜索角色、定位、机制"
	search.clear_button_enabled = true
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL; search.custom_minimum_size.y = 42
	CatalogueSkin.field(search)
	search_row.add_child(search)
	search.text_changed.connect(func(_text): _rebuild_roster())
	count_label = _label("",12); count_label.add_theme_color_override("font_color",CatalogueSkin.MUTED); sidebar.add_child(count_label)
	roster = ScrollContainer.new(); roster.name = "CharacterRoster"
	roster.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	roster.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roster.follow_focus = true; sidebar.add_child(roster)
	grid = GridContainer.new(); grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",8); grid.add_theme_constant_override("v_separation",8)
	roster.add_child(grid)
	detail_scroll = ScrollContainer.new(); detail_scroll.name = "CharacterDetails"
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.follow_focus = true; split.add_child(detail_scroll)
	detail = VBoxContainer.new(); detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation",14); detail_scroll.add_child(detail)
	detail_back = _button("列表",_return_to_roster); CatalogueSkin.glyph(detail_back,"left")
	detail_name_row = HBoxContainer.new(); detail.add_child(detail_name_row)
	title_label = _label("",32); title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_name_row.add_child(title_label)
	archive_number = _label("",13); archive_number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	archive_number.autowrap_mode = TextServer.AUTOWRAP_OFF
	archive_number.add_theme_color_override("font_color",CatalogueSkin.MUTED); detail_name_row.add_child(archive_number)
	detail_role_row = HBoxContainer.new(); detail_role_row.add_theme_constant_override("separation",12); detail.add_child(detail_role_row)
	role_label = _label("",14); role_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	role_label.add_theme_color_override("font_color",CatalogueSkin.MUTED); detail_role_row.add_child(role_label)
	status_label = _label("",12); status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.add_theme_color_override("font_color",CatalogueSkin.GREEN); detail_role_row.add_child(status_label)
	presentation = BoxContainer.new(); presentation.add_theme_constant_override("separation",22); detail.add_child(presentation)
	visual = VBoxContainer.new(); visual.size_flags_horizontal = Control.SIZE_EXPAND_FILL; visual.size_flags_stretch_ratio = 1.25
	visual.add_theme_constant_override("separation",12); presentation.add_child(visual)
	information = VBoxContainer.new(); information.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	information.add_theme_constant_override("separation",14); presentation.add_child(information)
	stage = Stage.new(); stage.name = "SpecimenStage"; stage.custom_minimum_size.y = 350; visual.add_child(stage)
	player = WarCataloguePlayer.new(); player.name = "CharacterArtwork"
	stage.add_child(player); player.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	player.offset_left = 22; player.offset_right = -22; player.offset_top = 24; player.offset_bottom = -38
	player.playback_changed.connect(_refresh_playback)
	action_caption = _label("",12); action_caption.add_theme_color_override("font_color",CatalogueSkin.MUTED)
	visual.add_child(action_caption)
	var action_row := HBoxContainer.new(); action_row.add_theme_constant_override("separation",6); visual.add_child(action_row)
	previous_action_button = _button("",func(): step_action(-1)); previous_action_button.tooltip_text = "上一个动作"
	CatalogueSkin.glyph(previous_action_button,"left"); previous_action_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	previous_action_button.custom_minimum_size.x = 40; action_row.add_child(previous_action_button)
	action_picker = OptionButton.new(); action_picker.name = "ActionPicker"
	action_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_picker.custom_minimum_size.y = 42; action_picker.fit_to_longest_item = false
	action_picker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	CatalogueSkin.button(action_picker); action_row.add_child(action_picker)
	next_action_button = _button("",func(): step_action(1)); next_action_button.tooltip_text = "下一个动作"
	CatalogueSkin.glyph(next_action_button,"right"); next_action_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	next_action_button.custom_minimum_size.x = 40; action_row.add_child(next_action_button)
	action_picker.item_selected.connect(func(index): player.select_mode(index); _refresh_playback(); Motion.reveal(player))
	var playback_row := HBoxContainer.new(); playback_row.add_theme_constant_override("separation",8); visual.add_child(playback_row)
	pause_button = _button("暂停",func(): player.toggle_playing()); pause_button.name = "PauseAnimation"; CatalogueSkin.button(pause_button,true); playback_row.add_child(pause_button)
	replay_button = _button("重播",func(): player.playing = true; player.restart(); Motion.reveal(player)); playback_row.add_child(replay_button)
	CatalogueSkin.glyph(replay_button,"replay")
	playback_label = _label("",12); playback_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	playback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; playback_label.add_theme_color_override("font_color",CatalogueSkin.MUTED); playback_row.add_child(playback_label)
	progress_bar = ProgressBar.new(); progress_bar.show_percentage = false; progress_bar.custom_minimum_size.y = 6
	visual.add_child(progress_bar)
	short_heading = _label("",20); information.add_child(short_heading)
	information.add_child(_section("角色概览", "01"))
	summary_label = _label("",16); summary_label.add_theme_constant_override("line_spacing",5); information.add_child(summary_label)
	information.add_child(_rule())
	information.add_child(_section("机能与机制", "02"))
	mechanism_box = VBoxContainer.new(); mechanism_box.add_theme_constant_override("separation",12); information.add_child(mechanism_box)
	stats_grid = GridContainer.new(); stats_grid.columns = 3
	stats_grid.add_theme_constant_override("h_separation",8); stats_grid.add_theme_constant_override("v_separation",8); information.add_child(stats_grid)
	note_label = _label("",12); note_label.add_theme_color_override("font_color",CatalogueSkin.MUTED); information.add_child(note_label)
	character_view.add_child(_rule())
	var nav := HBoxContainer.new(); nav.add_theme_constant_override("separation",8); character_view.add_child(nav)
	nav.add_child(detail_back)
	previous_button = _button("上一个",func(): step_character(-1)); CatalogueSkin.glyph(previous_button,"left"); nav.add_child(previous_button)
	index_label = _label("",12); index_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	index_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; index_label.add_theme_color_override("font_color",CatalogueSkin.MUTED); nav.add_child(index_label)
	next_button = _button("下一个",func(): step_character(1)); CatalogueSkin.glyph(next_button,"right",true); nav.add_child(next_button)
	_rebuild_roster()

func _rule() -> ColorRect:
	var rule := ColorRect.new(); rule.color = CatalogueSkin.LINE; rule.custom_minimum_size.y = 1
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule

func _section(caption: String,number: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var title := _label(caption,14); title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(title)
	var label := _label(number,11); label.add_theme_color_override("font_color",CatalogueSkin.MUTED); row.add_child(label)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	return row

func _build_maps() -> void:
	map_view = VBoxContainer.new(); map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL; body.add_child(map_view)
	var choices := HFlowContainer.new(); choices.add_theme_constant_override("h_separation",8); choices.add_theme_constant_override("v_separation",8); map_view.add_child(choices)
	var group := ButtonGroup.new()
	for entry in [["全身地图","fullbody"],["心脏","heart"],["双肺","lungs"],["小肠","small_intestine"]]:
		var id: String = entry[1]
		var button := _button(entry[0],func(): map_canvas.select_region(id); Motion.reveal(map_canvas,.24))
		button.toggle_mode = true; button.button_group = group; _selected_style(button)
		CatalogueSkin.glyph(button,"map")
		button.set_pressed_no_signal(id == "fullbody")
		choices.add_child(button)
	map_canvas = MapCanvas.new(); map_canvas.name = "RuntimeMapPreview"
	map_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_view.add_child(map_canvas)
	map_view.add_child(_label("观察真实地图 · 全身 / 心脏 / 双肺 / 小肠",13))
	map_view.hide()

func _build_buildings() -> void:
	building_view = VBoxContainer.new(); building_view.size_flags_vertical = Control.SIZE_EXPAND_FILL; building_view.add_theme_constant_override("separation",10); body.add_child(building_view)
	building_view.add_child(_label("建筑预览",18))
	building_view.add_child(_label("查看建筑用途、耐久、建造时间与资源消耗。手机端可上下滑动浏览全部建筑。",13))
	var scroll := ScrollContainer.new(); scroll.name = "BuildingPreviewScroll"; scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; building_view.add_child(scroll)
	var cards := VBoxContainer.new(); cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL; cards.add_theme_constant_override("separation",10); scroll.add_child(cards)
	var art: Dictionary = WarData.read("friendly_buildings").get("buildings",{})
	var keys: Array = WarData.config().Data.buildings.keys(); keys.sort()
	for id in keys:
		var spec: Dictionary = WarData.config().Data.buildings[id]
		var card := PanelContainer.new(); card.add_theme_stylebox_override("panel",CatalogueSkin.panel(CatalogueSkin.WHITE,14,14)); cards.add_child(card)
		var row := HBoxContainer.new(); row.add_theme_constant_override("separation",12); card.add_child(row)
		var preview := TextureRect.new(); preview.custom_minimum_size = Vector2(92,76); preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var source: Dictionary = art.get(id,{})
		if not source.is_empty(): preview.texture = load("res://assets/"+str(source.texture)) as Texture2D
		row.add_child(preview)
		var copy := VBoxContainer.new(); copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL; copy.add_theme_constant_override("separation",4); row.add_child(copy)
		copy.add_child(_label(str(spec.name),17))
		copy.add_child(_label(str(spec.get("desc","暂无说明")),13))
		var cost: Array[String] = []
		for resource in spec.get("cost",{}): cost.append(str(WarData.config().Data.names.get(resource,resource))+" "+str(int(spec.cost[resource])))
		copy.add_child(_label("耐久 %d · 建造 %d 秒 · %s" % [int(spec.get("hp",0)),int(spec.get("time",0))," / ".join(cost) if not cost.is_empty() else "无资源消耗"],12))
	building_view.hide()

func open() -> void:
	show()
	show_characters()
	close_button.grab_focus()
	Motion.reveal(panel,.22)

func close() -> void:
	hide()
	closed.emit()

func show_characters() -> void:
	page = "characters"
	character_view.show(); map_view.hide(); building_view.hide()
	character_tab.set_pressed_no_signal(true); map_tab.set_pressed_no_signal(false); building_tab.set_pressed_no_signal(false)
	_layout()
	_reveal_page(character_view)

func show_maps() -> void:
	page = "maps"
	character_view.hide(); map_view.show(); building_view.hide()
	character_tab.set_pressed_no_signal(false); map_tab.set_pressed_no_signal(true); building_tab.set_pressed_no_signal(false)
	_layout()
	_reveal_page(map_view)

func show_buildings() -> void:
	page = "buildings"
	character_view.hide(); map_view.hide(); building_view.show()
	character_tab.set_pressed_no_signal(false); map_tab.set_pressed_no_signal(false); building_tab.set_pressed_no_signal(true)
	_layout()
	_reveal_page(building_view)

func _reveal_page(view: Control) -> void:
	for tab in [character_tab,map_tab,building_tab]: Motion.attach(tab).call("refresh")
	Motion.reveal(view,.20)

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
		card.custom_minimum_size = Vector2(116,150); card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.tooltip_text = entry.name+" · "+entry.role
		grid.add_child(card)
		var column := VBoxContainer.new(); column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		column.offset_left = 8; column.offset_top = 8; column.offset_right = -8; column.offset_bottom = -8
		card.add_child(column)
		var art := TextureRect.new(); art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.texture = _portrait(entry); art.custom_minimum_size.y = 90
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		column.add_child(art)
		var label := _label(entry.name,13); label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.max_lines_visible = 1; label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; column.add_child(label)
		var tag := _label(str(entry.role).split(" / ")[0],11); tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.add_theme_color_override("font_color",CatalogueSkin.MUTED); tag.max_lines_visible = 1; tag.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; column.add_child(tag)
	for key in category_buttons:
		category_buttons[key].set_pressed_no_signal(key == category)
		Motion.attach(category_buttons[key]).call("refresh")
	count_label.text = "%02d 位角色  /  %s" % [filtered.size(),"全部收藏" if category == "all" else CATEGORY_NAMES[category]]
	previous_button.disabled = filtered.size() <= 1; next_button.disabled = filtered.size() <= 1
	if filtered.is_empty():
		var empty := _label("没有匹配的角色\n试试其他名称，或清空搜索。",16)
		empty.custom_minimum_size.x = 220; grid.add_child(empty)
		mobile_detail = false
		index_label.text = "暂无结果"
	else:
		var found := false
		for entry in filtered:
			if entry.id == selected_id: found = true; break
		select_character(selected_id if found else str(filtered[0].id),false)
	roster.scroll_vertical = 0
	_layout()
	Motion.reveal(grid,.16)

func _portrait(entry: Dictionary) -> Texture2D:
	var path := "res://assets/ui/catalogue/thumbnails/"+str(entry.id)+".png"
	if ResourceLoader.exists(path):
		if not portrait_cache.has(path): portrait_cache[path] = load(path)
		return portrait_cache[path]
	path = entry.portrait
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
	archive_number.text = "NO. %02d" % (entries.find(entry)+1)
	status_label.text = entry.status
	short_heading.text = entry.name+" · "+entry.status
	summary_label.text = entry.summary
	note_label.text = entry.note
	for child in mechanism_box.get_children(): mechanism_box.remove_child(child); child.queue_free()
	for i in entry.mechanics.size():
		var row := HBoxContainer.new(); mechanism_box.add_child(row)
		var number := _label("%02d" % (i+1),13); number.custom_minimum_size.x = 26
		number.add_theme_color_override("font_color",CatalogueSkin.GREEN); row.add_child(number)
		var label := _label(entry.mechanics[i],14); label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(label)
	for child in stats_grid.get_children(): stats_grid.remove_child(child); child.queue_free()
	if not str(entry.kind).is_empty():
		var spec: Dictionary = WarData.spec(entry.kind)
		for pair in [["生命","hp"],["单次伤害","damage"],["移动速度","speed"],["射程","range"],["攻击间隔","cool"],["视野","vision"]]:
			var tile := PanelContainer.new(); tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tile.add_theme_stylebox_override("panel",CatalogueSkin.panel(CatalogueSkin.WHITE,12,12)); stats_grid.add_child(tile)
			var column := VBoxContainer.new(); tile.add_child(column)
			var caption := _label(pair[0],11); caption.add_theme_color_override("font_color",CatalogueSkin.MUTED); column.add_child(caption)
			var raw: Variant = spec.get(pair[1],"—")
			var value := str(raw)
			if raw is float and is_equal_approx(raw,roundf(raw)): value = str(int(raw))
			if entry.kind in ["b_cell","dendritic_cell"] and pair[1] in ["range","cool"]: value = "—"
			column.add_child(_label(value+(" 秒" if pair[1] == "cool" and value != "—" else ""),22))
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
		if card is Button:
			card.set_pressed_no_signal(card.get_meta("entry_id","") == id)
			Motion.attach(card).call("refresh")
	detail_scroll.scroll_vertical = 0
	if from_card: mobile_detail = true
	_layout()
	call_deferred("_reveal_selected")
	if from_card and compact: detail_back.grab_focus()
	Motion.reveal(player,.20); Motion.reveal(information,.20)
	Motion.reveal(detail_name_row,.16)

func _reveal_selected() -> void:
	# Wait for the grid and scrollbar to finish their deferred layout before
	# measuring the selected card (especially on first open and after filters).
	await get_tree().process_frame
	await get_tree().process_frame
	if not roster.is_visible_in_tree(): return
	var card := grid.get_node_or_null("Card_"+selected_id) as Button
	if card: roster.ensure_control_visible(card)

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
	Motion.reveal(sidebar,.18)

func step_action(direction: int) -> void:
	if player.entry.actions.is_empty(): return
	var index := posmod(player.mode+direction,action_picker.item_count)
	action_picker.select(index)
	player.select_mode(index)
	Motion.reveal(player,.20)

func _selected_style(button: Button,subtle := false) -> void:
	CatalogueSkin.selected(button,subtle)

func _refresh_playback() -> void:
	if pause_button == null: return
	var action := player.current_action()
	pause_button.disabled = action.is_empty(); replay_button.disabled = action.is_empty()
	pause_button.text = "暂停" if player.playing else "播放"
	CatalogueSkin.glyph(pause_button,"pause" if player.playing else "play")
	for button in [pause_button,replay_button,previous_action_button,next_action_button]: Motion.attach(button).call("refresh")
	progress_bar.visible = not action.is_empty()
	action_caption.text = "形象立绘" if action.is_empty() else "动作演示 · "+str(action.name)
	action_picker.tooltip_text = "角色立绘" if action.is_empty() else str(action.name)
	if action.is_empty(): playback_label.text = "静态展示"

func _process(_delta: float) -> void:
	if page != "characters" or not detail_scroll.visible: return
	var action := player.current_action()
	if action.is_empty(): return
	playback_label.text = "%s · %02d / %02d" % ["播放中" if player.playing else "已暂停",player.frame_index+1,action.frames.size()]
	action_picker.tooltip_text = action.name
	progress_bar.value = minf(100,100*player.elapsed/float(action.duration))

func _layout() -> void:
	if panel == null: return
	compact = size.x < 760 or size.y < 500
	var short_landscape := size.y < 500 and size.x >= 760
	var margin := 8.0 if compact else 24.0
	panel.custom_minimum_size = Vector2(minf(size.x-margin*2,1280),minf(size.y-margin*2,860))
	var style := panel.get_theme_stylebox("panel")
	style.set_content_margin_all(12 if compact else 24)
	body.add_theme_constant_override("separation",8 if compact else 14)
	archive_subtitle.visible = not compact
	var tabs_parent: Node = archive_header if short_landscape else body
	if archive_tabs.get_parent() != tabs_parent:
		archive_tabs.reparent(tabs_parent)
		tabs_parent.move_child(archive_tabs,1)
	archive_header.get_child(0).custom_minimum_size.x = 110 if short_landscape else 0
	if split == null: return
	sidebar.custom_minimum_size.x = 0 if compact else 266
	sidebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL if compact else Control.SIZE_FILL
	sidebar.visible = not compact or not mobile_detail or filtered.is_empty()
	sidebar_tools.vertical = not short_landscape
	count_label.visible = not short_landscape
	sidebar.add_theme_constant_override("separation",8 if short_landscape else 12)
	roster.visible = true
	detail_scroll.visible = not filtered.is_empty() and (not compact or mobile_detail)
	detail_back.visible = compact and mobile_detail
	grid.columns = 4 if short_landscape else 2
	detail_name_row.visible = not short_landscape; detail_role_row.visible = not short_landscape
	short_heading.visible = short_landscape
	presentation.vertical = size.x < 760 or (size.x < 1120 and not short_landscape)
	stage.custom_minimum_size.y = 210 if short_landscape else (270 if compact else clampf(size.y-550,230,350))
	title_label.add_theme_font_size_override("font_size",26 if compact else 32)
	stats_grid.columns = 2 if compact else 3
	for button in category_buttons.values(): button.add_theme_font_size_override("font_size",14 if compact else 13)
	call_deferred("_fit_panel")

func _fit_panel() -> void:
	if panel == null: return
	panel.size = panel.custom_minimum_size
	panel.position = ((size-panel.size)*.5).floor()

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
	CatalogueSkin.button(button)
	button.pressed.connect(callback)
	return button
