class_name WarMedicineBubbles
extends RefCounted
## Fever/pain-relief projectiles; supply, actor spawning and UI live in their services.
## Tuning numbers remain first-pass balance defaults.
const MEDICINE_ID := "fever_pain_relief"
const SCHEMA := "cell-war-medicine-bubbles/v1"
const EPS := 0.0000001
const MAX_ID := 2147483647
const CATALOGUE_TUNING := ["damage", "range", "attackCooldownSeconds", "projectileSpeed", "slowRatio", "slowDurationSeconds"]
const EXTRA_DEFAULTS := {
	"projectileRadius":0.1, "targetRadius":0.35, "geometryStep":0.2,
	"projectileMaxLifetimeSeconds":2.0, "maxProjectiles":128,
	"maxSourceRecords":256, "maxEvents":256,
}
var _rules: Dictionary = {}
var _clock := 0.0
var _next_id := 1
var _projectiles: Array = []
var _slows: Dictionary = {}
var _sources: Dictionary = {}
var _events: Array = []
var _damage := Callable()
var _geometry := Callable()
var _radius := Callable()
var _error := ""


func _init(overrides: Dictionary = {}) -> void:
	var text := FileAccess.get_file_as_string("res://data/medicines.json")
	var catalogue = JSON.parse_string(text)
	if not catalogue is Dictionary or not catalogue.get("entries") is Array:
		_error = "missing_catalogue"; return
	var definition: Dictionary = {}
	for item in catalogue.entries:
		if item is Dictionary and item.get("id", "") == MEDICINE_ID:
			definition = item; break
	if definition.get("confirmation", {}).get("mechanic", "") != "core_confirmed":
		_error = "mechanic_not_confirmed"; return
	var defaults: Dictionary = definition.get("balanceDefaults", {}).get("values", {})
	var tuning := EXTRA_DEFAULTS.duplicate(true)
	for key in CATALOGUE_TUNING:
		if not defaults.has(key): _error = "missing_tuning"; return
		tuning[key] = defaults[key]
	for key in overrides:
		if not tuning.has(key): _error = "unknown_tuning"; return
		tuning[key] = overrides[key]
	if not _valid_rules(tuning): _error = "invalid_tuning"; return
	_rules = _normalize_rules(tuning)


## Geometry callback: (from:Vector2,to:Vector2,lane:int,source:Dictionary)->bool.
## Required: without it launch fails closed. Damage/radius callbacks are optional;
## omitted damage mutates target.hp directly for isolated service use/tests.
func bind_world(damage_callback: Callable, geometry_callback: Callable, radius_callback := Callable()) -> void:
	_damage = damage_callback
	_geometry = geometry_callback
	_radius = radius_callback


func ready() -> bool:
	return not _rules.is_empty()


func last_error() -> String:
	return _error


func tuning() -> Dictionary:
	var targets: Array[String] = []
	for kind in WarData.config().Data.units:
		if WarData.is_virus(str(kind)): targets.append(str(kind))
	targets.sort()
	return {"status":"draft_pending_balance", "confirmedValues":false,
		"medicineId":MEDICINE_ID, "values":_rules.duplicate(true),
		"catalogue":"res://data/medicines.json", "targetKinds":targets}


## sequence is the emitting actor's monotonically increasing shot sequence.
## Invalid, duplicate, cooling-down or capacity-limited calls do not consume it.
## aim fixes a direction at launch; the bubble never homes onto a moving target.
func launch(source: Dictionary, aim: Vector2, sequence: int) -> int:
	_error = ""
	if not ready(): _error = "not_configured"; return 0
	if not _geometry.is_valid(): _error = "geometry_required"; return 0
	if not _valid_actor(source) or float(source.hp) <= 0 or not aim.is_finite():
		_error = "invalid_source_or_aim"; return 0
	if sequence <= 0 or sequence > MAX_ID: _error = "invalid_sequence"; return 0
	var key := str(int(source.id))
	var previous: Dictionary = _sources.get(key, {"lastSequence":0, "readyAt":0.0})
	if sequence <= int(previous.lastSequence): _error = "duplicate_sequence"; return 0
	if _clock + EPS < float(previous.readyAt): _error = "cooldown"; return 0
	if _projectiles.size() >= int(_rules.maxProjectiles) or _next_id > MAX_ID:
		_error = "projectile_capacity"; return 0
	if not _sources.has(key) and _sources.size() >= int(_rules.maxSourceRecords):
		_error = "source_capacity"; return 0
	var start := Vector2(float(source.x), float(source.y))
	var direction := aim - start
	if direction.length_squared() <= EPS: _error = "zero_direction"; return 0
	direction = direction.normalized()
	if not direction.is_finite() or direction.is_zero_approx(): _error = "invalid_direction"; return 0
	var owner := {"id":int(source.id), "kind":str(source.kind), "faction":int(source.faction),
		"x":start.x, "y":start.y, "vesselLane":int(source.get("vesselLane", 0)), "statuses":{}}
	var projectile := {"id":_next_id, "source":owner, "x":start.x, "y":start.y,
		"dx":direction.x, "dy":direction.y, "born":_clock,
		"remainingDistance":float(_rules.range),
		"remainingLife":minf(float(_rules.projectileMaxLifetimeSeconds), float(_rules.range) / float(_rules.projectileSpeed))}
	_projectiles.append(projectile)
	_sources[key] = {"lastSequence":sequence, "readyAt":_clock + float(_rules.attackCooldownSeconds)}
	_next_id += 1
	_record("bubble_spawn", {"projectile":projectile.duplicate(true)})
	return int(projectile.id)


## Use either this wall-time adapter OR advance_simulation(), never both.
func advance(real_delta: float, entities: Array, paused := false, time_scale := 1.0) -> bool:
	if not is_finite(real_delta) or real_delta < 0 or not is_finite(time_scale) or time_scale < 0:
		_error = "invalid_delta"; return false
	if paused or is_zero_approx(time_scale): return true
	return advance_simulation(real_delta * time_scale, entities)


## entities must contain the current live actor dictionaries, including emitters.
## No delta clamp: the host fixed step owns time. Swept collisions prevent tunnelling.
func advance_simulation(delta: float, entities: Array) -> bool:
	if not ready() or not is_finite(delta) or delta < 0 or not is_finite(_clock + delta):
		_error = "invalid_delta_or_configuration"; return false
	if not _projectiles.is_empty() and not _geometry.is_valid():
		_error = "geometry_required"; return false
	var world: Dictionary = {}
	for actor in entities:
		if not actor is Dictionary or not _valid_actor(actor): continue
		var key := str(int(actor.id))
		if world.has(key): _error = "duplicate_entity_id"; return false
		world[key] = actor
	var end := _clock + delta
	_cleanup(world)
	var survivors: Array = []
	for projectile in _projectiles:
		if _move(projectile, delta, world): survivors.append(projectile)
	_projectiles = survivors
	_clock = end
	_cleanup(world)
	_error = ""
	return true


func speed_multiplier(target: Dictionary) -> float:
	if not _valid_actor(target) or float(target.hp) <= 0: return 1.0
	var status: Dictionary = _slows.get(str(int(target.id)), {})
	if status.is_empty() or float(status.expiresAt) <= _clock + EPS: return 1.0
	return 1.0 - float(status.ratio)


func slow_remaining(target_id: int) -> float:
	return maxf(0.0, float(_slows.get(str(target_id), {}).get("expiresAt", _clock)) - _clock)


func projectiles() -> Array:
	return _projectiles.duplicate(true)


func clock() -> float:
	return _clock


func drain_events() -> Array:
	var result := _events.duplicate(true)
	_events.clear()
	return result


func snapshot() -> Dictionary:
	return {"schema":SCHEMA, "medicineId":MEDICINE_ID, "tuningStatus":"draft_pending_balance",
		"clock":_clock, "nextProjectileId":_next_id, "rules":_rules.duplicate(true),
		"projectiles":_projectiles.duplicate(true), "slows":_slows.duplicate(true), "sources":_sources.duplicate(true)}


## Transactional restore. Callables are host bindings and are never serialized.
## Loading does not execute damage, spawn events, cooldowns or animation events.
func restore(data: Dictionary) -> bool:
	var normalized := _validate_snapshot(data)
	if normalized.is_empty(): _error = "invalid_snapshot"; return false
	_rules = normalized.rules
	_clock = float(normalized.clock)
	_next_id = int(normalized.nextProjectileId)
	_projectiles = normalized.projectiles
	_slows = normalized.slows
	_sources = normalized.sources
	_events.clear()
	_error = ""
	return true


## Save-envelope owners may validate before replacing any host/world state.
static func validate_snapshot(data: Dictionary) -> String:
	return "" if not _validate_snapshot(data).is_empty() else "invalid_medicine_bubble_snapshot"


func _move(projectile: Dictionary, delta: float, world: Dictionary) -> bool:
	var speed := float(_rules.projectileSpeed)
	var budget := minf(delta, minf(float(projectile.remainingLife), float(projectile.remainingDistance) / speed))
	var left := speed * budget
	var travelled := 0.0
	var point := Vector2(float(projectile.x), float(projectile.y))
	var direction := Vector2(float(projectile.dx), float(projectile.dy))
	while left > EPS:
		var length := minf(left, float(_rules.geometryStep))
		var next := point + direction * length
		var contact: Dictionary = {}
		var earliest := INF
		for target in world.values():
			if not _eligible(projectile, target): continue
			var radius := float(_rules.targetRadius)
			if _radius.is_valid():
				var value = _radius.call(target)
				if not _number(value) or float(value) <= 0: continue
				radius = float(value)
			var fraction := _circle_contact(point, next, Vector2(float(target.x), float(target.y)), radius + float(_rules.projectileRadius))
			if fraction >= 0 and (fraction < earliest - EPS or (absf(fraction - earliest) <= EPS and (contact.is_empty() or int(target.id) < int(contact.id)))):
				earliest = fraction; contact = target
		var stop := point.lerp(next, earliest) if not contact.is_empty() else next
		if not _geometry.is_valid() or not bool(_geometry.call(point, stop, int(projectile.source.vesselLane), projectile.source.duplicate(true))):
			_record("bubble_blocked", {"id":projectile.id, "x":point.x, "y":point.y, "vesselLane":int(projectile.source.vesselLane)}, _clock + travelled / speed)
			return false
		if not contact.is_empty():
			_hit(projectile, contact, stop, _clock + (travelled + length * earliest) / speed)
			return false
		point = next
		left -= length
		travelled += length
	projectile.x = point.x; projectile.y = point.y
	projectile.remainingDistance = maxf(0.0, float(projectile.remainingDistance) - travelled)
	projectile.remainingLife = maxf(0.0, float(projectile.remainingLife) - budget)
	if float(projectile.remainingLife) <= EPS or float(projectile.remainingDistance) <= EPS:
		_record("bubble_expired", {"id":projectile.id, "x":point.x, "y":point.y, "vesselLane":int(projectile.source.vesselLane)}, _clock + budget)
		return false
	return true


func _hit(projectile: Dictionary, target: Dictionary, point: Vector2, at: float) -> void:
	var before := float(target.hp)
	if _damage.is_valid():
		_damage.call(projectile.source.duplicate(true), target, float(_rules.damage), "medicine_bubble")
	else:
		target.hp = maxf(0.0, before - float(_rules.damage))
		if float(target.hp) <= 0: target.combatState = "dead"
	var actual := maxf(0.0, before - float(target.hp))
	var key := str(int(target.id))
	if float(target.hp) > 0 and actual > 0:
		# One medicine-owned status. Refresh, never add duration or multiply ratios.
		_slows[key] = {"ratio":float(_rules.slowRatio), "expiresAt":at + float(_rules.slowDurationSeconds)}
	elif float(target.hp) <= 0:
		_slows.erase(key)
	_record("bubble_impact", {"id":projectile.id, "target":int(target.id), "damage":actual,
		"x":point.x, "y":point.y, "vesselLane":int(projectile.source.vesselLane), "killed":float(target.hp) <= 0}, at)


func _eligible(projectile: Dictionary, target: Dictionary) -> bool:
	return (float(target.hp) > 0 and WarData.is_virus(str(target.kind)) and target.get("category", "") == "unit"
		and int(target.id) != int(projectile.source.id) and int(target.faction) != int(projectile.source.faction)
		and int(target.get("vesselLane", 0)) == int(projectile.source.vesselLane))


func _cleanup(world: Dictionary) -> void:
	for key in _slows.keys():
		if not world.has(key) or float(world[key].hp) <= 0 or float(_slows[key].expiresAt) <= _clock + EPS:
			_slows.erase(key)
	for key in _sources.keys():
		if not world.has(key) or float(world[key].hp) <= 0: _sources.erase(key)


func _record(kind: String, fields: Dictionary, at := -1.0) -> void:
	var event := fields.duplicate(true)
	event.kind = kind; event.time = _clock if at < 0 else at
	_events.append(event)
	while _events.size() > int(_rules.maxEvents): _events.pop_front()


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _id(value: Variant) -> bool:
	return _number(value) and float(value) >= 1 and float(value) <= MAX_ID and floorf(float(value)) == float(value)


static func _valid_actor(actor: Dictionary) -> bool:
	if not _id(actor.get("id")) or not actor.get("kind") is String or not _number(actor.get("hp")): return false
	for key in ["x", "y", "faction"]:
		if not _number(actor.get(key)): return false
	return (floorf(float(actor.faction)) == float(actor.faction) and _number(actor.get("vesselLane", 0))
		and floorf(float(actor.get("vesselLane", 0))) == float(actor.get("vesselLane", 0)))


static func _valid_rules(rules: Dictionary) -> bool:
	if rules.size() != EXTRA_DEFAULTS.size() + CATALOGUE_TUNING.size(): return false
	for key in rules:
		if not EXTRA_DEFAULTS.has(key) and not key in CATALOGUE_TUNING: return false
	for key in ["damage", "range", "projectileSpeed", "slowDurationSeconds", "projectileMaxLifetimeSeconds", "targetRadius", "geometryStep"]:
		if not _number(rules.get(key)) or float(rules[key]) <= 0 or float(rules[key]) > 100000: return false
	for key in ["attackCooldownSeconds", "projectileRadius"]:
		if not _number(rules.get(key)) or float(rules[key]) < 0 or float(rules[key]) > 100000: return false
	if not _number(rules.get("slowRatio")) or float(rules.slowRatio) < 0 or float(rules.slowRatio) >= 1: return false
	for key in ["maxProjectiles", "maxSourceRecords", "maxEvents"]:
		if not _id(rules.get(key)) or int(rules[key]) > 4096: return false
	return true


static func _normalize_rules(rules: Dictionary) -> Dictionary:
	var normalized := rules.duplicate(true)
	for key in normalized:
		normalized[key] = int(normalized[key]) if key in ["maxProjectiles", "maxSourceRecords", "maxEvents"] else float(normalized[key])
	return normalized


static func _circle_contact(from: Vector2, to: Vector2, center: Vector2, radius: float) -> float:
	var offset := from - center
	var c := offset.length_squared() - radius * radius
	if c <= 0: return 0.0
	var direction := to - from
	var a := direction.length_squared()
	if a <= EPS: return -1.0
	var b := offset.dot(direction)
	var discriminant := b * b - a * c
	if discriminant < 0: return -1.0
	var fraction := (-b - sqrt(discriminant)) / a
	return clampf(fraction, 0, 1) if fraction >= -EPS and fraction <= 1.0 + EPS else -1.0


static func _validate_snapshot(data: Dictionary) -> Dictionary:
	if data.get("schema") != SCHEMA or data.get("medicineId") != MEDICINE_ID: return {}
	if not _number(data.get("clock")) or float(data.clock) < 0 or not _id(data.get("nextProjectileId")): return {}
	if not data.get("rules") is Dictionary or not _valid_rules(data.rules): return {}
	if not data.get("projectiles") is Array or not data.get("slows") is Dictionary or not data.get("sources") is Dictionary: return {}
	if data.projectiles.size() > int(data.rules.maxProjectiles) or data.sources.size() > int(data.rules.maxSourceRecords) or data.slows.size() > 65536: return {}
	var result := data.duplicate(true)
	result.rules = _normalize_rules(result.rules)
	var ids: Dictionary = {}
	for projectile in result.projectiles:
		if not projectile is Dictionary or not _id(projectile.get("id")) or int(projectile.id) >= int(data.nextProjectileId): return {}
		if ids.has(int(projectile.id)): return {}
		ids[int(projectile.id)] = true
		for key in ["x", "y", "dx", "dy", "born", "remainingLife", "remainingDistance"]:
			if not _number(projectile.get(key)): return {}
		if absf(Vector2(float(projectile.dx), float(projectile.dy)).length_squared() - 1.0) > 0.00001: return {}
		if float(projectile.born) < 0 or float(projectile.born) > float(data.clock) + EPS: return {}
		if float(projectile.remainingLife) <= 0 or float(projectile.remainingLife) > float(data.rules.projectileMaxLifetimeSeconds) + EPS: return {}
		if float(projectile.remainingDistance) <= 0 or float(projectile.remainingDistance) > float(data.rules.range) + EPS: return {}
		if not projectile.get("source") is Dictionary: return {}
		var source: Dictionary = projectile.source
		var owner := source.duplicate(true); owner.hp = 1.0
		if not _valid_actor(owner): return {}
		# These components originate from Vector2 (float32). Rehydrate that exact
		# representation after JSON parsing instead of retaining a decimal-parser ULP.
		var position := Vector2(float(projectile.x), float(projectile.y))
		var direction := Vector2(float(projectile.dx), float(projectile.dy))
		projectile.x = position.x; projectile.y = position.y
		projectile.dx = direction.x; projectile.dy = direction.y
		var origin := Vector2(float(source.x), float(source.y))
		source.x = origin.x; source.y = origin.y
		projectile.id = int(projectile.id); source.id = int(source.id); source.faction = int(source.faction)
		source.vesselLane = int(source.get("vesselLane", 0))
	for key in result.slows:
		if not key is String or not key.is_valid_int() or str(int(key)) != key or not _id(int(key)) or not result.slows[key] is Dictionary: return {}
		var status: Dictionary = result.slows[key]
		if not _number(status.get("ratio")) or not is_equal_approx(float(status.ratio), float(data.rules.slowRatio)): return {}
		if not _number(status.get("expiresAt")) or float(status.expiresAt) < 0: return {}
		if float(status.expiresAt) > float(data.clock) + float(data.rules.slowDurationSeconds) + EPS: return {}
	for key in result.sources:
		if not key is String or not key.is_valid_int() or str(int(key)) != key or not _id(int(key)) or not result.sources[key] is Dictionary: return {}
		var source: Dictionary = result.sources[key]
		if not _id(source.get("lastSequence")) or not _number(source.get("readyAt")) or float(source.readyAt) < 0: return {}
		if float(source.readyAt) > float(data.clock) + float(data.rules.attackCooldownSeconds) + EPS: return {}
		source.lastSequence = int(source.lastSequence)
	return result
