extends SceneTree
## Regression coverage for the desk-phone reply path and the queued red-cell order.
var failures: Array[String] = []

func check(value: bool, text: String) -> void:
	if value: print("PASS "+text)
	else:
		failures.append(text)
		printerr("FAIL "+text)

func _initialize() -> void:
	call_deferred("run")

func legal_target(game: WarSimulation, red: Dictionary) -> Vector2:
	var from := WarData.point(red)
	for distance in [1.0, 2.0, 3.0, 4.0, 5.0]:
		for direction in 16:
			var candidate: Vector2 = from+Vector2.from_angle(float(direction)*TAU/16.0)*distance
			if game.navigation.point_allowed(candidate,int(red.get("vesselLane",0)),red.kind) and game.navigation.clear_segment(from,candidate,int(red.get("vesselLane",0)),red.kind) and game.navigation.movement_clear(from,candidate,red.kind,int(red.faction)):
				return candidate
	return Vector2.INF

func run() -> void:
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	for _frame in 3: await process_frame
	main.start("life")
	for _frame in 2: await process_frame
	var game: WarSimulation = main.game
	var phone: WarLifeDialogue = main.hud.life_dialogue
	game.life.offer()
	phone._take_pause()
	for _frame in 2: await process_frame
	check(main.hud.dialogue.bubble == "你有一条新消息请查收。","new external contact alerts through the cerebellum")
	phone._elapsed = 999.0
	phone._animate(0.0)
	check(not phone.option_buttons.is_empty() and not phone.option_buttons[0].disabled,"live phone reply is clickable while the simulation is paused")
	if not phone.option_buttons.is_empty(): phone.option_buttons[0].pressed.emit()
	for _frame in 2: await process_frame
	check(game.life.state().pending.is_empty() and int(game.life.state().decisionCount) == 1,"live phone reply settles the selected event")
	check(not game.paused,"settling a phone reply resumes simulation time")

	phone.show_preview("late_work")
	for _frame in 2: await process_frame
	phone._elapsed = 999.0
	phone._animate(0.0)
	check(not phone.option_buttons.is_empty() and not phone.option_buttons[0].disabled,"event preview options give visible feedback")
	if not phone.option_buttons.is_empty(): phone.option_buttons[0].pressed.emit()
	for _frame in 2: await process_frame
	check(phone.preview_choice == 0 and int(game.life.state().decisionCount) == 1,"event preview shows a result without altering life state")
	phone._toggle()

	var red: Dictionary = {}
	for entity in game.units():
		if entity.faction == 1 and entity.kind == "worker": red = entity; break
	var start := WarData.point(red)
	var target := legal_target(game,red)
	check(not red.is_empty() and target.is_finite(),"life run has a red cell and a legal nearby move destination")
	main.hud.focus_cell(false)
	check(game.selected.size() == 1 and int(game.selected[0]) == int(red.id),"find-cell control focuses the selected red cell")
	main.world.show_command_marker(start,"guard")
	check(main.world.marker_kind == "guard","guard command uses the three-dimensional guard marker")
	main.world.show_command_marker(start,"attackmove")
	check(main.world.marker_kind == "attack","attack command uses the three-dimensional attack marker")
	main.world.show_command_marker(start,"move")
	check(main.world.marker_kind == "move","move command uses the three-dimensional move marker")
	main.world.show_command_marker(start,"build")
	check(not is_finite(main.world.marker.x),"build command does not display a command marker")
	main.world.show_command_marker(start,"retreat")
	check(not is_finite(main.world.marker.x),"stop and retreat do not display a command marker")
	game.order(red,{"kind":"guard","x":start.x,"y":start.y,"lane":int(red.vesselLane),"guardRadius":6.0})
	for _step in 10: game.update(.1)
	check(not red.orders.is_empty() and red.orders[0].kind == "guard","guard order persists until it is replaced")
	var intruder := game.spawn("virus",2,target)
	var intruder_hp := float(intruder.get("hp",0))
	for _step in 35: game.update(.1)
	check(not intruder.is_empty() and float(intruder.hp) < intruder_hp,"guarded red cell actively attacks an enemy inside its post radius")
	if target.is_finite():
		game.selected = [int(red.id)]
		game.paused = true
		game.issue("move",target)
		game.paused = false
		for _step in 80: game.update(.1)
		check(WarData.point(red).distance_to(start) > .1,"queued red-cell move executes after time resumes")
	main.queue_free()
	await process_frame
	print("LIFE INTERACTION ",failures)
	quit(0 if failures.is_empty() else 1)
