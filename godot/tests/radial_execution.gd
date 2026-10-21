extends "res://tests/radial_commands.gd"
## Click the production UI, then run the real simulation and inspect outcomes.
var evidence: Array[Dictionary] = []

func screen(p: Vector2) -> Vector2:
	return main.get_canvas_transform()*main.world.display_point(p)

func reset_fixture(id := 1,enemy_near := false) -> Dictionary:
	main.start("cell_test")
	main.game.paused = true
	main.game.selected.clear()
	if not enemy_near:
		var enemy: Dictionary = main.game.entity(3); enemy.x = 140; enemy.y = 140
	main.camera.force_update_scroll()
	await frames()
	var cell: Dictionary = main.game.entity(id)
	if not WarDeskMapFrame.contains(root.get_visible_rect().size,screen(WarData.point(cell))):
		main.focus(main.world.display_point(WarData.point(cell)),32)
		main.camera.force_update_scroll(); await frames()
	await click(screen(WarData.point(cell)))
	check(main.game.selected == [id],"physical click selects cell %d" % id)
	return cell

func command_at(p: Vector2,action: String,_right := false) -> void:
	# A target must be inside the paper aperture before clicking it. Some fixtures
	# were authored for the old full-window camera and place it beyond that edge.
	if not WarDeskMapFrame.contains(root.get_visible_rect().size,screen(p)):
		main.focus(main.world.display_point(p),minf(main.camera.zoom.x,32))
		main.camera.force_update_scroll(); await frames()
	await click(screen(p),MOUSE_BUTTON_RIGHT)
	check(main.hud.wheel.visible,"target click opens live wheel: "+action)
	await choose(action)

func advance(seconds: float) -> void:
	main.game.paused = false
	for i in ceili(seconds/.05):
		main.game.navigation.update(10000)
		main.game.update(.05)
		if i%20 == 0: await process_frame
	main.game.paused = true

func run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	main = scene.instantiate(); scene = null
	root.add_child(main); current_scene = main
	main.set_process(false)
	var cell := await reset_fixture()
	var before := WarData.point(cell)
	var goal := Vector2(104,99)
	await command_at(goal,"move")
	main.game.update(.5)
	check(WarData.point(cell) == before,"pause holds physical UI movement until resume")
	await advance(8)
	check(WarData.point(cell).distance_to(goal) < .15,"UI move actually reaches the clicked ground")
	evidence.append({"action":"move","from":before,"to":WarData.point(cell),"goal":goal})

	cell = await reset_fixture()
	await command_at(Vector2(108,99),"move")
	await advance(.8)
	before = WarData.point(cell)
	check(before.distance_to(Vector2(100,99)) > .1,"cell has started moving before stop")
	await command_at(Vector2(105,101),"stop")
	await advance(1.5)
	check(cell.orders.is_empty() and WarData.point(cell).distance_to(before) < .05,"UI stop clears the route and stops real movement")

	cell = await reset_fixture()
	goal = Vector2(104,99)
	await command_at(goal,"attackmove")
	await advance(8)
	check(WarData.point(cell).distance_to(goal) < .15,"UI attack-move advances to the ground target")

	cell = await reset_fixture()
	await command_at(goal,"guard")
	await advance(8)
	check(WarData.point(cell).distance_to(goal) < .15 and not cell.orders.is_empty() and cell.orders[0].kind == "guard","UI guard reaches the point and keeps guarding")
	before = WarData.point(cell)
	await advance(2)
	check(WarData.point(cell).distance_to(before) < .05,"guard remains at the designated point without enemies")

	cell = await reset_fixture(2)
	var home: Vector2 = main.game.scenarios.home()
	await command_at(Vector2(105,104),"move")
	await advance(8)
	before = WarData.point(cell)
	await command_at(Vector2(104,102),"retreat")
	await advance(10)
	# Home is the live red cell's location: respect its body instead of overlapping it.
	check(WarData.point(cell).distance_to(home) < 1.5 and before.distance_to(home) > 5,"UI retreat actually returns beside the occupied home point")
	evidence.append({"action":"retreat","from":before,"to":WarData.point(cell),"occupiedHome":home})

	cell = await reset_fixture(2,true)
	var enemy: Dictionary = main.game.entity(3)
	var health := float(enemy.hp)
	await command_at(WarData.point(enemy),"attack")
	await advance(10)
	check(enemy.hp < health or main.game.entity(3).is_empty(),"UI explicit attack causes real target damage")
	evidence.append({"action":"attack","hpBefore":health,"hpAfter":enemy.hp})

	cell = await reset_fixture()
	main.game.state.resources["ui_test_resource"] = {"kind":"wood","x":104.0,"y":99.0,"amount":40.0,"radius":2.2,"vesselLane":0}
	await command_at(Vector2(104,99),"harvest")
	await advance(4)
	check(float(main.game.state.resources.ui_test_resource.amount) < 40 and float(cell.cargo.get("wood",0)) > 0,"UI harvest depletes the actual resource and fills cell cargo")
	evidence.append({"action":"harvest","remaining":main.game.state.resources.ui_test_resource.amount,"cargo":cell.cargo.duplicate()})

	cell = await reset_fixture()
	var stock: float = main.game.economy.stock(1,"wood")
	await command_at(Vector2(110,99),"build_menu")
	await choose("place:store")
	await advance(.1)
	var building: Dictionary = {}
	for e in main.game.entities():
		if e.category == "building" and int(e.id) != 4: building = e
	check(not building.is_empty() and main.game.economy.stock(1,"wood") < stock,"UI construction spends resources and creates a real building")
	await advance(40)
	check(not building.is_empty() and building.get("complete",false),"UI construction makes the worker finish the actual building")

	cell = await reset_fixture()
	building = main.game.entity(4)
	await command_at(WarData.point(building),"build",true)
	await advance(5)
	check(float(building.progress) > 0,"UI assist construction advances an existing building")

	cell = await reset_fixture()
	building = main.game.entity(4); building.complete = true; building.progress = 1; building.hp = building.maxHp-40
	health = float(building.hp); stock = main.game.economy.stock(1,"wood")
	await command_at(WarData.point(building),"repair",true)
	await advance(5)
	check(building.hp > health and main.game.economy.stock(1,"wood") < stock,"UI repair restores building health and pays repair cost")

	await reset_fixture(4)
	building = main.game.entity(4)
	goal = Vector2(105,101)
	await command_at(goal,"rally")
	await advance(.1)
	check(WarData.point(building.rally).distance_to(goal) < .001,"UI rally changes the real building rally point")

	# Also exercise actual anatomical terrain, not just the isolated fixture.
	main.start("fullbody"); main.game.paused = true
	cell = main.game.entity(main.game.selected[0])
	before = WarData.point(cell); goal = before
	for i in 24:
		var candidate := before+Vector2.from_angle(i*TAU/24)*3.5
		if main.game.navigation.clear_segment(before,candidate,0,cell.kind) and main.game.entities().all(func(e): return WarData.point(e).distance_to(candidate) > 1.5):
			goal = candidate; break
	check(goal != before,"anatomical fixture has a genuinely walkable destination")
	main.focus(before.lerp(goal,.5),32); main.camera.force_update_scroll()
	await frames()
	await command_at(goal,"move")
	await advance(2)
	check(WarData.point(cell).distance_to(before) < .1,"organ movement respects the friendly cell blocking the narrow passage")
	var front: Dictionary = main.game.units().filter(func(e): return e.id != cell.id and e.faction == 1 and WarData.point(e).distance_to(before) < 2)[0]
	await click(screen(WarData.point(front)))
	check(main.game.selected == [int(front.id)],"physical click selects the cell blocking the passage")
	await command_at(goal,"move")
	await advance(8)
	check(WarData.point(front).distance_to(goal) < .2,"UI command moves the leading cell through actual organ terrain")
	await click(screen(WarData.point(cell)))
	goal = before.lerp(goal,.45)
	await command_at(goal,"move")
	await advance(8)
	check(WarData.point(cell).distance_to(goal) < .2,"UI move executes after the friendly cell clears the passage")
	evidence.append({"action":"organ_move","from":before,"to":WarData.point(cell),"goal":goal})
	DirAccess.make_dir_recursive_absolute("res://test-output")
	var file := FileAccess.open("res://test-output/radial-execution.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"evidence":evidence,"physicalClicks":true,"realSimulation":true},"  "))
	print("RADIAL EXECUTION ",checks-failures.size(),"/",checks)
	main.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
