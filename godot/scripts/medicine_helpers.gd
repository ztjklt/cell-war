class_name WarMedicineHelpers
extends RefCounted
## One real fever/pain-relief helper type. Supply owns purchase/deployment.
const KIND := "fever_pain_relief"
var game: WarSimulation
var bubbles := WarMedicineBubbles.new()
var impacts: Array = []


func _init(owner: WarSimulation) -> void:
	game = owner
	_bind()


static func data() -> Dictionary:
	return WarData.read("medicine_helpers")


func enabled() -> bool:
	return game != null and game.life.enabled() and game.mode == "fullbody" and not game.is_campaign()


func _bind() -> void:
	bubbles.bind_world(
		func(source, target, amount, cause): game.combat.damage(source, target, amount, true, cause),
		func(a, b, lane, source): return game.navigation.clear_segment(a, b, lane, source.kind) and game.navigation.movement_clear(a, b, source.kind, int(source.faction)),
		func(target): return WarData.radius(target.kind))


func begin() -> void:
	bubbles.bind_world(Callable(), Callable())
	bubbles = WarMedicineBubbles.new(); _bind(); impacts.clear()
	game.state.medicineRuntime = {"version":1, "bubbles":bubbles.snapshot()}


func reset() -> void:
	bubbles.bind_world(Callable(), Callable())
	bubbles = WarMedicineBubbles.new(); _bind(); impacts.clear()
	if game.state.get("medicineRuntime") is Dictionary:
		game.state.medicineRuntime.version = int(game.state.medicineRuntime.version)
		if not bubbles.restore(game.state.medicineRuntime.bubbles): push_error("Invalid medicine runtime after validated restore")
	for e in game.entities():
		if e.kind != KIND: continue
		e.medicineSequence = int(e.get("medicineSequence", 0))
		e.medicineWorker = int(e.get("medicineWorker", 0))
		if e.get("medicineAttack") is Dictionary:
			for key in ["sequence", "target", "orderToken"]: e.medicineAttack[key] = int(e.medicineAttack[key])


func capture() -> void:
	if not enabled() or not game.state.has("medicineRuntime"): return
	bubbles.advance_simulation(0.0, game.entities())
	game.state.medicineRuntime.bubbles = bubbles.snapshot()


func before_step(dt: float) -> void:
	if not enabled(): return
	if not game.state.has("medicineRuntime"): begin()
	bubbles.advance_simulation(dt, game.entities())
	for event in bubbles.drain_events():
		if event.kind in ["bubble_impact", "bubble_blocked"]:
			impacts.append({"x":event.x, "y":event.y, "born":float(game.state.time), "vesselLane":int(event.get("vesselLane", 0))})
		game.event("medicine_" + str(event.kind), event)
	while impacts.size() > 128: impacts.pop_front()
	impacts = impacts.filter(func(effect): return float(game.state.time) - float(effect.born) < float(data().projectileVisual.impactSeconds))


func speed_multiplier(e: Dictionary) -> float:
	return bubbles.speed_multiplier(e) if enabled() else 1.0


func find_placement(worker: Dictionary) -> Dictionary:
	var fail := {"ok":false, "reason":"红细胞附近没有可用的组织落点"}
	if not enabled() or game.navigation.ground_mode or int(worker.get("vesselLane", -1)) != 0: return fail
	var origin := WarData.point(worker)
	var organ := game.navigation.organ_at(origin, "worker")
	if organ.is_empty() or not game.navigation.point_allowed(origin, 0, "worker"): return fail
	var radius := float(data().tuning.deploymentRadius)
	for ring in [1.5, 2.0, 2.5, 3.0]:
		if float(ring) > radius: continue
		for index in 24:
			var p := origin + Vector2.from_angle(float(index) * TAU / 24.0) * float(ring)
			if not _fits(p, organ): continue
			if not game.navigation.clear_segment(origin, p, 0, KIND) or not game.navigation.movement_clear(origin, p, KIND, int(worker.faction)): continue
			return {"ok":true, "reason":"", "organ":organ, "x":p.x, "y":p.y}
	return fail


func _fits(p: Vector2, organ: String) -> bool:
	if game.navigation.organ_at(p, KIND) != organ or not game.navigation.point_allowed(p, 0, KIND): return false
	# The selected navigation profile already owns tissue clearance. Do not inflate
	# its certified rings a second time; ordinary units use the same point contract.
	var radius := WarData.radius(KIND)
	for other in game.entities():
		if float(other.hp) <= 0 or int(other.get("vesselLane", 0)) != 0: continue
		if other.category == "building":
			var side := float(WarData.spec(other.kind).get("size", 1.0)) * .5 + radius + float(data().tuning.deploymentPadding)
			if Rect2(WarData.point(other) - Vector2.ONE * side, Vector2.ONE * side * 2).has_point(p): return false
		elif p.distance_to(WarData.point(other)) < radius + WarData.radius(other.kind) + float(data().tuning.deploymentPadding): return false
	return true


func spawn_at(placement: Dictionary, worker_id: int) -> Dictionary:
	if not enabled() or not placement.get("ok", false): return {}
	var p := WarData.point(placement)
	if not _fits(p, str(placement.organ)): return {}
	var e := game.spawn(KIND, 1, p)
	if e.is_empty(): return {}
	# Creation uses a certified tissue point, not pick_lane's projected blood priority.
	e.vesselLane = 0
	e.medicineId = KIND; e.medicineOrgan = placement.organ; e.medicineWorker = worker_id
	e.medicineRemaining = float(data().tuning.helperLifetimeSeconds)
	e.medicineLifetime = float(data().tuning.helperLifetimeSeconds)
	e.medicineSequence = 0; e.medicineNextAttack = float(game.state.time)
	game.event("medicine_deployed", {"source":worker_id, "helper":e.id, "organ":placement.organ})
	return e


func unit(e: Dictionary, dt: float) -> bool:
	if e.kind != KIND: return false
	if not enabled(): return true
	e.medicineRemaining = maxf(0.0, float(e.medicineRemaining) - dt)
	if float(e.medicineRemaining) <= 0:
		e.erase("medicineAttack"); game.combat.damage({}, e, e.hp, true, "medicine_expired"); return true
	var now := float(game.state.time)
	var order: Dictionary = e.orders[0] if not e.orders.is_empty() else {}
	var command := str(order.get("kind", ""))
	if e.get("medicineAttack") is Dictionary:
		var cast: Dictionary = e.medicineAttack
		if int(e.orderToken) != int(cast.orderToken) or float(e.get("hitTime", -1)) > float(cast.started):
			e.erase("medicineAttack")
		else:
			e.combatState = "attack"
			if not bool(cast.released) and now + .0000001 >= float(cast.releaseAt):
				cast.released = true
				var target := game.entity(int(cast.target))
				if _valid_target(e, target, float(data().tuning.get("range", 7.0))):
					var id := bubbles.launch(e, WarData.point(target), int(cast.sequence))
					if id > 0: game.event("medicine_shot", {"source":e.id, "target":target.id, "projectile":id, "sequence":cast.sequence})
			if now < float(cast.endsAt): return true
			e.erase("medicineAttack")
	if command in ["move", "retreat", "supplyroute"]:
		if game.go(e, WarData.point(order), dt, .05, int(order.get("lane", -1))):
			game.finish_order(e)
		return true
	var target := game.entity(int(order.get("target", 0))) if command == "attack" else {}
	if not _valid_target(e, target, float(WarData.spec(KIND).vision)):
		target = _nearest(e)
	if target.is_empty():
		if command == "attack":
			if game.entity(int(order.get("target", 0))).is_empty(): game.finish_order(e)
		elif command in ["attackmove", "guard"]:
			if game.go(e, WarData.point(order), dt, .05, int(order.get("lane", -1))) and command != "guard":
				game.finish_order(e)
		return true
	var reach := float(WarData.spec(KIND).range)
	if WarData.point(e).distance_to(WarData.point(target)) > reach:
		if command != "hold": game.go(e, WarData.point(target), dt, reach - .2, int(target.get("vesselLane", 0)))
		return true
	if now + .0000001 < float(e.medicineNextAttack): return true
	var interval := float(data().tuning.attackCooldownSeconds)
	e.medicineSequence = int(e.medicineSequence) + 1
	e.medicineAttack = {"sequence":e.medicineSequence, "target":int(target.id), "started":now,
		"releaseAt":now + interval * float(data().attackTiming.releaseFraction), "endsAt":now + interval,
		"orderToken":int(e.orderToken), "released":false}
	e.medicineNextAttack = now + interval
	e.weaponHeading = (WarData.point(target) - WarData.point(e)).angle()
	e.combatState = "attack"
	return true


func _valid_target(source: Dictionary, target: Dictionary, reach: float) -> bool:
	if target.is_empty() or float(target.hp) <= 0 or not WarData.is_virus(str(target.get("kind", ""))): return false
	if target.category != "unit" or int(target.faction) == int(source.faction) or int(target.get("vesselLane", 0)) != int(source.vesselLane): return false
	if WarData.point(source).distance_to(WarData.point(target)) > reach + .000001 or not game.visible(target, int(source.faction)): return false
	return game.navigation.clear_segment(WarData.point(source), WarData.point(target), int(source.vesselLane), KIND) and game.navigation.movement_clear(WarData.point(source), WarData.point(target), KIND, int(source.faction))


func _nearest(e: Dictionary) -> Dictionary:
	var best: Dictionary = {}; var distance := INF
	for target in game.entities():
		if not _valid_target(e, target, float(WarData.spec(KIND).vision)): continue
		var d := WarData.point(e).distance_squared_to(WarData.point(target))
		if d < distance or (is_equal_approx(d, distance) and (best.is_empty() or int(target.id) < int(best.id))):
			best = target; distance = d
	return best


static func sample(e: Dictionary, time: float, moving: float, dead: bool) -> Dictionary:
	var clips: Dictionary = data().clips
	var key := "move"; var elapsed := 0.0; var loop := true
	if dead:
		key = "death"; elapsed = maxf(0.0, time - float(e.get("died", time))); loop = false
		if elapsed >= float(clips.death.duration): return {"hidden":true}
	elif time - float(e.get("hitTime", -100.0)) < float(clips.hit.duration):
		key = "hit"; elapsed = maxf(0.0, time - float(e.hitTime)); loop = false
	elif e.get("medicineAttack") is Dictionary:
		key = "attack"; elapsed = (time - float(e.medicineAttack.started)) * float(clips.attack.duration) / float(data().tuning.attackCooldownSeconds); loop = false
	elif moving > .02: elapsed = time + int(e.id) * .071
	return {"key":key, "clip":clips[key], "frame":frame(clips[key], elapsed, loop), "family":KIND}


static func frame(clip: Dictionary, elapsed: float, loop: bool) -> int:
	var time := fposmod(elapsed, float(clip.duration)) if loop else maxf(0.0, elapsed)
	for index in clip.durations.size():
		if time < float(clip.durations[index]): return index
		time -= float(clip.durations[index])
	return clip.durations.size() - 1


static func validate_state(state: Dictionary) -> String:
	var actors: Array = state.get("entities", {}).values() if state.get("entities") is Dictionary else []
	var helpers := actors.filter(func(e): return e is Dictionary and e.get("kind", "") == KIND)
	if not state.has("medicineRuntime"): return "药品助手缺少运行状态" if not helpers.is_empty() else ""
	if not state.get("lifeRun") is Dictionary or not state.get("medicineSupply") is Dictionary or state.get("campaign") is Dictionary: return "药品运行模式无效"
	var runtime: Variant = state.medicineRuntime
	if not runtime is Dictionary or runtime.get("version") != 1 or not runtime.get("bubbles") is Dictionary: return "药品运行版本无效"
	if not WarMedicineBubbles.validate_snapshot(runtime.bubbles).is_empty(): return "泡泡状态无效"
	for projectile in runtime.bubbles.projectiles:
		if projectile.source.kind != KIND: return "药品弹体来源无效"
	for e in helpers:
		if e.get("medicineId", "") != KIND or not WarData.read("organs").has(e.get("medicineOrgan", "")): return "药品助手身份无效"
		if not _number(e.get("medicineLifetime")) or e.medicineLifetime <= 0 or e.medicineLifetime > 3600: return "药品初始时长无效"
		if not _number(e.get("medicineRemaining")) or e.medicineRemaining < 0 or e.medicineRemaining > e.medicineLifetime: return "药品剩余时间无效"
		if not _integer(e.get("medicineWorker"), 1) or not _integer(e.get("medicineSequence"), 0): return "药品助手序号无效"
		if not _number(e.get("medicineNextAttack")) or e.medicineNextAttack < 0: return "药品助手冷却无效"
		if e.has("medicineAttack"):
			var a: Variant = e.medicineAttack
			if not a is Dictionary or not a.get("released") is bool: return "药品攻击状态无效"
			for key in ["started", "releaseAt", "endsAt"]:
				if not _number(a.get(key)) or a[key] < 0: return "药品攻击时间无效"
			if a.started > a.releaseAt or a.releaseAt > a.endsAt: return "药品攻击顺序无效"
			for key in ["sequence", "target", "orderToken"]:
				if not _integer(a.get(key), 0): return "药品攻击编号无效"
	return ""


static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))


static func _integer(value: Variant, minimum: int) -> bool:
	return _number(value) and float(value) == floorf(float(value)) and float(value) >= minimum and float(value) <= 2147483647


func dispose() -> void:
	bubbles.bind_world(Callable(), Callable()); impacts.clear(); game = null
