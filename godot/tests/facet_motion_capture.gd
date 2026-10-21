extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main: Node2D = scene.instantiate(); scene = null
	root.add_child(main); current_scene = main
	main.set_process(false); main.set_process_unhandled_input(false)
	main.start("systemic"); main.game.paused = true
	await create_timer(10).timeout
	DirAccess.make_dir_recursive_absolute("res://test-output/facet-motion")
	var wheel: WarCommandWheel = main.hud.wheel
	var target := root.get_visible_rect().size*Vector2(.55,.5)
	for frame in 84:
		if frame == 5: main._open_wheel(target,false)
		if frame == 25:
			var event := InputEventMouseMotion.new()
			event.position = root.get_stretch_transform()*wheel.buttons[1].get_global_rect().get_center()
			root.push_input(event)
		if frame == 45:
			var event := InputEventMouseButton.new()
			event.position = root.get_stretch_transform()*wheel.buttons[1].get_global_rect().get_center()
			event.button_index = MOUSE_BUTTON_LEFT; event.pressed = true
			root.push_input(event)
		if frame == 48:
			var event := InputEventMouseButton.new()
			event.position = root.get_stretch_transform()*wheel.buttons[1].get_global_rect().get_center()
			event.button_index = MOUSE_BUTTON_LEFT; event.pressed = false
			root.push_input(event)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://test-output/facet-motion/%03d.png" % frame)
		await process_frame
	print("MOTION CAPTURED · orders ",main.game.state.commands.size())
	main.queue_free(); await process_frame
	quit()
