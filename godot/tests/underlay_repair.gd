extends SceneTree
var checks := 0
var failures: Array[String] = []

func check(value: bool,message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("FAIL ",message)

func _initialize() -> void:
	call_deferred("run")

func alpha_at(tiles: Array,point: Vector2,level: int) -> float:
	for tile in tiles:
		var b: Array = tile.sourceBox
		if not Rect2(b[0],b[1],b[2]-b[0],b[3]-b[1]).has_point(point): continue
		var spec: Dictionary = tile.levels[str(level)]
		var crop: Array = spec.sourceBox
		var pixel := Vector2i((point-Vector2(crop[0],crop[1]))*level)
		var texture := load("res://assets/"+spec.resource) as Texture2D
		var image := texture.get_image()
		if pixel.x < 0 or pixel.y < 0 or pixel.x >= image.get_width() or pixel.y >= image.get_height(): return 0
		return image.get_pixelv(pixel).a
	return 0

func run() -> void:
	var art: Dictionary = WarData.read("art")
	var repair: Dictionary = WarData.read("underlay_repair")
	var tiles: Array = art.foundation.filter(func(tile): return tile.kind == "underlay")
	check(tiles.size() == int(repair.tiles),"all repaired underlay tiles registered")
	check(FileAccess.get_sha256("res://"+repair.vector) == repair.vectorSha256,"repaired vector hash")
	for tile in tiles:
		for level in [4,8,16,32]:
			var spec: Dictionary = tile.levels[str(level)]
			check(spec.resource.begins_with("migrated/underlay-repair/"),"all LODs use repaired underlay")
			var texture := load("res://assets/"+spec.resource) as Texture2D
			var image := texture.get_image()
			check(image != null and image.get_size() == Vector2i(spec.pixelSize[0],spec.pixelSize[1]),"tile dimensions match source crop")
	for level in [4,8,16,32]:
		for point in [Vector2(390,488),Vector2(398,488),Vector2(402,488)]:
			check(alpha_at(tiles,point,level) > .99,"reported liver notch filled at LOD "+str(level))
		check(alpha_at(tiles,Vector2(510,310),level) == 0,"single-spine exclusion retained")
		check(alpha_at(tiles,Vector2(515,808),level) > .99,"bladder lower tissue remains continuous")
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main: Node2D = scene.instantiate(); scene = null
	root.add_child(main); current_scene = main
	main.set_process(false); main.set_process_unhandled_input(false)
	main.start("fullbody"); main.game.paused = true
	main.game.state.entities = {}; main.game.state.resources = {}; main.game.selected.clear()
	main.hud.hide(); main.world.layer = 4; main.world._process(.75)
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1280,800)
		for fixture in [["liver",Vector2(398,488)],["bladder",Vector2(515,799)]]:
			main.focus(WarData.source_to_world([fixture[1].x,fixture[1].y]),8)
			main.camera.force_update_scroll()
			var began := Time.get_ticks_msec()
			while Time.get_ticks_msec()-began < 7000: await process_frame
			await RenderingServer.frame_post_draw
			var active: Array = main.world.tiles_for_layer(1)
			check(not active.is_empty(),"repaired layer draws in native closeup")
			for entry in active: check(main.world.textures.get_texture(entry.spec.resource) != null,"native underlay texture ready")
			root.get_texture().get_image().save_png("res://test-output/underlay-repair/"+fixture[0]+"-godot.png")
	var out := FileAccess.open("res://test-output/underlay-repair.json",FileAccess.WRITE)
	out.store_string(JSON.stringify({"checks":checks,"failures":failures,"tiles":tiles.size(),"lods":[4,8,16,32],"intentionalArtRepair":true,"originalNavigationChanged":false},"  "))
	print("UNDERLAY REPAIR ",checks-failures.size(),"/",checks)
	main.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
