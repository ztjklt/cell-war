extends SceneTree
## Native catalogue interaction/layout regression. Does not instantiate a battle.
## Headless: ./godot/run.sh --headless --script res://tests/catalogue_polish.gd
## Screenshots: ./godot/run.sh --script res://tests/catalogue_polish.gd

const OUTPUT := "res://test-output/catalogue-polish"
const SIZES := [Vector2i(1280,800),Vector2i(360,780),Vector2i(844,390)]
var checks := 0
var failures: Array[String] = []
var screenshots: Array[String] = []
var preview: WarCoverPreview
var case_name := ""
var closed_count := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,message: String) -> void:
	checks += 1
	var label := case_name+" "+message
	if value: print("PASS ",label)
	else:
		failures.append(label)
		printerr("FAIL ",label)

func settle() -> void:
	for _frame in 4: await process_frame

func settle_page() -> void:
	# Newly shown wrapping labels can require another container layout pass.
	for _frame in 15: await process_frame

func viewport_rect() -> Rect2:
	return Rect2(Vector2.ZERO,Vector2(root.content_scale_size))

func visible_rect(control: Control) -> Rect2:
	if not control.is_visible_in_tree(): return Rect2()
	var rect := control.get_global_rect().intersection(viewport_rect())
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is Control and ancestor.clip_contents:
			rect = rect.intersection(ancestor.get_global_rect())
		ancestor = ancestor.get_parent()
	return rect

func reveal(control: Control) -> void:
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			ancestor.ensure_control_visible(control)
		ancestor = ancestor.get_parent()
	await settle()

func click_point(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = root.get_stretch_transform()*point
	root.push_input(motion)
	var event := InputEventMouseButton.new()
	event.position = root.get_stretch_transform()*point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)
	await settle()

func click(control: Control,label: String) -> void:
	await reveal(control)
	var rect := visible_rect(control)
	var reachable := rect.size.x >= 20 and rect.size.y >= 20
	check(reachable,label+" has a reachable click target")
	if reachable: await click_point(rect.get_center())

func key(code: int,target: Viewport = null,unicode_value := 0) -> void:
	if target == null: target = root
	var event := InputEventKey.new()
	event.keycode = code
	event.unicode = unicode_value
	event.pressed = true
	target.push_input(event)
	event = event.duplicate()
	event.pressed = false
	target.push_input(event)
	await settle()

func query(text: String) -> void:
	await click(preview.search,"search field")
	preview.search.select_all()
	await key(KEY_BACKSPACE)
	for character in text:
		await key(KEY_NONE,root,character.unicode_at(0))
	await settle()
	check(preview.search.text == text,"search accepts keyboard text: "+text)

func clear_query() -> void:
	await reveal(preview.search)
	var icon := preview.search.get_theme_icon("clear")
	var rect := preview.search.get_global_rect()
	var inset := float(icon.get_width())*.5+float(preview.search.get_theme_stylebox("normal").get_content_margin(SIDE_RIGHT))
	await click_point(Vector2(rect.end.x-inset,rect.get_center().y))
	check(preview.search.text.is_empty(),"native clear icon empties the search")

func choose_card(id: String) -> void:
	var card := preview.grid.get_node_or_null("Card_"+id) as Button
	check(card != null,"roster contains "+id)
	if card == null: return
	await click(card,"character card "+id)
	check(preview.selected_id == id and preview.detail_scroll.is_visible_in_tree(),"click opens "+id+" details")
	if preview.compact:
		check(not preview.sidebar.visible and preview.detail_back.is_visible_in_tree(),"compact details replace the sidebar and expose a back button")
	check_geometry("details "+id)

func return_to_list() -> void:
	if preview.compact and preview.mobile_detail:
		await click(preview.detail_back,"detail back button")
		check(preview.sidebar.is_visible_in_tree() and not preview.detail_scroll.visible,"back button restores compact roster")

func check_geometry(state: String) -> void:
	var panel_rect := preview.panel.get_global_rect()
	if state == "opening" and not preview.compact:
		for control in [preview.action_picker,preview.pause_button,preview.replay_button]:
			check(visible_rect(control).grow(1).encloses(control.get_global_rect()),"desktop playback controls are visible without scrolling")
	check(viewport_rect().grow(1).encloses(panel_rect),state+" panel stays within viewport: "+str(panel_rect))
	check(preview.panel.size.x > 0 and preview.panel.size.y > 0,state+" panel has usable size")
	for control in [preview.close_button,preview.character_tab,preview.map_tab,preview.building_tab]:
		check(viewport_rect().grow(1).encloses(control.get_global_rect()),state+" navigation remains inside viewport: "+control.text)
	if preview.sidebar.is_visible_in_tree():
		check(preview.sidebar.is_ancestor_of(preview.filters) and preview.sidebar.is_ancestor_of(preview.search) and preview.sidebar.is_ancestor_of(preview.roster),"sidebar contains filters, search and roster")
		check(preview.roster.size.y >= 150,state+" roster provides at least one full 150-pixel card row")
		if root.content_scale_size == Vector2i(844,390) and not preview.filtered.is_empty():
			var first: Dictionary = preview.filtered[0]
			var card := preview.grid.get_node_or_null("Card_"+str(first.id)) as Button
			var name_label: Label = null
			if card != null:
				for candidate in card.find_children("*","Label",true,false):
					if candidate.text == str(first.name): name_label = candidate; break
			check(name_label != null,state+" first card exposes its character name")
			if name_label != null:
				check(visible_rect(name_label).grow(1).encloses(name_label.get_global_rect()),state+" first card name is completely inside the visible roster; label="+str(name_label.get_global_rect())+", visible="+str(visible_rect(name_label))+", roster="+str(preview.roster.get_global_rect()))
				var text_width := name_label.get_theme_font("font").get_string_size(name_label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,name_label.get_theme_font_size("font_size")).x
				check(text_width <= name_label.size.x+1,state+" first card name fits without truncation")
	if preview.detail_scroll.is_visible_in_tree():
		check(preview.detail_scroll.size.y >= 80,state+" details retain a usable scrolling area")
		check(preview.detail.size.x <= preview.detail_scroll.size.x+1,state+" details do not overflow horizontally")

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await create_timer(.15).timeout
	await RenderingServer.frame_post_draw
	var path := OUTPUT.path_join(case_name+"-"+label+".png")
	var error := root.get_texture().get_image().save_png(path)
	check(error == OK,"screenshot saved: "+label)
	if error == OK: screenshots.append(path)

func wait_for_art() -> void:
	var deadline := Time.get_ticks_msec()+5000
	while not preview.player.loaded and Time.get_ticks_msec() < deadline:
		await create_timer(.025).timeout
	check(preview.player.loaded,"selected artwork finishes loading")

func choose_action(index: int) -> void:
	# Exercise the public action arrows with viewport mouse input. PopupMenu is a
	# separate native Window, so root.push_input cannot emulate its OS event route.
	var remaining := preview.action_picker.item_count
	while preview.player.mode != index and remaining > 0:
		await click(preview.next_action_button,"action selection arrow")
		remaining -= 1
	check(preview.action_picker.selected == index and preview.player.mode == index,"action arrows select the requested clip and synchronize the menu")

func wheel(scroll: ScrollContainer) -> void:
	var point := visible_rect(scroll).get_center()
	for _tick in 8:
		var event := InputEventMouseButton.new()
		event.position = root.get_stretch_transform()*point
		event.button_index = MOUSE_BUTTON_WHEEL_DOWN
		event.pressed = true
		root.push_input(event)
		event = event.duplicate()
		event.pressed = false
		root.push_input(event)
	await settle()

func named_button(parent: Node,text: String) -> Button:
	for child in parent.find_children("*","Button",true,false):
		if child.text == text: return child
	return null

func exercise_size(window_size: Vector2i) -> void:
	case_name = "%dx%d" % [window_size.x,window_size.y]
	root.size = window_size
	root.content_scale_size = window_size
	await settle()
	preview = WarCoverPreview.new()
	root.add_child(preview)
	preview.closed.connect(func(): closed_count += 1)
	preview.open()
	await settle()
	check(preview.character_count == 24,"all 24 authored entries remain available")
	check(preview.sidebar.is_visible_in_tree(),"opening starts with an accessible roster")
	check_geometry("opening")
	await capture("roster")
	for _tab in 4:
		await key(KEY_TAB)
		check(preview.is_ancestor_of(root.gui_get_focus_owner()),"Tab focus remains inside the archive")
	await click(preview.category_buttons.cells,"cells filter")
	check(preview.category == "cells" and preview.filtered.size() == 10,"cells filter shows all 10 cells")
	await query("巨噬")
	check(preview.filtered.size() == 1 and preview.filtered[0].id == "siege","Chinese search finds the macrophage")
	await query("zzzz")
	check(preview.filtered.is_empty() and not preview.detail_scroll.visible,"no-result search hides stale details")
	check(preview.previous_button.disabled and preview.next_button.disabled,"empty results disable character navigation")
	check_geometry("no results")
	await capture("empty-search")
	await clear_query()
	check(preview.filtered.size() == 10,"clearing restores the selected category")
	await choose_card("worker")
	await wait_for_art()
	await capture("cell-detail")
	check(preview.player.mode == 0 and preview.player.entry.actions.size() > 1,"worker enters a complete multi-action cycle")
	var previous_action_index := preview.player.action_index
	preview.player.advance(maxf(0,preview.player.cycle_duration()-preview.player.elapsed)+.001)
	check(preview.player.action_index == (previous_action_index+1)%preview.player.entry.actions.size(),"complete cycle advances to the next authored action")
	var cycled_action_name := str(preview.player.current_action().name)
	check(preview.action_caption.text.contains(cycled_action_name),"visible action caption immediately names the newly cycled action")
	await wait_for_art()
	check(preview.action_caption.text.contains(str(preview.player.current_action().name)),"action caption stays synchronized after the next atlas loads")
	await click(preview.pause_button,"pause")
	check(not preview.player.playing,"pause stops playback")
	var paused_time := preview.player.elapsed
	await create_timer(.08).timeout
	check(is_equal_approx(preview.player.elapsed,paused_time),"paused timeline remains still")
	await click(preview.replay_button,"replay")
	check(preview.player.playing and preview.player.elapsed < .3 and preview.player.action_index == 0,"replay starts the action cycle again from the beginning")
	await click(preview.next_button,"next character")
	check(preview.selected_id == "spear","next character follows the filtered roster")
	await click(preview.previous_button,"previous character")
	check(preview.selected_id == "worker","previous character returns within the filtered roster")
	await return_to_list()
	await query("巨噬")
	await choose_card("siege")
	var longest_index := -1
	for i in preview.player.entry.actions.size():
		if str(preview.player.entry.actions[i].name).contains("夸张吞噬"):
			longest_index = i+2
	check(longest_index >= 2,"authored long action name is present")
	if longest_index >= 2:
		await choose_action(longest_index)
		check(str(preview.player.current_action().get("name","")).contains("夸张吞噬"),"long action selection reaches its original clip")
		check_geometry("long action")
		await wait_for_art()
		await capture("long-action-controls")
		await click(preview.previous_action_button,"previous action")
		check(preview.player.mode == longest_index-1,"previous action keeps the original sequence")
		await click(preview.next_action_button,"next action")
		check(preview.player.mode == longest_index,"next action returns to the selected long action")
		var last_action_name := str(preview.player.current_action().name)
		await choose_action(1)
		check(preview.player.current_action().is_empty() and preview.action_caption.text == "形象立绘","selecting the same character portrait replaces its action caption")
		check(preview.action_picker.tooltip_text == "角色立绘" and not preview.action_picker.tooltip_text.contains(last_action_name),"portrait mode removes the previous action tooltip")
	await return_to_list()
	await clear_query()
	await click(preview.category_buttons.medicines,"medicines filter")
	check(preview.category == "medicines" and preview.filtered.size() == 5,"medicines filter preserves five entries")
	await choose_card("expectorant")
	check(preview.player.mode == 1 and preview.player.current_action().is_empty(),"portrait-only entry does not invent animation")
	check(preview.action_caption.text == "形象立绘" and preview.action_picker.tooltip_text == "角色立绘","portrait-only entry has a static caption and no stale action tooltip")
	check(preview.pause_button.disabled and preview.replay_button.disabled and preview.previous_action_button.disabled and preview.next_action_button.disabled,"portrait-only playback controls are disabled")
	await wait_for_art()
	await capture("portrait-only")
	await click(preview.map_tab,"map tab")
	await settle_page()
	check(preview.page == "maps" and preview.map_tab.button_pressed and not preview.character_tab.button_pressed and not preview.building_tab.button_pressed,"map tab selects independently")
	check(not preview.player.is_processing(),"hidden character player stops processing on maps")
	var heart := named_button(preview.map_view,"心脏")
	check(heart != null,"heart map selector exists")
	if heart != null: await click(heart,"heart map selector")
	check(preview.map_canvas.region.size.x < 1024 and not preview.map_canvas.tiles.is_empty(),"heart selector uses original regional map tiles")
	check_geometry("map page")
	await capture("heart-map")
	await click(preview.building_tab,"building tab")
	await settle_page()
	check(preview.page == "buildings" and preview.building_tab.button_pressed and not preview.character_tab.button_pressed and not preview.map_tab.button_pressed,"building tab selects independently")
	var building_scroll := preview.building_view.get_node("BuildingPreviewScroll") as ScrollContainer
	check(building_scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,"buildings keep vertical scrolling")
	await wheel(building_scroll)
	check(building_scroll.scroll_vertical > 0,"mouse wheel scrolls building cards")
	check_geometry("building page")
	await capture("buildings")
	await click(preview.character_tab,"character tab")
	await settle_page()
	check(preview.page == "characters" and preview.character_tab.button_pressed,"character tab returns to the archive")
	await return_to_list()
	await click(preview.category_buttons.cells,"cells filter after tabs")
	await choose_card("worker")
	var before_close := closed_count
	await key(KEY_ESCAPE)
	if preview.compact:
		check(preview.visible and not preview.mobile_detail and preview.sidebar.is_visible_in_tree(),"Escape from compact details returns to the list")
		check(closed_count == before_close,"first Escape does not close compact details entirely")
		await key(KEY_ESCAPE)
	check(not preview.visible and closed_count == before_close+1,"Escape closes the archive exactly once")
	check(not preview.player.is_processing(),"closed preview stops character processing")
	preview.open()
	await settle()
	await click(preview.close_button,"return to cover")
	check(not preview.visible and closed_count == before_close+2,"return button closes the read-only archive")
	preview.queue_free()
	await settle()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var original_catalogue := JSON.stringify(WarData.read("character_catalogue"))
	for window_size in SIZES:
		await exercise_size(window_size)
	case_name = "shared"
	check(JSON.stringify(WarData.read("character_catalogue")) == original_catalogue,"preview interactions leave catalogue data unchanged")
	var report := FileAccess.open(OUTPUT.path_join("report.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"screenshots":screenshots,"display":DisplayServer.get_name(),"scope":"standalone read-only catalogue, three viewport sizes; not battle or physical-device acceptance"},"  ")+"\n")
	report.close()
	print("CATALOGUE POLISH DONE ",checks," checks; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
