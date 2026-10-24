extends SceneTree
## Integration acceptance for painted native archive controls and their feedback.
## ./godot/run.sh --headless --script res://tests/catalogue_components.gd
## Omit --headless to save idle/hover/pressed/recovered component screenshots.

const OUTPUT := "res://test-output/catalogue-components"
const ART_ROOT := "res://assets/ui/catalogue/components/"
var checks := 0
var failures: Array[String] = []
var screenshots: Array[String] = []
var preview: WarCoverPreview
var checked_surfaces: Dictionary = {}
var checked_icons: Dictionary = {}
var pause_presses := 0
var close_count := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,message: String) -> void:
	checks += 1
	if value: print("PASS ",message)
	else:
		failures.append(message)
		printerr("FAIL ",message)

func wait_real(seconds := .25) -> void:
	await create_timer(seconds,true,false,true).timeout

func feedback_details(button: Button) -> String:
	var tweens: Array[Dictionary] = []
	for tween in get_processed_tweens():
		tweens.append({"valid":tween.is_valid(),"running":tween.is_running(),"elapsed":tween.get_total_elapsed_time()})
	return JSON.stringify({"scale":[button.scale.x,button.scale.y],"state":button.get_meta("catalogue_motion_state","missing"),"motion_running":button.get_meta("catalogue_motion_running","missing"),"reveal_running":button.get_meta("catalogue_reveal_running",false),"button_pressed":button.button_pressed,"disabled":button.disabled,"visible":button.is_visible_in_tree(),"frame":Engine.get_process_frames(),"tweens":tweens})

func wait_for_feedback(button: Button) -> void:
	# SceneTreeTimer can resume before this frame's Tween update, especially at
	# low FPS. Observe the rendered result, with a deadline rather than a sleep.
	var deadline := Time.get_ticks_msec()+1500
	while Time.get_ticks_msec() < deadline:
		if DisplayServer.get_name() == "headless": await process_frame
		else: await RenderingServer.frame_post_draw
		if not bool(button.get_meta("catalogue_motion_running",false)): return

func frames(count := 4) -> void:
	for _frame in count: await process_frame

func visible_rect(control: Control) -> Rect2:
	if not control.is_visible_in_tree(): return Rect2()
	var rect := control.get_global_rect().intersection(Rect2(Vector2.ZERO,Vector2(root.content_scale_size)))
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is Control and ancestor.clip_contents:
			rect = rect.intersection(ancestor.get_global_rect())
		ancestor = ancestor.get_parent()
	return rect

func reveal_for_click(control: Control) -> void:
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer: ancestor.ensure_control_visible(control)
		ancestor = ancestor.get_parent()
	await frames()
	var rect := visible_rect(control)
	check(rect.size.x >= 24 and rect.size.y >= 24,"native click target remains reachable: "+str(control.name))

func move_mouse(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = root.get_stretch_transform()*point
	root.push_input(event)
	await process_frame

func mouse_button(point: Vector2,down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = root.get_stretch_transform()*point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	root.push_input(event)
	await process_frame

func click(control: Control,settle_seconds := .025) -> void:
	await reveal_for_click(control)
	var point := visible_rect(control).get_center()
	await move_mouse(point)
	await mouse_button(point,true)
	await mouse_button(point,false)
	await wait_real(settle_seconds)

func rest_pointer() -> void:
	root.gui_release_focus()
	await move_mouse(Vector2(3,3))
	await wait_real()

func type_character(character: String) -> void:
	var event := InputEventKey.new()
	event.unicode = character.unicode_at(0)
	event.pressed = true
	root.push_input(event)
	event = event.duplicate(); event.pressed = false; root.push_input(event)
	await frames()

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var path := OUTPUT.path_join(label+".png")
	var error := root.get_texture().get_image().save_png(path)
	check(error == OK,"native screenshot saved: "+label)
	if error == OK: screenshots.append(path)

func image_of(texture: Texture2D) -> Image:
	if texture == null: return null
	var source := texture.get_image()
	if source != null and source.is_compressed(): source.decompress()
	return source

func check_surface(style: StyleBox,label: String) -> bool:
	if not style is StyleBoxTexture or style.texture == null: return false
	var path: String = style.texture.resource_path
	if not (path.begins_with(ART_ROOT) or path.begins_with("res://assets/ui/membrane/")) or not ResourceLoader.exists(path): return false
	if checked_surfaces.has(path): return bool(checked_surfaces[path])
	var source := image_of(style.texture)
	var readable := source != null and not source.is_empty()
	var minimum_alpha := 1.0
	if readable:
		# The text-bearing center must be opaque. Decorative transparent corners are
		# allowed, but cannot substitute for a legible native control surface.
		for y in 5:
			for x in 5:
				var px := roundi(source.get_width()*(.35+.075*x))
				var py := roundi(source.get_height()*(.35+.075*y))
				minimum_alpha = minf(minimum_alpha,source.get_pixel(px,py).a)
		readable = minimum_alpha >= .95
	checked_surfaces[path] = readable
	check(readable,label+" painted text surface has an opaque center (minimum alpha "+str(minimum_alpha)+")")
	return readable

func check_icon(texture: Texture2D,label: String) -> void:
	check(texture != null,label+" has a painted icon")
	if texture == null: return
	var path := texture.resource_path
	check(path.begins_with(ART_ROOT) and ResourceLoader.exists(path),label+" uses a bundled catalogue icon")
	if checked_icons.has(path): return
	var source := image_of(texture)
	var has_pixels := source != null and not source.is_empty() and source.get_used_rect().has_area()
	check(has_pixels,label+" icon contains visible artwork")
	if has_pixels:
		var corner_alpha := source.get_pixel(0,0).a+source.get_pixel(source.get_width()-1,0).a+source.get_pixel(0,source.get_height()-1).a+source.get_pixel(source.get_width()-1,source.get_height()-1).a
		check(corner_alpha < .4,label+" icon keeps transparent outer corners")
	checked_icons[path] = true

func check_controls(label: String) -> void:
	var buttons := preview.find_children("*","Button",true,false)
	check(buttons.size() >= 20,label+" inspects actual archive buttons, including character cards")
	for node in buttons:
		var button := node as Button
		var textured := true
		for state in ["normal","hover","pressed","disabled"]:
			textured = check_surface(button.get_theme_stylebox(state),str(button.name)+" "+state) and textured
		check(textured,label+" all four button states use readable painted textures: "+str(button.name))
		var helper: Variant = button.get_meta("_catalogue_motion_helper",null)
		check(is_instance_valid(helper) and helper is Node and helper.get_parent() == button,label+" button owns attached feedback: "+str(button.name))
		if button.icon != null: check_icon(button.icon,str(button.name))
	check(check_surface(preview.panel.get_theme_stylebox("panel"),"archive panel"),"archive panel uses the painted surface")
	for state in ["normal","read_only"]:
		check(check_surface(preview.search.get_theme_stylebox(state),"search "+state),"native search "+state+" uses the painted field")
	var search_helper: Variant = preview.search.get_meta("_catalogue_motion_helper",null)
	check(is_instance_valid(search_helper) and search_helper.get_parent() == preview.search,"search field owns feedback without replacing native text input")
	check_icon(preview.search.right_icon,"search field")
	check_icon(preview.search.get_theme_icon("clear"),"native clear button")
	check_icon(preview.action_picker.get_theme_icon("arrow"),"native action menu arrow")
	check_icon(preview.action_picker.get_popup().get_theme_icon("checked"),"native popup selection marker")

func check_settled(label: String) -> void:
	var opaque := true
	var idle := true
	for control in preview.find_children("*","Control",true,false):
		if control.has_meta("_catalogue_motion_helper"):
			opaque = opaque and control.modulate.a >= .99
			idle = idle and not bool(control.get_meta("catalogue_motion_running",false)) and not bool(control.get_meta("catalogue_reveal_running",false))
	check(opaque,label+" leaves no permanently transparent control")
	check(idle,label+" completes all feedback and reveals")
	check(get_processed_tweens().is_empty(),label+" leaves no scene tween running")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.size = Vector2i(1280,800)
	root.content_scale_size = root.size
	preview = WarCoverPreview.new(); root.add_child(preview)
	preview.closed.connect(func(): close_count += 1)
	preview.open()
	check(preview.panel.modulate.a < 1.0,"opening begins with a native panel reveal")
	await wait_real(.32)
	await rest_pointer()
	check_controls("initial roster")
	check_settled("opening")

	# Inspect a real action control through actual viewport input, not synthetic
	# signal emission. It retains its native single-click playback behavior.
	await reveal_for_click(preview.pause_button)
	await rest_pointer()
	var button := preview.pause_button
	var original_position := button.position
	var original_size := button.size
	var original_minimum := button.get_combined_minimum_size()
	var original_color := button.self_modulate
	var sibling_position := preview.replay_button.position
	button.pressed.connect(func(): pause_presses += 1)
	await capture("component-idle")
	await move_mouse(visible_rect(button).get_center())
	await wait_real(.18)
	check(button.scale.x > 1.0 and button.scale.x < 1.10,"real hover gives visible, restrained button emphasis")
	check(button.position == original_position and button.size == original_size and button.get_combined_minimum_size() == original_minimum and preview.replay_button.position == sibling_position,"hover does not reflow button labels or adjacent controls")
	check(visible_rect(button).size.y >= 24,"hover keeps the action click area accessible")
	await capture("component-hover")
	await mouse_button(visible_rect(button).get_center(),true)
	await wait_for_feedback(button)
	check(button.button_pressed and button.scale.x < 1.0 and button.scale.x > .90,"holding the real mouse button visibly compresses the control; "+feedback_details(button))
	await capture("component-pressed")
	await mouse_button(visible_rect(button).get_center(),false)
	await wait_real(.18)
	check(pause_presses == 1 and not preview.player.playing,"release invokes the original pause action exactly once")
	check(button.scale.x > 1.0,"release returns to hover emphasis")
	check_icon(button.icon,"paused action play icon")
	await rest_pointer()
	check(button.scale.is_equal_approx(Vector2.ONE) and button.self_modulate.is_equal_approx(original_color),"mouse exit restores original scale and color")
	await capture("component-recovered")
	check_settled("completed click feedback")

	# Native field input rebuilds the real roster; replacement cards must receive
	# the same art and feedback rather than falling back to the engine theme.
	await click(preview.search)
	await type_character("T")
	await wait_real(.25)
	check(preview.search.text == "T" and preview.filtered.size() == 1 and preview.filtered[0].id == "t_cell","painted search keeps native editing and filtering")
	check(preview.search.scale.x > 1.0,"focused native search receives feedback")
	var rebuilt := preview.grid.get_node_or_null("Card_t_cell") as Button
	check(rebuilt != null and check_surface(rebuilt.get_theme_stylebox("normal"),"rebuilt card"),"filtered replacement card retains its painted surface")
	check(rebuilt != null and is_instance_valid(rebuilt.get_meta("_catalogue_motion_helper",null)),"filtered replacement card retains attached feedback")
	var field_rect := preview.search.get_global_rect()
	var clear_icon := preview.search.get_theme_icon("clear")
	var inset := float(clear_icon.get_width())*.5+preview.search.get_theme_stylebox("normal").get_content_margin(SIDE_RIGHT)
	var clear_point := Vector2(field_rect.end.x-inset,field_rect.get_center().y)
	await move_mouse(clear_point); await mouse_button(clear_point,true); await mouse_button(clear_point,false)
	await wait_real(.25)
	check(preview.search.text.is_empty() and preview.filtered.size() == 24,"painted clear icon preserves native clear behavior")
	await rest_pointer()
	check(preview.search.scale.is_equal_approx(Vector2.ONE),"search feedback returns to rest")

	var worker := preview.grid.get_node("Card_worker") as Button
	await click(worker)
	check(preview.player.modulate.a < 1.0 and preview.information.modulate.a < 1.0,"character selection starts native artwork and information reveals")
	await wait_real(.28)
	await rest_pointer()
	check(preview.player.modulate.a >= .99 and preview.information.modulate.a >= .99 and preview.detail_name_row.modulate.a >= .99,"selected character artwork and copy finish fully visible")
	await reveal_for_click(preview.pause_button)
	await move_mouse(visible_rect(preview.pause_button).get_center()); await wait_real(.18)
	check(preview.pause_button.scale.x > 1.0,"enabled playback control can receive hover feedback")
	await click(preview.next_action_button)
	check(preview.player.mode == 1 and preview.pause_button.disabled,"native action arrow selects portrait and disables playback")
	await wait_real(.25)
	check(preview.pause_button.scale.is_equal_approx(Vector2.ONE) and not bool(preview.pause_button.get_meta("catalogue_motion_running",true)),"disabling through portrait selection cancels playback feedback")
	var presses_before_disabled := pause_presses
	await click(preview.pause_button)
	await wait_real(.18)
	check(pause_presses == presses_before_disabled and preview.player.mode == 1 and preview.pause_button.scale.is_equal_approx(Vector2.ONE),"disabled native playback ignores clicks and stays at rest")

	await click(preview.next_action_button)
	await reveal_for_click(preview.pause_button)
	await move_mouse(visible_rect(preview.pause_button).get_center()); await wait_real(.18)
	await click(preview.map_tab)
	check(preview.page == "maps" and preview.map_view.modulate.a < 1.0,"native page click starts the selected page reveal")
	check(preview.pause_button.scale.is_equal_approx(Vector2.ONE) and not bool(preview.pause_button.get_meta("catalogue_motion_running",true)),"hiding the character page cancels its button feedback")
	check(preview.player.modulate.a >= .99 and not bool(preview.player.get_meta("catalogue_reveal_running",false)),"hidden artwork never retains an unfinished transparent reveal")
	await wait_real(.28)
	await rest_pointer()
	check_settled("map page reveal")

	for tab in [preview.building_tab,preview.character_tab,preview.map_tab,preview.character_tab,preview.building_tab,preview.map_tab,preview.character_tab]:
		await click(tab,.005)
	await wait_real(.30)
	await rest_pointer()
	check(preview.page == "characters" and preview.character_view.visible and not preview.map_view.visible and not preview.building_view.visible,"rapid native page clicks preserve the final selected page")
	check_settled("rapid page changes")
	for id in ["spear","worker","b_cell","worker"]:
		var card := preview.grid.get_node("Card_"+id) as Button
		await click(card,.005)
	await wait_real(.30)
	await rest_pointer()
	check(preview.selected_id == "worker" and preview.player.modulate.a >= .99,"rapid character changes finish on the chosen fully visible character")
	check_settled("rapid character changes")
	check_controls("rebuilt roster")

	await click(preview.replay_button,.005)
	await click(preview.close_button,.005)
	await wait_real(.06)
	check(not preview.visible and close_count == 1,"closing during feedback returns control exactly once")
	check_settled("closed archive")
	preview.open()
	await frames()
	await click(preview.map_tab,.005)
	await click(preview.close_button,.005)
	await wait_real(.06)
	check(not preview.visible and close_count == 2,"reopen then close during a page reveal remains reliable")
	check_settled("second close")
	preview.queue_free()
	await wait_real(.10)
	check(get_processed_tweens().is_empty(),"freeing the archive leaves no orphan tween")
	var report := FileAccess.open(OUTPUT.path_join("report.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"screenshots":screenshots,"display":DisplayServer.get_name(),"painted_surfaces":checked_surfaces.keys(),"painted_icons":checked_icons.keys(),"scope":"standalone catalogue component art and native interaction; three-size flow remains catalogue_polish.gd"},"  ")+"\n")
	report.close()
	print("CATALOGUE COMPONENTS DONE ",checks," checks; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
