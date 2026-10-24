extends SceneTree
## Normal resources and public player commands only. No injected units or damage.
var game := WarSimulation.new()
var milestones: Array = []
var site := Vector2.INF
var barracks_id := 0
var recruited := false
var attacked := false
var cleaning := false
var next_report := 0.0
var farm_id := 0
var farming := false
var harvesting := false
var resumed := false
var session := WarSaveSession.new()
var extended := false
var peak_update_usec := 0
var slow_updates := 0
const OUTPUT := "res://test-output/left-lung-playthrough-20261023/"

func _initialize() -> void:
	call_deferred("run")

func mark(event: String) -> void:
	var row := {"event":event,"time":snappedf(float(game.state.time),.1),"wood":game.economy.stock(1,"wood"),"food":game.economy.stock(1,"food"),"units":game.units().filter(func(e): return e.faction == 1).size()}
	milestones.append(row); print(JSON.stringify(row))

func find_site(worker: Dictionary,kind := "barracks") -> Vector2:
	var best := Vector2.INF
	var distance := INF
	for x in range(-20,21):
		for y in range(-20,21):
			var p := game.economy.build_point(kind,WarData.point(worker)+Vector2(x,y))
			var d := WarData.point(worker).distance_squared_to(p)
			if d < 100 or d >= distance or not game.economy.can_place(kind,p,[int(worker.id)]): continue
			if not game.navigation.clear_segment(WarData.point(worker),p,0,"worker"): continue
			best = p; distance = d
	return best

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	extended = "--economy-resume" in OS.get_cmdline_user_args()
	WarSave.directory = "user://test-saves/left-lung-"+str(Time.get_ticks_usec())
	game.start("lung_defense",73)
	if extended: assert(session.create(game) == OK)
	var worker := game.entity(int(game.state.lungDefense.workers[0]))
	site = find_site(worker)
	if not site.is_finite(): printerr("FAIL no legal starter barracks site"); quit(1); return
	game.submit_player({"action":"place","building":"barracks","x":site.x,"y":site.y,"ids":[int(worker.id)]})
	mark("place_barracks")
	if extended:
		var farmer := game.entity(int(game.state.lungDefense.workers[1]))
		var farm_site := find_site(farmer,"farm")
		game.submit_player({"action":"place","building":"farm","x":farm_site.x,"y":farm_site.y,"ids":[int(farmer.id)]})
	for frame in 9000:
		var began := Time.get_ticks_usec()
		game.update(.1)
		var elapsed := Time.get_ticks_usec()-began
		peak_update_usec = maxi(peak_update_usec,elapsed)
		if elapsed > 16000: slow_updates += 1
		play()
		if game.state.time >= next_report:
			print(JSON.stringify(diagnostics()))
			next_report += 30
		if game.state.lungDefense.phase == "failed": break
		if game.state.lungDefense.phase == "defended" and (not extended or game.economy.stock(1,"oxygen") >= 14): break
		if extended and not resumed and game.state.time >= 210:
			mark("save_mid_battle")
			assert(session.save(game) == OK)
			var before := game.snapshot()
			assert(session.resume(game,session.active_path) == OK)
			assert(game.state.time == before.time and game.economy.stock(1,"wood") == float(before.factions[0].stock.wood))
			resumed = true
			mark("resume_mid_battle")
		if frame%20 == 0: await process_frame
	var won: bool = game.state.lungDefense.phase == "defended"
	if extended:
		won = won and resumed and game.economy.stock(1,"oxygen") >= 14 and float(game.state.get("farmed",0)) >= 16 and game.economy.stock(1,"food") >= 69
		assert(session.save(game) == OK)
		assert(session.resume(game,session.active_path) == OK)
		won = won and game.state.lungDefense.phase == "defended"
	mark("victory" if won else "not_completed")
	var file := FileAccess.open(OUTPUT+("economy-resume.json" if extended else "playthrough.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"milestones":milestones,"final":diagnostics(),"snapshot":game.snapshot(),"peak_update_usec":peak_update_usec,"updates_over_16ms":slow_updates},"",true,true)); file.close()
	print("LEFT_LUNG_PLAYTHROUGH ","PASS" if won else "FAIL")
	game.dispose()
	quit(0 if won else 1)

func play() -> void:
	var barracks := game.entity(barracks_id)
	if barracks.is_empty():
		for e in game.entities():
			if e.kind == "barracks" and e.faction == 1: barracks_id = int(e.id); barracks = e; break
	if not barracks.is_empty() and barracks.complete and not recruited:
		mark("barracks_complete")
		for i in 6: game.submit_player({"action":"train","target":barracks_id,"unit":"spear"})
		recruited = true
	if extended:
		for e in game.entities():
			if e.faction == 1 and e.kind == "farm":
				farm_id = int(e.id)
				if e.complete and not farming:
					game.submit_player({"action":"unit_order","unit":int(game.state.lungDefense.workers[1]),"order":{"kind":"farm","target":farm_id}})
					farming = true; mark("farm_work_started")
	var whites := game.units().filter(func(e): return e.faction == 1 and e.kind == "spear")
	var colony: Dictionary = game.state.influenzaColonies.groups.get(game.state.lungDefense.colony,{})
	if not attacked and whites.size() >= 6 and not colony.is_empty():
		mark("attack_with_six")
		var ids: Array[int] = []
		for e in whites: ids.append(int(e.id))
		game.submit_player({"action":"issue","kind":"attackmove","x":colony.center[0],"y":colony.center[1],"ids":ids})
		attacked = true
	if attacked and not cleaning and not colony.is_empty() and game.influenza.members(colony).is_empty() and game.influenza.forts(colony).is_empty() and int(colony.pending) == 0:
		mark("enemies_cleared")
		var ids: Array[int] = []
		var reds := game.units().filter(func(e): return e.faction == 1 and e.kind == "worker")
		reds.sort_custom(func(a,b): return int(a.id) < int(b.id))
		for e in reds.slice(0,2)+whites: ids.append(int(e.id))
		game.submit_player({"action":"issue","kind":"move","x":colony.center[0],"y":colony.center[1],"ids":ids})
		cleaning = true
	if extended and cleaning and not harvesting:
		var gatherer := int(game.state.lungDefense.workers[2])
		game.submit_player({"action":"unit_order","unit":gatherer,"order":{"kind":"harvest","resource":"5252285"}})
		harvesting = true; mark("gather_lung_oxygen")

func diagnostics() -> Dictionary:
	var friendly: Array = []
	for e in game.units():
		if e.faction == 1 and (e.kind == "spear" or int(e.id) == int(game.state.lungDefense.workers[0])):
			friendly.append({"id":e.id,"kind":e.kind,"hp":e.hp,"p":[e.x,e.y],"orders":e.orders,"failed":e.get("pathFailed",false),"pending":e.get("pathPending",false),"path":e.get("path",[])})
	return {"time":snappedf(float(game.state.time),.1),"phase":game.state.lungDefense.phase,"friendly":friendly,"colonies":game.state.influenzaColonies,"enemies":game.units().filter(func(e): return e.faction == 2).size(),"forts":game.entities().filter(func(e): return e.kind == "flu_fortress").size(),"nav_queue":game.navigation.queue.size(),"message":game.message}
