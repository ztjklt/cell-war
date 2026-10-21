extends SceneTree
var failures: Array[String] = []
var checks := 0
var main: Node2D

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("FAIL ",message)

func click(at: Vector2,button := MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = root.get_stretch_transform()*at
	event.pressed = true
	root.push_input(event)
	event = event.duplicate(); event.pressed = false
	root.push_input(event)
	await process_frame

func option(action: String) -> WarCommandButton:
	for btn in main.hud.wheel.buttons:
		if btn.action == action: return btn
	return null

func choose(action: String) -> void:
	await create_timer(.35).timeout
	var btn := option(action)
	check(btn != null,"option exists: "+action)
	if btn != null:
		var start := btn.position
		await click(btn.get_global_rect().get_center())
		if main.hud.wheel.committing:
			if action == "move":
				var count: int = main.game.state.commands.size()
				main.hud.wheel._choose(action)
				check(main.game.state.commands.size() == count,"confirmation animation blocks duplicate orders")
				await create_timer(.12).timeout
				check(btn.position.distance_to(start) > 1,"chosen badge travels toward the original target")
				check(main.hud.wheel.buttons.any(func(other): return other != btn and other.modulate.a < .5),"other options retire together during confirmation")
				await create_timer(.26).timeout
			else: await create_timer(.38).timeout

func frames(count := 5) -> void:
	for i in count: await process_frame

func run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	main = scene.instantiate(); scene = null
	root.add_child(main); current_scene = main
	main.set_process(false)
	main.start("systemic")
	main.game.paused = true
	await frames()
	var wheel: WarCommandWheel = main.hud.wheel
	var anchor := Vector2(760,440)
	var expected: Vector2 = main.world.command_point(main.get_canvas_transform().affine_inverse()*anchor)
	var ids: Array = main.game.selected.duplicate()
	await click(anchor)
	check(not wheel.visible and not main.hud.inspection.has_point,"left ground click does not choose a camera coordinate")
	await click(anchor,MOUSE_BUTTON_RIGHT)
	check(wheel.visible,"right ground click opens wheel after selection")
	check(wheel.buttons[0].modulate.a < 1,"wheel starts with staggered reveal rather than appearing fully formed")
	check(main.game.state.commands.is_empty(),"opening does not issue an order")
	check(main.game.selected == ids,"opening preserves the selected cells")
	check(not wheel.buttons[0]._has_point(Vector2.ZERO) and wheel.buttons[0]._has_point(wheel.buttons[0].size*.5),"hexagonal control excludes rectangular corners from input")
	await choose("move")
	check(not wheel.visible and main.game.state.commands.size() == 1,"second physical click submits exactly one order and closes")
	check(main.hud.root.get_children().any(func(child): return child is WarOrderPulse),"confirmation creates a short UI pulse at the selected target")
	if not main.game.state.commands.is_empty():
		var command: Dictionary = main.game.state.commands[0]
		check(command.kind == "move" and Vector2(command.x,command.y).distance_to(expected) < .0001,"move keeps original ground coordinate rather than option coordinate")
		check(command.ids == ids and main.game.paused,"order snapshots selection and respects tactical pause")
	main.game.state.commands.clear()
	await click(anchor,MOUSE_BUTTON_RIGHT)
	check(wheel.visible,"right click also opens the wheel")
	await click(Vector2(480,310))
	check(not wheel.visible and main.game.state.commands.is_empty(),"outside click cancels without click-through orders")
	main._open_wheel(anchor,false)
	var escape := InputEventKey.new(); escape.keycode = KEY_ESCAPE; escape.pressed = true
	root.push_input(escape)
	await process_frame
	check(not wheel.visible and main.game.selected == ids,"Escape closes while preserving selection")
	for action in ["attackmove","guard","retreat","stop"]:
		main._open_wheel(anchor,true)
		await choose(action)
		check(main.game.state.commands.size() == 1 and main.game.state.commands[0].kind == action,"real order dispatched: "+action)
		if not main.game.state.commands.is_empty(): check(main.game.state.commands[0].append,"queued order retains append mode: "+action)
		main.game.state.commands.clear()
	main.start("trachea_01"); main.game.paused = true
	await frames()
	main._open_wheel(anchor,false)
	check(option("build_menu") == null,"campaign never advertises prohibited building")
	wheel.close()
	main.start("sandbox"); main.game.paused = true
	main.hud._action("worker")
	main.game.state.factions[0].stock.wood = 1000
	await frames()
	var worker: Dictionary = main.game.entity(main.game.selected[0])
	var site := Vector2.ZERO
	for dx in range(5,26,3):
		for dy in range(5,26,3):
			var candidate: Vector2 = main.game.economy.build_point("store",WarData.point(worker)+Vector2(dx,dy))
			if main.game.economy.can_place("store",candidate,main.game.selected): site = candidate; break
		if site != Vector2.ZERO: break
	check(site != Vector2.ZERO,"fixture finds genuinely buildable terrain")
	main.focus(site,22); main.camera.force_update_scroll()
	main._open_wheel(main.get_canvas_transform()*site,false)
	check(option("build_menu") != null,"red cell has construction option")
	await choose("build_menu")
	check(wheel.visible and wheel.page == 0 and main.game.state.commands.is_empty(),"build opens submenu without spending or placing")
	check(option("place:store") != null,"submenu uses actual game buildings")
	await choose("next")
	check(wheel.page == 1 and option("place:range").disabled,"tech-locked buildings are disabled")
	await choose("next")
	check(wheel.page == 2,"all fourteen building recipes remain reachable")
	await choose("next")
	var count: int = main.game.entities().size()
	await choose("place:store")
	check(not wheel.visible and main.game.state.commands.size() == 1,"construction selection submits a real place command")
	if not main.game.state.commands.is_empty():
		var command: Dictionary = main.game.state.commands[0]
		check(command.action == "place" and command.building == "store" and WarData.point(command).distance_to(site) < .0001,"construction keeps original snapped target: %s / expected %s / captured %s" % [WarData.point(command),site,wheel.target_world])
	main.game.step(.1)
	check(main.game.entities().size() == count+1,"native economy actually creates the selected building")
	check(not worker.orders.is_empty() and worker.orders[0].kind == "build","worker receives native construction order")
	main.game.state.commands.clear()
	main._open_wheel(anchor,false)
	main.game.selected.clear()
	await frames()
	check(not wheel.visible,"changing selection invalidates an open menu")
	main.start("fullbody"); main.game.paused = true
	main.hud._action("worker")
	var resource_key: String = main.game.state.resources.keys()[0]
	var resource: Dictionary = main.game.state.resources[resource_key]
	site = WarData.point(resource)
	main.focus(site,20); main.camera.force_update_scroll()
	main._open_wheel(main.get_canvas_transform()*main.world.display_point(site),false)
	check(option("harvest") != null,"resource target exposes harvesting for red cells")
	await choose("harvest")
	check(not main.game.state.commands.is_empty() and main.game.state.commands[0].action == "unit_order" and main.game.state.commands[0].order.resource == resource_key,"harvesting submits actual resource identity")
	main.game.state.commands.clear()
	main.start("lung_skirmish"); main.game.paused = true
	var target: Dictionary = main.game.entity(int(main.game.state.lungSkirmish.enemies[0]))
	main.camera.force_update_scroll()
	main._open_wheel(main.get_canvas_transform()*main.world.display_point(WarData.point(target)),false)
	check(option("attack") != null,"enemy target exposes explicit attack")
	await choose("guard")
	check(main.game.state.commands[0].kind == "guard" and main.game.state.commands[0].target == 0,"explicit guard is not silently replaced by attack")
	main.game.state.commands.clear()
	for dimensions in [Vector2i(1280,800),Vector2i(360,780),Vector2i(430,932)]:
		root.size = dimensions
		await frames()
		var view := root.get_visible_rect().size
		for at in [Vector2.ONE,Vector2(view.x-1,1),view-Vector2.ONE,Vector2(1,view.y-1)]:
			main._open_wheel(at,false)
			await create_timer(.35).timeout
			var fits := true
			var overlap := false
			for i in wheel.buttons.size():
				var rect := wheel.buttons[i].get_global_rect()
				fits = fits and Rect2(Vector2.ZERO,view).encloses(rect)
				for j in range(i+1,wheel.buttons.size()): overlap = overlap or rect.intersects(wheel.buttons[j].get_global_rect())
			check(fits and not overlap,"options fit without overlap at edge %s / %s" % [dimensions,at])
			check(wheel.target_world == main.world.command_point(main.get_canvas_transform().affine_inverse()*at),"edge avoidance preserves ground target")
			wheel.close()
	main._open_wheel(Vector2(180,390),false)
	main.hud.toggle_menu()
	check(not wheel.visible and main.hud.menu.visible,"pause modal dismisses wheel")
	check(not main.hud.root.get_node("Bottom").visible,"full-width bottom command dock removed")
	check(main.hud.battle.left.visible == false,"campaign no longer duplicates bottom selection pad")
	var panel := WarUISkin.panel()
	check(main.hud.panel.get_node("_FacetSurface") is WarFacetSurface,"selection card has a real polygonal face renderer")
	check(WarFacetSurface.vertices(Rect2(0,0,94,80),14,true).size() == 6,"command surface retains six planar sides")
	check(WarFacetSurface.outline(Rect2(0,0,94,80),14,true).size() > 24,"corners use sampled circular arcs rather than sharp vertices")
	check(main.hud.resource_values.oxygen.caption.text == "氧气量" and main.hud.resource_values.food.caption.text == "葡萄糖量","resource labels omit organ prefixes")
	for text in ["移动进攻驻守撤退停止建造","氧气葡萄糖蛋白质"]:
		var supported := true
		for i in text.length(): supported = supported and (WarUISkin.BUTTON.has_char(text.unicode_at(i)) or WarUISkin.BODY.has_char(text.unicode_at(i)))
		check(supported,"packaged fonts cover "+text)
	DirAccess.make_dir_recursive_absolute("res://test-output")
	var file := FileAccess.open("res://test-output/radial-commands.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"physicalClicks":true,"usesNativeEconomy":true},"  "))
	print("RADIAL COMMANDS ",checks-failures.size(),"/",checks)
	main.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
