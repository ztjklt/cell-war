class_name WarOverviewIcon
extends Control
## Four framing corners and a body silhouette; the button has no text.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var center := size*.5
	var half := size*Vector2(.27,.25)
	var ink := WarUISkin.INK
	for side in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
		var p: Vector2 = center+half*side
		draw_polyline(PackedVector2Array([p-Vector2(side.x*6,0),p,p-Vector2(0,side.y*6)]),ink,1.8,true)
	draw_circle(center+Vector2(0,-6),2.2,ink,true,-1,true)
	draw_polyline(PackedVector2Array([center+Vector2(-5,0),center+Vector2(0,-2),center+Vector2(5,0)]),ink,1.8,true)
	draw_polyline(PackedVector2Array([center+Vector2(-3,8),center+Vector2(0,-2),center+Vector2(3,8)]),ink,1.8,true)
