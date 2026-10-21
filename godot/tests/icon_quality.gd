extends SceneTree
## Native-renderer regression: icon buffers contain artwork and focus adds no line.
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok: failures.append(message); printerr("FAIL ",message)

func rendered() -> void:
	for i in 3:
		await process_frame
		await RenderingServer.frame_post_draw

func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Icon pixel checks require a native renderer."); quit(1); return
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(720,300)
	var stage := Control.new(); root.add_child(stage)
	var background := ColorRect.new(); background.color = WarUISkin.CREAM
	background.size = Vector2(720,300); background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(background)
	var buttons: Array[WarCommandButton] = []
	var entries := [["移动","move"],["进攻","attackmove"],["驻守","guard"],["建造","build"],["撤退","retreat"],["停止","stop"]]
	for i in entries.size():
		var btn := WarCommandButton.new(); stage.add_child(btn)
		btn.configure(entries[i][0],entries[i][1],"primary" if i == 1 else "")
		btn.position = Vector2(26+i*113,35)
		buttons.append(btn)
	for i in 3:
		var icon := WarResourceIcon.new(); icon.kind = ["oxygen","food","wood"][i]
		icon.position = Vector2(30+i*226,177); icon.size = Vector2(38,38); stage.add_child(icon)
		var label := Label.new(); label.text = ["氧气量","葡萄糖量","蛋白质量"][i]
		label.position = icon.position+Vector2(48,6); label.theme = WarUISkin.theme(); stage.add_child(label)
	await rendered()
	for child in stage.get_children():
		var icon: WarSmoothIcon = child.glyph if child is WarCommandButton else (child if child is WarResourceIcon else null)
		if icon == null: continue
		var pixels := icon.icon_viewport.get_texture().get_image()
		check(pixels.get_used_rect().get_area() > 100,"visible artwork: "+str(child.name))
		check(pixels.get_size() == Vector2i((icon.size*WarSmoothIcon.SAMPLE_SCALE).ceil()),"supersampled icon dimensions: "+str(child.name))
	var selected := buttons[1]
	selected.set_process(false)
	selected.hover_amount = .5; selected._layout(); selected.release_focus()
	await rendered()
	var region := Rect2i(selected.position-Vector2.ONE*3,selected.size+Vector2.ONE*6)
	var before := root.get_texture().get_image().get_region(region)
	selected.grab_focus(); selected.queue_redraw()
	await rendered()
	var focused := root.get_texture().get_image().get_region(region)
	check(selected.has_focus(),"keyboard focus is retained")
	check(before.get_data() == focused.get_data(),"focus never draws an inner outline")
	selected.release_focus()
	DirAccess.make_dir_recursive_absolute("res://test-output")
	root.get_texture().get_image().save_png("res://test-output/ui-icon-clarity.png")
	print("ICON QUALITY ",checks-failures.size(),"/",checks)
	stage.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
