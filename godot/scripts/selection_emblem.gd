class_name WarSelectionEmblem
extends Control
var world: WarWorldView
var entities: Array = []
var elapsed := 0.0
var frame := WarUISkin.painted_panel(Color.WHITE,14,0,"badge")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	elapsed += delta
	if is_visible_in_tree(): queue_redraw()

func _draw() -> void:
	draw_style_box(frame,Rect2(Vector2(1,1),size-Vector2(2,2)))
	if entities.is_empty() or world == null: return
	var e: Dictionary = entities[0]
	var breathing := 1.0 if e.get("kind","") == "worker" else 1+sin(elapsed*2.4)*.018
	draw_set_transform(Vector2.ZERO if e.get("kind","") == "worker" else Vector2(0,sin(elapsed*2.4)*1.1),0,Vector2.ONE*breathing)
	if e.get("category","") == "building":
		WarFacetSurface.paint(self,Rect2(Vector2(15,21),size-Vector2(30,30)),WarUISkin.HONEY,3,3)
		draw_colored_polygon(PackedVector2Array([Vector2(11,23),Vector2(size.x*.5,10),Vector2(size.x-11,23)]),WarUISkin.MUTED)
		return
	var pose := world.animation(e,false)
	var box := Rect2(Vector2(4,3),size-Vector2(8,10))
	if not pose.is_empty() and pose.has("clip"):
		var clip: Dictionary = pose.clip
		var texture := world.textures.get_texture(clip.path)
		if texture:
			var frame := int(pose.frame)
			var source := Rect2(Vector2(frame%int(clip.columns),frame/int(clip.columns))*float(clip.frameSize),Vector2.ONE*float(clip.frameSize))
			draw_texture_rect_region(texture,box,source)
	else:
		var data: Dictionary = WarData.config().CellFrames
		var asset: Dictionary = data.assets[data.kinds.get(e.kind,"red")]
		var texture := world.textures.get_texture(asset.path)
		if texture: draw_texture_rect(texture,box,false)
