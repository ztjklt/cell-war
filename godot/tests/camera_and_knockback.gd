extends SceneTree

var checks := 0
var failures: Array[String] = []
var main: Node2D

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("FAIL ",message)

func key(code: Key,pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func pan(codes: Array,dt := .1) -> Vector2:
	main.camera.position = Vector2(100,100)
	main.camera.zoom = Vector2.ONE*10
	main.camera_travel.reset()
	for code in codes: key(code,true)
	main._update_camera_controls(dt)
	for code in codes: key(code,false)
	return main.camera_travel.target_position-Vector2(100,100)

func settle() -> void:
	var began := Time.get_ticks_msec()
	while main.camera_travel.active and Time.get_ticks_msec()-began < 2500: await process_frame

func fresh(game: WarSimulation,kind := "virus") -> Array:
	game.start("cell_test")
	game.state.entities.clear()
	game.navigation.blockers.clear()
	var attacker := game.spawn("spear",1,Vector2(98,100))
	var victim := game.spawn(kind,2,Vector2(100,100))
	return [attacker,victim]

func hit(game: WarSimulation,a: Dictionary,b: Dictionary,cause := "attack",direction := Vector2.ZERO) -> Vector2:
	var before := WarData.point(b)
	game.combat.damage(a,b,1,true,cause,direction)
	game.combat.resolve_knockback()
	return WarData.point(b)-before

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main); current_scene = main
	main.set_process(false)
	main.start("cell_test") # Exercise battle controls, with the startup cover closed.
	main.game.paused = true
	await process_frame
	check(pan([KEY_W]).is_equal_approx(Vector2(0,-6)),"W pans up while paused")
	check(pan([KEY_A]).is_equal_approx(Vector2(-6,0)),"A pans left")
	check(pan([KEY_S]).is_equal_approx(Vector2(0,6)),"S pans down")
	check(pan([KEY_D]).is_equal_approx(Vector2(6,0)),"D pans right")
	check(pan([KEY_W,KEY_D]).is_equal_approx(Vector2(6,-6).normalized()*6),"diagonal pan keeps the same speed")
	check(pan([KEY_LEFT,KEY_DOWN]).is_zero_approx(),"arrows no longer move camera")
	check(main.command_mode.is_empty() and main.game.state.commands.is_empty(),"A/S do not issue attack or stop orders")
	main.focus(Vector2(100,100),20)
	key(KEY_D,true); main._update_camera_controls(.1); key(KEY_D,false)
	check(main.camera_travel.target_position.is_equal_approx(Vector2(103,100)),"pan speed stays constant in screen pixels across zoom levels")
	await settle()
	check(main.camera.position.is_equal_approx(Vector2(103,100)),"camera reaches the pan target after key release")
	main.focus(Vector2(3,3),10)
	key(KEY_A,true); main._update_camera_controls(.1); key(KEY_A,false)
	check(main.camera_travel.target_position.x == 3,"pan stops at map boundary")
	main.focus(Vector2(100,100),10)
	main.hud.inspection.mark(Vector2(100,100))
	key(KEY_Q,true); main._update_camera_controls(.2); key(KEY_Q,false)
	check(main.camera_travel.target_zoom > 10 and is_equal_approx(main.camera.zoom.x,10),"Q starts camera travel without an image jump")
	await settle()
	check(main.camera.zoom.x > 10,"Q zooms in")
	key(KEY_E,true); main._update_camera_controls(.2); key(KEY_E,false)
	await settle()
	check(is_equal_approx(main.camera.zoom.x,10),"E zooms out at matching rate")
	main.focus(Vector2(100,100),10)
	key(KEY_Q,true)
	for i in 10: main._update_camera_controls(.02)
	key(KEY_Q,false)
	check(is_equal_approx(main.camera_travel.target_zoom,20*exp(.44)),"held keyboard zoom destination is frame-rate independent")
	main.focus(Vector2(100,100),2.8*32)
	key(KEY_Q,true); main._update_camera_controls(.2); key(KEY_Q,false)
	check(is_equal_approx(main.camera_travel.target_zoom,2.8*32),"keyboard zoom respects maximum")
	main.focus(Vector2(100,100),main.minimum_zoom())
	key(KEY_E,true); main._update_camera_controls(.2); key(KEY_E,false)
	check(is_equal_approx(main.camera_travel.target_zoom,main.minimum_zoom()),"keyboard zoom respects minimum")
	main.hud.menu.show()
	check(pan([KEY_D]).is_zero_approx(),"menu blocks keyboard camera")
	main.hud.menu.hide()
	main.hud.wheel.show()
	check(pan([KEY_W]).is_zero_approx(),"command wheel blocks keyboard camera")
	main.hud.wheel.hide()
	main.hud.home.show()
	check(pan([KEY_A]).is_zero_approx(),"home blocks keyboard camera")
	main.hud.home.hide()
	key(KEY_CTRL,true)
	check(pan([KEY_A]).is_zero_approx(),"modifier shortcuts do not pan")
	key(KEY_CTRL,false)
	check(pan([]).is_zero_approx(),"release stops camera movement")

	var game := WarSimulation.new()
	for kind in WarData.config().Data.units:
		var pair := fresh(game,kind)
		var victim: Dictionary = pair[1]
		var lane := int(victim.vesselLane)
		var push := hit(game,pair[0],victim)
		check(push.x > 0 and is_zero_approx(push.y) and push.length() <= WarCombat.HIT_PUSH_MAX+.0001,"small backward hit for "+kind)
		check(int(victim.vesselLane) == lane,"hit preserves navigation lane for "+kind)
	var pair := fresh(game)
	var attacker: Dictionary = pair[0]
	var victim: Dictionary = pair[1]
	check(hit(game,victim,attacker).x < 0,"friendly cell also recoils away from virus")
	pair = fresh(game); attacker = pair[0]; victim = pair[1]
	check(hit(game,attacker,victim,"projectile",Vector2.DOWN).y > 0,"projectile uses impact travel direction")
	var p := WarData.point(victim)
	game.combat.damage({},victim,1,true,"poison")
	game.combat.resolve_knockback()
	check(WarData.point(victim) == p,"status damage does not repeatedly push")
	game.combat.damage(attacker,victim,0)
	game.combat.resolve_knockback()
	check(WarData.point(victim) == p,"zero damage does not push")
	pair = fresh(game); attacker = pair[0]; victim = pair[1]
	p = WarData.point(victim)
	for i in 20: game.combat.damage(attacker,victim,.01,true)
	game.combat.resolve_knockback()
	check(WarData.point(victim).distance_to(p) <= WarCombat.HIT_PUSH_MAX+.0001,"same-tick hits have capped total push")
	pair = fresh(game); attacker = pair[0]; victim = pair[1]
	victim.orders = [{"kind":"move","x":110,"y":100}]
	victim.path = [{"p":Vector2(110,100),"lane":0}]
	hit(game,attacker,victim)
	check(victim.path.is_empty() and victim.orders.size() == 1,"push replans path but preserves order")
	pair = fresh(game); attacker = pair[0]; victim = pair[1]
	var bystander := game.spawn("virus",2,Vector2(102,100))
	var before_distance := WarData.point(victim).distance_to(WarData.point(bystander))
	for i in 20: hit(game,attacker,victim)
	check(WarData.point(victim).distance_to(WarData.point(bystander)) < before_distance and WarCellShape.contact(victim,bystander).is_empty(),"repeated pushes stop against another unit without overlap")
	pair = fresh(game); attacker = pair[0]; victim = pair[1]
	attacker.x = 98.9
	attacker.kind = "worker"
	game.order(victim,{"kind":"hold"})
	p = WarData.point(victim)
	game.step(WarSimulation.STEP)
	check(victim.hp < victim.maxHp and WarData.point(victim).x > p.x,"real simulation tick applies melee damage and push")
	check(victim.renderTrail.size() > 1 and victim.previousX == p.x,"hit displacement joins interpolated render trail")
	check(game.combat._knockbacks.is_empty(),"tick consumes pending impulses")
	pair = fresh(game); attacker = pair[0]; victim = pair[1]
	p = WarData.point(victim)
	game.combat.launch(attacker,victim,1,WarData.spec("spear").projectile)
	game.combat.update_projectiles(.2)
	game.combat.resolve_knockback()
	check(victim.hp < victim.maxHp and WarData.point(victim).x > p.x,"real projectile collision damages and pushes target")
	pair = fresh(game); attacker = pair[0]; victim = pair[1]
	var building := game.spawn("store",2,Vector2(103,100),"building")
	game.navigation.blockers = [building]
	victim.x = 101.35
	p = WarData.point(victim)
	hit(game,attacker,victim)
	check(game._position_free(victim,WarData.point(victim)),"push cannot enter building")
	pair = fresh(game); attacker = pair[0]; victim = pair[1]
	building = game.spawn("store",2,Vector2(103,100),"building")
	p = WarData.point(building)
	hit(game,attacker,building)
	check(WarData.point(building) == p,"buildings do not recoil")
	pair = fresh(game); attacker = pair[0]; victim = pair[1]
	game.combat.damage(attacker,victim,victim.hp,true)
	game.combat.resolve_knockback()
	check(victim.hp == 0 and game.combat._knockbacks.is_empty(),"lethal hit leaves no pending living-unit push")
	pair = fresh(game); attacker = pair[0]; victim = pair[1]
	game.combat.damage(attacker,victim,1,true)
	game.start("cell_test")
	check(game.combat._knockbacks.is_empty(),"restart clears pending hits")
	pair = fresh(game,"worker"); attacker = pair[0]; victim = pair[1]
	var herpes := game.spawn("herpes",1,Vector2(98,104))
	victim.y = 104
	p = WarData.point(victim)
	hit(game,herpes,victim,"collision")
	check(WarData.point(victim).distance_to(p) > WarCombat.HIT_PUSH_MAX,"existing strong herpes collision remains stronger than normal hit")

	# Real authored organ edge: repeated hits stop at the exact source boundary.
	game.start("fullbody")
	var target: Dictionary = {}
	for e in game.units():
		if e.kind == "worker" and int(e.vesselLane) == 0: target = e; break
	check(not target.is_empty(),"authored organ target exists")
	if not target.is_empty():
		var start := WarData.point(target)
		var source := {"id":99999,"kind":"virus","faction":2,"x":start.x-1,"y":start.y}
		for i in 1000:
			game.combat.queue_knockback(source,target,Vector2.RIGHT)
			game.combat.resolve_knockback()
		check(game.navigation.clear_segment(start,WarData.point(target),0,target.kind),"repeated hits stay within original organ")
		check(not game.navigation.clear_segment(WarData.point(target),WarData.point(target)+Vector2(.05,0),0,target.kind) or not game._position_free(target,WarData.point(target)+Vector2(.05,0)),"hits stop at wall or occupied edge")
	game.dispose()
	print("CAMERA_AND_KNOCKBACK %d/%d" % [checks-failures.size(),checks])
	var main_game: WarSimulation = main.game
	main.queue_free()
	await process_frame
	main_game.dispose()
	quit(0 if failures.is_empty() else 1)
