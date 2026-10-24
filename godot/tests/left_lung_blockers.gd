extends SceneTree
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ",label)

func run() -> void:
	var game := WarSimulation.new(); game.start("lung_defense",73)
	var workers := game.units().filter(func(e): return e.faction == 1 and e.kind == "worker")
	workers.sort_custom(func(a,b): return int(a.id) < int(b.id))
	var target := Vector2(1232.25549,1226.91052)
	var ids: Array[int] = [int(workers[0].id),int(workers[1].id)]
	game.submit_player({"action":"issue","kind":"move","x":target.x,"y":target.y,"ids":ids})
	var legal := true
	for i in 900:
		var previous: Dictionary = {}
		for id in ids: previous[id] = WarData.point(game.entity(id))
		game.update(.1)
		for id in ids:
			var e := game.entity(id)
			legal = legal and e.vesselLane == 0 and game.navigation.organ_at(WarData.point(e),e.kind) == "lung_l"
			legal = legal and game.navigation.clear_segment(previous[id],WarData.point(e),0,e.kind) and game.navigation.movement_clear(previous[id],WarData.point(e),e.kind,1)
		if i%20 == 0: await process_frame
	check(ids.all(func(id): return WarData.point(game.entity(id)).distance_to(target) < 7),"first two red cells can leave their idle squad and reach infection site")
	check(legal,"avoidance never changes organ or lane")
	var base := game.entity(int(game.state.lungDefense.base))
	check(game.economy._delivery_point(workers[2]).distance_to(WarData.point(base)) < .01,"left-lung worker returns resources to local core instead of distant heart")
	# A group move may be clicked over a building; formation must use free ground.
	var places := game.formation([workers[2],workers[3]],WarData.point(base),0)
	check(places.values().all(func(p): return not p.get("failed",false) and game.navigation.movement_clear(Vector2(p.x,p.y),Vector2(p.x,p.y),"worker",1)),"formation destinations avoid building footprints")
	game.dispose()
	game = WarSimulation.new(); game.start("lung_defense",73)
	var gatherer := int(game.state.lungDefense.workers[2])
	game.submit_player({"action":"unit_order","unit":gatherer,"order":{"kind":"harvest","resource":"5252285"}})
	for i in 1800:
		game.update(.1)
		if game.economy.stock(1,"oxygen") >= 14: break
		if i%20 == 0: await process_frame
	check(game.economy.stock(1,"oxygen") >= 14,"original red harvests and delivers oxygen through the crowded starting squad")
	game.dispose()
	print("LEFT_LUNG_BLOCKERS ",checks-failures.size(),"/",checks)
	quit(0 if failures.is_empty() else 1)
