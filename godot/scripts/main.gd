extends Node2D
var game := WarSimulation.new()
var world: WarWorldView
var camera: Camera2D
var hud: WarHUD
var command_mode := ""
var drag_button := 0
var drag_start := Vector2.ZERO
var drag_current := Vector2.ZERO
var dragging := false
var drag_box := false
var autosave_at := 360.0
var overlay: Node2D
var audio: WarAudio
var overview_active := false
var infection_preview: WarInfectionPreview
var map_frame: WarDeskMapFrame
var camera_travel: WarCameraTravel
var desk_layer: CanvasLayer
var settings := WarSettings.new()

func _ready() -> void:
	settings.load_from_disk()
	settings.apply(get_window())
	# The world-space paper clip has a fractional origin. GUI pixel snapping
	# rounds it before camera zoom, displacing the map by up to half a world unit.
	get_viewport().gui_snap_controls_to_pixels = false
	# Keep fonts, controls and input in the same stretched canvas coordinates.
	# Portrait uses the existing phone layout rather than a compressed desktop HUD.
	_update_content_scale()
	get_window().size_changed.connect(_update_content_scale)
	desk_layer = load("res://scenes/command_backdrop.tscn").instantiate()
	add_child(desk_layer)
	camera = Camera2D.new()
	camera.position_smoothing_enabled = false
	add_child(camera)
	camera_travel = WarCameraTravel.new()
	camera_travel.camera = camera
	camera_travel.update_frame = _camera_map_offset
	add_child(camera_travel)
	camera_travel.reset()
	map_frame = WarDeskMapFrame.new()
	map_frame.name = "LiveDeskMap"
	map_frame.z_index = -10
	add_child(map_frame)
	map_frame.desk_projection_changed.connect(_apply_desk_projection)
	world = load("res://scenes/world.tscn").instantiate()
	world.z_index = 0
	map_frame.add_child(world)
	world.setup(game,camera)
	world.show_paths = settings.show_paths()
	map_frame.bind_world(world,camera)
	audio = WarAudio.new()
	add_child(audio)
	hud = WarHUD.new()
	add_child(hud)
	hud.setup(game,world,camera)
	hud.command_mode_changed.connect(func(kind): command_mode = kind; game.notify("点击地图选择目标 · Esc 取消"))
	hud.focus_requested.connect(focus)
	hud.overview_requested.connect(return_overview)
	hud.zoom_requested.connect(_zoom_selected)
	hud.restart_requested.connect(start)
	hud.wheel.confirmed.connect(_radial_command)
	game.state_replaced.connect(func():
		hud.inspection.clear()
		_schedule_autosave()
		if game.is_campaign(): focus(game.scenarios.home(),2.4))
	get_viewport().size_changed.connect(func():
		if overview_active: call_deferred("overview")
		else: call_deferred("_camera_map_offset"))
	start("systemic")
	var direct_entry := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="): start(arg.trim_prefix("--mode=")); direct_entry = true
		if arg == "--overview": overview(); direct_entry = true
		if arg == "--life-review":
			start("life"); hud.life_dialogue.show_preview("late_work"); direct_entry = true
	if "--infection-preview" in OS.get_cmdline_user_args(): open_infection_preview(); direct_entry = true
	if not direct_entry: hud.return_home()

func open_infection_preview() -> void:
	start("fullbody")
	game.paused = true
	game.selected.clear()
	world.infections.select("lung_r")
	infection_preview = WarInfectionPreview.new()
	add_child(infection_preview)
	infection_preview.setup(self)
	infection_preview.closeup()
	print("INFECTION_PREVIEW_READY | organs=",world.infections.data.zones.size()," | paused | GPT-ground")

func _update_content_scale() -> void:
	var window := get_window()
	var design := Vector2i(360,780) if window.size.x < window.size.y else Vector2i(1440,900)
	if window.content_scale_size != design:
		window.content_scale_size = design

func start(mode: String) -> void:
	if is_instance_valid(infection_preview):
		infection_preview.queue_free()
		infection_preview = null
	if hud.wheel != null: hud.wheel.close()
	game.start(mode,int(Time.get_unix_time_from_system()) & 0x7fffffff)
	command_mode = ""
	hud.inspection.clear()
	hud.home.hide()
	world.layer = 0
	_schedule_autosave()
	if game.mode == "fullbody":
		for e in game.units():
			if e.kind == "worker" and e.faction == 1:
				game.selected.append(int(e.id)); focus(WarData.point(e),.25*32); break
	else: focus(game.scenarios.home(),18 if not game.is_campaign() else 2.4)
	if mode == "systemic":
		var q := game.scenarios.systemic()
		focus(WarData.point(q.center),.28*32)
		for id in q.players: game.selected.append(int(id))
	if mode == "lung_skirmish":
		var run: Dictionary = game.state.get("lungSkirmish",{})
		if run.has("center"): focus(WarData.point(run.center),.95*32)
		for id in WarData.array(run.get("players",[])): game.selected.append(int(id))
	if mode == "gastric_trial":
		focus(Vector2(1120,1552),.15*32)
		for e in game.units():
			if e.faction == 1: game.selected.append(int(e.id))
	if mode == "organ_trial":
		var box: Array = game.navigation.organs.liver.sourceBox
		focus(Vector2(box[0]+box[2],box[1]+box[3]+512),.15*32)
		for e in game.units():
			if e.faction == 1 and game.navigation.organ_at(WarData.point(e),e.kind) == "liver": game.selected.append(int(e.id))
	if mode == "cell_test":
		focus(Vector2(102,101),1.8*32)
		game.selected.assign([int(game.state.cellTest.red),int(game.state.cellTest.white)])
	hud._layout()
	if game.is_campaign(): _campaign_home()
	elif game.life.enabled(): overview()

func focus(p: Vector2,zoom: float) -> void:
	if hud != null and hud.wheel != null: hud.wheel.close()
	overview_active = false
	camera.position = p
	camera.zoom = Vector2.ONE*clampf(zoom,minimum_zoom(),2.8*32)
	if game.is_fullbody() and is_equal_approx(camera.zoom.x,minimum_zoom()):
		camera.position = Vector2(1024,2048)
		overview_active = true
	_camera_map_offset()
	camera_travel.reset()

func _camera_map_offset() -> void:
	var view := get_viewport_rect().size
	camera.offset = (view*.5-WarDeskMapFrame.rect_for(view).get_center())/camera.zoom
	camera.force_update_scroll()
	if map_frame != null: map_frame.sync_size()

func _apply_desk_projection(projection: Transform2D) -> void:
	desk_layer.transform = projection
	if hud != null and hud.life_dialogue != null: hud.life_dialogue.apply_desk_projection(projection)

func _overview_pose() -> Dictionary:
	if game.is_campaign():
		var b: Dictionary = game.navigation.campaign.bounds
		var size := WarDeskMapFrame.rect_for(get_viewport_rect().size).size-Vector2(30,30)
		return {"point":Vector2(float(b.x)+float(b.w)*.5,float(b.y)+float(b.h)*.5),"zoom":maxf(minimum_zoom(),minf(size.x/float(b.w),size.y/float(b.h))*.9)}
	return {"point":Vector2(1024,2048),"zoom":minimum_zoom()}

func overview() -> void:
	var pose := _overview_pose()
	focus(pose.point,pose.zoom)
	overview_active = true

func return_overview() -> void:
	hud.wheel.close()
	command_mode = ""
	drag_button = 0; dragging = false
	var pose := _overview_pose()
	camera_travel.aim(pose.point,pose.zoom)
	overview_active = true

func _clamp_camera() -> void:
	camera.position.x = clampf(camera.position.x,3,float(game.state.get("mapWidth",2048))-3)
	camera.position.y = clampf(camera.position.y,3,float(game.state.get("mapHeight",4096))-3)

func _process(delta: float) -> void:
	if world.infections.enabled: game.paused = true
	game.update(delta)
	if game.state.time >= autosave_at:
		if game.life.enabled(): WarSave.write_life_auto(game)
		else: WarSave.write(game,0)
		_schedule_autosave()
	_update_camera_controls(delta)
	queue_redraw()

func _schedule_autosave() -> void:
	var period := 180.0 if game.life.enabled() else 360.0
	autosave_at = (floorf(float(game.state.time)/period)+1)*period

func _update_camera_controls(delta: float) -> void:
	if hud.menu.visible or hud.home.visible or hud.wheel.visible: return
	if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META) or Input.is_key_pressed(KEY_ALT): return
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit: return
	var direction := Input.get_vector("camera_left","camera_right","camera_up","camera_down")
	if not direction.is_zero_approx():
		# Keep the same travel speed on screen at every zoom level.
		var position := camera_travel.target_position if camera_travel.active else camera.position
		var zoom := camera_travel.target_zoom if camera_travel.active else camera.zoom.x
		var bounds := Vector2(float(game.state.get("mapWidth",2048)),float(game.state.get("mapHeight",4096)))
		position = (position+direction*600.0*delta/zoom).clamp(Vector2.ONE*3.0,bounds-Vector2.ONE*3.0)
		camera_travel.aim(position,zoom)
		overview_active = false
	var zoom_direction := Input.get_axis("camera_zoom_out","camera_zoom_in")
	if zoom_direction != 0:
		_zoom_selected(exp(zoom_direction*delta*2.2))

func _draw() -> void:
	if dragging and drag_box:
		var a := get_canvas_transform().affine_inverse()*drag_start
		var b := get_canvas_transform().affine_inverse()*drag_current
		var rect := Rect2(a,b-a).abs()
		draw_rect(rect,Color(.4,.9,.75,.12))
		draw_rect(rect,Color("98e7cd"),false,1.2/camera.zoom.x)

func _input(event: InputEvent) -> void:
	# A drag that starts on paper must end even when released over the phone/HUD.
	if event is InputEventMouseButton and not event.pressed and event.button_index == drag_button:
		_finish_drag(event)
		get_viewport().set_input_as_handled()

func _finish_drag(event: InputEventMouseButton) -> void:
	var button := drag_button
	var moved := dragging or absf(event.position.x-drag_start.x)+absf(event.position.y-drag_start.y) > 7
	drag_button = 0
	dragging = false
	if hud.menu.visible or hud.home.visible: return
	var field := map_frame.screen_rect()
	drag_current = event.position.clamp(field.position,field.end)
	if moved:
		if drag_box: _box_select(event.shift_pressed)
	elif field.has_point(event.position):
		if button == MOUSE_BUTTON_LEFT:
			if not command_mode.is_empty(): _command(event.position,event.shift_pressed)
			else: _tap(event.position,event.shift_pressed,event.double_click)
		elif button == MOUSE_BUTTON_RIGHT:
			if command_mode.is_empty(): _open_wheel(event.position,event.shift_pressed)
			else: _command(event.position,event.shift_pressed)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_key(event)
		return
	if hud.menu.visible or hud.home.visible: return
	if event is InputEventMouseButton and event.pressed and not map_frame.contains_screen_point(event.position): return
	if (event is InputEventMagnifyGesture or event is InputEventPanGesture) and not map_frame.contains_screen_point(event.position): return
	if event is InputEventMagnifyGesture:
		_zoom(event.factor,event.position)
	elif event is InputEventPanGesture:
		# The anatomy is fixed on the paper; trackpad panning cannot displace it.
		return
	elif event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			_zoom(1.12 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1/1.12,event.position)
		elif event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
			if event.pressed:
				drag_button = event.button_index
				drag_start = event.position
				drag_current = event.position
				dragging = false
				drag_box = event.button_index == MOUSE_BUTTON_LEFT and world.layer != 6 and (hud.box_mode or command_mode.is_empty())
			else:
				if drag_button == 0 or event.button_index != drag_button: return
				_finish_drag(event)
	elif event is InputEventMouseMotion and drag_button != 0:
		var field := map_frame.screen_rect()
		drag_current = event.position.clamp(field.position,field.end)
		if absf(event.position.x-drag_start.x)+absf(event.position.y-drag_start.y) > 7: dragging = true

func _zoom(factor: float,at: Vector2,keep_center := false) -> void:
	var current := camera_travel.target_zoom if camera_travel.active else camera.zoom.x
	var zoom := clampf(current*factor,minimum_zoom(),2.8*32)
	if game.is_fullbody() and is_equal_approx(zoom,minimum_zoom()):
		return_overview()
		return
	overview_active = false
	var field := WarDeskMapFrame.rect_for(get_viewport_rect().size)
	var point := camera_travel.target_position if camera_travel.active else camera.position
	if not keep_center:
		point = get_canvas_transform().affine_inverse()*at-(at-field.get_center())/zoom
	point = point.clamp(Vector2.ONE*3,Vector2(game.state.get("mapWidth",2048),game.state.get("mapHeight",4096))-Vector2.ONE*3)
	camera_travel.aim(point,zoom)

func _zoom_selected(factor: float) -> void:
	_zoom(factor,WarDeskMapFrame.rect_for(get_viewport_rect().size).get_center(),true)

func _select(at: Vector2,append: bool,double: bool) -> void:
	append = append or hud.append_orders
	if world.layer == 6: return
	var p := get_canvas_transform().affine_inverse()*at
	var best: Dictionary = {}
	var distance := INF
	for e in game.entities():
		if not game.visible(e): continue
		var d := p.distance_to(world.display_point(world.unit_position(e)))
		var radius := maxf(world.display_radius(e,WarData.point(e)),6.0/camera.zoom.x)
		if e.category == "building": radius = maxf(radius,float(WarData.spec(e.kind).get("size",1))*.5)
		if world.pick(e,p) and d < distance:
			best = e
			distance = d
	if not append: game.selected.clear()
	if not best.is_empty() and best.faction == 1:
		game.state.selectedOnce = true
		if append and game.selected.has(int(best.id)): game.selected.erase(int(best.id))
		else: game.selected.append(int(best.id))
		if double and best.faction == 1:
			for e in game.units():
				if e.kind == best.kind and e.faction == 1 and WarData.point(e).distance_squared_to(WarData.point(best)) <= 144 and not game.selected.has(int(e.id)): game.selected.append(int(e.id))

func _box_select(append: bool) -> void:
	append = append or hud.append_orders
	if world.layer == 6: return
	game.state.selectedOnce = true
	var a := get_canvas_transform().affine_inverse()*drag_start
	var b := get_canvas_transform().affine_inverse()*drag_current
	var rect := Rect2(a,b-a).abs()
	if not append: game.selected.clear()
	for e in game.units():
		if e.faction == 1 and rect.has_point(world.display_point(world.unit_position(e))) and not game.selected.has(int(e.id)): game.selected.append(int(e.id))

func _command(at: Vector2,append: bool) -> void:
	append = append or hud.append_orders
	if world.layer == 6: return
	var displayed: Vector2 = get_canvas_transform().affine_inverse()*at
	var p := world.command_point(displayed)
	if command_mode == "rally":
		if not game.selected.is_empty():
			game.submit_player({"action":"rally","target":game.selected[0],"x":p.x,"y":p.y})
		command_mode = ""
		return
	if command_mode.begins_with("build:"):
		var building := command_mode.trim_prefix("build:")
		p = game.economy.build_point(building,p)
		if game.economy.can_place(building,p,game.selected):
			game.submit_player({"action":"place","building":building,"x":p.x,"y":p.y,"append":append})
			world.show_command_marker(p,"build")
			command_mode = ""
		return
	if game.selected.is_empty():
		game.notify("先选择要指挥的细胞")
		return
	var target_id := 0
	var kind := command_mode if not command_mode.is_empty() else "move"
	for e in game.entities():
		if game.visible(e) and world.pick(e,displayed):
			if e.faction != 1:
				kind = "attack"
				target_id = int(e.id)
				break
			elif e.category == "building" and (not e.get("complete",true) or e.hp < e.maxHp):
				kind = "repair" if e.get("complete",true) else "build"
				target_id = int(e.id)
				break
	if target_id == 0:
		for key in game.state.resources:
			var resource: Dictionary = game.state.resources[key]
			if (resource.amount > 0 or resource.get("organSource",false)) and p.distance_to(WarData.point(resource)) <= float(resource.get("radius",2.2)):
				for id in game.selected:
					var e := game.entity(id)
					if e.get("kind","") == "worker":
						game.submit_player({"action":"unit_order","unit":int(e.id),"order":{"kind":"harvest","resource":key,"x":resource.x,"y":resource.y},"append":append})
				world.show_command_marker(p,"move")
				return
	game.issue(kind,p,append,target_id)
	audio.play("command")
	command_mode = ""
	world.show_command_marker(p,kind)

func _key(event: InputEventKey) -> void:
	var key := event.keycode
	if hud.wheel.visible:
		if key == KEY_ESCAPE: hud.wheel.close()
		return
	if key == KEY_ESCAPE:
		if not command_mode.is_empty(): command_mode = ""
		else:
			if hud.menu.visible: hud.close_menu()
			elif hud.dialogue.active or hud.dialogue.chatting: hud.dialogue.close_chat()
			else: game.selected.clear()
		return
	if hud.menu.visible or hud.home.visible: return
	match key:
		KEY_Q,KEY_E:
			if not (event.ctrl_pressed or event.meta_pressed or event.alt_pressed): _zoom_selected(2.0 if key == KEY_Q else .5)
		KEY_SPACE: game.paused = not game.paused
		KEY_M: hud.show_map()
		KEY_F:
			if not (event.ctrl_pressed or event.meta_pressed or event.alt_pressed): hud.focus_cell(false)
		KEY_C:
			if not (event.ctrl_pressed or event.meta_pressed or event.alt_pressed): hud.focus_cell(true)
		KEY_R: game.issue("retreat")
		KEY_H: hud.return_home()
		KEY_B: hud.show_build()
		KEY_1,KEY_2,KEY_3:
			var index := key-KEY_1
			if event.ctrl_pressed or event.meta_pressed: game.groups[index] = game.selected.duplicate()
			else:
				game.selected.clear()
				for id in game.groups[index]:
					if not game.entity(int(id)).is_empty(): game.selected.append(int(id))

func _exit_tree() -> void:
	# Services hold typed references during play. Break their cycles on shutdown.
	game.dispose()

func minimum_zoom() -> float:
	return WarDeskMapFrame.overview_zoom(get_viewport_rect().size,Vector2(game.state.get("mapWidth",2048),game.state.get("mapHeight",4096)))

func _tap(at: Vector2,append: bool,double: bool) -> void:
	var p := get_canvas_transform().affine_inverse()*at
	if not Rect2(Vector2.ZERO,Vector2(game.state.get("mapWidth",2048),game.state.get("mapHeight",4096))).has_point(p): return
	# A map click is gameplay input only. Camera movement is reserved for WASD/Q/E.
	hud.inspection.clear()
	if world.layer == 6: return
	for e in game.entities():
		if e.faction != 1 or not game.visible(e): continue
		if world.pick(e,p):
			if not game.is_fullbody() and e.category == "building" and game.selected.has(int(e.id)) and not double: _open_wheel(at,append)
			else: _select(at,append,double)
			return
	if not game.is_fullbody(): _open_wheel(at,append)

func _open_wheel(at: Vector2,append: bool) -> void:
	if world.layer == 6: return
	var displayed := get_canvas_transform().affine_inverse()*at
	hud.wheel.open(at,world.command_point(displayed),append)

func _radial_command(action: String,p: Vector2,append: bool,ids: Array,context: Dictionary) -> void:
	# Use the original target, not the screen position of the option being clicked.
	var live_ids: Array[int] = []
	var workers: Array[int] = []
	for id in ids:
		var e := game.entity(int(id))
		if e.is_empty() or e.faction != 1 or e.hp <= 0: continue
		live_ids.append(int(id))
		if e.kind == "worker": workers.append(int(id))
	if live_ids.is_empty(): hud.wheel.close(); return
	if action == "production": hud.wheel.close(); hud.show_build(); return
	if action.begins_with("place:"):
		var kind := action.trim_prefix("place:")
		p = game.economy.build_point(kind,p)
		if not game.economy.can_place(kind,p,workers):
			hud.wheel.present_error(status_message())
			return
		game.submit_player({"action":"place","building":kind,"x":p.x,"y":p.y,"append":append,"ids":workers})
	elif action == "harvest":
		var resource: Dictionary = game.state.resources.get(context.resource,{})
		if resource.is_empty() or (resource.get("amount",0) <= 0 and not resource.get("organSource",false)):
			hud.wheel.present_error("此处资源已耗尽")
			return
		for id in workers:
			game.submit_player({"action":"unit_order","unit":id,"order":{"kind":"harvest","resource":context.resource,"x":resource.x,"y":resource.y},"append":append,"ids":workers})
	elif action == "rally":
		for id in live_ids:
			if game.entity(id).get("category","") == "building": game.submit_player({"action":"rally","target":id,"x":p.x,"y":p.y,"ids":live_ids})
	else:
		var target := int(context.get("target",0)) if action in ["attack","repair","build","farm","extinguish"] else 0
		if target != 0 and game.entity(target).is_empty():
			hud.wheel.present_error("目标已离开战场，请重新选择位置")
			return
		if action == "farm":
			var bed := game.entity(target)
			if workers.is_empty() or bed.is_empty() or bed.kind != "farm" or bed.faction != 1 or bed.hp <= 0 or not bed.get("complete",false):
				hud.wheel.present_error("请选择红细胞和已完成的己方培养床")
				return
		if action == "extinguish":
			var building := game.entity(target)
			if game.mode != "sandbox" or workers.is_empty() or building.is_empty() or building.category != "building" or building.faction != 1 or building.hp <= 0 or float(building.get("fire",0)) <= 0:
				hud.wheel.present_error("请选择红细胞和正在燃烧的己方建筑")
				return
		game.submit_player({"action":"issue","kind":action,"x":p.x,"y":p.y,"append":append,"target":target,"ids":workers if action in ["repair","build","farm","extinguish"] else live_ids})
	hud.wheel.confirm(action)
	audio.play("command")
	world.show_command_marker(p,action)

func status_message() -> String:
	return hud.status.text

func _campaign_home() -> void:
	var home := game.scenarios.home()
	var bounds: Dictionary = game.navigation.campaign.bounds
	var size := get_viewport_rect().size
	if game.mode == "trachea_01":
		var stage := hud.battle.stage
		var zoom := minf(.4,maxf(.14,(stage.size.x-16)/(float(bounds.w)*32)))*32
		focus(home,zoom)
		camera.force_update_scroll()
		var actual := get_canvas_transform()*home
		var wanted := stage.position+stage.size*Vector2(.5,.68)
		camera.position += (actual-wanted)/zoom
	else:
		var zoom := minf(.6,maxf(.24,minf((size.x-32)/(76*32),maxf(160,size.y-270)/(72*32))))*32
		focus(home-Vector2(17,0),zoom)
