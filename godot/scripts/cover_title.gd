class_name WarCoverTitle
extends Control
## Neo-constructivist ivory / scarlet / navy sculpture, gently suspended in space.
var text := ""
var english := false
const LETTERING = preload("res://assets/image/cover-titles-20261021/constructivist-titles-v2.png")
var phase := 0.0

func float_offset() -> float:
	return sin(phase)*(4.5 if size.x < 300 else 11.0)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	resized.connect(queue_redraw)
	phase = .45 if english else 0.0
	visibility_changed.connect(func(): set_process(is_visible_in_tree()))
	set_process(is_visible_in_tree())

func _process(delta: float) -> void:
	phase += delta*1.55
	queue_redraw()

func _draw() -> void:
	var source := Rect2(56,538,1659,308) if english else Rect2(95,36,1601,491)
	var width := size.x-12
	var height := width*source.size.y/source.size.x
	var pivot := Vector2(size.x*.5,(size.y-height)*.35+height*.5+float_offset())
	# Lean the two wordmarks inward while retaining vertical suspension.
	draw_set_transform(pivot,deg_to_rad(3.0 if english else -3.0))
	var rect := Rect2(Vector2(-width*.5,-height*.5),Vector2(width,height))
	draw_texture_rect_region(LETTERING,rect,source)
	draw_set_transform_matrix(Transform2D.IDENTITY)
