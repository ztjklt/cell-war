extends SceneTree
var main: Node2D
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("FAIL ",message)

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(1); return
	WarSave.directory = "user://test-saves/organ-resources-native"
	root.size = Vector2i(1440,900)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main); current_scene = main
	main.set_process(false); main.start("life"); main.game.paused = true
	DirAccess.make_dir_recursive_absolute("res://test-output/organ-resources")
	for id in ["lung_r.oxygen","stomach.food","small_intestine.wood"]:
		var source: Dictionary = main.game.state.resources[id]
		main.focus(WarData.point(source),32)
		var texture: String = WarOrganResources.data().art[source.kind].texture
		var began := Time.get_ticks_msec()
		while Time.get_ticks_msec()-began < 12000:
			await process_frame
			if main.world.textures.get_texture(texture) != null and main.world.visible_tiles.all(func(tile): return main.world.textures.get_texture(tile.spec.resource) != null): break
		check(main.world.textures.get_texture(texture) != null,id+" original GPT texture is loaded by the real world")
		check(main.game.paused and main.game.state.time == 0,id+" capture never advances paused economy")
		for i in 8: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://test-output/organ-resources/"+source.kind+"-station.png")
	var empty: Dictionary = main.game.state.resources["small_intestine.wood"]
	empty.amount = 0.0
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test-output/organ-resources/depleted-station.png")
	check(main.game.state.resources.has(empty.id),"depleted source remains present for visual and input selection")
	empty.contested = true
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test-output/organ-resources/contested-station.png")
	var file := FileAccess.open("res://test-output/organ-resources/native-checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	print("ORGAN RESOURCES NATIVE ",checks-failures.size(),"/",checks)
	main.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
