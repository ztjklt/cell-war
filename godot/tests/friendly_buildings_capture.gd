extends SceneTree
var main: Node2D
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("FAIL ",message)

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(1); return
	WarSave.directory = "user://test-saves/friendly-buildings-art"
	root.size = Vector2i(1440,900)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main); current_scene = main
	main.set_process(false); main.start("life"); main.game.paused = true
	var station := WarData.point(main.game.state.resources["lung_r.oxygen"])
	var center := Vector2.INF
	var buildings: Array = []
	var kinds := ["core","barracks","store","lab","clinic","house"]
	# Both rows must stay in the actual lung tissue. The source station's
	# neighborhood includes holes, so an arbitrary second row is not valid.
	for y in range(-14,15,2):
		for x in range(-14,15,2):
			var candidate := station+Vector2(x,y)
			var valid := true
			for i in kinds.size():
				var at := candidate+Vector2((i%3-1)*6,(-3 if i<3 else 3))
				valid = valid and at.distance_to(station)>4 and main.game.navigation.point_allowed(at,0,kinds[i])
			if valid: center = candidate; break
		if center.is_finite(): break
	check(center.is_finite(),"both visual fixture rows fit the existing tissue without moving any map geometry")
	if not center.is_finite(): main.queue_free(); quit(1); return
	for i in kinds.size():
		var kind: String = kinds[i]
		var building: Dictionary = main.game.spawn(kind,1,center+Vector2((i%3-1)*6,(-3 if i<3 else 3)),"building")
		check(not building.is_empty(),kind+" fixture placed on legal tissue")
		if building.is_empty(): continue
		buildings.append(building)
		check(WarData.spec(kind).size == (3 if kind in ["core","barracks"] else 2),kind+" preserves original collision size")
		check(main.world.pick(building,main.world.display_point(WarData.point(building))),kind+" can be picked at its original base")
	main.focus(center,40)
	var began := Time.get_ticks_msec()
	while Time.get_ticks_msec()-began < 12000:
		await process_frame
		if main.world.friendly_buildings.values().all(func(spec): return main.world.textures.get_texture(spec.texture) != null) and main.world.visible_tiles.all(func(tile): return main.world.textures.get_texture(tile.spec.resource) != null): break
	for spec in main.world.friendly_buildings.values(): check(main.world.textures.get_texture(spec.texture) != null,"selected original texture loaded: "+spec.texture)
	for i in 8: await process_frame
	DirAccess.make_dir_recursive_absolute("res://test-output/friendly-buildings")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test-output/friendly-buildings/six-buildings.png")
	for b in buildings: b.complete = false; b.progress = .5
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test-output/friendly-buildings/six-construction.png")
	check(main.game.state.time == 0 and main.game.paused,"visual fixture never advances or spends the real start")
	var file := FileAccess.open("res://test-output/friendly-buildings/native-checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"fixture":"explicitly spawned completed then half-built buildings for native visual review; not an economic progression test"},"  "))
	print("FRIENDLY BUILDINGS NATIVE ",checks-failures.size(),"/",checks)
	main.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
