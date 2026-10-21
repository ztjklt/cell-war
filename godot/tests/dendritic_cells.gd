extends SceneTree
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,label: String) -> void:
	checks += 1
	if not value: failures.append(label); printerr("FAIL ",label)

func fresh(game: WarSimulation) -> Array:
	game.start("cell_test"); game.state.entities.clear(); game.navigation.blockers.clear()
	var source := game.spawn("dendritic_cell",1,Vector2(100,100))
	var enemy := game.spawn("spear",2,Vector2(104,100))
	game.order(enemy,{"kind":"hold"}); game.dendritic.refresh()
	return [source,enemy]

func movement_distance(game: WarSimulation,slowed: bool) -> float:
	var pair := fresh(game)
	var source: Dictionary = pair[0]
	var enemy: Dictionary = pair[1]
	if not slowed: source.hp = 0
	var before := WarData.point(enemy)
	var target := Vector2(104,104)
	enemy.path = [{"p":target,"lane":0}]; enemy.pathIndex = 0
	enemy.pathGoal = target; enemy.pathPending = false; enemy.lastTravel = game.state.time
	enemy.movementSpeed = 0.0
	game.go(enemy,target,.1)
	return WarData.point(enemy).distance_to(before)

func shot_count(game: WarSimulation,slowed: bool) -> int:
	var pair := fresh(game)
	var source: Dictionary = pair[0]
	var enemy: Dictionary = pair[1]
	enemy.x = 103.0
	# The cell-test scene deliberately freezes non-player units. Reverse the
	# factions here so the slowed shooter uses the real live combat loop.
	source.faction = 2; enemy.faction = 1
	if not slowed: source.hp = 0
	var target := game.spawn("store",2,Vector2(107,100),"building")
	target.hp = 100000.0; target.maxHp = 100000.0
	game.order(enemy,{"kind":"attack","target":target.id})
	var events: Array = []
	var receive := func(event):
		if event.kind == "projectile_spawn" and int(event.source) == int(enemy.id): events.append(event)
	game.combat_event.connect(receive)
	for i in 200: game.step(.1)
	game.combat_event.disconnect(receive)
	return events.size()

func run() -> void:
	var game := WarSimulation.new()
	var pair := fresh(game)
	var source: Dictionary = pair[0]
	var enemy: Dictionary = pair[1]
	check(WarDendriticCells.can_scan(source,game.state.time) and game.dendritic.marked(enemy,1),"stopped scanner precisely marks enemy by faction")
	check(not game.dendritic.marked(enemy,2),"enemy does not receive its own faction's detection mark")
	check(is_equal_approx(game.combat.multiplier(enemy,"moveMultiplier"),.7),"marked movement speed is seventy percent")
	check(is_equal_approx(game.combat.multiplier(enemy,"attackSpeedMultiplier"),.7),"marked attack speed is seventy percent")
	check(game.combat.multiplier(enemy,"attackMultiplier")==1,"scan does not change per-hit damage")
	var second := game.spawn("dendritic_cell",1,Vector2(101,102)); game.dendritic.refresh()
	check(is_equal_approx(game.combat.multiplier(enemy,"moveMultiplier"),.7),"overlapping scanners never stack to forty-nine percent")
	second.hp = 0; enemy.x = 108.0
	check(game.dendritic.marked(enemy,1),"exact scan radius is included")
	enemy.x = 108.01
	check(not game.dendritic.marked(enemy,1),"leaving coverage immediately removes mark")
	enemy.x = 104.0; enemy.faction = 1
	check(not game.dendritic.marked(enemy,1) and game.combat.multiplier(enemy,"moveMultiplier")==1,"friendly cells are not marked or slowed")
	enemy.faction = 2; enemy.vesselLane = 5
	check(not game.dendritic.marked(enemy,1),"projected overlapping navigation lanes are not connected by scanning")
	enemy.vesselLane = 0
	var building := game.spawn("tower",2,Vector2(110,110),"building")
	check(not game.dendritic.marked(building,1),"scan applies to enemy units rather than buildings")
	var blocker := game.spawn("store",2,Vector2(102,100),"building")
	game.navigation.blockers = [blocker]
	check(not game.dendritic.marked(enemy,1),"solid building blocks detection and slowdown")
	game.navigation.blockers.clear(); game.state.entities.erase(str(blocker.id))
	game.order(source,{"kind":"move","x":100.0,"y":104.0,"lane":0})
	check(not game.dendritic.marked(enemy,1),"moving order stops scanning immediately")
	game.order(source,{"kind":"hold"}); game.dendritic.refresh()
	check(game.dendritic.marked(enemy,1),"holding resumes scanning")
	game.combat.damage({},source,1,true,"test")
	check(not game.dendritic.marked(enemy,1),"hit reaction interrupts scanning immediately")
	game.state.time = 1.0; game.dendritic.refresh()
	check(game.dendritic.marked(enemy,1),"scan resumes after recovery")
	source.hp = 0
	check(not game.dendritic.marked(enemy,1),"scanner death removes mark and penalty immediately")
	pair = fresh(game); source = pair[0]; enemy = pair[1]
	enemy.hp = 0
	var concealed := game.spawn("herpes",2,Vector2(104,103)); concealed.burrowed = true
	game.order(concealed,{"kind":"hold"})
	var white := game.spawn("spear",1,Vector2(101,103))
	game.order(source,{"kind":"move","x":100.0,"y":104.0,"lane":0})
	check(not game.visible(concealed,1),"ordinary ally vision does not reveal a burrowed enemy")
	game.order(source,{"kind":"hold"}); game.dendritic.refresh()
	check(game.visible(concealed,1) and game.dendritic.marked(concealed,1),"scan reveals precise position of a burrowed herpes target")
	check(concealed.burrowed and is_equal_approx(game.combat.multiplier(concealed,"moveMultiplier"),.7),"mark does not force emergence and applies the same debuff")
	check(game.combat.enemy(white,10).id == concealed.id,"revealed hidden target can be acquired by a teammate")
	var view := WarWorldView.new(); view.game = game
	var camera := Camera2D.new(); camera.zoom = Vector2.ONE*64; view.camera = camera
	check(view.pick(concealed,WarData.point(concealed)),"revealed underground marker has precise picking")
	game.order(source,{"kind":"move","x":100.0,"y":104.0,"lane":0})
	check(not game.visible(concealed,1) and not view.pick(concealed,WarData.point(concealed)),"concealed target hides again after detection stops")
	view.free(); camera.free()
	pair = fresh(game); source = pair[0]; enemy = pair[1]
	check(not game.combat.fight(source,enemy,.1,true),"scanner does not attack or chase")
	game.combat.launch(source,enemy,10,{"speed":10,"ttl":1})
	check(game.state.combatProjectiles.is_empty(),"scanner cannot launch a projectile through combat API")
	game.order(source,{"kind":"attack","target":enemy.id})
	var before := WarData.point(source); game.step(.1)
	check(WarData.point(source)==before and source.orders.is_empty(),"explicit attack orders cannot turn scanner into a fighter")
	enemy.cooldown = 1.0; game.dendritic.refresh(); game.step(.1)
	check(is_equal_approx(float(enemy.cooldown),.93),"real attack cooldown progresses at seventy percent rate")
	var normal_move := movement_distance(game,false)
	var slow_move := movement_distance(game,true)
	check(normal_move > 0 and absf(slow_move-normal_move*.7) < .00001,"real route displacement is reduced to seventy percent within coordinate precision")
	var normal_shots := shot_count(game,false)
	var slow_shots := shot_count(game,true)
	check(normal_shots >= 10 and slow_shots < normal_shots,"real twenty-second attack count falls: %d -> %d" % [normal_shots,slow_shots])
	pair = fresh(game); source = pair[0]; enemy = pair[1]
	var support := game.spawn("b_cell",2,Vector2(105,102)); game.b_cells.refresh()
	check(is_equal_approx(game.combat.multiplier(enemy,"attackSpeedMultiplier"),1.4),"B-cell speed bonus and scanner penalty compose once each")
	var spec: Dictionary = WarData.spec("dendritic_cell")
	check(spec.damage==0 and not spec.has("projectile"),"dendritic role is an unarmed support cell")
	game.spawn("core",1,Vector2(118,110),"building")
	var barracks := game.spawn("barracks",1,Vector2(112,112),"building")
	game.economy.add(1,"wood",200); game.economy.add(1,"food",200)
	check(game.economy.train(barracks,"dendritic_cell"),"existing production building can train dendritic cell")
	game.economy.update(float(spec.train))
	check(game.units().filter(func(e): return e.kind=="dendritic_cell").size()==2,"training produces an actual scanner")
	var snapshot := game.snapshot()
	check(WarSave.validate(snapshot).is_empty(),"save accepts scanner and support state")
	game.restore(snapshot)
	check(game.dendritic.marked(game.entity(int(enemy.id)),1),"load reconstructs marks from living stationary scanners")
	for key in {"dcMove":16,"dcScan":6,"dcHit":12,"dcDeath":12}:
		var clip: Dictionary = WarDendriticCells.data().clips[key]
		var expected: int = {"dcMove":16,"dcScan":6,"dcHit":12,"dcDeath":12}[key]
		check(clip.durations.size()==expected and ResourceLoader.exists("res://assets/"+clip.path),"complete imported action "+key)
		check(WarDendriticCells.data().outlines[key].all(func(p): return p.size()>=3),"complete picking outlines "+key)
	var sample: Dictionary = game.entity(int(source.id)).duplicate(true)
	check(WarDendriticCells.sample(sample,10,0,false).key=="dcScan","stationary scanner plays original lamp cycle")
	check(WarDendriticCells.sample(sample,10,1,false).key=="dcMove","movement selects new sixteen-frame action")
	sample.cellHitStarted = 10.0
	check(WarDendriticCells.sample(sample,10.2,0,false).key=="dcHit","damage selects twelve-frame hit reaction")
	sample.deathTime = 10.0
	check(WarDendriticCells.sample(sample,11.439,0,true).frame==11 and WarDendriticCells.sample(sample,12,0,true).get("hidden",false),"death completes twelve frames then hides")
	check(WarCellShape.pose(sample,100,false).angle==0,"all six branches stay front-facing")
	game.paused = true; var time := float(game.state.time); game.update(.2)
	check(game.state.time==time,"pause freezes reconnaissance simulation")
	game.dispose()
	if OS.get_cmdline_user_args().has("--capture"): await capture()
	DirAccess.make_dir_recursive_absolute("res://test-output")
	var file := FileAccess.open("res://test-output/dendritic-cells.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"normalShots":normal_shots,"slowedShots":slow_shots,"normalMove":normal_move,"slowedMove":slow_move},"  "))
	print("DENDRITIC ",checks-failures.size(),"/",checks," SHOTS ",normal_shots," -> ",slow_shots)
	quit(0 if failures.is_empty() else 1)

func capture() -> void:
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main); current_scene = main; root.size = Vector2i(1440,900)
	main.set_process(false); main.set_process_unhandled_input(false); main.start("cell_test")
	var pair := fresh(main.game)
	var source: Dictionary = pair[0]; pair[1].hp = 0
	var enemy: Dictionary = main.game.spawn("virus",2,Vector2(104,100)); enemy.attackDamage = 0
	var hidden: Dictionary = main.game.spawn("herpes",2,Vector2(105,103)); hidden.burrowed = true
	main.game.order(enemy,{"kind":"hold"}); main.game.order(hidden,{"kind":"hold"})
	source.combatState = "scanning"; main.game.state.time = .65; main.game.paused = true
	main.game.dendritic.refresh(); main.game.selected.assign([int(source.id)])
	main.camera.position = Vector2(102,101); main.camera.zoom = Vector2.ONE*64; main.camera.force_update_scroll()
	var began := Time.get_ticks_msec(); var path: String = WarDendriticCells.data().clips.dcScan.path
	while main.world.textures.get_texture(path)==null and Time.get_ticks_msec()-began<10000: await process_frame
	check(main.world.textures.get_texture(path)!=null,"native renderer loads original six-frame scanner")
	check(main.game.visible(hidden,1),"native underground target is detected")
	main.hud.wheel.open(Vector2(700,450),Vector2(102,101),false)
	check(not main.hud.wheel.buttons.any(func(b): return b.action in ["attack","attackmove"]),"scanner-only command menu has no attack option")
	main.hud.wheel.close()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://test-output")
	root.get_texture().get_image().save_png("res://test-output/dendritic-native.png")
	var owned: WarSimulation = main.game
	main.queue_free(); await process_frame; owned.dispose()
