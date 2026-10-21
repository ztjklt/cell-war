class_name WarCover
extends Control
## Static character artwork, frontal sculpted names and floating menu projections.
signal action_requested(action: String)
const ART := "res://assets/image/cover-standoff-20261020/artwork-static-v2.png"
const PAPER := Color("f5eddf")
const FONT = preload("res://assets/fonts/MiSans-Regular.ttf")
var stage: Control
var background: TextureRect
var buttons: Array[WarCoverButton] = []
var titles: Array[WarCoverTitle] = []
var footer: Label
var art_scale := 1.0
var compact := false
var button_area: Control
var overlay: Control

class CoverOverlay extends Control:
	var cover: WarCover
	func _draw() -> void:
		cover.paint_overlay(self)

func _ready() -> void:
	name = "ConstructivistCover"
	clip_contents = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var paper := ColorRect.new()
	paper.color = PAPER; paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(paper)
	stage = Control.new(); stage.name = "StaticArtwork"; stage.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(stage)
	background = TextureRect.new(); background.name = "ApprovedStandoffArtwork"
	background.texture = load(ART)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(background)
	for name_text in ["细胞战争","CELL WAR"]:
		var title := WarCoverTitle.new()
		title.text = name_text; title.english = name_text == "CELL WAR"
		title.name = "EnglishTitle" if title.english else "ChineseTitle"
		stage.add_child(title); titles.append(title)
	overlay = CoverOverlay.new(); overlay.cover = self; overlay.name = "GraphicForeground"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(overlay)
	button_area = Control.new(); button_area.name = "MenuActions"; button_area.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(button_area)
	var specs := [["开始作战","START GAME","start"],["角色预览","CHARACTERS","preview"],["教学模式","TUTORIAL","tutorial"],["设置","SETTINGS","settings"]]
	for i in specs.size():
		var b := WarCoverButton.new(); b.name = str(specs[i][2]).to_pascal_case()
		b.caption = specs[i][0]; b.english = specs[i][1]; b.icon_index = i; b.primary = i == 0
		var action: String = specs[i][2]
		b.activated.connect(func(): action_requested.emit(action))
		button_area.add_child(b); buttons.append(b)
	footer = Label.new(); footer.text = "微 观 生 命  /  宏 观 战 场"
	footer.add_theme_font_override("font",FONT); footer.add_theme_font_size_override("font_size",10)
	footer.add_theme_color_override("font_color",Color(.08,.13,.16,.58)); footer.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(footer)
	resized.connect(_layout)
	_layout()
	set_process(false)

func _layout() -> void:
	if stage == null: return
	compact = size.x < 720
	for b in buttons:
		b.compact = compact; b.scale = Vector2.ONE
		b.custom_minimum_size = Vector2(120,122) if compact else Vector2(120,140)
	art_scale = minf(size.x/1600.0,size.y/900.0) if not compact else size.x/1600.0
	stage.scale = Vector2.ONE*art_scale
	stage.position = (size-Vector2(1600,900)*art_scale)*.5 if not compact else Vector2(0,120+maxf(0,size.y-500)*.28)
	background.size = Vector2(1600,900); background.position = Vector2.ZERO
	if not compact:
		if button_area.get_parent() != stage: button_area.reparent(stage,false)
		button_area.position = Vector2.ZERO; button_area.size = Vector2(1600,900)
		for i in buttons.size():
			buttons[i].floor_skew = 1-float(i)*2/3
			buttons[i].place_on_ground(Vector2(480+i*210,840),Vector2(800,600),785,190)
		for i in titles.size():
			if titles[i].get_parent() != stage: titles[i].reparent(stage,false)
			titles[i].position = Vector2(32 if i == 0 else 978,48)
			titles[i].size = Vector2(590,200)
	else:
		if button_area.get_parent() != self: button_area.reparent(self,false)
		button_area.position = Vector2(14,size.y-292); button_area.size = Vector2(size.x-28,252)
		for i in buttons.size():
			buttons[i].floor_skew = .7 if i%2 == 0 else -.7
			buttons[i].position = Vector2((i%2)*(size.x-28)*.5,floori(i/2.0)*126)
			buttons[i].size = Vector2((size.x-28)*.5,122)
		for i in titles.size():
			if titles[i].get_parent() != self: titles[i].reparent(self,false)
			titles[i].position = Vector2(0 if i == 0 else size.x*.52,18)
			titles[i].size = Vector2(size.x*.52 if i == 0 else size.x*.48,100)
	for i in buttons.size():
		buttons[i].focus_neighbor_left = buttons[(i+3)%4].get_path()
		buttons[i].focus_neighbor_right = buttons[(i+1)%4].get_path()
		buttons[i].queue_redraw()
	footer.position = Vector2(24,size.y-28)
	overlay.queue_redraw()

func paint_overlay(canvas: Control) -> void:
	if compact:
		canvas.draw_rect(Rect2(0,0,size.x,120),PAPER)
		canvas.draw_rect(Rect2(0,size.y-310,size.x,310),PAPER)
