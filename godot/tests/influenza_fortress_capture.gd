extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1440,900)
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main); current_scene = main
	main.set_process(false); main.set_process_unhandled_input(false)
	main.start("fullbody")
	main.game.state.influenzaColonies = {"version":1,"groups":{}}
	var group: Dictionary = main.game.influenza.start_outbreak("lung_r",0,10)
	var fort: Dictionary = {}
	for i in 600:
		main.game.navigation.update(10000)
		main.game.step(.1)
		var sites: Array = main.game.influenza.forts(group)
		if not sites.is_empty(): fort = sites[0]
		if not fort.is_empty() and float(fort.progress) >= .45: break
	if fort.is_empty() or float(fort.progress) < .45:
		printerr("Real fortress construction did not reach capture phase"); quit(1); return
	main.focus(WarData.point(fort)+Vector2(0,-.6),48)
	# A friendly observer provides ordinary faction vision; it is added only after simulating construction.
	var observer: Dictionary = {}
	for i in 30:
		var p := WarData.point(fort)+Vector2.from_angle(i*2.399963)*12
		if main.game.navigation.point_allowed(p,0,"scout"):
			observer = main.game.spawn("scout",1,p)
			if not observer.is_empty(): break
	if observer.is_empty(): printerr("No legal observer position"); quit(1); return
	observer.vesselLane = 0
	main.game.paused = true
	var path: String = WarInfluenzaColonies.data().texture
	var began := Time.get_ticks_msec()
	while Time.get_ticks_msec()-began < 10000:
		await process_frame
		if main.world.textures.get_texture(path) != null and main.world.textures.get_texture(WarInfluenzaAnimation.data().clips.fluBuild.path) != null: break
	main.camera.force_update_scroll()
	await process_frame; await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://test-output/influenza-fortress")
	root.get_texture().get_image().save_png("res://test-output/influenza-fortress/construction.png")
	main.game.state.entities.erase(str(observer.id))
	for i in 600:
		main.game.navigation.update(10000); main.game.step(.1)
		if fort.complete: break
	if not fort.complete: printerr("Construction never completed"); quit(1); return
	observer = main.game.spawn("scout",1,WarData.point(observer)); observer.vesselLane = 0
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test-output/influenza-fortress/completed.png")
	print("FORTRESS CAPTURED: actual construction and completed simplified art")
	main.queue_free(); await process_frame
	quit()
