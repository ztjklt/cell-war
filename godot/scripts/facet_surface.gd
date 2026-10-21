class_name WarFacetSurface
extends Node2D
## Shared cut faces for real Controls; Node2D children never join Container layout.
var host: Control
var fill := Color("fff8eb")
var depth := 5.0
var cut := 14.0
var hover_amount := 0.0
var press_amount := 0.0
var highlight := 0.0:
	set(value):
		highlight = value; queue_redraw()
var pulse_tween: Tween

func pulse() -> void:
	if pulse_tween: pulse_tween.kill()
	highlight = 1
	pulse_tween = create_tween()
	pulse_tween.tween_property(self,"highlight",0.0,.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

static func vertices(rect: Rect2,corner: float,hexagon := false) -> PackedVector2Array:
	var p := rect.position
	var s := rect.size
	if hexagon:
		return PackedVector2Array([p+Vector2(s.x*.22,0),p+Vector2(s.x*.78,0),p+Vector2(s.x,s.y*.5),p+Vector2(s.x*.78,s.y),p+Vector2(s.x*.22,s.y),p+Vector2(0,s.y*.5)])
	var c := minf(corner,minf(s.x,s.y)*.35)
	return PackedVector2Array([p+Vector2(c,0),p+Vector2(s.x-c,0),p+Vector2(s.x,c),p+Vector2(s.x,s.y-c),p+Vector2(s.x-c,s.y),p+Vector2(c,s.y),p+Vector2(0,s.y-c),p+Vector2(0,c)])

static func rounded_polygon(polygon: PackedVector2Array,radius: float,steps := 6) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in polygon.size():
		var current := polygon[i]
		var incoming := polygon[(i-1+polygon.size())%polygon.size()]-current
		var outgoing := polygon[(i+1)%polygon.size()]-current
		var u := incoming.normalized()
		var v := outgoing.normalized()
		var half_angle := acos(clampf(u.dot(v),-.9999,.9999))*.5
		var distance := minf(radius/tan(half_angle),minf(incoming.length(),outgoing.length())*.44)
		var actual_radius := distance*tan(half_angle)
		var center := current+(u+v).normalized()*(actual_radius/sin(half_angle))
		var entry := current+u*distance
		var leave := current+v*distance
		var start := (entry-center).angle()
		var sweep := wrapf((leave-center).angle()-start,-PI,PI)
		for sample in steps+1:
			result.append(center+Vector2.from_angle(start+sweep*float(sample)/steps)*actual_radius)
	return result

static func outline(rect: Rect2,corner: float,hexagon := false) -> PackedVector2Array:
	# True circular tangent fillets; keep planar sides and their shallow depth.
	return rounded_polygon(vertices(rect,corner,hexagon),minf(14,minf(rect.size.x,rect.size.y)*.14))

static func paint(canvas: CanvasItem,rect: Rect2,color: Color,thickness := 5.0,corner := 14.0,hexagon := false,hover := 0.0,pressed := 0.0) -> void:
	if rect.size.x < 8 or rect.size.y < 8: return
	var offset := lerpf(0,thickness*.65,pressed)-hover*1.5
	var front := Rect2(rect.position+Vector2(0,offset),rect.size-Vector2(0,thickness))
	var outer := outline(front,corner,hexagon)
	var back := outer.duplicate()
	for i in back.size(): back[i].y += thickness*(1-pressed*.65)
	canvas.draw_colored_polygon(back,color.darkened(.23))
	var base := color.lightened(hover*.06)
	canvas.draw_colored_polygon(outer,base)
	var inner := outline(front.grow(-3.5),maxf(2,corner-2),hexagon)
	for i in outer.size():
		var next := (i+1)%outer.size()
		var edge := (outer[next]-outer[i]).normalized()
		var light := Vector2(edge.y,-edge.x).dot(Vector2(-.45,-.89))*.16
		var tone := base.lightened(light) if light > 0 else base.darkened(-light)
		canvas.draw_colored_polygon(PackedVector2Array([outer[i],outer[next],inner[next],inner[i]]),tone)
	canvas.draw_colored_polygon(inner,base)
	var line := outer.duplicate(); line.append(outer[0])
	canvas.draw_polyline(line,Color("99775a")*Color(1,1,1,.36),1,true)

static func attach(control: Control,color: Color,thickness := 5.0,corner := 14.0) -> WarFacetSurface:
	var old := control.get_node_or_null("_FacetSurface") as WarFacetSurface
	if old != null:
		old.fill = color; old.depth = thickness; old.cut = corner; old.queue_redraw()
		return old
	var node := WarFacetSurface.new()
	node.name = "_FacetSurface"
	node.host = control; node.fill = color; node.depth = thickness; node.cut = corner
	node.show_behind_parent = true
	control.add_child(node)
	control.resized.connect(node.queue_redraw)
	if control is Button:
		for state in ["normal","hover","pressed","disabled","focus"]:
			var skin := control.get_theme_stylebox(state).duplicate() as StyleBoxFlat
			if skin == null: skin = StyleBoxFlat.new()
			skin.bg_color = Color.TRANSPARENT; skin.set_border_width_all(0); skin.shadow_size = 0
			control.add_theme_stylebox_override(state,skin)
	return node

func _process(delta: float) -> void:
	if host == null or not host.is_visible_in_tree(): return
	if host is Button:
		var button := host as Button
		var next_hover := move_toward(hover_amount,1.0 if button.is_hovered() and not button.disabled else 0.0,delta*9)
		var next_press := move_toward(press_amount,1.0 if button.is_pressed() and not button.disabled else 0.0,delta*20)
		if next_hover != hover_amount or next_press != press_amount:
			hover_amount = next_hover; press_amount = next_press; queue_redraw()

func _draw() -> void:
	if host == null: return
	var color := Color("e2dbd0") if host is Button and (host as Button).disabled else fill
	paint(self,Rect2(Vector2.ZERO,host.size),color.lightened(highlight*.1),depth,cut,false,hover_amount,press_amount)
