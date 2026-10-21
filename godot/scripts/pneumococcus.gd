class_name WarPneumococcus
extends RefCounted
## Independent delayed-spit service. Public simulation/combat hooks are a separate merge.
const STATE_KEY := "pneumococcusCombat"
const LIMIT := 128
const HISTORY_LIMIT := 64
const EPS := .000001
var game
var _stepping := false

func _init(owner) -> void:
	game = owner
	state()

static func data() -> Dictionary:
	return WarData.read("pneumococcus")

static func fresh_state() -> Dictionary:
	return {"version":1,"nextShotId":0,"resolvedThrough":0,"casts":{},"projectiles":{},"finished":{},"recent":[]}

func state() -> Dictionary:
	if not game.state.has(STATE_KEY): game.state[STATE_KEY] = fresh_state()
	return game.state[STATE_KEY]

func now() -> float:
	return float(game.state.time)

func _emit(kind: String,fields: Dictionary) -> void:
	if game.has_method("event"): game.event(kind,fields)

func is_casting(e: Dictionary) -> bool:
	return state().casts.values().any(func(c): return int(c.source) == int(e.get("id",0)))

func _target_geometry(target: Dictionary,lane: int) -> Dictionary:
	# The existing combat adapter exposes a checkpoint's endpoint on this lane.
	# A gate's other endpoint is never an implicit cross-lane projectile passage.
	if game.combat.has_method("_target_geometry"):
		return game.combat._target_geometry(target,lane)
	return {"point":WarData.point(target),"lane":int(target.get("vesselLane",0)),
		"radius":float(WarData.spec(target.kind).get("size",2))*.5 if target.get("category","") == "building" else 0.0}

func _valid_target(e: Dictionary,target: Dictionary) -> bool:
	if target.is_empty() or float(target.get("hp",0)) <= 0 or e.faction == target.faction: return false
	var lane := int(e.get("vesselLane",0))
	var geometry := _target_geometry(target,lane)
	if lane != int(geometry.lane): return false
	if WarData.point(e).distance_squared_to(geometry.point) > pow(float(data().unit.range),2)+EPS: return false
	return game.navigation.clear_segment(WarData.point(e),geometry.point,lane,"pneumococcus")

func try_attack(e: Dictionary,target: Dictionary) -> bool:
	if game.paused or e.get("kind","") != "pneumococcus" or float(e.get("hp",0)) <= 0: return false
	if now()+EPS < float(e.get("pneumoNextAttackAt",0)) or is_casting(e): return false
	if now()-float(e.get("pneumoLastHitAt",-100)) < float(data().clips.pnHitRight.duration)-EPS: return false
	if state().casts.size()+state().projectiles.size()+state().finished.size() >= LIMIT or not _valid_target(e,target): return false
	var rate := 1.0
	if game.combat.has_method("multiplier"): rate = clampf(float(game.combat.multiplier(e,"attackSpeedMultiplier")),.01,32)
	var damage := float(e.get("attackDamage",data().unit.damage))
	if damage <= 0: return false
	var s := state()
	s.nextShotId = int(s.nextShotId)+1
	var id: int = s.nextShotId
	s.casts[str(id)] = {"id":id,"phase":"pending","source":int(e.id),"target":int(target.id),
		"started":now(),"releaseAt":now()+float(data().projectile.windup)/rate,
		"shotSpeed":rate,"damage":damage,"orderToken":int(e.get("orderToken",0)),"lane":int(e.get("vesselLane",0))}
	e.pneumoShotAt = now(); e.pneumoShotSpeed = rate; e.pneumoShotId = id
	e.pneumoShotCancelled = false; e.pneumoCastState = "pending"
	e.pneumoNextAttackAt = now()+float(data().unit.cool)/rate
	e.combatState = "attack"
	var aim: Vector2 = _target_geometry(target,int(e.get("vesselLane",0))).point-WarData.point(e)
	if absf(aim.x) > EPS: e.pneumoFacingLeft = aim.x < 0
	e.weaponHeading = aim.angle(); e.weaponTarget = target.id; e.weaponTargetTime = now()
	_emit("pneumococcus_cast",{"source":e.id,"target":target.id,"shot":id})
	return true

func notify_hit(e: Dictionary,push_direction := Vector2.ZERO) -> void:
	if e.get("kind","") != "pneumococcus": return
	e.pneumoLastHitAt = now()
	if now()-float(e.get("pneumoHitAt",-100)) >= float(data().clips.pnHitRight.duration)-EPS:
		e.pneumoHitAt = now()
		# push_direction is attacker -> victim in rendered/local horizontal convention.
		var from_x: float = -push_direction.x*(-1 if e.get("pneumoFacingLeft",false) else 1)
		if absf(from_x) > EPS: e.pneumoHitSide = "left" if from_x < 0 else "right"
		elif not e.has("pneumoHitSide"): e.pneumoHitSide = "right"
	cancel_for_unit(e,"hit")

func notify_death(e: Dictionary) -> void:
	if e.get("kind","") != "pneumococcus": return
	if not e.has("pneumoDeathAt"): e.pneumoDeathAt = now()
	cancel_for_unit(e,"death") # Already-fired projectiles continue independently.

func cancel_for_unit(e: Dictionary,reason := "order") -> void:
	for key in state().casts.keys():
		var cast: Dictionary = state().casts[key]
		if int(cast.source) == int(e.get("id",0)):
			e.pneumoShotCancelled = true; e.pneumoCastState = "cancelled"
			_finish(int(cast.id),"cancelled",{"reason":reason,"source":int(cast.source)})

func _finish(id: int,outcome: String,fields: Dictionary = {}) -> void:
	var s := state(); var key := str(id)
	if id <= int(s.resolvedThrough) or s.finished.has(key): return
	s.casts.erase(key); s.projectiles.erase(key); s.finished[key] = outcome
	var record := fields.duplicate(true)
	record["id"] = id; record["outcome"] = outcome; record["time"] = now()
	s.recent.append(record)
	while s.recent.size() > HISTORY_LIMIT: s.recent.pop_front()
	while s.finished.has(str(int(s.resolvedThrough)+1)):
		s.finished.erase(str(int(s.resolvedThrough)+1)); s.resolvedThrough = int(s.resolvedThrough)+1
	_emit("pneumococcus_"+outcome,record)

func step(_dt := 0.0) -> void:
	if game.paused or _stepping: return
	_stepping = true
	var s := state()
	for key in s.casts.keys():
		if not s.casts.has(key): continue
		var cast: Dictionary = s.casts[key]
		var e: Dictionary = game.entity(int(cast.source))
		var target: Dictionary = game.entity(int(cast.target))
		var valid := not e.is_empty() and float(e.get("hp",0)) > 0
		valid = valid and int(e.get("orderToken",0)) == int(cast.orderToken) and int(e.get("vesselLane",0)) == int(cast.lane)
		if valid: valid = float(e.get("pneumoLastHitAt",-100)) < float(cast.started) and _valid_target(e,target)
		if not valid:
			if not e.is_empty(): e.pneumoShotCancelled = true; e.pneumoCastState = "cancelled"
			_finish(int(cast.id),"cancelled",{"source":int(cast.source),"reason":"invalidated"})
			continue
		if now()+EPS < float(cast.releaseAt): continue
		var delta: Vector2 = _target_geometry(target,int(cast.lane)).point-WarData.point(e)
		if delta.length_squared() < EPS:
			_finish(int(cast.id),"cancelled",{"reason":"zero_aim"}); e.pneumoShotCancelled = true; e.pneumoCastState = "cancelled"
			continue
		var direction := delta.normalized()
		var origin := WarData.point(e)
		var muzzle := origin+direction*minf(float(data().projectile.muzzleDistance),delta.length()*.5)
		if not game.navigation.clear_segment(origin,muzzle,int(cast.lane),"pneumococcus"):
			_finish(int(cast.id),"cancelled",{"reason":"muzzle_blocked"}); e.pneumoShotCancelled = true; e.pneumoCastState = "cancelled"
			continue
		var born: float = cast.releaseAt
		s.projectiles[key] = {"id":int(cast.id),"phase":"flying","source":int(e.id),"sourceKind":"pneumococcus",
			"faction":int(e.faction),"x":muzzle.x,"y":muzzle.y,"dx":direction.x,"dy":direction.y,
			"speed":float(data().projectile.speed),"radius":float(data().projectile.radius),"damage":float(cast.damage),
			"vesselLane":int(cast.lane),"born":born,"expiresAt":born+float(data().projectile.ttl),
			"lastUpdatedAt":born,"style":"pneumococcus_kernel"}
		s.casts.erase(key); e.pneumoCastState = "released"
		_emit("pneumococcus_projectile_spawn",{"shot":int(cast.id),"source":e.id,"target":target.id})
	for key in s.projectiles.keys():
		if s.projectiles.has(key): _advance_projectile(s.projectiles[key])
	_stepping = false

static func _circle_t(a: Vector2,b: Vector2,center: Vector2,radius: float) -> float:
	var offset := a-center; var delta := b-a
	var c := offset.length_squared()-radius*radius
	if c <= 0: return 0.0
	var aa := delta.length_squared()
	if aa <= EPS: return INF
	var bb := offset.dot(delta); var disc := bb*bb-aa*c
	if disc < 0: return INF
	var t := (-bb-sqrt(disc))/aa
	return t if t >= 0 and t <= 1 else INF

static func _rect_t(a: Vector2,b: Vector2,rect: Rect2) -> float:
	var enter := 0.0; var leave := 1.0; var delta := b-a
	for axis in 2:
		var low: float = rect.position[axis]; var high: float = rect.end[axis]
		if absf(delta[axis]) < EPS:
			if a[axis] < low or a[axis] > high: return INF
		else:
			var t1: float = (low-a[axis])/delta[axis]; var t2: float = (high-a[axis])/delta[axis]
			enter = maxf(enter,minf(t1,t2)); leave = minf(leave,maxf(t1,t2))
			if enter > leave: return INF
	return enter

func _first_hit(a: Vector2,b: Vector2,bullet: Dictionary) -> Dictionary:
	var nearest := INF; var result: Dictionary = {}
	for target in game.entities():
		if float(target.get("hp",0)) <= 0 or int(target.get("id",0)) == int(bullet.source): continue
		var geometry := _target_geometry(target,int(bullet.vesselLane))
		if int(geometry.lane) != int(bullet.vesselLane): continue
		var building: bool = target.get("category","") == "building"
		if not building and (target.get("category","") != "unit" or int(target.faction) == int(bullet.faction)): continue
		var t := INF
		if building:
			var half := float(target.collisionSize)*.5 if target.has("collisionSize") else float(geometry.radius)
			t = _rect_t(a,b,Rect2(geometry.point-Vector2.ONE*half,Vector2.ONE*half*2).grow(float(bullet.radius)))
		else:
			var radius: float = data().body.radius if target.kind == "pneumococcus" else WarData.radius(target.kind)
			t = _circle_t(a,b,geometry.point,radius+float(bullet.radius))
		if is_finite(t) and (t < nearest-EPS or (is_equal_approx(t,nearest) and (result.is_empty() or int(target.id) < int(result.target.id)))):
			nearest = t; result = {"target":target,"t":t}
	return result

func _advance_projectile(bullet: Dictionary) -> void:
	var end := minf(now(),float(bullet.expiresAt))
	var travel := maxf(0,end-float(bullet.lastUpdatedAt))*float(bullet.speed)
	var direction := Vector2(bullet.dx,bullet.dy)
	var position := WarData.point(bullet)
	while travel > EPS:
		var distance := minf(.15,travel); var next := position+direction*distance
		var clear: bool = game.navigation.clear_segment(position,next,int(bullet.vesselLane),"pneumococcus")
		var wall_t := 1.0
		if not clear:
			var low := 0.0; var high := 1.0
			for _i in 12:
				var mid := (low+high)*.5
				if game.navigation.clear_segment(position,position.lerp(next,mid),int(bullet.vesselLane),"pneumococcus"): low = mid
				else: high = mid
			wall_t = low
		var hit := _first_hit(position,next,bullet)
		if not hit.is_empty() and float(hit.t) <= wall_t+EPS:
			var target: Dictionary = hit.target
			if int(target.faction) != int(bullet.faction):
				var source: Dictionary = game.entity(int(bullet.source))
				if source.is_empty(): source = {"id":int(bullet.source),"kind":"pneumococcus","faction":int(bullet.faction),"x":position.x,"y":position.y,"statuses":{}}
				# Consume first: damage callbacks, nested steps and callback-time saves
				# must never observe a live projectile that already dealt damage.
				_finish(int(bullet.id),"hit",{"source":int(bullet.source),"target":int(target.id)})
				var hp_before := float(target.hp)
				game.combat.damage(source,target,float(bullet.damage),false,"projectile",direction)
				if target.kind == "pneumococcus" and float(target.hp) < hp_before:
					if float(target.hp) <= 0: notify_death(target)
					else: notify_hit(target,direction)
			else: _finish(int(bullet.id),"blocked",{"target":int(target.id),"reason":"friendly_building"})
			return
		if not clear:
			_finish(int(bullet.id),"blocked",{"reason":"wall"}); return
		position = next; travel -= distance
	bullet.x = position.x; bullet.y = position.y; bullet.lastUpdatedAt = end
	if now()+EPS >= float(bullet.expiresAt): _finish(int(bullet.id),"expired")

func projectiles() -> Array:
	return state().projectiles.values().duplicate(true) # Renderer copy; never add these to generic combatProjectiles.

func snapshot() -> Dictionary:
	return state().duplicate(true)

func restore(value: Variant) -> String:
	var error := validate_state(value)
	if error.is_empty(): game.state[STATE_KEY] = value.duplicate(true)
	return error

static func _number(v: Variant,low: float,high: float) -> bool:
	return (v is int or v is float) and is_finite(float(v)) and float(v) >= low and float(v) <= high

static func _integer(v: Variant,low := 0,high := 1000000000) -> bool:
	return _number(v,low,high) and float(v) == float(int(v))

static func _json_safe(value: Variant,depth := 0) -> bool:
	if depth > 8: return false
	if value == null or value is bool or value is String or value is int: return true
	if value is float: return is_finite(value)
	if value is Array:
		if value.size() > 256: return false
		for child in value:
			if not _json_safe(child,depth+1): return false
		return true
	if value is Dictionary:
		if value.size() > 256: return false
		for key in value:
			if not key is String or not _json_safe(value[key],depth+1): return false
		return true
	return false

static func validate_state(value: Variant) -> String:
	if not _json_safe(value): return "吐核状态包含非规范JSON值"
	if not value is Dictionary or value.get("version",0) != 1: return "肺炎链球菌状态版本无效"
	if not _integer(value.get("nextShotId")) or not _integer(value.get("resolvedThrough")): return "吐核编号无效"
	var serial := int(value.nextShotId); var through := int(value.resolvedThrough)
	if through > serial: return "吐核完成游标无效"
	for field in ["casts","projectiles","finished"]:
		if not value.get(field) is Dictionary or value[field].size() > LIMIT: return "吐核队列无效"
	if value.casts.size()+value.projectiles.size()+value.finished.size() > LIMIT: return "吐核活动数量无效"
	if value.finished.has(str(through+1)): return "吐核完成游标未归并"
	if not value.get("recent") is Array or value.recent.size() > HISTORY_LIMIT: return "吐核历史无效"
	var ids: Array[int] = []; var sources: Dictionary = {}
	for field in ["casts","projectiles","finished"]:
		for key in value[field]:
			if not key is String or not key.is_valid_int() or str(int(key)) != key: return "吐核键无效"
			var id := int(key)
			if id <= through or id > serial or ids.has(id): return "吐核阶段重复或重播"
			ids.append(id)
			var item: Variant = value[field][key]
			if field == "finished":
				if not item in ["hit","blocked","expired","cancelled"]: return "吐核结果无效"
				continue
			if not item is Dictionary or item.get("id",0) != id: return "吐核对象无效"
			if not _integer(item.get("source"),1) or not _number(item.get("damage"),0,1000000): return "吐核来源或伤害无效"
			if field == "casts":
				if item.get("phase","") != "pending" or not _integer(item.get("target"),1) or not _integer(item.get("orderToken")): return "吐核蓄力无效"
				if not _integer(item.get("lane"),0,4096) or not _number(item.get("shotSpeed"),.01,32): return "吐核蓄力速度或平面无效"
				if not _number(item.get("started"),0,1000000000) or not _number(item.get("releaseAt"),0,1000000000): return "吐核时间无效"
				if absf(float(item.releaseAt)-float(item.started)-float(data().projectile.windup)/float(item.shotSpeed)) > EPS: return "吐核发射时刻无效"
				if sources.has(str(item.source)): return "同一单位重复蓄力"
				sources[str(item.source)] = true
			else:
				if item.get("phase","") != "flying" or item.get("sourceKind","") != "pneumococcus" or item.get("style","") != "pneumococcus_kernel": return "吐核弹体类型无效"
				for field_name in ["x","y","dx","dy","born","expiresAt","lastUpdatedAt"]:
					if not _number(item.get(field_name),-1000000000,1000000000): return "吐核弹体数值无效"
				if not _integer(item.get("faction"),1,16) or not _integer(item.get("vesselLane"),0,4096): return "吐核阵营或平面无效"
				if not _number(item.get("speed"),.01,200) or not _number(item.get("radius"),.001,2): return "吐核弹速或半径无效"
				if absf(Vector2(item.dx,item.dy).length_squared()-1) > .0001: return "吐核方向无效"
				if float(item.born) < 0 or absf(float(item.expiresAt)-float(item.born)-float(data().projectile.ttl)) > EPS: return "吐核寿命无效"
				if float(item.lastUpdatedAt) < float(item.born) or float(item.lastUpdatedAt) > float(item.expiresAt)+EPS: return "吐核推进时间无效"
	ids.sort()
	if ids.size() != serial-through: return "吐核阶段有缺口"
	for i in ids.size():
		if ids[i] != through+i+1: return "吐核阶段有缺口"
	var history_ids: Dictionary = {}
	for item in value.recent:
		if not item is Dictionary or not _integer(item.get("id"),1,serial) or not _number(item.get("time"),0,1000000000) or not item.get("outcome","") in ["hit","blocked","expired","cancelled"]: return "吐核历史记录无效"
		var key := str(int(item.id))
		if history_ids.has(key) or value.casts.has(key) or value.projectiles.has(key): return "吐核历史与活动阶段冲突"
		if int(item.id) > through and value.finished.get(key,"") != item.outcome: return "吐核历史与终止结果冲突"
		history_ids[key] = true
	return ""
