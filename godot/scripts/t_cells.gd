class_name WarTCells
extends RefCounted
## Independent T-cell runtime. No shared simulation/combat/config registration.
## Geometry/landing are required and fail closed. No actor/world references saved.
const SCHEMA := "cell-war-t-cells/1"
const EPS := .0000001
var _clock := 0.0
var _next_projectile := 1
var _actors: Dictionary = {}
var _projectiles: Array = []
var _events: Array = []
var _geometry := Callable()
var _landing := Callable()
var _damage := Callable()
var _radius := Callable()
var _multiplier := Callable()
var _target_geometry := Callable()
var _error := ""

static func data() -> Dictionary:
	return WarData.read("t_cell")

## geometry(from,to,lane,actor,purpose) -> bool, purpose = blink or knife.
## landing(point,lane,actor) -> bool, including terrain, buildings and units.
## damage(source,target,amount,direction); radius(target); multiplier(actor,field).
func bind_world(geometry: Callable,landing: Callable,damage := Callable(),radius := Callable(),multiplier := Callable(),target_geometry := Callable()) -> void:
	_geometry = geometry; _landing = landing; _damage = damage; _radius = radius; _multiplier = multiplier
	_target_geometry = target_geometry

func last_error() -> String:
	return _error

static func unit_record(id: int,faction: int,p: Vector2,lane := 0) -> Dictionary:
	return {"id":id,"kind":"t_cell","category":"unit","faction":faction,"x":p.x,"y":p.y,"vesselLane":lane,
		"hp":data().unitDefinition.hp,"maxHp":data().unitDefinition.hp,"orderToken":0,"statuses":{},"orders":[],"cargo":{},"queue":[],"cooldown":0.0}

func _state(e: Dictionary) -> Dictionary:
	var key := str(int(e.id))
	if not _actors.has(key):
		if _actors.size() >= int(data().limits.actors): return {}
		_actors[key] = {"mode":"idle","since":_clock,"nextBlinkAt":_clock,"sequence":0,"orderToken":int(e.get("orderToken",0)),
			"cooldown":0.0,"progress":0.0,"fired":false,"target":0,"rate":1.0,"route":[],"routeIndex":0,"needsRoute":false,"blink":{},"trail":[]}
	return _actors[key]

func set_route(e: Dictionary,approved_path: Array,sequence: int) -> bool:
	_error = ""
	if not _live_t(e) or sequence < 1: _error = "invalid_actor_or_sequence"; return false
	if not _geometry.is_valid() or not _landing.is_valid(): _error = "geometry_and_landing_required"; return false
	var s := _state(e)
	if s.is_empty(): _error = "actor_capacity"; return false
	if sequence <= int(s.sequence): _error = "stale_route"; return false
	var route: Array = []
	if approved_path.is_empty() or approved_path.size() > int(data().limits.pathPoints): _error = "invalid_route"; return false
	for waypoint in approved_path:
		if not waypoint is Dictionary or not _lane(waypoint.get("lane")): _error = "invalid_waypoint"; return false
		if waypoint.has("p") and not waypoint.p is Vector2: _error = "invalid_waypoint"; return false
		var p: Vector2 = waypoint.p if waypoint.get("p") is Vector2 else WarData.point(waypoint)
		if not _point(p) or not waypoint.has("p") and (not _number(waypoint.get("x")) or not _number(waypoint.get("y"))): _error = "invalid_waypoint"; return false
		route.append({"x":p.x,"y":p.y,"lane":int(waypoint.lane)})
	if s.mode != "hit": _idle(s)
	s.route = route; s.routeIndex = 0; s.sequence = sequence; s.orderToken = int(e.get("orderToken",0)); s.needsRoute = false
	return true

func stop(e: Dictionary) -> void:
	if not _valid_actor(e) or not _actors.has(str(int(e.id))): return
	var s: Dictionary = _actors[str(int(e.id))]
	s.route = []; s.routeIndex = 0; s.blink = {}; s.needsRoute = false
	if s.mode not in ["hit","dead"]: _idle(s)
	# nextBlinkAt is deliberately retained: stop/reorder never grants another burst.

func begin_attack(e: Dictionary,target: Dictionary) -> bool:
	_error = ""
	if not _live_t(e) or not _valid_actor(target) or float(target.hp) <= 0 or e.faction == target.faction: _error = "invalid_target"; return false
	if not _geometry.is_valid(): _error = "geometry_required"; return false
	var s := _state(e)
	if s.is_empty(): _error = "actor_capacity"; return false
	if s.mode in ["hit","dead","throw"] or s.mode == "blink" and _clock-float(s.since) < float(data().blink.arrival): _error = "busy"; return false
	if float(s.cooldown) > EPS: _error = "cooldown"; return false
	if not _aim_valid(e,target): _error = "range_lane_or_geometry"; return false
	s.route = []; s.routeIndex = 0; s.blink = {}; s.needsRoute = false
	s.mode = "throw"; s.since = _clock; s.progress = 0.0; s.fired = false; s.target = int(target.id)
	s.orderToken = int(e.get("orderToken",0)); s.cooldown = float(data().weapon.cooldown); s.rate = _rate(e,"attackSpeedMultiplier")
	e.shotTime = _clock; e.shotSpeed = s.rate; e.cooldown = s.cooldown; e.weaponHeading = (WarData.point(target)-WarData.point(e)).angle()
	_record("t_attack_start",{"source":e.id,"target":target.id})
	return true

func notify_hit(e: Dictionary,at := -1.0) -> void:
	if not _valid_actor(e) or e.kind != "t_cell": return
	var s := _state(e)
	if s.is_empty(): return
	var time := _clock if at < 0 else at
	s.route = []; s.routeIndex = 0; s.blink = {}; s.needsRoute = true; s.target = 0; s.fired = false; s.progress = 0.0
	if float(e.hp) <= 0:
		if s.mode != "dead": s.mode = "dead"; s.since = time; e.deathTime = time
	elif s.mode != "hit" or time-float(s.since) >= float(data().clips.tHit.duration): s.mode = "hit"; s.since = time

func advance(real_delta: float,entities: Array,paused := false,time_scale := 1.0) -> bool:
	if not _number(real_delta) or real_delta < 0 or not _number(time_scale) or time_scale < 0: _error = "invalid_delta"; return false
	if paused or time_scale == 0: return true
	return advance_simulation(real_delta*time_scale,entities)

func advance_simulation(delta: float,entities: Array) -> bool:
	if not _number(delta) or delta < 0 or delta > 60 or not is_finite(_clock+delta): _error = "invalid_delta"; return false
	if not _projectiles.is_empty() and not _geometry.is_valid(): _error = "geometry_required"; return false
	var world: Dictionary = {}
	for e in entities:
		if not e is Dictionary or not _valid_actor(e): continue
		var key := str(int(e.id))
		if world.has(key): _error = "duplicate_entity_id"; return false
		world[key] = e
		if e.kind == "t_cell" and _state(e).is_empty(): _error = "actor_capacity"; return false
	var left := delta
	while left > EPS:
		var dt := minf(left,float(data().limits.substep)); var end := _clock+dt
		# Existing impacts win over unreleased attacks in this substep.
		var advanced: Dictionary = {}
		for b in _projectiles.duplicate():
			advanced[int(b.id)] = true
			if not _move_projectile(b,end,world): _projectiles.erase(b)
		for key in _actors.keys():
			var s: Dictionary = _actors[key]
			if not world.has(key) or float(world[key].hp) <= 0 or world[key].kind != "t_cell":
				if s.mode != "dead": s.mode = "dead"; s.since = _clock; s.route = []; s.blink = {}; s.target = 0
				if end-float(s.since) >= float(data().clips.tDeath.duration): _actors.erase(key)
				continue
			_update_actor(world[key],s,dt,end,world)
		for b in _projectiles.duplicate():
			if not advanced.has(int(b.id)) and not _move_projectile(b,end,world): _projectiles.erase(b)
		_clock = end; left -= dt
		for s in _actors.values(): s.trail = s.trail.filter(func(t): return _clock-float(t.time) < float(data().blink.trailSeconds))
	_error = ""
	return true

func _update_actor(e: Dictionary,s: Dictionary,dt: float,end: float,world: Dictionary) -> void:
	if s.mode == "dead": return
	if int(e.get("orderToken",0)) != int(s.orderToken):
		stop(e); s.orderToken = int(e.get("orderToken",0)); s.needsRoute = true
	s.rate = _rate(e,"attackSpeedMultiplier")
	s.cooldown = maxf(0,float(s.cooldown)-dt*float(s.rate)); e.cooldown = s.cooldown; e.travelSpeed = 0.0
	if s.mode == "hit":
		e.combatState = "hit"
		if end-float(s.since) >= float(data().clips.tHit.duration): _idle(s)
		return
	if s.mode == "throw":
		e.combatState = "attack"
		var before := float(s.progress)
		s.progress = minf(float(data().clips.tThrow.duration),before+dt*float(s.rate))
		if not s.fired and float(s.progress)+EPS >= float(data().weapon.windup):
			s.fired = true # Commit once before emitting or calling any host callback.
			var target: Dictionary = world.get(str(int(s.target)),{})
			var at := _clock+(float(data().weapon.windup)-before)/maxf(EPS,float(s.rate))
			if not target.is_empty() and _aim_valid(e,target): _launch(e,target,at)
		if float(s.progress)+EPS >= float(data().clips.tThrow.duration): _idle(s)
		return
	if s.mode == "blink" and end-float(s.since)+EPS >= float(data().blink.cycle): _idle(s)
	if s.mode == "idle" and not s.route.is_empty() and _clock+EPS >= float(s.nextBlinkAt):
		s.mode = "blink"; s.since = _clock; s.nextBlinkAt = _clock+float(data().blink.cycle); s.blink = {}
	if s.mode != "blink": return
	e.combatState = "move"
	var elapsed := end-float(s.since)
	if elapsed+EPS < float(data().blink.departure): return
	if s.blink.is_empty() and not _plan_blink(e,s): return
	if s.blink.get("arrived",false): return
	var from := Vector2(s.blink.fromX,s.blink.fromY); var destination := Vector2(s.blink.toX,s.blink.toY)
	var t := clampf((elapsed-float(data().blink.departure))/(float(data().blink.arrival)-float(data().blink.departure)),0,1)
	var desired := from.lerp(destination,t*t*(3-2*t)); var p := WarData.point(e)
	var quota := minf(float(s.blink.allowance),_move_allowance(e))
	var next := p.move_toward(desired,maxf(0,quota-float(s.blink.spent)))
	if not _clear(p,destination,e,"blink") or not _land(destination,e) or not _clear(p,next,e,"blink") or not _land(next,e): _halt(s,"geometry_or_landing_changed",e); return
	var travelled := p.distance_to(next)
	if travelled > EPS:
		e.x = next.x; e.y = next.y; e.moveHeading = (next-p).angle(); e.travelSpeed = travelled/dt
		s.blink.spent = float(s.blink.spent)+travelled
		s.trail.append({"x":p.x,"y":p.y,"time":end,"frame":5})
		while s.trail.size() > int(data().blink.maxGhosts): s.trail.pop_front()
	if next.distance_squared_to(destination) <= EPS*EPS:
		s.routeIndex = int(s.blink.nextIndex); s.blink.arrived = true
		if int(s.routeIndex) >= s.route.size(): s.route = []; s.routeIndex = 0; s.blink.nextIndex = 0
		_record("t_blink_arrive",{"source":e.id,"x":e.x,"y":e.y},end)
	elif t >= 1-EPS or float(s.blink.spent)+EPS >= quota: _halt(s,"movement_budget_reduced",e)

func _plan_blink(e: Dictionary,s: Dictionary) -> bool:
	var origin := WarData.point(e); var cursor := origin; var budget := _move_allowance(e)
	var best := origin; var next_index := int(s.routeIndex); var reason := "new_route_required"
	for i in range(int(s.routeIndex),s.route.size()):
		var waypoint: Dictionary = s.route[i]
		if int(waypoint.lane) != int(e.vesselLane): reason = "lane_transition_required"; break
		var p := WarData.point(waypoint); var distance := cursor.distance_to(p)
		if distance <= EPS: next_index = i+1; continue
		var candidate := cursor.move_toward(p,minf(distance,budget))
		if not _clear(origin,candidate,e,"blink") or not _land(candidate,e): break
		best = candidate; next_index = i+1 if distance <= budget+EPS else i
		budget -= distance
		if budget <= EPS: break
		cursor = p
	if origin.distance_squared_to(best) <= EPS*EPS:
		if next_index >= s.route.size(): s.route = []; s.routeIndex = 0; _idle(s); return false
		_halt(s,reason,e); return false
	s.blink = {"fromX":origin.x,"fromY":origin.y,"toX":best.x,"toY":best.y,"nextIndex":next_index,
		"allowance":_move_allowance(e),"spent":0.0,"arrived":false}
	_record("t_blink_depart",{"source":e.id,"fromX":origin.x,"fromY":origin.y,"x":best.x,"y":best.y},float(s.since)+float(data().blink.departure))
	return true

func _move_allowance(e: Dictionary) -> float:
	return minf(float(data().radius)*2*float(data().blink.distanceInBodiesCap),float(data().unitDefinition.speed)*float(data().blink.cycle)*_rate(e,"moveMultiplier"))

func _halt(s: Dictionary,reason: String,e: Dictionary) -> void:
	s.route = []; s.routeIndex = 0; s.blink = {}; s.needsRoute = true; _idle(s)
	_record("t_route_required",{"source":e.id,"reason":reason})

static func _idle(s: Dictionary) -> void:
	s.mode = "idle"; s.target = 0; s.progress = 0.0; s.fired = false; s.blink = {}

func _rate(e: Dictionary,field: String) -> float:
	if not _multiplier.is_valid(): return 1.0
	var value: Variant = _multiplier.call(e,field)
	return clampf(float(value),0,32) if _number(value) else 0.0

func _clear(a: Vector2,b: Vector2,e: Dictionary,purpose: String) -> bool:
	return _geometry.is_valid() and bool(_geometry.call(a,b,int(e.get("vesselLane",0)),e.duplicate(true),purpose))

func _land(p: Vector2,e: Dictionary) -> bool:
	return _landing.is_valid() and bool(_landing.call(p,int(e.get("vesselLane",0)),e.duplicate(true)))

func _target_radius(e: Dictionary) -> float:
	var value: Variant = _radius.call(e) if _radius.is_valid() else e.get("radius",data().radius)
	return float(value) if _number(value) and float(value) > 0 else 0.0

func _aim_valid(e: Dictionary,target: Dictionary) -> bool:
	if not _valid_actor(target) or float(target.hp) <= 0 or e.faction == target.faction: return false
	var geometry := _target_shape(e,target)
	if not geometry.get("targetable",true) or int(e.vesselLane) != int(geometry.lane): return false
	var p: Vector2 = geometry.point
	var reach := float(data().weapon.range)+(float(geometry.radius) if target.category == "building" else 0.0)
	return WarData.point(e).distance_to(p) <= reach+EPS and not WarData.point(e).is_equal_approx(p) and _clear(WarData.point(e),p,e,"knife")

func _target_shape(source: Dictionary,target: Dictionary) -> Dictionary:
	if _target_geometry.is_valid():
		var shape: Variant = _target_geometry.call(source,target)
		if shape is Dictionary and shape.get("point") is Vector2 and shape.point.is_finite() and _lane(shape.get("lane")) and _number(shape.get("radius")):
			return shape
	return {"point":WarData.point(target),"lane":int(target.vesselLane),"radius":_target_radius(target),"blocks":target.get("blocksProjectiles",true)}

func _launch(e: Dictionary,target: Dictionary,at: float) -> void:
	if _projectiles.size() >= int(data().limits.projectiles) or _next_projectile >= 2147483647: return
	var direction := ((_target_shape(e,target).point as Vector2)-WarData.point(e)).normalized()
	var owner := {"id":int(e.id),"kind":"t_cell","category":"unit","faction":int(e.faction),"x":e.x,"y":e.y,"hp":1.0,"vesselLane":int(e.vesselLane),"statuses":{}}
	_projectiles.append({"id":_next_projectile,"source":owner,"x":e.x,"y":e.y,"launchX":e.x,"launchY":e.y,"dx":direction.x,"dy":direction.y,
		"born":at,"remaining":float(data().weapon.range)})
	e.weaponHeading = direction.angle()
	_record("t_knife_spawn",{"id":_next_projectile,"source":e.id,"target":target.id},at); _next_projectile += 1

func _move_projectile(b: Dictionary,end: float,world: Dictionary) -> bool:
	var start := maxf(_clock,float(b.born)); var speed := float(data().weapon.speed)
	var distance := minf(maxf(0,end-start)*speed,float(b.remaining)); var travelled := 0.0
	var p := WarData.point(b); var direction := Vector2(b.dx,b.dy)
	while distance > EPS:
		var length := minf(distance,float(data().limits.geometryStep)); var next := p+direction*length
		var hit: Dictionary = {}; var earliest := INF
		for target in world.values():
			if float(target.hp) <= 0 or int(target.id)==int(b.source.id): continue
			var shape := _target_shape(b.source,target)
			if int(shape.lane)!=int(b.source.vesselLane) or not shape.get("blocks",true): continue
			var building: bool = target.category == "building"
			if not building and target.faction==b.source.faction or building and not target.get("blocksProjectiles",true): continue
			var radius := float(shape.radius); var center: Vector2 = shape.point
			var range_limit := float(data().weapon.range)+(radius if building else 0.0)
			if Vector2(b.launchX,b.launchY).distance_to(center) > range_limit+EPS: continue
			var fraction := _box_contact(p,next,center,radius+float(data().weapon.radius)) if building else _circle_contact(p,next,center,radius+float(data().weapon.radius))
			if fraction >= 0 and (fraction < earliest-EPS or absf(fraction-earliest) <= EPS and (hit.is_empty() or int(target.id)<int(hit.id))): earliest = fraction; hit = target
		var stop := p.lerp(next,earliest) if not hit.is_empty() else next
		if not _clear(p,stop,b.source,"knife"):
			_projectiles.erase(b); _record("t_knife_blocked",{"id":b.id,"x":p.x,"y":p.y},start+travelled/speed); return false
		if not hit.is_empty():
			_projectiles.erase(b) # A save/event callback can never observe a consumed live knife.
			var at := start+(travelled+length*earliest)/speed
			if hit.faction != b.source.faction:
				var source: Dictionary = world.get(str(int(b.source.id)),b.source)
				if _damage.is_valid(): _damage.call(source,hit,float(data().weapon.damage),direction)
				else: hit.hp = maxf(0,float(hit.hp)-float(data().weapon.damage))
				if hit.kind == "t_cell": notify_hit(hit,at)
			_record("t_knife_impact",{"id":b.id,"target":hit.id,"blockedByAlly":hit.faction==b.source.faction,"x":stop.x,"y":stop.y},at)
			return false
		p = next; distance -= length; travelled += length
	b.x = p.x; b.y = p.y; b.remaining = maxf(0,float(b.remaining)-travelled)
	return float(b.remaining) > EPS

static func _circle_contact(a: Vector2,b: Vector2,p: Vector2,radius: float) -> float:
	var d := b-a; var offset := a-p; var c := offset.length_squared()-radius*radius
	if c <= 0: return 0.0
	var aa := d.length_squared(); var bb := 2*offset.dot(d); var disc := bb*bb-4*aa*c
	if aa <= EPS*EPS or disc < 0: return -1.0
	var t := (-bb-sqrt(disc))/(2*aa)
	return t if t >= 0 and t <= 1 else -1.0

static func _box_contact(a: Vector2,b: Vector2,p: Vector2,radius: float) -> float:
	var low := 0.0; var high := 1.0; var d := b-a
	for axis in 2:
		if absf(d[axis]) <= EPS:
			if absf(a[axis]-p[axis]) > radius: return -1.0
		else:
			var enter := (p[axis]-radius-a[axis])/d[axis]; var leave := (p[axis]+radius-a[axis])/d[axis]
			low = maxf(low,minf(enter,leave)); high = minf(high,maxf(enter,leave))
			if high < low: return -1.0
	return low

func sample(e: Dictionary,at := -1.0) -> Dictionary:
	var time := _clock if at < 0 else at
	var s: Dictionary = _actors.get(str(int(e.id)),{})
	if s.is_empty(): return sample_state({"mode":"dead" if float(e.get("hp",1))<=0 else "idle","since":float(e.get("deathTime",e.get("died",time)))},time)
	var state := s.duplicate(true)
	if state.mode == "throw": state.progress = maxf(0,float(s.progress)+(time-_clock)*float(s.rate))
	var result := sample_state(state,time)
	result.afterimages = state.trail.filter(func(t): return time >= float(t.time) and time-float(t.time) < float(data().blink.trailSeconds))
	return result

static func sample_state(s: Dictionary,time: float) -> Dictionary:
	var mode: String = s.get("mode","idle"); var key := {"blink":"tBlink","throw":"tThrow","hit":"tHit","dead":"tDeath"}.get(mode,"tBlink")
	var clip: Dictionary = data().clips[key]
	var elapsed := float(s.get("progress",0)) if mode == "throw" else maxf(0,time-float(s.get("since",time)))
	if mode == "idle": elapsed = 0
	var frame: int = clip.durations.size()-1; var end := 0.0
	for i in clip.durations.size():
		end += float(clip.durations[i])
		if elapsed < end-EPS: frame = i; break
	return {"key":key,"clip":clip,"frame":frame,"family":"t_cell","hidden":mode=="dead" and elapsed+EPS>=float(clip.duration) or mode=="blink" and data().blink.hiddenFrames.any(func(i): return int(i)==frame),
		"bodyRect":clip.get("bodyRects",[])[frame] if clip.has("bodyRects") else {},"afterimages":[]}

func state_for(id: int) -> Dictionary:
	return _actors.get(str(id),{}).duplicate(true)

func projectiles() -> Array:
	return _projectiles.duplicate(true)

func drain_events() -> Array:
	var copy := _events.duplicate(true); _events.clear(); return copy

func _record(kind: String,fields: Dictionary,at := -1.0) -> void:
	var entry := fields.duplicate(true); entry.kind = kind; entry.time = _clock if at < 0 else at
	_events.append(entry)
	while _events.size() > int(data().limits.events): _events.pop_front()

func snapshot() -> Dictionary:
	return {"schema":SCHEMA,"clock":_clock,"nextProjectileId":_next_projectile,"actors":_actors.duplicate(true),"projectiles":_projectiles.duplicate(true)}

func restore(value: Dictionary) -> bool:
	if not validate_snapshot(value).is_empty(): _error = "invalid_snapshot"; return false
	_clock = float(value.clock); _next_projectile = int(value.nextProjectileId)
	_actors = value.actors.duplicate(true); _projectiles = value.projectiles.duplicate(true); _events.clear(); _error = ""
	return true

static func validate_snapshot(value: Dictionary) -> String:
	if value.get("schema","") != SCHEMA or not _number(value.get("clock")) or float(value.clock)<0 or not _id(value.get("nextProjectileId")): return "invalid_header"
	if not value.get("actors") is Dictionary or not value.get("projectiles") is Array or value.actors.size()>int(data().limits.actors) or value.projectiles.size()>int(data().limits.projectiles): return "invalid_collections"
	for key in value.actors:
		if not key is String or not key.is_valid_int() or str(int(key))!=key or not _id(int(key)) or not value.actors[key] is Dictionary: return "invalid_actor_key"
		var s: Dictionary = value.actors[key]
		if s.get("mode","") not in ["idle","blink","throw","hit","dead"]: return "invalid_mode"
		for field in ["since","nextBlinkAt","cooldown","progress","rate"]:
			if not _number(s.get(field)) or float(s[field])<0: return "invalid_actor_number"
		if float(s.since)>float(value.clock)+EPS or float(s.cooldown)>float(data().weapon.cooldown)+EPS or float(s.progress)>float(data().clips.tThrow.duration)+EPS or float(s.rate)>32: return "invalid_actor_time"
		for field in ["sequence","orderToken","routeIndex","target"]:
			if not _integer(s.get(field),0,2147483647): return "invalid_actor_integer"
		if not s.get("fired") is bool or not s.get("needsRoute") is bool or not s.get("route") is Array or not s.get("trail") is Array or not s.get("blink") is Dictionary: return "invalid_actor_state"
		if s.route.size()>int(data().limits.pathPoints) or int(s.routeIndex)>s.route.size() or s.trail.size()>int(data().blink.maxGhosts): return "invalid_path_size"
		if s.mode=="throw" and (int(s.target)<=0 or bool(s.fired)!=(float(s.progress)+EPS>=float(data().weapon.windup))): return "invalid_release_commit"
		for p in s.route:
			if not p is Dictionary or not _number(p.get("x")) or not _number(p.get("y")) or not _point(WarData.point(p)) or not _lane(p.get("lane")): return "invalid_waypoint"
		for t in s.trail:
			if not t is Dictionary or not _number(t.get("x")) or not _number(t.get("y")) or not _point(WarData.point(t)) or not _number(t.get("time")) or float(t.time)<0 or float(t.time)>float(value.clock)+EPS or not _integer(t.get("frame"),0,15): return "invalid_trail"
		if not s.blink.is_empty():
			for field in ["fromX","fromY","toX","toY","allowance","spent"]:
				if not _number(s.blink.get(field)) or float(s.blink[field])<0: return "invalid_blink_number"
			if not _point(Vector2(s.blink.toX,s.blink.toY)) or not _point(Vector2(s.blink.fromX,s.blink.fromY)) or not _integer(s.blink.get("nextIndex"),0,s.route.size()) or not s.blink.get("arrived") is bool: return "invalid_blink"
			if float(s.blink.spent)>float(s.blink.allowance)+.001 or float(s.blink.allowance)>float(data().radius)*2*float(data().blink.distanceInBodiesCap)+EPS: return "invalid_blink_budget"
	var ids: Dictionary = {}
	for b in value.projectiles:
		if not b is Dictionary or not _id(b.get("id")) or int(b.id)>=int(value.nextProjectileId) or ids.has(int(b.id)): return "invalid_projectile_id"
		ids[int(b.id)] = true
		for field in ["x","y","launchX","launchY","dx","dy","born","remaining"]:
			if not _number(b.get(field)): return "invalid_projectile_number"
		if not _point(WarData.point(b)) or not _point(Vector2(b.launchX,b.launchY)) or float(b.born)<0 or float(b.born)>float(value.clock)+EPS or float(b.remaining)<=0 or float(b.remaining)>float(data().weapon.range)+EPS: return "invalid_projectile_position"
		if absf(Vector2(b.dx,b.dy).length_squared()-1)>EPS*10 or not b.get("source") is Dictionary or not _valid_actor(b.source) or b.source.kind!="t_cell": return "invalid_projectile_source"
	return ""

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _integer(value: Variant,low: int,high: int) -> bool:
	return _number(value) and float(value)>=low and float(value)<=high and floorf(float(value))==float(value)

static func _id(value: Variant) -> bool:
	return _integer(value,1,2147483647)

static func _lane(value: Variant) -> bool:
	return _integer(value,0,211)

static func _point(p: Vector2) -> bool:
	return p.is_finite() and p.x>=0 and p.y>=0 and p.x<=2048 and p.y<=4096

static func _valid_actor(e: Dictionary) -> bool:
	return _id(e.get("id")) and e.get("kind") is String and e.get("category","") in ["unit","building"] and _number(e.get("hp")) and float(e.hp)>=0 and _number(e.get("x")) and _number(e.get("y")) and _point(WarData.point(e)) and _lane(e.get("vesselLane",0)) and _integer(e.get("faction"),0,3)

static func _live_t(e: Dictionary) -> bool:
	return _valid_actor(e) and e.kind=="t_cell" and e.category=="unit" and float(e.hp)>0 and _integer(e.get("orderToken",0),0,2147483647)
