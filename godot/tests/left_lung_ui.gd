extends "res://tests/opening_flow.gd"
## Actual native clicks from cover to victory. Only simulation time is accelerated.
const EVIDENCE := "res://test-output/left-lung-playthrough-20261023/"
var evidence_dir := EVIDENCE

func prepare_evidence(default_path := EVIDENCE) -> void:
	evidence_dir = default_path
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence="): evidence_dir = argument.trim_prefix("--evidence=").trim_suffix("/")+"/"
	DirAccess.make_dir_recursive_absolute(evidence_dir)

func prefix_button(parent: Node,prefix: String) -> Button:
	for node in parent.find_children("*","Button",true,false):
		if node.text.begins_with(prefix) and node.is_visible_in_tree(): return node
	return null

func advance(seconds: float) -> void:
	for i in ceili(seconds/.1):
		if main.game.paused: break
		main._process(.1) # Same navigation budget, autosave and rules as the game.
		if i%20 == 0: await process_frame
	await frames()

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	var began := Time.get_ticks_msec()
	var stable := 0
	while stable < 5 and Time.get_ticks_msec()-began < 12000:
		await process_frame
		var ready: bool = main.world.textures.pending.is_empty() and not main.world.visible_tiles.is_empty()
		for tile in main.world.visible_tiles:
			if main.world.textures.get_texture(tile.spec.resource) == null: ready = false
		stable = stable+1 if ready else 0
	check(stable >= 5,"terrain streamed for "+name)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(evidence_dir+name+".png")

func select_cells(cells: Array) -> void:
	for i in cells.size():
		var event := InputEventMouseButton.new()
		event.position = root.get_stretch_transform()*screen(WarData.point(cells[i]))
		event.button_index = MOUSE_BUTTON_LEFT; event.shift_pressed = i > 0; event.pressed = true
		root.push_input(event); await process_frame
		event = event.duplicate(); event.pressed = false; root.push_input(event)
		await frames(2)
	check(main.game.selected.size() == cells.size() and cells.all(func(e): return main.game.selected.has(int(e.id))),"real clicks select requested squad")

func command_at(kind: String,point: Vector2) -> void:
	await click(screen(point),MOUSE_BUTTON_RIGHT)
	await create_timer(.35).timeout
	var option: Button
	for candidate in main.hud.wheel.buttons:
		if candidate.action == kind: option = candidate; break
	if not await press(option): return
	await create_timer(.4).timeout
	check(main.game.state.commands.any(func(c): return c.get("kind","") == kind),"radial button submits "+kind)

func play_battle() -> void:
	await frames(15)
	if not await press(main.hud.home.buttons[0]): return
	if not await press(prefix_button(main.hud.menu_body,"＋ 新建存档")): return
	check(main.game.units().filter(func(e): return e.faction == 1).size() == 20 and stocks() == {"wood":160.0,"food":125.0},"new save keeps normal opening resources and 20 reds")
	main.focus(main.world.display_point(Vector2(1232,1200)),8)
	while main.camera_travel.active: await process_frame
	await frames(15)
	var red: Dictionary = main.game.entity(int(main.game.state.lungDefense.workers[0]))
	await select_cells([red])
	if not await open_build(): return
	if not await press(prefix_button(main.hud.menu_body,str(WarData.spec("barracks").name)+" ·")): return
	await click(screen(Vector2(1235.5,1192.5)))
	await advance(45)
	var barracks: Dictionary = {}
	for e in main.game.entities():
		if e.faction == 1 and e.kind == "barracks": barracks = e; break
	if not check(not barracks.is_empty() and barracks.complete,"clicked barracks is built by the original red"): return
	await click(screen(WarData.point(barracks)))
	if not await open_build(): return
	for i in 6:
		if not await press(train_button()): return
	if not await press(named_button(main.hud.menu_body,"返回游戏")): return
	await advance(.2)
	check(barracks.queue.size() == 6 and stocks() == {"wood":30.0,"food":53.0},"six real production clicks charge 90 protein and 72 glucose")
	await capture("native-preparation")
	await advance(145)
	var whites: Array = main.game.units().filter(func(e): return e.faction == 1 and e.kind == "spear")
	if not check(whites.size() == 6,"six white cells actually finish training"): return
	await select_cells(whites)
	await command_at("attackmove",Vector2(1232.25549,1226.91052))
	await advance(23)
	await capture("native-combat")
	# Exit and continue through visible buttons while the actual fight is underway.
	if not await press(named_button(main.hud.root,"≡")): return
	if not await press(named_button(main.hud.menu_body,"返回首页")): return
	var path: String = main.saves.active_path
	var saved := WarSaveSession.document(path)
	if not await press(main.hud.home.buttons[0]): return
	if not await press(prefix_button(main.hud.menu_body,"继续 ·")): return
	check(main.game.state.time == saved.snapshot.time and main.game.selected.size() == 6,"continue restores battle clock and selected squad")
	for i in 120:
		await advance(2)
		var group: Dictionary = main.game.state.influenzaColonies.groups[main.game.state.lungDefense.colony]
		if main.game.influenza.members(group).is_empty() and main.game.influenza.forts(group).is_empty() and int(group.pending) == 0: break
	var colony: Dictionary = main.game.state.influenzaColonies.groups[main.game.state.lungDefense.colony]
	if not check(main.game.influenza.members(colony).is_empty() and main.game.influenza.forts(colony).is_empty(),"normal clicked attack actually removes enemies and fortresses"): return
	await capture("native-cleanup-instruction")
	var reds: Array = main.game.units().filter(func(e): return e.faction == 1 and e.kind == "worker")
	reds.sort_custom(func(a,b): return int(a.id) < int(b.id))
	await select_cells(reds.slice(0,2))
	await command_at("move",WarData.point(colony.center))
	for i in 90:
		await advance(1)
		if main.game.state.lungDefense.phase == "defended": break
	check(main.game.state.lungDefense.phase == "defended","actual red move and white presence complete 20 second purification")
	await frames(10)
	check(main.hud.defense_countdown.is_visible_in_tree() and main.hud.defense_countdown.digits.text == "左肺已夺回","victory is persistently visible")
	check(not main.hud.defense_countdown.get_global_rect().intersects(main.hud.toolbar.get_global_rect()),"battle objective does not cover the toolbar")
	check(WarSaveSession.document(path).snapshot.lungDefense.phase == "defended","victory transition saves immediately")
	await capture("native-victory")
	if not await press(named_button(main.hud.root,"存档")): return
	if not await press(prefix_button(main.hud.menu_body,"继续 ·")): return
	check(main.game.state.lungDefense.phase == "defended" and main.game.state.influenzaColonies.groups[main.game.state.lungDefense.colony].cleared,"continuing the won save preserves genuine purification")
	record("native-victory-resumed",{"colonies":main.game.state.influenzaColonies})

func run() -> void:
	WarSave.directory = "user://test-saves/left-lung-ui-"+str(Time.get_ticks_usec())
	WarSettings.storage_path = WarSave.directory+"/settings.json"
	DirAccess.make_dir_recursive_absolute(WarSave.directory)
	prepare_evidence()
	root.size = Vector2i(1440,900)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main); current_scene = main; main.set_process(false)
	await play_battle()
	var file := FileAccess.open(evidence_dir+"native-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"evidence":evidence,"snapshot":main.game.snapshot()},"",true,true)); file.close()
	print("LEFT_LUNG_UI ",checks-failures.size(),"/",checks)
	main.queue_free(); await frames()
	quit(0 if failures.is_empty() else 1)
