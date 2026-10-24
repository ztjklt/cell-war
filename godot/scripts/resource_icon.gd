class_name WarResourceIcon
extends WarSmoothIcon
var kind := "oxygen"
var frame := WarUISkin.painted_panel(Color.WHITE,14,0,"micro")

func _gem(canvas: CanvasItem,at: Vector2,radius: float,color: Color) -> void:
	var rect := Rect2(at-Vector2.ONE*radius,Vector2.ONE*radius*2)
	var outer := WarFacetSurface.vertices(rect,2,true)
	canvas.draw_colored_polygon(WarFacetSurface.outline(rect,2,true),color)
	canvas.draw_colored_polygon(PackedVector2Array([outer[0],outer[1],at,outer[5]]),color.lightened(.18))
	canvas.draw_colored_polygon(PackedVector2Array([outer[1],outer[2],outer[3],at]),color.darkened(.16))
	canvas.draw_colored_polygon(PackedVector2Array([outer[3],outer[4],outer[5],at]),color.darkened(.06))

func _paint_icon(canvas: CanvasItem) -> void:
	var side := minf(size.x,size.y)
	var center := size*.5
	var color := WarUISkin.SAGE if kind == "oxygen" else (WarUISkin.HONEY if kind == "food" else WarUISkin.LILAC)
	frame.modulate_color = color.lightened(.32)
	canvas.draw_style_box(frame,Rect2(center-Vector2.ONE*side*.48,Vector2.ONE*side*.96))
	if kind == "oxygen":
		canvas.draw_line(center-Vector2(side*.15,1),center+Vector2(side*.15,-1),WarUISkin.CREAM,2,true)
		for offset in [-.15,.15]: _gem(canvas,center+Vector2(offset*side,-1),side*.15,Color("fff6e5"))
	elif kind == "food":
		for at in [Vector2(0,-.16),Vector2(-.16,.12),Vector2(.16,.12)]: _gem(canvas,center+at*side,side*.15,Color("fff4d3"))
	else:
		var points := [center+Vector2(0,-.2)*side,center+Vector2(-.19,.13)*side,center+Vector2(.19,.13)*side]
		for at in points:
			canvas.draw_line(center,at,WarUISkin.CREAM,2,true)
			_gem(canvas,at,side*.13,Color("f5eefb"))
