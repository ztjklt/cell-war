extends SceneTree
## Geometry/transport fixture: authored cell-test red and terrain; other units
## removed to isolate building approach from unrelated troop traffic/combat.
const OUT := "res://test-output/construction-approach/"
var checks := 0
var failures: Array[String] = []
var records: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("FAIL ",message)

func fixture() -> WarSimulation:
	var game := WarSimulation.new(); game.start("cell_test",73)
	for e in game.units():
		if int(e.id) != int(game.state.cellTest.red): game.state.entities.erase(str(e.id))
	return game

func frame(game: WarSimulation) -> void:
	game.navigation.update(10000); game.update(.1)

func run_case(kind: String,site: Vector2,move_first := false,blocked_side := false) -> void:
	var game := fixture()
	var red := game.entity(int(game.state.cellTest.red))
	var birth := WarData.point(red)
	if move_first:
		game.submit_player({"action":"unit_order","unit":int(red.id),"order":{"kind":"move","x":104,"y":99,"lane":0}})
		for i in 80: frame(game)
		check(WarData.point(red).distance_to(Vector2(104,99)) < .1,"original red really walks to the reported starting point")
	var obstacle: Dictionary = {}
	if blocked_side:
		check(game.economy.place("store",site-Vector2(0,3),[int(red.id)]),"side obstruction is a real paid blueprint")
		obstacle = game.entity(int(game.state.nextId)-1)
	var before := game.economy.stock(1,"wood")
	check(game.economy.can_place(kind,site,[int(red.id)]),"reported diagonal site remains a legal placement: "+str(site))
	game.submit_player({"action":"place","building":kind,"x":site.x,"y":site.y,"ids":[int(red.id)]})
	var building: Dictionary = {}
	var started := float(game.state.time)
	var maximum_step := 0.0
	var previous := WarData.point(red)
	var stayed_clear := true
	var layer_preserved := true
	var first_route: Array = []
	var saved := false
	for i in 1200:
		frame(game)
		maximum_step = maxf(maximum_step,previous.distance_to(WarData.point(red)))
		previous = WarData.point(red)
		layer_preserved = layer_preserved and int(red.vesselLane) == 0
		if not red.path.is_empty() and first_route.is_empty(): first_route = red.path.duplicate(true)
		for b in game.entities():
			if b.kind == kind and WarData.point(b).distance_to(site) < .01: building = b; break
		if building.is_empty(): continue
		stayed_clear = stayed_clear and game.navigation.movement_clear(WarData.point(red),WarData.point(red),red.kind,1)
		if move_first and not blocked_side and float(building.progress) >= .25 and not saved and not building.complete:
			saved = true
			game.paused = true
			var point := WarData.point(red); var progress := float(building.progress)
			for pause_frame in 10: game.update(.1)
			check(WarData.point(red) == point and building.progress == progress,"pause holds real movement and construction progress")
			game.paused = false
			var id := int(building.id); var actor := int(red.id)
			check(WarSave.write(game,1) == OK and WarSave.read_slot(game,1) == OK,"diagonal construction saves and reloads natively")
			red = game.entity(actor); building = game.entity(id)
			check(WarData.point(red).distance_to(point) < .001 and is_equal_approx(float(building.progress),progress),"restore preserves actual work position and partial construction")
		if building.complete: break
	check(not building.is_empty() and building.complete,"actual diagonal construction completes: "+kind+" "+str(site))
	check(stayed_clear and layer_preserved,"builder stays outside every building and on its original plane")
	check(maximum_step <= float(WarData.spec("worker").speed)*WarSimulation.STEP+.001,"builder uses ordinary movement budget without relocation")
	check(is_equal_approx(before-game.economy.stock(1,"wood"),float(WarData.spec(kind).cost.wood)),"diagonal build charges the original cost exactly once")
	if blocked_side: check(not obstacle.complete,"alternate approach does not erase or auto-complete the obstructing blueprint")
	records.append({"kind":kind,"site":[site.x,site.y],"birth":[birth.x,birth.y],"actor":[red.x,red.y],"elapsed":float(game.state.time)-started,"complete":building.get("complete",false),"progress":building.get("progress",0),"path":first_route,"finalActor":red.duplicate(true),"sideObstruction":blocked_side,"maxStep":maximum_step,"clear":stayed_clear,"plane":red.vesselLane})
	var prefix := "baseline-rerun-" if OS.get_cmdline_user_args().has("--baseline") and FileAccess.file_exists(OUT+"baseline.json") else ("baseline-" if OS.get_cmdline_user_args().has("--baseline") else "")
	var file := FileAccess.open(OUT+prefix+kind+"-"+str(roundi(site.x))+"-"+str(roundi(site.y))+("-side" if blocked_side else "")+"-snapshot.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(game.snapshot(),"  ",true,true))
	game.dispose()

func enclosed_case() -> void:
	var game := fixture()
	var red := game.entity(int(game.state.cellTest.red))
	var site := Vector2(112,110)
	var openings: Array[int] = []
	for offset in [Vector2(-3,0),Vector2(3,0),Vector2(0,-3),Vector2(0,3)]:
		check(game.economy.place("store",site+offset,[int(red.id)]),"enclosure fixture pays for each real surrounding blueprint")
		openings.append(int(game.state.nextId)-1)
	check(game.economy.place("store",site,[int(red.id)]),"enclosed fixture uses an actual paid target blueprint")
	var target := game.entity(int(game.state.nextId)-1)
	for i in 200: frame(game)
	check(target.progress == 0 and not target.complete,"no legal working edge never becomes remote construction")
	check(game.navigation.movement_clear(WarData.point(red),WarData.point(red),red.kind,1),"blocked worker never enters enclosure walls")
	# Release one controlled obstacle only; never move the actor or write target progress.
	game.state.entities.erase(str(openings[0]))
	for i in 800:
		frame(game)
		if target.complete: break
	check(target.complete,"normal retry reaches the newly opened working edge and completes")
	records.append({"enclosure":true,"completeAfterOpening":target.complete,"actor":[red.x,red.y],"time":game.state.time})
	game.dispose()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	WarSave.directory = "user://test-saves/construction-approach"
	run_case("store",Vector2(112,110),true)
	run_case("store",Vector2(112,88))
	run_case("store",Vector2(88,110))
	run_case("store",Vector2(88,88))
	run_case("core",Vector2(112.5,110.5))
	run_case("store",Vector2(112,110),false,true)
	enclosed_case()
	var filename := "baseline.json" if OS.get_cmdline_user_args().has("--baseline") else "checks.json"
	if filename == "baseline.json" and FileAccess.file_exists(OUT+filename): filename = "baseline-rerun.json"
	var file := FileAccess.open(OUT+filename,FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":records,"scope":"controlled actor/terrain fixture, actual placement/payment/navigation/construction; other cell-test units removed"},"  ",true,true))
	DirAccess.remove_absolute(WarSave.path(1))
	print("CONSTRUCTION APPROACH ",checks-failures.size(),"/",checks)
	quit(0 if failures.is_empty() else 1)
