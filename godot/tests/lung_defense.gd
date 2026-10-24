extends SceneTree
var failures: Array[String] = []
var checks := 0

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ",label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game := WarSimulation.new()
	game.start("lung_defense",73)
	var event: Dictionary = game.state.get("lungDefense",{})
	var base := game.entity(int(event.get("base",0)))
	check(game.mode == "fullbody" and event.phase == "preparing","dedicated event uses full-body world")
	check(not base.is_empty() and base.kind == "core" and base.complete and game.navigation.organ_at(WarData.point(base)) == "lung_l","ordinary completed core starts on left-lung tissue")
	check(event.workers.size() == 20 and game.units().filter(func(e): return e.faction == 1 and e.kind == "worker").size() == 20,"exactly twenty living red cells start")
	check(game.economy.population(1).x == 20 and game.economy.population(1).y == 30,"opening population leaves room for white-cell training")
	check(game.state.influenzaColonies.groups.is_empty(),"no infection floor or virus during preparation")
	var saved := game.snapshot()
	check(WarSave.validate(saved).is_empty(),"event snapshot validates")
	game.paused = true
	game.update(1.0)
	check(is_zero_approx(float(game.state.time)),"pause does not consume preparation")
	game.paused = false
	game.speed = 4.0
	game.scenarios.before_step(4.0)
	check(is_equal_approx(float(event.elapsed),1.0),"speed boost still grants two real active minutes")
	game.speed = 1.0
	# The real building/training methods must remain usable by the starter squad.
	var worker: Dictionary = game.entity(int(event.workers[0]))
	var site := Vector2.INF
	var distance := INF
	for x in range(-20,21):
		for y in range(-20,21):
			var p := game.economy.build_point("barracks",WarData.point(worker)+Vector2(x,y))
			var d := WarData.point(worker).distance_squared_to(p)
			if d < 100 or d >= distance or not game.economy.can_place("barracks",p,[int(worker.id)]): continue
			if not game.navigation.clear_segment(WarData.point(worker),p,0,"worker"): continue
			site = p; distance = d
	check(site.is_finite(),"red cell has a legal lung site for the white-cell barracks")
	if site.is_finite():
		check(game.economy.place("barracks",site,[int(worker.id)]),"red cell can order a real barracks")
		var barracks: Dictionary = {}
		for e in game.entities():
			if e.kind == "barracks" and e.faction == 1: barracks = e
		check(not barracks.is_empty(),"barracks construction is queued")
		if not barracks.is_empty():
			for i in 1100:
				game.navigation.update(10000)
				game.step(.1)
				if barracks.complete: break
			check(barracks.complete,"red cell physically completes barracks during preparation")
			if barracks.complete:
				check(game.economy.train(barracks,"spear"),"completed barracks accepts white-cell training with opening resources")
	while float(event.elapsed) < 119.8:
		game.navigation.update(10000)
		game.step(.1)
	check(game.units().any(func(e): return e.faction == 1 and e.kind == "spear"),"trained white cell joins the defense before invasion")
	check(event.phase == "preparing" and game.state.influenzaColonies.groups.is_empty(),"no early invasion")
	game.step(.2)
	check(event.phase == "infected" and not game.state.influenzaColonies.groups.is_empty(),"invasion begins after 120 active seconds")
	var group: Dictionary = game.state.influenzaColonies.groups.get(event.colony,{})
	check(group.organ == "lung_l" and group.pending+game.influenza.members(group).size() == 13 and WarInfectionZones.live_patches(game).size() == 1,"certified left-lung infection ground precedes thirteen flu viruses")
	for i in 4: game.influenza.before_step(.1)
	check(game.influenza.members(group).size() == 13 and group.pending == 0,"all thirteen influenza viruses enter through the real colony")
	var resumed := WarSimulation.new()
	resumed.mode = game.mode
	resumed.restore(game.snapshot())
	check(resumed.state.lungDefense.phase == "infected" and resumed.influenza.members(resumed.state.influenzaColonies.groups[event.colony]).size() == 13,"invasion and preparation state survive native snapshot restore")
	resumed.dispose()
	group.cleared = true
	game.scenarios.after_step(.1)
	check(event.phase == "defended","existing infection purification completes the event")
	game.dispose()
	print("LUNG_DEFENSE ",checks-failures.size(),"/",checks)
	quit(0 if failures.is_empty() else 1)
