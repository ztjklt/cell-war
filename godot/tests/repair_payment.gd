extends SceneTree
## Controlled damaged-building fixtures; real queued commands and simulation.
var checks := 0
var failures: Array[String] = []
var records: Array = []

func _initialize() -> void: call_deferred("run")

func check(value: bool,label: String) -> void:
	checks += 1
	if not value: failures.append(label); printerr("FAIL ",label)

func run_case(damage: float,label: String) -> void:
	var game := WarSimulation.new(); game.start("cell_test",73)
	game.state.entities.clear(); game.navigation.blockers.clear()
	var building := game.spawn("store",1,Vector2(110,110),"building")
	var left := game.spawn("worker",1,Vector2(108,110))
	var right := game.spawn("worker",1,Vector2(112,110))
	building.hp -= damage
	var before := game.economy.stock(1,"wood")
	for worker in [left,right]:
		game.submit_player({"action":"unit_order","unit":worker.id,"order":{"kind":"repair","target":building.id}})
		game.submit_player({"action":"unit_order","unit":worker.id,"order":{"kind":"move","x":worker.x,"y":114,"lane":0},"append":true})
	for i in 50:
		game.navigation.update(10000); game.update(.1)
		if left.orders.is_empty() and right.orders.is_empty(): break
	check(is_equal_approx(building.hp,building.maxHp),label+": actual repair restores only missing health")
	var spent := before-game.economy.stock(1,"wood")
	check(is_equal_approx(spent,ceilf(damage/20.0)),label+": shared repair pays only for effective health-restoring ticks")
	check(float(left.y) > 111 and float(right.y) > 111,label+": both workers continue their appended movement after completion")
	check(WarSave.validate(game.snapshot()).is_empty(),label+": resulting inventory and orders remain saveable")
	records.append({"label":label,"initialDamage":damage,"spent":spent,"hp":building.hp,"maxHp":building.maxHp})
	game.dispose()

func run() -> void:
	run_case(10,"two workers finish the same small repair")
	run_case(40,"two workers share two useful repair ticks")
	run_case(0,"stale queued repair on a full-health building")
	DirAccess.make_dir_recursive_absolute("res://test-output/repair-payment")
	var name := "baseline" if OS.get_cmdline_user_args().has("--baseline") else "checks"
	FileAccess.open("res://test-output/repair-payment/"+name+".json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"records":records,"scope":"explicit two-worker and damage fixtures; real queue, movement and inventory; no added resources"},"  "))
	print("REPAIR PAYMENT ",checks-failures.size(),"/",checks)
	quit(0 if failures.is_empty() else 1)
