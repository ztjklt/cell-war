extends SceneTree
var failures: Array[String] = []
var checks := 0

func check(value: bool,message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("FAIL ",message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var large_batch := WarSimulation.new()
	large_batch.start("fullbody")
	large_batch.state.influenzaColonies = {"version":1,"groups":{}}
	var large_group := large_batch.influenza.start_outbreak("brain",0,20)
	for i in 5: large_batch.influenza.before_step(0)
	check(large_batch.influenza.members(large_group).size() == 20 and large_group.pending == 0,"full twenty-virus batch spawns on another organ's certified tissue")
	large_batch.dispose()
	var game := WarSimulation.new()
	game.start("fullbody")
	game.state.influenzaColonies = {"version":1,"groups":{}}
	var group := game.influenza.start_outbreak("lung_r",0,10)
	check(not group.is_empty() and group.pending == 10,"outbreak queues ten viruses")
	for i in 3: game.influenza.before_step(0)
	var members := game.influenza.members(group)
	check(members.size() == 10 and group.pending == 0,"batch actually spawns without losses")
	for e in members:
		check(e.vesselLane == 0 and game.navigation.organ_at(WarData.point(e),"virus") == "lung_r","virus stays on certified right-lung tissue")
	var original: Array = members.map(func(e): return int(e.id))
	members[-1].hp = 0
	game.influenza.after_step(.1)
	check(game.influenza.forts(group).is_empty(),"nine viruses cannot start a fortress")
	members[-1].hp = members[-1].maxHp
	game.influenza.after_step(.1)
	var forts := game.influenza.forts(group)
	check(forts.size() == 1,"ten viruses start exactly one fortress")
	if forts.is_empty():
		finish(game); return
	var fort: Dictionary = forts[0]
	check(not fort.complete and fort.builders.size() == 10,"all ten builders assigned")
	check(game.influenza._site_allowed(WarData.point(fort)+Vector2(.1,0),group) == false,"fortress cannot overlap existing site")
	check(game.influenza.members(group).size() == 10,"construction does not consume builders")
	game.influenza.before_step(30)
	check(group.produced == 0,"unfinished fortress produces nothing")
	var began := Time.get_ticks_msec()
	for i in 900:
		game.navigation.update(10000)
		game.step(.1)
		if fort.complete: break
		if i%100 == 0: print("BUILD ",i," progress ",fort.progress," workers ",fort.builders.size())
	check(fort.complete,"real pathfinding brings ten viruses to drill and finish")
	if not fort.complete:
		for id in fort.builders:
			var worker := game.entity(int(id))
			print("WORKER ",id," p=",WarData.point(worker)," slot=",worker.get("fluBuildSlot")," state=",worker.get("combatState")," failed=",worker.get("pathFailed")," path=",worker.get("path")," work=",worker.get("fluWorkedAt",-1))
	check(original.all(func(id): return not game.entity(id).is_empty() and game.entity(id).hp > 0),"all original builders survive completion")
	check(game.influenza.forts(group).size() == 1,"same ten cannot build unlimited fortresses")
	if not fort.complete:
		finish(game); return
	var before := game.influenza.members(group).size()
	fort.growthElapsed = 0.0
	game.influenza.before_step(29.9)
	check(game.influenza.members(group).size() == before,"no birth before thirty seconds")
	var saved := game.snapshot()
	check(WarSave.validate(saved).is_empty(),"new colony and fortress save validates")
	var resumed := WarSimulation.new()
	resumed.restore(saved)
	var restored_group: Dictionary = resumed.state.influenzaColonies.groups[group.id]
	var restored_fort := resumed.entity(int(fort.id))
	check(is_equal_approx(float(restored_fort.growthElapsed),29.9),"save/load preserves incubation timer")
	resumed.influenza.before_step(.1)
	check(resumed.influenza.members(restored_group).size() == before+1,"birth occurs at thirty seconds after reload")
	resumed.dispose()
	game.influenza.before_step(.1)
	check(game.influenza.members(group).size() == before+1 and group.produced == 1,"exactly one new virus every thirty seconds")
	game.paused = true
	var timer: float = fort.growthElapsed
	game.update(1.0)
	check(fort.growthElapsed == timer,"pause freezes incubation")
	game.paused = false
	# An impossible birth location retains one ready birth rather than losing it or bursting.
	var position := WarData.point(fort)
	fort.x = 0; fort.y = 0
	game.influenza.before_step(30)
	check(is_equal_approx(float(fort.growthElapsed),30) and group.produced == 1,"blocked birth waits without losing progress")
	fort.x = position.x; fort.y = position.y
	game.influenza.before_step(.1)
	check(group.produced == 2,"ready birth retries when space becomes valid")
	game.influenza.before_step(60)
	check(group.produced == 4,"elapsed sixty seconds produces two viruses without timer drift")
	while game.influenza.members(group).size() < 19:
		if game.influenza._spawn_virus(group,position).is_empty(): break
	game.influenza.after_step(.1)
	check(game.influenza.forts(group).size() == 1,"nineteen viruses still have one fortress slot")
	var extra := game.influenza._spawn_virus(group,position)
	check(not extra.is_empty(),"twentieth virus can join colony")
	game.state.time += 1.1
	game.influenza.after_step(.1)
	forts = game.influenza.forts(group)
	check(forts.size() == 2,"twenty living viruses unlock second fortress")
	if forts.size() == 2:
		var site: Dictionary = forts[1]
		var builder := game.entity(int(site.builders[0]))
		var enemy := game.spawn("spear",1,WarData.point(builder)+Vector2(1,0))
		if not enemy.is_empty():
			builder.cooldown = 0.0
			game.influenza.unit(builder,.1)
			check(builder.combatState == "attack" and builder.has("shotTime"),"builder fights nearby defenders using real attack logic")
			check(builder.get("fluWorkedAt",-100) != game.state.time,"combat interrupts drilling")
			enemy.hp = 0
		game.influenza.after_step(.1)
		check(game.influenza.forts(group).size() == 2,"incomplete fortress also reserves its quota")
	var broken := game.snapshot()
	broken.influenzaColonies.groups[group.id].pending = -1
	check(not WarSave.validate(broken).is_empty(),"corrupt colony counts are rejected")
	for e in game.influenza.members(group): e.hp = 0
	for e in game.influenza.forts(group): e.hp = 0
	game.influenza.after_step(.1)
	game.influenza.before_step(60)
	check(not group.cleared and group.purification.elapsed == 0 and game.influenza.members(group).is_empty(),"destroyed enemies stop births but still require joint purification")
	print("SIMULATION milliseconds ",Time.get_ticks_msec()-began)
	finish(game)

func finish(game: WarSimulation) -> void:
	game.dispose()
	DirAccess.make_dir_recursive_absolute("res://test-output")
	var file := FileAccess.open("res://test-output/influenza-fortress.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	print("INFLUENZA FORTRESS ",checks-failures.size(),"/",checks)
	quit(0 if failures.is_empty() else 1)
