class_name WarHeartDisplay
extends RefCounted
## Native port of HeartMotion + HeartDisplayTransform. Navigation stays authored.
var data: Dictionary
var source := PackedVector2Array()
var target := PackedVector2Array()
var box: Rect2
var triangles: Array
var _time := INF
var _geometry: Dictionary = {}
var _meshes: Dictionary = {}

func _init() -> void:
	data = WarData.read("presentation").heart
	for p in data.vertices: source.append(Vector2(p[0],p[1]))
	target = source.duplicate()
	box = Rect2(Vector2(data.sourceBox[0],data.sourceBox[1]),Vector2(data.sourceBox[2]-data.sourceBox[0],data.sourceBox[3]-data.sourceBox[1]))
	triangles = data.triangles

static func smooth(value: float) -> float:
	var t := clampf(value,0,1)
	return t*t*(3-2*t)

static func envelope(p: float,a: float,b: float,c: float) -> float:
	if p <= a or p >= c: return 0
	return smooth((p-a)/(b-a)) if p < b else 1-smooth((p-b)/(c-b))

func sample(time: float) -> void:
	if time == _time: return
	_time = time
	var phase := fposmod(time,1)
	var atrial := -envelope(phase,.01,.10,.23)+.18*envelope(phase,.22,.31,.43)
	var ventricular := -envelope(phase,.18,.30,.49)+.22*envelope(phase,.46,.59,.79)
	for i in source.size():
		var basis: Array = data.bases[i]
		if basis.is_empty(): target[i] = source[i]; continue
		var offset := Vector2(basis[0]*atrial+basis[2]*ventricular,basis[1]*atrial+basis[3]*ventricular)
		offset = offset.limit_length(float(basis[4]))*float(data.weights[i])
		target[i] = source[i]+offset

func _weights(p: Vector2,a: Vector2,b: Vector2,c: Vector2) -> Vector3:
	var u := b-a
	var v := c-a
	var det := u.cross(v)
	var w := Vector2((p-a).cross(v)/det,u.cross(p-a)/det)
	return Vector3(1-w.x-w.y,w.x,w.y)

func _bound(p: Vector2,vertices: PackedVector2Array) -> Array:
	for tr in triangles:
		var w := _weights(p,vertices[int(tr[0])],vertices[int(tr[1])],vertices[int(tr[2])])
		if w.x >= -.00001 and w.y >= -.00001 and w.z >= -.00001: return [tr,w]
	return []

func forward(p: Vector2) -> Vector2:
	var q := Vector2(p.x*.5,(p.y-512)*.5)
	if not box.has_point(q): return p
	var binding := _bound(q,source)
	if binding.is_empty(): return p
	return _apply(binding)

func inverse(p: Vector2) -> Vector2:
	var q := Vector2(p.x*.5,(p.y-512)*.5)
	if not box.grow(1).has_point(q): return p
	var binding := _bound(q,target)
	if binding.is_empty(): return p
	var tr: Array = binding[0]
	var w: Vector3 = binding[1]
	return (source[int(tr[0])]*w.x+source[int(tr[1])]*w.y+source[int(tr[2])]*w.z)*2+Vector2(0,512)

func _apply(binding: Array) -> Vector2:
	var tr: Array = binding[0]
	var w: Vector3 = binding[1]
	return (target[int(tr[0])]*w.x+target[int(tr[1])]*w.y+target[int(tr[2])]*w.z)*2+Vector2(0,512)

func _clip(points: PackedVector2Array,axis: int,value: float,sign: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if points.is_empty(): return out
	var previous := points[-1]
	for current in points:
		var pa := (previous.x if axis == 0 else previous.y)-value
		var ca := (current.x if axis == 0 else current.y)-value
		if (pa*sign >= 0) != (ca*sign >= 0): out.append(previous.lerp(current,pa/(pa-ca)))
		if ca*sign >= 0: out.append(current)
		previous = current
	return out

func _prepare(rect: Rect2) -> Array:
	var parts: Array = []
	var overlap := rect.intersection(box)
	if not overlap.has_area(): return parts
	for tr in triangles:
		var a := source[int(tr[0])]
		var b := source[int(tr[1])]
		var c := source[int(tr[2])]
		var points := PackedVector2Array([a,b,c])
		points = _clip(points,0,rect.position.x,1)
		points = _clip(points,0,rect.end.x,-1)
		points = _clip(points,1,rect.position.y,1)
		points = _clip(points,1,rect.end.y,-1)
		for i in range(1,points.size()-1):
			for p in [points[0],points[i],points[i+1]]:
				parts.append({"source":p,"bind":[tr,_weights(p,a,b,c)]})
	for r in [Rect2(rect.position,Vector2(rect.size.x,overlap.position.y-rect.position.y)),Rect2(Vector2(rect.position.x,overlap.end.y),Vector2(rect.size.x,rect.end.y-overlap.end.y)),Rect2(Vector2(rect.position.x,overlap.position.y),Vector2(overlap.position.x-rect.position.x,overlap.size.y)),Rect2(Vector2(overlap.end.x,overlap.position.y),Vector2(rect.end.x-overlap.end.x,overlap.size.y))]:
		if r.has_area():
			for p in [r.position,Vector2(r.end.x,r.position.y),r.end,r.position,r.end,Vector2(r.position.x,r.end.y)]: parts.append({"source":p,"bind":[]})
	return parts

func draw_spec(canvas: CanvasItem,spec: Dictionary,texture: Texture2D,alpha: float) -> bool:
	var b: Array = spec.sourceBox
	var rect := Rect2(Vector2(b[0],b[1]),Vector2(b[2]-b[0],b[3]-b[1]))
	if not rect.intersects(box): return false
	var key := str(spec.sourceBox)
	if not _geometry.has(key): _geometry[key] = _prepare(rect)
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	for part in _geometry[key]:
		vertices.append(_apply(part.bind) if not part.bind.is_empty() else part.source*2+Vector2(0,512))
		uvs.append((part.source-rect.position)/rect.size)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	_meshes[spec.resource] = mesh
	canvas.draw_mesh(mesh,texture,Transform2D.IDENTITY,Color(1,1,1,alpha))
	return true
