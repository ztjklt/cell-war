extends "res://tests/opening_flow.gd"
## Sandbox starts retain their units/resources; fire/damage are explicit emergency fixtures.
const FIRE_OUT := "res://test-output/extinguish-ui/"
var worked := false

func option(action: String) -> Button:
	for button in main.hud.wheel.buttons:
		if button.action == action: return button
	return null

func capture_fire(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await create_timer(.2).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(FIRE_OUT+name+".png")

func fire_wheel(target: Dictionary) -> void:
	await click(screen(WarData.point(target)),MOUSE_BUTTON_RIGHT)
	await create_timer(.35).timeout
	check(main.hud.wheel.visible and int(main.hud.wheel.context.target) == int(target.id),"physical right click targets the actual burning building")

func exercise() -> void:
	var game: WarSimulation = main.game
	var core: Dictionary = game.entities().filter(func(e): return e.faction == 1 and e.kind == "core")[0]
	var worker: Dictionary = game.entity(4)
	var original_stock := stocks()
	var original_units := game.units().filter(func(e): return e.faction == 1).size()
	main.focus((WarData.point(core)+WarData.point(worker))*.5,22)
	await frames(12)
	await click(screen(WarData.point(worker)))
	check(game.selected == [int(worker.id)],"physical map click selects the original sandbox red cell")
	await press(main.hud.pause_button)
	check(game.paused,"actual pause button holds the emergency before command entry")
	await fire_wheel(core)
	check(option("extinguish") == null,"intact nonburning building has no extinguish command")
	key(KEY_ESCAPE); await frames()
	core.fire = 1.0; core.hp -= 5 # Controlled emergency; no buildings/units/resources injected.
	var damaged := float(core.hp)
	await fire_wheel(core)
	if not check(option("extinguish") != null,"burning friendly building exposes a real extinguish badge"): return
	check(option("repair") != null,"fire suppression preserves the independent repair choice")
	await capture_fire("extinguish-command")
	await press(option("extinguish")); await create_timer(.4).timeout
	check(game.state.commands.size() == 1 and game.state.commands[0].kind == "extinguish" and int(game.state.commands[0].target) == int(core.id) and game.state.commands[0].ids == [int(worker.id)],"actual extinguish badge queues the original target for red cells only")
	check(worker.orders.is_empty() and is_equal_approx(core.fire,1) and is_equal_approx(core.hp,damaged),"pause leaves fire health and worker orders unchanged")
	await press(main.hud.pause_button)
	for i in 20:
		await advance(1)
		if worker.combatState == "build" and not worker.orders.is_empty() and worker.orders[0].kind == "extinguish" and not worked:
			worked = true; main.hud._process(.2); await frames()
			check(main.hud.details.text.contains("灭火") and worker.combatState == "build","real suppression displays extinguishing while retaining its work animation")
			await capture_fire("extinguishing")
		if float(core.fire) <= 0: break
	record("fire-suppression",{"fire":core.fire,"worker":worker.duplicate(true)})
	check(worked and is_zero_approx(float(core.fire)) and worker.orders.is_empty(),"original worker actually reaches the building extinguishes its fire and completes the task")
	check(core.hp > 0 and float(core.hp) < damaged,"normal fire causes real damage without silently repairing the building")
	check(stocks() == original_stock and game.units().filter(func(e): return e.faction == 1).size() == original_units,"fire suppression adds no resources or units and charges no repair cost")
	await capture_fire("fire-extinguished")
	await press(main.hud.pause_button)
	await fire_wheel(core)
	check(option("extinguish") == null and option("repair") != null,"extinguished building returns to its real repair option")
	key(KEY_ESCAPE); await frames()
	core.fire = 1.0
	await fire_wheel(core)
	core.fire = 0.0
	var before: int = game.state.commands.size()
	await press(option("extinguish"))
	check(game.state.commands.size() == before and main.hud.wheel.visible and main.hud.wheel.feedback_error,"fire that ends before confirmation rejects a stale badge without submitting an order")
	key(KEY_ESCAPE); await frames()
	core.fire = 1.0
	await fire_wheel(core)
	core.faction = 2
	await press(option("extinguish"))
	check(game.state.commands.size() == before and main.hud.wheel.visible and main.hud.wheel.feedback_error,"captured target ownership is rechecked at confirmation")
	key(KEY_ESCAPE); await frames(); core.faction = 1
	var white: Dictionary = game.entity(9)
	await click(screen(WarData.point(white)))
	check(game.selected == [int(white.id)],"physical map click selects a white cell for the negative actor case")
	await fire_wheel(core)
	check(option("extinguish") == null,"white cells are not offered a red-cell-only task")
	key(KEY_ESCAPE); await frames()
	await click(screen(WarData.point(worker)))
	await fire_wheel(core)
	await press(option("extinguish")); await create_timer(.4).timeout
	core.faction = 2
	await press(main.hud.pause_button)
	var fire_before := float(core.fire)
	await advance(.2)
	check(worker.orders.is_empty() and float(core.fire) >= fire_before-.02 and stocks() == original_stock,"native economy rejects ownership changed after queueing without working or spending")
	core.faction = 1
	# UI density fixture: a damaged burning cultivation bed retains all three actions.
	game.paused = true
	var p := game.economy.build_point("farm",WarData.point(worker)+Vector2(-4,3))
	var farm: Dictionary = game.spawn("farm",1,p,"building")
	farm.complete = true; farm.hp = farm.maxHp-1; farm.fire = 1.0
	main.focus((WarData.point(worker)+p)*.5,22); await frames()
	await fire_wheel(farm)
	check(option("extinguish") != null and option("farm") != null and option("repair") != null,"burning cultivation bed keeps suppression cultivation and repair choices together")
	for button in main.hud.wheel.buttons: check(root.get_visible_rect().encloses(button.get_global_rect()),"dense emergency command badge stays in the window")
	await capture_fire("burning-farm-commands")
	key(KEY_ESCAPE); await frames()
	main.start("cell_test"); game.paused = true
	var target: Dictionary = game.entity(int(game.state.cellTest.building))
	target.fire = 1
	main.focus(WarData.point(game.entity(1)),22); await frames()
	await click(screen(WarData.point(game.entity(1))))
	await fire_wheel(target)
	check(option("extinguish") == null,"sandbox-only fire action is not advertised by unrelated battle modes")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(FIRE_OUT)
	WarSave.directory = "user://test-saves/extinguish-ui-%d" % Time.get_ticks_usec()
	root.size = Vector2i(1440,900)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main); current_scene = main; main.set_process(false)
	main.start("sandbox"); main.game.paused = false
	await exercise()
	var mode := "headless" if DisplayServer.get_name() == "headless" else "native"
	FileAccess.open(FIRE_OUT+"extinguish-ui-"+mode+".json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"worked":worked,"physicalWindowInput":true,"fixture":"original sandbox red/core/resources; fire and five health damage deliberately supplied; final stale-target and dense farm-menu cases are explicit fixtures; normal simulation performs suppression","isolatedSaveDirectory":WarSave.directory},"  "))
	print("EXTINGUISH UI ",checks," checks, failures=",failures)
	main.queue_free(); await process_frame; quit(0 if failures.is_empty() else 1)
