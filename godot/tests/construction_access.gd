extends SceneTree
const OUT := "res://test-output/construction-access/"
var failures: Array[String] = []
var checks := 0
var report := {"cases":[]}

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("FAIL ",message)

func frame(game: WarSimulation) -> void:
	game.navigation.update(20000); game.update(.1)

func fixture() -> WarSimulation:
	var game := WarSimulation.new(); game.start("life",73)
	game.state.erase("lifeRun")
	game.state.erase("medicineSupply"); game.state.erase("medicineRuntime")
	return game

func case(kind: String,site: Vector2,move_first: bool) -> void:
	var game := fixture()
	var red: Dictionary = game.units()[0]
	var birth := WarData.point(red)
	if move_first:
		game.submit_player({"action":"unit_order","unit":int(red.id),"order":{"kind":"move","x":994.0,"y":1907.5,"lane":0}})
		for i in 80: frame(game)
		check(WarData.point(red).distance_to(Vector2(994,1907.5)) < .1,"core case physically walks out of the birth patch")
	var before := game.economy.stock(1,"wood")
	var allowed := game.economy.can_place(kind,site,[int(red.id)])
	check(allowed,kind+": reported placement is genuinely allowed")
	game.submit_player({"action":"place","building":kind,"x":site.x,"y":site.y,"ids":[int(red.id)]})
	var building: Dictionary = {}
	var began := float(game.state.time)
	var max_step := 0.0
	var previous := WarData.point(red)
	for i in 1500:
		frame(game)
		max_step = maxf(max_step,previous.distance_to(WarData.point(red))); previous = WarData.point(red)
		for e in game.entities():
			if e.kind == kind and int(e.faction) == 1: building = e; break
		if not building.is_empty() and building.complete: break
	check(not building.is_empty() and building.complete,kind+": original reported site completes through actual construction")
	check(is_equal_approx(before-game.economy.stock(1,"wood"),float(WarData.spec(kind).cost.wood)),kind+": actual cost is charged exactly once")
	check(WarData.point(red).distance_to(birth) > .1 and max_step <= float(WarData.spec("worker").speed)*WarSimulation.STEP+.001,kind+": actor walks to work with no position injection")
	var radius := float(WarData.spec(kind).size)*.5+WarData.radius(red.kind)+.12
	var goal := site+(WarData.point(red)-site).normalized()*minf(radius,(float(WarData.spec(kind).size)*.5+1.2)*.95)
	var record := {"kind":kind,"site":[site.x,site.y],"elapsed":float(game.state.time)-began,"completed":building.get("complete",false),"red":red.duplicate(true),"building":building.duplicate(true),"approach":[goal.x,goal.y],"approachAllowed":game.navigation.point_allowed(goal,0,"worker"),"message":game.message,"active":game.navigation.active.duplicate(true)}
	report.cases.append(record)
	var file := FileAccess.open(OUT+kind+"-snapshot.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(game.snapshot(),"  ",true,true))
	game.dispose()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	case("store",Vector2(990,1906),false)
	case("core",Vector2(987.5,1905.5),true)
	report.checks = checks; report.failures = failures
	var file := FileAccess.open(OUT+"checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ",true,true))
	print("CONSTRUCTION ACCESS ",checks-failures.size(),"/",checks)
	quit(0 if failures.is_empty() else 1)
