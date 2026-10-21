class_name WarCellShape
extends RefCounted
## CellSilhouette.lua: original alpha contours and standing convex contact hulls.

static func pose(e: Dictionary,time: float,contact: bool) -> Dictionary:
	var angle := 0.0
	var mirror := false
	var pulse := 1.0
	if e.kind == WarTCellRuntime.KIND:
		mirror = cos(float(e.get("moveHeading",PI)) if float(e.get("travelSpeed",0))>.02 else float(e.get("weaponHeading",e.get("moveHeading",PI)))) > 0
	elif e.kind == WarMedicineHelpers.KIND:
		mirror = cos(float(e.get("weaponHeading",e.get("moveHeading",PI)))) > 0
	elif e.kind in ["scout","b_cell","dendritic_cell"]:
		pass # Platelet hands and trapezoid stay upright while walking or holding a wall.
	elif e.kind in ["spear","neutrophil"]:
		angle = float(e.get("weaponHeading",e.get("moveHeading",PI)))
		mirror = cos(angle) > 0
		if not mirror: angle -= PI
	elif e.kind == "worker":
		mirror = cos(float(e.get("moveHeading",e.get("weaponHeading",PI) if contact else PI))) > 0
	else:
		angle = float(e.get("weaponHeading",e.get("moveHeading",0)))+time*.16+int(e.id)*.37
		if not contact: pulse = .985+.015*sin((time+int(e.id)*.73)*TAU/3.2)
	if e.kind == "virus":
		# Keep the original standing contact hull; the new facing sprite does not spin.
		angle = time*.3+int(e.id)*.71 if contact else 0.0
		mirror = false if contact else cos(float(e.get("weaponHeading",e.get("moveHeading",0)))) < 0
		pulse = 1
	return {"angle":angle,"mirror":mirror,"pulse":pulse}

static func normalized(e: Dictionary,key: String,frame: int,field: String) -> PackedVector2Array:
	var points := PackedVector2Array()
	if e.kind == WarTCellRuntime.KIND: return WarTCellRuntime.normalized(key,frame,field)
	if e.kind == WarMedicineHelpers.KIND:
		var data: Dictionary = WarMedicineHelpers.data()
		var source: Array = data.hull if field == "hull" else data.outlines.get(key,data.outlines.move)[clampi(frame,0,15)]
		for p in source: points.append(Vector2(p[0],p[1]))
		return points
	if e.kind == "dendritic_cell":
		var data: Dictionary = WarDendriticCells.data()
		var outlines: Array = data.outlines.get(key,data.outlines.dcScan)
		var source: Array = data.hull if field == "hull" else outlines[clampi(frame,0,outlines.size()-1)]
		for p in source: points.append(Vector2(p[0],p[1]))
		return points
	if e.kind == "b_cell":
		var data: Dictionary = WarBCells.data()
		var source: Array = data.hull if field == "hull" else data.outlines.get(key,data.outlines.bBuff)[clampi(frame,0,data.outlines.get(key,data.outlines.bBuff).size()-1)]
		for p in source: points.append(Vector2(p[0],p[1]))
		return points
	if e.kind == "scout":
		var data: Dictionary = WarPlatelets.data()
		var source: Array = data.hull if field == "hull" else data.outlines.get(key,data.outlines.plateletDefend)[clampi(frame,0,data.outlines.get(key,data.outlines.plateletDefend).size()-1)]
		for p in source: points.append(Vector2(p[0],p[1]))
		return points
	if e.kind == "virus" and key.begins_with("flu") and field == "outline":
		for p in WarInfluenzaAnimation.data().outlines[key][clampi(frame,0,19)]: points.append(Vector2(p[0],p[1]))
		return points
	if e.kind == "virus":
		for i in range(1,21):
			if field == "hull" and i%2 != 0: continue
			points.append(Vector2.from_angle(i*PI/10)*(.99 if i%2 == 0 else .72))
		return points
	var data: Dictionary = WarData.read("cell_silhouettes")
	if key.is_empty():
		if e.kind == "worker": key = "redWalk"
		elif e.kind in ["spear","neutrophil"]: key = "whiteMove"
		else: key = "legacy_"+str(WarData.config().CellFrames.kinds.get(e.kind,"red"))
	for p in data[key][mini(frame,data[key].size()-1)][field]: points.append(Vector2(p[0],p[1]))
	return points

static func hull(e: Dictionary,p: Vector2 = Vector2(INF,INF)) -> PackedVector2Array:
	if not is_finite(p.x): p = WarData.point(e)
	var result := PackedVector2Array()
	var rotation := pose(e,0,true)
	for point in normalized(e,"",0,"hull"):
		if rotation.mirror: point.x = -point.x
		result.append(p+point.rotated(rotation.angle)*WarData.radius(e.kind))
	return result

static func _axes(a: PackedVector2Array,b: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for points in [a,b]:
		var last: Vector2 = points[-1]
		for point in points:
			var axis := Vector2(-(point.y-last.y),point.x-last.x)
			if axis.length_squared() > 1e-20: out.append(axis.normalized())
			last = point
	return out

static func _project(points: PackedVector2Array,axis: Vector2) -> Vector2:
	var low := INF
	var high := -INF
	for point in points:
		var d := point.dot(axis)
		low = minf(low,d); high = maxf(high,d)
	return Vector2(low,high)

static func contact(a: Dictionary,b: Dictionary,ap := Vector2(INF,INF),bp := Vector2(INF,INF),padding := 0.0) -> Array:
	if not is_finite(ap.x): ap = WarData.point(a)
	if not is_finite(bp.x): bp = WarData.point(b)
	var radius := WarData.radius(a.kind)+WarData.radius(b.kind)+padding
	if ap.distance_squared_to(bp) > radius*radius: return []
	var pa := hull(a,ap)
	var pb := hull(b,bp)
	var depth := INF
	var normal := Vector2.ZERO
	for axis in _axes(pa,pb):
		var al := _project(pa,axis)
		var bl := _project(pb,axis)
		if al.y+padding <= bl.x or bl.y+padding <= al.x: return []
		var positive := bl.y-al.x+padding
		var negative := al.y-bl.x+padding
		var d := minf(positive,negative)
		if d < depth: depth = d; normal = axis*(1 if positive < negative else -1)
	return [depth,normal]

static func sweep(a: Dictionary,b: Dictionary,p: Vector2,delta: Vector2,padding := 0.0) -> Array:
	var pa := hull(a,p)
	var pb := hull(b)
	var enter := -INF
	var leave := INF
	var normal := Vector2.ZERO
	for axis in _axes(pa,pb):
		var al := _project(pa,axis)
		var bl := _project(pb,axis)
		var speed := delta.dot(axis)
		if absf(speed) < 1e-10:
			if al.y+padding < bl.x or bl.y+padding < al.x: return []
		else:
			var low := (bl.x-padding-al.y)/speed
			var high := (bl.y+padding-al.x)/speed
			if low > high: var swap := low; low = high; high = swap
			if low > enter: enter = low; normal = axis*(-1 if speed > 0 else 1)
			leave = minf(leave,high)
			if enter > leave: return []
	if leave < 0 or enter > 1: return []
	if enter < -1e-10:
		var overlapping := contact(a,b,p,Vector2(INF,INF),padding)
		if overlapping.is_empty() or delta.dot(overlapping[1]) >= 0: return []
		normal = overlapping[1]
	return [maxf(0,enter),normal]
