class_name WarVisionEye
extends Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var center := size*.5
	var rx := size.x*.28
	var ry := size.y*.18
	var points := PackedVector2Array()
	for side in [-1,1]:
		var a := center+Vector2(-rx if side == -1 else rx,0)
		var b := center+Vector2(-rx*.4 if side == -1 else rx*.4,ry*1.6*side)
		var c := center+Vector2(rx*.4 if side == -1 else -rx*.4,ry*1.6*side)
		var d := center+Vector2(rx if side == -1 else -rx,0)
		for i in 17:
			var t := float(i)/16
			var u := 1-t
			points.append(a*u*u*u+b*3*u*u*t+c*3*u*t*t+d*t*t*t)
	draw_polyline(points,WarUISkin.INK,size.x*.04,true)
	draw_circle(center,ry*.55,WarUISkin.INK,true,-1,true)
