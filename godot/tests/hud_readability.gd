extends "res://tests/left_lung_ui.gd"
## Native HUD geometry and real readouts; explicit fixtures do not advance battle.

func inspect_layout(dimensions: Vector2i) -> void:
	root.size = dimensions
	await frames(12)
	main.hud._process(.2); main.hud._layout()
	await frames(10)
	main.hud._layout(); await frames(3)
	var view := root.get_visible_rect()
	var tag := str(dimensions)
	check(view.encloses(main.hud.panel.get_global_rect()),tag+" entire selection panel stays on screen")
	check(main.hud.panel.get_global_rect().encloses(main.hud.focus_button.get_global_rect()),tag+" focus button stays in its panel")
	check(not main.hud.panel.get_global_rect().intersects(main.hud.status.get_global_rect()),tag+" status clears selection panel")
	for kind in main.hud.resource_values:
		var refs: Dictionary = main.hud.resource_values[kind]
		check(refs.card.is_visible_in_tree(),tag+" resource visible: "+kind)
		check(view.encloses(refs.card.get_global_rect()),tag+" resource stays on screen: "+kind)
		check(refs.card.get_global_rect().encloses(refs.value.get_global_rect()) and refs.card.get_global_rect().encloses(refs.caption.get_global_rect()),tag+" resource labels fit: "+kind)
		check(not refs.card.get_global_rect().intersects(main.hud.toolbar.get_global_rect()) and not refs.card.get_global_rect().intersects(main.hud.root.get_node("Navigation").get_global_rect()),tag+" resource clears map and toolbar: "+kind)
	await capture("hud-"+str(dimensions.x)+"x"+str(dimensions.y))

func run() -> void:
	WarSave.directory = "user://test-saves/hud-readability-"+str(Time.get_ticks_usec())
	WarSettings.storage_path = WarSave.directory+"/settings.json"
	DirAccess.make_dir_recursive_absolute(WarSave.directory)
	prepare_evidence("res://test-output/hud-polish-20261024/")
	root.size = Vector2i(1440,900)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main); current_scene = main; main.set_process(false)
	main.new_run("lung_defense"); main.game.paused = true
	await frames(12)
	main.hud._process(.2)
	check(main.hud.resource_values.wood.value.text == "160","new run shows actual initial protein without counting up from zero")
	for dimensions in [Vector2i(1440,900),Vector2i(1024,768),Vector2i(360,780),Vector2i(390,844),Vector2i(430,932)]:
		await inspect_layout(dimensions)
	root.size = Vector2i(1440,900); await frames(15)
	var selected: Array = main.game.selected.duplicate()
	var before_time: float = main.game.state.time
	if await press(main.hud.focus_button):
		check(main.game.selected == selected,"animated focus button keeps the selected cell")
	check(main.game.state.time == before_time,"HUD feedback leaves paused simulation clock unchanged")
	main.game.economy.add(1,"wood",7)
	main.hud._process(.2); await create_timer(.4).timeout
	check(main.hud.resource_values.wood.value.text == "167","resource feedback settles on the real delivered amount")
	var original_save: String = main.saves.active_path
	main.new_run("lung_defense"); main.game.paused = true
	main.hud._process(.2)
	check(main.hud.resource_values.wood.value.text == "160","new save resets readout immediately instead of animating old stock")
	main.continue_run(original_save)
	main.hud._process(.2)
	check(main.game.economy.stock(1,"wood") == 167 and main.hud.resource_values.wood.value.text == "167","continuing another save immediately shows that save's actual resources")
	main.game.selected.assign(main.game.state.lungDefense.workers)
	root.size = Vector2i(390,844)
	await frames(15); main.hud._process(.2); await frames(8)
	check(root.get_visible_rect().encloses(main.hud.panel.get_global_rect()) and main.hud.panel.get_global_rect().encloses(main.hud.selection.get_global_rect()),"large squad title wraps inside its on-screen selection panel")
	await capture("hud-squad-portrait")
	for dimensions in [Vector2i(1440,900),Vector2i(390,844)]:
		root.size = dimensions; await frames(12)
		main.start("life"); main.game.paused = true
		main.overview()
		while main.camera_travel.active: await process_frame
		await frames(15); main.hud._layout(); await frames(5)
		check(root.get_visible_rect().encloses(main.hud.panel.get_global_rect()),"shared life selection panel stays on screen "+str(dimensions))
		check(not main.hud.panel.get_global_rect().intersects(main.hud.life_dialogue.phone.get_global_rect()),"shared life phone clears taller selection panel "+str(dimensions))
		await capture("hud-life-"+str(dimensions.x)+"x"+str(dimensions.y))
	print("HUD_READABILITY ",checks-failures.size(),"/",checks)
	main.queue_free(); await frames()
	quit(0 if failures.is_empty() else 1)
