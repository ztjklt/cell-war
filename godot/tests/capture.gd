extends SceneTree
var game_root: Node

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	game_root = scene.instantiate()
	scene = null
	root.add_child(game_root)
	current_scene = game_root
	game_root.set_process(false); game_root.set_process_unhandled_input(false)
	var mode := "fullbody"
	var home := false
	var advisor := false
	var handbook := false
	var wheel := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="): mode = arg.trim_prefix("--mode=")
		if arg == "--home": home = true
		if arg == "--advisor": advisor = true
		if arg == "--handbook": handbook = true
		if arg == "--wheel": wheel = true
		if arg == "--narrow": root.size = Vector2i(360,780)
		if arg.begins_with("--size="):
			var dimensions := arg.trim_prefix("--size=").split("x")
			root.size = Vector2i(int(dimensions[0]),int(dimensions[1]))
	game_root.start(mode)
	if mode == "fullbody": game_root.overview()
	else: game_root.game.paused = true
	if home: game_root.hud.return_home()
	if advisor: game_root.hud.dialogue.answer("defense")
	if handbook: game_root.hud.show_help()
	# Allow actual threaded textures to finish; frame count alone is not IO evidence.
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec()-started < 12000:
		await process_frame
	if wheel:
		if game_root.game.selected.is_empty():
			for e in game_root.game.units():
				if e.faction == 1 and game_root.game.selected.size() < 3: game_root.game.selected.append(int(e.id))
		game_root._open_wheel(root.get_visible_rect().size*Vector2(.55,.51),false)
		for i in 15: await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://test-output")
	var suffix := ""
	if wheel: suffix = "-wheel"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--size="): suffix = "-"+arg.trim_prefix("--size=")
	root.get_texture().get_image().save_png("res://test-output/"+("home" if home else mode)+("-advisor" if advisor else "")+("-handbook" if handbook else "")+("-narrow" if root.size.x == 360 else "")+suffix+".png")
	print("RECT systemic ",game_root.hud.systemic_panel.get_global_rect()," minimum ",game_root.hud.systemic_panel.get_combined_minimum_size()," label ",game_root.hud.scenario.get_global_rect())
	print("CAPTURED "+mode)
	call_deferred("quit")
