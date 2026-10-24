class_name WarUISkin
extends RefCounted
## GPT-painted membranes with native text, state, layout and input.
const ROOT := "res://assets/ui/membrane/"
const CREAM := Color("fff8eb")
const OAT := Color("f5e2dd")
const INK := Color("57334f")
const MUTED := Color("876576")
const LINE := Color("cba8be")
const SAGE := Color("afd0bd")
const CORAL := Color("f1b2b6")
const HONEY := Color("edc778")
const LILAC := Color("d4c4e7")
const DISPLAY = preload("res://assets/fonts/ZCOOLKuaiLe-Regular.ttf")
const BUTTON = preload("res://assets/fonts/ZCOOLQingKeHuangYou-Regular.ttf")
const BODY = preload("res://assets/fonts/MiSans-Regular.ttf")
const Motion = preload("res://scripts/catalogue_motion.gd")
const STATES := ["normal","hover","pressed","hover_pressed","disabled","focus"]

# Native flat fills remain useful for meters and layout-only padding.
static func panel(color := CREAM,radius := 18,margin := 12) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.set_border_width_all(1)
	box.border_color = LINE
	box.set_content_margin_all(margin)
	return box

static func painted_panel(fill := Color.WHITE,radius := 18,margin := 12,asset := "") -> StyleBoxTexture:
	var id := asset if not asset.is_empty() else ("panel" if radius >= 18 else "surface")
	var box := StyleBoxTexture.new()
	box.texture = load(ROOT+id+".png") as Texture2D
	var border: int = {"panel":38,"surface":18,"badge":20,"compact":10,"micro":5,"button":24,"track":4}.get(id,0)
	box.set_texture_margin_all(border)
	if id == "button":
		box.texture_margin_top = 12; box.texture_margin_bottom = 12
	box.set_content_margin_all(margin)
	box.modulate_color = fill
	return box

static func button_box(state: String,accent := "",_radius := 14,asset := "button") -> StyleBox:
	if state == "focus":
		var ring := panel(Color.TRANSPARENT,14,8)
		ring.border_color = INK; ring.set_border_width_all(2)
		return ring
	var tint := Color.WHITE
	if accent == "primary": tint = Color("ffe0df")
	elif accent == "sage": tint = Color("e2f3e7")
	if state == "hover": tint = Color("fff1fa") if accent.is_empty() else tint.lightened(.10)
	if state in ["pressed","hover_pressed"]: tint = Color("decbea") if accent.is_empty() else tint.darkened(.09)
	if state == "disabled": tint = Color("d9d0d8")
	var box := painted_panel(tint,14,8,asset)
	return box

static func prepare_popup(popup: PopupMenu) -> void:
	# Native macOS subwindows need both flags; otherwise alpha corners turn black.
	popup.transparent = true
	popup.transparent_bg = true

static func apply_button(node: Button,accent := "",decorate := true) -> void:
	if node is OptionButton: prepare_popup(node.get_popup())
	var asset := "compact" if node.text.length() <= 2 else "button"
	for state in STATES: node.add_theme_stylebox_override(state,button_box(state,accent,14,asset))
	for state in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color"]:
		node.add_theme_color_override(state,INK)
	node.add_theme_color_override("font_disabled_color",Color("93818e"))
	node.add_theme_font_override("font",BUTTON)
	node.add_theme_font_size_override("font_size",19)
	node.set_meta("membrane_surface",true)
	if decorate: Motion.attach(node)

static func facet_panel(node: PanelContainer,color := Color.WHITE,_cut := 16.0) -> void:
	if node is WarHUDPlate: return
	var old := node.get_theme_stylebox("panel")
	if old is StyleBoxTexture: return
	var box := painted_panel(color,18,12)
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]: box.set_content_margin(side,maxf(18,old.get_content_margin(side)))
	node.add_theme_stylebox_override("panel",box)
	var face := node.get_node_or_null("_FacetSurface")
	if face != null: node.remove_child(face); face.queue_free()

static func skin_tree(node: Node) -> void:
	if node is Button: Motion.attach(node)
	if node is PanelContainer: facet_panel(node)
	for child in node.get_children(): skin_tree(child)

static func theme() -> Theme:
	var display_font: Font = DISPLAY
	var button_font: Font = BUTTON
	display_font.fallbacks = [BODY]; button_font.fallbacks = [BODY]
	var result := Theme.new()
	result.default_font = BODY; result.default_font_size = 16
	for type in ["Button","OptionButton","CheckBox","CheckButton"]:
		result.set_font("font",type,BUTTON); result.set_font_size("font_size",type,19)
		for state in STATES: result.set_stylebox(state,type,button_box(state))
		for state in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color"]: result.set_color(state,type,INK)
		result.set_color("font_disabled_color",type,Color("93818e"))
	for type in ["CheckBox","CheckButton"]:
		result.set_icon("checked",type,load("res://assets/ui/catalogue/components/icon-check.png"))
		result.set_icon("unchecked",type,load(ROOT+"knob.png"))
		result.set_icon("checked_disabled",type,load("res://assets/ui/catalogue/components/icon-check.png"))
		result.set_icon("unchecked_disabled",type,load(ROOT+"knob.png"))
	result.set_color("font_color","Label",INK)
	for type in ["PanelContainer","Panel","PopupMenu","TooltipPanel"]: result.set_stylebox("panel",type,painted_panel(Color.WHITE,18,12))
	result.set_color("font_color","TooltipLabel",INK)
	result.set_color("font_color","PopupMenu",INK); result.set_color("font_hover_color","PopupMenu",INK)
	result.set_stylebox("hover","PopupMenu",painted_panel(Color("eee0f3"),12,4,"compact"))
	for state in ["normal","read_only"]: result.set_stylebox(state,"LineEdit",painted_panel(Color.WHITE if state == "normal" else Color("e0d6df"),12,10))
	result.set_stylebox("focus","LineEdit",button_box("focus"))
	result.set_color("font_color","LineEdit",INK); result.set_color("font_placeholder_color","LineEdit",MUTED)
	result.set_color("caret_color","LineEdit",INK); result.set_color("selection_color","LineEdit",LILAC)
	for type in ["HScrollBar","VScrollBar"]:
		for state in ["scroll","scroll_focus","grabber","grabber_highlight","grabber_pressed"]:
			var tint := Color("e7d9e3") if state.begins_with("scroll") else LILAC
			if state == "grabber_pressed": tint = CORAL
			var bar := painted_panel(tint,3,0,"track")
			bar.content_margin_left = 4; bar.content_margin_right = 4
			bar.content_margin_top = 4; bar.content_margin_bottom = 4
			result.set_stylebox(state,type,bar)
	for type in ["HSlider","VSlider"]:
		for state in ["slider","grabber_area","grabber_area_highlight"]: result.set_stylebox(state,type,painted_panel(Color.WHITE if state == "slider" else LILAC,3,3,"track"))
		for state in ["grabber","grabber_highlight","grabber_disabled"]: result.set_icon(state,type,load(ROOT+"knob.png"))
	for key in ["background","fill"]: result.set_stylebox(key,"ProgressBar",painted_panel(OAT if key == "background" else SAGE,3,0,"track"))
	return result
