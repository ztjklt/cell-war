extends Control
## GPT-painted stage behind the unmodified source character and animation.
const BACKDROP = preload("res://assets/ui/catalogue/specimen-stage.png")
var frame := StyleBoxFlat.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.bg_color = Color("f1eddf")
	frame.border_color = Color("dcd6c6")
	frame.set_corner_radius_all(20)
	frame.set_border_width_all(1)
	resized.connect(queue_redraw)

func _draw() -> void:
	draw_style_box(frame,Rect2(Vector2.ZERO,size))
	# Rounded textured geometry keeps the artwork full bleed without stretching it.
	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var radius := minf(19,minf(size.x,size.y)*.25)
	var corners := [Vector2(size.x-radius-1,radius+1),Vector2(size.x-radius-1,size.y-radius-1),Vector2(radius+1,size.y-radius-1),Vector2(radius+1,radius+1)]
	var texture_size := BACKDROP.get_size()
	var fit := maxf(size.x/texture_size.x,size.y/texture_size.y)
	var source_origin := (texture_size-size/fit)*Vector2(.5,1)
	for corner in 4:
		for step in 13:
			var angle := (-PI*.5+corner*PI*.5)+step/12.0*PI*.5
			var point: Vector2 = corners[corner]+Vector2.from_angle(angle)*radius
			points.append(point)
			uvs.append((point/fit+source_origin)/texture_size)
			colors.append(Color.WHITE)
	draw_polygon(points,colors,uvs,BACKDROP)
