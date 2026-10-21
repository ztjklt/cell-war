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

func settle() -> void:
	var began := Time.get_ticks_msec()
	while main.camera_travel.active and Time.get_ticks_msec()-began < 2500: await process_frame
	await frames()

func press(button: int,point: Vector2,down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button; event.pressed = down
	event.position = root.get_stretch_transform()*point
	root.push_input(event)

func motion(button: int,point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.button_mask = 1 << (button-1)
	event.position = root.get_stretch_transform()*point
	root.push_input(event)

func drag(button: int,from: Vector2,to: Vector2) -> bool:
	var before: Vector2 = main.camera.position
	press(button,from,true)
	motion(button,to)
	await frames(2)
	var still: bool = main.camera.position.is_equal_approx(before)
	press(button,to,false)
	await frames(2)
	return still and main.camera.position.is_equal_approx(before) and main.drag_button == 0

func centered() -> bool:
	main.camera.force_update_scroll()
	var middle := WarDeskMapFrame.rect_for(root.get_visible_rect().size).get_center()
	return (main.get_canvas_transform()*Vector2(1024,2048)).distance_to(middle) < .5

func run() -> void:
	WarSave.directory = "user://test-saves/desk-camera"
	root.size = Vector2i(1440,900)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main); current_scene = main
	main.set_process(false); main.start("life"); main.game.paused = true
	if DisplayServer.get_name() == "headless": main.world.hide()
	main.hud.life_dialogue.expanded = false
	await frames()
	check(main.overview_active and centered(),"new life run opens with the whole body centered on the sheet")
	check(is_equal_approx(main.hud.life_dialogue.phone.get_rect().end.x,1400),"desktop phone moves left while keeping its width")
	var unit: Dictionary = {}
	for e in main.game.units():
		if e.kind == "worker" and e.faction == 1: unit = e; break
	for window_size in [Vector2i(1440,900),Vector2i(360,780)]:
		root.size = window_size; await frames(10); main.hud._layout(); await frames()
		main.overview(); await frames()
		check(centered(),"overview stays centered after resize "+str(window_size))
		main.focus(WarData.point(unit),18); main.camera.force_update_scroll(); await frames()
		var field := WarDeskMapFrame.rect_for(root.get_visible_rect().size)
		var at := field.get_center()
		var selected: Array = main.game.selected.duplicate()
		var commands: Array = main.game.state.commands.duplicate(true)
		for button in [MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
			check(await drag(button,at,at-Vector2(45,35)),"mouse drag cannot pan the body "+str(button)+" "+str(window_size))
		check(not main.hud.wheel.visible and main.game.selected == selected and main.game.state.commands == commands,"blocked drags create no wheel, selection change or command "+str(window_size))
		main.command_mode = "move"
		check(await drag(MOUSE_BUTTON_LEFT,at,at-Vector2(40,30)),"armed command drag cannot pan or issue an order "+str(window_size))
		check(main.game.state.commands == commands and main.command_mode == "move","drag keeps the armed command unsubmitted "+str(window_size))
		main.command_mode = ""
		var pan := InputEventPanGesture.new()
		pan.position = root.get_stretch_transform()*at; pan.delta = Vector2(12,8)
		var before: Vector2 = main.camera.position
		root.push_input(pan); await frames()
		check(main.camera.position.is_equal_approx(before),"trackpad gesture keeps the paper fixed "+str(window_size))
		Input.action_press("camera_right"); Input.action_press("camera_down")
		main._update_camera_controls(.5)
		Input.action_release("camera_right"); Input.action_release("camera_down")
		check(main.camera_travel.target_position.x > before.x and main.camera_travel.target_position.y > before.y,"WASD pans the camera across the paper "+str(window_size))
		await settle()
		main.focus(before,main.camera.zoom.x)
		main.game.selected.clear()
		check(await drag(MOUSE_BUTTON_LEFT,at-Vector2(12,12),at+Vector2(6,6)),"left box selection keeps the camera fixed "+str(window_size))
		check(main.game.selected.has(int(unit.id)),"left drag still box-selects cells "+str(window_size))
		main.hud.inspection.clear()
		main.focus(WarData.point(unit),18); main.camera.force_update_scroll()
		var anchor: Vector2 = main.get_canvas_transform().affine_inverse()*at
		var zoom: float = main.camera.zoom.x
		press(MOUSE_BUTTON_WHEEL_UP,at,true); await frames()
		check(main.camera.zoom.x > zoom and anchor.distance_to(main.get_canvas_transform().affine_inverse()*at) < .01,"wheel zoom still inspects the pointed location "+str(window_size))
		zoom = main.camera.zoom.x
		var pinch := InputEventMagnifyGesture.new()
		pinch.position = root.get_stretch_transform()*at; pinch.factor = 1.2
		root.push_input(pinch); await frames()
		check(main.camera.zoom.x > zoom,"pinch zoom remains available "+str(window_size))
		main._zoom(.00001,at+Vector2(10,-15)); await settle()
		check(main.overview_active and centered(),"zooming out restores the centered whole-body view "+str(window_size))
		main.focus(WarData.point(unit),18)
		main.hud.zoom_tools.get_child(1).pressed.emit()
		await settle()
		check(main.camera.zoom.x < 18,"zoom button remains available "+str(window_size))
		main.focus(WarData.point(unit),main.minimum_zoom()*.999)
		check(main.overview_active and centered(),"button zoom also recenters at the overview limit "+str(window_size))
		main.focus(WarData.point(unit),18); await frames()
		var nav: WarMinimap = main.hud.navigation
		var nav_point := nav.get_global_rect().get_center()+Vector2(6,6)
		var target: Vector2 = (nav_point-nav.global_position-nav.origin)/nav.map_scale
		press(MOUSE_BUTTON_LEFT,nav_point,true); await frames()
		check(main.camera.position.distance_to(target) < .1,"minimap click still locates a chosen area "+str(window_size))
		before = main.camera.position
		motion(MOUSE_BUTTON_LEFT,nav_point+Vector2(10,10)); await frames()
		press(MOUSE_BUTTON_LEFT,nav_point+Vector2(10,10),false); await frames()
		check(main.camera.position.is_equal_approx(before),"dragging the minimap cannot slide the anatomy "+str(window_size))
		main.focus(WarData.point(unit),18); await frames()
		check(await drag(MOUSE_BUTTON_RIGHT,at,main.hud.overview_button.get_global_rect().get_center()),"release over fixed HUD ends a paper drag without moving or clicking through "+str(window_size))
		check(not main.hud.wheel.visible and main.game.state.commands == commands,"drag into HUD does not become a battlefield command "+str(window_size))
	var file := FileAccess.open("res://test-output/desk-camera.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	print("DESK CAMERA ",checks," checks, failures=",failures)
	main.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
