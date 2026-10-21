class_name WarPlatelets
extends RefCounted
## Stationary platelets automatically make unbranched left/right defensive lines.
var game: WarSimulation
const SPACING := 2.65
const ATTACH := 3.25
const RELEASE := 3.8

func _init(owner: WarSimulation) -> void:
	game = owner

static func is_platelet(e: Dictionary) -> bool:
	return e.get("kind","") == "scout" and e.get("category","") == "unit"

static func defending(e: Dictionary) -> bool:
	if not is_platelet(e) or float(e.get("hp",0)) <= 0: return false
	var orders: Array = e.get("orders",[])
	return (orders.is_empty() or orders[0].get("kind","") in ["hold","stop"]) and float(e.get("travelSpeed",0)) <= .01

static func push_scale(e: Dictionary) -> float:
	if not is_platelet(e): return 1.0
	if not defending(e): return .45
	return .05 if not e.get("plateletLinks",[]).is_empty() else .22

func detach(e: Dictionary) -> void:
	for id in e.get("plateletLinks",[]):
		var other := game.entity(int(id))
		if not other.is_empty():
			var remaining: Array = other.get("plateletLinks",[]).duplicate()
			remaining.erase(int(e.id))
			other.plateletLinks = remaining
	e.plateletLinks = []
	e.erase("plateletLinkStarted")

func compatible(a: Dictionary,b: Dictionary,limit: float) -> bool:
	if not defending(a) or not defending(b) or a.faction != b.faction: return false
	var lane := int(a.get("vesselLane",0))
	if lane != int(b.get("vesselLane",0)): return false
	var delta := WarData.point(b)-WarData.point(a)
	var radius := WarData.radius("scout")
	if absf(delta.y) > radius*.65 or absf(delta.x) < radius*1.5 or delta.length() > radius*limit: return false
	return game.navigation.clear_segment(WarData.point(a),WarData.point(b),lane,"scout") and game.navigation.movement_clear(WarData.point(a),WarData.point(b),"scout",int(a.faction))

func _side_free(e: Dictionary,other: Dictionary,links: Dictionary) -> bool:
	var right := float(other.x) > float(e.x)
	for id in links[int(e.id)]:
		if (float(game.entity(int(id)).x) > float(e.x)) == right: return false
	return true

func update() -> void:
	var list := game.units().filter(func(e): return is_platelet(e))
	list.sort_custom(func(a,b): return int(a.id)<int(b.id))
	var links: Dictionary = {}
	for e in list: links[int(e.id)] = []
	var candidates: Array = []
	for i in list.size():
		for j in range(i+1,list.size()):
			var a: Dictionary = list[i]
			var b: Dictionary = list[j]
			var existing: bool = a.get("plateletLinks",[]).has(int(b.id)) and b.get("plateletLinks",[]).has(int(a.id))
			if compatible(a,b,RELEASE if existing else ATTACH):
				candidates.append({"a":a,"b":b,"distance":WarData.point(a).distance_squared_to(WarData.point(b)),"existing":existing})
	candidates.sort_custom(func(a,b):
		if a.existing != b.existing: return a.existing
		if not is_equal_approx(a.distance,b.distance): return a.distance<b.distance
		return int(a.a.id)<int(b.a.id) if a.a.id != b.a.id else int(a.b.id)<int(b.b.id))
	for edge in candidates:
		var a: Dictionary = edge.a
		var b: Dictionary = edge.b
		if not _side_free(a,b,links) or not _side_free(b,a,links): continue
		links[int(a.id)].append(int(b.id))
		links[int(b.id)].append(int(a.id))
	for e in list:
		var next: Array = links[int(e.id)]
		if not next.is_empty() and e.get("plateletLinks",[]).is_empty(): e.plateletLinkStarted = game.state.time
		e.plateletLinks = next
		if next.is_empty(): e.erase("plateletLinkStarted")
		if defending(e): e.combatState = "defend"

func formation(troops: Array,target: Vector2,lane: int) -> Dictionary:
	if troops.is_empty() or not troops.all(func(e): return is_platelet(e)): return {}
	var list := troops.duplicate()
	list.sort_custom(func(a,b): return float(a.x)<float(b.x) if not is_equal_approx(a.x,b.x) else int(a.id)<int(b.id))
	var spacing := WarData.radius("scout")*SPACING
	if list.size() == 1:
		var best := INF
		var snapped := target
		for other in game.units():
			if not defending(other) or other.id == list[0].id or other.faction != list[0].faction or int(other.get("vesselLane",0)) != lane: continue
			for sign_x in [-1,1]:
				var occupied := false
				for id in other.get("plateletLinks",[]):
					var neighbor := game.entity(int(id))
					if not neighbor.is_empty() and (neighbor.x>other.x) == (sign_x>0): occupied = true
				if occupied: continue
				var p := WarData.point(other)+Vector2(sign_x*spacing,0)
				var distance := p.distance_squared_to(target)
				if distance < best and distance < spacing*spacing*1.5 and game.navigation.point_allowed(p,lane,"scout") and game._position_free(list[0],p) and game.navigation.clear_segment(WarData.point(other),p,lane,"scout"):
					best = distance; snapped = p
		target = snapped
	var result: Dictionary = {}
	var previous := Vector2(INF,INF)
	for i in list.size():
		var p := target+Vector2((i-(list.size()-1)*.5)*spacing,0)
		if not game.navigation.point_allowed(p,lane,"scout"): return {}
		if not game.navigation.movement_clear(p,p,"scout",int(list[i].faction)): return {}
		if is_finite(previous.x) and (not game.navigation.clear_segment(previous,p,lane,"scout") or not game.navigation.movement_clear(previous,p,"scout",int(list[i].faction))): return {}
		for other in game.units():
			if list.has(other) or int(other.get("vesselLane",0)) != lane: continue
			if not WarCellShape.contact(list[i],other,p).is_empty(): return {}
		result[int(list[i].id)] = {"x":p.x,"y":p.y,"lane":lane}
		previous = p
	return result

static func data() -> Dictionary:
	return WarData.read("platelet")

static func sample(e: Dictionary,time: float,moving: float,dead: bool) -> Dictionary:
	var clips: Dictionary = data().clips
	var key := "plateletDefend"
	var elapsed := time+int(e.id)*.071
	var loop := true
	if dead or e.has("deathTime"):
		key = "plateletDeath"; loop = false
		elapsed = maxf(0,time-float(e.get("deathTime",e.get("died",time))))
		if elapsed >= float(clips[key].duration): return {"hidden":true,"key":key,"frame":11}
	else:
		var hit := float(e.get("cellHitStarted",-100))
		var connected := float(e.get("plateletLinkStarted",-100))
		if time >= hit and time-hit < float(clips.plateletHit.duration):
			key = "plateletHit"; elapsed = time-hit; loop = false
		elif moving > .02:
			key = "plateletMove"
		elif time >= connected and time-connected < float(clips.plateletConnect.duration):
			key = "plateletConnect"; elapsed = time-connected; loop = false
	var clip: Dictionary = clips[key]
	var t := fmod(maxf(0,elapsed),float(clip.duration)) if loop else maxf(0,elapsed)
	var end := 0.0
	var frame: int = clip.durations.size()-1
	for i in clip.durations.size():
		end += float(clip.durations[i])
		if t < end-.000001: frame = i; break
	return {"key":key,"clip":clip,"frame":frame,"family":"platelet"}
