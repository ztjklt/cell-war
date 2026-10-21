extends SceneTree
## Actual paid placement on authored concave terrain, plus explicitly injected
## tiny-hole/raster fixtures. These are boundary tests, not opening playthroughs.
const OUT := "res://test-output/building-terrain/"
var checks := 0
var failures: Array[String] = []
var records: Array = []

func _initialize() -> void: call_deferred("run")

func check(value: bool,label: String) -> void:
	checks += 1
	if not value: failures.append(label); printerr("FAIL ",label)

func attempt(game: WarSimulation,kind: String,p: Vector2,worker: int,expected: bool,label: String) -> void:
	var radius := float(WarData.spec(kind).size)*.5
	var corners_allowed := true
	for x in [-radius,radius]:
		for y in [-radius,radius]:
			corners_allowed = corners_allowed and game.navigation.point_allowed(p+Vector2(x,y),0,"worker")
	check(corners_allowed,label+": all four corners pass the previous placement rule")
	var before := game.economy.stock(1,"wood")
	var count := game.entities().size()
	var next_id := int(game.state.nextId)
	var orders: Array = game.entity(worker).orders.duplicate(true)
	var allowed := game.economy.can_place(kind,p,[worker])
	var placed := game.economy.place(kind,p,[worker])
	check(allowed == expected and placed == expected,label+": preview and payment enforce the full footprint")
	if not expected:
		check(game.economy.stock(1,"wood") == before,label+": invalid footprint cannot spend protein")
		check(game.entities().size() == count and int(game.state.nextId) == next_id,label+": no unusable blueprint is created")
		check(game.entity(worker).orders == orders,label+": rejection preserves the current task")
		check(game.message.contains("组织地面"),label+": rejection explains the terrain requirement")
	else:
		check(game.entities().size() == count+1 and is_equal_approx(before-game.economy.stock(1,"wood"),float(WarData.spec(kind).cost.wood)),label+": safe placement still creates one paid blueprint")
	records.append({"label":label,"kind":kind,"point":[p.x,p.y],"expected":expected,"allowed":allowed,"placed":placed})

func authored_boundaries() -> void:
	for row in [
		["brain","barracks",Vector2(1093.5,638.5),Vector2(1092.014799,638.665479)],
		["pancreas","store",Vector2(990,1680),Vector2(989.013795,1680.499325)],
		["kidney_r","barracks",Vector2(851.5,1668.5),Vector2(851.81698,1669.928245)],
		["large_intestine","barracks",Vector2(1040.5,1809.5),Vector2(1039.175604,1809.665819)]
	]:
		var game := WarSimulation.new(); game.start("life",73)
		check(game.navigation.organ_at(row[3]).is_empty(),str(row[0])+": authored wall cuts into the square between its valid corners")
		attempt(game,row[1],row[2],25,false,"authored "+str(row[0])+" concavity")
		game.dispose()
	var game := WarSimulation.new(); game.start("life",73)
	attempt(game,"store",Vector2(985,1906),25,true,"original opening storage site")
	game.dispose()

func enclosed_hole() -> void:
	var game := WarSimulation.new(); game.start("life",73)
	var center := Vector2(1089.5,1932.5)
	var hole_center := center+Vector2(.6,.4)
	var rings: Array = game.navigation.grid("small_intestine","siege").rings
	check(game.economy.can_place("barracks",center,[25]),"tiny-hole control site is originally legal")
	# This subpixel hole is a deliberate geometry fixture, not modified map data.
	for ring in rings:
		if Geometry2D.is_point_in_polygon(hole_center,ring.outer):
			ring.holes.append(PackedVector2Array([hole_center+Vector2(-.1,-.1),hole_center+Vector2(.1,-.1),hole_center+Vector2(.1,.1),hole_center+Vector2(-.1,.1)]))
			break
	check(game.navigation.point_allowed(center,0,"worker") and not game.navigation.point_allowed(hole_center,0,"worker"),"injected hole avoids both center and boundary samples")
	attempt(game,"barracks",center,25,false,"enclosed tiny polygon hole")
	game.dispose()

func raster_hole() -> void:
	var game := WarSimulation.new(); game.start("cell_test",73)
	var center := Vector2(110.5,110.5)
	check(game.economy.can_place("barracks",center,[1]),"raster-hole control site is originally legal")
	game.submit_player({"action":"place","building":"barracks","x":center.x,"y":center.y,"ids":[1]})
	var grid := game.navigation.campaign_grid
	var cell := Vector2i((Vector2(110,110)-grid.origin).round())
	grid.valid[cell.y*grid.width+cell.x] = 0
	check(game.navigation.point_allowed(center,0,"worker") and not game.navigation.point_allowed(Vector2(110,110),0,"worker"),"injected blocked grid cell is inside the footprint away from its center")
	var before := game.economy.stock(1,"wood")
	var count := game.entities().size()
	game.update(.1)
	check(game.entities().size() == count and game.economy.stock(1,"wood") == before,"queued placement rechecks a newly blocked interior cell without spending")
	attempt(game,"barracks",center,1,false,"enclosed raster hole")
	game.dispose()

func run() -> void:
	authored_boundaries(); enclosed_hole(); raster_hole()
	DirAccess.make_dir_recursive_absolute(OUT)
	var name := "baseline" if OS.get_cmdline_user_args().has("--baseline") else "checks"
	FileAccess.open(OUT+name+".json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"records":records,"scope":"four authored concave sites, legal opening site, explicit enclosed polygon and raster holes; actual can_place/place/queued payment"},"  "))
	print("BUILDING TERRAIN ",checks-failures.size(),"/",checks)
	quit(0 if failures.is_empty() else 1)
