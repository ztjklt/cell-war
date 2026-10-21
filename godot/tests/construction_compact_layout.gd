extends SceneTree
const OUT := "res://test-output/construction-compact-layout/"
var checks := 0
var failures: Array[String] = []
var report := {"stages":[],"probes":[],"cornerCertificates":[]}

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("FAIL ",message)

func frame(game: WarSimulation) -> void:
	game.navigation.update(20000); game.update(.1)

func build(game: WarSimulation,kind: String,p: Vector2) -> Dictionary:
	var before := game.economy.stock(1,"wood")
	game.submit_player({"action":"place","building":kind,"x":p.x,"y":p.y,"ids":[25]})
	var site: Dictionary = {}
	var began := float(game.state.time)
	var clear := true
	var plane := true
	var max_step := 0.0
	var previous := WarData.point(game.entity(25))
	var moves: Array = []
	for i in 1800:
		frame(game)
		var actor := game.entity(25)
		var point := WarData.point(actor)
		max_step = maxf(max_step,previous.distance_to(point))
		plane = plane and int(actor.vesselLane) == 0
		var trail: Array = actor.get("renderTrail",[])
		for segment in range(1,trail.size()):
			clear = clear and game.navigation.clear_segment(trail[segment-1],trail[segment],0,"worker") and game.navigation.movement_clear(trail[segment-1],trail[segment],"worker",1)
		if point.distance_to(previous) > .001 and (moves.is_empty() or float(game.state.time)-float(moves[-1].time) > .5): moves.append({"x":point.x,"y":point.y,"time":game.state.time})
		previous = point
		for e in game.entities():
			if e.kind == kind and int(e.faction) == 1: site = e; break
		if not site.is_empty() and site.complete: break
	check(not site.is_empty() and site.complete,"original red completes compact "+kind)
	check(clear and plane,"every actual compact-layout movement segment preserves tissue and building clearance")
	check(max_step <= float(WarData.spec("worker").speed)*WarSimulation.STEP+.001,"compact builder never exceeds its ordinary movement budget")
	check(is_equal_approx(before-game.economy.stock(1,"wood"),float(WarData.spec(kind).cost.wood)),"compact layout pays actual "+kind+" cost exactly once")
	report.stages.append({"kind":kind,"site":[p.x,p.y],"elapsed":float(game.state.time)-began,"progress":site.get("progress",0),"red":game.entity(25).duplicate(true),"charged":before-game.economy.stock(1,"wood"),"moves":moves,"clear":clear,"plane":plane,"maxStep":max_step})
	return site

func probe(game: WarSimulation,p: Vector2) -> Dictionary:
	var result := {"point":[p.x,p.y],"done":false,"path":[],"reason":"timeout"}
	var token := game.navigation.request(game.entity(25),p,0)
	var receive := func(id,path,reason):
		if id == token: result.done = true; result.path = path.duplicate(true); result.reason = reason
	game.navigation.path_ready.connect(receive)
	var began := Time.get_ticks_msec()
	while not result.done and Time.get_ticks_msec()-began < 5000: game.navigation.update(20000)
	game.navigation.path_ready.disconnect(receive); game.navigation.cancel(token)
	return result

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var game := WarSimulation.new(); game.start("life",73)
	for key in ["lifeRun","medicineSupply","medicineRuntime"]: game.state.erase(key)
	game.submit_player({"action":"unit_order","unit":25,"order":{"kind":"move","x":994,"y":1907.5,"lane":0}})
	for i in 80: frame(game)
	check(WarData.point(game.entity(25)).distance_to(Vector2(994,1907.5)) < .1,"original red walks out of birth pocket")
	build(game,"core",Vector2(987.5,1905.5))
	var barracks := build(game,"barracks",Vector2(981.5,1905.5))
	check(game.navigation._building_corner_detour(WarData.point(game.entity(25)),Vector2(987.5,1905.5),"worker",1,"small_intestine").is_empty(),"exact-corner fallback cannot route into an occupied building interior")
	if not barracks.is_empty() and not barracks.complete:
		var actor := game.entity(25)
		var core: Dictionary = game.entities().filter(func(e): return e.kind == "core" and int(e.faction) == 1)[0]
		var core_extent := 1.5+WarData.radius("worker")
		var target := game.navigation.building_approach(actor,barracks,2.7)
		for sign_y in [-1.0,1.0]:
			for margin in [.002,.01,.02,.05,.12,.25,.5,1.0]:
				var points := [WarData.point(actor),WarData.point(core)+Vector2(core_extent+margin,sign_y*(core_extent+margin)),WarData.point(core)+Vector2(-core_extent-margin,sign_y*(core_extent+margin)),target]
				var cert: Array = []
				for segment in range(1,points.size()):
					cert.append({"from":points[segment-1],"to":points[segment],"ground":game.navigation.clear_segment(points[segment-1],points[segment],0,"worker"),"building":game.navigation.movement_clear(points[segment-1],points[segment],"worker",1)})
				report.cornerCertificates.append({"sign":sign_y,"margin":margin,"segments":cert})
		var extent := 1.5+WarData.radius("worker")+.12
		var span := sqrt(pow(2.7*.95,2)-extent*extent)
		for i in 9:
			var along := lerpf(-span,span,float(i)/8)
			for offset in [Vector2(-extent,along),Vector2(extent,along),Vector2(along,-extent),Vector2(along,extent)]:
				var p: Vector2 = WarData.point(barracks)+offset
				if game.navigation.point_allowed(p,0,"worker") and game.navigation.movement_clear(p,p,"worker",1): report.probes.append(probe(game,p))
		report.preferred = game.navigation.building_approach(actor,barracks,2.7)
	report.checks = checks; report.failures = failures
	var prefix := "baseline" if OS.get_cmdline_user_args().has("--baseline") else "checks"
	var file := FileAccess.open(OUT+prefix+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ",true,true))
	file = FileAccess.open(OUT+prefix+"-snapshot.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(game.snapshot(),"  ",true,true))
	game.dispose()
	print("CONSTRUCTION COMPACT ",checks-failures.size(),"/",checks)
	quit(0 if failures.is_empty() else 1)
