extends SceneTree
var failures: Array[String] = []
var checks := 0

func check(value: bool,message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("FAIL ",message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://test-output/legacy-art")
	var data: Dictionary = WarData.read("legacy_art")
	check(FileAccess.get_sha256("res://data/legacy_base.bin") == data.meshSha256,"original contour mesh integrity")
	var bytes := FileAccess.open("res://data/legacy_base.bin",FileAccess.READ).get_length()
	for spec in data.base:
		check(int(spec.offset)+int(spec.vertexCount)*8 <= bytes and int(spec.vertexCount)%3 == 0,"valid constrained triangle buffer")
		check(absf(spec.area-spec.triangulatedArea) <= maxf(.000001,spec.area*1e-9),"triangulation preserves curved-region area")
	for sample in data.alphaOracle: check(absf(WarLegacyArt.blend(sample.zoom)-sample.alpha) < .000001,"original zoom blend "+str(sample.zoom))
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main: Node2D = scene.instantiate(); scene = null
	root.add_child(main); current_scene = main
	main.set_process(false); main.set_process_unhandled_input(false)
	root.size = Vector2i(1280,800)
	var trace_file := FileAccess.open("res://tests/fixtures/legacy-art.json",FileAccess.READ)
	if trace_file == null: printerr("Missing frozen legacy-art fixture"); quit(1); return
	var fixtures: Array = JSON.parse_string(trace_file.get_as_text())
	for fixture in fixtures:
		main.start(fixture.mode); main.game.paused = true
		main.focus(WarData.point(fixture.center),fixture.zoom)
		main.hud.hide()
		main.game.state.entities = {}; main.game.state.resources = {}; main.game.state.combatProjectiles = []; main.game.corpses.clear()
		main.camera.force_update_scroll()
		await process_frame
		main.world._process(0)
		check(main.world.visible_tiles.is_empty(),"trial does not load fullbody layer tiles")
		check(main.world.legacy.enabled(main.game),"trial uses original legacy render branch")
		var expected: Array = fixture.overlays.map(func(row): return row.resource)
		var actual: Array = main.world.legacy.active_specs.map(func(row): return row.resource)
		check(actual == expected,"production Lua trial overlay draw order "+fixture.mode+" got "+str(actual)+" expected "+str(expected))
		if DisplayServer.get_name() != "headless":
			var began := Time.get_ticks_msec()
			while Time.get_ticks_msec()-began < 10000: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://test-output/legacy-art/"+fixture.mode+"-godot.png")
	main.start("fullbody"); await process_frame
	check(not main.world.legacy.enabled(main.game),"fullbody keeps current streamed renderer")
	var file := FileAccess.open("res://test-output/legacy-art.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"pixelIdenticalClaim":false,"oracle":"production ReferenceArt static trial compositor"},"  "))
	print("LEGACY ART ",checks-failures.size(),"/",checks)
	main.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
