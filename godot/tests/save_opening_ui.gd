extends SceneTree
var main: Node
var checks := 0
var failures: Array[String] = []
const OUTPUT := "res://test-output/save-opening-20261023/"

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok: failures.append(message); printerr("FAIL ",message)

func frames(n := 5) -> void:
	for i in n: await process_frame

func find_button(node: Node,prefix: String) -> Button:
	if node is Button and node.text.begins_with(prefix): return node
	for child in node.get_children():
		var result := find_button(child,prefix)
		if result != null: return result
	return null

func press(button: Button) -> void:
	check(button != null and button.is_visible_in_tree() and not button.disabled,"requested button available")
	if button == null: return
	await frames()
	var event := InputEventMouseButton.new()
	event.position = root.get_stretch_transform()*button.get_global_rect().get_center()
	event.button_index = MOUSE_BUTTON_LEFT; event.pressed = true; root.push_input(event)
	event = event.duplicate(); event.pressed = false; root.push_input(event)
	await create_timer(.35).timeout
	await frames(5)

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	if main.world.visible:
		var began := Time.get_ticks_msec()
		var stable := 0
		while stable < 5 and Time.get_ticks_msec()-began < 12000:
			await process_frame
			var ready: bool = main.world.textures.pending.is_empty() and not main.world.visible_tiles.is_empty()
			for tile in main.world.visible_tiles:
				if main.world.textures.get_texture(tile.spec.resource) == null: ready = false
			stable = stable+1 if ready else 0
		check(stable >= 5,"terrain finishes streaming before "+name)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT+name+".png")

func covered() -> bool:
	var rect := root.get_visible_rect()
	var projection: Transform2D = main.map_frame.desk_projection()
	return (projection*rect).grow(.1).encloses(rect)

func settle() -> void:
	var began := Time.get_ticks_msec()
	var all_covered := true
	while main.camera_travel.active and Time.get_ticks_msec()-began < 3000:
		await process_frame
		all_covered = all_covered and covered()
	check(not main.camera_travel.active and all_covered,"every animated camera frame remains inside desk artwork")

func run() -> void:
	WarSave.directory = "user://test-saves/save-ui-"+str(Time.get_ticks_usec())
	WarSettings.storage_path = WarSave.directory+"/settings.json"
	DirAccess.make_dir_recursive_absolute(WarSave.directory)
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.size = Vector2i(1440,900)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main); current_scene = main
	main.set_process(false)
	await frames(15)
	check(main.hud.home.visible and WarSaveSession.records().is_empty(),"cover does not create a save")
	await press(main.hud.home.buttons[0])
	check(main.hud.menu.visible and main.hud.home.visible,"Start opens save picker")
	await capture("save-picker-empty")
	await press(find_button(main.hud.menu_body,"＋ 新建存档"))
	check(not main.hud.home.visible and main.game.state.lungDefense.organ == "lung_l" and not main.saves.active_path.is_empty(),"new save enters left lung and writes a record")
	var first: String = main.saves.active_path
	var selected: Array = main.game.selected.duplicate()
	main.game.paused = true
	for i in 15: main.game.step(.1)
	var elapsed: float = main.game.state.lungDefense.elapsed
	await frames(15)
	check(main.hud.defense_countdown.is_visible_in_tree(),"countdown visible on actual game screen")
	await capture("left-lung-countdown")
	main.hud.return_home(); await frames()
	check(is_equal_approx(WarSaveSession.document(first).snapshot.lungDefense.elapsed,elapsed),"return home flushes actual progress")
	await press(main.hud.home.buttons[0])
	await capture("save-picker-existing")
	await press(find_button(main.hud.menu_body,"＋ 新建存档"))
	check(main.saves.active_path != first and WarSaveSession.records().size() == 2,"second new game preserves first record")
	main.hud.return_home(); await frames()
	main.continue_run(first); await frames()
	check(is_equal_approx(main.game.state.lungDefense.elapsed,elapsed) and main.game.selected == selected,"continue restores selected cells and preparation progress")
	main.game.paused = true
	main.game.step(.1)
	main.saves.since_save = WarSaveSession.INTERVAL
	main._process(.01)
	check(is_equal_approx(WarSaveSession.document(first).snapshot.time,main.game.state.time),"real-time autosave flushes even while paused")
	main.overview(); await frames()
	for action in ["camera_left","camera_right","camera_up","camera_down"]:
		Input.action_press(action); main._update_camera_controls(1); Input.action_release(action)
	check(main.overview_active and not main.camera_travel.active and covered(),"all four pan directions do nothing at overview")
	await capture("overview-locked")
	main._zoom_selected(1.08); await settle()
	for action in ["camera_left","camera_right","camera_up","camera_down"]:
		Input.action_press(action); main._update_camera_controls(100); Input.action_release(action)
		await settle()
	await capture("zoom-edge")
	main.return_overview(); await settle()
	check(main.camera.position.distance_to(Vector2(1024,2048)) < .01,"zooming back restores fixed overview center")
	root.size = Vector2i(360,780); await frames(15)
	check(covered(),"resize keeps overview inside portrait artwork")
	main.focus(main.game.scenarios.home(),8); await frames(10)
	await capture("portrait-countdown")
	var clock_rect: Rect2 = main.hud.defense_countdown.get_global_rect()
	check(root.get_visible_rect().encloses(clock_rect) and not clock_rect.intersects(main.hud.layer_button.get_global_rect()) and not clock_rect.intersects(main.hud.overview_button.get_global_rect()),"portrait countdown fits without overlapping view buttons")
	main.hud.show_cover_settings(); await frames(10)
	var scroll: ScrollContainer = main.hud.menu.get_child(0)
	check(scroll.get_h_scroll_bar().max_value <= scroll.get_h_scroll_bar().page+.5,"portrait settings do not overflow horizontally")
	await capture("portrait-settings")
	main.hud.close_menu()
	for e in main.game.entities():
		if e.faction == 1 and not e.has("checkpointId"): e.hp = 0
	main.game.scenarios.after_step(.1)
	main.hud._process(.2); await frames(8)
	check(main.game.paused and main.hud.menu.visible and main.hud.menu_body.get_child(0).text == "左肺防线失守","failed defense pauses and opens recovery choices")
	await capture("defense-failed")
	main.free()
	print("SAVE_OPENING_UI ",checks-failures.size(),"/",checks)
	quit(0 if failures.is_empty() else 1)
