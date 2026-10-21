class_name WarCameraTravel
extends Node
## Move the native camera in real time, including while tactical time is paused.
var camera: Camera2D
var update_frame: Callable
var target_position := Vector2.ZERO
var target_zoom := 1.0
var active := false

func reset() -> void:
	active = false
	target_position = camera.position
	target_zoom = camera.zoom.x

func aim(point: Vector2,zoom: float) -> void:
	target_position = point
	target_zoom = zoom
	active = true

func _process(delta: float) -> void:
	if not active: return
	var amount := 1-exp(-12*maxf(0,delta))
	camera.position = camera.position.lerp(target_position,amount)
	camera.zoom = Vector2.ONE*exp(lerpf(log(camera.zoom.x),log(target_zoom),amount))
	if absf(log(camera.zoom.x/target_zoom)) < .0001 and camera.position.distance_to(target_position)*target_zoom < .02:
		camera.position = target_position
		camera.zoom = Vector2.ONE*target_zoom
		active = false
	update_frame.call()
	camera.force_update_scroll()
