extends "res://tests/opening_flow.gd"
## HUD fixtures deliberately change station stock/occupation, not opening balance.
const UI_OUT := "res://test-output/organ-resource-ui/"

func capture_ui(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(UI_OUT+name+".png")

func wheel_option(action: String) -> Button:
	for button in main.hud.wheel.buttons:
		if button.action == action: return button
	return null

func run() -> void:
	DirAccess.make_dir_recursive_absolute(UI_OUT)
	WarSave.directory = "user://test-saves/organ-resource-ui-%d" % Time.get_ticks_usec()
	root.size = Vector2i(1440,900)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main); current_scene = main
	main.set_process(false); main.start("life"); main.game.paused = true
	var resource: Dictionary = main.game.state.resources["small_intestine.wood"]
	var worker: Dictionary = main.game.units().filter(func(e): return e.faction == 1)[0]
	main.focus(main.world.display_point(WarData.point(resource)),18)
	await frames(12)
	await click(screen(WarData.point(worker)))
	check(main.game.selected == [int(worker.id)],"physical map click selects the red cell in the resource fixture")
	resource.amount = 0; resource.contested = false
	await click(screen(WarData.point(resource)),MOUSE_BUTTON_RIGHT)
	await create_timer(.35).timeout
	check(main.hud.wheel.visible and main.hud.wheel.context.resource == resource.id,"empty renewable station remains an actual wheel target")
	check(wheel_option("harvest") != null,"empty station still offers a harvest badge")
	var info: String = main.hud.wheel.feedback.text
	check(info.contains("肠道蛋白站") and info.contains("小肠") and info.contains("站内库存 0 / 300"),"wheel identifies station, organ and empty stock")
	check(info.contains("安全补充中") and info.contains("每秒恢复 1.0") and info.contains("空站可等候"),"wheel explains regeneration and waiting at empty stations")
	check(root.get_visible_rect().encloses(main.hud.wheel.feedback.get_global_rect()),"expanded station feedback remains inside the desktop window")
	await capture_ui("empty-station-wheel")
	if await press(wheel_option("harvest")):
		await create_timer(.4).timeout
		check(main.game.state.commands.any(func(c): return c.action == "unit_order" and c.order.kind == "harvest" and c.order.resource == resource.id),"actual empty-station harvest passes through main and queues its real command")
		check(not main.hud.wheel.visible,"confirmed renewable harvest closes the wheel normally")
	main.game.paused = false; main.game.update(.15); main.game.paused = true
	check(not worker.orders.is_empty() and worker.orders[0].kind == "harvest" and worker.orders[0].resource == resource.id,"real simulation accepts the persistent renewable assignment")
	main.hud._process(.2); await frames()
	check(main.hud.details.text.contains("肠道蛋白站") and main.hud.details.text.contains("心脏补给点"),"selected courier names its station and fallback delivery destination")
	var core: Dictionary = main.game.spawn("core",1,Vector2(981.5,1905.5),"building")
	core.complete = true; core.progress = 1; core.hp = core.maxHp
	main.hud._process(.2); await frames()
	check(main.hud.details.text.contains("装满后运往 → 小肠 · 核心胞巢"),"selected courier reports the same-organ depot chosen by real economy")
	worker.cargo = {"wood":14.0}; worker.delivering = true
	main.hud._process(.2); await frames()
	check(main.hud.details.text.contains("运输中 → ") and main.hud.details.text.contains("蛋白质 · 14"),"loaded courier distinguishes transport in progress from future delivery")
	worker.cargo.clear(); worker.delivering = false
	await click(screen(WarData.point(resource)),MOUSE_BUTTON_RIGHT)
	await create_timer(.35).timeout
	resource.contested = true
	await frames()
	check(main.hud.wheel.feedback.text.contains("敌军占用 · 已停工") and wheel_option("harvest") != null,"occupation is shown without removing the persistent harvest option")
	await capture_ui("occupied-station-wheel")
	key(KEY_ESCAPE); await frames()
	await click(screen(WarData.point(resource)+Vector2(2.4,0)),MOUSE_BUTTON_RIGHT)
	check(main.hud.wheel.visible and str(main.hud.wheel.context.resource).is_empty(),"station click radius remains 2.2 rather than its transparent art canvas")
	key(KEY_ESCAPE); await frames()
	await press(named_button(main.hud.root,"≡"))
	await press(named_button(main.hud.menu_body,"器官补给与运输"))
	check(main.hud.menu.visible and main.game.paused,"actual menu exposes the paused resource and transport guide")
	check(main.hud.resource_station_labels.size() == WarOrganResources.data().sources.size(),"resource overview includes every configured station")
	check(main.hud.resource_station_labels[resource.id].text.contains("敌军占用 · 已停工"),"resource overview shares current occupation status")
	await capture_ui("resource-overview")
	await press(named_button(main.hud.menu_body,"观察 · 小肠肠道蛋白站"))
	check(not main.hud.menu.visible and main.camera.position.distance_to(main.world.display_point(WarData.point(resource))) < .1,"actual observe button focuses the selected station")
	check(main.hud.resource_values.wood.card.tooltip_text.contains("已运抵补给点"),"banked resource counter is distinguished from station and carried stock")
	var output := {"checks":checks,"failures":failures,"physicalWindowInput":true,"fixture":"new-life UI fixture; empty/contested flags, one completed local core and carried cargo are explicitly supplied for display checks; camera/scroll framing driven by test; independent opening_flow has no injected units/resources","isolatedSaveDirectory":WarSave.directory}
	FileAccess.open(UI_OUT+"organ-resource-ui.json",FileAccess.WRITE).store_string(JSON.stringify(output,"  "))
	print("ORGAN RESOURCE UI ",checks," checks, failures=",failures)
	main.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
