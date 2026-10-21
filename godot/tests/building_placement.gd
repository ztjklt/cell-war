extends SceneTree
## Controlled occupancy fixtures; each attempt calls actual economy.place or the
## actual queued place command and inspects inventory/entities, never a mock pay.
const OUT := "res://test-output/building-placement/"
var failures: Array[String] = []
var checks := 0
var records: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("FAIL ",message)

func fixture() -> WarSimulation:
	var game := WarSimulation.new(); game.start("cell_test",73)
	return game

func frame(game: WarSimulation) -> void:
	game.navigation.update(10000); game.update(.1)

func inventory(game: WarSimulation) -> Dictionary:
	return {"wood":game.economy.stock(1,"wood"),"food":game.economy.stock(1,"food"),"oxygen":game.economy.stock(1,"oxygen")}

func attempt(game: WarSimulation,kind: String,p: Vector2,expected: bool,label: String,append := false) -> bool:
	var red: Dictionary = game.units().filter(func(e): return e.kind == "worker" and int(e.faction) == 1)[0]
	var before := inventory(game)
	var count := game.entities().size()
	var next_id := int(game.state.nextId)
	var orders: Array = red.orders.duplicate(true)
	var allowed := game.economy.can_place(kind,p,[int(red.id)])
	var placed := game.economy.place(kind,p,[int(red.id)],1,append)
	check(allowed == expected and placed == expected,label+": preview and real placement agree")
	if not expected:
		check(inventory(game) == before,label+": rejected placement charges no resources")
		check(game.entities().size() == count and int(game.state.nextId) == next_id,label+": rejected placement creates no blueprint or allocated id")
		check(red.orders == orders,label+": rejection preserves the existing worker order")
		check(not game.message.is_empty(),label+": rejection has an explicit reason")
	else:
		check(game.entities().size() == count+1,label+": actual blueprint is created")
		var expected_stock := before.duplicate()
		for resource in WarData.spec(kind).cost: expected_stock[resource] -= float(WarData.spec(kind).cost[resource])
		check(inventory(game) == expected_stock,label+": blueprint pays the exact original cost once")
	records.append({"label":label,"point":[p.x,p.y],"expected":expected,"allowed":allowed,"placed":placed,"before":before,"after":inventory(game),"newEntities":game.entities().size()-count,"reason":game.message})
	return placed

func occupancy_cases() -> void:
	var game := fixture()
	game.order(game.entity(1),{"kind":"hold"})
	var original := WarData.point(game.entity(1))
	var covered := attempt(game,"store",Vector2(100,99),false,"construction actor inside blueprint")
	if OS.get_cmdline_user_args().has("--baseline") and covered:
		game.order(game.entity(1),{"kind":"move","x":104,"y":99,"lane":0})
		for i in 100: frame(game)
		records[-1].actualTrapped = WarData.point(game.entity(1)).distance_to(original) < .001
		records[-1].actor = game.entity(1).duplicate(true)
	game.dispose()
	game = fixture()
	attempt(game,"store",Vector2(100,104),false,"live friendly white inside blueprint")
	game.dispose()
	game = fixture()
	attempt(game,"store",Vector2(108,104),false,"live enemy inside tissue blueprint")
	game.dispose()
	game = fixture()
	attempt(game,"store",Vector2(101,99),false,"partial live red-cell footprint overlap")
	game.dispose()
	game = fixture()
	game.entity(2).hp = 0 # Explicit dead-unit occupancy fixture; not synthetic combat evidence.
	attempt(game,"store",Vector2(100,104),true,"dead unit does not reserve a footprint")
	game.dispose()
	game = fixture()
	var border := game.spawn("worker",1,Vector2(111.59375,110))
	check(not border.is_empty(),"legal touching-cell fixture spawns")
	attempt(game,"store",Vector2(110,110),true,"unit bounding footprint touches without penetrating")
	game.dispose()

func building_cases() -> void:
	var game := fixture()
	# The authored cell-test store is at (96.5,98.5), side 2. Incoming (98,100)
	# has a 0.5 x 0.5 real overlap while the center distance exceeds radius sum 2.
	attempt(game,"store",Vector2(98,100),false,"diagonal positive-area overlap with authored completed store")
	game.dispose()
	game = fixture()
	check(game.economy.place("store",Vector2(110,110),[1]),"blueprint fixture is created through real paid placement")
	var first: Dictionary = game.entity(int(game.state.nextId)-1)
	check(not first.complete,"new blueprint reserves ground before completion")
	attempt(game,"house",Vector2(111,110),false,"unfinished blueprint blocks overlapping construction")
	game.dispose()
	game = fixture()
	check(game.economy.place("store",Vector2(110,110),[1]),"touching fixture pays for first blueprint")
	attempt(game,"store",Vector2(112,110),true,"square buildings may legally share a boundary edge")
	game.dispose()
	game = fixture()
	check(game.economy.place("store",Vector2(110,110),[1]),"corner fixture pays for first blueprint")
	attempt(game,"store",Vector2(112,112),true,"square buildings may legally touch at a corner")
	game.dispose()
	game = fixture()
	var initial: Dictionary = game.entity(int(game.state.cellTest.building))
	initial.hp = 0
	attempt(game,"store",Vector2(96,98),true,"destroyed building does not keep a live footprint")
	game.dispose()

func layer_case() -> void:
	var game := WarSimulation.new(); game.start("life",73)
	game.state.erase("lifeRun")
	game.state.erase("medicineSupply"); game.state.erase("medicineRuntime")
	var red: Dictionary = game.units()[0]
	var chosen := Vector2.INF
	var lane_id := -1
	for lane in WarData.read("vessels").lanes:
		if int(lane.lane) >= 203: continue
		for raw in lane.points:
			var p := game.economy.build_point("store",WarData.point(raw))
			if not game.navigation.point_allowed(p,int(lane.lane),"spear"): continue
			if game.navigation.pick_lane(p,"store") != 0 or not game.economy.can_place("store",p,[int(red.id)]): continue
			chosen = p; lane_id = int(lane.lane); break
		if chosen.is_finite(): break
	check(chosen.is_finite(),"actual tissue/blood projection offers a legal two-plane fixture")
	if chosen.is_finite():
		var white := game.spawn("spear",1,chosen)
		white.vesselLane = lane_id
		check(game.navigation.point_allowed(WarData.point(white),lane_id,"spear"),"projected white actually occupies its authored vascular domain")
		attempt(game,"store",chosen,true,"another vascular plane does not block tissue construction")
	game.dispose()

func queue_and_append_cases() -> void:
	var game := fixture()
	check(game.economy.can_place("store",Vector2(104,100),[1]),"queued site initially has no live occupant")
	game.submit_player({"action":"unit_order","unit":2,"order":{"kind":"move","x":104,"y":100,"lane":0}})
	for i in 150:
		frame(game)
		if WarData.point(game.entity(2)).distance_to(Vector2(104,100)) < .1: break
	check(WarData.point(game.entity(2)).distance_to(Vector2(104,100)) < .1,"friendly physically walks into the formerly clear placement")
	var before := inventory(game); var count := game.entities().size(); var id := int(game.state.nextId)
	game.submit_player({"action":"unit_order","unit":2,"order":{"kind":"hold"}})
	game.submit_player({"action":"place","building":"store","x":104,"y":100,"ids":[1]})
	frame(game)
	check(inventory(game) == before and int(game.state.nextId) == id and game.entities().size() == count,"queued commit rechecks live occupancy without payment or blueprint")
	check(game.message.contains("细胞"),"queued rejection identifies cell occupancy")
	game.dispose()
	game = fixture()
	game.order(game.entity(1),{"kind":"move","x":104,"y":99,"lane":0})
	# Restore the original diagonal regression now that building approach is fixed.
	attempt(game,"store",Vector2(112,110),true,"distant diagonal placement with append",true)
	check(game.entity(1).orders.size() == 2 and game.entity(1).orders[0].kind == "move" and game.entity(1).orders[1].kind == "build","append retains move before the new build order")
	var building := game.entity(int(game.state.nextId)-1)
	for i in 1000:
		frame(game)
		if building.complete: break
	check(building.complete,"distant appended build really executes after the original move")
	game.dispose()

func inspect_diagonal_access() -> void:
	var game := fixture()
	game.order(game.entity(1),{"kind":"move","x":104,"y":99,"lane":0})
	game.economy.place("store",Vector2(112,110),[1],1,true)
	for i in 200: frame(game)
	var red := game.entity(1)
	var site := Vector2(112,110)
	var radius := 1.0+WarData.radius("worker")+.12
	var approach := site+(WarData.point(red)-site).normalized()*minf(radius,2.2*.95)
	var file := FileAccess.open(OUT+"diagonal-access-state.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"red":red,"time":game.state.time,"site":[112,110],"approach":[approach.x,approach.y],"terrainAllowed":game.navigation.point_allowed(approach,0,"worker"),"buildingClearance":game.navigation.movement_clear(approach,approach,"worker",1),"active":game.navigation.active,"queue":game.navigation.queue},"  ",true,true))
	file = FileAccess.open(OUT+"diagonal-access-snapshot.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(game.snapshot(),"  ",true,true))
	game.dispose()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	if OS.get_cmdline_user_args().has("--inspect-access"):
		inspect_diagonal_access(); quit(); return
	occupancy_cases(); building_cases(); layer_case(); queue_and_append_cases()
	var filename := "baseline.json" if OS.get_cmdline_user_args().has("--baseline") else "checks.json"
	var file := FileAccess.open(OUT+filename,FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"records":records,"scope":"explicit occupancy fixtures; actual placement/payment/queued commands and movement"},"  ",true,true))
	print("BUILDING PLACEMENT ",checks-failures.size(),"/",checks)
	quit(0 if failures.is_empty() else 1)
