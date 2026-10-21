extends SceneTree
## Native, repeatable demonstration using ordinary navigation and simulation.
var main: Node2D
var samples: Array = []
var elapsed := 0.0
var ready := false
var captured := false
var font: Font

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1600,1000)
	root.title = "细胞战争 · 顺流 ×3 / 逆流 ×0.4 · Godot 实际移动"
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main); current_scene = main
	main.set_process(false)
	main.start("fullbody")
	main.game.state.entities = {}
	main.game.state.resources = {}
	main.game.state.influenzaColonies = {"version":1,"groups":{}}
	main.game.navigation.gates.clear()
	main.game.paused = true
	font = load("res://assets/fonts/MiSans-Regular.ttf")
	for lane in [14,10]:
		var points := PackedVector2Array()
		for point in WarData.read("vessels").lanes[lane-1].points: points.append(WarData.point(point))
		var center := 0
		for i in points.size():
			if absf(points[i].y-1580) < absf(points[center].y-1580): center = i
		var tangent := (points[mini(center+1,points.size()-1)]-points[maxi(0,center-1)]).normalized()
		for along in [true,false]:
			var offset := tangent.orthogonal()*(2.0 if along else -2.0)
			var start := points[center]+offset
			var target_index := center
			var sign := 1 if along else -1
			while target_index+sign >= 0 and target_index+sign < points.size() and points[target_index].distance_to(points[center]) < 38:
				target_index += sign
			var target := points[target_index]+offset
			if not main.game.navigation.point_allowed(start,lane,"worker") or not main.game.navigation.point_allowed(target,lane,"worker"):
				printerr("Preview point lacks certified vessel clearance: ",lane); quit(1); return
			var e: Dictionary = main.game.spawn("worker",1,start)
			if e.is_empty(): printerr("Preview cell could not spawn"); quit(1); return
			e.vesselLane = lane
			var label := Label.new()
			label.text = "顺流 ×3" if along else "逆流 ×0.4"
			label.add_theme_font_override("font",font)
			label.add_theme_font_size_override("font_size",19)
			label.add_theme_color_override("font_color",Color("126148") if along else Color("7b391b"))
			label.add_theme_color_override("font_shadow_color",Color.WHITE)
			label.add_theme_constant_override("shadow_offset_x",1)
			label.add_theme_constant_override("shadow_offset_y",1)
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			main.add_child(label)
			samples.append({"unit":e,"start":start,"target":target,"lane":lane,"along":along,"label":label,"offset":offset})
	main.focus(Vector2(997,1580),8.5)
	main.game.selected.clear()
	main.game.notify("左侧蓝管流向心脏 ↑ · 右侧红管流出心脏 ↓ · 相同红细胞，顺流 ×3 / 逆流 ×0.4 · 每 6 秒重放，空格暂停")
	reset()
	for sample in samples:
		var e: Dictionary = sample.unit
		while e.pathPending:
			main.game.navigation.update(20000)
		if e.pathFailed or e.path.is_empty(): printerr("Preview route failed: ",sample.lane); quit(1); return
		print("FLOW_PREVIEW_ROUTE lane=",sample.lane," downstream=",sample.along," waypoints=",e.path.size())
	if OS.get_cmdline_user_args().has("--verify"):
		for i in 20: main.game.step(.1)
		for sample in samples:
			var distance: float = WarData.point(sample.unit).distance_to(sample.start)
			if distance < (8.0 if sample.along else .7): printerr("Preview cell did not move: ",sample); quit(1); return
			print("FLOW_PREVIEW_MOVED lane=",sample.lane," downstream=",sample.along," distance=",distance)
		main.queue_free(); await process_frame; quit(); return
	# Warm the native compositor before beginning the visible comparison.
	var began := Time.get_ticks_msec()
	while Time.get_ticks_msec()-began < 3500: await process_frame
	main.game.paused = false
	ready = true
	process_frame.connect(advance)
	print("FLOW_PREVIEW_READY | native window | four live cells | repeat=6s")

func reset() -> void:
	elapsed = 0
	for sample in samples:
		var e: Dictionary = sample.unit
		e.x = sample.start.x; e.y = sample.start.y
		e.previousX = e.x; e.previousY = e.y; e.vesselLane = sample.lane
		main.game.order(e,{"kind":"move","x":sample.target.x,"y":sample.target.y,"lane":sample.lane})
		main.game.go(e,sample.target,0.0,.05,int(sample.lane))

func advance() -> void:
	if not ready or not is_instance_valid(main): return
	var delta := minf(root.get_process_delta_time(),.1)
	main.game.update(delta)
	main._update_camera_controls(delta)
	if not main.game.paused: elapsed += delta*main.game.speed
	if elapsed >= 6: reset()
	for sample in samples:
		var label: Label = sample.label
		label.scale = Vector2.ONE/main.camera.zoom.x
		var side: float = signf(sample.offset.x)
		label.position = WarData.point(sample.unit)+Vector2((14 if side > 0 else -110)/main.camera.zoom.x,-12/main.camera.zoom.x)
	if elapsed > 3 and not captured:
		captured = true
		call_deferred("capture")

func capture() -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://test-output")
	root.get_texture().get_image().save_png("res://test-output/blood-flow-preview.png")
