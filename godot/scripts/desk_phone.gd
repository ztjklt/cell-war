class_name WarDeskPhone
extends Control
## Flat overhead phone; messages and choices are real sibling Controls.
var shell := StyleBoxFlat.new()
var screen := StyleBoxFlat.new()

static func rect_for(view: Vector2,expanded := true) -> Rect2:
	if view.x < 720:
		if not expanded: return Rect2(view.x-172,196,160,196)
		return Rect2(12,190,view.x-24,maxf(250,view.y-358))
	var width := clampf(view.x*.26,320,374)
	return Rect2(view.x-width-40,220,width,maxf(320,view.y-232))

func content_rect() -> Rect2:
	return Rect2(Vector2(15,36),size-Vector2(30,58))

func _ready() -> void:
	# Blank phone glass must not send a command to the map beneath it on portrait.
	mouse_filter = Control.MOUSE_FILTER_STOP
	shell.bg_color = Color("2d3934")
	shell.border_color = Color("534b3e")
	shell.set_border_width_all(2)
	shell.set_corner_radius_all(25)
	screen.bg_color = Color("edf0e6")
	screen.border_color = Color("bdc4b2")
	screen.set_border_width_all(1)
	screen.set_corner_radius_all(15)
	resized.connect(queue_redraw)

func _draw() -> void:
	draw_style_box(shell,Rect2(Vector2.ZERO,size))
	draw_style_box(screen,Rect2(Vector2(7,23),size-Vector2(14,39)))
	draw_line(Vector2(size.x*.5-19,12),Vector2(size.x*.5+13,12),Color("7c897d"),3,true)
	draw_circle(Vector2(size.x*.5+25,12),2,Color("9ba696"),true,-1,true)
	draw_line(Vector2(size.x*.5-20,size.y-8),Vector2(size.x*.5+20,size.y-8),Color("a6b19f"),3,true)
