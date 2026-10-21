extends SceneTree
var main: Node2D
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("FAIL ",message)

func frames(count := 5) -> void:
	for i in count: await process_frame

func click_at(point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT; event.pressed = true
	event.position = root.get_stretch_transform()*point
	root.push_input(event)
	event = event.duplicate(); event.pressed = false
	root.push_input(event)
	await frames(2)

func native_clip_check() -> void:
	if DisplayServer.get_name() == "headless": return
	main.start("systemic"); main.game.paused = true
	main.overview()
	var began := Time.get_ticks_msec()
	while Time.get_ticks_msec()-began < 6000: await process_frame
	await RenderingServer.frame_post_draw
	var shown := root.get_texture().get_image()
	shown.save_png("res://test-output/command-desk-native.png")
	main.world.hide()
	await frames(2); await RenderingServer.frame_post_draw
	var hidden := root.get_texture().get_image()
	for uv in [Vector2(.24,.48),Vector2(.80,.47),Vector2(.60,.97)]:
		var pixel := Vector2i(Vector2(shown.get_size())*uv)
		var a := shown.get_pixelv(pixel)
		var b := hidden.get_pixelv(pixel)
		check(absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b) < .004,"native terrain never covers desk outside paper: "+str(uv))
	var pixel := Vector2i(Vector2(shown.get_size())*Vector2(.465,.48))
	var a := shown.get_pixelv(pixel)
	var b := hidden.get_pixelv(pixel)
	check(absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b) > .1,"native terrain is actually drawn inside paper")

func run() -> void:
	WarSave.directory = "user://test-saves/command-desk"
	root.size = Vector2i(1440,900)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main); current_scene = main
	main.set_process(false); main.start("life"); main.game.paused = true
	main.hud.life_dialogue.expanded = false
	await frames()
	var world_id: int = main.world.get_instance_id()
	var layers := {}
	for name in WarWorldView.LAYER_NODES: layers[name] = main.world.get_node(name).get_instance_id()
	var scenery: Control = main.get_node("CommandBackdrop/DeskArt")
	check(scenery.mouse_filter == Control.MOUSE_FILTER_IGNORE and scenery.find_children("*","Button",true,false).is_empty(),"desk scenery cannot impersonate or intercept buttons")
	var life: Dictionary = main.game.life.state().duplicate(true)
	var unit: Dictionary = {}
	for e in main.game.units():
		if e.kind == "worker" and e.faction == 1: unit = e; break
	for window_size in [Vector2i(1440,900),Vector2i(1920,1200),Vector2i(360,780),Vector2i(430,932),Vector2i(1280,800)]:
		root.size = window_size; await frames(8)
		main.hud._layout(); await frames()
		var view: Vector2 = root.get_visible_rect().size
		var field := WarDeskMapFrame.rect_for(view)
		main.focus(WarData.point(unit),18); main.camera.force_update_scroll()
		await frames(2)
		var at: Vector2 = main.get_canvas_transform()*main.world.display_point(main.world.unit_position(unit))
		check(at.distance_to(field.get_center()) < .5,"camera puts focused unit on the desk sheet "+str(window_size))
		main.game.selected.clear()
		await click_at(at)
		check(main.game.selected.has(int(unit.id)),"physical click selects live anatomy unit "+str(window_size))
		var selected: Array = main.game.selected.duplicate()
		main.overview(); await frames()
		for button in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
			var event := InputEventMouseButton.new()
			event.button_index = button; event.pressed = true; event.position = Vector2(3,view.y*.5)
			main._unhandled_input(event)
			event = event.duplicate(); event.pressed = false; main._unhandled_input(event)
		check(main.drag_button == 0 and not main.hud.wheel.visible and main.game.selected == selected,"clicking desk props creates no map order or command wheel "+str(window_size))
		main.focus(WarData.point(unit),18); main.camera.force_update_scroll(); await frames()
		var before: Vector2 = main.get_canvas_transform().affine_inverse()*field.get_center()
		main._zoom(1.12,field.get_center()); main.camera.force_update_scroll()
		var after: Vector2 = main.get_canvas_transform().affine_inverse()*field.get_center()
		check(before.distance_to(after) < .01,"zoom preserves the map point under the cursor "+str(window_size))
	check(main.game.life.state() == life,"desk framing never changes money, age or life decisions")
	check(main.world.get_instance_id() == world_id,"resizing keeps the same live world")
	for name in layers: check(main.world.get_node(name).get_instance_id() == layers[name],"independent map layer preserved: "+name)
	await native_clip_check()
	var file := FileAccess.open("res://test-output/command-desk.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	print("COMMAND DESK ",checks," checks, failures=",failures)
	main.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
