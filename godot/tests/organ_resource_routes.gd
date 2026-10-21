extends SceneTree
## Isolated transport fixtures: authored red/source positions, real commands and movement.
## Life hazards are disabled explicitly; geometry, gates, collision and economy stay active.
const OUT := "res://test-output/organ-resource-routes/"
var failures: Array[String] = []
var checks := 0
var report := {"scope":"isolated transport fixture; life hazard director removed; no red/resource relocation or road changes","cases":[]}

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,message: String) -> bool:
	checks += 1
	if not value: failures.append(message); printerr("FAIL ",message)
	return value

func fresh() -> WarSimulation:
	var game := WarSimulation.new(); game.start("life",73)
	game.state.erase("lifeRun") # Explicitly isolate navigation/transport from new outbreaks and life endings.
	# Medicine's newly wired state belongs to that life run, not this transport fixture.
	game.state.erase("medicineSupply"); game.state.erase("medicineRuntime")
	return game

func red_cell(game: WarSimulation) -> Dictionary:
	return game.units().filter(func(e): return e.kind == "worker" and int(e.faction) == 1)[0]

func frame(game: WarSimulation) -> void:
	game.navigation.update(20000)
	game.update(.1)

func record_state(game: WarSimulation,red: Dictionary) -> Dictionary:
	var path: Array = []
	for waypoint in red.get("path",[]):
		var p := WarData.point(waypoint.p)
		path.append({"x":p.x,"y":p.y,"lane":waypoint.lane,"organ":waypoint.get("organ",""),"gate":waypoint.get("gate","")})
	return {"time":game.state.time,"red":red.duplicate(true),"actualPath":path,"organ":game.navigation.organ_at(WarData.point(red),red.kind),"lane":red.get("vesselLane",0),"destination":game.economy._delivery_point(red),"activeNavigation":game.navigation.active.duplicate(true),"queue":game.navigation.queue.duplicate(true),"message":game.message}

func save_record(name: String,game: WarSimulation,red: Dictionary,extra: Dictionary) -> void:
	var record := record_state(game,red); record.merge(extra)
	report.cases.append(record)
	var file := FileAccess.open(OUT+name+"-state.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(record,"  ",true,true))
	file = FileAccess.open(OUT+name+"-snapshot.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(game.snapshot(),"  ",true,true))

func local_store_site(game: WarSimulation,red: Dictionary) -> Vector2:
	var origin := WarData.point(red)
	var choices: Array = []
	for y in range(-10,11):
		for x in range(-10,11):
			var p := game.economy.build_point("store",origin+Vector2(x,y))
			if p.distance_to(origin) < 2.2 or game.navigation.organ_at(p) != "small_intestine": continue
			if p.distance_to(WarData.point(game.state.resources["small_intestine.wood"])) < 3.5: continue
			if not game.navigation.clear_segment(origin,p,0,"worker") or not game.navigation.movement_clear(origin,p,"worker",1): continue
			if not game.economy.can_place("store",p,[int(red.id)]): continue
			if not game.navigation.point_allowed(p,0,"worker"): continue
			choices.append(p)
	choices.sort_custom(func(a,b): return a.distance_squared_to(origin) < b.distance_squared_to(origin))
	return choices[0] if not choices.is_empty() else Vector2.INF

func gather_and_deliver(game: WarSimulation,red: Dictionary,station: String,name: String,max_seconds := 4800.0) -> bool:
	var source: Dictionary = game.state.resources[station]
	var began := float(game.state.time)
	var original := WarData.point(red)
	var initial_delivered := float(game.state.get("delivered",0))
	var carrying := false
	var arrived := true
	var pickups := 0
	var saved := false
	var travelled := 0.0
	var last := original
	var held := true
	var peak := 0.0
	var max_step := 0.0
	var deposits := 0
	var entered_lanes: Array = []
	var stages: Array = []
	var route_events: Array = []
	var callback := func(token,path,reason):
		if route_events.size() < 30: route_events.append({"token":token,"points":path.size(),"reason":reason,"time":game.state.time})
	game.navigation.path_ready.connect(callback)
	var last_progress := began
	game.submit_player({"action":"unit_order","unit":int(red.id),"order":{"kind":"harvest","resource":station,"x":source.x,"y":source.y},"ids":[int(red.id)]})
	for i in ceili(max_seconds/.1):
		var stock := game.economy.stock(1,str(source.kind))
		var delivered_before := float(game.state.get("delivered",0))
		var stomach_before := game.economy.stomach_glucose(1)
		frame(game)
		var p := WarData.point(red)
		max_step = maxf(max_step,last.distance_to(p))
		travelled += last.distance_to(p); last = p
		if p.distance_to(original) > .001 and travelled > 0:
			if float(red.get("travelSpeed",0)) > 0: last_progress = game.state.time
		var lane := int(red.get("vesselLane",0))
		if not entered_lanes.has(lane): entered_lanes.append(lane)
		held = held and not red.orders.is_empty() and red.orders[0].get("resource","") == station
		var total := 0.0
		for amount in red.cargo.values(): total += amount
		peak = maxf(peak,total)
		if total > 0 and not carrying:
			carrying = true; pickups += 1
			arrived = arrived and lane == 0 and p.distance_to(WarData.point(source)) <= 1.5001
			stages.append({"phase":"first_pickup","time":game.state.time,"point":[p.x,p.y],"lane":lane,"cargo":red.cargo.duplicate(true)})
		if float(game.state.get("delivered",0)) > delivered_before:
			deposits += 1
			var destination := game.economy._delivery_point(red)
			stages.append({"phase":"deposit","time":game.state.time,"point":[p.x,p.y],"lane":lane,"delta":float(game.state.delivered)-delivered_before,"stockDelta":game.economy.stock(1,str(source.kind))-stock,"stomachDelta":game.economy.stomach_glucose(1)-stomach_before,"destination":[destination.x,destination.y],"organ":game.navigation.organ_at(p,"worker")})
			check(lane == 0 and (game.navigation.organ_at(p,"worker") == "heart" or game.entities().any(func(b): return b.faction == 1 and b.kind in ["core","store"] and b.get("complete",false) and WarData.point(b).distance_to(destination) < .001)),name+": deposit %d happens on heart tissue or at a real completed depot" % deposits)
			check(red.cargo.is_empty() and not red.get("delivering",false),name+": deposit %d clears carried goods" % deposits)
			check(is_equal_approx(float(stages[-1].stockDelta),14),name+": deposit %d increases inventory by exactly fourteen" % deposits)
			if source.organId == "stomach": check(is_equal_approx(float(stages[-1].stomachDelta),14),name+": deposit %d preserves actual stomach origin" % deposits)
			if deposits == 2: break
			carrying = false
		if red.get("delivering",false) and not saved:
			saved = true
			var saved_position := WarData.point(red)
			var saved_cargo: Dictionary = red.cargo.duplicate(true)
			var saved_orders: Array = red.orders.duplicate(true)
			var saved_time := float(game.state.time)
			game.paused = true
			for pause_frame in 20: game.update(.1)
			check(WarData.point(red) == saved_position and red.cargo == saved_cargo and game.state.time == saved_time,name+": pause freezes actual loaded transport")
			game.paused = false
			check(WarSave.write(game,1) == OK and WarSave.read_slot(game,1) == OK,name+": loaded courier saves and reloads through native files")
			red = game.entity(int(red.id)); source = game.state.resources[station]
			check(WarData.point(red).distance_to(saved_position) < .001 and red.cargo == saved_cargo and red.orders == saved_orders,name+": restore preserves position, cargo and harvesting assignment")
		if i > 100 and i%500 == 0: print("ROUTE ",name," t=",game.state.time-began," p=",p," lane=",lane," cargo=",total," pending=",red.pathPending," failed=",red.pathFailed)
		if float(game.state.time)-last_progress > 40: break
	var delivered := float(game.state.get("delivered",0))-initial_delivered
	var okay := deposits == 2
	check(pickups == 2 and arrived,name+": two actual pickups happen at the source tissue position")
	check(peak == float(WarOrganResources.data().capacityPerRedCell),name+": red really carries a full fourteen-unit load")
	check(okay and is_equal_approx(delivered,28),name+": two full loads really arrive and each deposits exactly once")
	check(held,name+": original harvesting assignment survives the round trip")
	check(travelled > 1,name+": red physically travels rather than being relocated")
	check(max_step <= float(WarData.spec("worker").speed)*WarSimulation.STEP*3+.005,name+": every actual tick stays within the legal maximum movement budget")
	if okay:
		check(red.cargo.is_empty() and not red.get("delivering",false),name+": deposit clears cargo and delivery flag")
		check(is_equal_approx(float(stages[-1].stockDelta),14),name+": inventory increases by exactly the carried load")
		for i in 3: frame(game)
		check(is_equal_approx(float(game.state.delivered)-initial_delivered,28),name+": next ticks do not duplicate deposit")
	game.navigation.path_ready.disconnect(callback)
	save_record(name,game,red,{"station":station,"began":began,"elapsed":float(game.state.time)-began,"travelled":travelled,"maxStep":max_step,"original":[original.x,original.y],"stages":stages,"enteredLanes":entered_lanes,"deposits":deposits,"delivered":delivered,"peakCargo":peak,"heldOrder":held,"routes":route_events})
	return okay

func short_loop() -> void:
	var game := fresh(); var red := red_cell(game)
	var original := WarData.point(red)
	check(game.units().size() == 1,"short loop starts with only the original red cell")
	# Replay the same actual initial move established by the native opening test;
	# coarse component 2 and component 1 are not proof of disconnected geometry.
	game.submit_player({"action":"unit_order","unit":int(red.id),"order":{"kind":"move","x":994.0,"y":1907.5,"lane":0},"ids":[int(red.id)]})
	for i in 80: frame(game)
	check(WarData.point(red).distance_to(Vector2(994,1907.5)) < .1,"authored red actually leaves the six-node start patch via its legal corridor")
	var site := local_store_site(game,red)
	check(site.is_finite(),"a genuinely legal local store site exists")
	if not site.is_finite(): game.dispose(); return
	var stock := game.economy.stock(1,"wood")
	game.submit_player({"action":"place","building":"store","x":site.x,"y":site.y,"ids":[int(red.id)]})
	var store: Dictionary = {}
	for i in 1200:
		frame(game)
		for e in game.entities():
			if e.kind == "store" and int(e.faction) == 1: store = e
		if not store.is_empty() and store.complete: break
	check(not store.is_empty() and store.complete,"original red builds local store by legal paid command and actual construction")
	check(is_equal_approx(stock-game.economy.stock(1,"wood"),30),"store consumes its actual thirty protein cost")
	if not store.is_empty() and store.complete:
		check(WarData.point(red).distance_to(original) > .1,"builder really moves from authored birth point")
		gather_and_deliver(game,red,"small_intestine.wood","small-intestine-local",240)
	else: save_record("local-build-stall",game,red,{"site":site,"store":store})
	game.dispose()

func inspect_blocked_site() -> void:
	var game := fresh(); var red := red_cell(game)
	game.submit_player({"action":"place","building":"store","x":990,"y":1906,"ids":[int(red.id)]})
	for i in 100: frame(game)
	var store: Dictionary = {}
	for e in game.entities():
		if e.kind == "store" and int(e.faction) == 1: store = e; break
	if store.is_empty(): game.dispose(); return
	var center := WarData.point(store)
	var radius := float(WarData.spec(store.kind).size)*.5+WarData.radius(red.kind)+.12
	var goal := center+(WarData.point(red)-center).normalized()*minf(radius,2.2*.95)
	var grid := game.navigation.grid("small_intestine",WarNavigation.profile(red.kind))
	var job := {"from":WarData.point(red),"to":goal,"kind":red.kind,"faction":1,"lane":0,"target_lane":0}
	grid.blockers = game.navigation.blockers; grid.moving_radius = WarData.radius("worker"); grid.moving_faction = 1
	var begin_ok := grid.begin(WarData.point(red),goal)
	var endpoints := {"begin":begin_ok,"start":grid._start,"goal":grid._goal,"goalPoint":grid.position_of(grid._goal),"goalBlocked":grid.point_blocked(grid.position_of(grid._goal)),"startPoint":grid.position_of(grid._start),"startBlocked":grid.point_blocked(grid.position_of(grid._start))}
	var with_building := game.navigation._plan(job)
	var original_blockers := game.navigation.blockers
	game.navigation.blockers = []
	var without_building := game.navigation._plan(job)
	game.navigation.blockers = original_blockers
	var alternatives: Array = []
	for i in 32:
		var p := center+Vector2.from_angle(TAU*i/32)*2.1
		if game.navigation.point_allowed(p,0,"worker") and game.navigation.movement_clear(p,p,"worker",1): alternatives.append([p.x,p.y])
	save_record("blocked-site-diagnostic",game,red,{"approach":[goal.x,goal.y],"approachOrgan":game.navigation.organ_at(goal,"worker"),"approachAllowed":game.navigation.point_allowed(goal,0,"worker"),"startComponent":grid.component(WarData.point(red)),"goalComponent":grid.component(goal),"planLegsWithBuilding":with_building,"planLegsWithoutBuilding":without_building,"legalApproachCandidates":alternatives,"store":store,"gridEndpoints":endpoints})
	game.dispose()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	WarSave.directory = "user://test-saves/organ-resource-routes"
	if OS.get_cmdline_user_args().has("--inspect-blocked"):
		inspect_blocked_site(); quit(); return
	if not OS.get_cmdline_user_args().has("--stations-only"): short_loop()
	if not OS.get_cmdline_user_args().has("--short-only"):
		for station in ["small_intestine.wood","large_intestine.wood","lung_r.oxygen","lung_l.oxygen","stomach.food"]:
			var game := fresh(); var red := red_cell(game)
			gather_and_deliver(game,red,station,station.replace(".","-"))
			game.dispose()
	report.checks = checks; report.failures = failures
	DirAccess.remove_absolute(WarSave.path(1))
	var filename := "checks-short.json" if OS.get_cmdline_user_args().has("--short-only") else ("checks-stations.json" if OS.get_cmdline_user_args().has("--stations-only") else "checks.json")
	var file := FileAccess.open(OUT+filename,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ",true,true))
	print("ORGAN RESOURCE ROUTES ",checks-failures.size(),"/",checks)
	quit(0 if failures.is_empty() else 1)
