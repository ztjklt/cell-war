extends SceneTree
## Native input + source completeness + playback lifecycle, without a battle instance.
var failures: Array[String] = []
var checks := 0
var preview: WarCoverPreview

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("FAIL ",message)
	else: print("PASS ",message)

func settle() -> void:
	for i in 8: await process_frame

func press_node(button: Control) -> void:
	if preview.roster.is_ancestor_of(button): preview.roster.ensure_control_visible(button)
	if preview.detail_scroll.is_ancestor_of(button): preview.detail_scroll.ensure_control_visible(button)
	await settle()
	var event := InputEventMouseButton.new()
	var visible_rect := button.get_global_rect()
	var ancestor := button.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer: visible_rect = visible_rect.intersection(ancestor.get_global_rect())
		ancestor = ancestor.get_parent()
	event.position = root.get_stretch_transform()*visible_rect.get_center()
	event.button_index = MOUSE_BUTTON_LEFT; event.pressed = true; root.push_input(event)
	event = event.duplicate(); event.pressed = false; root.push_input(event)
	await settle()

func press(text: String) -> void:
	for button in preview.find_children("*","Button",true,false):
		if button.text == text and button.is_visible_in_tree():
			await press_node(button); return
	check(false,"button exists: "+text)

func key(code: Key,shift := false) -> void:
	var event := InputEventKey.new(); event.keycode = code; event.pressed = true; event.shift_pressed = shift
	var viewport: Viewport = root
	viewport.push_input(event); event = event.duplicate(); event.pressed = false; viewport.push_input(event)
	await settle()

func choose_action(index: int) -> void:
	if preview.size.y < 500:
		for i in preview.action_picker.item_count:
			if preview.player.mode == index: break
			await press_node(preview.next_action_button)
		check(preview.player.mode == index,"native action arrows select requested item in short landscape")
		return
	await press_node(preview.action_picker)
	var popup := preview.action_picker.get_popup()
	for i in popup.item_count+2:
		if popup.get_focused_item() == index: break
		await key(KEY_DOWN)
	check(popup.get_focused_item() == index,"native action popup focuses requested item")
	await key(KEY_ENTER)

func type_text(value: String) -> void:
	for character in value:
		var event := InputEventKey.new(); event.unicode = character.unicode_at(0); event.pressed = true
		root.push_input(event)
		event = event.duplicate(); event.pressed = false; root.push_input(event)
	await settle()

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test-output/cover/"+name+".png")

func wait_for_art() -> void:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec()-start < 8000:
		if preview.player.loaded: break
		await process_frame
	await settle()

func wait_for_map() -> void:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec()-start < 8000:
		if preview.map_canvas.textures.cache.size() >= preview.map_canvas.tiles.size(): break
		await process_frame
	await settle()

func verify_catalogue() -> void:
	var ids: Dictionary = {}
	var kinds: Dictionary = {}
	var dimensions: Dictionary = {}
	var total_actions := 0
	for entry in preview.entries:
		check(not ids.has(entry.id),"unique character "+entry.id); ids[entry.id] = true
		if not str(entry.kind).is_empty(): kinds[entry.kind] = true
		check(ResourceLoader.exists(entry.portrait),"installed portrait "+entry.id)
		check(not entry.summary.is_empty() and not entry.mechanics.is_empty() and not entry.status.is_empty(),"mechanics and status "+entry.id)
		var valid := true
		for action in entry.actions:
			total_actions += 1
			if not dimensions.has(action.path):
				var image := Image.load_from_file(action.path)
				dimensions[action.path] = image.get_size()
			var duration := 0.0
			for frame in action.frames:
				var r: Array = frame.rect
				valid = valid and r[0] >= 0 and r[1] >= 0 and r[2] > 0 and r[3] > 0
				valid = valid and r[0]+r[2] <= dimensions[action.path].x and r[1]+r[3] <= dimensions[action.path].y
				valid = valid and float(frame.duration) > 0
				duration += float(frame.duration)
			valid = valid and is_equal_approx(duration,float(action.duration))
		check(valid,"all frame rectangles and timings valid "+entry.id)
	for kind in WarData.config().Data.units:
		check(kinds.has(kind),"existing runtime kind covered "+kind)
	check(total_actions == int(WarData.read("character_catalogue").actionCount) and total_actions >= 88,"all authored actions and auxiliary graphics are registered")
	# Exercise every sequence through its complete cycle, including transparent death endings.
	var player := WarCataloguePlayer.new()
	for entry in preview.entries:
		if entry.actions.is_empty(): continue
		player.select(entry)
		for i in entry.actions.size():
			check(player.action_index == i,"sequence visits action %s/%d" % [entry.id,i])
			player.advance(player.cycle_duration()+.000001)
		check(player.cycles == 1 and player.action_index == 0 and player.frame_index == 0,"complete cycle restarts "+entry.id)
	player.free()

func run() -> void:
	# Embed native popup windows so synthetic viewport input reaches the open menu.
	root.gui_embed_subwindows = true
	DirAccess.make_dir_recursive_absolute("res://test-output/cover")
	preview = WarCoverPreview.new(); root.add_child(preview)
	verify_catalogue()
	for dimensions in [Vector2i(1280,800),Vector2i(360,780),Vector2i(844,390)]:
		root.size = dimensions; root.content_scale_size = dimensions
		preview.open(); preview.set_category("all"); preview.search.text = ""; preview._rebuild_roster()
		await settle()
		var rect := preview.panel.get_global_rect()
		check(rect.position.x >= 0 and rect.end.x <= dimensions.x+1 and rect.position.y >= 0 and rect.end.y <= dimensions.y+1,"preview panel fits "+str(dimensions)+" "+str(rect))
		check(preview.character_count == 24,"complete 24-character catalogue "+str(dimensions))
		check(preview.close_button.get_global_rect().position.y >= 0,"return control remains on screen")
		await capture("characters-%dx%d" % [dimensions.x,dimensions.y])
		await press("细胞"); check(preview.filtered.size() == 10,"native cell category")
		await press_node(preview.grid.get_node("Card_b_cell"))
		check(preview.selected_id == "b_cell" and preview.detail_scroll.visible,"native character selection opens detail")
		await wait_for_art(); check(preview.player.loaded,"selected character art loads")
		await press("暂停")
		var elapsed := preview.player.elapsed
		await create_timer(.15).timeout
		check(not preview.player.playing and is_equal_approx(elapsed,preview.player.elapsed),"pause freezes animation")
		await press("重播")
		check(preview.player.frame_index == 0 and is_zero_approx(preview.player.elapsed),"replay rewinds while paused")
		await press("播放"); await create_timer(.15).timeout
		check(preview.player.playing and preview.player.elapsed > 0,"play resumes animation")
		await choose_action(1)
		check(preview.player.mode == 1 and preview.pause_button.disabled,"native action menu selects static portrait")
		await choose_action(2)
		check(preview.player.mode >= 2 and not preview.pause_button.disabled,"native action menu selects an individual clip")
		preview.player.playing = false
		var selected_action := preview.player.action_index
		preview.player.advance(preview.player.cycle_duration()-preview.player.elapsed+.000001)
		check(preview.player.action_index == selected_action and preview.player.frame_index == 0,"individual action loops without switching role")
		await press_node(preview.previous_action_button)
		check(preview.player.mode == 1,"native previous action arrow returns to portrait")
		await press_node(preview.next_action_button)
		check(preview.player.mode == 2,"native next action arrow returns to clip")
		preview.detail_scroll.scroll_vertical = 0; await settle()
		await capture("b-cell-detail-%dx%d" % [dimensions.x,dimensions.y])
		if preview.compact:
			await key(KEY_ESCAPE)
			check(preview.visible and preview.roster.visible and not preview.detail_scroll.visible,"Escape returns from narrow detail to list")
		await press("药物"); check(preview.filtered.size() == 5,"native medicine category")
		await press_node(preview.grid.get_node("Card_antibiotic"))
		await wait_for_art()
		preview.detail_scroll.scroll_vertical = 0; await settle()
		await capture("medicine-detail-%dx%d" % [dimensions.x,dimensions.y])
		preview.select_character("expectorant",preview.compact); await settle()
		check(preview.player.mode == 1 and preview.pause_button.disabled,"portrait-only character has no fake animation")
		check((preview.status_label.text.contains("提案") or preview.status_label.text.contains("草案")) and preview.player.entry.get("confirmation",{}).get("mechanic","draft") == "draft","unconfirmed mechanic is labeled as proposal")
		preview.select_character("antibiotic"); await press("‹ 上一个")
		check(preview.selected_id == "expectorant","previous character wraps within category")
		await press("下一个 ›"); check(preview.selected_id == "antibiotic","next character wraps within category")
		if preview.compact: await press_node(preview.detail_back)
		await press("病原体"); check(preview.filtered.size() == 9,"native pathogen category includes original parasites")
		await press("全部")
		await press_node(preview.search)
		await type_text("牵手")
		check(preview.filtered.size() == 1 and preview.filtered[0].id == "scout","native search matches mechanism: "+preview.search.text)
		await press("清空"); await press_node(preview.search)
		await type_text("不存在的角色")
		check(preview.filtered.is_empty() and not preview.detail_scroll.visible and preview.next_button.disabled,"empty search hides stale detail and disables navigation")
		await press("清空"); check(preview.filtered.size() == 24,"clear restores all characters")
		await press("地图预览"); check(preview.page == "maps" and not preview.player.is_processing(),"map tab suspends character playback")
		await wait_for_map()
		check(preview.map_canvas.textures.cache.size() >= preview.map_canvas.tiles.size(),"complete map textures load")
		await press("心脏"); await wait_for_map()
		check(preview.map_canvas.region.size.x < 1024,"native map region switch")
		await capture("heart-preview-%dx%d" % [dimensions.x,dimensions.y])
		await press("角色预览")
		check(not preview.map_canvas.is_processing(),"character tab suspends hidden map")
		for i in 4:
			await key(KEY_TAB,i%2 == 0)
			check(preview.is_ancestor_of(root.gui_get_focus_owner()),"keyboard focus stays in modal")
		await press("返回封面")
		check(not preview.visible and not preview.player.is_processing() and not preview.map_canvas.is_processing(),"return stops both preview renderers")
		check(preview.player.textures.cache.is_empty() and preview.map_canvas.textures.cache.is_empty(),"closing releases streaming texture memory")
		preview.open(); await settle()
		check(preview.visible and preview.filtered.size() == 24,"preview can reopen after complete flow")
		preview.close()
	var file := FileAccess.open("res://test-output/cover/preview-checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"nativeInput":true,"readOnly":true,"characters":24,"actions":WarData.read("character_catalogue").actionCount},"  "))
	print("COVER PREVIEW DONE ",checks," checks ",failures)
	preview.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
