class_name WarAdenovirusAttack
extends RefCounted
## Independent opt-in simulation service. Never spawns actors or edits public combat.
## Host must freeze the caster during a cast and supply authoritative world callbacks.
const SCHEMA := "cell-war-adenovirus/v1"
const MAX_ID := 2147483647
const MAX_SOURCES := 4096
const EPS := 0.000000001
var _rules: Dictionary = {}
var _clock := 0.0
var _next_id := 1
var _sources: Dictionary = {}
var _events: Array = []
var _damage := Callable()
var _geometry := Callable()
var _knockback := Callable()
var _advancing := false
var _error := ""

func _init() -> void:
	var definition = JSON.parse_string(FileAccess.get_file_as_string("res://data/adenovirus.json"))
	if definition is Dictionary: _rules = definition.get("rules", {}).duplicate(true)

## Required callbacks (all three):
## geometry(from, to, lane, source, target, purpose) -> strictly bool true.
##   purpose: cast/impact/target/push; target may be empty. Must check holes, walls,
##   unopened gates and authoritative layer connectivity, including same-point queries.
## damage(source, target, amount, info) -> void. Suggested cause: adenovirus_slam;
##   the public combat adapter must avoid its ordinary automatic knockback.
## knockback(source, target, displacement, info) -> void. Respect occupancy and
##   target resistance; displacement is already clipped against geometry in .05 steps.
## Callbacks run inside an atomic simulation step. Saving/restoring/reentering the
## service from any callback is rejected. Callback dictionaries are live actors.
func bind_world(damage_callback: Callable, geometry_callback: Callable, knockback_callback: Callable) -> void:
	if _advancing: return
	_damage = damage_callback; _geometry = geometry_callback; _knockback = knockback_callback

func last_error() -> String:
	return _error

func clock() -> float:
	return _clock

func tuning() -> Dictionary:
	return _rules.duplicate(true)

func _bound() -> bool:
	return _damage.is_valid() and _geometry.is_valid() and _knockback.is_valid()

func _record_for(id: int) -> Dictionary:
	return _sources.get(str(id), {"lastSequence":0, "readyAt":0.0,
		"hitAt":-1.0, "hitSide":"right", "deathAt":-1.0, "cast":{}})

## aim is a real simulation coordinate, fixed at windup. The caster does not teleport.
## Initial castReach=radius (2.4); host approaches before calling. One monotonic
## sequence per actor; IDs must never be reused within a session/save.
func begin(source: Dictionary, aim: Vector2, sequence: int) -> int:
	_error = ""
	if _advancing: _error = "reentrant_call"; return 0
	if not _bound(): _error = "callbacks_required"; return 0
	if not _actor(source) or source.kind != "adenovirus" or source.category != "unit" or source.hp <= 0 or not aim.is_finite():
		_error = "invalid_source_or_aim"; return 0
	if not _integer(sequence, 1, MAX_ID): _error = "invalid_sequence"; return 0
	var key := str(int(source.id))
	var record := _record_for(int(source.id))
	if sequence <= int(record.lastSequence): _error = "duplicate_sequence"; return 0
	if float(record.deathAt) >= 0 or _hit_active(record) or not record.cast.is_empty():
		_error = "busy"; return 0
	if _clock + EPS < float(record.readyAt): _error = "cooldown"; return 0
	if (_sources.size() >= MAX_SOURCES and not _sources.has(key)) or _next_id > MAX_ID:
		_error = "capacity"; return 0
	var origin := _point(source)
	if origin.distance_to(aim) > float(_rules.castReach) + EPS: _error = "out_of_range"; return 0
	# Also guard the preflight callback against save/reentrant begin.
	_advancing = true
	var clear := _clear(origin, aim, int(source.vesselLane), source, {}, "cast")
	_advancing = false
	if not clear: _error = "blocked"; return 0
	var cast := {"id":_next_id, "born":_clock, "origin":[origin.x,origin.y],
		"aim":[aim.x,aim.y], "lane":int(source.vesselLane), "faction":int(source.faction),
		"orderToken":int(source.get("orderToken",0)), "hitTime":float(source.get("hitTime",-1)), "resolved":false}
	record.cast = cast; record.lastSequence = sequence; record.readyAt = _clock + float(_rules.cooldown)
	_sources[key] = record; _next_id += 1
	_event("windup", int(source.id), cast)
	return int(cast.id)

func cancel(source_id: int, reason := "cancelled") -> void:
	if _advancing: return
	_cancel(source_id, reason)

func _cancel(source_id: int, reason: String) -> void:
	var record := _record_for(source_id)
	if record.cast.is_empty(): return
	_event(reason, source_id, record.cast)
	record.cast = {}
	_sources[str(source_id)] = record

## Direction is projected locally by the host: victim -> attacker. Repeated hits
## during one reaction do not change its side or restart it. Call after actual damage.
func notify_hit(source: Dictionary, toward_attacker: Vector2) -> bool:
	if not _actor(source) or source.kind != "adenovirus" or not toward_attacker.is_finite(): return false
	if source.hp <= 0: return notify_death(source)
	var key := str(int(source.id))
	if not _sources.has(key) and _sources.size() >= MAX_SOURCES: return false
	_cancel(int(source.id), "hit_cancelled")
	var record := _record_for(int(source.id))
	if float(record.deathAt) >= 0: return false
	if not _hit_active(record):
		record.hitAt = _clock
		if absf(toward_attacker.x) > EPS: record.hitSide = "right" if toward_attacker.x > 0 else "left"
	_sources[key] = record
	return true

func notify_death(source: Dictionary) -> bool:
	if not _actor(source) or source.kind != "adenovirus" or source.hp > 0: return false
	return _death(int(source.id))

func _death(source_id: int) -> bool:
	if not _sources.has(str(source_id)) and _sources.size() >= MAX_SOURCES: return false
	_cancel(source_id, "death_cancelled")
	var record := _record_for(source_id)
	if float(record.deathAt) < 0: record.deathAt = _clock
	_sources[str(source_id)] = record
	return true

func advance(real_delta: float, entities: Array, paused := false, time_scale := 1.0) -> bool:
	if not _number(real_delta) or real_delta < 0 or not _number(time_scale) or time_scale < 0: return false
	if paused or time_scale == 0: return true
	return advance_simulation(real_delta * time_scale, entities)

func advance_simulation(delta: float, entities: Array) -> bool:
	if _advancing: _error = "reentrant_call"; return false
	if not _number(delta) or delta < 0 or not is_finite(_clock + delta): _error = "invalid_delta"; return false
	var world: Dictionary = {}
	for actor in entities:
		if not actor is Dictionary or not _actor(actor): continue
		var key := str(int(actor.id))
		if world.has(key): _error = "duplicate_entity_id"; return false
		world[key] = actor
	for record in _sources.values():
		if not record.cast.is_empty() and not _bound(): _error = "callbacks_required"; return false
	_advancing = true
	_clock += delta
	var keys := _sources.keys(); keys.sort()
	for key in keys:
		var record: Dictionary = _sources[key]
		var cast: Dictionary = record.cast
		if cast.is_empty(): continue
		var source: Dictionary = world.get(key, {})
		if source.is_empty() or source.kind != "adenovirus": _cancel(int(key), "source_missing"); continue
		if source.hp <= 0: _death(int(key)); continue
		if int(source.get("orderToken",0)) != int(cast.orderToken) or int(source.vesselLane) != int(cast.lane) or int(source.faction) != int(cast.faction) or _point(source).distance_to(_vector(cast.origin)) > EPS:
			_cancel(int(key), "source_changed"); continue
		if float(source.get("hitTime",-1)) > float(cast.hitTime):
			_cancel(int(key), "hit_cancelled"); continue
		if not cast.resolved and _clock + EPS >= float(cast.born) + float(_rules.impactDelay):
			# Commit once before any external side effects. Restore refuses unresolved past impacts.
			cast.resolved = true
			_resolve(source, cast, world)
		if _clock + EPS >= float(cast.born) + float(_rules.recoveryEnd): record.cast = {}
	_advancing = false
	_error = ""
	return true

func _resolve(source: Dictionary, cast: Dictionary, world: Dictionary) -> void:
	var aim := _vector(cast.aim)
	var lane := int(cast.lane)
	if not _clear(_vector(cast.origin), aim, lane, source, {}, "impact"):
		_event("impact_blocked", int(source.id), cast); return
	var targets := world.values()
	targets.sort_custom(func(a: Dictionary,b: Dictionary): return int(a.id) < int(b.id))
	var eligible: Array = []
	# Sample the complete blast before damage callbacks can breach a gate or move
	# another actor. A gate destroyed by this impact still occludes this same impact.
	for target in targets:
		if target.hp <= 0 or int(target.id) == int(source.id) or int(target.faction) == int(cast.faction) or int(target.vesselLane) != lane: continue
		if _point(target).distance_to(aim) > float(_rules.radius) + EPS: continue
		if not _clear(aim, _point(target), lane, source, target, "target"): continue
		eligible.append(target)
	var hit_ids: Array = []
	for target in eligible:
		if target.hp <= 0 or int(target.faction) == int(cast.faction) or int(target.vesselLane) != lane: continue
		var info := {"cause":"adenovirus_slam", "castId":int(cast.id), "point":cast.aim.duplicate(),
			"lane":lane, "impactAt":float(cast.born)+float(_rules.impactDelay)}
		_damage.call(source, target, float(_rules.damage), info.duplicate(true))
		hit_ids.append(int(target.id))
		if not _actor(target) or target.category != "unit" or target.hp <= 0 or int(target.vesselLane) != lane: continue
		var start := _point(target)
		var direction := start - aim
		if direction.is_zero_approx(): direction = Vector2.RIGHT
		direction = direction.normalized()
		var end := start
		var distance := 0.0
		while distance < float(_rules.knockback) - EPS:
			var next_distance := minf(distance + .05, float(_rules.knockback))
			var point := start + direction * next_distance
			if not _clear(end, point, lane, source, target, "push"): break
			end = point; distance = next_distance
		if end.distance_to(start) > EPS: _knockback.call(source, target, end-start, info.duplicate(true))
	_event("impact", int(source.id), cast, hit_ids)

func _clear(a: Vector2, b: Vector2, lane: int, source: Dictionary, target: Dictionary, purpose: String) -> bool:
	if not _geometry.is_valid(): return false
	var result = _geometry.call(a,b,lane,source,target,purpose)
	return result is bool and result

func _hit_active(record: Dictionary) -> bool:
	return float(record.hitAt) >= 0 and _clock < float(record.hitAt) + float(_rules.hitDuration) - EPS

## Simulation-owned presentation only. Calling this or sampling animation never deals damage.
func presentation(source_id: int) -> Dictionary:
	var record := _record_for(source_id)
	var result := {"clock":_clock, "pose":"idle", "elapsed":0.0, "hitSide":record.hitSide,
		"cast":record.cast.duplicate(true), "warning":{"visible":false}}
	if float(record.deathAt) >= 0:
		result.pose = "death"; result.elapsed = _clock-float(record.deathAt)
	elif _hit_active(record):
		result.pose = "hit-"+str(record.hitSide); result.elapsed = _clock-float(record.hitAt)
	elif not record.cast.is_empty():
		result.pose = "slam"; result.elapsed = _clock-float(record.cast.born)
		result.warning = {"visible":not record.cast.resolved, "point":record.cast.aim.duplicate(),
			"lane":record.cast.lane, "radius":_rules.radius,
			"remaining":maxf(0.0,float(_rules.impactDelay)-float(result.elapsed))}
	return result

func _event(type: String, source_id: int, cast: Dictionary, hits: Array = []) -> void:
	_events.append({"type":type, "sourceId":source_id, "castId":cast.id, "clock":_clock, "hits":hits})
	if _events.size() > 256: _events.pop_front()

func drain_events() -> Array:
	if _advancing: return []
	var result := _events.duplicate(true); _events.clear(); return result

func snapshot() -> Dictionary:
	if _advancing: _error = "atomic_step_in_progress"; return {}
	return {"schema":SCHEMA, "clock":_clock, "nextCastId":_next_id,
		"rules":_rules.duplicate(true), "sources":_sources.duplicate(true)}

## Transactional, JSON-safe restore. No callback, damage or event is fired by loading.
## Host must restore actor positions/layers/order tokens from the SAME atomic save.
func restore(data: Dictionary) -> bool:
	if _advancing: _error = "atomic_step_in_progress"; return false
	if not _valid_snapshot(data): _error = "invalid_snapshot"; return false
	_clock = float(data.clock); _next_id = int(data.nextCastId)
	_sources = data.sources.duplicate(true); _events.clear(); _error = ""
	return true

func _valid_snapshot(data: Dictionary) -> bool:
	if not _keys(data,["schema","clock","nextCastId","rules","sources"]): return false
	if data.get("schema") != SCHEMA or not _number(data.get("clock")) or float(data.clock) < 0: return false
	if not _integer(data.get("nextCastId"),1,MAX_ID+1) or not data.get("rules") is Dictionary or data.rules != _rules: return false
	if not data.get("sources") is Dictionary or data.sources.size() > MAX_SOURCES: return false
	var cast_ids: Dictionary = {}
	for key in data.sources:
		if not key is String or not key.is_valid_int() or str(int(key)) != key or not _integer(int(key),1,MAX_ID): return false
		var r = data.sources[key]
		if not r is Dictionary or not _integer(r.get("lastSequence"),0,MAX_ID): return false
		if not _keys(r,["lastSequence","readyAt","hitAt","hitSide","deathAt","cast"]): return false
		if not _number(r.get("readyAt")) or float(r.readyAt) < 0 or float(r.readyAt) > float(data.clock)+float(_rules.cooldown)+EPS: return false
		for field in ["hitAt","deathAt"]:
			if not _number(r.get(field)) or (float(r[field]) != -1 and (float(r[field]) < 0 or float(r[field]) > float(data.clock))): return false
		if r.get("hitSide") not in ["left","right"] or not r.get("cast") is Dictionary: return false
		var c: Dictionary = r.cast
		if c.is_empty(): continue
		if not _keys(c,["id","born","origin","aim","lane","faction","orderToken","hitTime","resolved"]): return false
		if r.lastSequence == 0 or float(r.deathAt) >= 0: return false
		if not _integer(c.get("id"),1,int(data.nextCastId)-1) or cast_ids.has(int(c.id)): return false
		cast_ids[int(c.id)] = true
		if not _number(c.get("born")) or float(c.born) < 0 or float(c.born) > float(data.clock): return false
		if float(data.clock)+EPS >= float(c.born)+float(_rules.recoveryEnd): return false
		if absf(float(r.readyAt)-float(c.born)-float(_rules.cooldown)) > EPS: return false
		if not _pair(c.get("origin")) or not _pair(c.get("aim")) or _vector(c.origin).distance_to(_vector(c.aim)) > float(_rules.castReach)+EPS: return false
		if not _integer(c.get("lane"),0,MAX_ID) or not _integer(c.get("faction"),0,MAX_ID) or not _integer(c.get("orderToken"),0,MAX_ID): return false
		if not _number(c.get("hitTime")) or not c.get("resolved") is bool: return false
		var due := float(data.clock)+EPS >= float(c.born)+float(_rules.impactDelay)
		if bool(c.resolved) != due: return false
		if float(r.hitAt) >= float(c.born) and float(r.hitAt) >= 0: return false
	return true

static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value) and float(value) == floorf(float(value)) and float(value) >= minimum and float(value) <= maximum

static func _pair(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _number(value[0]) and _number(value[1]) and _vector(value).is_finite()

static func _keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size(): return false
	for key in expected:
		if not value.has(key): return false
	return true

static func _vector(value: Array) -> Vector2:
	return Vector2(float(value[0]),float(value[1]))

static func _point(actor: Dictionary) -> Vector2:
	return Vector2(float(actor.x),float(actor.y))

static func _actor(actor: Dictionary) -> bool:
	return _integer(actor.get("id"),1,MAX_ID) and actor.get("kind") is String and actor.get("category") in ["unit","building"] and _integer(actor.get("faction"),0,MAX_ID) and _integer(actor.get("vesselLane"),0,MAX_ID) and _number(actor.get("x")) and _number(actor.get("y")) and _point(actor).is_finite() and _number(actor.get("hp")) and _integer(actor.get("orderToken",0),0,MAX_ID) and _number(actor.get("hitTime",-1))
