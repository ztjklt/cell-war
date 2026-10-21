class_name WarBloodFlow
extends RefCounted
## Blue returns to the heart; red leaves it. Crossings never connect lanes.
const DOWNSTREAM := 3.0
const UPSTREAM := 1.0 / 2.5
const BUCKET_SIZE := 16.0
var lanes: Dictionary = {}

func _init(data: Dictionary) -> void:
	var cardiac: Dictionary = {}
	for lane in data.lanes:
		if lane.system in ["chamber","valve"]:
			cardiac[int(lane.a)] = true
			cardiac[int(lane.b)] = true
	for system in ["artery","vein"]:
		var graph: Dictionary = {}
		var distances: Dictionary = {}
		var open: Dictionary = {}
		for lane in data.lanes:
			if lane.system != system: continue
			var points := PackedVector2Array()
			var length := 0.0
			for point in lane.points:
				var p := WarData.point(point)
				if not points.is_empty(): length += points[-1].distance_to(p)
				points.append(p)
			var a := int(lane.a)
			var b := int(lane.b)
			for pair in [[a,b],[b,a]]:
				if not graph.has(pair[0]): graph[pair[0]] = []
				graph[pair[0]].append({"node":pair[1],"length":length})
				if cardiac.has(pair[0]): distances[pair[0]] = 0.0; open[pair[0]] = true
			var blue: bool = lane.get("oxygen","") == "low" or (lane.get("oxygen","") != "high" and system == "vein")
			var buckets: Dictionary = {}
			for i in range(1,points.size()):
				var box := Rect2(points[i-1],Vector2.ZERO).expand(points[i]).grow(float(lane.width)*.5+2)
				var first := Vector2i((box.position/BUCKET_SIZE).floor())
				var last := Vector2i((box.end/BUCKET_SIZE).floor())
				for y in range(first.y,last.y+1):
					for x in range(first.x,last.x+1):
						var key := Vector2i(x,y)
						if not buckets.has(key): buckets[key] = []
						buckets[key].append(i)
			lanes[int(lane.lane)] = {"points":points,"blue":blue,"sign":1.0,"buckets":buckets}
		# Same-system distances prevent a nearby return vessel from becoming an
		# arterial shortcut through the capillaries at a finger or organ bed.
		while not open.is_empty():
			var node := -1
			var nearest := INF
			for key in open:
				if distances[key] < nearest: node = key; nearest = distances[key]
			open.erase(node)
			for link in graph.get(node,[]):
				var candidate: float = nearest + link.length
				if candidate < float(distances.get(link.node,INF)):
					distances[link.node] = candidate
					open[link.node] = true
		for lane in data.lanes:
			if lane.system != system: continue
			# Isolated service/portal fragments retain their authored a-to-b order.
			var sign := 1.0
			var a: float = distances.get(int(lane.a),INF)
			var b: float = distances.get(int(lane.b),INF)
			if is_finite(a) and is_finite(b) and not is_equal_approx(a,b):
				sign = (1.0 if a < b else -1.0) if system == "artery" else (1.0 if a > b else -1.0)
			var entry: Dictionary = lanes[int(lane.lane)]
			# Pulmonary tube names describe anatomy; the user's rule follows color.
			if bool(entry.blue) != (system == "vein"): sign *= -1.0
			entry.sign = sign

func direction(lane: int, position: Vector2) -> Vector2:
	if not lanes.has(lane): return Vector2.ZERO
	var entry: Dictionary = lanes[lane]
	var points: PackedVector2Array = entry.points
	var nearest := INF
	var tangent := Vector2.ZERO
	var candidates: Array = entry.buckets.get(Vector2i((position/BUCKET_SIZE).floor()),[])
	for i: int in candidates:
		var delta := points[i]-points[i-1]
		if delta.length_squared() < .00000001: continue
		var closest := Geometry2D.get_closest_point_to_segment(position,points[i-1],points[i])
		var distance := position.distance_squared_to(closest)
		if distance < nearest:
			nearest = distance
			tangent = delta.normalized()*float(entry.sign)
	return tangent

func multiplier(lane: int, position: Vector2, movement: Vector2) -> float:
	# At an exact bend vertex, sample just ahead to choose the segment being
	# entered instead of tying with the segment the cell has already left.
	var heading := movement.normalized()
	var alignment := direction(lane,position+heading*.001).dot(heading)
	if alignment > .0001: return DOWNSTREAM
	if alignment < -.0001: return UPSTREAM
	return 1.0
