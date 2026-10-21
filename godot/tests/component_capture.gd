extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	root.size = Vector2i(1440,1000)
	var scene: PackedScene = load("res://scenes/ui_components.tscn")
	var gallery := scene.instantiate(); scene = null
	root.add_child(gallery); current_scene = gallery
	await create_timer(.65).timeout
	DirAccess.make_dir_recursive_absolute("res://ui")
	ResourceSaver.save(WarUISkin.theme(),"res://ui/cell_theme.tres")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://test-output")
		root.get_texture().get_image().save_png("res://test-output/ui-components.png")
	print("COMPONENTS READY")
	gallery.queue_free(); await process_frame
	quit()
