class_name WarCoverButton
extends Button
## Perspective pedestal with an upright hologram. Native input includes both.
signal activated
var icon_index := 0
var caption := ""
var english := ""
var primary := false
var motion := true
var compact := false
var floor_skew := 0.0
var projected_top := PackedVector2Array()
var hover_weight := 0.0
var phase := 0.0
var pulse_elapsed := 1.0
var activation_pending := false
const FEEDBACK_TIME := .22
const INK := Color("14202a")
const RED := Color("ed3538")
const PAPER := Color("fff3de")
const FONT = preload("res://assets/fonts/MiSans-Regular.ttf")

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL
	text = caption; tooltip_text = caption
	for state in ["normal","hover","pressed","focus"]:
		add_theme_stylebox_override(state,StyleBoxEmpty.new())
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
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

func top_polygon() -> PackedVector2Array:
	if not compact and not projected_top.is_empty(): return projected_top
	var w := size.x
	var back_width := w*.70
	var front_width := w*.88
	var shift := floor_skew*w*.09
	return PackedVector2Array([
		Vector2((w-back_width)*.5+shift,86),
		Vector2((w+back_width)*.5+shift,86),
		Vector2((w+front_width)*.5,110),
		Vector2((w-front_width)*.5,110)])

func place_on_ground(front_center: Vector2,vanishing_point: Vector2,back_y: float,width: float) -> void:
	var ratio := (back_y-vanishing_point.y)/(front_center.y-vanishing_point.y)
	var back_center := vanishing_point+(front_center-vanishing_point)*ratio
	var quad := PackedVector2Array([
		back_center+Vector2(-width*.5*ratio,0),back_center+Vector2(width*.5*ratio,0),
		front_center+Vector2(width*.5,0),front_center+Vector2(-width*.5,0)])
	var box := Rect2(quad[0],Vector2.ZERO)
	for point in quad: box = box.expand(point)
	position = box.position-Vector2(0,140)
	size = Vector2(box.size.x,box.size.y+174)
	projected_top = PackedVector2Array()
	for point in quad: projected_top.append(point-position)

func hologram_center() -> Vector2:
	var center := pedestal_center()
	return center-Vector2(0,78 if compact else 100)

func pedestal_center(top := PackedVector2Array()) -> Vector2:
	if top.is_empty(): top = top_polygon()
	var surface := rounded_surface(top)
	var area_twice := 0.0
	var center := Vector2.ZERO
	for i in surface.size():
		var a := surface[i]
		var b := surface[(i+1)%surface.size()]
		var cross_product := a.cross(b)
		area_twice += cross_product
		center += (a+b)*cross_product
	return center/(3*area_twice)

func rounded_surface(top: PackedVector2Array,inset := 0.0) -> PackedVector2Array:
	var result := PackedVector2Array()
	var radius := Vector2(.085,.22)
	var corners := [Vector2(radius.x,radius.y),Vector2(1-radius.x,radius.y),Vector2(1-radius.x,1-radius.y),Vector2(radius.x,1-radius.y)]
	for corner in 4:
		for step in 7:
			var angle := PI+corner*PI*.5+step*PI/12
			var uv: Vector2 = corners[corner]+Vector2(cos(angle),sin(angle))*radius
			uv = Vector2.ONE*inset+uv*(1-2*inset)
			result.append(project(uv,top))
	return result

func _has_point(point: Vector2) -> bool:
	var volume := rounded_surface(top_polygon())
	var lower := volume.duplicate()
	for i in lower.size(): lower[i].y += 6 if compact else 12
	volume.append_array(lower)
	volume = Geometry2D.convex_hull(volume)
	var center := hologram_center()
	var projection := Rect2(center-Vector2(61,29 if compact else 34),Vector2(122,78 if compact else 99))
	return Geometry2D.is_point_in_polygon(point,volume) or projection.has_point(point)

func project(point: Vector2,top: PackedVector2Array) -> Vector2:
	return top[0].lerp(top[1],point.x).lerp(top[3].lerp(top[2],point.x),point.y)

func _draw() -> void:
	var top := top_polygon()
	var down := Vector2(0,2 if is_pressed() else 0)
	for i in top.size(): top[i] += down
	var thickness := 6.0 if compact else 12.0
	var fill := Color("ef4445") if primary else Color("f6ecda")
	fill = fill.lightened(hover_weight*.07)
	var pulse := maxf(0.0,1-pulse_elapsed/.42)
	var red_accent := primary or icon_index == 3
	var glow := Color("ff645a") if red_accent else Color("348ba1")
	var surface := rounded_surface(top)
	var shadow := surface.duplicate()
	for i in shadow.size(): shadow[i] += Vector2(5,thickness+7)
	draw_colored_polygon(shadow,Color(.23,.13,.08,.10))
	var lower := surface.duplicate()
	for i in lower.size(): lower[i].y += thickness
	var front := Color("cb333c") if primary else Color("d0bfa6")
	draw_colored_polygon(lower,front)
	for i in surface.size():
		var next := (i+1)%surface.size()
		draw_colored_polygon(PackedVector2Array([surface[i],surface[next],lower[next],lower[i]]),front)
	draw_colored_polygon(surface,fill.lightened(.16))
	var inner := rounded_surface(top,.025)
	draw_colored_polygon(inner,fill)
	var outline := surface.duplicate(); outline.append(surface[0])
	draw_polyline(outline,Color("bb3239") if primary else Color("cbb99e"),1,true)
	# A luminous oval is projected onto the floor; all content above it faces us.
	var socket := pedestal_center(top)
	for i in range(4,0,-1):
		_draw_floor_ring(socket,Vector2(42+i*3,11+i),Color(glow,.025*(5-i)))
	_draw_floor_ring(socket,Vector2(41,11),Color(PAPER if primary else glow,.52+hover_weight*.23))
	_draw_floor_ring(socket,Vector2(32,8),Color(PAPER if primary else glow,.28))
	if pulse > 0:
		_draw_floor_ring(socket,Vector2(40+38*(1-pulse),11+10*(1-pulse)),Color(PAPER if primary else glow,pulse*.8),2)
	var center := hologram_center()
	center.y += sin(phase)*(2.0 if compact else 3.8)-hover_weight*3
	center.y += sin(minf(pulse_elapsed/.22,1.0)*PI)*3 if pulse > 0 else 0
	var bottom := center+Vector2(0,48 if compact else 61)
	# Restrained, transparent projector rays rather than an opaque panel.
	draw_polygon(PackedVector2Array([socket+Vector2(-27,0),socket+Vector2(27,0),bottom+Vector2(53,0),bottom+Vector2(-53,0)]),PackedColorArray([Color(glow,.12),Color(glow,.12),Color(glow,0),Color(glow,0)]))
	var ink := Color("c52b37") if red_accent else Color("193f51")
	ink = ink.lightened(pulse*.19)
	var hologram_scale := .82 if compact else 1.04
	# A single crisp silhouette; transparent light stays behind the icon.
	draw_set_transform(center,0,Vector2.ONE*hologram_scale)
	_draw_icon(Vector2.ZERO,Color(ink,.98))
	draw_set_transform_matrix(Transform2D.IDENTITY)
	var width := 156.0 if not compact else minf(size.x,154)
	var baseline := center+Vector2(-width*.5,36 if compact else 44)
	var font_size := 19 if compact else 24
	draw_string_outline(FONT,baseline,caption,HORIZONTAL_ALIGNMENT_CENTER,width,font_size,3,Color(PAPER,.60))
	draw_string(FONT,baseline,caption,HORIZONTAL_ALIGNMENT_CENTER,width,font_size,Color(ink,.94))
	draw_string(FONT,baseline+Vector2(0,16),english,HORIZONTAL_ALIGNMENT_CENTER,width,10,Color(ink,.85))
	# Small light dashes and an expanding click flash give readable state feedback.
	var line_y := center.y+(56 if compact else 65)
	draw_line(Vector2(center.x-12,line_y),Vector2(center.x+12,line_y),Color(glow,.55+hover_weight*.3),1.5,true)
	if pulse > .05:
		draw_arc(center,29+(1-pulse)*24,0,TAU,56,Color(glow,pulse*.7),1.8,true)
	if has_focus():
		var focus_line := inner.duplicate(); focus_line.append(inner[0])
		draw_polyline(focus_line,Color(PAPER if primary else glow,.8),1.7,true)
	var accent_a := top[3].lerp(top[2],.37)+Vector2(0,thickness*.55)
	var accent_b := top[3].lerp(top[2],.63)+Vector2(0,thickness*.55)
	draw_line(accent_a,accent_b,PAPER if primary else Color(glow,.7),2,true)

func _draw_floor_ring(center: Vector2,radius: Vector2,color: Color,line_width := 1.0) -> void:
	if compact: radius.y *= .6
	var ring := PackedVector2Array()
	for i in 49: ring.append(center+Vector2(cos(i*TAU/48)*radius.x,sin(i*TAU/48)*radius.y))
	draw_polyline(ring,color,line_width,true)

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
