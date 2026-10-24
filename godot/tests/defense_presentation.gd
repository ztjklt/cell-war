extends "res://tests/left_lung_ui.gd"
## Explicit presentation fixtures. Natural victory remains covered by left_lung_ui.

func check_panel(ui: Control,label: String) -> void:
	check(root.get_visible_rect().encloses(ui.get_global_rect()),label+" stays on screen")
	check(not ui.get_global_rect().intersects(main.hud.toolbar.get_global_rect()),label+" clears toolbar")
	check(not ui.get_global_rect().intersects(main.hud.layer_button.get_global_rect()) and not ui.get_global_rect().intersects(main.hud.overview_button.get_global_rect()),label+" clears view controls")
	check(ui.mouse_filter == Control.MOUSE_FILTER_IGNORE and ui.find_children("*","Control",true,false).all(func(c): return c.mouse_filter == Control.MOUSE_FILTER_IGNORE),label+" does not steal map input")
	check(ui.digits.get_global_rect().end.y <= ui.detail.get_global_rect().position.y,label+" clock does not overlap instructions: "+str(ui.digits.get_global_rect())+" / "+str(ui.detail.get_global_rect()))
	for node in ui.find_children("*","Label",true,false):
		if node.is_visible_in_tree():
			check(node.size.x+.1 >= node.get_minimum_size().x and ui.get_global_rect().encloses(node.get_global_rect()),label+" text fits: "+node.text)

func exercise_card() -> void:
	main.new_run("lung_defense"); main.game.paused = true
	await frames(12)
	var ui: WarDefenseCountdown = main.hud.defense_countdown
	ui._process(.1)
	var art: Array = ui.find_children("*","TextureRect",true,false)
	check(art.size() >= 2 and art.all(func(c): return c.texture != null),"generated card and character art are actually used")
	check(ui.get("progress") is ProgressBar,"native progress meter is available")
	check(ui.caption.text.contains("暂停") and ui.digits.text == "02:00","preparation shows real paused clock")
	check_panel(ui,"desktop preparation")
	await capture("ui-preparation")
	var before_motion := ui.characters.position
	var before_clock: float = main.game.state.lungDefense.elapsed
	for i in 6: ui._process(.1)
	check(ui.characters.position.distance_to(before_motion) > .1,"cell art floats while the paused game clock stays still")
	check(main.game.state.lungDefense.elapsed == before_clock and ui.digits.text == "02:00","decorative motion does not advance preparation")
	main.game.state.lungDefense.elapsed = 119
	ui._process(.1)
	check(ui.digits.text == "00:01","last preparation second remains visible")
	var group: Dictionary = main.game.influenza.start_outbreak("lung_l",0,13)
	main.game.state.lungDefense.phase = "infected"; main.game.state.lungDefense.colony = group.id
	ui._process(.1)
	check(ui.detail.text.contains("病毒") and ui.detail.text.contains("13") and ui.detail.text.contains("要塞"),"combat shows remaining enemies and fortress count for the current colony")
	await capture("ui-combat")
	group.pending = 0; group.purification.status = "waiting_red"; group.purification.red = 0; group.purification.white = 2
	ui._process(.1)
	check(ui.digits.text.contains("红细胞") and ui.detail.text.contains("0/1") and ui.detail.text.contains("2/1"),"missing red cell is explained with actual required presence")
	await capture("ui-waiting-red")
	group.purification.status = "purifying"; group.purification.red = 1; group.purification.elapsed = 10
	ui._process(.1)
	check(ui.get("progress") != null and is_equal_approx(float(ui.get("progress").value),.5),"purification meter reflects ten of twenty seconds")
	check(ui.digits.text.contains("10") and ui.digits.text.contains("20"),"purification shows elapsed and required duration")
	await capture("ui-purifying")
	group.purification.elapsed = 12; ui._process(.1)
	var meter_motion: Tween = ui.get("_meter_tween")
	if check(meter_motion != null,"progress uses a native transition"):
		# Step the real Tween deterministically; texture upload can make a native
		# frame longer than the entire transition during the screenshot fixture.
		meter_motion.pause(); meter_motion.custom_step(.05)
		check(ui.progress.value > .5 and ui.progress.value < .6,"purification progress interpolates visually between updates")
		meter_motion.custom_step(.2)
		check(is_equal_approx(ui.progress.value,.6),"animated progress settles on the exact simulation value")
	await check_waiting_with_distant_virus(ui,group)
	group.purification.status = "contested"; group.purification.elapsed = 0
	ui._process(.1)
	check(ui.get("progress") != null and float(ui.get("progress").value) == 0,"interrupted purification never keeps stale progress")
	main.game.state.lungDefense.phase = "defended"; main.game.state.lungDefense.finishedAt = 301
	ui._process(.1)
	check(ui.digits.text == "左肺已夺回" and ui.detail.text.contains("05:01"),"victory shows actual recorded completion time")
	await capture("ui-victory")
	root.size = Vector2i(390,844); await frames(20); ui._process(.1); await frames()
	check_panel(ui,"portrait victory")
	await capture("ui-victory-portrait")
	main.new_run("lung_defense"); main.game.paused = true; await frames(12); ui._process(.1)
	check(ui.digits.text == "02:00" and ui.caption.text.contains("准备"),"new save clears victory text and restarts preparation")
	check_panel(ui,"portrait preparation")
	await capture("ui-preparation-portrait")
	for dimensions in [Vector2i(360,780),Vector2i(844,390),Vector2i(1024,768)]:
		root.size = dimensions; await frames(20); ui._process(.1); await frames()
		check_panel(ui,"preparation "+str(dimensions))
	await capture("ui-preparation-tablet")

func check_waiting_with_distant_virus(ui: WarDefenseCountdown,group: Dictionary) -> void:
	# Real purification checks the infection floor, not all living colony members.
	var virus: Dictionary = main.game.spawn("virus",2,Vector2(1232,1210))
	var white: Dictionary = main.game.spawn("spear",1,WarData.point(group.center))
	if not check(not virus.is_empty() and not white.is_empty(),"boundary fixture spawns on legal tissue"): return
	virus.fluColony = group.id
	main.game.influenza.purification.update(.1)
	check(main.game.influenza.members(group).size() == 1 and group.purification.status == "waiting_red" and group.purification.hostiles == 0,"distant colony virus does not contest the cleared infection floor")
	ui._process(.1)
	check(ui.digits.text == "还需要红细胞","waiting red follows real purification state while a virus lives elsewhere")
	var red: Dictionary = main.game.spawn("worker",1,WarData.point(group.center))
	if not check(not red.is_empty(),"red can join the infection floor"): return
	main.game.influenza.purification.update(5)
	ui._process(.1)
	check(group.purification.status == "purifying" and ui.progress.value > 0,"red and white can purify with a distant surviving virus")
	white.vesselLane = 1
	main.game.influenza.purification.update(.1)
	ui._process(.1)
	check(group.purification.status == "waiting_white" and ui.progress.value == 0 and ui.digits.text == "还需要白细胞","white leaving resets progress and asks for white instead of chasing distant viruses")
	await capture("ui-waiting-white")

func run() -> void:
	WarSave.directory = "user://test-saves/defense-art-"+str(Time.get_ticks_usec())
	WarSettings.storage_path = WarSave.directory+"/settings.json"
	DirAccess.make_dir_recursive_absolute(WarSave.directory)
	prepare_evidence("res://test-output/left-lung-ui-20261023/")
	root.size = Vector2i(1440,900)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main); current_scene = main; main.set_process(false)
	# Dummy renderer has no GPU terrain textures; native runs verify the real art.
	if DisplayServer.get_name() == "headless": main.world.hide()
	await exercise_card()
	print("DEFENSE_PRESENTATION ",checks-failures.size(),"/",checks)
	main.queue_free(); await frames()
	quit(0 if failures.is_empty() else 1)

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	# Stage entrances settle before the screenshot; cell float stays animated.
	await create_timer(.4).timeout
	await super.capture(name)
