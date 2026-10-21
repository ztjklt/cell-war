extends SceneTree
var checks := 0
var failures: Array[String] = []

func check(value: bool,label: String) -> void:
	checks += 1
	if not value: failures.append(label); printerr("FAIL ",label)

func _initialize() -> void:
	call_deferred("run")

func fresh(game: WarSimulation,count := 5) -> Array:
	game.start("cell_test")
	game.state.entities.clear()
	game.navigation.blockers.clear()
	var result: Array = []
	for i in count: result.append(game.spawn("scout",1,Vector2(100+i*WarData.radius("scout")*WarPlatelets.SPACING,100)))
	return result

func run() -> void:
	var game := WarSimulation.new()
	var line := fresh(game)
	game.step(.1)
	for i in line.size():
		check(line[i].combatState == "defend","stationary platelet braces %d"%i)
		check(line[i].plateletLinks.size() == (1 if i in [0,line.size()-1] else 2),"automatic unbranched chain %d"%i)
	var tail: Dictionary = game.spawn("scout",1,WarData.point(line[-1])+Vector2(WarData.radius("scout")*WarPlatelets.SPACING,0))
	game.step(.1)
	check(tail.plateletLinks == [int(line[-1].id)] and line[-1].plateletLinks.size()==2,"new neighbor extends existing wall")
	var middle: Dictionary = line[2]
	game.order(middle,{"kind":"move","x":105.0,"y":104.0,"lane":0})
	check(middle.plateletLinks.is_empty() and not line[1].plateletLinks.has(int(middle.id)) and not line[3].plateletLinks.has(int(middle.id)),"move immediately releases both grips")
	game.platelets.update()
	check(middle.plateletLinks.is_empty(),"moving order cannot reconnect before arrival")
	line=fresh(game,4); game.platelets.update()
	game.combat.damage({},line[1],1000,true,"test")
	check(line[1].plateletLinks.is_empty() and line[0].plateletLinks.is_empty(),"death immediately releases both neighbors")
	game.platelets.update()
	check(line[0].plateletLinks.is_empty() and line[2].plateletLinks==[int(line[3].id)],"death opens a gap without bridging a missing body")
	line=fresh(game,2); line[1].faction=2; game.platelets.update()
	check(line[0].plateletLinks.is_empty(),"hostile platelet cannot join friendly wall")
	line[1].faction=1; line[1].vesselLane=5; game.platelets.update()
	check(line[0].plateletLinks.is_empty(),"projected proximity cannot connect different navigation lanes")
	line=fresh(game,2)
	var blocker:=game.spawn("store",2,WarData.point(line[0]).lerp(WarData.point(line[1]),.5),"building")
	game.navigation.blockers=[blocker]
	game.platelets.update()
	check(line[0].plateletLinks.is_empty(),"a building blocks hand-linking even on the same lane")
	line=fresh(game,3)
	var off_axis:=game.spawn("scout",1,WarData.point(line[1])+Vector2(0,WarData.radius("scout")*2.7))
	game.platelets.update()
	check(off_axis.plateletLinks.is_empty() and line[1].plateletLinks.size()==2,"no perpendicular branches")
	var source:=game.spawn("virus",2,Vector2(96,96))
	var linked_before:=WarData.point(line[1])
	game.combat.damage(source,line[1],1,true,"attack",Vector2.DOWN)
	game.combat.resolve_knockback()
	var linked_push:=WarData.point(line[1]).distance_to(linked_before)
	var lone:=game.spawn("scout",1,Vector2(110,100))
	var lone_before:=WarData.point(lone)
	game.combat.damage(source,lone,1,true,"attack",Vector2.DOWN)
	game.combat.resolve_knockback()
	var lone_push:=WarData.point(lone).distance_to(lone_before)
	var normal:=game.spawn("worker",1,Vector2(115,100))
	var normal_before:=WarData.point(normal)
	game.combat.damage(source,normal,1,true,"attack",Vector2.DOWN)
	game.combat.resolve_knockback()
	var normal_push:=WarData.point(normal).distance_to(normal_before)
	check(linked_push>0 and linked_push<lone_push*.4 and lone_push<normal_push*.4,"linked wall resists displacement more than lone platelet and ordinary cell")
	check(line[1].hp==line[1].maxHp-1 and line[1].cellHitStarted==game.state.time,"resistance does not suppress damage or reaction")
	var poses := {"plateletMove":16,"plateletConnect":12,"plateletDefend":12,"plateletHit":8,"plateletDeath":12}
	for key in poses:
		var clip: Dictionary = WarPlatelets.data().clips[key]
		check(clip.durations.size()==poses[key] and ResourceLoader.exists("res://assets/"+clip.path),"complete imported clip "+key)
	var e: Dictionary = line[0].duplicate(true)
	e.erase("cellHitStarted"); e.erase("plateletLinkStarted")
	check(WarPlatelets.sample(e,10,0,false).key=="plateletDefend","idle is defense")
	check(WarPlatelets.sample(e,10,1,false).key=="plateletMove","movement uses waddle")
	e.plateletLinkStarted=10.0
	check(WarPlatelets.sample(e,10.4,0,false).key=="plateletConnect","connection plays reaching transition")
	check(WarPlatelets.sample(e,11.2,0,false).key=="plateletDefend","connection settles into defensive loop")
	e.cellHitStarted=10.3
	check(WarPlatelets.sample(e,10.4,0,false).key=="plateletHit","impact interrupts connection")
	e.deathTime=10.35
	check(WarPlatelets.sample(e,10.4,0,true).key=="plateletDeath","death interrupts impact")
	check(WarPlatelets.sample(e,12,0,true).get("hidden",false),"death cannot resurrect")
	check(WarCellShape.pose(e,100,false).angle==0 and not WarCellShape.pose(e,100,false).mirror,"platelet artwork remains upright")
	line=fresh(game,3)
	game.selected.assign(line.map(func(unit): return int(unit.id)))
	game.issue("move",Vector2(110,105))
	game.step(.1)
	var destinations: Array = line.map(func(unit): return Vector2(unit.orders[0].x,unit.orders[0].y))
	check(is_equal_approx(destinations[0].y,destinations[1].y) and is_equal_approx(destinations[1].y,destinations[2].y),"group command assigns one defensive line")
	for i in 160:
		game.navigation.update(10000)
		game.step(.1)
		if line.all(func(unit): return unit.orders.is_empty()): break
	game.step(.1) # Finish the arrival tick before checking the stationary state.
	check(line.all(func(unit): return unit.orders.is_empty()) and line[1].plateletLinks.size()==2,"real movement arrives and automatically connects")
	var saved:=game.snapshot()
	check(WarSave.validate(saved).is_empty(),"platelet wall saves through existing schema")
	game.restore(saved)
	check(game.entity(int(line[1].id)).plateletLinks.size()==2,"load reconstructs valid links from positions")
	game.dispose()
	if OS.get_cmdline_user_args().has("--capture"):
		var main: Node2D = load("res://scenes/main.tscn").instantiate()
		root.add_child(main); current_scene=main
		root.size=Vector2i(1440,900)
		main.set_process(false); main.set_process_unhandled_input(false)
		main.start("cell_test")
		var cells:=fresh(main.game,5)
		main.game.state.time=5.0
		main.game.platelets.update()
		for cell in cells: cell.plateletLinkStarted=0.0
		main.game.selected.assign(cells.map(func(cell): return int(cell.id)))
		main.game.paused=true
		main.camera.position=Vector2(102.5,100)
		main.camera.zoom=Vector2.ONE*128
		main.camera.force_update_scroll()
		var began:=Time.get_ticks_msec()
		var path: String = WarPlatelets.data().clips.plateletDefend.path
		while main.world.textures.get_texture(path)==null and Time.get_ticks_msec()-began<10000: await process_frame
		check(main.world.textures.get_texture(path)!=null,"native wall renderer loads defense atlas")
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://test-output")
		root.get_texture().get_image().save_png("res://test-output/platelets-native.png")
		main.game.combat.damage({},cells[2],1,true,"test")
		main.game.state.time+=.24
		path=WarPlatelets.data().clips.plateletHit.path
		began=Time.get_ticks_msec()
		while main.world.textures.get_texture(path)==null and Time.get_ticks_msec()-began<10000: await process_frame
		check(main.world.textures.get_texture(path)!=null,"native renderer loads stable-grip hit atlas")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://test-output/platelets-hit-native.png")
		var owned: WarSimulation = main.game
		main.queue_free(); await process_frame; owned.dispose()
	DirAccess.make_dir_recursive_absolute("res://test-output")
	var output:=FileAccess.open("res://test-output/platelets.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures,"linkedPush":linked_push,"lonePush":lone_push,"ordinaryPush":normal_push},"  "))
	print("PLATELETS ",checks-failures.size(),"/",checks)
	quit(0 if failures.is_empty() else 1)
