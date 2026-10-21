extends SceneTree
## Regression cases found while auditing live buttons and the battle loop.
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,description: String) -> void:
	checks += 1
	if not value: failures.append(description); printerr("FAIL ",description)

func fixture() -> WarSimulation:
	var game := WarSimulation.new()
	game.start("cell_test")
	game.state.entities.clear()
	game.navigation.blockers.clear()
	game.economy.add(1,"wood",1000)
	game.economy.add(1,"food",1000)
	game.economy.add(1,"oxygen",1000)
	return game

func run() -> void:
	var game := WarSimulation.new()
	game.start("life")
	var players := game.units().filter(func(e): return e.faction == 1)
	check(players.size() == 1 and players[0].kind == "worker","new survival starts with one red cell")
	game.spawn("spear",1,WarData.point(players[0])+Vector2(-3,0))
	var saved := game.snapshot()
	game.restore(saved)
	check(game.units().filter(func(e): return e.faction == 1).size() == 2,"restore never removes units earned after the start")
	game.start("fullbody")
	check(game.units().filter(func(e): return e.faction == 1).size() == 2,"legacy fullbody keeps its authored squad")
	# Let the real influenza colony enqueue its longer searches, then command
	# a nearby cell. Short movement must complete while that backlog still exists.
	game.step(.1)
	var front := game.entity(26)
	var goal := WarData.point(front)+Vector2(-2.5,0)
	game.selected.assign([int(front.id)])
	game.issue("move",goal)
	for i in 80:
		game.navigation.update(3500)
		game.step(.1)
	check(WarData.point(front).distance_to(goal) < .2,"local movement remains responsive during actual outbreak pathfinding")
	game.dispose()

	game = fixture()
	var worker := game.spawn("worker",1,Vector2(100,100))
	var completed: Array[int] = []
	game.navigation.path_ready.connect(func(token,_path,_reason): completed.append(token))
	var cancelled := game.navigation.request(worker,Vector2(102,100),0)
	game.navigation.cancel(cancelled)
	game.navigation.update(10000)
	check(not completed.has(cancelled),"cancelled direct route is never delivered")
	var token := game.navigation.request(worker,Vector2(104,100),0)
	var wall := game.spawn("store",1,Vector2(102,100),"building")
	game.navigation.blockers = [wall]
	var path: Array = []
	game.navigation.path_ready.connect(func(id,points,_reason):
		if id == token: path.assign(points))
	for i in 30:
		game.navigation.update(10000)
		if completed.has(token): break
	var safe := not path.is_empty()
	for i in range(1,path.size()):
		safe = safe and game.navigation.movement_clear(path[i-1].p,path[i].p,"worker",1)
	check(safe and path.size() > 2,"building placed after enqueue invalidates direct clearance and routes around it")
	game.dispose()

	game = fixture()
	var lab := game.spawn("lab",1,Vector2(120,110),"building")
	lab.complete = false
	var stock := game.economy.stock(1,"wood")
	check(not game.economy.research(lab,"tier2") and game.economy.stock(1,"wood") == stock,"unfinished laboratory cannot charge for research")
	lab.complete = true
	check(game.economy.research(lab,"tier2"),"finished laboratory starts research")
	lab.hp = 0
	game.economy.update(.1)
	check(not game.state.factions[0].researching,"destroyed laboratory releases the research lock")
	var replacement := game.spawn("lab",1,Vector2(125,110),"building")
	check(game.economy.research(replacement,"tier2"),"replacement laboratory can restart lost research")
	game.dispose()

	game = fixture()
	var core := game.spawn("core",1,Vector2(110,110),"building")
	game.navigation.blockers = [core]
	var waiting := game.spawn("worker",1,Vector2(113,110))
	check(game.economy.train(core,"worker"),"worker training starts with space in population")
	core.queue[0].remaining = 0
	game.economy.update(.1)
	var born := game.units().filter(func(e): return e.id != waiting.id)
	check(born.size() == 1 and WarCellShape.contact(born[0],waiting).is_empty(),"production chooses a free exit instead of overlapping an existing cell")
	check(core.queue.is_empty(),"successful free birth consumes exactly one production item")
	core.hp = 0
	check(not game.economy.train(core,"worker"),"destroyed building cannot accept training")
	game.dispose()

	game = fixture()
	core = game.spawn("core",1,Vector2(110,110),"building")
	game.navigation.blockers = [core]
	check(game.economy.train(core,"worker"),"blocked-exit fixture queues a worker")
	core.queue[0].remaining = 0
	for i in 24:
		game.spawn("worker",2,Vector2(113,110)+Vector2.from_angle(i*2.399)*sqrt(float(i))*.5)
	game.economy.update(.1)
	check(core.queue.size() == 1 and core.queue[0].remaining == 0,"blocked exits preserve completed production without overlap")
	check(WarSave.validate(game.snapshot()).is_empty(),"blocked production can be saved")
	for e in game.units(): game.state.entities.erase(str(e.id))
	game.economy.update(.1)
	check(core.queue.is_empty() and game.units().size() == 1,"clearing an exit delivers the already-paid cell exactly once")
	game.dispose()
	DirAccess.make_dir_recursive_absolute("res://test-output/bug-audit-20261021")
	var file := FileAccess.open("res://test-output/bug-audit-20261021/gameplay-regressions.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	print("GAMEPLAY REGRESSIONS ",checks-failures.size(),"/",checks)
	quit(0 if failures.is_empty() else 1)
