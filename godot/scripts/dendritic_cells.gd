class_name WarDendriticCells
extends RefCounted
## Stationary reconnaissance reveals precise enemy positions and slows both rates.
var game: WarSimulation
var _sources: Array = []

func _init(owner: WarSimulation) -> void:
	game = owner

static func data() -> Dictionary:
	return WarData.read("dendritic_cell")

static func concealed(e: Dictionary) -> bool:
	return bool(e.get("burrowed",false)) or bool(e.get("concealed",false))

static func can_scan(e: Dictionary,time := INF) -> bool:
	if e.get("kind","") != "dendritic_cell" or e.get("category","") != "unit" or float(e.get("hp",0)) <= 0 or e.get("returning",false): return false
	if float(e.get("travelSpeed",0)) > .01 or WarData.point(e).distance_squared_to(Vector2(e.get("previousX",e.x),e.get("previousY",e.y))) > .000001: return false
	if e.has("cellHitStarted") and time < float(e.cellHitStarted)+float(data().clips.dcHit.duration): return false
	var orders: Array = e.get("orders",[])
	if orders.is_empty() or orders[0].get("kind","") in ["hold","stop"]: return true
	return orders[0].get("kind","") == "guard" and WarData.point(e).distance_to(WarData.point(orders[0])) <= .1

func refresh() -> void:
	_sources = game.units().filter(func(e): return can_scan(e,float(game.state.time)))

func covers(source: Dictionary,target: Dictionary) -> bool:
	if not can_scan(source,float(game.state.time)) or float(target.get("hp",0)) <= 0 or target.get("category","") != "unit" or int(source.faction) == int(target.faction): return false
	var lane := int(source.get("vesselLane",0))
	if lane != int(target.get("vesselLane",0)): return false
	var a := WarData.point(source)
	var b := WarData.point(target)
	var radius := float(data().scan.radius)
	return a.distance_squared_to(b) <= radius*radius+.000001 and game.navigation.clear_segment(a,b,lane,source.kind) and game.navigation.movement_clear(a,b,source.kind,int(source.faction))

func marked(target: Dictionary,faction := -1) -> bool:
	for source in _sources:
		if faction >= 0 and int(source.faction) != faction: continue
		if covers(source,target): return true
	return false

func multiplier(target: Dictionary,field: String) -> float:
	if field not in ["moveMultiplier","attackSpeedMultiplier"] or not marked(target): return 1.0
	return float(data().scan[field]) # Multiple scanners never multiply the penalty again.

func marked_count(source: Dictionary) -> int:
	var count := 0
	for target in game.units():
		if covers(source,target): count += 1
	return count

static func sample(e: Dictionary,time: float,moving: float,dead: bool) -> Dictionary:
	var clips: Dictionary = data().clips
	var key := "dcScan"
	var elapsed := time+int(e.id)*.071
	var loop := true
	if dead or e.has("deathTime"):
		key = "dcDeath"; loop = false
		elapsed = maxf(0,time-float(e.get("deathTime",e.get("died",time))))
		if elapsed >= float(clips[key].duration): return {"hidden":true,"key":key,"frame":clips[key].durations.size()-1}
	elif e.has("cellHitStarted") and time-float(e.cellHitStarted) < float(clips.dcHit.duration):
		key = "dcHit"; loop = false; elapsed = maxf(0,time-float(e.cellHitStarted))
	elif moving > .02:
		key = "dcMove"
	elif not can_scan(e,time):
		key = "dcMove"; elapsed = 0; loop = false
	var clip: Dictionary = clips[key]
	var t := fmod(maxf(0,elapsed),float(clip.duration)) if loop else maxf(0,elapsed)
	var frame: int = clip.durations.size()-1
	var end := 0.0
	for i in clip.durations.size():
		end += float(clip.durations[i])
		if t < end-.000001: frame = i; break
	return {"key":key,"clip":clip,"frame":frame,"family":"dendritic_cell"}
