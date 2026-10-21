extends SceneTree
## Verifies cover -> settings input callbacks without writing user preferences.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,text: String) -> void:
	if not value:
		failures.append(text)
		printerr("FAIL "+text)
	else:
		print("PASS "+text)

func find_button(root: Node,text: String) -> Button:
	for node in root.find_children("*","Button",true,false):
		if node.text == text: return node as Button
	return null

func run() -> void:
	WarSettings.storage_path = "user://test-settings-ui.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(WarSettings.storage_path))
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	for _frame in 3: await process_frame
	main.hud.home.buttons[3].activated.emit()
	for _frame in 2: await process_frame
	var hud: WarHUD = main.hud
	check(hud.menu.visible,"cover settings opens a visible modal")
	check(hud.menu.z_index > hud.home.z_index,"settings modal is above the cover")
	check(hud.menu.mouse_filter == Control.MOUSE_FILTER_STOP,"settings modal consumes pointer input")
	var mute := find_button(hud.menu_body,"静音") as CheckButton
	var fullscreen := find_button(hud.menu_body,"全屏：关")
	var fps := find_button(hud.menu_body,"帧率上限：60")
	check(mute != null and fullscreen != null and fps != null,"settings controls are present")
	if mute != null:
		mute.toggled.emit(true)
		check(main.settings.muted(),"mute control updates runtime audio preference")
	if fps != null:
		fps.pressed.emit()
		check(main.settings.fps() == 120 and Engine.max_fps == 120,"frame cap control updates the engine")
	var paths := find_button(hud.menu_body,"路线显示：开")
	if paths != null:
		paths.pressed.emit()
		check(not main.settings.show_paths() and not main.world.show_paths,"route display control updates the world")
	fullscreen = find_button(hud.menu_body,"全屏：关")
	if fullscreen != null:
		fullscreen.pressed.emit()
		check(main.settings.fullscreen(),"fullscreen control updates its preference")
	WarSettings.storage_path = "user://settings.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test-settings-ui.json"))
	main.queue_free()
	await process_frame
	print("SETTINGS UI ",failures)
	quit(0 if failures.is_empty() else 1)
