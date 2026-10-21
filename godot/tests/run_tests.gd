extends SceneTree
var failures: Array[String] = []
var checks := 0

func check(condition: bool,name: String) -> void:
	checks += 1
	if not condition:
		failures.append(name)
		printerr("FAIL: "+name)
	else:
		print("PASS: "+name)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	WarSave.directory = "user://test-saves"
	var game := WarSimulation.new()
	game.start()
	check(game.units().size() >= 2,"fullbody starts with live cells")
	check(game.navigation.organs.size() == 12,"twelve authored organs")
	check(game.state.resources.size() == 5,"five real harvesting sites")
	check(WarData.config().Data.resources == ["wood","oxygen","food"],"three active resource identities")
	var worker: Dictionary = {}
	for e in game.units():
		if e.kind == "worker" and e.faction == 1: worker = e; break
	check(not worker.is_empty(),"red cell exists")
	check(game.navigation.organ_at(WarData.point(worker)) == "small_intestine","starter belongs to small intestine")
	game.combat.apply_status(worker,"slow",{"duration":.2})
	check(is_equal_approx(game.combat.multiplier(worker,"moveMultiplier"),.6),"slow multiplier")
	game.step(.1)
	check(worker.statuses.has("slow"),"status active before expiry")
	game.step(.11)
	check(not worker.statuses.has("slow"),"status expires in simulation time")
	var start := WarData.point(worker)
	game.paused = true
	var time := float(game.state.time)
	game.update(.5)
	check(game.state.time == time,"pause freezes simulation")
	game.paused = false
	check(game.navigation.clear_segment(start,start,0,"worker"),"starter has exact geometric clearance")
	check(not game.navigation.clear_segment(start,Vector2.ZERO,0,"worker"),"organ wall rejects segment")
	var g := game.navigation.grid("small_intestine","siege")
	var a := g.nearest(start)
	check(a >= 0 and g.valid[a] != 0,"grid start attaches to exact position")
	var destination := g.position_of(a)
	for i in range(a+1,mini(a+1000,g.valid.size())):
		if g.valid[i] and g.components[i] == g.components[a]: destination = g.position_of(i); break
	var ready := false
	var result: Array = []
	var request := game.navigation.request(worker,destination,0)
	var receive := func(token,path,_reason):
		if token == request: result.assign(path)
	game.navigation.path_ready.connect(receive)
	for i in 2000:
		game.navigation.update(10000)
		if not result.is_empty(): ready = true; break
	check(ready,"native path request completes")
	if ready:
		check(result[-1].p.distance_to(destination) < .00001,"route preserves exact destination")
	game.navigation.path_ready.disconnect(receive)
	var bad := game.snapshot()
	bad.entities[str(worker.id)].hp = -1
	check(not WarSave.validate(bad).is_empty(),"corrupt health rejected")
	check(WarSave.validate(game.snapshot()).is_empty(),"live snapshot validates")
	check(WarSave.write(game,3) == OK,"atomic native save")
	worker.hp = 1
	check(WarSave.read_slot(game,3) == OK,"native load")
	check(game.entity(worker.id).hp > 1,"save restores state")
	DirAccess.remove_absolute(WarSave.path(3))
	game.start("systemic")
	var q: Dictionary = game.state.systemicBattle
	check(q.players.size() == 3 and q.enemies.size() == 2,"systemic authored encounter")
	var oxygen := float(q.oxygen)
	game.scenarios.before_step(.1)
	check(float(q.produced) > 0 and float(q.oxygen) >= 0,"lung produces oxygen without negative stock")
	check(game.scenarios.isolate(true),"isolate both lung gates")
	for id in q.gates: check(game.navigation.gates[id].isolated,"isolation gate "+id)
	check(game.scenarios.isolate(false),"reopen lung gates")
	for id in q.players:
		var e := game.entity(int(id))
		if e.has("combatReserve"):
			e.combatReserve = 0
			check(game.scenarios.shot(e) == float(WarData.config().SystemicConfig.exhaustedCooldown),"exhaustion changes cooldown")
	game.start("trachea_01")
	check(game.is_campaign() and game.navigation.campaign.id == "trachea_01","campaign changes map")
	check(game.scenarios.reinforce(),"campaign reinforcement request")
	check(not game.scenarios.reinforce(),"reinforcement cooldown enforced")
	var old := float(game.state.campaign.event.elapsed)
	check(game.scenarios.skip_wave(),"skip waiting for next wave")
	check(float(game.state.campaign.event.elapsed) >= old,"skip advances event clock")
	var home := game.scenarios.home()
	check(game.navigation.campaign_clear(home,home),"campaign home is walkable")
	check(not game.navigation.campaign_clear(home,Vector2.ZERO),"campaign walls block movement")
	game.start("lungs_01")
	check(game.state.campaign.map_id == "lungs_01","lung campaign start")
	game.start("nasal_01")
	check(game.state.campaign.map_id == "nasal_01","nasal campaign start")
	game.start("fullbody")
	var gate: Dictionary = game.navigation.gates.values()[0]
	game.combat.damage({"id":9000,"kind":"virus","faction":2},gate,float(gate.hp),true)
	check(gate.breached and int(gate.faction) == 0,"pathogen captures a vascular gate")
	game.combat.damage({"id":9001,"kind":"spear","faction":1},gate,float(gate.hp),true)
	check(not gate.breached and int(gate.faction) == 1,"defender recaptures a vascular gate")
	var corrupt := game.snapshot()
	corrupt.combatProjectiles = [{"sourceKind":"virus","x":1,"y":1,"dx":0,"dy":0,"speed":1,"ttl":1,"damage":1}]
	check(not WarSave.validate(corrupt).is_empty(),"zero projectile direction rejected")
	game.start("trachea_01")
	var count := game.units().size()
	var stock := game.economy.stock(1,"wood")
	game.scenarios.change_campaign("lungs_01")
	check(game.units().size() == count,"campaign transition carries surviving squad")
	check(game.economy.stock(1,"wood") == stock,"campaign transition carries economy")
	game.start("cell_test")
	game.scenarios.cell_action("oxygen")
	check(game.entity(int(game.state.cellTest.red)).cargo.oxygen == 8,"oxygen carry animation state")
	var virus := game.entity(int(game.state.cellTest.virus))
	var virus_start := WarData.point(virus)
	for i in 20:
		game.navigation.update(10000)
		game.step(.1)
	check(WarData.point(virus) == virus_start,"animation test target remains stationary")
	var red_id := int(game.state.cellTest.red)
	game.selected.assign([red_id])
	for resource in WarData.spec("store").cost: game.economy.add(1,resource,float(WarData.spec("store").cost[resource]))
	game.paused = true
	var entity_count := game.entities().size()
	game.submit_player({"action":"place","building":"store","x":110.2,"y":99.8})
	game.update(.5)
	check(game.entities().size() == entity_count,"paused construction does not spawn a building")
	game.step(.1)
	var placed: Dictionary = {}
	for e in game.entities():
		if e.kind == "store" and int(e.id) != int(game.state.cellTest.building): placed = e
	check(not placed.is_empty(),"queued construction executes on resume step")
	if not placed.is_empty():
		check(WarData.point(placed) == Vector2(110,99),"construction snaps to original even-size grid")
		check(is_equal_approx(float(placed.hp),maxf(30,float(placed.maxHp)*.15)),"construction starts with original partial health")
	check(absf(WarResourceGeneration.hash_value(1,1,73)-0.6993902701416007) < 1e-12,"sandbox hash matches original Lua")
	check(absf(WarResourceGeneration.hash_value(2047,4095,2147483647)-0.3135248596377321) < 1e-12,"sandbox hash preserves integer overflow rules")
	game.start("sandbox",73)
	for i in 400:
		game.resource_generation.update()
		if not game.state.nativeGeneratedChunks.is_empty() and game.resource_generation.pending.is_empty(): break
	check(not game.state.resources.is_empty(),"sandbox generates harvesting sites at runtime")
	check(not game.state.nativeGeneratedChunks.is_empty(),"sandbox records generated chunks for saves")
	print("RESULT %d/%d" % [checks-failures.size(),checks])
	var report := {"passed":checks-failures.size(),"total":checks,"failures":failures,"engine":Engine.get_version_info().string}
	DirAccess.make_dir_recursive_absolute("res://test-output")
	var file := FileAccess.open("res://test-output/rules.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	# Break service back references before exiting the headless scene tree.
	game.dispose()
	quit(0 if failures.is_empty() else 1)
