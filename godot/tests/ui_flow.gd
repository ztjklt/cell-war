extends SceneTree
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("run")

func check(value: bool,text: String) -> void:
	if not value: failures.append(text); printerr("FAIL "+text)
	else: print("PASS "+text)

func run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main: Node2D = scene.instantiate()
	scene = null
	root.add_child(main)
	current_scene = main
	main.start("systemic")
	main.game.paused = true
	await process_frame
	var red: Dictionary = {}
	for e in main.game.units():
		if e.kind == "worker": red = e; break
	main.focus(WarData.point(red),20)
	main.camera.force_update_scroll()
	var at: Vector2 = main.get_canvas_transform()*WarData.point(red)
	main._select(at,false,false)
	check(main.game.selected.has(int(red.id)),"mouse selection uses camera coordinates")
	var target := WarData.point(red)+Vector2(-2,0)
	var screen: Vector2 = main.get_canvas_transform()*target
	main._command(screen,false)
	main._command(screen,true)
	check(main.game.state.commands.size() == 2,"paused commands wait for the simulation step")
	main.game.step(.1)
	check(red.orders.size() == 2,"shift appends a command")
	main.game.issue("stop")
	main.game.step(.1)
	check(red.orders.is_empty(),"stop clears queued commands")
	main.hud.toggle_menu()
	check(main.hud.menu.visible and main.game.paused,"menu pauses the game")
	main.hud.close_menu()
	check(not main.hud.menu.visible and main.game.paused,"menu preserves prior pause state")
	var previous_button_ratio := 0.0
	for window_size in [Vector2i(720,450),Vector2i(1280,800),Vector2i(1440,900),Vector2i(1920,1200)]:
		root.size = window_size
		for i in 5: await process_frame
		var stretch := root.get_stretch_transform()
		var factor := stretch.get_scale()
		var bounds: Rect2 = main.hud.pause_button.get_global_rect()
		var ratio: float = bounds.size.x*factor.x/root.size.x
		check(absf(factor.x-factor.y) < .002,"uniform canvas scaling at "+str(window_size))
		if previous_button_ratio > 0:
			check(absf(ratio-previous_button_ratio) < .002,"button keeps its window proportion at "+str(window_size))
		previous_button_ratio = ratio
		# Inject window coordinates, so Godot's actual input conversion is exercised.
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = stretch*bounds.get_center()
		click.pressed = true
		root.push_input(click)
		click = click.duplicate(); click.pressed = false
		root.push_input(click)
		await process_frame
		check(not main.game.paused,"scaled pause button receives physical click at "+str(window_size))
		main.game.paused = true
		main.focus(WarData.point(red),20)
		main.camera.force_update_scroll()
		main.game.selected.clear()
		click = InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = stretch*(main.get_canvas_transform()*WarData.point(red))
		click.pressed = true; root.push_input(click)
		click = click.duplicate(); click.pressed = false; root.push_input(click)
		await process_frame
		check(main.game.selected.has(int(red.id)),"scaled world selection receives physical click at "+str(window_size))
	root.size = Vector2i(360,780)
	for i in 5: await process_frame
	main.hud._layout()
	check(main.hud.panel.visible and main.hud.panel.position.y > 400,"narrow layout keeps original bottom selection card")
	for i in 5: await process_frame
	var outside := 0
	for button in main.hud.root.find_children("*","Button",true,false):
		if not button.is_visible_in_tree(): continue
		var rect: Rect2 = button.get_global_rect()
		if rect.position.x < -1 or rect.end.x > 361 or rect.end.y > 781:
			outside += 1
			printerr("OUTSIDE ",button.text," ",rect)
	check(outside == 0,"visible buttons fit 360px window")
	main.start("trachea_01")
	for i in 8: await process_frame
	var battle: WarBattleHUD = main.hud.battle
	check(battle.bar.get_global_rect().end.y <= battle.gauge_root.get_global_rect().position.y,"campaign header does not overlap zone gauge")
	outside = 0
	for button in battle.find_children("*","Button",true,false):
		if not button.is_visible_in_tree(): continue
		var rect: Rect2 = button.get_global_rect()
		if rect.position.x < -1 or rect.end.x > 361 or rect.end.y > 781: outside += 1; printerr("OUTSIDE campaign ",button.text," ",rect)
	check(outside == 0,"campaign controls fit 360px window")
	root.size = Vector2i(430,932)
	for i in 5: await process_frame
	check(root.get_stretch_transform().get_scale().x > 1.19,"portrait UI grows with the window")
	var visible_size := root.get_visible_rect().size
	check(visible_size.x < 720,"larger portrait window retains narrow layout")
	root.size = Vector2i(1280,800)
	for i in 5: await process_frame
	check(main.hud.battle.bar.get_global_rect().end.x <= root.get_visible_rect().size.x,"rotation back to landscape repositions campaign controls")
	var file := FileAccess.open("res://test-output/ui-flow.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"windowSizes":[[720,450],[1280,800],[1440,900],[1920,1200],[360,780],[430,932]],"physicalInputTested":true},"  "))
	print("UI FLOW DONE ",failures)
	main.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
