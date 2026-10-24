class_name WarOrderPulse
extends Control
## Compact acknowledgement after the chosen badge reaches its actual target.
var age := 0.0
var caption: Label
var frame := WarUISkin.painted_panel(Color("e2f3e7"),12,0,"compact")

func configure(at: Vector2,action: String,queued := false) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 76
	size = Vector2(140,56)
	position = (at-Vector2(70,21)).clamp(Vector2(8,8),get_viewport_rect().size-size-Vector2(8,8))
	var names := {"move":"移动","attack":"攻击","attackmove":"进攻","guard":"驻守","retreat":"撤退","stop":"停止","harvest":"采集","repair":"维修","build":"协助建造","rally":"集结"}
	var title: String = names.get(action,"建造" if action.begins_with("place:") else "指令")
	caption = Label.new()
	caption.text = title+("已排队" if queued else "已下达")
	caption.position = Vector2(0,38); caption.size = Vector2(140,22)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_override("font",WarUISkin.BUTTON)
	caption.add_theme_font_size_override("font_size",17)
	caption.add_theme_color_override("font_color",WarUISkin.INK)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(caption)

func _process(delta: float) -> void:
	age += delta
	modulate.a = smoothstep(0,.08,age)*(1-smoothstep(.48,.72,age))
	queue_redraw()
	if age > .72: queue_free()

func _draw() -> void:
	draw_style_box(frame,Rect2(Vector2(51,1),Vector2(38,36)))
	var progress := clampf(age/.16,0,1)
	var a := Vector2(62,16)
	var b := Vector2(69,23)
	var c := Vector2(80,11)
	if progress < .4: draw_line(a,a.lerp(b,progress/.4),WarUISkin.INK,2.5,true)
	else:
		draw_line(a,b,WarUISkin.INK,2.5,true)
		draw_line(b,b.lerp(c,(progress-.4)/.6),WarUISkin.INK,2.5,true)
