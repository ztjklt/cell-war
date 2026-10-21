extends SceneTree
var failures: Array[String] = []
var checks := 0
var main: Node2D

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,text: String) -> void:
	checks += 1
	if not value: failures.append(text); printerr("FAIL ",text)

func frames(count := 5) -> void:
	for i in count: await process_frame

func finish_chat(ui: WarLifeDialogue) -> void:
	var began := Time.get_ticks_msec()
	while not ui.animation_finished() and Time.get_ticks_msec()-began < 20000: await process_frame
	await frames(3)
	check(ui.animation_finished(),"chat animation completes while simulation is paused")

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	print("LIFE UI CAPTURE ",name)
	var began := Time.get_ticks_msec()
	var stable := 0
	while name == "desktop" and Time.get_ticks_msec()-began < 12000 and stable < 5:
		await process_frame
		var ready: bool = main.world.textures.pending.is_empty()
		for tile in main.world.visible_tiles:
			if main.world.textures.get_texture(tile.spec.resource) == null: ready = false
		stable = stable+1 if ready else 0
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png("res://test-output/life-decisions/"+name+".png")
	print("LIFE UI CAPTURED ",name)

func run() -> void:
	WarSave.directory = "user://test-saves/life-ui"
	DirAccess.make_dir_recursive_absolute("res://test-output/life-decisions")
	root.size = Vector2i(1440,900)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main); current_scene = main
	main.set_process(false); main.start("life"); main.overview()
	await frames(20)
	var ui: WarLifeDialogue = main.hud.life_dialogue
	check(ui.visible and ui.phone.position.x > 1000,"external conversations live in the right-hand desk phone")
	check(main.hud.panel.position.x < 100 and main.hud.zoom_tools.position.x < 100,"command card and zoom tools move to the left")
	check(ui.phone.get_global_rect().encloses(ui.panel.get_global_rect()),"real dialogue controls fit the phone screen")
	check(ui.phone.size.x >= 360 and ui.phone.position.x-WarDeskMapFrame.rect_for(root.get_visible_rect().size).end.x > 80,"wider phone has a clear gap from the shifted map")
	var s: Dictionary = main.game.life.state()
	s.serial = 1; s.pending = {"id":"late_work","token":1,"offeredAt":0.0}; s.revision += 1
	await frames()
	check(ui.option_buttons.size() == 3 and main.game.paused,"actual incoming conversation opens three choices and pauses")
	check(ui.panel is MarginContainer and not ui.panel.has_node("_FacetSurface") and ui.phone is WarDeskPhone,"phone contains native dialogue without an extra decorative panel")
	check(not ui.animation_finished() and ui.option_buttons.all(func(b): return b.disabled),"choices cannot be clicked before progressive reveal")
	check(not ui.submit_choice(1,0) and int(s.money) == 300,"early hidden-choice submission cannot settle")
	var first_self := INF
	var last_other := 0.0
	var first_option := INF
	for stage in ui._stages:
		if stage.option: first_option = minf(first_option,float(stage.start))
		elif stage.own: first_self = minf(first_self,float(stage.start))
		else: last_other = maxf(last_other,float(stage.start))
	check(first_self > last_other and first_option > first_self,"other speaker, own reply and choices reveal in order")
	await create_timer(.5).timeout
	await capture("chat-incoming")
	await finish_chat(ui)
	check(ui.content.size.y <= ui.scroll.size.y+1,"short desktop chat fits without blank inflated message rows")
	var black := 0
	var white := 0
	for shell in ui.content.find_children("*","PanelContainer",true,false):
		var fill: Color = shell.get_theme_stylebox("panel").bg_color
		if fill == Color("151515"): black += 1
		if fill == Color.WHITE: white += 1
	check(black >= 2 and white >= 2,"own messages have black bubbles and external messages white bubbles")
	check(not ui.phone.get_global_rect().intersects(main.hud.panel.get_global_rect()),"right phone and left command card do not overlap")
	await capture("desktop")
	var balance := int(s.money)
	var button: Button = ui.option_buttons[1]
	ui.scroll.ensure_control_visible(button)
	await frames()
	var press := InputEventMouseButton.new(); press.button_index = MOUSE_BUTTON_LEFT; press.pressed = true
	press.position = root.get_stretch_transform()*button.get_global_rect().get_center()
	root.push_input(press)
	var release := press.duplicate(); release.pressed = false; root.push_input(release)
	await frames()
	check(s.pending.is_empty() and int(s.money) == balance+60 and int(s.decisionCount) == 1,"physical click settles authored reply once")
	check(not main.game.paused and s.history.back().reply.contains("再做一会儿"),"reply becomes own dialogue and prior running state resumes")
	check(main.drag_button == 0 and main.game.state.commands.is_empty(),"phone reply never becomes a battlefield click")
	check(not ui.submit_choice(1,1) and int(s.money) == balance+60,"stale button cannot pay twice")
	await finish_chat(ui)
	await capture("answered")
	var snapshot: Dictionary = main.game.snapshot()
	for item in WarLifeRun.catalogue():
		ui.show_preview(item.id)
		await frames(2)
		check(ui.option_buttons.size() == 3 and ui.option_buttons.all(func(b): return b.disabled),"preview shows all three non-settling choices "+item.id)
	check(main.game.life.state() == snapshot.lifeRun,"all forty previews leave life state unchanged")
	ui.show_preview("late_work")
	await frames()
	await finish_chat(ui)
	for window_size in [Vector2i(360,780),Vector2i(430,932),Vector2i(844,390),Vector2i(1280,800)]:
		root.size = window_size; await frames(8); main.hud._layout(); await frames(4)
		await finish_chat(ui)
		var bounds := root.get_visible_rect()
		var rect := ui.panel.get_global_rect()
		check(rect.position.x >= 0 and rect.end.x <= bounds.end.x+1 and rect.end.y <= bounds.end.y+1,"conversation within viewport "+str(window_size))
		check(not ui.phone.get_global_rect().intersects(main.hud.panel.get_global_rect()),"phone does not cover the left command card "+str(window_size))
		check(ui.phone.get_global_rect().encloses(rect),"conversation stays inside phone "+str(window_size))
		for tool in main.hud.toolbar.get_children():
			if not tool.is_visible_in_tree(): continue
			var tool_rect: Rect2 = tool.get_global_rect()
			check(tool_rect.position.x >= 0 and tool_rect.end.x <= bounds.end.x+1,"right toolbar fits "+str(window_size)+tool.text)
		if window_size == Vector2i(360,780):
			check(not main.hud.status.visible,"portrait notices do not show through chat gaps")
			check(ui.option_buttons.back().get_global_rect().end.y <= ui.scroll.get_global_rect().end.y+1,"portrait chat follows through to the final option")
			var glass := InputEventMouseButton.new()
			glass.button_index = MOUSE_BUTTON_LEFT; glass.pressed = true
			glass.position = root.get_stretch_transform()*(ui.phone.position+Vector2(8,ui.phone.size.y*.5))
			root.push_input(glass)
			glass = glass.duplicate(); glass.pressed = false; root.push_input(glass)
			await frames()
			check(not main.hud.wheel.visible and main.drag_button == 0,"blank phone glass shields underlying battlefield clicks")
			var zoom: Vector2 = main.camera.zoom
			glass = InputEventMouseButton.new(); glass.button_index = MOUSE_BUTTON_WHEEL_DOWN; glass.pressed = true
			glass.position = root.get_stretch_transform()*ui.scroll.get_global_rect().get_center(); root.push_input(glass)
			await frames()
			check(main.camera.zoom == zoom,"scrolling phone messages never zooms the underlying map")
			await capture("portrait")
		if window_size == Vector2i(844,390): await capture("short-landscape")
	ui._toggle(); await frames()
	check(not main.game.paused,"ending preview restores earlier pause state")
	main.start("systemic"); await frames()
	check(not ui.visible and not main.game.life.enabled(),"legacy mode hides life conversation")
	var file := FileAccess.open("res://test-output/life-decisions/ui.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"physicalClick":true,"previews":40},"  "))
	print("LIFE UI ",checks," checks, failures=",failures)
	main.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
