class_name WarBrainRig
extends Control
## BrainRig.lua's original layered puppet, using the original crop/UV contracts.
var data: Dictionary = WarData.read("presentation").brainRig
var textures: Dictionary = {}
var meshes: Dictionary = {}
var time := 0.0
var look := Vector2.ZERO
var pointer := Vector2(INF,INF)
var transform := Transform2D.IDENTITY
var speaking := false
var mood := "idle"

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for key in data.assets: textures[key] = load("res://assets/"+data.assets[key].path)

func _process(delta: float) -> void:
	time += delta
	var mouse := get_local_mouse_position()
	var desired := (mouse-size*.5)/(size*.7)
	var blend := 1-exp(-10*delta)
	look = look.lerp(desired.clamp(Vector2(-1,-1),Vector2.ONE),blend)
	pointer = mouse if not is_finite(pointer.x) else pointer.lerp(mouse,blend)
	queue_redraw()

func _polygon(points: Array,texture: Texture2D,uv_points: Array = []) -> void:
	var p := PackedVector2Array()
	var uv := PackedVector2Array()
	for i in points.size():
		p.append(Vector2(points[i][0],points[i][1]))
		var q: Array = uv_points[i] if not uv_points.is_empty() else points[i]
		uv.append(Vector2(q[0]/data.width,q[1]/data.height))
	draw_set_transform_matrix(transform)
	draw_colored_polygon(p,Color.WHITE,uv,texture)

func _texture(key: String,rect: Rect2,ellipse := false) -> void:
	var a: Dictionary = data.assets[key]
	var crop: Array = a.crop
	var points := PackedVector2Array()
	var uv := PackedVector2Array()
	var count := 40 if ellipse else 4
	for i in count:
		var point: Vector2 = Vector2(.5,.5)+Vector2.from_angle(float(i)/count*TAU)*.5 if ellipse else [Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN][i]
		points.append(rect.position+point*rect.size)
		uv.append((Vector2(crop[0],crop[1])+point*Vector2(crop[2],crop[3]))/Vector2(a.w,a.h))
	draw_set_transform_matrix(transform)
	draw_colored_polygon(points,Color.WHITE,uv,textures[key])

func _quad(key: String,source: Array,target: Array,alpha: float) -> void:
	var p := PackedVector2Array()
	var uv := PackedVector2Array()
	var a: Dictionary = data.assets[key]
	# Match the two source triangles instead of interpolating the quad as a fan.
	for i in [0,1,2,0,2,3]:
		p.append(Vector2(target[i][0],target[i][1]))
		uv.append(Vector2(source[i][0]/a.w,source[i][1]/a.h))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = p
	arrays[Mesh.ARRAY_TEX_UV] = uv
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	draw_set_transform_matrix(transform)
	meshes[key] = mesh
	draw_mesh(mesh,textures[key],Transform2D.IDENTITY,Color(1,1,1,alpha))

func _draw() -> void:
	if textures.is_empty(): return
	var scale := minf(size.x/data.width,size.y/data.height)*.93
	var breath := sin(time*1.8)*.012
	transform = Transform2D.IDENTITY.translated_local(size*.5).scaled_local(Vector2.ONE*scale).translated_local(Vector2(0,sin(time*1.25)*9)).rotated_local(sin(time*.8)*.009+look.x*.008).scaled_local(Vector2(1+breath,1-breath*.7)).translated_local(Vector2(-data.width*.5,-data.height*.5))
	var outer := transform
	for part in data.arms:
		var pivot := Vector2(part.pivot[0],part.pivot[1])
		transform = outer.translated_local(pivot).rotated_local((sin(time*1.45+part.phase)-sin(part.phase))*.023).translated_local(-pivot)
		_polygon(part.polygon,textures.anatomy)
	transform = outer
	_polygon(data.core,textures.anatomy)
	transform = outer.translated_local(look*Vector2(1.2,.8))
	var face := transform
	var cycle := fposmod(time+2.3,4.7)
	var blink := 1-sin(cycle/.2*PI) if cycle < .2 else 1.0
	var cursor := transform.affine_inverse()*(pointer if is_finite(pointer.x) else get_local_mouse_position())
	for eye in [[205.5,232.5,35.5,39.0,212.0,234.0,22.0,42.0],[291.0,221.0,22.5,34.0,285.5,223.5,16.0,37.0]]:
		transform = face
		draw_set_transform_matrix(transform)
		draw_ellipse(Vector2(eye[0],eye[1]),eye[2],eye[3],Color("fff8f0"))
		if blink > .25:
			var center := Vector2(eye[0],eye[1])
			var delta := cursor-center
			var gaze := delta/sqrt(delta.length_squared()+80*80)*Vector2(13 if eye[0] < 250 else 8,9 if eye[0] < 250 else 8)
			transform = face.translated_local(center+gaze).scaled_local(Vector2(1,maxf(.05,blink)))
			_texture("pupil",Rect2(Vector2(-eye[6]*.5,-eye[7]*.5),Vector2(eye[6],eye[7])),true)
		else: _texture("closed",Rect2(Vector2(eye[0]-eye[2],eye[1]-eye[3]),Vector2(eye[2]*2,eye[3]*2)),true)
	transform = face
	_texture("glasses",Rect2(165,179,154,98))
	if speaking or mood == "happy":
		var mouth: String = ["talkA","talkB","talkO","neutral"][int(time*8)%4] if speaking else "happy"
		_texture(mouth,Rect2(232,273,23,10 if mouth == "neutral" else 23))
	transform = outer.translated_local(Vector2(285,310)).rotated_local(sin(time*1.4)*.012).translated_local(Vector2(-285,-310+sin(time*1.7)*1.1))
	var corners := [[264,276],[384,244],[345,330],[207,359]]
	_quad("tabletBase",[[21,22],[127,0],[109,74],[2,104]],corners,1)
	_quad("tabletOutline",[[28,24],[123,0],[105,79],[12,101]],corners,.78)
	_quad("tablet",[[4,24],[109,0],[102,76],[0,108]],[[265,277],[381,248],[343,328],[211,355]],.94+sin(time*2.1)*.04)
	transform = outer
	if mood == "alert": _texture("alert",Rect2(336,44,20,31))
	elif mood == "thinking": _texture("question",Rect2(335,44,22,30))
	draw_set_transform_matrix(Transform2D.IDENTITY)
