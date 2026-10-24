extends RefCounted
## GPT-painted membrane surfaces, shared by native archive controls.
## Dynamic text, focus, interaction and state tint remain native Godot UI.
const Motion = preload("res://scripts/catalogue_motion.gd")
const ROOT := "res://assets/ui/catalogue/components/"
const PAPER := WarUISkin.CREAM
const WHITE := Color.WHITE
const INK := WarUISkin.INK
const MUTED := WarUISkin.MUTED
const LINE := WarUISkin.LINE
const GREEN := WarUISkin.INK
const PALE := Color("eee0f3")

static func panel(fill := WHITE, radius := 16, margin := 14) -> StyleBoxTexture:
	return WarUISkin.painted_panel(fill,radius,margin,"track" if radius <= 3 else "")

static func focus_ring(_radius := 12) -> StyleBox:
	return WarUISkin.button_box("focus")

static func icon(id: String) -> Texture2D:
	return load(ROOT+"icon-"+id+".png") as Texture2D

static func glyph(button: Button,id: String,right := false) -> void:
	button.icon = icon(id)
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_constant_override("icon_max_width",20)
	button.add_theme_constant_override("h_separation",5)
	# expand_icon excludes the icon from Button's native minimum width. Reserve
	# its space explicitly so text buttons retain their generated glyph at rest.
	var text_width := button.get_theme_font("font").get_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,-1,button.get_theme_font_size("font_size")).x
	button.custom_minimum_size.x = maxf(button.custom_minimum_size.x,text_width+20+(5 if not button.text.is_empty() else 0)+16)

static func button(button: Button, primary := false) -> void:
	WarUISkin.apply_button(button,"primary" if primary else "")
	button.add_theme_font_override("font",WarUISkin.BODY)
	button.add_theme_font_size_override("font_size",14)
	button.add_theme_color_override("icon_disabled_color",Color(1,1,1,.4))
	button.set_meta("catalogue_generated_surface",true)

static func selected(button: Button, _card := false) -> void:
	button.add_theme_stylebox_override("pressed",WarUISkin.button_box("pressed"))
	button.add_theme_stylebox_override("hover_pressed",WarUISkin.button_box("hover_pressed"))

static func field(input: LineEdit) -> void:
	input.add_theme_stylebox_override("normal",panel(WHITE,12,10))
	input.add_theme_stylebox_override("read_only",panel(Color("e7e4db"),12,10))
	input.add_theme_stylebox_override("focus",focus_ring())
	input.add_theme_color_override("font_color",INK)
	input.add_theme_color_override("font_placeholder_color",MUTED)
	input.add_theme_font_size_override("font_size",13)
	input.add_theme_icon_override("clear",icon("close"))
	input.right_icon = icon("search")
	input.set_meta("catalogue_generated_surface",true)
	Motion.attach(input)

static func theme() -> Theme:
	var result := WarUISkin.theme()
	result.set_color("font_color","Label",INK)
	result.set_stylebox("panel","PopupMenu",panel(WHITE,14,8))
	result.set_stylebox("hover","PopupMenu",WarUISkin.painted_panel(PALE,8,4,"compact"))
	result.set_color("font_color","PopupMenu",INK)
	result.set_color("font_hover_color","PopupMenu",INK)
	result.set_font("font","PopupMenu",WarUISkin.BODY)
	result.set_font_size("font_size","PopupMenu",14)
	result.set_icon("checked","PopupMenu",icon("check"))
	result.set_icon("radio_checked","PopupMenu",icon("check"))
	result.set_icon("arrow","OptionButton",icon("down"))
	return result
