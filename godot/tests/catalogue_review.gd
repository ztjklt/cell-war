extends SceneTree
## Interactive review entry. Returning from the catalogue reaches the real cover.
func _initialize() -> void:
	call_deferred("open_gallery")

func open_gallery() -> void:
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	main.hud.cover_preview.open()
