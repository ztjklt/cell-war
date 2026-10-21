extends "res://tests/opening_flow.gd"
## Original red/resources, paid buildings and physical clicks through two harvests.
const FARM_OUT := "res://test-output/farming-ui/"

func option(action: String) -> Button:
	for button in main.hud.wheel.buttons:
		if button.action == action: return button
	return null

func snapshot_ui(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await create_timer(.8).timeout # Let the HUD's animated resource counters settle.
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(FARM_OUT+name+".png")

func place_at(kind: String,at: Vector2) -> Dictionary:
	if not await open_build(): return {}
	var choice: Button
	for node in main.hud.menu_body.get_children():
		if node is Button and node.text.begins_with(str(WarData.spec(kind).name)+" ·"): choice = node; break
	if not await press(choice): return {}
	await click(screen(at))
	if not check(main.game.state.commands.any(func(c): return c.action == "place" and c.building == kind),"real placement click queues "+kind): return {}
	var result: Dictionary = {}
	for i in 70:
		await advance(1)
		for entity in main.game.entities():
			if entity.faction == 1 and entity.kind == kind: result = entity; break
		if not result.is_empty() and result.complete: break
	record("construction:"+kind,{"building":result,"workers":main.game.units().filter(func(e): return e.kind == "worker")})
	check(not result.is_empty() and result.complete,"original red completes paid "+kind)
	check(not result.is_empty() and WarData.point(result).distance_to(at) < .001,"screen coordinate roundtrip preserves the chosen grid site: "+kind)
	return result

func open_farm(red: Dictionary,farm: Dictionary) -> void:
	main.game.selected.assign([int(red.id)])
	await click(screen(WarData.point(farm)),MOUSE_BUTTON_RIGHT)
	await create_timer(.35).timeout
	check(main.hud.wheel.visible and main.hud.wheel.context.target == int(farm.id),"real right click targets the cultivation bed")

func exercise() -> void:
	var red: Dictionary = main.game.units().filter(func(e): return e.faction == 1)[0]
	check(main.game.units().size() == 1 and red.kind == "worker" and stocks() == {"wood":160.0,"food":125.0},"start keeps the original single red and starting resources")
	main.focus(main.world.display_point(Vector2(990,1906)),22)
	await frames(12)
	await click(screen(WarData.point(red)))
	check(main.game.selected == [int(red.id)],"physical click selects the original red")
	if not await move_to(Vector2(994,1907.5)): return
	await advance(8)
	var store := await place_at("store",Vector2(985,1906))
	if store.is_empty() or not store.complete: return
	if not await move_to(Vector2(983,1905.7716)): return
	await advance(12)
	check(WarData.point(red).distance_to(Vector2(983,1905.7716)) < .1,"original red walks to the farming approach")
	var farm := await place_at("farm",Vector2(984,1904))
	if farm.is_empty() or not farm.complete: return
	check(is_equal_approx(main.game.economy.stock(1,"wood"),115),"store and farm charge their real 30 and 15 protein")
	if not await press(main.hud.pause_button): return
	check(main.game.paused,"physical pause button freezes the cultivation order")
	await open_farm(red,farm)
	if not check(option("farm") != null,"completed friendly cultivation bed offers a visible cultivation command"): return
	await snapshot_ui("cultivate-command")
	# Time was paused through the real toolbar before opening the command wheel.
	if not await press(option("farm")): return
	await create_timer(.4).timeout
	check(main.game.state.commands.any(func(c): return c.get("kind","") == "farm" and int(c.get("target",0)) == int(farm.id) and c.ids == [int(red.id)]),"actual cultivation badge queues its original target for the selected red")
	check(red.orders.is_empty() and float(farm.get("harvest",0)) == 0,"paused click neither farms nor changes current orders")
	if not await press(main.hud.pause_button): return
	check(not main.game.paused,"physical continue button executes the queued cultivation")
	var before: float = main.game.economy.stock(1,"food")
	for i in 80:
		await advance(1)
		if main.game.economy.stock(1,"food") >= before+16: break
	check(main.game.economy.stock(1,"food") >= before+16,"physical command completes two real glucose harvest and delivery cycles")
	check(float(main.game.state.get("farmed",0)) >= 16 and red.orders[0].kind == "farm","cultivation persists after its first delivery")
	check(main.game.economy.stomach_glucose(1) == 0,"cultivation does not counterfeit stomach glucose provenance")
	check(main.game.units().size() == 1 and main.game.economy.stock(1,"wood") == 115,"successful farming adds neither cells nor free protein")
	record("two-clicked-cultivation-deliveries",{"farm":int(farm.id),"red":red.duplicate(true)})
	await snapshot_ui("glucose-delivered")
	# Explicit state fixtures below exercise stale/invalid menu targets, after the
	# independent original-start production sequence above has already succeeded.
	main.game.paused = true
	farm.hp -= 1
	await open_farm(red,farm)
	check(option("farm") != null and option("repair") != null,"damaged completed bed retains both repair and cultivation choices")
	main.hud.wheel.close(); farm.hp = farm.maxHp
	farm.complete = false
	await open_farm(red,farm)
	check(option("farm") == null and option("build") != null,"unfinished bed offers construction instead of cultivation")
	main.hud.wheel.close(); farm.complete = true
	await open_farm(red,farm)
	farm.faction = 2
	var queued: int = main.game.state.commands.size()
	if await press(option("farm")):
		check(main.game.state.commands.size() == queued and main.hud.wheel.visible and main.hud.wheel.feedback_error,"target captured after the wheel opened rejects the stale click")
	main.hud.wheel.close(); farm.faction = 1
	main.game.order(red,{"kind":"farm","target":store.id})
	var paid := stocks(); var old_hp: float = store.hp
	main.game.economy.construct(red,red.orders[0],1)
	check(red.orders.is_empty() and stocks() == paid and store.hp == old_hp,"invalid farm order cannot silently turn into repair or charge protein")
	main.game.order(red,{"kind":"farm","target":farm.id}); farm.faction = 2
	var harvest: float = farm.get("harvest",0)
	main.game.economy.construct(red,red.orders[0],1)
	check(red.orders.is_empty() and float(farm.get("harvest",0)) == harvest and stocks() == paid,"executing a farm order rechecks target ownership")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(FARM_OUT)
	WarSave.directory = "user://test-saves/farming-ui-%d" % Time.get_ticks_usec()
	root.size = Vector2i(1440,900)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main); current_scene = main
	main.set_process(false); main.start("life"); main.game.paused = false
	await exercise()
	FileAccess.open(FARM_OUT+"farming-ui.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"evidence":evidence,"physicalWindowInput":true,"scope":"original red/resources; actual move, paid store/farm construction, cultivation and two deliveries; final negative cases explicitly mutate bed ownership/condition","injectedUnits":0,"injectedResources":0,"isolatedSaveDirectory":WarSave.directory},"  "))
	print("FARMING UI ",checks," checks, failures=",failures)
	main.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
