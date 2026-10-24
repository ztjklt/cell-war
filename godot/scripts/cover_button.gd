class_name WarCoverButton
extends Button
## GPT membrane card with floating native glyphs and delayed single activation.
signal activated
var icon_index := 0
var caption := ""
var english := ""
var primary := false
var motion := true
var compact := false
var hover_weight := 0.0
var phase := 0.0
var pulse_elapsed := 1.0
var activation_pending := false
const FEEDBACK_TIME := .22
const INK := WarUISkin.INK
const RED := Color("ed3538")
const PAPER := Color("fff3de")
const FONT = preload("res://assets/fonts/MiSans-Regular.ttf")

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL
	text = caption; tooltip_text = caption
	WarUISkin.apply_button(self,"primary" if primary else "",false)
	for state in WarUISkin.STATES: add_theme_stylebox_override(state,WarUISkin.button_box(state,"primary" if primary else "",14,"badge"))
	for state in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color"]:
		add_theme_color_override(state,Color.TRANSPARENT)
	pressed.connect(_activate)
	resized.connect(queue_redraw)
	visibility_changed.connect(_visibility_changed)
	phase = icon_index*.72
	_visibility_changed()

func _visibility_changed() -> void:
	set_process(is_visible_in_tree())
	if not is_visible_in_tree():
		activation_pending = false
		pulse_elapsed = 1.0

func _activate() -> void:
	if activation_pending: return
	activation_pending = true
	pulse_elapsed = 0.0
	queue_redraw()

func _process(delta: float) -> void:
	if motion: phase += delta*1.7
	hover_weight = move_toward(hover_weight,1.0 if is_hovered() or has_focus() else 0.0,delta*6)
	pulse_elapsed += delta
	queue_redraw()
	if activation_pending and pulse_elapsed >= FEEDBACK_TIME:
		activation_pending = false
		activated.emit()

func hologram_center() -> Vector2:
	return Vector2(size.x*.5,size.y*.30)

func _has_point(point: Vector2) -> bool:
	return Rect2(Vector2(3,3),size-Vector2(6,6)).has_point(point)

func _draw() -> void:
	var pulse := maxf(0.0,1-pulse_elapsed/.42)
	var center := hologram_center()
	center.y += sin(phase)*2.2-hover_weight*2+sin(minf(pulse_elapsed/.22,1.0)*PI)*2
	var ink := Color("a04e6b") if primary else INK
	var icon_scale := .70 if compact else .83
	draw_set_transform(center,0,Vector2.ONE*icon_scale)
	_draw_icon(Vector2.ZERO,ink)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	var width := size.x-20
	var baseline := Vector2(10,size.y*.70)
	draw_string(FONT,baseline,caption,HORIZONTAL_ALIGNMENT_CENTER,width,18 if compact else 22,ink)
	draw_string(FONT,baseline+Vector2(0,17),english,HORIZONTAL_ALIGNMENT_CENTER,width,10,WarUISkin.MUTED)
	if pulse > .05:
		draw_arc(center,22+(1-pulse)*15,0,TAU,48,Color(WarUISkin.CORAL,pulse*.8),1.6,true)

func _draw_icon(c: Vector2,color: Color) -> void:
	match icon_index:
		0:
			draw_colored_polygon(_soft_polygon(PackedVector2Array([c+Vector2(-13,-23),c+Vector2(23,0),c+Vector2(-13,23)]),5),color)
		1:
			# A red cell: a smooth disc with a recessed centre, drawn as two contours.
			var red := Color(Color("d53542"),color.a)
			var rim := PackedVector2Array()
			var hollow := PackedVector2Array()
			var lower_edge := PackedVector2Array()
			for i in 65:
				var angle := i*TAU/64
				rim.append(c+Vector2(cos(angle)*24,sin(angle)*17).rotated(-.22))
				hollow.append(c+Vector2(cos(angle)*11,sin(angle)*6.5-1).rotated(-.22))
			for i in 33:
				var angle := i*PI/32
				lower_edge.append(c+Vector2(cos(angle)*24,sin(angle)*17+3).rotated(-.22))
			draw_colored_polygon(rim,Color(red,.06))
			draw_polyline(lower_edge,red,3.2,true)
			draw_polyline(rim,red,3.6,true)
			draw_polyline(hollow,red,3.0,true)
		2:
			draw_colored_polygon(_soft_polygon(PackedVector2Array([c+Vector2(-28,-7),c+Vector2(0,-21),c+Vector2(28,-7),c+Vector2(0,7)]),4),color)
			var rim := _soft_path(PackedVector2Array([c+Vector2(-17,3),c+Vector2(-17,14),c+Vector2(0,21),c+Vector2(17,14),c+Vector2(17,3)]),4)
			draw_polyline(rim,color,3.8,true)
			_soft_line(c+Vector2(26,-3),c+Vector2(26,15),color,3.5)
		3:
			draw_arc(c,15,0,TAU,64,color,7,true)
			for i in 8:
				var v := Vector2.from_angle(i*TAU/8)
				_soft_line(c+v*17,c+v*23,color,7)

func _soft_line(a: Vector2,b: Vector2,color: Color,width: float) -> void:
	draw_line(a,b,color,width,true)
	draw_circle(a,width*.5,color,true,-1,true); draw_circle(b,width*.5,color,true,-1,true)

func _soft_polygon(points: PackedVector2Array,radius: float) -> PackedVector2Array:
	var closed := points.duplicate()
	closed.append(points[0]); closed.append(points[1])
	var result := _soft_path(closed,radius)
	# Discard the open end caps; the sampled first corner closes the perimeter.
	result.remove_at(result.size()-1); result.remove_at(0)
	return result

func _soft_path(points: PackedVector2Array,radius: float) -> PackedVector2Array:
	var result := PackedVector2Array([points[0]])
	for i in range(1,points.size()-1):
		var corner := points[i]
		var a := corner.move_toward(points[i-1],minf(radius,corner.distance_to(points[i-1])*.4))
		var b := corner.move_toward(points[i+1],minf(radius,corner.distance_to(points[i+1])*.4))
		for step in 7:
			var t := step/6.0
			result.append(a.lerp(corner,t).lerp(corner.lerp(b,t),t))
	result.append(points[-1])
	return result
