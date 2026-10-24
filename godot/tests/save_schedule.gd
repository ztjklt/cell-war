extends SceneTree
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok: failures.append(message); printerr("FAIL ",message)

func run() -> void:
	WarSave.directory = "user://test-saves/save-schedule-"+str(Time.get_ticks_usec())
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main); current_scene = main; main.set_process(false)
	main._process(30)
	check(WarSaveSession.records().is_empty(),"cover placeholder never autosaves")
	main.new_run("life"); main.game.paused = true
	check(main.game.selected.size() == 1 and main.game.entity(main.game.selected[0]).kind == "worker","life entry retains original starter")
	check(main.overview_active,"life new game retains overview")
	var first: String = main.saves.active_path
	for i in 10: main.game.step(.1)
	main._process(14)
	check(is_zero_approx(WarSaveSession.document(first).snapshot.time),"no premature periodic save")
	main._process(1)
	check(is_equal_approx(WarSaveSession.document(first).snapshot.time,1.0),"fifteen real seconds writes current profile while paused")
	check(not FileAccess.file_exists(WarSave.path(0)) and not FileAccess.file_exists(WarSave.life_auto_path()),"new session does not overwrite either legacy auto file")
	main.new_run("cell_test"); main.game.paused = true
	var second: String = main.saves.active_path
	main.saves.since_save = 14.9
	main.continue_run(first)
	check(main.saves.since_save == 0.0 and main.saves.active_path == first,"loading resets autosave clock to selected run")
	main.game.paused = true; main.game.step(.1)
	main._process(15)
	check(is_equal_approx(WarSaveSession.document(first).snapshot.time,1.1) and is_zero_approx(WarSaveSession.document(second).snapshot.time),"autosave writes only continued record")
	main.hud.return_home()
	var saved: String = FileAccess.get_file_as_string(first)
	main._process(40)
	check(saved == FileAccess.get_file_as_string(first),"cover does not rewrite cleared selection or menu pause into record")
	main.continue_run(first)
	main.game.groups[0] = main.game.selected.duplicate()
	var selected: Array = main.game.selected.duplicate()
	var groups: Array = main.game.groups.duplicate(true)
	var before: Dictionary = main.game.snapshot()
	# Existing record remains writable; allocating a new runs directory fails.
	var original_directory := WarSave.directory
	var blocker := FileAccess.open(original_directory+"/blocked",FileAccess.WRITE); blocker.store_string("file"); blocker.close()
	WarSave.directory = original_directory+"/blocked"
	main.new_run("lung_defense")
	check(main.game.selected == selected and main.game.groups == groups and main.game.snapshot() == before and main.saves.active_path == first,"failed new record preserves current world, selection and groups")
	WarSave.directory = original_directory
	main.free()
	print("SAVE_SCHEDULE ",checks-failures.size(),"/",checks)
	quit(0 if failures.is_empty() else 1)
