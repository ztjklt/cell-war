extends SceneTree
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("FAIL ",message)

func run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main: Node2D = scene.instantiate()
	scene = null
	root.add_child(main)
	current_scene = main
	root.size = Vector2i(1280,800)
	await process_frame
	main.hud._layout()
	var view: WarWorldView = main.world
	var sim: WarSimulation = main.game
	check(sim.mode == "systemic" and sim.paused and main.hud.home.visible,"default opens cover over prepared paused systemic battle")
	check(sim.selected.is_empty() and not view.visible and view.process_mode == Node.PROCESS_MODE_DISABLED,"cover clears selection and suspends the hidden map compositor")
	check(absf(main.camera.zoom.x-.28*32) < .00001,"original initial zoom")
	check(main.hud.systemic_panel.visible,"systemic controls are visible on initial entry")
	check(not view.art.has("heart"),"superseded heart art is not overlaid")
	check(view.art.reference.resource == "image/anatomy-reference/body-map-reference.png" or view.art.reference.resource.ends_with("reference.png"),"raw reference uses original bitmap")
	var max_error := 0.0
	for fixture in view.presentation.heart.oracle:
		view.heart.sample(float(fixture.time))
		for i in fixture.vertices.size():
			var expected := Vector2(fixture.vertices[i][0],fixture.vertices[i][1])
			max_error = maxf(max_error,view.heart.target[i].distance_to(expected))
			check(view.heart.target[i].distance_to(expected) < .0001,"Lua cardiac vertex at %s / %s" % [fixture.time,i])
			var authored := view.heart.source[i]*2+Vector2(0,512)
			check(view.heart.inverse(view.heart.forward(authored)).distance_to(authored) < .0005,"cardiac inverse hit mapping")
	for fixture in view.presentation.depthOracle:
		check(view.obscured({"vesselLane":fixture.lane},Vector2(fixture.x,fixture.y)) == fixture.hidden,"Lua crossing depth lane %s" % fixture.lane)
	for fixture in view.presentation.animationOracle:
		sim.state.time = float(fixture.time)+WarSimulation.STEP
		sim.accumulator = 0
		var pose := view.animation(fixture.entity,fixture.entity.has("deathTime"))
		check(pose.key == fixture.expected.key and int(pose.frame)+1 == int(fixture.expected.frame) and not pose.get("hidden",false) == bool(fixture.expected.visible),"Lua animation %s at %s" % [fixture.expected.key,fixture.time])
	for fixture in view.presentation.contactOracle:
		var actual := WarCellShape.contact(fixture.a,fixture.b)
		check(actual.is_empty() == fixture.contact.is_empty(),"Lua silhouette overlap")
		if not actual.is_empty() and not fixture.contact.is_empty():
			check(absf(float(actual[0])-float(fixture.contact[0])) < .0001 and (actual[1] as Vector2).distance_to(Vector2(fixture.contact[1],fixture.contact[2])) < .0001,"Lua silhouette contact normal and depth %s heading %s got %s expected %s" % [fixture.a.kind,fixture.a.get("weaponHeading",0),actual,fixture.contact])
	for fixture in view.presentation.commandLaneOracle:
		check(sim.navigation.command_lane(Vector2(fixture.x,fixture.y),fixture.kind,int(fixture.preferred)) == int(fixture.expected),"Lua command layer at %s,%s" % [fixture.x,fixture.y])
	for fixture in view.presentation.motionOracle:
		sim.accumulator = float(fixture.accumulator)
		var e := {"kind":"worker","category":"unit","x":101.0,"y":101.0,"previousX":100.0,"previousY":100.0,"renderTrail":[Vector2(100,100),Vector2(101,100),Vector2(101,101)]}
		check(view.unit_position(e).distance_to(Vector2(fixture.x,fixture.y)) < .00001,"Lua interpolation follows swept corner segments")
	sim.accumulator = 0
	var queued := {"id":999,"kind":"worker","orders":[],"orderToken":7,"cellShot":{"started":0}}
	sim.order(queued,{"kind":"move","x":1,"y":1},true)
	check(queued.orderToken == 7 and queued.has("cellShot"),"append preserves current action token and shot")
	view.layer = 1
	view._process(.375)
	check(absf(view.layer_weights[3]-.59) < .00001,"original smoothstep transition midpoint")
	var interrupted: Array = view.layer_weights.duplicate()
	view.layer = 3
	view._process(0)
	check(view.layer_weights == interrupted,"rapid mode switching is continuous")
	view.layer = 6
	view._process(.75)
	var orders_before := JSON.stringify(sim.snapshot())
	main._command(Vector2(500,400),false)
	check(JSON.stringify(sim.snapshot()) == orders_before,"original reference mode blocks gameplay commands")
	check(not main.has_node("WarCombatFX"),"no added combat particle overlay")
	DirAccess.make_dir_recursive_absolute("res://test-output")
	var file := FileAccess.open("res://test-output/presentation-parity.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"maxHeartSourceError":max_error,"oracle":"current Lua HeartDisplayTransform / CellAnimation / VesselChannelsArt","nativeVisualParityAccepted":false},"  "))
	print("PRESENTATION PARITY ",checks-failures.size(),"/",checks," max cardiac error ",max_error)
	main.queue_free()
	await process_frame
	call_deferred("quit",0 if failures.is_empty() else 1)
