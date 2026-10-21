class_name WarGrid
extends RefCounted
## The original eight-direction adjacency is authoritative, including diagonal
## sweeps. A visual raster or corner-cutting AStarGrid is insufficient here.

const DIRS := [Vector2i(-1,-1), Vector2i(0,-1), Vector2i(1,-1), Vector2i(-1,0),
	Vector2i(1,0), Vector2i(-1,1), Vector2i(0,1), Vector2i(1,1)]
var width: int
var height: int
var origin: Vector2
var spacing: float
var valid: PackedByteArray
var adjacency: PackedByteArray
var components: PackedByteArray
var rings: Array = []
var _cost: Dictionary = {}
var _parent: Dictionary = {}
var _closed: Dictionary = {}
var _heap: Array = []
var _goal: int = -1
var _start: int = -1
var searching := false
var found := false
var segment_validator: Callable
var _attachments: Dictionary = {}
var blockers: Array = []
var moving_radius := .6
var moving_faction := 1

func _init(data: Dictionary) -> void:
	width = int(data.width)
	height = int(data.height)
	origin = WarData.source_to_world(data.origin)
	spacing = float(data.step) * 2.0
	valid = data.valid if data.has("valid") else Marshalls.base64_to_raw(data.validBase64)
	adjacency = data.adjacency if data.has("adjacency") else Marshalls.base64_to_raw(data.adjacencyBase64)
	components = data.components if data.has("components") else Marshalls.base64_to_raw(data.componentBase64)
	rings = prepare_rings(data.safeRings)
	assert(valid.size() == width * height and adjacency.size() == valid.size())

static func prepare_rings(raw: Variant) -> Array:
	var result: Array = []
	for ring in WarData.array(raw):
		var outer := PackedVector2Array()
		for p in ring.outer:
			outer.append(WarData.source_to_world(p))
		var holes: Array = []
		for raw_hole in WarData.array(ring.holes):
			var hole := PackedVector2Array()
			for p in raw_hole:
				hole.append(WarData.source_to_world(p))
			holes.append(hole)
		result.append({"outer": outer, "holes": holes})
	return result

static func inside(prepared: Array, p: Vector2) -> bool:
	for ring in prepared:
		if Geometry2D.is_point_in_polygon(p, ring.outer):
			var in_hole := false
			for hole in ring.holes:
				if Geometry2D.is_point_in_polygon(p, hole):
					in_hole = true
					break
			if not in_hole:
				return true
	return false

static func segment_inside(prepared: Array, a: Vector2, b: Vector2) -> bool:
	if not inside(prepared, a) or not inside(prepared, b):
		return false
	# Check exact polygon intersections, then test intervals. Sampling alone can
	# tunnel through a thin wall even when both endpoints are valid.
	var cuts: Array[float] = [0.0, 1.0]
	var delta := b - a
	if delta.length_squared() < 0.000000001:
		return true
	for ring in prepared:
		var boundaries: Array = [ring.outer]
		boundaries.append_array(ring.holes)
		for boundary in boundaries:
			for i in boundary.size():
				var hit: Variant = Geometry2D.segment_intersects_segment(a, b, boundary[i], boundary[(i+1) % boundary.size()])
				if hit != null:
					cuts.append(clampf((hit-a).dot(delta) / delta.length_squared(), 0.0, 1.0))
	cuts.sort()
	for i in range(1, cuts.size()):
		if not inside(prepared, a + delta * ((cuts[i-1]+cuts[i])*0.5)):
			return false
	return true

func position_of(index: int) -> Vector2:
	return origin + Vector2(index % width, index / width) * spacing

func nearest(p: Vector2, max_radius := 12, must_connect := true) -> int:
	var at := Vector2i(((p - origin) / spacing).round())
	var best := -1
	var distance := INF
	for radius in range(max_radius + 1):
		for y in range(maxi(0,at.y-radius), mini(height,at.y+radius+1)):
			for x in range(maxi(0,at.x-radius),mini(width,at.x+radius+1)):
				if radius > 0 and absi(x-at.x) < radius and absi(y-at.y) < radius:
					continue
				var index := y * width + x
				if valid[index] == 0:
					continue
				var q := position_of(index)
				var d := p.distance_squared_to(q)
				var connects: bool = segment_validator.call(p,q) if segment_validator.is_valid() else segment_inside(rings,p,q)
				if d < distance and (not must_connect or connects):
					best = index
					distance = d
		if best >= 0:
			return best
	return best

func component(p: Vector2) -> int:
	var index := nearest(p)
	return components[index] if index >= 0 else 0

func attachment(p: Vector2,target_component: int) -> int:
	var cache_key := str(p)+":"+str(target_component)
	if _attachments.has(cache_key): return int(_attachments[cache_key])
	var at := Vector2i(((p-origin)/spacing).round())
	var candidates: Array = []
	for y in range(maxi(0,at.y-12),mini(height,at.y+13)):
		for x in range(maxi(0,at.x-12),mini(width,at.x+13)):
			var index := y*width+x
			if valid[index] and int(components[index]) == target_component:
				candidates.append([p.distance_squared_to(position_of(index)),index])
	candidates.sort_custom(func(a,b): return a[0] < b[0])
	for row in candidates:
		var q := position_of(int(row[1]))
		var clear: bool = segment_validator.call(p,q) if segment_validator.is_valid() else segment_inside(rings,p,q)
		if clear:
			_attachments[cache_key] = int(row[1])
			return int(row[1])
	_attachments[cache_key] = -1
	if _attachments.size() > 1024: _attachments.clear()
	return -1

func begin(a: Vector2, b: Vector2) -> bool:
	_start = nearest(a)
	_goal = nearest(b)
	if _start >= 0 and _goal >= 0 and components[_start] != components[_goal]:
		# Tiny authored corridors can be narrower than the lattice spacing. A
		# longer exact polygon sweep can attach an endpoint to the main component
		# without jumping a wall or moving the endpoint itself.
		var alternate := attachment(a,int(components[_goal]))
		if alternate >= 0: _start = alternate
		else:
			alternate = attachment(b,int(components[_start]))
			if alternate >= 0: _goal = alternate
	_cost.clear()
	_parent.clear()
	_closed.clear()
	_heap.clear()
	found = false
	searching = _start >= 0 and _goal >= 0 and components[_start] == components[_goal]
	if searching:
		_cost[_start] = 0.0
		push(_start, position_of(_start).distance_to(position_of(_goal)))
	return searching

func push(index: int, score: float) -> void:
	var i := _heap.size()
	_heap.append([index, score])
	while i > 0:
		var parent := (i-1) / 2
		if _heap[parent][1] <= score:
			break
		_heap[i] = _heap[parent]
		i = parent
	_heap[i] = [index,score]

func pop() -> int:
	var first: int = _heap[0][0]
	var tail: Array = _heap.pop_back()
	if not _heap.is_empty():
		var i := 0
		while i*2+1 < _heap.size():
			var child := i*2+1
			if child+1 < _heap.size() and _heap[child+1][1] < _heap[child][1]:
				child += 1
			if tail[1] <= _heap[child][1]:
				break
			_heap[i] = _heap[child]
			i = child
		_heap[i] = tail
	return first

func advance(budget_usec := 3000) -> bool:
	var until := Time.get_ticks_usec() + budget_usec
	while searching and not _heap.is_empty() and Time.get_ticks_usec() < until:
		var index := pop()
		if _closed.has(index):
			continue
		if index == _goal:
			found = true
			searching = false
			break
		_closed[index] = true
		var mask := adjacency[index]
		for bit in 8:
			if mask & (1 << bit) == 0:
				continue
			var offset: Vector2i = DIRS[bit]
			var other := index + offset.y * width + offset.x
			if _closed.has(other):
				continue
			if point_blocked(position_of(other)): continue
			if offset.x != 0 and offset.y != 0:
				var at := position_of(index)
				if point_blocked(at+Vector2(offset.x,0)*spacing) or point_blocked(at+Vector2(0,offset.y)*spacing): continue
			var cost: float = _cost[index] + spacing * (1.41421356237 if offset.x != 0 and offset.y != 0 else 1.0)
			if cost < float(_cost.get(other,INF)):
				_cost[other] = cost
				_parent[other] = index
				push(other,cost+position_of(other).distance_to(position_of(_goal)))
	if _heap.is_empty():
		searching = false
	return not searching

func point_blocked(p: Vector2) -> bool:
	for blocker in blockers:
		if blocker.kind == "gate" and int(blocker.faction) == moving_faction: continue
		var radius := float(WarData.spec(blocker.kind).get("size",1))*.5+moving_radius
		if Rect2(WarData.point(blocker)-Vector2.ONE*radius,Vector2.ONE*radius*2).has_point(p): return true
	return false

func path() -> Array[Vector2]:
	var result: Array[Vector2] = []
	if not found:
		return result
	var index := _goal
	while true:
		result.append(position_of(index))
		if index == _start:
			break
		index = _parent[index]
	result.reverse()
	# Only remove collinear vertices; never smooth across an uncertified wall.
	var compact: Array[Vector2] = []
	for p in result:
		if compact.size() >= 2:
			var a := compact[-1]-compact[-2]
			var b := p-compact[-1]
			if absf(a.cross(b)) < 0.00001 and a.dot(b) > 0:
				compact.pop_back()
		compact.append(p)
	return compact
