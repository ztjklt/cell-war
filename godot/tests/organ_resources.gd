extends SceneTree
var failures: Array[String] = []
var checks := 0
var report := {"routes":[]}

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("FAIL ",message)

func frame(game: WarSimulation,seconds: float) -> void:
	for i in int(round(seconds/.1)):
		game.navigation.update(10000)
		game.update(.1)

func run() -> void:
	WarSave.directory = "user://test-saves/organ-resources"
	var game := WarSimulation.new(); game.start("life",73)
	check(game.organ_resources.enabled() and game.state.resources.size() == 5,"life starts with all five organ stations")
	var red := game.units().filter(func(e): return e.faction == 1)[0] as Dictionary
	check(game.units().filter(func(e): return e.faction == 1).size() == 1 and red.kind == "worker","new organ economy still starts with one red")
	check(game.economy.stock(1,"wood") == 160 and game.economy.stock(1,"food") == 125,"initial construction and first-white funds remain available")
	for spec in WarOrganResources.data().sources:
		if not game.state.resources.has(spec.id):
			check(false,spec.id+" exists before route verification")
			continue
		var node: Dictionary = game.state.resources[spec.id]
		var point := WarData.point(node)
		check(game.navigation.organ_at(point,"worker") == spec.organ and game.navigation.point_allowed(point,0,"worker"),spec.id+" is on its authored tissue plane")
		var path: Array = []
		var token := game.navigation.request(red,point,0)
		var callback := func(id,points,_reason):
			if id == token: path.assign(points)
		game.navigation.path_ready.connect(callback)
		for i in 500:
			game.navigation.update(30000)
			if not path.is_empty(): break
		game.navigation.path_ready.disconnect(callback)
		check(not path.is_empty(),spec.id+" has an actual navigation route from the starting red")
		report.routes.append({"station":spec.id,"waypoints":path.size()})
		game.navigation.cancel(token)
	var protein: Dictionary = game.state.resources["small_intestine.wood"]
	protein.amount = 0.0
	game.order(red,{"kind":"harvest","resource":protein.id,"x":protein.x,"y":protein.y})
	frame(game,1)
	check(not red.orders.is_empty() and red.orders[0].resource == protein.id,"depleted renewable station retains the harvesting assignment")
	check(is_equal_approx(protein.amount,1.0),"safe intestine protein refills at one unit per simulation second")
	game.paused = true; var amount := float(protein.amount)
	frame(game,4)
	check(protein.amount == amount,"pause freezes station recovery")
	game.paused = false; game.speed = 2.0
	game.order(red,{"kind":"hold"}); frame(game,1)
	check(is_equal_approx(protein.amount,amount+2),"two-times speed advances station refill by two simulated seconds")
	game.speed = 1.0
	var enemy := game.spawn("virus",2,WarData.point(protein)+Vector2(0,2))
	check(not enemy.is_empty(),"contest fixture is a legally placed virus")
	enemy.vesselLane = 0
	check(game.organ_resources.contested(protein),"same tissue enemy contests the station")
	enemy.vesselLane = 145
	check(not game.organ_resources.contested(protein),"projected blood-lane enemy cannot contest tissue station")
	enemy.vesselLane = 0
	amount = protein.amount
	game.organ_resources.advance(.5)
	check(protein.contested and protein.amount == amount,"enemy presence stops refill")
	game.state.entities.erase(str(enemy.id)); game.organ_resources.advance(.5)
	check(not protein.contested and protein.amount > amount,"removing enemy restores production")
	protein.amount = protein.max-.1; game.organ_resources.advance(.5)
	check(protein.amount == protein.max,"refill is capped at station capacity")
	check(WarSave.write(game,1) == OK,"organ source state saves to an isolated slot")
	protein.amount = 0; check(WarSave.read_slot(game,1) == OK,"organ source state loads")
	check(game.state.resources[protein.id].amount == protein.max,"restoring does not regenerate or erase stored stock")
	var bad := game.snapshot(); bad.resources[protein.id].amount = -1
	check(not WarSave.validate(bad).is_empty(),"negative station inventory is rejected")
	bad = game.snapshot(); bad.resources[protein.id].vesselLane = 1
	check(not WarSave.validate(bad).is_empty(),"station plane tampering is rejected")
	red = game.entity(25)
	var center := WarData.point(red)
	var depot_point := center
	var local_grid := game.navigation.grid("small_intestine","siege")
	for i in 16:
		var candidate := center+Vector2.from_angle(i*TAU/16)*4
		if game.navigation.organ_at(candidate) == "small_intestine" and local_grid.component(candidate) == local_grid.component(center):
			depot_point = candidate; break
	var depot := game.spawn("store",1,depot_point,"building")
	check(not depot.is_empty() and game.navigation.organ_at(WarData.point(depot)) == "small_intestine","local depot fixture occupies legal starting organ")
	report.depot = {"red":[red.x,red.y],"depot":[depot.x,depot.y],"lane":depot.vesselLane,"redComponent":game.navigation.grid("small_intestine","siege").component(WarData.point(red)),"depotComponent":game.navigation.grid("small_intestine","siege").component(WarData.point(depot)),"destination":game.economy._delivery_point(red)}
	check(game.economy._delivery_point(red).distance_to(WarData.point(depot)) < .001,"same-organ completed depot replaces the distant heart journey")
	depot.complete = false
	check(game.economy._delivery_point(red).distance_to(WarData.point(depot)) > 1,"unfinished depot cannot receive cargo")
	depot.complete = true
	var receiver := depot_point.move_toward(center,2.0)
	red.x = receiver.x; red.y = receiver.y
	red.cargo = {"food":10.0,"wood":2.0}; red.cargoStomachGlucose = 3.0; red.delivering = true
	var stomach_before := game.economy.stomach_glucose(1)
	var stock_before := game.economy.stock(1,"wood")
	game.economy.harvest(red,{"resource":"small_intestine.wood"},.1)
	check(red.cargo.is_empty() and game.economy.stock(1,"wood") == stock_before+2,"physical delivery deposits every resource once")
	check(game.economy.stomach_glucose(1) == stomach_before+3,"mixed glucose marks only the three stomach-origin units")
	game.economy.harvest(red,{"resource":"small_intestine.wood"},.1)
	check(game.economy.stock(1,"wood") == stock_before+2,"next harvesting tick does not duplicate delivered cargo")
	game.start("fullbody")
	check(not game.organ_resources.enabled() and game.state.resources.size() == 5 and game.state.resources.values().any(func(r): return r.organId == "liver"),"frozen legacy fullbody resources are preserved")
	game.dispose()
	DirAccess.make_dir_recursive_absolute("res://test-output/organ-resources")
	report.checks = checks; report.failures = failures
	var file := FileAccess.open("res://test-output/organ-resources/checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ",true,true))
	print("ORGAN RESOURCES ",checks-failures.size(),"/",checks)
	quit(0 if failures.is_empty() else 1)
