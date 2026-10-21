extends SceneTree
var main: Node2D
var failures: Array[String] = []
var checks := 0
const OUTPUT := "res://test-output/inspection-camera/"

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("FAIL ",message)

func frames(count := 5) -> void:
	for i in count: await process_frame

func settle() -> void:
	var began := Time.get_ticks_msec()
	while main.camera_travel.active and Time.get_ticks_msec()-began < 2500: await process_frame
	await frames()
	check(not main.camera_travel.active,"camera travel reaches its destination")

func click(point: Vector2,button := MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.position = root.get_stretch_transform()*point
	event.button_index = button; event.pressed = true
	root.push_input(event)
	event = event.duplicate(); event.pressed = false; root.push_input(event)
	await frames(2)

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code; event.physical_keycode = code; event.pressed = true
	root.push_input(event)
	event = event.duplicate(); event.pressed = false; root.push_input(event)

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT+name+".png")

func wait_terrain() -> void:
	if DisplayServer.get_name() == "headless": return
	var began := Time.get_ticks_msec()
	var stable := 0
	while Time.get_ticks_msec()-began < 12000 and stable < 5:
		await process_frame
		var ready: bool = main.world.textures.pending.is_empty() and not main.world.visible_tiles.is_empty()
		for tile in main.world.visible_tiles:
			if main.world.textures.get_texture(tile.spec.resource) == null: ready = false
		stable = stable+1 if ready else 0
	check(stable >= 5,"visible terrain finishes streaming")

func native_clip_check() -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var shown := root.get_texture().get_image()
	main.world.hide(); await frames(3); await RenderingServer.frame_post_draw
	var hidden := root.get_texture().get_image()
	var aperture: Rect2 = main.map_frame.screen_rect()
	for uv in [Vector2(.02,.5),Vector2(.98,.5)]:
		var pixel := Vector2i(Vector2(shown.get_size())*uv)
		var a := shown.get_pixelv(pixel)
		var b := hidden.get_pixelv(pixel)
		if not aperture.has_point(Vector2(pixel)):
			check(absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b) < .004,"terrain stays within the moving paper edges "+str(uv))
		elif main.camera.zoom.x > 32:
			check(absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b) > .1,"microscopic terrain extends beyond the former fixed window "+str(uv))
	main.world.show(); await frames(3)

func rigid_desk_check(target: Vector2) -> void:
	var view: Vector2 = root.get_visible_rect().size
	var basis := WarDeskMapFrame.overview_projection(view,Vector2(2048,4096))
	var projection: Transform2D = main.desk_layer.transform
	var ratio: float = main.camera.zoom.x/main.minimum_zoom()
	var anatomy: Vector2 = main.get_canvas_transform()*main.world.display_point(target)
	for mark in [view*Vector2(.21,.45),view*Vector2(.60,.55),view*Vector2(.12,.48)]:
		var expected: Vector2 = (basis*main.world.display_point(target)-mark)*ratio
		check((anatomy-projection*mark).distance_to(expected) < .2,"body and desk landmarks retain one shared camera projection")
	check(projection.is_equal_approx(main.map_frame.desk_projection()),"background uses the same projection as the world-space paper")

func run() -> void:
	WarSave.directory = "user://test-saves/inspection-camera"
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.size = Vector2i(1440,900)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main); current_scene = main
	main.set_process(false); main.start("life"); main.game.paused = true
	if DisplayServer.get_name() == "headless": main.world.hide()
	await frames(30)
	var field := WarDeskMapFrame.rect_for(root.get_visible_rect().size)
	var phone_rect: Rect2 = main.hud.life_dialogue.phone.get_rect()
	var art_size: Vector2 = main.get_node("CommandBackdrop/DeskArt").size
	var ids: Array = main.world.layer_nodes.map(func(node): return node.get_instance_id())
	var zoom: float = main.camera.zoom.x
	key(KEY_Q); await frames()
	check(main.camera.zoom.x > zoom and not main.hud.inspection.has_point,"Q zooms without an observation coordinate")
	await settle()
	var unit: Dictionary = {}
	for e in main.game.units():
		if e.kind == "worker" and e.faction == 1: unit = e; break
	var target := WarData.point(unit)
	main.camera.force_update_scroll()
	var at: Vector2 = main.get_canvas_transform()*main.world.display_point(target)
	var commands: Array = main.game.state.commands.duplicate(true)
	await click(at)
	check(not main.hud.inspection.has_point,"physical map click does not set a camera coordinate")
	check(not main.hud.wheel.visible and main.game.state.commands == commands,"map click opens no command wheel and submits no order")
	await wait_terrain()
	await capture("selected")
	var camera_center: Vector2 = main.camera.position
	zoom = main.camera.zoom.x
	key(KEY_Q)
	check(is_equal_approx(main.camera.zoom.x,zoom),"Q changes the camera destination without jumping the image")
	await create_timer(.06).timeout
	check(main.camera.zoom.x > zoom and main.camera.zoom.x < main.camera_travel.target_zoom,"camera passes smoothly through an intermediate distance")
	await capture("approaching")
	await settle()
	check(main.camera.position.distance_to(camera_center) < .05,"Q keeps the current view center instead of the clicked coordinate")
	check((main.get_canvas_transform()*main.world.display_point(target)).distance_to(field.get_center()) > .5,"clicking a coordinate does not center the camera")
	check(main.world.global_transform.is_equal_approx(Transform2D.IDENTITY) and main.world.layer_nodes.all(func(node): return node.scale.is_equal_approx(Vector2.ONE)),"camera travel never rescales anatomy nodes or their independent layers")
	rigid_desk_check(target)
	check(main.map_frame.screen_rect().size.x > field.size.x*1.5,"paper aperture expands with the desktop approach")
	await wait_terrain()
	await native_clip_check()
	await capture("desk-approach")
	for i in 8: key(KEY_Q)
	await settle()
	check(is_equal_approx(main.camera.zoom.x,2.8*32),"repeated Q reaches the existing microscopic camera limit")
	check(main.world.visible_world_rect().size.is_equal_approx(main.map_frame.screen_rect().size/main.camera.zoom),"texture culling follows the visible portion of the moving paper")
	check(main.map_frame.screen_rect().size.is_equal_approx(root.get_visible_rect().size),"microscopic paper view fills the screen")
	rigid_desk_check(target)
	if DisplayServer.get_name() != "headless":
		var began := Time.get_ticks_msec()
		while Time.get_ticks_msec()-began < 10000:
			await process_frame
			if main.world.visible_tiles.any(func(tile): return tile.spec.resource.contains("/l32/") and main.world.textures.get_texture(tile.spec.resource) != null): break
		check(main.world.visible_tiles.any(func(tile): return tile.spec.resource.contains("/l32/") and main.world.textures.get_texture(tile.spec.resource) != null),"microscope loads actual level-32 terrain tiles")
	await wait_terrain()
	await native_clip_check()
	await capture("microscopic")
	var projected_phone: Rect2 = main.desk_layer.transform*phone_rect
	var actual_phone: Rect2 = main.hud.life_dialogue.phone.get_global_rect()
	check(actual_phone.position.distance_to(projected_phone.position) < .5 and actual_phone.size.distance_to(projected_phone.size) < .5,"phone and its live controls travel with the desk")
	check(main.get_node("CommandBackdrop/DeskArt").size == art_size,"desk artwork keeps its native layout while the common camera changes")
	check(main.world.layer_nodes.map(func(node): return node.get_instance_id()) == ids,"camera travel retains every independent anatomy canvas")
	check(main.hud.overview_button.text.is_empty() and main.hud.overview_button.get_rect().end.x < main.hud.layer_button.position.x,"return-to-overview is an icon directly left of the eye")
	await click(main.hud.overview_button.get_global_rect().get_center())
	await settle()
	check(main.overview_active and is_equal_approx(main.camera.zoom.x,main.minimum_zoom()) and main.camera.position.distance_to(Vector2(1024,2048)) < .01,"physical overview icon restores the centered whole-body camera")
	check(main.desk_layer.transform.is_equal_approx(Transform2D.IDENTITY),"returning to overview restores the entire desk composition")
	await capture("returned")
	await click(main.hud.life_dialogue.phone.get_global_rect().get_center())
	check(not main.hud.inspection.has_point,"phone clicks do not create a camera coordinate")
	root.size = Vector2i(360,780); await frames(12); main.hud._layout()
	main.hud.life_dialogue.expanded = false; main.hud.life_dialogue.layout()
	main.overview(); await frames()
	check(main.hud.overview_button.get_rect().end.x < main.hud.layer_button.position.x and main.hud.overview_button.position.x > 0,"portrait retains the separate overview and eye icons")
	at = main.get_canvas_transform()*main.world.display_point(target)
	await click(at)
	camera_center = main.camera.position
	key(KEY_Q); await settle()
	check(main.camera.position.distance_to(camera_center) < .05,"portrait Q also keeps its current view center")
	await click(main.hud.overview_button.get_global_rect().get_center()); await settle()
	check(main.overview_active and is_equal_approx(main.camera.zoom.x,main.minimum_zoom()),"portrait overview icon returns to the whole body")
	await capture("portrait")
	var file := FileAccess.open(OUTPUT+"checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	print("INSPECTION CAMERA ",checks," checks, failures=",failures)
	main.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
