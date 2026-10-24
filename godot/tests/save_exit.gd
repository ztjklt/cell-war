extends SceneTree
## Run in two separate processes with the same --case id; writer closes the Window.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var case_id := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="): case_id = arg.trim_prefix("--case=")
	if case_id.is_empty(): printerr("Missing isolated --case id"); quit(1); return
	WarSave.directory = "user://test-saves/exit-"+case_id
	var receipt_path := WarSave.directory+"/receipt.json"
	if "--read" in OS.get_cmdline_user_args():
		var receipt: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(receipt_path))
		var game := WarSimulation.new()
		var session := WarSaveSession.new()
		var result := session.resume(game,str(receipt.path))
		var expected_selected: Array[int] = []; expected_selected.assign(receipt.selected)
		var ok: bool = result == OK and is_equal_approx(game.state.time,float(receipt.time)) and game.selected == expected_selected and game.state.commands.size() == 1 and game.state.commands[0].kind == "guard"
		if not ok: printerr("EXIT DIAGNOSTIC ", {"result":result,"saved_time":game.state.get("time"),"expected":receipt,"selected":game.selected,"commands":game.state.get("commands")})
		print("SAVE_EXIT_RESTART ","PASS" if ok else "FAIL")
		game.dispose(); quit(0 if ok else 1); return
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main); current_scene = main; main.set_process(false)
	main.new_run("lung_defense"); main.game.paused = true
	for i in 53: main.game.step(.1)
	main.game.issue("guard",main.game.scenarios.home())
	var receipt := {"path":main.saves.active_path,"time":main.game.state.time,"selected":main.game.selected}
	var file := FileAccess.open(receipt_path,FileAccess.WRITE); file.store_string(JSON.stringify(receipt)); file.close()
	print("SAVE_EXIT_WINDOW_CLOSE at ",main.game.state.time)
	root.close_requested.emit()
