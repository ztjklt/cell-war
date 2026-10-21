extends SceneTree
var failures: Array[String] = []
var checks := 0

func check(value: bool,message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("FAIL ",message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for fixture in WarData.read("progress").oracle:
		var state: Dictionary = fixture.input.duplicate(true)
		if state.entities is Array:
			var entities: Dictionary = {}
			for e in state.entities: entities[str(int(e.id))] = e
			state.entities = entities
		WarProgress.advance(state)
		check(state.outcome == fixture.outcome and int(state.tutorial) == int(fixture.tutorial),"original tutorial/outcome "+fixture.label)
		for i in 3:
			check(state.factions[i].lost == fixture.factions[i].lost and state.factions[i].conquered == fixture.factions[i].conquered,"original faction liveness "+fixture.label)
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main: Node2D = scene.instantiate(); scene = null
	root.add_child(main); current_scene = main
	main.start("sandbox"); main.game.paused = true
	await process_frame
	main.hud._action("worker")
	for i in 10: main.game.step(.1)
	check(int(main.game.state.tutorial) == 2,"real selection advances sandbox tutorial")
	main.hud._process(.2)
	check(main.hud.progress_panel.visible and main.hud.tutorial_text.text == WarData.read("progress").tutorials[1],"original tutorial text and progress are visible")
	var worker: Dictionary = main.game.entity(main.game.selected[0])
	var core: Dictionary = {}
	for e in main.game.entities():
		if e.kind == "core" and e.faction == 1: core = e; break
	worker.x = core.x; worker.y = core.y; worker.cargo = {"wood":3}; worker.delivering = true
	main.game.economy.harvest(worker,{},.1)
	check(float(main.game.state.get("delivered",0)) == 3,"actual delivery records original tutorial metric")
	main.game.state.tutorial = 5
	main.game.state.trained = 1
	for i in 10: main.game.step(.1)
	check(int(main.game.state.tutorial) == 6,"production milestone advances tutorial")
	main.game.state.entities = {}
	for i in 10: main.game.step(.1)
	check(main.game.state.outcome == "defeat","sandbox destruction reaches original defeat condition")
	var time: float = main.game.state.time
	main.game.step(.1)
	check(main.game.state.time == time,"defeat freezes sandbox simulation")
	main.hud._process(.2)
	check(main.hud.menu.visible and main.hud.outcome_shown == "defeat","defeat opens original recovery modal")
	main.hud.close_menu(); main.hud._process(.2)
	check(not main.hud.menu.visible,"dismissed outcome does not reopen every frame")
	var file := FileAccess.open("res://test-output/progress.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"oracle":"original Simulation.lua sandbox outcome/tutorial block; native integration"},"  "))
	print("PROGRESS ",checks-failures.size(),"/",checks)
	main.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
