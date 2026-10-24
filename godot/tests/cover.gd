extends SceneTree
var failures: Array[String] = []
var cover: WarCover
var actions: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,message: String) -> void:
	if not value: failures.append(message); printerr("FAIL ",message)
	else: print("PASS ",message)

func click(button: BaseButton,local_point := Vector2.INF) -> void:
	var before := actions.size()
	var event := InputEventMouseButton.new()
	event.position = root.get_stretch_transform()*button.get_global_rect().get_center()
	if local_point != Vector2.INF:
		event.position = root.get_stretch_transform()*(button.get_global_transform()*local_point)
	event.button_index = MOUSE_BUTTON_LEFT; event.pressed = true; root.push_input(event)
	event = event.duplicate(); event.pressed = false; root.push_input(event)
	await process_frame
	check(actions.size() == before,"click feedback precedes navigation")
	await create_timer(.26).timeout
	check(actions.size() == before+1,"click dispatches exactly once after feedback")

func screenshot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test-output/cover/"+name+".png")

func artwork_pixels() -> PackedByteArray:
	await RenderingServer.frame_post_draw
	var scale := root.get_stretch_transform().get_scale()
	# Titles now float. Compare only the unchanged central anatomy on the GPU.
	var origin := Vector2i(cover.size.x*.36*scale.x,cover.size.y*.30*scale.y)
	var extent := Vector2i(cover.size.x*.28*scale.x,cover.size.y*.38*scale.y)
	return root.get_texture().get_image().get_region(Rect2i(origin,extent)).get_data()

func menu_pixels() -> PackedByteArray:
	await RenderingServer.frame_post_draw
	var rendered := root.get_texture().get_image()
	var start := int(rendered.get_height()*.74)
	return rendered.get_region(Rect2i(0,start,rendered.get_width(),rendered.get_height()-start)).get_data()

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://test-output/cover")
	cover = WarCover.new(); root.add_child(cover)
	cover.action_requested.connect(func(action): actions.append(action))
	for i in 4: await process_frame
	check(not cover.is_processing(),"cover has no idle animation update")
	check(cover.background.material == null,"approved artwork has no eye-tracking shader")
	check(cover.background.texture.resource_path.ends_with("artwork-static-v2.png"),"approved static three-villain art is loaded")
	check(cover.find_children("*","CheckButton",true,false).is_empty(),"dynamic effects switch is removed")
	check(cover.find_children("*","Sprite2D",true,false).is_empty(),"no animated character rigs are instantiated")
	check(cover.titles[0].text == "细胞战争" and cover.titles[1].text == "CELL WAR","correct Chinese and English titles")
	check(cover.buttons[1].caption == "角色预览","character preview uses the confirmed menu name")
	for window_size in [Vector2i(1280,800),Vector2i(1672,941),Vector2i(360,780)]:
		root.size = window_size
		root.content_scale_size = Vector2i(360,780) if window_size.x < window_size.y else Vector2i(1440,900)
		for i in 6: await process_frame
		check(cover.titles[0].get_global_rect().get_center().x < cover.titles[1].get_global_rect().get_center().x,"Chinese title stays left of English at "+str(window_size))
		if not cover.compact:
			check(cover.button_area.get_parent() == cover.stage,"cards share the artwork transform")
		for button in cover.buttons:
			var skin := button.get_theme_stylebox("normal") as StyleBoxTexture
			check(skin != null and skin.texture.resource_path.begins_with("res://assets/ui/membrane/"),"generated membrane card "+button.caption)

		for button in cover.buttons:
			var rect := button.get_global_rect()
			check(rect.position.x >= 0 and rect.end.x <= cover.size.x+1 and rect.position.y >= 0 and rect.end.y <= cover.size.y+1,"button fits "+str(window_size)+" "+button.caption)
			check(button.motion and button.is_processing(),"menu icon floats while visible "+button.caption)
			await click(button)
		check(actions.slice(actions.size()-4) == ["start","preview","tutorial","settings"],"real clicks dispatch four actions "+str(window_size))
		await click(cover.buttons[0],cover.buttons[0].size*Vector2(.5,.75))
		check(actions.back() == "start","card text area accepts input "+str(window_size))
		await click(cover.buttons[1],cover.buttons[1].hologram_center())
		check(actions.back() == "preview","floating icon accepts input "+str(window_size))
		var action_count := actions.size()
		var outside := InputEventMouseButton.new()
		outside.position = root.get_stretch_transform()*(cover.buttons[0].get_global_transform()*Vector2(1,1))
		outside.button_index = MOUSE_BUTTON_LEFT; outside.pressed = true; root.push_input(outside)
		outside = outside.duplicate(); outside.pressed = false; root.push_input(outside)
		await process_frame
		check(actions.size() == action_count,"empty space outside membrane card does not activate it")
		for button in cover.buttons: button.release_focus()
		await create_timer(.45).timeout
		await screenshot("static-%dx%d" % [window_size.x,window_size.y])
	root.size = Vector2i(1280,800); root.content_scale_size = Vector2i(1440,900)
	for i in 5: await process_frame
	var transform: Transform2D = cover.background.get_global_transform()
	var pixels := PackedByteArray()
	if DisplayServer.get_name() != "headless": pixels = await artwork_pixels()
	for point in [Vector2(5,280),Vector2(1435,280)]:
		var event := InputEventMouseMotion.new()
		event.position = root.get_stretch_transform()*point; root.push_input(event)
		await create_timer(.25).timeout
		check(cover.background.get_global_transform() == transform,"mouse and elapsed time do not move artwork")
		if not pixels.is_empty():
			var current: PackedByteArray = await artwork_pixels()
			check(current == pixels,"rendered artwork remains pixel-identical after mouse movement")
	await screenshot("static-final")
	cover.buttons[0]._activate()
	await create_timer(.06).timeout
	check(cover.buttons[0].activation_pending and cover.buttons[0].pulse_elapsed < .22,"click pulse is visible before navigation")
	await screenshot("icon-click-feedback")
	await create_timer(.25).timeout
	cover.buttons[0].grab_focus()
	var key := InputEventKey.new(); key.keycode = KEY_SPACE; key.pressed = true; root.push_input(key)
	key = key.duplicate(); key.pressed = false; root.push_input(key)
	await create_timer(.26).timeout
	check(actions.back() == "start","membrane card accepts keyboard activation")
	var before := actions.size()
	cover.buttons[0]._activate(); cover.buttons[0]._activate()
	await create_timer(.26).timeout
	check(actions.size() == before+1,"rapid activation cannot dispatch duplicate navigation")
	var phase := cover.buttons[1].phase
	var idle_pixels := PackedByteArray()
	if DisplayServer.get_name() != "headless":
		idle_pixels = await menu_pixels()
	await create_timer(.18).timeout
	check(cover.buttons[1].phase != phase,"icon idle phase advances")
	if not idle_pixels.is_empty():
		check(idle_pixels != await menu_pixels(),"native renderer shows moving icon pixels")
	var title_min := cover.titles[0].float_offset()
	var title_max := title_min
	for i in 8:
		await create_timer(.2).timeout
		title_min = minf(title_min,cover.titles[0].float_offset())
		title_max = maxf(title_max,cover.titles[0].float_offset())
	check(title_max-title_min > 5,"sculpted titles visibly float vertically")
	cover.hide()
	for button in cover.buttons: check(not button.is_processing(),"hidden menu stops card updates "+button.caption)
	for title in cover.titles: check(not title.is_processing(),"hidden title stops float updates "+title.text)
	cover.show()
	for button in cover.buttons: check(button.is_processing(),"return home resumes card updates "+button.caption)
	var file := FileAccess.open("res://test-output/cover/static-checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"physicalInput":true,"titleMotion":true,"iconMotion":true,"characterMotion":false,"eyeTracking":false,"nativePixelsCompared":not pixels.is_empty()},"  "))
	print("STATIC COVER QA DONE ",failures)
	cover.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
