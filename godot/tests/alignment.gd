extends SceneTree
var failures: Array[String] = []
var checks := 0

func check(value: bool,message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("FAIL ",message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var oracle: Dictionary = WarData.read("advisor_oracle")
	for fixture in oracle.split:
		check(WarAdvisorDialogue.split_text(fixture.text,float(fixture.limit)) == fixture.chunks,"BrainUI split "+fixture.text)
	for fixture in oracle.replies:
		var actual := WarAdvisorRules.reply_data(fixture.state,fixture.entities,float(fixture.food),fixture.spec,fixture.topic)
		check(actual == fixture.expected,"BrainAdvisor "+fixture.tag+" "+fixture.topic+" got "+JSON.stringify(actual)+" expected "+JSON.stringify(fixture.expected))
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main: Node2D = scene.instantiate()
	scene = null
	root.size = Vector2i(1280,800)
	root.add_child(main); current_scene = main
	# The current entry point opens the cover; tactical reading starts in play.
	main.start("systemic")
	await process_frame
	var dialogue: WarAdvisorDialogue = main.hud.dialogue
	dialogue.answer("defense")
	check(dialogue.chatting and dialogue.active and not dialogue.strips.is_empty(),"advisor topics create original reading strips")
	var before := dialogue.elapsed
	main.game.paused = true
	dialogue._process(.5)
	check(dialogue.elapsed > before,"original dialogue keeps reading during tactical pause")
	main.hud.show_help()
	before = dialogue.elapsed
	dialogue._process(.5)
	check(dialogue.elapsed == before,"modal blocks dialogue reading")
	check(main.hud.menu_body.get_child_count() > 8,"handbook includes complete original sections")
	main.hud.close_menu()
	main.start("trachea_01")
	check(not dialogue.active and dialogue.history.is_empty(),"new world resets advisor session")
	main.game.paused = false
	dialogue._poll(1.1,false)
	check(dialogue.bubble.contains("我是你的参谋小脑") and dialogue.bubble.contains("行动由你决定"),"approved commander/advisor proactive introduction")
	main.game.state.campaign.event.zones[-1].control = 30
	dialogue._poll(.1,false)
	check(dialogue.bubble == "下段屏障告急！先回防，再调援。","danger edge uses original trachea wording")
	dialogue._process(.01)
	check(main.hud.advisor.mood == "alert","critical zone drives advisor alert expression")
	main.game.state.campaign.event.status = "completed"
	dialogue._process(.01)
	check(main.hud.advisor.mood == "happy","completion drives advisor happy expression")
	root.size = Vector2i(360,780)
	for i in 5: await process_frame
	dialogue.answer("supply")
	for i in 5: await process_frame
	check(dialogue.controls.get_global_rect().end.x <= 361,"advisor topic buttons fit narrow window")
	main.start("fullbody")
	var move: Dictionary = oracle.shortMove
	var worker: Dictionary = main.game.entity(int(move.id))
	var target := Vector2(move.x,move.y)
	var position: Dictionary = main.game.formation([worker],target,int(move.lane))
	check(WarData.point(position[int(worker.id)]).distance_to(target) < .00001,"clear short single move retains exact target")
	main.game.selected.assign([int(worker.id)])
	main.game.issue("move",target)
	for i in 20:
		main.game.navigation.update(10000)
		main.game.step(.1)
	check(WarData.point(worker).distance_to(target) < .1,"clear short single move reaches original allowed destination")
	var report := {"checks":checks,"failures":failures,"oracle":"current BrainUI.split / BrainAdvisor.reply","runtimeLuaAdded":false}
	DirAccess.make_dir_recursive_absolute("res://test-output")
	var file := FileAccess.open("res://test-output/alignment.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("ALIGNMENT ",checks-failures.size(),"/",checks)
	main.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
