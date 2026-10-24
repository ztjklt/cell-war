class_name WarHUDPlate
extends PanelContainer
## GPT-painted membrane under native containers; the artwork has no input surface.
const RESOURCE = preload("res://assets/ui/hud/resource-plate.png")
const SELECTION = preload("res://assets/ui/hud/selection-plate.png")
var artwork: AtlasTexture
var highlight := 0.0:
	set(value):
		highlight = value
		queue_redraw()
var pulse_tween: Tween

func configure(resource := false) -> void:
	artwork = AtlasTexture.new()
	artwork.atlas = RESOURCE if resource else SELECTION
	# Exclude near-transparent outer padding; source PNGs stay unchanged.
	artwork.region = Rect2(48,117,2075,476) if resource else Rect2(56,155,1662,579)
	var skin := WarUISkin.panel(Color.TRANSPARENT,0,8 if resource else 14)
	skin.set_border_width_all(0)
	if resource:
		skin.content_margin_top = 6; skin.content_margin_bottom = 6
	add_theme_stylebox_override("panel",skin)
	resized.connect(queue_redraw)

func pulse() -> void:
	reset_feedback()
	highlight = 1
	pulse_tween = create_tween()
	pulse_tween.tween_property(self,"highlight",0.0,.38).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func reset_feedback() -> void:
	if pulse_tween != null: pulse_tween.kill()
	highlight = 0

func _draw() -> void:
	if artwork != null:
		draw_texture_rect(artwork,Rect2(Vector2.ZERO,size),false,Color(1+highlight*.06,1+highlight*.025,1,1))
