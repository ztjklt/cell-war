extends "res://tests/left_lung_ui.gd"
## Shared art coverage across live dynamic menus; gameplay stays in native controls.
const MEMBRANE := "res://assets/ui/membrane/"
var styled := 0

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await frames(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(evidence_dir+name+".png")

func check_resource_corners() -> void:
	for control in main.hud.root.find_children("*","Control",true,false):
		if control is WarResourceIcon:
			check(control.frame.texture_margin_left+control.frame.texture_margin_right <= control.size.x*.96 and control.frame.texture_margin_top+control.frame.texture_margin_bottom <= control.size.y*.96,"resource membrane corners fit actual drawing bounds")

func popup_key(popup: Window,code: Key) -> void:
	var event := InputEventKey.new(); event.keycode = code; event.pressed = true
	if popup == root: popup.push_input(event)
	else: popup.window_input.emit(event)
	await process_frame
	event = event.duplicate(); event.pressed = false
	if popup == root: popup.push_input(event)
	else: popup.window_input.emit(event)
	await frames(3)

func painted(style: StyleBox) -> bool:
	return style is StyleBoxTexture and style.texture != null and style.texture.resource_path.begins_with(MEMBRANE)

func surface_tree(node: Node,context: String) -> void:
	if node is Button and not node is WarCoverButton and node != main.hud.dialogue.hit:
		for state in ["normal","hover","pressed","disabled"]:
			check(painted(node.get_theme_stylebox(state)),context+" "+str(node.name)+" "+state+" uses membrane art")
		var box := node.get_theme_stylebox("normal") as StyleBoxTexture
		if box != null and node.is_visible_in_tree():
			check(node.size.x+1 >= box.texture_margin_left+box.texture_margin_right and node.size.y+1 >= box.texture_margin_top+box.texture_margin_bottom,context+" generated corners fit "+str(node.name))
		styled += 1
	if node is PanelContainer and not node is WarHUDPlate:
		check(painted(node.get_theme_stylebox("panel")),context+" "+str(node.name)+" panel uses membrane art")
	for child in node.get_children(): surface_tree(child,context)

func run() -> void:
	prepare_evidence("res://test-output/global-ui-20261024/")
	var skin := WarUISkin.theme()
	for type in ["Button","OptionButton","LineEdit","HSlider","VScrollBar","PopupMenu"]:
		var key: String = {"Button":"normal","OptionButton":"normal","LineEdit":"normal","HSlider":"slider","VScrollBar":"scroll","PopupMenu":"panel"}[type]
		check(painted(skin.get_stylebox(key,type)),type+" uses generated shared art")
	if not failures.is_empty(): finish(); return
	WarSave.directory = "user://test-saves/global-ui-"+str(Time.get_ticks_usec())
	WarSettings.storage_path = WarSave.directory+"/settings.json"
	DirAccess.make_dir_recursive_absolute(WarSave.directory)
	root.size = Vector2i(1440,900); root.content_scale_size = root.size
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main); current_scene = main; await frames(15); main.set_process(false)
	for button in main.hud.home.buttons:
		check(painted(button.get_theme_stylebox("normal")),"cover "+button.caption+" shares membrane art")
	await capture("cover-desktop")
	if not await press(main.hud.home.buttons[0]): finish(); return
	surface_tree(main.hud.menu,"save opening")
	await capture("save-picker")
	if not await press(prefix_button(main.hud.menu_body,"＋ 新建存档")): finish(); return
	main.start("life"); main.set_process(false); await frames(6)
	for method in ["show_saves","show_cover_settings","show_build","show_battlefields","show_resource_stations","show_command_tools","show_medicine_supply","show_organ_actions","show_organ_guide","show_help","show_life_events"]:
		main.hud.call(method); await frames(5)
		if method == "show_cover_settings":
			var mute: CheckButton = main.hud.menu.find_children("*","CheckButton",true,false)[0]
			var before_mute: bool = main.settings.muted()
			if await press(mute): check(main.settings.muted() != before_mute,"native membrane mute control changes the real setting")
			var slider: HSlider = main.hud.menu.find_children("*","HSlider",true,false)[0]
			var before_volume: float = main.settings.volume()
			await click(slider.get_global_rect().position+slider.size*Vector2(.8,.5))
			check(main.settings.volume() > before_volume,"native generated slider changes real volume")
		surface_tree(main.hud.menu,method)
		await capture(method)
		main.hud.close_menu()
	check_resource_corners()
	var pulse := WarOrderPulse.new(); main.hud.root.add_child(pulse)
	pulse.configure(Vector2(700,400),"move")
	check(pulse.frame.texture_margin_left+ pulse.frame.texture_margin_right <= 38 and pulse.frame.texture_margin_top+pulse.frame.texture_margin_bottom <= 36,"order acknowledgement corners fit actual drawing bounds")
	check(styled > 35,"all dynamic menu families were visited")
	var phone: WarLifeDialogue = main.hud.life_dialogue
	phone.show_preview("late_work"); await frames(8)
	phone._elapsed = 999.0; phone._animate(0.0); await frames(8)
	surface_tree(phone,"phone preview")
	var life_before: String = JSON.stringify(main.game.life.state())
	await capture("phone-preview")
	if await press(phone.option_buttons[0]):
		check(phone.preview_choice == 0,"native phone choice selects the preview result")
		check(JSON.stringify(main.game.life.state()) == life_before,"phone preview input does not settle or advance life")
	await capture("phone-reply")
	phone._toggle()
	main.hud.dialogue.answer("body"); await frames(6)
	surface_tree(main.hud.dialogue.controls,"advisor controls")
	surface_tree(main.hud.dialogue.feed,"advisor strips")
	await capture("advisor-chat")
	main.hud.dialogue.close_chat()
	main.hud.return_home()
	if await press(main.hud.home.buttons[1]):
		surface_tree(main.hud.cover_preview,"catalogue")
		await frames(12); await capture("catalogue")
		var picker: OptionButton = main.hud.cover_preview.action_picker
		picker.grab_focus()
		await popup_key(root,KEY_SPACE)
		var popup := picker.get_popup()
		check(popup.visible,"native keyboard expands the action menu")
		check(popup.transparent and popup.transparent_bg,"native popup preserves transparent art corners")
		if popup.visible:
			await capture("catalogue-popup")
			# Native Window input cannot be driven through Viewport.push_input on
			# macOS. Actual item selection is checked with system mouse input;
			# this test covers opening, theme, transparency and safe dismissal.
			popup.hide()
			check(picker.selected == 0 and main.hud.cover_preview.player.mode == 0,"dismissing the action popup does not change selection")
		main.hud.cover_preview.close()
	main.start("life"); main.set_process(false); await frames(6)
	for dimensions in [Vector2i(1024,768),Vector2i(360,780),Vector2i(390,844),Vector2i(844,390)]:
		root.size = dimensions; root.content_scale_size = dimensions
		await frames(8)
		check_resource_corners()
		main.hud.show_cover_settings(); await frames(6)
		check(main.hud.menu.get_global_rect().end.x <= root.get_visible_rect().size.x+1,"settings stays inside "+str(dimensions))
		await capture("settings-%dx%d"%[dimensions.x,dimensions.y])
		main.hud.close_menu()
	main.queue_free(); await frames()
	finish()

func finish() -> void:
	var report := FileAccess.open(evidence_dir+"coverage-result.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"display":DisplayServer.get_name(),"styledControls":styled},"  "))
	print("GLOBAL_UI ",checks-failures.size(),"/",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
