extends SceneTree
var main: Node2D
var failures: Array[String] = []
var checks := 0
const OUT := "res://test-output/bug-audit-ui/"

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("FAIL ",message)

func frames(count := 5) -> void:
	for i in count: await process_frame

func named_button(parent: Node,text: String) -> Button:
	for node in parent.find_children("*","Button",true,false):
		if node.text == text: return node
	return null

func production_button(kind: String,research := false) -> Button:
	for entry in main.hud.production_buttons:
		if entry.kind == kind and entry.research == research: return entry.button
	return null

func expose(button: Button) -> void:
	var parent := button.get_parent()
	while parent != null:
		if parent is ScrollContainer: parent.ensure_control_visible(button)
		parent = parent.get_parent()
	await frames(5)

func mouse(point: Vector2,down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = root.get_stretch_transform()*point
	event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down
	root.push_input(event)

func click(button: Button,hold := .03) -> void:
	check(button != null,"target button exists")
	if button == null: return
	await expose(button)
	var at := button.get_global_rect().get_center()
	check(root.get_visible_rect().has_point(at),"physical click stays inside the window: "+button.text)
	mouse(at,true)
	await create_timer(hold).timeout
	mouse(at,false)
	await frames(4)

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+name+".png")

func fresh(mode := "cell_test") -> void:
	if main.hud.menu.visible: main.hud.close_menu()
	main.start(mode); main.game.paused = false
	await frames(6)

func building(kind: String,point: Vector2) -> Dictionary:
	var e: Dictionary = main.game.spawn(kind,1,point,"building")
	e.complete = true; e.progress = 1; e.hp = e.maxHp
	return e

func stock(wood: float,food := 100.0) -> void:
	var fa: Dictionary = main.game.state.factions[0]
	fa.stock.wood = wood
	fa.food = [{"amount":food,"born":main.game.state.time,"stomachGlucose":food}]

func save_checks() -> void:
	await fresh()
	stock(123)
	main.hud.show_saves(); await frames(8)
	var row: HBoxContainer
	for node in main.hud.menu_body.get_children():
		if node is HBoxContainer and node.get_child(0).text == "槽位 1": row = node
	check(row != null,"manual save row exists")
	var save := named_button(row,"保存")
	var load_button := named_button(row,"读取")
	check(load_button.disabled and not FileAccess.file_exists(WarSave.path(1)),"first-time test slot starts empty and disabled")
	var instance := load_button.get_instance_id()
	await click(save,.22)
	check(FileAccess.file_exists(WarSave.path(1)) and not load_button.disabled,"physical first save immediately enables reading")
	check(load_button.get_instance_id() == instance and main.hud.menu.visible,"save updates the existing row without reopening the menu")
	await capture("save-enabled")
	stock(17)
	await click(load_button)
	check(not main.hud.menu.visible and is_equal_approx(main.game.economy.stock(1,"wood"),123),"physical read restores the saved value")
	await fresh("life")
	main.game.life.state().money = 777
	main.hud.show_saves(); await frames(8)
	for node in main.hud.menu_body.get_children():
		if node is HBoxContainer and node.get_child(0).text == "槽位 2": row = node
	await click(named_button(row,"保存"))
	main.hud.close_menu()
	await fresh()
	main.hud.show_saves(); await frames(8)
	for node in main.hud.menu_body.get_children():
		if node is HBoxContainer and node.get_child(0).text == "槽位 2": row = node
	var overview := [0]
	main.hud.overview_requested.connect(func(): overview[0] += 1)
	await click(named_button(row,"读取"))
	check(main.game.life.enabled() and int(main.game.life.state().money) == 777 and overview[0] == 1,"manual life slot restores its state through the whole-body overview entry")

func battlefield_checks() -> void:
	for mode in ["cell_test","fullbody","systemic","trachea_01"]:
		await fresh(mode)
		main.hud.show_battlefields(); await frames()
		var campaign: bool = main.game.is_campaign()
		check((named_button(main.hud.menu_body,"下一波") != null) == campaign,"wave action is campaign-only: "+mode)
		var autoplay := named_button(main.hud.menu_body,"开启挂机指挥")
		check((autoplay != null) == campaign,"autoplay action is campaign-only: "+mode)
		var isolate := named_button(main.hud.menu_body,"隔离右肺")
		check((isolate != null) == (mode == "systemic"),"lung isolation is systemic-only: "+mode)
		if mode == "systemic":
			await click(isolate)
			check(not main.hud.menu.visible and main.game.state.commands.any(func(c): return c.action == "isolate"),"visible lung action submits a real command")
		if campaign:
			await click(autoplay)
			check(main.game.state.campaign.autoplay and not main.hud.menu.visible,"physical autoplay toggles the current campaign")
	await fresh("trachea_01")
	main.game.state.campaign.event.status = "completed"
	main.hud.show_battlefields(); await frames()
	var wave := named_button(main.hud.menu_body,"下一波")
	check(wave.disabled and not wave.tooltip_text.is_empty(),"finished campaign explicitly disables its unavailable next wave")
	main.hud.close_menu()

func production_checks() -> void:
	await fresh()
	building("core",Vector2(104,112))
	var barracks := building("barracks",Vector2(112,112))
	stock(30)
	main.game.selected.assign([int(barracks.id)])
	main.hud.show_build(); await frames(8)
	var train := production_button("spear")
	check(main.game.paused,"production menu auto-pauses tactical time")
	await click(train)
	check(main.game.state.commands.size() == 1 and barracks.queue.is_empty(),"paused physical train queues an order without producing early")
	check(main.hud.production_feedback.text.contains("已排队") and main.hud.production_pending.text.contains("1 项"),"queued training feedback is visible inside the modal")
	await click(train)
	check(main.game.state.commands.size() == 2 and train.text.contains("待执行 2"),"repeated affordable training has visible pending count")
	await click(train)
	check(main.game.state.commands.size() == 2 and main.hud.production_feedback.text.contains("缺少") and main.hud.production_feedback.text.contains("预留"),"oversubscribed paused training gives clear resource feedback")
	check(is_equal_approx(main.game.economy.stock(1,"wood"),30),"UI reservations do not spend simulation resources while paused")
	await capture("production-pending")
	await click(named_button(main.hud.menu_body,"返回游戏"))
	check(not main.game.paused,"return restores the preceding running state")
	main.game.update(.15); await frames(5)
	check(main.game.state.commands.is_empty() and barracks.queue.size() == 2 and is_equal_approx(main.game.economy.stock(1,"wood"),0),"resume executes each queued training once and pays exact cost")
	main.hud._process(.2); await frames(5)
	var cancel: Button
	for row in main.hud._selection_rows:
		if row.production: cancel = row.button; break
	await expose(cancel)
	var id := cancel.get_instance_id()
	var first: Dictionary = barracks.queue[0]
	var at := cancel.get_global_rect().get_center()
	mouse(at,true)
	main.game.update(.4)
	await create_timer(.4).timeout
	check(is_instance_valid(cancel) and cancel.get_instance_id() == id and cancel.get_parent() == main.hud.orders_box,"queue countdown retains the pressed button across HUD refreshes")
	mouse(at,false); await frames(6)
	check(barracks.queue.size() == 1 and not barracks.queue.any(func(item): return is_same(item,first)),"release cancels the exact originally pressed queue item")
	check(is_equal_approx(main.game.economy.stock(1,"wood"),11),"physical cancel refunds the existing 75 percent policy once")
	await capture("queue-cancelled")
	main.game.economy.update(25)
	check(int(main.game.state.get("trained",0)) == 1 and barracks.queue.is_empty(),"remaining real production completes and spawns a trained cell")
	main.game.selected.clear(); main.hud._process(.2)
	check(main.hud.orders_box.get_child_count() == 0,"clearing selection removes old queue controls")

func research_checks() -> void:
	await fresh()
	var lab := building("lab",Vector2(110,112))
	main.game.selected.assign([int(lab.id)])
	stock(59)
	main.hud.show_build(); await frames(8)
	var research := production_button("tier2",true)
	await click(research)
	check(main.game.state.commands.is_empty() and main.hud.production_feedback.text.contains("缺少"),"unaffordable research reports its missing resource inside the menu")
	stock(60)
	await click(research)
	await click(research)
	check(main.game.state.commands.size() == 1 and main.hud.production_feedback.text.contains("研究已排队"),"duplicate paused research stays one command with explicit feedback")
	await capture("research-pending")
	await click(named_button(main.hud.menu_body,"返回游戏"))
	main.game.update(.15)
	check(lab.queue.size() == 1 and main.game.state.factions[0].researching == "tier2" and is_equal_approx(main.game.economy.stock(1,"wood"),0),"resume starts the real research and charges once")
	main.game.economy.update(71)
	check(main.game.state.factions[0].tech.get("tier2",false) and int(main.game.state.factions[0].tier) == 2,"resumed research completes through the real economy")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	WarSave.directory = "user://test-saves/bug-audit-ui-%d" % Time.get_ticks_usec()
	root.size = Vector2i(1440,900)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main); current_scene = main
	main.set_process(false)
	await save_checks()
	await battlefield_checks()
	await production_checks()
	await research_checks()
	var file := FileAccess.open(OUT+"ui-reliability.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"physicalWindowCoordinates":true,"isolatedSaveDirectory":WarSave.directory},"  "))
	print("UI RELIABILITY ",checks," checks, failures=",failures)
	main.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
