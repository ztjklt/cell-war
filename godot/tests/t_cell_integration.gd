extends SceneTree
var checks := 0
var failures: Array[String] = []
var events: Array = []
var report := {}

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,label: String) -> void:
	checks += 1
	if not value: failures.append(label); printerr("FAIL ",label)

func frame(game: WarSimulation,seconds: float) -> void:
	for i in int(round(seconds/.1)):
		game.navigation.update(15000); game.update(.1)

func fresh(mode := "cell_test") -> WarSimulation:
	var game := WarSimulation.new(); game.start(mode); game.paused = false
	game.state.entities.clear(); game.navigation.blockers.clear()
	game.state.influenzaColonies = {"version":1,"groups":{}}
	game.economy.add(1,"wood",1000); game.economy.add(1,"food",1000); game.economy.add(1,"oxygen",1000)
	game.combat_event.connect(func(event): events.append(event))
	return game

func actor(game: WarSimulation,p := Vector2(100,100)) -> Dictionary:
	return game.spawn("t_cell",1,p)

func count(kind: String,start := 0) -> int:
	return events.slice(start).filter(func(e): return e.kind==kind).size()

func run() -> void:
	var game := fresh(); var source := actor(game)
	var barracks := game.spawn("barracks",1,Vector2(115,110),"building"); game.spawn("core",1,Vector2(125,110),"building")
	game.state.factions[0].tier = 2
	var stock := {"wood":game.economy.stock(1,"wood"),"food":game.economy.stock(1,"food"),"oxygen":game.economy.stock(1,"oxygen")}
	game.submit_player({"action":"train","target":barracks.id,"unit":"t_cell"}); frame(game,22.2)
	check(game.units().filter(func(e):return e.kind=="t_cell").size()==2 and barracks.queue.is_empty(),"real tier-two barracks produces a T cell after twenty-two seconds")
	check(game.economy.stock(1,"wood")==stock.wood-25 and game.economy.stock(1,"food")==stock.food-20 and game.economy.stock(1,"oxygen")==stock.oxygen-5,"actual T production pays protein, glucose and oxygen once")
	check(WarData.spec("t_cell").hp==105 and WarData.spec("t_cell").pop==2,"registered hp and population match first defaults")
	game.dispose()

	game = fresh(); source = actor(game)
	game.selected.assign([int(source.id)]); game.issue("move",Vector2(108,100)); frame(game,.2)
	check(source.x==100,"real move command shows launch frames before displacement")
	frame(game,.3)
	check(source.x>100 and source.x<=102.836 and not game.t_cells.cells.state_for(source.id).trail.is_empty(),"actual map movement is a budgeted burst with real afterimages")
	frame(game,4)
	check(WarData.point(source).distance_to(Vector2(108,100))<.06 and source.orders.is_empty(),"goto completes on the requested safe map position")
	game.issue("move",Vector2(120,100)); frame(game,.3); game.issue("stop"); frame(game,.1)
	var stopped := WarData.point(source); var enemy := game.spawn("virus",2,stopped+Vector2(9,0))
	frame(game,2)
	check(WarData.point(source)==stopped and source.get("tCellStopped",false),"stop cancels movement and does not immediately chase a distant enemy")
	game.issue("hold"); frame(game,.1); check(not source.orders.is_empty() and source.orders[0].kind=="hold","hold persists as an actual defensive order")
	game.dispose()

	game = fresh(); source = actor(game); enemy = game.spawn("virus",2,Vector2(104,100)); enemy.hp=14.0
	game.selected.assign([int(source.id)]); game.issue("attackmove",Vector2(112,100)); var start := events.size(); frame(game,8)
	check(enemy.hp==0 and count("t_knife_impact",start)==1,"attack-move uses one independent damaging knife")
	check(WarData.point(source).distance_to(Vector2(112,100))<.06,"attack-move resumes its original destination after killing the target")
	check(game.state.combatProjectiles.is_empty(),"T knife is never duplicated in the generic projectile array")
	game.dispose()

	game = fresh(); source = actor(game); game.selected.assign([int(source.id)])
	game.issue("guard",Vector2(105,103)); frame(game,4)
	check(WarData.point(source).distance_to(Vector2(105,103))<.06 and source.orders[0].kind=="guard","guard reaches its point and retains the order")
	var red := game.spawn("worker",1,Vector2(100,104)); game.issue("retreat"); frame(game,4)
	check(WarData.point(source).distance_to(WarData.point(red))<=1.61 and source.orders.is_empty(),"retreat approaches the live home cell without trying to occupy its body")
	game.dispose()

	game = fresh(); source = actor(game); enemy = game.spawn("virus",2,Vector2(104,100)); enemy.hp=1000; enemy.maxHp=1000
	game.order(source,{"kind":"attack","target":enemy.id}); frame(game,.5)
	game.combat.damage({},source,1,true,"test"); start=events.size(); frame(game,.4)
	check(count("t_knife_spawn",start)==0 and enemy.hp==1000,"incoming hit before release interrupts the real queued attack")
	game.dispose()

	game = fresh(); source = actor(game); enemy = game.spawn("virus",2,Vector2(104,100)); enemy.hp=1000; enemy.maxHp=1000
	game.order(source,{"kind":"attack","target":enemy.id}); frame(game,.6)
	check(game.t_cells.cells.projectiles().size()==1,"actual release creates one live T knife")
	game.combat.damage({},source,source.hp,true,"test"); frame(game,.3)
	check(enemy.hp==986,"released knife survives source death and hits once")
	check(game.corpses.any(func(e):return e.kind=="t_cell"),"T death is retained as a real side-fall corpse")
	frame(game,1.6); check(not game.corpses.any(func(e):return e.kind=="t_cell"),"T corpse expires after its twelve-frame death")
	game.dispose()

	game = fresh(); source = actor(game); enemy = game.spawn("virus",2,Vector2(104,100)); enemy.hp=1000; enemy.maxHp=1000
	game.order(source,{"kind":"attack","target":enemy.id});frame(game,.5);start=events.size()
	game.state.combatProjectiles.append({"id":9001,"source":enemy.id,"sourceKind":"spear","faction":2,"x":source.x+.9,"y":source.y,"dx":-1.0,"dy":0.0,"speed":10.0,"ttl":1.0,"damage":1.0,"targetKinds":{},"style":"granule","vesselLane":0,"born":game.state.time})
	frame(game,.1)
	check(source.hp==104 and count("t_knife_spawn",start)==0,"same-tick incoming host projectile interrupts before the unreleased T knife")
	game.dispose()

	game = fresh("fullbody")
	var base := Vector2.ZERO
	for room in game.navigation.organs.liver.rooms:
		var candidate := WarData.source_to_world(room.centerSource)
		if [Vector2.ZERO,Vector2(-2,2),Vector2(2,2),Vector2(4,0)].all(func(offset):return game.navigation.clear_segment(candidate,candidate+offset,0,"spear")): base=candidate;break
	source = actor(game,base);source.vesselLane=0
	var b := game.spawn("b_cell",1,base+Vector2(-2,2)); var scan := game.spawn("dendritic_cell",2,base+Vector2(2,2));b.vesselLane=0;scan.vesselLane=0
	game.organ_functions.faction_state(1).commandUntil=20
	game.b_cells.refresh(); game.dendritic.refresh()
	enemy = game.spawn("virus",2,base+Vector2(4,0)); enemy.vesselLane=0;enemy.hp=1000; enemy.maxHp=1000;game.order(enemy,{"kind":"hold"})
	game.order(source,{"kind":"attack","target":enemy.id}); frame(game,.4)
	check(is_equal_approx(float(game.t_cells.cells.state_for(source.id).rate),2*1.15*.7),"real B/brain/dendritic modifiers compose in T cadence")
	frame(game,.3)
	check(enemy.hp<1000,"composed cadence reaches a real released hit")
	game.dispose()
	# Keep the movement measurement free of the previous knife's hit reaction:
	# a scanner struck during that cast correctly pauses its debuff.
	game = fresh("fullbody"); source = actor(game,base); source.vesselLane=0
	scan = game.spawn("dendritic_cell",2,base+Vector2(2,2)); scan.vesselLane=0
	game.order(scan,{"kind":"hold"}); game.dendritic.refresh()
	game.selected.assign([int(source.id)])
	var slow_goal := Vector2.INF
	for i in 32:
		var candidate := WarData.point(source)+Vector2.from_angle(i*TAU/32)*4
		var landing := WarData.point(source).move_toward(candidate,3*.945*.7)
		if game.navigation.command_lane(candidate,"t_cell",0)==0 and game.t_cells._landing(candidate,0,source) and game.t_cells._landing(landing,0,source) and game.navigation.clear_segment(WarData.point(source),candidate,0,"t_cell") and game.t_cells._buildings_clear(WarData.point(source),candidate,source) and candidate.distance_to(WarData.point(scan))<7:
			slow_goal=candidate; break
	check(slow_goal.is_finite(),"real tissue slowdown fixture has a clear goal inside detection coverage")
	if slow_goal.is_finite():
		var before := WarData.point(source)
		var motion_events := events.size()
		game.issue("move",slow_goal); frame(game,.6)
		var distance := WarData.point(source).distance_to(before)
		report.slowBlink={"distance":distance,"start":[before.x,before.y],"goal":[slow_goal.x,slow_goal.y],"position":[source.x,source.y],"multiplier":game.t_cells._multiplier(source,"moveMultiplier"),"state":game.t_cells.cells.state_for(source.id),"events":events.slice(motion_events),"plan":game.t_cells.snapshot().plans}
		check(absf(distance-3*.945*.7)<.004,"real dendritic slowdown shortens T blink distance to seventy percent (%.5f)" % distance)
	game.dispose()

	await gate_and_save()
	await attack_save()
	await sandbox()
	if OS.get_cmdline_user_args().has("--capture"): await capture()
	DirAccess.make_dir_recursive_absolute("res://test-output/t-cells")
	report.checks=checks; report.failures=failures
	var filename := "integration-native.json" if OS.get_cmdline_user_args().has("--capture") else "integration.json"
	var file:=FileAccess.open("res://test-output/t-cells/"+filename,FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ",true,true))
	print("T_INTEGRATION ",checks-failures.size(),"/",checks)
	quit(0 if failures.is_empty() else 1)

func gate_and_save() -> void:
	var game:=WarSimulation.new(); game.start("fullbody");game.state.influenzaColonies={"version":1,"groups":{}}
	var contract:Dictionary=game.navigation.organs.liver.gateContracts.siege[0]
	var a:=WarData.source_to_world(contract.tissueAnchorSource);var b:=WarData.source_to_world(contract.pipeAnchorSource)
	var source:=game.spawn("t_cell",1,a);source.vesselLane=0
	game.order(source,{"kind":"move","x":b.x,"y":b.y,"lane":int(contract.laneIndex)})
	game.t_cells.unit(source,.1);game.navigation.update(1000000)
	var checkpoint:Dictionary=game.navigation.gates[contract.id];checkpoint.isolated=true
	frame(game,1)
	check(WarData.point(source).distance_to(a)<.003 and source.vesselLane==0,"stale approved gate path is blocked when the actual checkpoint closes")
	checkpoint.isolated=false;frame(game,.4)
	var transit_position := WarData.point(source)
	checkpoint.isolated=true;frame(game,1)
	check(WarData.point(source).distance_to(transit_position)<.003 and source.vesselLane==0,"a gate closing during transit halts T before the layer handoff")
	checkpoint.isolated=false
	var previous:=WarSave.directory;WarSave.directory="user://test-saves/t-cell-integration/"+("native" if OS.get_cmdline_user_args().has("--capture") else "rules")
	check(WarSave.write(game,1)==OK,"actual T route/transit snapshot saves through normal validation")
	var snapshot:=game.snapshot();var epos:=WarData.point(source)
	frame(game,5);check(source.vesselLane==int(contract.laneIndex) and WarData.point(source).distance_to(b)<.003,"certified gate is crossed in budgeted bursts before switching layer at its exact endpoint")
	check(WarSave.read_slot(game,1)==OK,"actual mid-route T save restores")
	source=game.entity(int(source.id));check(WarData.point(source)==epos,"read restores the same actual T position")
	frame(game,5);check(source.vesselLane==int(contract.laneIndex) and WarData.point(source).distance_to(b)<.003,"restored certified gate traversal reaches the same endpoint")
	var false_edge:=game.t_cells._certify({"x":a.x,"y":a.y,"lane":0},{"x":a.x,"y":a.y,"lane":200})
	check(false_edge.is_empty(),"mere projected overlap is not a certified navigation edge")
	report.gate={"id":contract.id,"distance":a.distance_to(b),"lane":contract.laneIndex,"savePosition":[epos.x,epos.y]}
	game.dispose();WarSave.directory=previous

func sandbox() -> void:
	var game:=WarSimulation.new();game.start("sandbox",73)
	var home:Vector2=WarData.point(game.units().filter(func(e):return e.faction==1 and e.kind=="worker")[0])
	var source:=game.spawn("t_cell",1,home+Vector2(4,0))
	check(not source.is_empty(),"T is a real spawnable identity in the legacy sandbox")
	if not source.is_empty():
		var goal:=Vector2.INF
		for i in 32:
			var candidate:=WarData.point(source)+Vector2.from_angle(i*TAU/32)*4
			if game.t_cells._landing(candidate,0,source) and game.navigation.clear_segment(WarData.point(source),candidate,0,"t_cell") and game.t_cells._buildings_clear(WarData.point(source),candidate,source):goal=candidate;break
		check(goal.is_finite(),"sandbox movement fixture chooses an actually unoccupied clear destination")
		if not goal.is_finite(): game.dispose();return
		game.selected.assign([int(source.id)]);game.issue("move",goal);frame(game,5)
		check(WarData.point(source).distance_to(goal)<.1,"legacy sandbox T uses blink navigation instead of being disabled outside fullbody")
		report.sandbox={"home":[home.x,home.y],"goal":[goal.x,goal.y],"position":[source.x,source.y],"orders":source.orders,"runtime":game.t_cells.snapshot(),"message":game.message}
	game.dispose()

func attack_save() -> void:
	var game:=fresh();var source:=actor(game);var enemy:=game.spawn("virus",2,Vector2(104,100));enemy.hp=1000;enemy.maxHp=1000
	game.order(source,{"kind":"attack","target":enemy.id});frame(game,.6)
	var previous:=WarSave.directory;WarSave.directory="user://test-saves/t-cell-integration/"+("native-flight" if OS.get_cmdline_user_args().has("--capture") else "rules-flight")
	check(WarSave.write(game,0)==OK,"actual flying T knife saves with its committed release flag")
	frame(game,.3);check(enemy.hp==986,"original saved projectile impacts once")
	var start:=events.size();check(WarSave.read_slot(game,0)==OK,"actual in-flight host save restores")
	enemy=game.entity(int(enemy.id));check(enemy.hp==1000 and count("t_knife_spawn",start)==0,"load neither damages nor re-emits the saved projectile")
	frame(game,.3);check(enemy.hp==986 and count("t_knife_impact",start)==1 and count("t_knife_spawn",start)==0,"restored live projectile impacts once without a second launch")
	check(WarSave.write(game,1)==OK and WarSave.read_slot(game,1)==OK,"post-impact host state saves and loads")
	enemy=game.entity(int(enemy.id));frame(game,.1);check(enemy.hp==986,"post-impact restore does not replay a consumed hit")
	var legacy:=game.snapshot();legacy.erase("tCellRuntime");check(WarSave.validate(legacy).is_empty(),"older saves may omit the T runtime section")
	var invalid:=game.snapshot();invalid.tCellRuntime.cells.clock+=1
	check(not WarSave.validate(invalid).is_empty(),"host save rejects a T clock detached from world simulation time")
	invalid=game.snapshot();invalid.erase("entities")
	check(not WarSave.validate(invalid).is_empty(),"host T validation rejects a missing world without accessing invalid entities")
	game.dispose();WarSave.directory=previous

func capture() -> void:
	var main:Node2D=load("res://scenes/main.tscn").instantiate();root.add_child(main);current_scene=main;root.size=Vector2i(1440,900)
	main.set_process(false);main.set_process_unhandled_input(false);main.start("cell_test")
	var game:WarSimulation=main.game;game.state.entities.clear();game.navigation.blockers.clear()
	var source:=actor(game);game.selected.assign([int(source.id)]);game.issue("move",Vector2(110,100));frame(game,.5)
	game.paused=true;game.accumulator=.099
	main.camera.position=Vector2(102,100);main.camera.zoom=Vector2.ONE*96;main.camera.force_update_scroll()
	var path:String=WarTCells.data().clips.tBlink.path;var began:=Time.get_ticks_msec()
	while main.world.textures.get_texture(path)==null and Time.get_ticks_msec()-began<10000:await process_frame
	main.world.record_draws=true;await process_frame;await RenderingServer.frame_post_draw
	check(main.world.drawn_specs[4].any(func(r):return r.has("tCell") and int(r.ghosts)>0),"native T render draws original blink frames and real afterimages")
	root.get_texture().get_image().save_png("res://test-output/t-cells/native-blink.png")
	game.paused=false;game.start("cell_test");game.state.entities.clear();game.navigation.blockers.clear();source=actor(game)
	var enemy:=game.spawn("virus",2,Vector2(104,100));game.order(source,{"kind":"attack","target":enemy.id});frame(game,.7)
	game.paused=true;game.accumulator=.099;game.selected.assign([int(source.id)]);main.camera.position=Vector2(102,100)
	path=WarTCells.data().clips.tThrow.path;began=Time.get_ticks_msec()
	while main.world.textures.get_texture(path)==null and Time.get_ticks_msec()-began<10000:await process_frame
	await process_frame;await RenderingServer.frame_post_draw
	check(main.world.drawn_specs[4].any(func(r):return r.has("tKnife")) and main.world.drawn_specs[4].any(func(r):return r.has("tCell") and r.bodyCrop),"native cast draws one separate real knife and a body-only throw region")
	root.get_texture().get_image().save_png("res://test-output/t-cells/native-throw.png")
	main.queue_free();await process_frame;game.dispose()
