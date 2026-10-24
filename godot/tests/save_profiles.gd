extends SceneTree
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool,text: String) -> void:
	checks += 1
	if not ok: failures.append(text); printerr("FAIL ",text)

func run() -> void:
	WarSave.directory = "user://test-saves/profiles-"+str(Time.get_ticks_usec())
	check(ResourceLoader.exists("res://scripts/save_session.gd"),"independent save session exists")
	if not failures.is_empty(): quit(1); return
	var session = load("res://scripts/save_session.gd").new()
	var game := WarSimulation.new()
	game.start("lung_defense",73)
	check(session.create(game,"第一档") == OK,"create first profile")
	var first: String = session.active_path
	for i in 10: game.step(.1)
	var elapsed: float = game.state.lungDefense.elapsed
	check(session.save(game,{"zoom":8.0}) == OK,"save actual simulation progress")
	game.start("lung_defense",74)
	check(session.create(game,"第二档") == OK and session.active_path != first,"new profile does not overwrite old profile")
	var second: String = session.active_path
	check(session.records().size() == 2,"both saves appear in list")
	var restarted = load("res://scripts/save_session.gd").new()
	check(restarted.resume(game,first) == OK and is_equal_approx(game.state.lungDefense.elapsed,elapsed),"new process session restores preparation progress")
	check(restarted.view.get("zoom",0) == 8.0 and restarted.title == "第一档","view metadata and profile name survive restart")
	game.step(.1)
	check(restarted.save(game) == OK,"continued session saves into its own file")
	check(session.resume(game,second) == OK and is_zero_approx(game.state.time),"second save remains untouched")
	var corrupt := WarSave.directory+"/runs/corrupt.json"
	var f := FileAccess.open(corrupt,FileAccess.WRITE); f.store_string("broken"); f.close()
	var before := game.snapshot()
	check(session.resume(game,corrupt) != OK and game.snapshot() == before and session.active_path == second,"corrupt save cannot replace current session")
	check(session.records().any(func(row): return row.path == corrupt and not row.valid),"corrupt save is shown as unavailable")
	check(WarSave.write(game,2) == OK,"legacy slot can still be written")
	var legacy: String = FileAccess.get_file_as_string(WarSave.path(2))
	check(session.resume(game,WarSave.path(2)) == OK and session.active_path != WarSave.path(2),"legacy save migrates to independent profile")
	check(FileAccess.get_file_as_string(WarSave.path(2)) == legacy,"legacy original is preserved")
	var invalid := WarSave.directory+"/runs/invalid-defense.json"
	var document := WarSaveSession.document(session.active_path)
	document.snapshot.lungDefense = {"phase":"preparing","elapsed":"broken"}
	f = FileAccess.open(invalid,FileAccess.WRITE); f.store_string(JSON.stringify(document)); f.close()
	before = game.snapshot()
	check(session.resume(game,invalid) != OK and game.snapshot() == before,"incomplete defense metadata is rejected before restore")
	var good_path: String = session.active_path
	session.active_path = WarSave.directory+"/blocked/record.json"
	f = FileAccess.open(WarSave.directory+"/blocked",FileAccess.WRITE); f.store_string("file"); f.close()
	check(session.save(game) != OK,"disk write failure is reported")
	check(FileAccess.file_exists(good_path),"write failure preserves last valid record")
	game.dispose()
	print("SAVE_PROFILES ",checks-failures.size(),"/",checks)
	quit(0 if failures.is_empty() else 1)
