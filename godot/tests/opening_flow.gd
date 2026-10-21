extends SceneTree
## New-life entry with its authored red cell/resources, through real window input.
## Only time/navigation scheduling and scroll exposure are driven by this test.
var main: Node2D
var failures: Array[String] = []
var checks := 0
var evidence: Array[Dictionary] = []
var accelerated_seconds := 0.0
const OUT := "res://test-output/opening-flow/"

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,message: String) -> bool:
	checks += 1
	if not value: failures.append(message); printerr("FAIL ",message)
	return value

func frames(count := 5) -> void:
	for i in count: await process_frame

func screen(point: Vector2) -> Vector2:
	return main.get_canvas_transform()*main.world.display_point(point)

func click(point: Vector2,button := MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.position = root.get_stretch_transform()*point
	event.button_index = button; event.pressed = true
	root.push_input(event)
	await process_frame
	event = event.duplicate(); event.pressed = false
	root.push_input(event)
	await frames()

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code; event.physical_keycode = code; event.pressed = true
	root.push_input(event)
	event = event.duplicate(); event.pressed = false
	root.push_input(event)

func named_button(parent: Node,text: String) -> Button:
	for node in parent.find_children("*","Button",true,false):
		if node.text == text and node.is_visible_in_tree(): return node
	return null

func press(button: Button) -> bool:
	if not check(button != null,"requested visible button exists"): return false
	var parent := button.get_parent()
	while parent != null:
		if parent is ScrollContainer: parent.ensure_control_visible(button)
		parent = parent.get_parent()
	await frames()
	var at := button.get_global_rect().get_center()
	if not check(root.get_visible_rect().has_point(at) and button.is_visible_in_tree() and not button.disabled,"window button is available: "+button.text): return false
	await click(at)
	await create_timer(.28).timeout
	return true

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+name+".png")

func stocks() -> Dictionary:
	return {"wood":main.game.economy.stock(1,"wood"),"food":main.game.economy.stock(1,"food")}

func record(stage: String,extra := {}) -> void:
	var item := {"stage":stage,"time":main.game.state.time,"stocks":stocks(),"population":str(main.game.economy.population(1)),"selected":main.game.selected.duplicate()}
	item.merge(extra)
	evidence.append(item)
	print("OPENING ",stage," ",JSON.stringify(item))

func advance(seconds: float) -> void:
	# Keep the original rules, paths, production, life clock and collision active.
	# main._process is suspended; this is accelerated simulation, not wall time.
	for i in ceili(seconds/.05):
		if main.game.paused: break
		main.game.navigation.update(10000)
		main.game.update(.05)
		accelerated_seconds += .05
		if i%20 == 0: await process_frame
	await frames()

func open_build() -> bool:
	if not await press(named_button(main.hud.root,"≡")): return false
	if not await press(named_button(main.hud.menu_body,"建设与生产")): return false
	return check(main.hud.menu.visible and main.game.paused,"actual menu opens construction/production and pauses")

func site_for(kind: String,worker: Dictionary) -> Vector2:
	# Read existing placement/navigation geometry to choose an accessible site.
	# This does not add terrain/resources or move the red cell into place.
	var start := WarData.point(worker)
	var site := Vector2.INF
	var distance := INF
	for dx in range(-20,21):
		for dy in range(-20,21):
			var p: Vector2 = main.game.economy.build_point(kind,start+Vector2(dx,dy))
			var d := start.distance_squared_to(p)
			if d < 9 or d >= distance: continue
			if not Rect2(360,220,680,440).has_point(screen(p)): continue
			if not main.game.navigation.point_allowed(p,0,"worker"): continue
			if not main.game.navigation.clear_segment(start,p,0,"worker"): continue
			if not main.game.navigation.movement_clear(start,p,"worker",1): continue
			if not main.game.economy.can_place(kind,p,main.game.selected): continue
			site = p; distance = d
	return site

func move_to(point: Vector2) -> bool:
	await click(screen(point),MOUSE_BUTTON_RIGHT)
	if not check(main.hud.wheel.visible,"physical right click opens the real command wheel"): return false
	await create_timer(.35).timeout
	var move: Button
	for button in main.hud.wheel.buttons:
		if button.action == "move": move = button; break
	if not await press(move): return false
	await create_timer(.4).timeout
	return check(main.game.state.commands.any(func(c): return c.get("kind","") == "move"),"actual move badge submits the selected cell's movement")

func check_initial_escape(worker: Dictionary) -> void:
	var start := WarData.point(worker)
	var organ: String = main.game.navigation.organ_at(start,"worker")
	var grid: WarGrid = main.game.navigation.grid(organ,WarNavigation.profile("worker"))
	var start_component := grid.component(start)
	var counts := {}
	var goal := Vector2.INF
	var distance := INF
	for i in grid.valid.size():
		if not grid.valid[i]: continue
		var component := int(grid.components[i])
		counts[str(component)] = int(counts.get(str(component),0))+1
		if component == start_component: continue
		var at := grid.position_of(i)
		var d := start.distance_squared_to(at)
		if d >= distance or not Rect2(360,220,680,440).has_point(screen(at)): continue
		goal = at; distance = d
	if not check(goal != Vector2.INF,"nearby main tissue offers a real destination outside the starting patch"): return
	if not await move_to(goal): return
	await advance(8)
	record("initial-red-move",{"start":str(start),"goal":str(goal),"actual":str(WarData.point(worker)),"startComponent":start_component,"componentGridCounts":counts,"orders":worker.orders.duplicate(true),"pathFailed":worker.get("pathFailed",false),"message":main.game.message})
	check(WarData.point(worker).distance_to(start) > 1,"the original red cell can leave its starting tissue patch")
	await capture("initial-red-move")

func build(kind: String,worker: Dictionary) -> Dictionary:
	await click(screen(WarData.point(worker)))
	if not check(main.game.selected == [int(worker.id)],"physical map click selects the original red cell for "+kind): return {}
	var site := site_for(kind,worker)
	if not check(site != Vector2.INF,"starting tissue has an accessible legal site for "+kind): return {}
	if not await open_build(): return {}
	var choice: Button
	for node in main.hud.menu_body.get_children():
		if node is Button and node.text.begins_with(str(WarData.spec(kind).name)+" ·"): choice = node; break
	if not await press(choice): return {}
	if not check(main.command_mode == "build:"+kind and not main.game.paused,"construction button arms placement and restores running time"): return {}
	await click(screen(site))
	if not check(main.game.state.commands.any(func(c): return c.action == "place" and c.building == kind),"physical tissue click submits original construction command: "+kind): return {}
	await advance(.15)
	var building: Dictionary = {}
	for entity in main.game.entities():
		if entity.faction == 1 and entity.kind == kind: building = entity; break
	if not check(not building.is_empty() and not building.complete,"real economy starts the paid construction: "+kind): return {}
	var began: float = main.game.state.time
	for i in ceili(float(WarData.spec(kind).time)+20):
		await advance(1)
		if building.complete or worker.hp <= 0 or main.game.paused: break
	record("built:"+kind,{"id":building.id,"site":str(site),"elapsed":float(main.game.state.time)-began,"complete":building.complete,"progress":building.progress,"workerOrders":worker.orders.duplicate(true),"workerPosition":str(WarData.point(worker)),"pathFailed":worker.get("pathFailed",false),"message":main.game.message})
	await capture("construction-"+kind)
	if not check(building.complete and worker.hp > 0,"the original red cell actually completes "+kind): return {}
	await capture("built-"+kind)
	return building

func train_button() -> Button:
	for entry in main.hud.production_buttons:
		if entry.kind == "spear" and not entry.research: return entry.button
	return null

func run_opening() -> void:
	await frames(12)
	if not check(main.hud.home.visible and main.game.paused,"normal startup begins on the paused cover"): return
	if not await press(main.hud.home.buttons[0]): return
	if not check(not main.hud.home.visible and main.game.life.enabled() and main.game.mode == "fullbody","physical cover start enters a genuine new life"): return
	var units: Array = main.game.units().filter(func(e): return e.faction == 1)
	if not check(units.size() == 1 and units[0].kind == "worker","new life retains exactly one authored red cell and zero white cells"): return
	var worker: Dictionary = units[0]
	check(stocks() == {"wood":160.0,"food":125.0},"original starting resources remain 160 protein and 125 glucose")
	check(not main.game.entities().any(func(e): return e.faction == 1 and e.kind in ["core","house","barracks"]),"start has no fabricated population or production building")
	check(main.game.economy.population(1) == Vector2i(1,0),"initial population needs a real capacity building")
	record("original-start",{"worker":worker.duplicate(true),"seed":main.game.state.seed})
	await capture("start-overview")
	await click(screen(WarData.point(worker)))
	for i in 6: key(KEY_Q)
	var began := Time.get_ticks_msec()
	while main.camera_travel.active and Time.get_ticks_msec()-began < 2500: await process_frame
	if not check(not main.camera_travel.active and main.camera.zoom.x > 10,"real map click and Q bring the starting tissue into view"): return
	await frames(12)
	await capture("starting-tissue")
	await check_initial_escape(worker)
	var core := await build("core",worker)
	if core.is_empty(): return
	check(main.game.economy.population(1) == Vector2i(1,10) and is_equal_approx(main.game.economy.stock(1,"wood"),95),"completed core opens ten population slots for its original 65 protein")
	var barracks := await build("barracks",worker)
	if barracks.is_empty(): return
	check(is_equal_approx(main.game.economy.stock(1,"wood"),55),"real barracks uses its original 40 protein")
	await click(screen(WarData.point(barracks)))
	if not check(main.game.selected == [int(barracks.id)],"physical map click selects the completed barracks"): return
	if not await open_build(): return
	if not await press(train_button()): return
	check(main.game.state.commands.any(func(c): return c.action == "train" and c.unit == "spear") and barracks.queue.is_empty(),"physical white-cell button queues a command in the paused menu")
	if not await press(named_button(main.hud.menu_body,"返回游戏")): return
	await advance(.2)
	if not check(barracks.queue.size() == 1 and barracks.queue[0].unit == "spear","resuming executes the first real white-cell training"): return
	check(is_equal_approx(main.game.economy.stock(1,"wood"),40) and is_equal_approx(main.game.economy.stock(1,"food"),113),"first training charges the authored 15 protein and 12 glucose")
	await advance(2)
	await create_timer(.2).timeout
	var cancel: Button
	for entry in main.hud._selection_rows:
		if entry.production: cancel = entry.button; break
	if not await press(cancel): return
	check(barracks.queue.is_empty() and not main.game.units().any(func(e): return e.faction == 1 and e.kind == "spear"),"actual queue cancellation removes production before any white cell exists")
	check(is_equal_approx(main.game.economy.stock(1,"wood"),51) and is_equal_approx(main.game.economy.stock(1,"food"),122),"cancel returns the existing 75 percent refund without added resources")
	record("cancelled-first-training")
	await capture("cancelled-training")
	if not await open_build(): return
	if not await press(train_button()): return
	if not await press(named_button(main.hud.menu_body,"返回游戏")): return
	await advance(.2)
	if not check(barracks.queue.size() == 1,"the same real button can restart the cancelled white-cell production"): return
	await advance(25)
	var white: Dictionary = {}
	for e in main.game.units():
		if e.faction == 1 and e.kind == "spear": white = e; break
	if not check(not white.is_empty() and barracks.queue.is_empty() and int(main.game.state.get("trained",0)) == 1,"unmodified production spawns the first white cell and consumes its queue"): return
	check(is_equal_approx(main.game.economy.stock(1,"wood"),36) and is_equal_approx(main.game.economy.stock(1,"food"),110),"whole opening including cancellation stays within original resources")
	record("first-white-cell",{"id":white.id,"position":str(WarData.point(white))})
	await click(screen(WarData.point(white)))
	if not check(main.game.selected == [int(white.id)],"physical map click selects the genuinely trained white cell"): return
	var start := WarData.point(white)
	var goal := Vector2.INF
	for distance in [4.0,5.0,3.0,2.0]:
		for i in 24:
			var p: Vector2 = start+Vector2.from_angle(TAU*i/24)*distance
			if not Rect2(360,220,680,440).has_point(screen(p)): continue
			if main.game.navigation.point_allowed(p,0,"spear") and main.game.navigation.clear_segment(start,p,0,"spear") and main.game.navigation.movement_clear(start,p,"spear",1): goal = p; break
		if goal != Vector2.INF: break
	if not check(goal != Vector2.INF,"first white cell has a legal nearby movement destination"): return
	if not await move_to(goal): return
	await advance(8)
	check(WarData.point(white).distance_to(goal) < .15 and WarData.point(white).distance_to(start) > start.distance_to(goal)-.2,"the trained white cell reaches its clicked tissue destination")
	record("newborn-moved",{"start":str(start),"goal":str(goal),"actual":str(WarData.point(white)),"lifePending":main.game.life.state().pending})
	await capture("newborn-moved")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	WarSave.directory = "user://test-saves/opening-flow-%d" % Time.get_ticks_usec()
	root.size = Vector2i(1440,900)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main); current_scene = main
	main.set_process(false)
	await run_opening()
	var file := FileAccess.open(OUT+"opening-flow.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"evidence":evidence,"acceleratedSimulationSeconds":accelerated_seconds,"physicalWindowInput":true,"testDriver":"main process suspended; fixed .05 simulation steps and navigation scheduling; geometry read for reachable sites; scroll controls exposed","injectedUnits":0,"injectedResources":0,"isolatedSaveDirectory":WarSave.directory},"  "))
	print("OPENING FLOW ",checks," checks, failures=",failures)
	main.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
