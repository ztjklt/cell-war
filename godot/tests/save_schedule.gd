extends SceneTree
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,description: String) -> void:
	if not value: failures.append(description); printerr("FAIL ",description)

func run() -> void:
	WarSave.directory = "user://test-saves/save-schedule"
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main); current_scene = main
	main.set_process(false)
	main.start("life"); main.game.paused = true
	check(main.game.selected.size() == 1 and main.game.entity(main.game.selected[0]).kind == "worker","life selects its starting red cell")
	check(main.overview_active,"new life retains the whole-body starting camera")
	main.game.state.time = 10.0
	check(WarSave.write(main.game,1) == OK,"isolated early life save writes")
	main.autosave_at = 10800.0
	main.game.state.time = 10000.0
	check(WarSave.read_slot(main.game,1) == OK and main.autosave_at == 180.0,"loading an early life save resets a later run's autosave deadline")
	main.game.state.time = 180.0
	main._process(0)
	check(FileAccess.file_exists(WarSave.life_auto_path()) and main.autosave_at == 360.0,"loaded life writes to its independent auto slot on schedule")
	main.start("cell_test"); main.game.paused = true
	main.game.state.time = 370.0
	check(WarSave.write(main.game,2) == OK,"isolated legacy save writes")
	main.autosave_at = 180.0
	check(WarSave.read_slot(main.game,2) == OK and main.autosave_at == 720.0,"legacy load schedules its own six-minute period")
	var file := FileAccess.open("res://test-output/bug-audit-20261021/save-schedule.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":7,"failures":failures},"  "))
	print("SAVE SCHEDULE ",7-failures.size(),"/7")
	main.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
