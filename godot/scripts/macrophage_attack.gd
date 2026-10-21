class_name WarMacrophageAttack
extends RefCounted
## Independent siege melee candidate. No spawning, hiding, resources or public wiring.
const SCHEMA := "cell-war-macrophage/v1"
const EPS := 0.000000001
const MAX_ID := 2147483647
const MAX_SOURCES := 4096
var _rules: Dictionary = {}
var _clock := 0.0
var _next_id := 1
var _sources: Dictionary = {}
var _events: Array = []
var _damage := Callable()
var _geometry := Callable()
var _radius := Callable()
var _speed := Callable()
var _advancing := false
var _error := ""

func _init() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/macrophage.json"))
	_rules = data.rules.duplicate(true)

## Mandatory: damage(source,target,50,info)->receipt; geometry(from,to,lane,source,
## target,phase)->bool; radius(actor)->finite nonnegative physical radius.
## Optional speed(source)->the SAME combined attackSpeedMultiplier used by combat.
## No separate B-cell/brain/dendritic stacking is implemented here.
## Receipt: {castId,sourceId,targetId,actualDamage,killedBySource}. A swallow also
## requires live-before/dead-after, target.lastAttacker==source.id, a current
## registered pathogen unit, and actualDamage matching the synchronous hp loss.
func bind_world(damage_callback: Callable, geometry_callback: Callable, radius_callback: Callable, speed_callback := Callable()) -> void:
	if _advancing: return
	_damage = damage_callback; _geometry = geometry_callback; _radius = radius_callback; _speed = speed_callback

func _bound() -> bool:
	return _damage.is_valid() and _geometry.is_valid() and _radius.is_valid()

func clock() -> float:
	return _clock

func last_error() -> String:
	return _error

func tuning() -> Dictionary:
	return _rules.duplicate(true)

func _record(id: int) -> Dictionary:
	return _sources.get(str(id),{"lastSequence":0,"cooldown":0.0,"hitAt":-1.0,"deathAt":-1.0,"cast":{}})

func _rate(source: Dictionary) -> float:
	var rate: Variant = _speed.call(source) if _speed.is_valid() else 1.0
	return float(rate) if _number(rate) and float(rate) >= 0 and float(rate) <= 100 else -1.0

## Fixed target ID. Host approaches first and freezes the caster while active.
## At bite time recheck the target's CURRENT range, layer and LOS; never retarget.
func begin(source: Dictionary, target: Dictionary, sequence: int) -> int:
	_error = ""
	if _advancing: _error = "reentrant_call"; return 0
	if not _bound(): _error = "callbacks_required"; return 0
	if not _actor(source) or source.kind != "siege" or source.category != "unit" or source.hp <= 0 or not _enemy(source,target):
		_error = "invalid_actors"; return 0
	if not _integer(sequence,1,MAX_ID): _error = "invalid_sequence"; return 0
	var record := _record(int(source.id))
	if sequence <= int(record.lastSequence): _error = "duplicate_sequence"; return 0
	if not record.cast.is_empty() or float(record.deathAt) >= 0 or _hit(record): _error = "busy"; return 0
	if float(record.cooldown) > EPS: _error = "cooldown"; return 0
	if (_sources.size() >= MAX_SOURCES and not _sources.has(str(int(source.id)))) or _next_id > MAX_ID:
		_error = "capacity"; return 0
	_advancing = true
	var rate := _rate(source)
	var clear := _solution(source,target,"windup")
	_advancing = false
	if rate < 0 or not clear: _error = "invalid_speed_or_blocked"; return 0
	var point := _point(source); var aim := _point(target)
	var cast := {"id":_next_id,"born":_clock,"speed":maxf(.01,rate),
		"origin":[point.x,point.y],"aim":[aim.x,aim.y],"lane":int(source.vesselLane),"faction":int(source.faction),
		"orderToken":int(source.get("orderToken",0)),"hitTime":float(source.get("hitTime",-1)),
		"targetId":int(target.id),"targetKind":str(target.kind),"targetFaction":int(target.faction),
		"targetCategory":str(target.category),"resolved":false,"swallowed":false,"outcome":"pending"}
	record.cast = cast; record.lastSequence = sequence; record.cooldown = float(_rules.cooldown)
	_sources[str(int(source.id))] = record; _next_id += 1
	_event("windup",int(source.id),cast)
	return int(cast.id)

func _solution(source: Dictionary, target: Dictionary, phase: String) -> bool:
	if not _enemy(source,target) or not _bound(): return false
	var sr: Variant = _radius.call(source); var tr: Variant = _radius.call(target)
	if not _number(sr) or not _number(tr) or float(sr) < 0 or float(tr) < 0: return false
	# Match the existing weapon convention: unit centres, building near surface.
	var reach := float(_rules.reach)+(float(tr) if target.category == "building" else 0.0)
	if _point(source).distance_to(_point(target)) > reach+.000001: return false
	var result: Variant = _geometry.call(_point(source),_point(target),int(source.vesselLane),source,target,phase)
	return result is bool and result

func cancel(source_id: int, reason := "cancelled") -> void:
	if not _advancing: _cancel(source_id,reason)

func _cancel(source_id: int, reason: String) -> void:
	var record := _record(source_id)
	if record.cast.is_empty(): return
	_event(reason,source_id,record.cast); record.cast = {}; _sources[str(source_id)] = record

func notify_hit(source: Dictionary) -> bool:
	if not _actor(source) or source.kind != "siege": return false
	if source.hp <= 0: return notify_death(source)
	if not _sources.has(str(int(source.id))) and _sources.size() >= MAX_SOURCES: return false
	_cancel(int(source.id),"hit_cancelled")
	var record := _record(int(source.id))
	if float(record.deathAt) >= 0: return false
	if not _hit(record): record.hitAt = _clock
	_sources[str(int(source.id))] = record
	return true

func notify_death(source: Dictionary) -> bool:
	if not _actor(source) or source.kind != "siege" or source.hp > 0: return false
	if not _sources.has(str(int(source.id))) and _sources.size() >= MAX_SOURCES: return false
	_cancel(int(source.id),"death_cancelled")
	var record := _record(int(source.id))
	if float(record.deathAt) < 0: record.deathAt = _clock
	_sources[str(int(source.id))] = record
	return true

func advance(real_delta: float, entities: Array, paused := false, time_scale := 1.0) -> bool:
	if not _number(real_delta) or real_delta < 0 or not _number(time_scale) or time_scale < 0: return false
	return true if paused or time_scale == 0 else advance_simulation(real_delta*time_scale,entities)

func advance_simulation(delta: float, entities: Array) -> bool:
	if _advancing: _error = "reentrant_call"; return false
	if not _number(delta) or delta < 0 or not is_finite(_clock+delta): _error = "invalid_delta"; return false
	if not _sources.is_empty() and not _bound(): _error = "callbacks_required"; return false
	var world: Dictionary = {}; var rates: Dictionary = {}
	for actor in entities:
		if not actor is Dictionary or not _actor(actor): continue
		var key := str(int(actor.id))
		if world.has(key): _error = "duplicate_entity_id"; return false
		world[key] = actor
	_advancing = true
	for key in _sources:
		if not world.has(key): continue
		rates[key] = _rate(world[key])
		if float(rates[key]) < 0: _advancing = false; _error = "invalid_speed"; return false
	_clock += delta
	var keys := _sources.keys(); keys.sort()
	for key in keys:
		var record: Dictionary = _sources[key]
		var source: Dictionary = world.get(key,{})
		if not source.is_empty(): record.cooldown = maxf(0.0,float(record.cooldown)-delta*float(rates[key]))
		var cast: Dictionary = record.cast
		if cast.is_empty(): continue
		if source.is_empty() or source.kind != "siege": _cancel(int(key),"source_missing"); continue
		if source.hp <= 0: notify_death(source); continue
		if int(source.get("orderToken",0)) != int(cast.orderToken) or int(source.vesselLane) != int(cast.lane) or int(source.faction) != int(cast.faction) or _point(source).distance_to(_vector(cast.origin)) > EPS:
			_cancel(int(key),"source_changed"); continue
		if float(source.get("hitTime",-1)) > float(cast.hitTime):
			notify_hit(source); continue
		var elapsed := (_clock-float(cast.born))*float(cast.speed)
		if not cast.resolved and elapsed+EPS >= float(_rules.biteAt):
			cast.resolved = true
			_bite(source,cast,world.get(str(int(cast.targetId)),{}))
		if elapsed+EPS >= float(_rules.recoveryEnd): record.cast = {}
	_advancing = false; _error = ""
	return true

func _bite(source: Dictionary, cast: Dictionary, target: Dictionary) -> void:
	cast.outcome = "miss"
	if not _actor(target) or target.kind != cast.targetKind or int(target.faction) != int(cast.targetFaction) or target.category != cast.targetCategory or not _solution(source,target,"bite"):
		_event("bite_miss",int(source.id),cast); return
	var before := float(target.hp)
	var info := {"cause":"macrophage_bite","castId":int(cast.id),"targetId":int(target.id),
		"sourceId":int(source.id),"biteAt":float(cast.born)+float(_rules.biteAt)/float(cast.speed),
		"lane":int(cast.lane),"allowSwallow":target.category == "unit" and WarData.is_pathogen(str(target.kind))}
	# Exactly one synchronous callback. No instant kill, removal, healing or reward.
	var receipt: Variant = _damage.call(source,target,float(_rules.damage),info.duplicate(true))
	cast.outcome = "hit"
	var credited := _receipt(receipt,info,before,target)
	if info.allowSwallow and credited and float(target.hp) <= 0 and target.get("lastAttacker",0) == source.id:
		cast.swallowed = true; cast.outcome = "swallowed"
		_event("swallow_success",int(source.id),cast)
	else:
		_event("bite_hit",int(source.id),cast)

func _receipt(receipt: Variant, info: Dictionary, before: float, target: Dictionary) -> bool:
	if not receipt is Dictionary or not _actor(target): return false
	for key in ["castId","sourceId","targetId"]:
		if not _integer(receipt.get(key),1,MAX_ID) or int(receipt[key]) != int(info[key]): return false
	if receipt.get("killedBySource") != true or not receipt.get("killedBySource") is bool: return false
	var actual: Variant = receipt.get("actualDamage")
	return _number(actual) and float(actual) > 0 and absf(float(actual)-(before-maxf(0.0,float(target.hp)))) <= EPS

func _hit(record: Dictionary) -> bool:
	return float(record.hitAt) >= 0 and _clock < float(record.hitAt)+float(_rules.hitDuration)-EPS

func presentation(source_id: int) -> Dictionary:
	var record := _record(source_id)
	var result := {"clock":_clock,"pose":"idle","elapsed":0.0,"swallowed":false,"cast":record.cast.duplicate(true)}
	if float(record.deathAt) >= 0:
		result.pose = "death"; result.elapsed = _clock-float(record.deathAt)
	elif _hit(record):
		result.pose = "hit"; result.elapsed = _clock-float(record.hitAt)
	elif not record.cast.is_empty():
		result.pose = "swallow"; result.elapsed = (_clock-float(record.cast.born))*float(record.cast.speed)
		result.swallowed = record.cast.swallowed
	return result

func _event(type: String, source_id: int, cast: Dictionary) -> void:
	_events.append({"type":type,"sourceId":source_id,"targetId":cast.targetId,"castId":cast.id,"clock":_clock})
	if _events.size() > 256: _events.pop_front()

func drain_events() -> Array:
	if _advancing: return []
	var events := _events.duplicate(true); _events.clear(); return events

func snapshot() -> Dictionary:
	if _advancing: _error = "atomic_step_in_progress"; return {}
	return {"schema":SCHEMA,"clock":_clock,"nextCastId":_next_id,"rules":_rules.duplicate(true),"sources":_sources.duplicate(true)}

func restore(data: Dictionary) -> bool:
	if _advancing: _error = "atomic_step_in_progress"; return false
	if not _valid_snapshot(data): _error = "invalid_snapshot"; return false
	_clock = float(data.clock); _next_id = int(data.nextCastId); _sources = data.sources.duplicate(true)
	_events.clear(); _error = ""; return true

func _valid_snapshot(data: Dictionary) -> bool:
	if not _keys(data,["schema","clock","nextCastId","rules","sources"]) or data.schema != SCHEMA: return false
	if not _number(data.clock) or float(data.clock) < 0 or not _integer(data.nextCastId,1,MAX_ID+1): return false
	if not data.rules is Dictionary or data.rules != _rules or not data.sources is Dictionary or data.sources.size() > MAX_SOURCES: return false
	var ids: Dictionary = {}
	for key in data.sources:
		if not key is String or not key.is_valid_int() or str(int(key)) != key or not _integer(int(key),1,MAX_ID): return false
		var r: Variant = data.sources[key]
		if not r is Dictionary or not _keys(r,["lastSequence","cooldown","hitAt","deathAt","cast"]): return false
		if not _integer(r.lastSequence,0,MAX_ID) or not _number(r.cooldown) or float(r.cooldown) < 0 or float(r.cooldown) > float(_rules.cooldown): return false
		for field in ["hitAt","deathAt"]:
			if not _number(r[field]) or (float(r[field]) != -1 and (float(r[field]) < 0 or float(r[field]) > float(data.clock))): return false
		if not r.cast is Dictionary: return false
		var c: Dictionary = r.cast
		if c.is_empty(): continue
		if not _keys(c,["id","born","speed","origin","aim","lane","faction","orderToken","hitTime","targetId","targetKind","targetFaction","targetCategory","resolved","swallowed","outcome"]): return false
		if r.lastSequence == 0 or float(r.deathAt) >= 0 or not _integer(c.id,1,int(data.nextCastId)-1) or ids.has(int(c.id)): return false
		ids[int(c.id)] = true
		if not _number(c.born) or float(c.born) < 0 or float(c.born) > float(data.clock): return false
		if not _number(c.speed) or float(c.speed) < .01 or float(c.speed) > 100: return false
		var elapsed := (float(data.clock)-float(c.born))*float(c.speed)
		if elapsed+EPS >= float(_rules.recoveryEnd): return false
		if not _pair(c.origin) or not _pair(c.aim) or not _number(c.hitTime): return false
		for field in ["lane","faction","orderToken","targetFaction"]:
			if not _integer(c[field],0,MAX_ID): return false
		if not _integer(c.targetId,1,MAX_ID) or int(c.targetId) == int(key) or not c.targetKind is String or c.targetKind.is_empty(): return false
		if c.targetCategory not in ["unit","building"] or c.faction == c.targetFaction: return false
		if not c.resolved is bool or not c.swallowed is bool: return false
		if c.resolved != (elapsed+EPS >= float(_rules.biteAt)): return false
		if c.outcome not in ["pending","miss","hit","swallowed"] or (c.outcome == "pending") == c.resolved: return false
		if c.swallowed != (c.outcome == "swallowed"): return false
		if c.swallowed and (c.targetCategory != "unit" or not WarData.is_pathogen(c.targetKind)): return false
		if float(r.hitAt) >= float(c.born) and float(r.hitAt) >= 0: return false
	return true

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value) and float(value) == floorf(float(value)) and float(value) >= minimum and float(value) <= maximum

static func _point(actor: Dictionary) -> Vector2:
	return Vector2(float(actor.x),float(actor.y))

static func _vector(value: Array) -> Vector2:
	return Vector2(float(value[0]),float(value[1]))

static func _pair(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _number(value[0]) and _number(value[1]) and _vector(value).is_finite()

static func _keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size(): return false
	for key in expected:
		if not value.has(key): return false
	return true

static func _actor(actor: Dictionary) -> bool:
	return _integer(actor.get("id"),1,MAX_ID) and actor.get("kind") is String and actor.get("category") in ["unit","building"] and _integer(actor.get("faction"),0,MAX_ID) and _integer(actor.get("vesselLane"),0,MAX_ID) and _number(actor.get("x")) and _number(actor.get("y")) and _point(actor).is_finite() and _number(actor.get("hp")) and _integer(actor.get("orderToken",0),0,MAX_ID) and _number(actor.get("hitTime",-1))

static func _enemy(source: Dictionary, target: Dictionary) -> bool:
	return _actor(target) and target.hp > 0 and target.id != source.id and target.faction != source.faction and target.vesselLane == source.vesselLane
