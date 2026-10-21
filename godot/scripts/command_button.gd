class_name WarCommandButton
extends Button
## Polygonal command badge: real input, shallow faces and animated hover/press.
var action := ""
var glyph: WarCommandIcon
var caption: Label
var fill := WarUISkin.OAT
var hover_amount := 0.0
var press_amount := 0.0
var press_velocity := 0.0
var entrance: Tween

func configure(title: String,kind: String,accent := "") -> void:
	action = kind
	name = "Command_"+kind.replace(":","_")
	custom_minimum_size = Vector2(88,78)
	size = custom_minimum_size
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	fill = WarUISkin.CORAL if accent == "primary" else (WarUISkin.SAGE if accent == "sage" else WarUISkin.OAT)
	WarUISkin.apply_button(self,accent,false)
	for state in ["normal","hover","pressed","disabled","focus"]: add_theme_stylebox_override(state,StyleBoxEmpty.new())
	glyph = WarCommandIcon.new()
	glyph.kind = kind
	add_child(glyph)
	caption = Label.new()
	caption.text = title
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_override("font",WarUISkin.BUTTON)
	caption.add_theme_color_override("font_color",WarUISkin.INK)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(caption)
	resized.connect(_layout)
	button_down.connect(func():
		press_amount = .35; press_velocity = 4.0
		_layout())
	_layout()

func _layout() -> void:
	if glyph == null: return
	pivot_offset = size*.5
	var offset := press_amount*2.5-hover_amount*2
	glyph.position = Vector2((size.x-34)*.5,6+offset)
	glyph.size = Vector2(34,34)
	glyph.pivot_offset = glyph.size*.5
	glyph.scale = Vector2.ONE*(1+hover_amount*.07-press_amount*.03)
	glyph.rotation = deg_to_rad(hover_amount*(-4 if action in ["attack","attackmove"] else 3))
	caption.position = Vector2(5,43+offset)
	caption.size = Vector2(size.x-10,23)
	caption.add_theme_font_size_override("font_size",mini(18,maxi(11,floori((size.x-17)/maxi(2,caption.text.length())))))
	queue_redraw()

func reveal(from: Vector2,to: Vector2,delay: float) -> void:
	if entrance: entrance.kill()
	position = from; scale = Vector2.ONE*.72; modulate.a = 0
	entrance = create_tween().set_parallel(true)
	entrance.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	entrance.tween_property(self,"position",to,.22).set_delay(delay)
	entrance.tween_property(self,"scale",Vector2.ONE,.22).set_delay(delay)
	entrance.tween_property(self,"modulate:a",1.0,.16).set_delay(delay)

func settle(to: Vector2) -> void:
	if entrance: entrance.kill()
	position = to; scale = Vector2.ONE; modulate.a = 1

func _has_point(point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(point,WarFacetSurface.outline(Rect2(Vector2.ZERO,size),14,true))

func _process(delta: float) -> void:
	var next_hover := move_toward(hover_amount,1.0 if (is_hovered() or has_focus()) and not disabled else 0.0,delta*8)
	var previous_press := press_amount
	var target := 1.0 if is_pressed() and not disabled else 0.0
	var step := minf(delta,.05)/4
	for i in 4:
		press_velocity += ((target-press_amount)*460-press_velocity*28)*step
		press_amount += press_velocity*step
	if absf(press_amount-target) < .001 and absf(press_velocity) < .01:
		press_amount = target; press_velocity = 0
	var ink := Color("a49383") if disabled else WarUISkin.INK
	if next_hover != hover_amount or previous_press != press_amount or glyph.color != ink:
		hover_amount = next_hover
		glyph.color = ink; glyph.emphasis = hover_amount
		glyph.modulate.a = .5 if disabled else 1.0
		glyph.queue_redraw(); caption.add_theme_color_override("font_color",ink)
		_layout()

func _draw() -> void:
	var color := Color("e3dbd0") if disabled else fill
	WarFacetSurface.paint(self,Rect2(Vector2.ZERO,size),color,5,14,true,hover_amount,press_amount)
