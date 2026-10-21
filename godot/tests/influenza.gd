extends SceneTree
var failures: Array[String] = []
var checks := 0

func check(value: bool,message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("FAIL ",message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var base := {"id":0,"kind":"virus","category":"unit","x":100.0,"y":100.0,"hp":100.0,"maxHp":100.0,"faction":2}
	var keys := {"move":"fluMove","attack":"fluAttack","hit":"fluHit","death":"fluDeath","build":"fluBuild"}
	for action in keys:
		var key: String = keys[action]
		var clip: Dictionary = WarInfluenzaAnimation.data().clips[key]
		check(clip.durations.size() == 20,"twenty frames in "+action)
		check(ResourceLoader.exists("res://assets/"+str(clip.path)),"imported atlas "+action)
		var window := float(WarData.spec("virus").cool) if action == "attack" else float(clip.duration)
		for i in 20:
			var time := (i+.5)*window/20
			var e := base.duplicate(true)
			if action == "attack": e.shotTime = 0.0
			if action == "hit": e.cellHitStarted = 0.0
			if action == "death": e.deathTime = 0.0
			if action == "build": e.cellWorkTime = time
			var sample := WarInfluenzaAnimation.sample(e,time,1.0,action == "death")
			check(sample.key == key and int(sample.frame) == i,"reachable %s frame %d" % [action,i+1])
			if action != "death":
				check(WarCellShape.normalized(e,key,i,"outline").size() >= 3,"painted picking contour %s %d" % [action,i+1])
	var e := base.duplicate(true)
	e.shotTime = 0.0; e.cellHitStarted = .2
	check(WarInfluenzaAnimation.sample(e,.3,1,false).key == "fluHit","hit interrupts bite")
	e.deathTime = .25
	check(WarInfluenzaAnimation.sample(e,.3,1,false).key == "fluDeath","death interrupts hit")
	check(WarInfluenzaAnimation.sample(e,2.26,0,true).get("hidden",false),"death remains vanished")
	check(is_equal_approx(WarInfluenzaAnimation.corpse_duration(e),2.1),"full two-second death retained")
	e = base.duplicate(true)
	check(WarInfluenzaAnimation.sample(e,10,0,false).frame == 0,"stationary virus does not walk")
	e.cellWorkTime = 10.0
	check(WarInfluenzaAnimation.sample(e,9.95,0,false).key == "fluBuild","interpolated render clock displays current drilling")
	e.erase("cellWorkTime")
	check(is_zero_approx(float(WarCellShape.pose(e,10,false).angle)),"artwork stays upright")
	e.weaponHeading = PI
	check(WarCellShape.pose(e,10,false).mirror,"left-facing bite mirrors")
	check(not WarCellShape.pose(e,0,true).mirror,"standing collision hull preserved")
	var game := WarSimulation.new()
	game.start("cell_test")
	var virus: Dictionary = game.entity(int(game.state.cellTest.virus))
	game.state.time = 10.0
	game.combat.damage({},virus,1,true,"test")
	check(virus.cellHitStarted == 10.0,"real damage starts virus hit")
	game.state.time = 10.1
	game.combat.damage({},virus,1,true,"test")
	check(virus.cellHitStarted == 10.0,"rapid damage does not trap reaction on first frame")
	var view := WarWorldView.new()
	view.game = game
	check(view.animation(virus,false).family == "influenza","runtime renderer selects approved virus family")
	view.free(); game.dispose()
	if OS.get_cmdline_user_args().has("--capture"):
		var scene: PackedScene = load("res://scenes/main.tscn")
		var main: Node2D = scene.instantiate(); scene = null
		root.add_child(main); current_scene = main
		root.size = Vector2i(1440,900)
		main.set_process(false); main.set_process_unhandled_input(false)
		main.start("lung_skirmish")
		main.game.state.time = .65
		for id in main.game.state.lungSkirmish.enemies:
			main.game.entity(int(id)).shotTime = 0.0
		var target: Dictionary = main.game.entity(int(main.game.state.lungSkirmish.enemies[0]))
		main.camera.position = WarData.point(target)
		main.camera.zoom = Vector2.ONE*64
		main.camera.force_update_scroll()
		var began := Time.get_ticks_msec()
		var path: String = WarInfluenzaAnimation.data().clips.fluAttack.path
		while main.world.textures.get_texture(path) == null and Time.get_ticks_msec()-began < 10000:
			await process_frame
		check(main.world.textures.get_texture(path) != null,"actual renderer loads reviewed attack atlas")
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://test-output")
		root.get_texture().get_image().save_png("res://test-output/influenza-native.png")
		main.queue_free(); await process_frame
	DirAccess.make_dir_recursive_absolute("res://test-output")
	var output := FileAccess.open("res://test-output/influenza.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	print("INFLUENZA ",checks-failures.size(),"/",checks)
	quit(0 if failures.is_empty() else 1)
