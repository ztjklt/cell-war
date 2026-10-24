extends SceneTree
var main: Node
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool,text: String) -> void:
	checks += 1
	if not ok: failures.append(text); printerr("FAIL ",text)

func frames(n := 4) -> void:
	for i in n: await process_frame

func find_button(node: Node,prefix: String) -> Button:
	if node is Button and node.text.begins_with(prefix): return node
	for child in node.get_children():
		var found := find_button(child,prefix)
		if found != null: return found
	return null

func run() -> void:
	WarSave.directory = "user://test-saves/opening-fixes-"+str(Time.get_ticks_usec())
	WarSettings.storage_path = WarSave.directory+"/settings.json"
	DirAccess.make_dir_recursive_absolute(WarSave.directory)
	root.size = Vector2i(1440,900)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main); current_scene = main
	main.set_process(false); main.start("lung_defense"); main.game.paused = true
	await frames(12)
	var defense: Dictionary = main.game.state.lungDefense
	var base: Dictionary = main.game.entity(int(defense.base))
	check(defense.organ == "lung_l" and main.game.navigation.organ_at(WarData.point(base)) == "lung_l" and base.y < 1280,"new opening is in upper left lung")
	var countdown: Control = main.hud.root.find_child("DefenseCountdown",true,false)
	check(countdown != null and countdown.is_visible_in_tree(),"preparation countdown visible independently of systemic panel")
	var selected: Array = main.game.selected.duplicate()
	main.hud.focus_button.pressed.emit()
	check(main.game.selected == selected,"focus button preserves selected cell")
	main.overview()
	Input.action_press("camera_right")
	main._update_camera_controls(.5)
	Input.action_release("camera_right")
	check(not main.camera_travel.active and main.overview_active,"WASD cannot pan at overview")
	main.focus(Vector2(-10000,-10000),main.minimum_zoom()*1.1)
	var projected: Rect2 = main.map_frame.desk_projection()*Rect2(Vector2.ZERO,root.get_visible_rect().size)
	check(projected.grow(.05).encloses(root.get_visible_rect()),"zoomed camera keeps full artwork over viewport")
	main.hud.show_battlefields()
	var paths_before: bool = main.settings.show_paths()
	find_button(main.hud.menu_body,"路线显示").pressed.emit()
	check(main.settings.show_paths() != paths_before and main.settings.show_paths() == main.world.show_paths,"battlefield route toggle updates persisted setting")
	main.hud.show_battlefields()
	var muted_before: bool = main.settings.muted()
	find_button(main.hud.menu_body,"声音").pressed.emit()
	check(main.settings.muted() != muted_before and main.settings.muted() == AudioServer.is_bus_mute(0),"battlefield sound toggle updates persisted setting")
	main.hud.close_menu()
	main.start("systemic")
	main.game.state.entities.erase(str(int(main.game.scenarios.systemic().courier)))
	var before: Vector2 = main.camera.position
	find_button(main.hud.systemic_panel,"定位运输队").pressed.emit()
	check(main.camera.position.is_equal_approx(before),"missing courier does not move camera")
	main.start("nasal_01"); main.game.paused = true
	main.hud.show_battlefields()
	check(find_button(main.hud.root,"下一波") == null,"no next-wave button in either HUD or menu")
	main.hud.close_menu(); main.start("lung_defense")
	for e in main.game.entities():
		if e.faction == 1 and not e.has("checkpointId"): e.hp = 0
	main.game.scenarios.after_step(.1)
	check(main.game.state.lungDefense.phase == "failed","destroyed opening defense enters failure")
	main.free()
	print("OPENING_FIXES ",checks-failures.size(),"/",checks)
	quit(0 if failures.is_empty() else 1)
