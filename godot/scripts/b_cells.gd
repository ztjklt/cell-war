class_name WarBCells
extends RefCounted
## A non-attacking support cell. Stationary flower shaking doubles nearby allies' attack rate.
var game: WarSimulation
var _sources: Array = []

func _init(owner: WarSimulation) -> void:
	game = owner

static func data() -> Dictionary:
	return WarData.read("b_cell")

static func can_emit(e: Dictionary) -> bool:
	if e.get("kind","") != "b_cell" or e.get("category","") != "unit" or float(e.get("hp",0)) <= 0 or e.get("returning",false): return false
	if float(e.get("travelSpeed",0)) > .01 or WarData.point(e).distance_squared_to(Vector2(e.get("previousX",e.x),e.get("previousY",e.y))) > .000001: return false
	var orders: Array = e.get("orders",[])
	if orders.is_empty() or orders[0].get("kind","") in ["hold","stop"]: return true
	return orders[0].get("kind","") == "guard" and WarData.point(e).distance_to(WarData.point(orders[0])) <= .1

func refresh() -> void:
	_sources = game.units().filter(func(e): return can_emit(e))

func speed_multiplier(target: Dictionary) -> float:
	if float(target.get("hp",0)) <= 0 or target.get("category","") != "unit" or float(WarData.spec(target.kind).get("damage",0)) <= 0: return 1.0
	var aura: Dictionary = data().aura
	for source in _sources:
		if not can_emit(source) or source.id == target.id or source.faction != target.faction: continue
		var lane := int(source.get("vesselLane",0))
		if lane != int(target.get("vesselLane",0)): continue
		var a := WarData.point(source)
		var b := WarData.point(target)
		if a.distance_squared_to(b) > float(aura.radius)*float(aura.radius)+.000001: continue
		if game.navigation.clear_segment(a,b,lane,target.kind) and game.navigation.movement_clear(a,b,target.kind,int(target.faction)):
			return float(aura.attackSpeedMultiplier) # Multiple B cells refresh coverage, never multiply it again.
	return 1.0

static func sample(e: Dictionary,time: float,moving: float,dead: bool) -> Dictionary:
	var clips: Dictionary = data().clips
	var key := "bBuff"
	var elapsed := time+int(e.id)*.071
	var loop := true
	if dead or e.has("deathTime"):
		key = "bDeath"; loop = false
		elapsed = maxf(0,time-float(e.get("deathTime",e.get("died",time))))
		if elapsed >= float(clips[key].duration): return {"hidden":true,"key":key,"frame":clips[key].durations.size()-1}
	elif moving > .02:
		key = "bMove"
	elif not can_emit(e):
		key = "bMove"; elapsed = 0.0; loop = false
	var clip: Dictionary = clips[key]
	var t := fmod(maxf(0,elapsed),float(clip.duration)) if loop else maxf(0,elapsed)
	var frame: int = clip.durations.size()-1
	var end := 0.0
	for i in clip.durations.size():
		end += float(clip.durations[i])
		if t < end-.000001: frame = i; break
	return {"key":key,"clip":clip,"frame":frame,"family":"b_cell"}
