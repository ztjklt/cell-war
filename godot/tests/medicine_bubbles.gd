extends SceneTree
const Service = preload("res://scripts/medicine_bubbles.gd")
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("run")


func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); printerr("FAIL ", label)


func near(value: float, expected: float, label: String, tolerance := 0.00001) -> void:
	check(absf(value - expected) <= tolerance, label)


func actor(id: int, point: Vector2, kind := "virus", faction := 2, hp := 100.0, lane := 0) -> Dictionary:
	return {"id":id, "kind":kind, "category":"unit", "faction":faction,
		"hp":hp, "maxHp":hp, "x":point.x, "y":point.y, "vesselLane":lane, "statuses":{}}


func emitter(id := 101) -> Dictionary:
	return actor(id, Vector2.ZERO, "fever_pain_relief", 1, 60.0)


func service(overrides: Dictionary = {}):
	var value = Service.new(overrides)
	value.bind_world(Callable(), func(_a, _b, _lane, _source): return true)
	return value


func roundtrip(data: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(data, "", false, true))


func test_configuration() -> void:
	var value = service()
	check(value.ready(), "catalogue configures only the confirmed fever medicine")
	check(value.tuning().status == "draft_pending_balance" and not value.tuning().confirmedValues, "all numbers remain tunable unconfirmed defaults")
	near(value.tuning().values.damage, 4.0, "damage read from medicines.json")
	near(value.tuning().values.slowRatio, .3, "slow ratio read from medicines.json")
	near(value.tuning().values.slowDurationSeconds, 2.0, "slow duration read from medicines.json")
	var copy: Dictionary = value.tuning(); copy.values.damage = 999.0
	near(value.tuning().values.damage, 4.0, "tuning getter cannot mutate live rules")
	check(not service({"damage":NAN}).ready(), "NaN tuning rejected")
	check(not service({"slowRatio":1.0}).ready(), "hard freeze is not silently enabled by tuning")
	check(not service({"range":0.0}).ready(), "zero range rejected")
	check(not service({"unknownAbility":true}).ready(), "unknown ability override rejected")
	check(service({"damage":2.0, "slowRatio":.2}).ready(), "explicit pending-balance overrides supported")
	var closed = Service.new()
	check(closed.launch(emitter(), Vector2(3, 0), 1) == 0 and closed.last_error() == "geometry_required", "unbound geometry fails closed")


func test_hit_and_refresh() -> void:
	var value = service()
	var source := emitter(); var target := actor(1, Vector2(3, 0)); var world := [source, target]
	target.statuses = {"unrelated":{"duration":7, "moveMultiplier":.8}}
	check(value.launch(source, Vector2(3, 0), 1) == 1, "first bubble has independent stable id")
	check(value.launch(source, Vector2(3, 0), 1) == 0, "same shot sequence cannot emit twice")
	check(value.launch(source, Vector2(3, 0), 2) == 0 and value.last_error() == "cooldown", "unconfirmed cooldown default advances in service state")
	value.advance_simulation(.1, world)
	near(target.hp, 100.0, "no instant damage at launch")
	near(value.projectiles()[0].x, 1.4, "projectile actually advances along launch direction")
	value.advance_simulation(.1, world)
	near(target.hp, 96.0, "swept hit mutates live target health once")
	check(value.projectiles().is_empty(), "hit consumes independent projectile")
	near(value.speed_multiplier(target), .7, "fixed slow produces one movement factor")
	check(value.slow_remaining(1) > 1.9 and value.slow_remaining(1) < 2.0, "impact time inside tick determines remaining slow")
	check(target.statuses == {"unrelated":{"duration":7, "moveMultiplier":.8}}, "medicine never overwrites unrelated status config or base movement")
	value.advance_simulation(1.2, world)
	check(value.slow_remaining(1) < .8, "slow timer progresses in simulation time")
	check(value.launch(source, Vector2(3, 0), 2) == 2, "failed cooldown attempt did not consume sequence")
	value.advance_simulation(.2, world)
	near(target.hp, 92.0, "second collision causes one further hit")
	near(value.speed_multiplier(target), .7, "repeat hit does not multiply slow to .49")
	check(value.slow_remaining(1) > 1.9 and value.slow_remaining(1) <= 2.0, "repeat hit refreshes rather than adds duration")
	value.advance_simulation(1.9, world)
	near(value.speed_multiplier(target), .7, "refreshed slow remains until its actual deadline")
	value.advance_simulation(.2, world)
	near(value.speed_multiplier(target), 1.0, "slow expires without modifying base stats")
	near(target.hp, 92.0, "expiry does not inflict extra damage")
	var hits := value.drain_events().filter(func(e): return e.kind == "bubble_impact")
	check(hits.size() == 2 and value.drain_events().is_empty(), "observational hit events drain once")
	var simultaneous = service({"attackCooldownSeconds":0.0})
	var s := emitter(); var t := actor(1, Vector2(3, 0))
	simultaneous.launch(s, Vector2(3, 0), 1); simultaneous.launch(s, Vector2(3, 0), 2)
	simultaneous.advance_simulation(.3, [s, t])
	near(t.hp, 92.0, "two independent projectiles each resolve their own collision")
	near(simultaneous.speed_multiplier(t), .7, "same-tick multiple hits still use fixed slow")
	var large = service(); s = emitter(); t = actor(1, Vector2(3, 0))
	large.launch(s, Vector2(3, 0), 1); large.advance_simulation(3.0, [s, t])
	near(t.hp, 96.0, "large delta does not tunnel or repeat damage")
	near(large.speed_multiplier(t), 1.0, "large delta ages slow from actual impact instead of tick end")
	var thin = service({"projectileSpeed":100.0, "geometryStep":4.0, "targetRadius":.01, "projectileRadius":0.0})
	s = emitter(); t = actor(17, Vector2(3.14159, 0))
	thin.launch(s, Vector2(7, 0), 1); thin.advance_simulation(.1, [s, t])
	near(t.hp, 96.0, "swept collision hits a thin target between coarse segment endpoints")


func test_filtering_geometry_and_death() -> void:
	var value = service()
	var source := emitter()
	var bacteria := actor(1, Vector2(1, 0), "wolf")
	var ally := actor(2, Vector2(1.5, 0), "virus", 1)
	var other_lane := actor(3, Vector2(2, 0), "virus", 2, 100.0, 1)
	var dead := actor(4, Vector2(2.3, 0), "virus", 2, 0.0)
	var far := actor(6, Vector2(5, 0))
	var near_target := actor(5, Vector2(3, 0), "herpes")
	value.launch(source, Vector2(7, 0), 1)
	value.advance_simulation(.5, [source, far, bacteria, ally, other_lane, dead, near_target])
	for item in [bacteria, ally, other_lane, far]: near(item.hp, 100.0, "noneligible or farther actor untouched: %d" % int(item.id))
	near(dead.hp, 0.0, "dead target never takes damage")
	near(near_target.hp, 96.0, "nearest existing virus kind wins regardless of input array order")
	var tie = service(); var a := actor(8, Vector2(3, 0)); var b := actor(7, Vector2(3, 0))
	tie.launch(source, Vector2(3, 0), 1); tie.advance_simulation(.3, [source, a, b])
	near(a.hp, 100.0, "equal contact order is stable")
	near(b.hp, 96.0, "equal contacts resolve by stable entity id")
	var wall = service({"geometryStep":2.0})
	wall.bind_world(Callable(), func(_a, end, _lane, _source): return end.x < 2.0)
	var behind := actor(9, Vector2(3, 0))
	wall.launch(source, Vector2(6, 0), 1); wall.advance_simulation(.4, [source, behind])
	near(behind.hp, 100.0, "wall before target prevents damage")
	check(wall.projectiles().is_empty(), "blocked bubble terminates")
	var before_wall = service({"geometryStep":2.0})
	before_wall.bind_world(Callable(), func(_a, end, _lane, _source): return end.x < 2.0)
	var exposed := actor(10, Vector2(1.5, 0))
	before_wall.launch(source, Vector2(6, 0), 1); before_wall.advance_simulation(.4, [source, exposed])
	near(exposed.hp, 96.0, "target before later wall still receives nearer contact")
	var stationary = service(); var moving := actor(11, Vector2(3, 0))
	stationary.launch(source, Vector2(3, 0), 1); moving.y = 3.0
	stationary.advance_simulation(.6, [source, moving])
	near(moving.hp, 100.0, "fixed-direction bubble can be dodged; it does not home")
	check(stationary.projectiles().is_empty(), "miss expires at range/lifetime limit")
	var short_life = service({"projectileMaxLifetimeSeconds":.05}); var distant := actor(12, Vector2(3, 0))
	short_life.launch(source, Vector2(3, 0), 1); short_life.advance_simulation(.3, [source, distant])
	near(distant.hp, 100.0, "explicit flight lifetime expires before distant collision")
	check(short_life.projectiles().is_empty(), "expired projectile removed")
	var lethal = service(); var fragile := actor(13, Vector2(3, 0), "virus", 2, 2.0)
	lethal.launch(source, Vector2(3, 0), 1); lethal.advance_simulation(.3, [source, fragile])
	near(fragile.hp, 0.0, "damage clamps target health to zero")
	near(lethal.speed_multiplier(fragile), 1.0, "dead target receives no active slow")
	check(lethal.snapshot().slows.is_empty(), "lethal hit leaves no stale debuff")
	var death = service(); var dying := actor(14, Vector2(3, 0)); var next := actor(15, Vector2(5, 0))
	death.launch(source, Vector2(5, 0), 1); dying.hp = 0.0
	death.advance_simulation(.5, [source, dying, next])
	near(next.hp, 96.0, "dead aimed actor does not absorb a surviving straight projectile")
	next.hp = 0.0; death.advance_simulation(0.0, [source, dying, next])
	check(death.snapshot().slows.is_empty(), "later external death clears medicine slow")
	var orphan = service(); var retired := emitter(); var survivor := actor(16, Vector2(3, 0))
	orphan.launch(retired, Vector2(3, 0), 1); retired.hp = 0.0
	orphan.advance_simulation(.3, [retired, survivor])
	near(survivor.hp, 96.0, "already emitted bubble survives emitter death independently")
	check(orphan.snapshot().sources.is_empty(), "dead emitter cooldown bookkeeping is retired")


func test_time_and_serialization() -> void:
	var first = service(); var source := emitter(); var target := actor(1, Vector2(3, 0))
	first.launch(source, Vector2(3, 0), 1)
	var untouched: Dictionary = first.snapshot()
	check(first.advance(100.0, [source, target], true, 2.0), "paused wall-time adapter accepts valid time")
	check(first.snapshot() == untouched, "pause freezes projectiles cooldowns and service clock")
	check(not first.advance_simulation(-1.0, [source, target]), "negative simulation delta rejected")
	check(not first.advance(INF, [source, target]), "nonfinite wall time rejected")
	check(first.snapshot() == untouched, "invalid time is transactional")
	first.advance_simulation(.1, [source, target])
	var saved := roundtrip(first.snapshot())
	check(Service.validate_snapshot(saved).is_empty(), "save owner can validate service state before replacing the world")
	var restored = service(); check(restored.restore(saved), "mid-flight JSON roundtrip restores")
	check(restored.drain_events().is_empty(), "restore does not replay spawn events")
	var target_copy := target.duplicate(true); var source_copy := source.duplicate(true)
	first.advance_simulation(.1, [source, target]); restored.advance_simulation(.1, [source_copy, target_copy])
	near(target_copy.hp, target.hp, "restored flight causes identical actual health change")
	check(first.snapshot() == restored.snapshot(), "mid-flight restored state advances deterministically")
	check(restored.launch(source_copy, Vector2(3, 0), 1) == 0, "JSON load preserves shot idempotence")
	check(restored.launch(source_copy, Vector2(3, 0), 2) == 0 and restored.last_error() == "cooldown", "JSON load preserves emitter cooldown")
	var active_save := roundtrip(restored.snapshot())
	var resumed = service(); check(resumed.restore(active_save), "active slow JSON roundtrip restores")
	var hp := float(target_copy.hp)
	var frozen: Dictionary = resumed.snapshot()
	resumed.advance(9.0, [source_copy, target_copy], true, 4.0)
	check(resumed.snapshot() == frozen and is_equal_approx(resumed.speed_multiplier(target_copy), .7), "pause freezes an already active slow deadline")
	resumed.advance_simulation(1.0, [source_copy, target_copy])
	near(target_copy.hp, hp, "loading a resolved hit does not repeat damage")
	near(resumed.speed_multiplier(target_copy), .7, "saved slow preserves remaining active time")
	resumed.advance_simulation(1.1, [source_copy, target_copy])
	near(resumed.speed_multiplier(target_copy), 1.0, "loaded slow expires normally")
	var fast = service(); var fixed = service(); var a := actor(2, Vector2(3, 0)); var b := a.duplicate(true)
	fast.launch(source, Vector2(3, 0), 1); fixed.launch(source, Vector2(3, 0), 1)
	fast.advance(.1, [source, a], false, 2.0); fixed.advance_simulation(.2, [source, b])
	check(fast.snapshot() == fixed.snapshot() and a.hp == b.hp, "2x wall adapter matches one explicitly scaled simulation step")
	var boundary = service(); boundary.launch(source, Vector2(3, 0), 1)
	var baseline: Dictionary = boundary.snapshot()
	for kind in ["schema", "direction", "negative_lifetime", "invalid_rules", "medicine", "duplicate_bubble"]:
		var bad := roundtrip(baseline)
		match kind:
			"schema": bad.schema = "wrong"
			"direction": bad.projectiles[0].dx = 0; bad.projectiles[0].dy = 0
			"negative_lifetime": bad.projectiles[0].remainingLife = -1
			"invalid_rules": bad.rules.slowRatio = 9
			"medicine": bad.medicineId = "antibiotic"
			"duplicate_bubble": bad.projectiles.append(bad.projectiles[0].duplicate(true))
		check(not boundary.restore(bad), "corrupt snapshot rejected: " + kind)
		check(not Service.validate_snapshot(bad).is_empty(), "save-owner validation reports corruption: " + kind)
		check(boundary.snapshot() == baseline, "failed load preserves live state: " + kind)
	var detached = Service.new()
	check(detached.restore(roundtrip(baseline)), "callbacks are not required to inspect or restore a snapshot")
	var held: Dictionary = detached.snapshot()
	check(not detached.advance_simulation(.3, [source, target]), "restored flight requires explicit geometry rebind")
	check(detached.snapshot() == held, "missing geometry preserves in-flight save instead of losing a projectile")
	detached.bind_world(Callable(), func(_a, _b, _lane, _source): return true)
	check(detached.advance_simulation(.3, [source, target]), "rebound restored service resumes normally")
	var illegal := roundtrip(active_save)
	illegal.slows["1"].expiresAt += 100
	check(not boundary.restore(illegal), "corrupt overlong slow cannot become a permanent debuff")
	illegal = roundtrip(baseline); illegal.rules.extraAbility = 1
	check(not boundary.restore(illegal), "snapshot cannot inject an unknown medicine ability")
	var limit = service({"maxProjectiles":1, "maxEvents":2, "attackCooldownSeconds":0.0})
	check(limit.launch(source, Vector2(20, 0), 1) > 0, "capacity accepts first projectile")
	check(limit.launch(source, Vector2(20, 0), 2) == 0, "projectile capacity enforced")
	limit.advance_simulation(1.0, [source]); limit.launch(source, Vector2(20, 0), 2)
	check(limit.drain_events().size() <= 2, "observational event history is bounded")
	var zero = service(); check(zero.launch(source, Vector2.ZERO, 1) == 0, "zero launch direction rejected")
	check(zero.launch(source, Vector2(NAN, 0), 1) == 0, "nonfinite aim rejected")
	var angled = service(); angled.launch(source,Vector2(3.0,-.114038),1)
	var loaded_angle = service(); loaded_angle.restore(roundtrip(angled.snapshot()))
	check(loaded_angle.snapshot()==angled.snapshot(),"angled Vector2 direction restores its exact engine representation")


func test_native_world_callback() -> void:
	var game := WarSimulation.new(); game.start("cell_test")
	var source := game.entity(int(game.state.cellTest.white))
	var target := game.entity(int(game.state.cellTest.virus))
	target.x = float(source.x) + 3.0; target.y = float(source.y); target.faction = 2
	var old_hp := float(target.hp)
	var value = Service.new()
	value.bind_world(
		func(owner, victim, amount, cause): game.combat.damage(owner, victim, amount, true, cause),
		func(a, b, lane, owner): return game.navigation.clear_segment(a, b, lane, owner.kind),
		func(victim): return WarData.radius(victim.kind))
	check(value.launch(source, WarData.point(target), 1) > 0, "opt-in test binds existing actor and native navigation")
	game.state.time += .3
	value.advance_simulation(.3, game.entities())
	near(target.hp, old_hp - 4.0, "native WarCombat callback damages actual simulation dictionary")
	check(not game.effects.is_empty(), "existing combat records actual damage feedback")
	near(value.speed_multiplier(target), .7, "existing runtime virus exposes independent medicine slow query")
	check(game.state.combatProjectiles.is_empty(), "independent bubble never aliases ordinary projectile storage")
	var before := game.snapshot()
	value.snapshot(); value.drain_events()
	check(game.snapshot() == before, "inspection and serialization do not modify the host simulation")
	value.bind_world(Callable(), Callable())
	game.dispose()


func run() -> void:
	test_configuration()
	test_hit_and_refresh()
	test_filtering_geometry_and_death()
	test_time_and_serialization()
	test_native_world_callback()
	var report := {"passed":checks - failures.size(), "total":checks, "failures":failures,
		"engine":Engine.get_version_info().string, "scope":"Independent opt-in service; no formal battle/shop/deployment integration."}
	DirAccess.make_dir_recursive_absolute("res://test-output")
	FileAccess.open("res://test-output/medicine-bubbles.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("MEDICINE BUBBLES ", checks - failures.size(), "/", checks, " ", failures)
	quit(0 if failures.is_empty() else 1)
