extends SceneTree
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,label: String) -> void:
	checks += 1
	if not value: failures.append(label); printerr("FAIL ",label)

func fresh(game: WarSimulation) -> Array:
	game.start("cell_test")
	game.state.entities.clear(); game.navigation.blockers.clear()
	var source:=game.spawn("b_cell",1,Vector2(100,100))
	var ally:=game.spawn("spear",1,Vector2(104,100))
	game.b_cells.refresh()
	return [source,ally]

func shot_count(game: WarSimulation,boosted: bool) -> int:
	var pair:=fresh(game)
	var support: Dictionary = pair[0]
	var ally: Dictionary = pair[1]
	if not boosted: support.hp=0
	var enemy:=game.spawn("virus",2,Vector2(106,100))
	enemy.hp=10000.0; enemy.maxHp=10000.0; enemy.attackDamage=0.0
	game.order(ally,{"kind":"hold"}); game.order(enemy,{"kind":"hold"})
	var events: Array = []
	var receive:=func(event):
		if event.kind=="projectile_spawn" and int(event.source)==int(ally.id): events.append(event)
	game.combat_event.connect(receive)
	for i in 60: game.step(.1)
	game.combat_event.disconnect(receive)
	return events.size()

func run() -> void:
	var game:=WarSimulation.new()
	var pair:=fresh(game)
	var source: Dictionary = pair[0]
	var ally: Dictionary = pair[1]
	check(WarBCells.can_emit(source) and game.b_cells.speed_multiplier(ally)==2,"stationary flower shaking doubles friendly attack rate")
	check(game.combat.multiplier(ally,"attackMultiplier")==1,"flower aura does not double per-hit damage")
	var second:=game.spawn("b_cell",1,Vector2(101,102)); game.b_cells.refresh()
	check(game.b_cells.speed_multiplier(ally)==2,"overlapping B cells stay capped at twice attack speed")
	ally.x=106.0
	check(game.b_cells.speed_multiplier(ally)==2,"exact radius edge is included")
	second.hp=0; ally.x=106.01
	check(game.b_cells.speed_multiplier(ally)==1,"leaving radius removes benefit immediately")
	ally.x=104.0; ally.faction=2
	check(game.b_cells.speed_multiplier(ally)==1,"hostile unit receives no benefit")
	ally.faction=1; ally.vesselLane=5
	check(game.b_cells.speed_multiplier(ally)==1,"overlapping projection on another lane receives no benefit")
	ally.vesselLane=0
	var building:=game.spawn("tower",1,Vector2(104,102),"building")
	check(game.b_cells.speed_multiplier(building)==1 and game.b_cells.speed_multiplier(source)==1,"buildings and the non-attacking B cell are not attack recipients")
	game.order(source,{"kind":"move","x":103.0,"y":104.0,"lane":0})
	check(not WarBCells.can_emit(source) and game.b_cells.speed_multiplier(ally)==1,"move command immediately stops flower support")
	game.order(source,{"kind":"hold"})
	game.b_cells.refresh()
	check(game.b_cells.speed_multiplier(ally)==2,"holding position resumes support")
	game.combat.damage({},source,1000,true,"test")
	check(game.b_cells.speed_multiplier(ally)==1,"provider death immediately removes benefit")
	pair=fresh(game); source=pair[0]; ally=pair[1]
	var blocker:=game.spawn("store",2,Vector2(102,100),"building")
	game.navigation.blockers=[blocker]
	check(game.b_cells.speed_multiplier(ally)==1,"building blocks support through its footprint")
	pair=fresh(game); source=pair[0]; ally=pair[1]
	var enemy:=game.spawn("virus",2,Vector2(103,103))
	enemy.attackDamage=0.0
	ally.attackDamage=0.0 # Isolate the support cell from its armed teammate's damage.
	var hp:=float(enemy.hp)
	check(not game.combat.fight(source,enemy,.1,true),"support B cell refuses both attack and chase")
	game.combat.launch(source,enemy,100,{"speed":10,"ttl":1})
	check(game.state.combatProjectiles.is_empty() and enemy.hp==hp,"B cell cannot launch a projectile even through combat API")
	var start:=WarData.point(source)
	game.order(source,{"kind":"attack","target":enemy.id})
	for i in 10: game.step(.1)
	check(WarData.point(source)==start and not source.has("shotTime") and enemy.hp==hp,"explicit attack order never enables B cell firing or pursuit")
	game.state.time=10.0; ally.cooldown=1.0; ally.orders=[{"kind":"hold"}]
	game.b_cells.refresh(); game.step(.1)
	check(is_equal_approx(ally.cooldown,.8),"real cooldown progresses twice as fast inside aura")
	check(source.combatState=="buff","standing B cell uses flower-shaking state despite nearby enemies")
	var normal:=shot_count(game,false)
	var boosted:=shot_count(game,true)
	check(normal>0 and boosted==normal*2,"six-second real projectile count doubles: %d -> %d"%[normal,boosted])
	pair=fresh(game); source=pair[0]; ally=pair[1]
	enemy=game.spawn("virus",2,Vector2(106,100))
	game.combat.fight(ally,enemy,.1,false)
	check(is_equal_approx(float(ally.cellShot.releaseAt)-float(ally.shotTime),float(WarData.spec("spear").projectile.windup)/2),"attack windup follows doubled cadence")
	game.state.time=.35
	var view:=WarWorldView.new(); view.game=game
	var fast_frame:=int(view.animation(ally,false).frame)
	var slow:=ally.duplicate(true); slow.shotSpeed=1.0
	check(fast_frame>int(view.animation(slow,false).frame),"white-cell firing animation advances at boosted rate")
	view.free()
	pair=fresh(game); source=pair[0]; ally=pair[1]
	var spec: Dictionary = WarData.spec("b_cell")
	check(spec.damage==0 and not spec.has("projectile") and WarData.config().Data.unitOrder.has("b_cell"),"B cell is a trainable support identity without weapon data")
	game.economy.add(1,"wood",200); game.economy.add(1,"food",200)
	game.spawn("core",1,Vector2(118,110),"building")
	var barracks:=game.spawn("barracks",1,Vector2(112,112),"building")
	check(game.economy.train(barracks,"b_cell"),"existing white-cell production building can queue B cell")
	game.economy.update(float(spec.train))
	check(game.units().filter(func(e): return e.kind=="b_cell").size()==2,"production completes a real B cell")
	var snapshot:=game.snapshot()
	check(WarSave.validate(snapshot).is_empty(),"save schema accepts B cell and production state")
	game.restore(snapshot)
	check(game.b_cells.speed_multiplier(game.entity(int(ally.id)))==2,"load reconstructs support from living stationary providers")
	var expected_counts := {"bMove":16,"bBuff":6,"bDeath":12}
	for key in expected_counts:
		var clip: Dictionary = WarBCells.data().clips[key]
		check(clip.durations.size()==expected_counts[key] and ResourceLoader.exists("res://assets/"+clip.path),"current imported frame count in "+key)
		check(WarBCells.data().outlines[key].all(func(points): return points.size()>=3),"complete painted picking contours in "+key)
	var e: Dictionary = game.entity(int(source.id)).duplicate(true)
	check(WarBCells.sample(e,10,0,false).key=="bBuff","idle loops flower-shaking")
	check(WarBCells.sample(e,.899-int(e.id)*.071,0,false).frame==5,"original six-frame loop reaches final source frame")
	check(WarCellShape.normalized(e,"bBuff",999,"outline").size()>=3,"original six-frame picking clamps to its own frame count")
	check(WarBCells.sample(e,10,1,false).key=="bMove","movement selects waddle")
	e.deathTime=10.0
	check(WarBCells.sample(e,11.439,0,true).frame==11,"twelve-frame death reaches final fallen pose")
	check(WarBCells.sample(e,10.5,0,true).key=="bDeath" and WarBCells.sample(e,12,0,true).get("hidden",false),"death is one-shot and never returns to shaking")
	check(WarCellShape.pose(e,100,false).angle==0,"B cell stays front-facing")
	game.paused=true; var before:=float(game.state.time); game.update(.2)
	check(game.state.time==before,"pause freezes support simulation time")
	game.dispose()
	if OS.get_cmdline_user_args().has("--capture"):
		var main: Node2D = load("res://scenes/main.tscn").instantiate()
		root.add_child(main); current_scene=main; root.size=Vector2i(1440,900)
		main.set_process(false); main.set_process_unhandled_input(false); main.start("cell_test")
		var cells:=fresh(main.game)
		var b: Dictionary = cells[0]; var white: Dictionary = cells[1]
		main.game.state.time=5.0; main.game.paused=true; main.game.b_cells.refresh()
		white.shotTime=4.75; white.shotSpeed=2.0
		main.game.selected.assign([int(b.id)])
		main.camera.position=Vector2(102,100); main.camera.zoom=Vector2.ONE*96; main.camera.force_update_scroll()
		var began:=Time.get_ticks_msec(); var path: String = WarBCells.data().clips.bBuff.path
		while main.world.textures.get_texture(path)==null and Time.get_ticks_msec()-began<10000: await process_frame
		check(main.world.textures.get_texture(path)!=null,"native renderer loads flower animation")
		main.hud.wheel.open(Vector2(700,450),Vector2(102,100),false)
		check(not main.hud.wheel.buttons.any(func(button): return button.action in ["attack","attackmove"]),"B-only command menu has no attack option")
		main.hud.wheel.close()
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://test-output")
		root.get_texture().get_image().save_png("res://test-output/b-cell-native.png")
		var owned: WarSimulation=main.game
		main.queue_free(); await process_frame; owned.dispose()
	DirAccess.make_dir_recursive_absolute("res://test-output")
	var file:=FileAccess.open("res://test-output/b-cells.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"normalShots":normal,"boostedShots":boosted},"  "))
	print("B_CELLS ",checks-failures.size(),"/",checks," SHOTS ",normal," -> ",boosted)
	quit(0 if failures.is_empty() else 1)
