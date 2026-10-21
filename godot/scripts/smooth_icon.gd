class_name WarSmoothIcon
extends Control
## Supersample only the small icon, including polygon faces, on Compatibility.
## Viewports render on demand; settled icons do not redraw every frame.
# Twofold dimensions + linear minification combine four samples per output pixel.
const SAMPLE_SCALE := 2

class IconPainter extends Node2D:
	var icon: WarSmoothIcon
	func _draw() -> void:
		icon._paint_icon(self)

var icon_viewport: SubViewport
var icon_painter: IconPainter

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	icon_viewport = SubViewport.new()
	icon_viewport.name = "IconSamples"
	icon_viewport.transparent_bg = true
	icon_viewport.disable_3d = true
	icon_viewport.gui_disable_input = true
	icon_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(icon_viewport)
	icon_painter = IconPainter.new()
	icon_painter.icon = self
	icon_painter.scale = Vector2.ONE*SAMPLE_SCALE
	icon_viewport.add_child(icon_painter)
	resized.connect(queue_redraw)
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(icon_viewport) or size.x <= 0 or size.y <= 0: return
	icon_viewport.size = Vector2i((size*SAMPLE_SCALE).ceil())
	icon_painter.queue_redraw()
	icon_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	draw_texture_rect(icon_viewport.get_texture(),Rect2(Vector2.ZERO,size),false)

func _paint_icon(_canvas: CanvasItem) -> void:
	pass
