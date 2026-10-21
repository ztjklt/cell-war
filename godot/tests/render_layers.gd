extends SceneTree
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://test-output/original-layers")
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main: Node2D = scene.instantiate()
	scene = null
	root.add_child(main)
	current_scene = main
	main.set_process(false); main.set_process_unhandled_input(false)
	root.size = Vector2i(512,768)
	await process_frame
	main.start("fullbody")
	main.game.paused = true
	main.game.state.entities = {}
	main.game.state.resources = {}
	main.game.state.erase("systemicBattle")
	main.game.state.time = 0
	main.world.record_draws = true
	main.hud.hide()
	main.focus(Vector2(1024,2048),.2)
	main.camera.force_update_scroll()
	var began := Time.get_ticks_msec()
	while Time.get_ticks_msec()-began < 12000:
		await process_frame
	var paths := PackedStringArray()
	for entry in main.world.visible_tiles:
		paths.append(entry.spec.resource)
		if main.world.textures.get_texture(entry.spec.resource) == null: failures.append("unloaded "+entry.spec.resource)
	var trace_file := FileAccess.open("res://tests/fixtures/original-layers.json",FileAccess.READ)
	if trace_file == null:
		printerr("Missing frozen original-layers fixture")
		main.queue_free()
		await process_frame
		quit(1)
		return
	var oracle: Array = JSON.parse_string(trace_file.get_as_text())
	var checked := 0
	var structural_checks := 0
	for i in WarWorldView.LAYER_NODES.size():
		var node: WarWorldLayer = main.world.get_node(WarWorldView.LAYER_NODES[i])
		structural_checks += 1
		if node.channel != i or node.z_index != i or node.world != main.world:
			failures.append("independent layer node "+node.name)
	for i in 7:
		main.world.layer = i
		main.world._process(.75)
		if i == 6:
			while main.world.textures.get_texture(main.world.art.reference.resource) == null: await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var native_draws: Array = []
		# Read the actual successful native texture/heart-mesh draw submissions.
		for channel in [0,1,2,3,6]:
			native_draws.append_array(main.world.drawn_specs.get(channel,[]))
		var expected: Array = oracle[i].draws
		if native_draws.size() != expected.size(): failures.append("draw count "+oracle[i].mode)
		for n in mini(native_draws.size(),expected.size()):
			checked += 1
			if native_draws[n].path != expected[n].path or absf(native_draws[n].alpha-expected[n].alpha) > .00001: failures.append("draw sequence "+oracle[i].mode+" "+str(n))
		root.get_texture().get_image().save_png("res://test-output/original-layers/godot-"+oracle[i].mode+".png")
	main.world.layer = 0
	main.world._process(.75)
	var isolated_images: Dictionary = {}
	for channel in 4:
		for node in main.world.layer_nodes: node.visible = node.channel == channel
		await process_frame
		await RenderingServer.frame_post_draw
		var pixels := root.get_texture().get_image()
		pixels.save_png("res://test-output/original-layers/isolated-"+WarWorldView.LAYER_NODES[channel]+".png")
		var digest := HashingContext.new()
		digest.start(HashingContext.HASH_SHA256); digest.update(pixels.get_data())
		isolated_images[WarWorldView.LAYER_NODES[channel]] = digest.finish().hex_encode()
		structural_checks += 1
		if main.world.drawn_specs.get(channel,[]).is_empty(): failures.append("empty isolated layer "+str(channel))
	if isolated_images.values().size() != 4 or Array(isolated_images.values()).count(isolated_images.BodyBase) != 1:
		failures.append("isolated base should differ from overlays")
	for node in main.world.layer_nodes: node.show()
	var out := FileAccess.open("res://test-output/layer-compositor.json",FileAccess.WRITE)
	out.store_string(JSON.stringify({"drawsChecked":checked,"independentLayerChecks":structural_checks,"isolatedImageSha256":isolated_images,"failures":failures,"oracle":"production Lua ReferenceArt.draw with approved native underlay repair when present","approvedUnderlayRepair":FileAccess.file_exists("res://data/underlay_repair.json"),"nativeEvidence":"actual successful draw submissions from independent layer canvases","screenshots":"test-output/original-layers","pixelIdenticalClaim":false},"  "))
	print("LAYER COMPOSITOR ",checked," draws; failures ",failures)
	main.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
