extends SceneTree
## Isolate fortress attack range independently from construction and worker routing.
var checks := 0
var failures: Array[String] = []
var cases: Array = []
var denials: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,text: String) -> void:
	checks += 1
	if not value: failures.append(text); printerr("FAIL ",text)

func run_case(kind: String,distance: float) -> void:
	var game := WarSimulation.new(); game.start("life",39462)
	var patch: Dictionary = game.influenza.zone("lung_r").placements[0]
	var center := WarData.point(patch.center)
	var position := Vector2(INF,INF)
	for i in 64:
		var p := center+Vector2.from_angle(i*TAU/64)*distance
		if game.navigation.organ_at(p,kind) == "lung_r" and game.navigation.clear_segment(p,center,0,kind): position = p; break
	check(position.is_finite(),"certified unobstructed fixture at distance "+str(distance))
	if not position.is_finite(): game.dispose(); return
	var fort := game.spawn("flu_fortress",2,center,"building"); fort.vesselLane = 0
	var unit := game.spawn(kind,1,position); unit.vesselLane = 0
	check(not fort.is_empty() and not unit.is_empty(),"real target and attacker spawn "+kind)
	var events := {"shots":0,"impacts":0,"hits":0,"damage":0.0}
	var target_id := int(fort.id)
	game.combat_event.connect(func(event):
		if event.kind == "projectile_spawn": events.shots += 1
		if event.kind == "projectile_impact": events.impacts += 1
		if event.kind == "damage" and int(event.target) == target_id: events.hits += 1; events.damage += float(event.amount))
	game.submit_player({"action":"unit_order","unit":int(unit.id),"order":{"kind":"attack","target":target_id}})
	var attempts := 0
	var previous := -1.0
	for i in 80:
		game.navigation.update(10000); game.update(.1)
		if unit.has("cellShot") and float(unit.cellShot.started) != previous: attempts += 1; previous = float(unit.cellShot.started)
	check(events.hits > 0 and events.shots > 0,"in-range building attack actually releases and damages: "+kind+" distance "+str(distance))
	cases.append({"kind":kind,"command":{"kind":"attack","target":target_id},"unit":int(unit.id),"target":target_id,
		"initialPoint":[position.x,position.y],"finalPoint":[unit.x,unit.y],"fortressPoint":[fort.x,fort.y],
		"distance":WarData.point(unit).distance_to(WarData.point(fort)),"unitRange":WarData.spec(kind).range,"targetRadius":WarData.spec("flu_fortress").size*.5,
		"clearSegment":game.navigation.clear_segment(WarData.point(unit),WarData.point(fort),0,kind),"vesselLane":unit.vesselLane,
		"orders":unit.orders,"pathPending":unit.pathPending,"pathFailed":unit.pathFailed,"pathSize":unit.path.size(),
		"combatState":unit.combatState,"windupAttempts":attempts,"events":events,"remainingFortressHp":fort.hp,"simulatedSeconds":game.state.time})
	game.dispose()

func denied_case(stage: String,reason: String) -> void:
	# A controlled flat-map fixture isolates all three firing phases. The wall
	# is injected only into this test's navigation mask, never into game data.
	var game := WarSimulation.new(); game.start("cell_test",39462)
	game.state.entities.clear(); game.navigation.set_ground("cell_test")
	var point: Vector2 = game.navigation.campaign_grid.origin+Vector2(10,10)
	var unit := game.spawn("spear",1,point)
	var fort := game.spawn("flu_fortress",2,point+Vector2(7,0),"building")
	check(game.combat._firing_solution(unit,fort).in_range,"denial starts within unchanged range: "+stage+"/"+reason)
	if stage != "prepare":
		check(game.combat.fight(unit,fort,.1,false) and unit.has("cellShot"),"real windup starts before condition changes: "+stage+"/"+reason)
		if stage == "impact":
			game.state.time = float(unit.cellShot.releaseAt)
			game.combat.update_projectiles(.001)
			check(game.state.combatProjectiles.size() == 1,"real projectile exists before impact condition changes: "+reason)
	match reason:
		"range": fort.x = point.x+8.2
		"lane": fort.vesselLane = 1
		"wall":
			var grid := game.navigation.campaign_grid
			var q := Vector2i((point+Vector2(3,0)-grid.origin).round())
			grid.valid[q.y*grid.width+q.x] = 0
	check(not game.combat._firing_solution(unit,fort).in_range,"same geometry rejects changed condition: "+stage+"/"+reason)
	if stage == "prepare":
		check(not game.combat.fight(unit,fort,.1,false) and not unit.has("cellShot"),"denied prepare does not start a windup: "+reason)
	elif stage == "release":
		game.state.time = float(unit.cellShot.releaseAt)
		game.combat.update_projectiles(.1)
		check(game.state.combatProjectiles.is_empty(),"denied release does not spawn a projectile: "+reason)
	else:
		game.combat.update_projectiles(1.1)
	check(fort.hp == fort.maxHp,"denied phase cannot damage a building: "+stage+"/"+reason)
	denials.append({"stage":stage,"reason":reason,"remainingFortressHp":fort.hp,"projectiles":game.state.combatProjectiles.size()})
	game.dispose()

func run() -> void:
	var combat_hash := FileAccess.get_sha256("res://scripts/combat.gd")
	for kind in ["spear","neutrophil"]:
		for distance in [5.0,7.0,8.0]: run_case(kind,distance)
	for stage in ["prepare","release","impact"]:
		for reason in ["range","lane","wall"]: denied_case(stage,reason)
	DirAccess.make_dir_recursive_absolute("res://test-output")
	var file := FileAccess.open("res://test-output/life-building-attack.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":cases,"deniedPhases":denials,"combatSourceSha256":combat_hash,"scope":"normal fixed-step lung attacks plus controlled prepare/release/impact rejection fixtures; no construction, hp overrides, direct damage calls or UI"},"  ",true,true))
	print("LIFE BUILDING ATTACK ",checks," checks, failures=",failures)
	quit(0 if failures.is_empty() else 1)
