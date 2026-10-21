class_name WarCommandBackdrop
extends Control
## A strictly overhead, flat illustrated desk; scenery never receives input.
const DESKTOP = preload("res://assets/image/command-desk-20261021/command-desk-balanced-wide-v6.png")
const PORTRAIT_PATH := "res://assets/image/command-desk-20261021/command-desk-balanced-portrait-v6.png"
var portrait: Texture2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(PORTRAIT_PATH): portrait = load(PORTRAIT_PATH)
	resized.connect(queue_redraw)
	queue_redraw()

func _draw() -> void:
	var image: Texture2D = portrait if size.x < 720 and portrait != null else DESKTOP
	var factor := maxf(size.x/image.get_width(),size.y/image.get_height())
	var image_size := image.get_size()*factor
	var origin := (size-image_size)*.5
	draw_texture_rect(image,Rect2(origin,image_size),false)
	# Printed notebook ink follows the artwork through cover scaling and cropping.
	var narrow := size.x < 720
	var anchor := image.get_size()*(Vector2(.31,.065) if narrow else Vector2(.175,.151))
	var font_size := roundi(image.get_width()*(19.0/852.0 if narrow else 20.0/1586.0))
	draw_set_transform(origin+anchor*factor,deg_to_rad(-16 if narrow else -14),Vector2.ONE*factor)
	draw_string(WarUISkin.BODY,Vector2.ZERO,"人体防卫部",HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color("654c35"))
	draw_set_transform(Vector2.ZERO)
