class_name WarWorldLayer
extends Node2D
## A retained, independently visible canvas for one original compositor pass.
var world: WarWorldView
@export var channel := 0

func _draw() -> void:
	if world != null: world.draw_layer(self,channel)
