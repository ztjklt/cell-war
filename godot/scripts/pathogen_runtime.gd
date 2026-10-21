class_name WarPathogenRuntime
extends RefCounted
## Opt-in host adapter. No global registration, natural invasion or shared hooks.
## unit() must intercept both species BEFORE influenza/scenarios/generic fight.
## advance() runs once after unit dispatch, before corpse removal/knockback resolve.
const KINDS := ["pneumococcus","adenovirus"]
const SCHEMA := "cell-war-pathogen-host/v1"
const EPS := .000001
var game: WarSimulation
var pneumococcus: WarPneumococcus
var _host: PneumoHost
var _adenos: Dictionary = {}
var _sequences: Dictionary = {}
var _acted: Dictionary = {}
var _pending: Dictionary = {}
var _last_tick := -1
var _last_time := 0.0
var _stepping := false
var _project := Callable()
var _error := ""

class CombatBridge extends RefCounted:
	var owner
	func _init(runtime): owner = runtime
	func multiplier(actor: Dictionary,field: String) -> float:
		return owner.game.combat.multiplier(actor,field)
	func _target_geometry(target: Dictionary,lane: int) -> Dictionary:
		return owner.target_geometry(target,lane)
	func damage(source: Dictionary,target: Dictionary,amount: float,raw := false,cause := "projectile",direction := Vector2.ZERO) -> void:
		owner._damage(source,target,amount,raw,cause,direction)

class PneumoHost extends RefCounted:
	var owner
	var navigation: WarNavigation
	var combat: CombatBridge
	var state: Dictionary:
		get: return owner.game.state
	var paused: bool:
		get: return owner.game.paused
	func _init(runtime):
		owner = runtime; navigation = runtime.game.navigation; combat = CombatBridge.new(runtime)
	func entity(id: int) -> Dictionary: return owner.game.entity(id)
	func entities() -> Array: return owner.game.entities()
	func event(kind: String,fields: Dictionary) -> void: owner.game.event(kind,fields)

func _init(owner: WarSimulation, projection := Callable()) -> void:
	game = owner; _project = projection
	_host = PneumoHost.new(self); pneumococcus = WarPneumococcus.new(_host)
	_last_time = float(game.state.get("time",0))

static func handles(kind: String) -> bool:
	return kind in KINDS

static func registered(kind: String) -> bool:
	var family := "bacterium" if kind == "pneumococcus" else "virus"
	return handles(kind) and WarData.is_pathogen(kind) and WarData.pathogen_family(kind) == family and WarData.config().Data.cellRadii.has(kind)

func last_error() -> String: return _error

## This does not register a kind or choose an invasion location. The caller must
## supply a certified point AND explicit lane; projected pick_lane is not authority.
func spawn(kind: String,faction: int,point: Vector2,lane: int) -> Dictionary:
	if _stepping or not registered(kind) or not point.is_finite() or lane < 0: return {}
	if not game.navigation.point_allowed(point,lane,kind): return {}
	var probe := {"id":-1,"kind":kind,"faction":faction,"vesselLane":lane,"x":point.x,"y":point.y,"category":"unit"}
	if not game._position_free(probe,point): return {}
	var actor := game.spawn(kind,faction,point)
	if actor.is_empty(): return {}
	actor.vesselLane = lane
	return actor

func target_geometry(target: Dictionary,lane: int) -> Dictionary:
	return game.combat._target_geometry(target,lane)

func _view(target: Dictionary,lane: int) -> Dictionary:
	if not target.has("checkpointId"): return target
	var geometry := target_geometry(target,lane)
	var proxy := target.duplicate(true)
	proxy.x = geometry.point.x; proxy.y = geometry.point.y; proxy.vesselLane = int(geometry.lane)
	return proxy

func _world(lane: int) -> Array:
	var result: Array = []
	for actor in game.entities(): result.append(_view(actor,lane))
	return result

func _adeno(id: int) -> WarAdenovirusAttack:
	var key := str(id)
	if not _adenos.has(key):
		var service := WarAdenovirusAttack.new()
		service.bind_world(_adeno_damage,_adeno_geometry,_adeno_push)
		service.advance_simulation(float(game.state.time),[])
		_adenos[key] = service
	return _adenos[key]

func _cast(actor: Dictionary) -> Dictionary:
	var service: WarAdenovirusAttack = _adenos.get(str(int(actor.id)))
	return {} if service == null else service.presentation(int(actor.id)).cast

func _freeze(actor: Dictionary) -> void:
	game.reset_path(actor); actor.movementSpeed = 0.0; actor.travelSpeed = 0.0
	actor.combatState = "attack"

func _eligible(source: Dictionary,target: Dictionary,require_visibility := true) -> bool:
	if target.is_empty() or float(target.get("hp",0)) <= 0 or target.get("category","") not in ["unit","building"] or target.faction == source.faction: return false
	if target.has("checkpointId") and target.get("breached",false): return false
	var lane := int(source.get("vesselLane",0))
	var geometry := target_geometry(target,lane)
	return int(geometry.lane) == lane and (not require_visibility or game.visible(_view(target,lane),int(source.faction)))

func _nearest(source: Dictionary) -> Dictionary:
	var best: Dictionary = {}; var distance := pow(float(WarData.spec(source.kind).vision),2)
	for target in game.entities():
		if not _eligible(source,target): continue
		var geometry := target_geometry(target,int(source.vesselLane))
		var d := WarData.point(source).distance_squared_to(geometry.point)
		if d < distance-EPS or (absf(d-distance) <= EPS and (best.is_empty() or int(target.id) < int(best.id))):
			best = target; distance = d
	return best

## Return true for every handled species, including idle/cooling/unregistered:
## never fall through to the legacy generic fight or influenza construction.
func unit(actor: Dictionary,dt: float) -> bool:
	if not handles(str(actor.get("kind",""))): return false
	if game.paused or _stepping or actor.hp <= 0 or not registered(actor.kind): return true
	var key := str(int(actor.id)); var tick := int(game.state.tick)
	if int(_acted.get(key,-1)) == tick: return true
	_acted[key] = tick
	var order: Dictionary = actor.orders[0] if not actor.get("orders",[]).is_empty() else {}
	var command := str(order.get("kind",""))
	var cast := _cast(actor) if actor.kind == "adenovirus" else {}
	if not cast.is_empty() and int(cast.orderToken) != int(actor.get("orderToken",0)):
		_adeno(int(actor.id)).cancel(int(actor.id),"order"); cast = {}
	if actor.kind == "pneumococcus" and pneumococcus.is_casting(actor):
		var changed := false
		for pending in pneumococcus.state().casts.values():
			if int(pending.source) == int(actor.id) and int(pending.orderToken) != int(actor.get("orderToken",0)): changed = true
		if changed: pneumococcus.cancel_for_unit(actor,"order")
	if command in ["move","retreat","guard","supplyroute"]:
		cancel(actor,"movement")
		var point := Vector2(float(order.get("x",actor.x)),float(order.get("y",actor.y)))
		if game.go(actor,point,dt,.05,int(order.get("lane",actor.vesselLane))) and command != "guard": game.finish_order(actor)
		return true
	if command in ["build","repair","harvest","gather","farm","extinguish"]:
		cancel(actor,"unsupported_work"); actor.combatState = "idle"; return true
	if not cast.is_empty() or (actor.kind == "pneumococcus" and pneumococcus.is_casting(actor)):
		_freeze(actor); return true
	var target := game.entity(int(order.get("target",0))) if command == "attack" else {}
	if not _eligible(actor,target,command != "attack"): target = _nearest(actor) if command != "attack" else {}
	if not target.is_empty():
		_engage(actor,target,dt,command not in ["hold","stop"]); return true
	if command == "attackmove":
		if game.go(actor,Vector2(order.get("x",actor.x),order.get("y",actor.y)),dt,.05,int(order.get("lane",actor.vesselLane))): game.finish_order(actor)
	elif command == "attack":
		game.finish_order(actor)
	elif command not in ["hold","stop"] and game.is_fullbody():
		_gate_goal(actor,dt)
	return true

func _engage(source: Dictionary,target: Dictionary,dt: float,chase: bool) -> void:
	var lane := int(source.vesselLane); var geometry := target_geometry(target,lane)
	if int(geometry.lane) != lane: return
	if source.kind == "pneumococcus":
		var reachable := WarData.point(source).distance_to(geometry.point) <= float(WarPneumococcus.data().unit.range)+EPS
		if reachable and game.navigation.clear_segment(WarData.point(source),geometry.point,lane,source.kind):
			_freeze(source); pneumococcus.try_attack(source,target); return
	else:
		var aim := _slam_aim(source,target)
		if WarData.point(source).distance_to(aim) <= 2.4+EPS and _adeno_geometry(WarData.point(source),aim,lane,source,{},"cast"):
			_freeze(source); _pending[str(int(source.id))] = {"target":int(target.id),"aim":[aim.x,aim.y],"orderToken":int(source.get("orderToken",0))}; return
	if chase:
		var clear := game.navigation.clear_segment(WarData.point(source),geometry.point,lane,source.kind)
		if source.kind == "adenovirus": clear = clear and _adeno_geometry(WarData.point(source),_slam_aim(source,target),lane,source,{},"cast")
		game.go(source,geometry.point,dt,maxf(.2,float(WarData.spec(source.kind).range)-.15) if clear else .2,lane)

func _slam_aim(source: Dictionary,target: Dictionary) -> Vector2:
	var geometry := target_geometry(target,int(source.vesselLane))
	var goal: Vector2 = geometry.point
	if target.category == "building":
		var start := WarData.point(source)
		var rect := Rect2(goal-Vector2.ONE*float(geometry.radius),Vector2.ONE*float(geometry.radius)*2)
		var at := WarPneumococcus._rect_t(start,goal,rect)
		if is_finite(at): goal = start.lerp(goal,at)-(goal-start).normalized()*.002
	return goal

## Explicit authored port traversal only. All attacking goes through _engage.
func _gate_goal(source: Dictionary,dt: float) -> void:
	var lane := int(source.vesselLane)
	var organ := game.navigation.organ_at(WarData.point(source),source.kind) if lane == 0 else ""
	var port: Dictionary = {}; var distance := INF
	for p in WarData.read("checkpoints").ports:
		if (lane == 0 and p.organId != organ) or (lane > 0 and int(p.lane) != lane): continue
		var point := WarData.source_to_world(p.b if lane == 0 else p.a)
		var d := WarData.point(source).distance_squared_to(point)
		if p.id == source.get("spreadTargetGate",""): d *= .8
		if d < distance: port = p; distance = d
	if port.is_empty(): return
	var gate: Dictionary = game.navigation.gates.get(port.id,{})
	if gate.is_empty(): return
	source.spreadTargetGate = port.id
	if not gate.get("breached",false):
		_engage(source,gate,dt,true); return
	if gate.get("isolated",false): return
	var destination := WarData.source_to_world(port.a if lane == 0 else port.b)
	var next_lane := int(port.lane) if lane == 0 else 0
	if game.go(source,destination,dt,.025,next_lane):
		source.spreadOriginGate = port.id; source.spreadOriginOrgan = port.organId
		source.erase("spreadTargetGate")

func cancel(actor: Dictionary,reason := "order") -> void:
	_pending.erase(str(int(actor.id)))
	if actor.kind == "pneumococcus": pneumococcus.cancel_for_unit(actor,reason)
	elif _adenos.has(str(int(actor.id))): _adenos[str(int(actor.id))].cancel(int(actor.id),reason)

func _screen_direction(point: Vector2,direction: Vector2) -> Vector2:
	return _project.call(point+direction)-_project.call(point) if _project.is_valid() else direction

func notify_hit(actor: Dictionary,direction := Vector2.ZERO) -> void:
	if not handles(str(actor.get("kind",""))): return
	actor.pathogenObservedHit = float(actor.get("hitTime",game.state.time))
	if actor.hp <= 0: notify_death(actor); return
	if actor.kind == "pneumococcus": pneumococcus.notify_hit(actor,_screen_direction(WarData.point(actor),direction))
	else: _adeno(int(actor.id)).notify_hit(actor,-_screen_direction(WarData.point(actor),direction))

func notify_death(actor: Dictionary) -> void:
	if actor.kind == "pneumococcus": pneumococcus.notify_death(actor)
	elif actor.kind == "adenovirus": _adeno(int(actor.id)).notify_death(actor)
	_pending.erase(str(int(actor.id)))

func _observe() -> void:
	for actor in game.entities():
		if not handles(str(actor.kind)): continue
		if actor.hp <= 0: notify_death(actor); continue
		if float(actor.get("hitTime",-1)) > float(actor.get("pathogenObservedHit",-1)):
			var attacker := game.entity(int(actor.get("lastAttacker",0)))
			notify_hit(actor,Vector2.ZERO if attacker.is_empty() else WarData.point(actor)-WarData.point(attacker))

## The host has already advanced state.time/tick. New adeno intents start AFTER
## old casts advance, so windup never accidentally inherits the previous tick.
func advance(_dt: float) -> bool:
	if _stepping: _error = "reentrant_step"; return false
	if not is_finite(_dt) or _dt < 0: _error = "invalid_delta"; return false
	if game.paused: return true
	var now := float(game.state.time); var tick := int(game.state.tick)
	if now < _last_time-EPS or tick < _last_tick: _error = "clock_reversed"; return false
	if tick == _last_tick and absf(now-_last_time) <= EPS: return _pending.is_empty()
	_stepping = true
	for actor in game.entities():
		if actor.kind == "adenovirus": _adeno(int(actor.id))
	for key in _adenos:
		var service: WarAdenovirusAttack = _adenos[key]
		var source := game.entity(int(key))
		var lane := int(source.get("vesselLane",0))
		if not service.advance_simulation(maxf(0,now-service.clock()),_world(lane)):
			_stepping = false; _error = service.last_error(); return false
	_observe()
	for key in _pending:
		var intent: Dictionary = _pending[key]; var source := game.entity(int(key)); var target := game.entity(int(intent.target))
		if source.is_empty() or source.hp <= 0 or int(source.get("orderToken",0)) != int(intent.orderToken) or not _eligible(source,target): continue
		var next := int(_sequences.get(key,0))+1
		if _adeno(int(key)).begin(source,Vector2(intent.aim[0],intent.aim[1]),next) > 0: _sequences[key] = next
	_pending.clear()
	pneumococcus.step(_dt)
	for key in _adenos:
		for event in _adenos[key].drain_events(): game.event("adenovirus_"+str(event.type),event)
	_last_time = now; _last_tick = tick; _stepping = false; _error = ""
	return true

func _adeno_geometry(a: Vector2,b: Vector2,lane: int,source: Dictionary,target: Dictionary,purpose: String) -> bool:
	var kind := str(target.kind) if purpose == "push" and not target.is_empty() else str(source.kind)
	if not game.navigation.clear_segment(a,b,lane,kind): return false
	for building in game.entities():
		if building.category != "building" or building.hp <= 0: continue
		if purpose == "target" and int(building.id) == int(target.get("id",0)): continue
		if building.has("checkpointId") and building.get("breached",false) and not building.get("isolated",false): continue
		var geometry := target_geometry(building,lane)
		if int(geometry.lane) != lane: continue
		var radius := float(geometry.radius)+(WarData.radius(kind) if purpose == "push" else 0.0)
		var rect := Rect2(geometry.point-Vector2.ONE*radius,Vector2.ONE*radius*2)
		if is_finite(WarPneumococcus._rect_t(a,b,rect)): return false
	if purpose == "push":
		var live := game.entity(int(target.get("id",0)))
		return not live.is_empty() and game._position_free(live,b)
	return true

func _damage(source: Dictionary,target: Dictionary,amount: float,raw: bool,cause: String,direction: Vector2) -> void:
	var actual := game.entity(int(target.id))
	if actual.is_empty() or actual.hp <= 0: return
	var hp := float(actual.hp)
	game.combat.damage(source,actual,amount,raw,cause,direction)
	if not is_same(actual,target):
		for field in ["hp","faction","lastAttacker","hitTime"]:
			if actual.has(field): target[field] = actual[field]
	if float(actual.hp) < hp: notify_hit(actual,direction)

func _adeno_damage(source: Dictionary,target: Dictionary,amount: float,info: Dictionary) -> void:
	_damage(source,target,amount,false,"adenovirus_slam",WarData.point(target)-Vector2(info.point[0],info.point[1]))

func _adeno_push(_source: Dictionary,target: Dictionary,delta: Vector2,_info: Dictionary) -> void:
	var actual := game.entity(int(target.id))
	if actual.is_empty() or actual.hp <= 0: return
	var push := delta*WarPlatelets.push_scale(actual)
	var pending: Dictionary = game.combat._knockbacks.get(int(actual.id),{"push":Vector2.ZERO,"limit":push.length()})
	pending.limit = maxf(float(pending.limit),push.length())
	pending.push = ((pending.push as Vector2)+push).limit_length(float(pending.limit))
	game.combat._knockbacks[int(actual.id)] = pending

func presentation(actor: Dictionary) -> Dictionary:
	if actor.kind == "adenovirus": return _adeno(int(actor.id)).presentation(int(actor.id))
	return {}

func projectiles() -> Array: return pneumococcus.projectiles()

## Runtime block only; take world snapshot at the same frame boundary.
func snapshot() -> Dictionary:
	if _stepping or not _pending.is_empty() or absf(float(game.state.time)-_last_time) > EPS or int(game.state.tick) != _last_tick:
		_error = "not_at_frame_boundary"; return {}
	var adenovirus: Dictionary = {}
	for key in _adenos: adenovirus[key] = _adenos[key].snapshot()
	return {"schema":SCHEMA,"time":_last_time,"tick":int(game.state.tick),"lastTick":_last_tick,
		"pneumococcus":pneumococcus.snapshot(),"adenovirus":adenovirus,"sequences":_sequences.duplicate(true),"acted":_acted.duplicate(true)}

static func _json_safe(value: Variant,depth := 0) -> bool:
	if depth > 12: return false
	if value == null or value is bool or value is String or value is int: return true
	if value is float: return is_finite(value)
	if value is Array:
		if value.size() > 4096: return false
		for item in value:
			if not _json_safe(item,depth+1): return false
		return true
	if value is Dictionary:
		if value.size() > 4096: return false
		for key in value:
			if not key is String or not _json_safe(value[key],depth+1): return false
		return true
	return false

static func validate_snapshot(value: Variant,world: Dictionary) -> String:
	if not value is Dictionary or not _json_safe(value): return "invalid_json"
	if not WarAdenovirusAttack._keys(value,["schema","time","tick","lastTick","pneumococcus","adenovirus","sequences","acted"]) or value.schema != SCHEMA: return "invalid_schema"
	if not WarPneumococcus._number(value.time,0,1000000000) or absf(float(value.time)-float(world.get("time",-1))) > EPS: return "world_clock_mismatch"
	if not WarPneumococcus._integer(value.tick) or int(value.tick) != int(world.get("tick",-1)) or value.lastTick != value.tick: return "world_tick_mismatch"
	for field in ["adenovirus","sequences","acted"]:
		if not value[field] is Dictionary or value[field].size() > 4096: return "invalid_actor_ledger"
	var error := WarPneumococcus.validate_state(value.pneumococcus)
	if not error.is_empty(): return error
	if world.get(WarPneumococcus.STATE_KEY,value.pneumococcus) != value.pneumococcus: return "pneumo_world_block_mismatch"
	var actors: Dictionary = world.get("entities",{})
	for actor in actors.values():
		if actor.get("kind","") != "pneumococcus": continue
		for field in ["pneumoShotAt","pneumoNextAttackAt","pneumoLastHitAt","pneumoHitAt","pneumoDeathAt"]:
			if actor.has(field) and not WarPneumococcus._number(actor[field],0,1000000000): return "invalid_pneumo_actor_time"
			if actor.has(field) and field != "pneumoNextAttackAt" and float(actor[field]) > float(value.time)+EPS: return "future_pneumo_actor_time"
		for field in ["pneumoFacingLeft","pneumoShotCancelled"]:
			if actor.has(field) and not actor[field] is bool: return "invalid_pneumo_actor_flag"
		if actor.has("pneumoHitSide") and actor.pneumoHitSide not in ["left","right"]: return "invalid_pneumo_hit_side"
		if actor.has("pneumoShotSpeed") and not WarPneumococcus._number(actor.pneumoShotSpeed,.01,32): return "invalid_pneumo_actor_speed"
		if actor.has("pneumoShotId") and not WarPneumococcus._integer(actor.pneumoShotId,1,int(value.pneumococcus.nextShotId)): return "invalid_pneumo_actor_shot"
	for cast in value.pneumococcus.casts.values():
		var actor: Dictionary = actors.get(str(int(cast.source)),{})
		if actor.get("kind","") != "pneumococcus" or float(actor.get("hp",0)) <= 0 or int(actor.get("orderToken",0)) != int(cast.orderToken) or int(actor.get("vesselLane",0)) != int(cast.lane): return "orphan_pneumo_cast"
		if float(cast.started) > float(value.time) or float(cast.releaseAt) <= float(value.time)+EPS or int(actor.get("pneumoShotId",0)) != int(cast.id): return "stale_pneumo_cast"
		var target: Dictionary = actors.get(str(int(cast.target)),{})
		if target.is_empty() or float(target.get("hp",0)) <= 0 or target.faction == actor.faction or float(actor.get("pneumoLastHitAt",-100)) >= float(cast.started): return "invalidated_pneumo_cast"
	for bullet in value.pneumococcus.projectiles.values():
		if float(bullet.born) > float(value.time) or float(bullet.expiresAt) <= float(value.time)+EPS or absf(float(bullet.lastUpdatedAt)-float(value.time)) > EPS: return "stale_pneumo_projectile"
	for field in ["sequences","acted"]:
		for key in value[field]:
			if not key is String or not key.is_valid_int() or str(int(key)) != key or int(key) <= 0 or not WarPneumococcus._integer(value[field][key]): return "invalid_ledger_id"
			if field == "acted" and int(value[field][key]) > int(value.tick): return "future_actor_tick"
			if field == "sequences" and not value.adenovirus.has(key): return "orphan_sequence"
	for key in value.adenovirus:
		if not key is String or not key.is_valid_int() or str(int(key)) != key or int(key) <= 0: return "invalid_adeno_id"
		var service := WarAdenovirusAttack.new()
		if not value.adenovirus[key] is Dictionary or not service.restore(value.adenovirus[key]) or absf(service.clock()-float(value.time)) > EPS: return "invalid_adeno_state"
		var records: Dictionary = value.adenovirus[key].sources
		if records.size() > 1 or (records.size() == 1 and not records.has(key)): return "mixed_adeno_sources"
		if int(value.sequences.get(key,0)) != int(records.get(key,{}).get("lastSequence",0)): return "sequence_mismatch"
		var cast: Dictionary = records.get(key,{}).get("cast",{})
		if not cast.is_empty():
			var actor: Dictionary = actors.get(key,{})
			if actor.get("kind","") != "adenovirus" or float(actor.get("hp",0)) <= 0 or int(actor.get("orderToken",0)) != int(cast.orderToken) or int(actor.get("vesselLane",0)) != int(cast.lane) or int(actor.get("faction",-1)) != int(cast.faction): return "orphan_adeno_cast"
			if WarData.point(actor).distance_to(Vector2(cast.origin[0],cast.origin[1])) > EPS: return "moved_adeno_cast"
	return ""

func restore(value: Variant) -> bool:
	if _stepping or not _pending.is_empty(): _error = "atomic_step_in_progress"; return false
	_error = validate_snapshot(value,game.state)
	if not _error.is_empty(): return false
	var restored: Dictionary = {}
	for key in value.adenovirus:
		var service := WarAdenovirusAttack.new(); service.restore(value.adenovirus[key])
		service.bind_world(_adeno_damage,_adeno_geometry,_adeno_push); restored[key] = service
	for service in _adenos.values(): service.bind_world(Callable(),Callable(),Callable())
	_adenos = restored; pneumococcus.restore(value.pneumococcus)
	_sequences = value.sequences.duplicate(true); _acted = value.acted.duplicate(true)
	_last_time = float(value.time); _last_tick = int(value.lastTick)
	return true

func dispose() -> void:
	for service in _adenos.values(): service.bind_world(Callable(),Callable(),Callable())
	_adenos.clear(); pneumococcus.game = null
	_host.combat.owner = null; _host.owner = null; _host.navigation = null
	game = null
