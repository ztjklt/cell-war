extends SceneTree
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,message: String) -> void:
	if not value: failures.append(message); printerr("FAIL ",message)
	else: print("PASS ",message)

func press(button: Button) -> void:
	var event := InputEventMouseButton.new()
	event.position = root.get_stretch_transform()*button.get_global_rect().get_center()
	event.button_index = MOUSE_BUTTON_LEFT; event.pressed = true; root.push_input(event)
	event = event.duplicate(); event.pressed = false; root.push_input(event)
	await create_timer(.28).timeout

func run() -> void:
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main); current_scene = main
	for i in 3: await process_frame
	var cover: WarCover = main.hud.home
	check(cover.visible and main.game.paused,"normal startup opens paused cover")
	check(not main.world.visible and main.world.process_mode == Node.PROCESS_MODE_DISABLED,"cover suspends hidden map compositor")
	await press(cover.buttons[2])
	check(main.hud.menu.visible and cover.visible,"tutorial opens existing guide over cover")
	main.hud.close_menu()
	await press(cover.buttons[3])
	check(main.hud.menu.visible and main.hud.menu_body.get_child(0).text == "设置与游戏入口","settings opens real settings")
	main.hud.close_menu()
	await press(cover.buttons[0])
	check(not cover.visible and main.game.mode == "fullbody" and main.game.life.enabled(),"start retains the current authored life entry")
	check(main.world.visible and main.world.process_mode == Node.PROCESS_MODE_INHERIT,"entering gameplay restores map compositor")
	main.hud.return_home()
	await process_frame
	var previous_mode: String = main.game.mode
	var previous_state := JSON.stringify(main.game.state)
	await press(cover.buttons[1])
	check(cover.visible and main.hud.cover_preview.visible and main.game.mode == previous_mode,"pilot preview keeps the current battle paused")
	check(main.hud.cover_preview.character_count == WarData.read("character_catalogue").entries.size() and main.hud.cover_preview.character_count >= WarData.config().Data.units.size(),"character preview displays the complete authored catalogue")
	check(main.hud.cover_preview.is_ancestor_of(root.gui_get_focus_owner()),"preview owns keyboard focus instead of the cover beneath it")
	main.hud.cover_preview.set_category("medicines")
	main.hud.cover_preview.select_character("vaccine")
	main.hud.cover_preview.player.advance(3.0)
	main.hud.cover_preview.step_character(1)
	main.hud.cover_preview.show_maps()
	await process_frame
	check(main.hud.cover_preview.map_canvas.tiles.size() > 0,"map preview loads independent runtime anatomy layers")
	main.hud.cover_preview.map_canvas.select_region("heart")
	check(main.hud.cover_preview.map_canvas.region.size.x < 1024,"heart preview focuses actual organ bounds")
	main.hud.cover_preview.close()
	check(JSON.stringify(main.game.state) == previous_state,"catalogue selection, playback and maps leave paused battle state unchanged")
	check(not main.hud.cover_preview.visible and cover.visible and main.game.paused,"closing preview returns to cover without starting a campaign")
	main.hud.return_home()
	await process_frame
	check(cover.visible and main.game.paused and not main.world.visible,"return home restores cover and pauses map")
	DirAccess.make_dir_recursive_absolute("res://test-output/cover")
	var file := FileAccess.open("res://test-output/cover/game-flow.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures},"  "))
	print("COVER GAME FLOW DONE ",failures)
	main.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
