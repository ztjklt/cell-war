extends SceneTree
var failures: Array[String] = []
var checks := 0

func check(value: bool,message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("FAIL ",message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main: Node2D = scene.instantiate(); scene = null
	root.add_child(main); current_scene = main
	main.set_process(false); main.set_process_unhandled_input(false)
	main.start("lung_skirmish")
	await process_frame
	main.camera.force_update_scroll()
	var run: Dictionary = main.game.state.get("lungSkirmish",{})
	check(run.has("center"),"encounter center preserved beyond Lua Save snapshot")
	check(run.get("players",[]).size() == 3,"three original encounter players preserved")
	check(run.get("enemies",[]).size() == 3,"three original viruses preserved")
	if run.has("center"):
		var center := WarData.point(run.center)
		check(main.camera.position.distance_to(center) < .001,"entry camera focuses encounter rather than abdominal worker")
		check(main.game.scenarios.home().distance_to(center) < .001,"encounter home and retreat center agree")
		check(is_equal_approx(main.camera.zoom.x,.95*32),"original closeup zoom")
		var dimensions: Vector2 = main.get_viewport_rect().size/main.camera.zoom
		var bounds := Rect2(main.camera.get_screen_center_position()-dimensions*.5,dimensions)
		for id in run.players:
			var e: Dictionary = main.game.entity(int(id))
			check(main.game.selected.has(int(id)),"encounter player initially selected")
			check(e.get("lungSkirmishUnit",false) and e.hp > 0 and bounds.has_point(WarData.point(e)),"living encounter player inside initial view")
			check(main.game.visible(e) and not main.world.obscured(e,WarData.point(e)),"encounter player is render-visible")
		for id in run.enemies:
			var e: Dictionary = main.game.entity(int(id))
			check(bounds.has_point(WarData.point(e)),"enemy inside initial closeup")
		check(main.game.selected.size() == 3,"unrelated abdominal cells not selected")
	DirAccess.make_dir_recursive_absolute("res://test-output")
	var out := FileAccess.open("res://test-output/cell-entry.json",FileAccess.WRITE)
	out.store_string(JSON.stringify({"checks":checks,"failures":failures,"source":"original LungSkirmish.setup metadata; native camera/selection/render visibility"},"  "))
	print("CELL ENTRY ",checks-failures.size(),"/",checks)
	main.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
