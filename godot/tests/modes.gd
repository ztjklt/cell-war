extends SceneTree
var errors: Array = []
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for mode in ["fullbody","systemic","lung_skirmish","nasal_01","trachea_01","lungs_01","sandbox","organ_trial","gastric_trial","cell_test"]:
		var game := WarSimulation.new()
		var started := Time.get_ticks_msec()
		game.start(mode)
		for i in 30:
			game.navigation.update(10000)
			game.step(.1)
		var error := WarSave.validate(game.snapshot())
		print(mode," cells=",game.units().size()," ms=",Time.get_ticks_msec()-started," save=",error)
		if not error.is_empty(): errors.append({"mode":mode,"error":error})
		if mode == "cell_test":
			game.scenarios.cell_action("oxygen")
			var red := game.entity(int(game.state.cellTest.red))
			if red.cargo.get("oxygen",0) != 8: errors.append({"mode":mode,"error":"oxygen animation cargo"})
			game.scenarios.cell_action("shoot")
		if mode == "sandbox":
			var fa: Dictionary = game.state.factions[0]
			var core: Dictionary = {}
			for e in game.entities():
				if e.kind == "core" and e.faction == 1: core = e; break
			if core.is_empty() or not game.economy.train(core,"worker"): errors.append({"mode":mode,"error":"core production"})
		game.dispose()
	print("MODE ERRORS ",errors)
	DirAccess.make_dir_recursive_absolute("res://test-output")
	var file := FileAccess.open("res://test-output/modes.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"modes":10,"errors":errors},"  "))
	quit(0 if errors.is_empty() else 1)
