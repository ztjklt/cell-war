extends SceneTree
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game := WarSimulation.new()
	game.start("systemic")
	var shots := [0,0,0]
	game.combat_event.connect(func(event):
		if event.kind == "projectile_spawn": shots[0] += 1
		if event.kind == "damage": shots[1] += 1
		if event.kind == "death": shots[2] += 1)
	var began := Time.get_ticks_msec()
	for i in 1500:
		game.navigation.update(10000)
		game.step(.1)
		if i % 100 == 0: print("STEP ",i," events ",shots," delivered ",game.state.systemicBattle.delivered)
	var q: Dictionary = game.state.systemicBattle
	var report := {"seconds":game.state.time,"milliseconds":Time.get_ticks_msec()-began,
		"shots":shots[0],"damageEvents":shots[1],"deaths":shots[2],"oxygen":q.oxygen,
		"glucose":q.glucose,"courier":q.get("courierState",""),"delivered":q.delivered}
	print(report)
	DirAccess.make_dir_recursive_absolute("res://test-output")
	var file := FileAccess.open("res://test-output/encounter.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	game.dispose()
	quit(0 if shots[0] > 0 and shots[1] > 0 and float(q.delivered) > 0 else 1)
