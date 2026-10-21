class_name WarLegacySurface
extends Node
## Only the legacy vector base is supersampled. Registered organ overlays,
## fullbody anatomy layers, units and HUD keep independent canvases.
class Painter extends Node2D:
	var world: WarWorldView
	func _draw() -> void:
		world.legacy.draw_base_layer(self,world)

var world: WarWorldView
var viewport: SubViewport
var camera: Camera2D
var painter: Painter
var world_rect := Rect2()

func setup(source: WarWorldView) -> void:
	world = source
	viewport = SubViewport.new()
	viewport.world_2d = World2D.new()
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	camera = Camera2D.new(); viewport.add_child(camera)
	painter = Painter.new(); painter.world = world; viewport.add_child(painter)

func sync(active: bool) -> void:
	if not active:
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	var size := world.get_viewport_rect().size
	var factor := 2.0
	var target := Vector2i(size*factor)
	if viewport.size != target: viewport.size = target
	camera.position = world.camera.position
	camera.offset = world.camera.offset
	camera.zoom = world.camera.zoom*factor
	camera.force_update_scroll()
	var dimensions := size/world.camera.zoom
	world_rect = Rect2(world.camera.get_screen_center_position()-dimensions*.5,dimensions)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	painter.queue_redraw()

func draw(canvas: CanvasItem) -> void:
	canvas.draw_texture_rect(viewport.get_texture(),world_rect,false)
