class_name WarInspectionMarker
extends Control
## Screen-sized survey ink attached to a live world coordinate, never a button.
var world: WarWorldView
var point := Vector2.ZERO
var has_point := false
var pulse := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true

func mark(value: Vector2) -> void:
	point = value
	has_point = true
	pulse = 0
	queue_redraw()

func clear() -> void:
	has_point = false
	queue_redraw()

func _process(delta: float) -> void:
	pulse += delta
	if world != null:
		var frame := world.get_parent() as WarDeskMapFrame
		var aperture := frame.screen_rect()
		position = aperture.position
		size = aperture.size
	queue_redraw()

func _draw() -> void:
	if not has_point or world == null: return
	var projected := get_viewport().get_canvas_transform()*world.display_point(point)-global_position
	if not Rect2(Vector2.ZERO,size).has_point(projected): return
	var ink := Color("245e59")
	var paper := Color("fff8eb")
	var radius := 17.0+5*exp(-pulse*7)
	# Cream under-strokes stay legible on both pale paper and dark micro terrain.
	for side in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
		var p: Vector2 = projected+side*radius
		var path := PackedVector2Array([p-Vector2(side.x*7,0),p,p-Vector2(0,side.y*7)])
		draw_polyline(path,paper,4,true)
		draw_polyline(path,ink,1.7,true)
	for axis in [Vector2.RIGHT,Vector2.DOWN]:
		for sign_value in [-1,1]:
			draw_line(projected+axis*sign_value*4,projected+axis*sign_value*10,paper,4,true)
			draw_line(projected+axis*sign_value*4,projected+axis*sign_value*10,ink,1.4,true)
	draw_circle(projected,2.1,ink,true,-1,true)
	var label_size := Vector2(154,24)
	var label_at := projected+Vector2(22,-33)
	label_at.x = clampf(label_at.x,4,maxf(4,size.x-label_size.x-4))
	label_at.y = clampf(label_at.y,4,maxf(4,size.y-label_size.y-4))
	var panel := WarUISkin.panel(Color(paper,.96),4,0)
	panel.border_color = Color(ink,.35)
	draw_style_box(panel,Rect2(label_at,label_size))
	draw_circle(label_at+Vector2(10,12),2,ink,true,-1,true)
	draw_string(WarUISkin.BODY,label_at+Vector2(18,16),"X %04d  ·  Y %04d" % [roundi(point.x),roundi(point.y)],HORIZONTAL_ALIGNMENT_LEFT,-1,11,ink)
