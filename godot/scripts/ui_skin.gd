class_name WarUISkin
extends RefCounted
## Cream/cocoa palette with shallow polygonal faces, shared by live components.
const CREAM := Color("fff8eb")
const OAT := Color("f4dfc7")
const INK := Color("624735")
const MUTED := Color("8a6c58")
const LINE := Color("d8bfa4")
const SAGE := Color("86ae94")
const CORAL := Color("ef9b81")
const HONEY := Color("edc778")
const LILAC := Color("c1b7d5")
const DISPLAY = preload("res://assets/fonts/ZCOOLKuaiLe-Regular.ttf")
const BUTTON = preload("res://assets/fonts/ZCOOLQingKeHuangYou-Regular.ttf")
const BODY = preload("res://assets/fonts/MiSans-Regular.ttf")

static func panel(color := CREAM,radius := 18,margin := 12) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.set_border_width_all(1)
	box.border_color = LINE
	box.set_content_margin_all(margin)
	return box

static func button_box(state: String,accent := "",radius := 14) -> StyleBoxFlat:
	var fill := OAT if accent.is_empty() else (CORAL if accent == "primary" else SAGE)
	if state == "hover": fill = fill.lightened(.12)
	if state == "pressed": fill = fill.darkened(.07)
	if state == "disabled": fill = Color("e5dcd0")
	var box := panel(fill,radius,8)
	box.border_color = Color(LINE,.55) if accent.is_empty() else Color(fill,0)
	if state == "focus":
		box.bg_color = Color.TRANSPARENT
		box.border_color = INK
		box.set_border_width_all(2)
	return box

static func apply_button(node: Button,accent := "",decorate := true) -> void:
	for state in ["normal","hover","pressed","disabled","focus"]:
		node.add_theme_stylebox_override(state,button_box(state,accent))
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		node.add_theme_color_override(state,INK)
	node.add_theme_color_override("font_disabled_color",Color("a49383"))
	node.add_theme_font_override("font",BUTTON)
	node.add_theme_font_size_override("font_size",19)
	if decorate: WarFacetSurface.attach(node,CORAL if accent == "primary" else (SAGE if accent == "sage" else OAT),4,9)

static func facet_panel(node: PanelContainer,color := CREAM,cut := 16.0) -> void:
	var skin := node.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	if skin == null: skin = panel(color)
	skin.bg_color = Color.TRANSPARENT
	skin.set_border_width_all(0); skin.shadow_size = 0
	node.add_theme_stylebox_override("panel",skin)
	WarFacetSurface.attach(node,color,6,cut)

static func theme() -> Theme:
	var display_font: Font = DISPLAY
	var button_font: Font = BUTTON
	display_font.fallbacks = [BODY]
	button_font.fallbacks = [BODY]
	var result := Theme.new()
	result.default_font = BODY
	result.default_font_size = 16
	result.set_font("font","Button",BUTTON)
	result.set_font_size("font_size","Button",19)
	for state in ["normal","hover","pressed","disabled","focus"]:
		result.set_stylebox(state,"Button",button_box(state))
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		result.set_color(state,"Button",INK)
	result.set_color("font_disabled_color","Button",Color("a49383"))
	result.set_color("font_color","Label",INK)
	result.set_stylebox("panel","PanelContainer",panel())
	result.set_stylebox("panel","TooltipPanel",panel(CREAM,10,9))
	result.set_color("font_color","TooltipLabel",INK)
	for key in ["background","fill"]:
		var rail := panel(OAT if key == "background" else SAGE,4,0)
		rail.set_border_width_all(0)
		result.set_stylebox(key,"ProgressBar",rail)
	return result
