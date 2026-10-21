extends SceneTree
## Focused synchronization checks for reconnaissance and the five medicine entries.
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("FAIL ",message)
	else: print("PASS ",message)

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://test-output/cover")
	root.size = Vector2i(1280,800); root.content_scale_size = root.size
	var preview := WarCoverPreview.new(); root.add_child(preview)
	preview.open(); preview.select_character("dendritic_cell")
	for i in 5: await process_frame
	var entry: Dictionary = preview.player.entry
	var runtime: Dictionary = WarData.read("dendritic_cell")
	check(entry.kind == "dendritic_cell" and not WarData.spec(entry.kind).is_empty(),"reconnaissance links to an existing runtime unit")
	check(entry.status == "现役单位" and preview.status_label.text == entry.status,"reconnaissance is displayed as active, not preview-only")
	check(entry.runtimeDefinition == "res://data/dendritic_cell.json" and FileAccess.file_exists(entry.runtimeDefinition),"runtime definition cross-link resolves within Godot")
	check(runtime.scan.moveMultiplier == .7 and runtime.scan.attackSpeedMultiplier == .7,"both current speed multipliers remain 0.7")
	check(str(entry.mechanics).contains("移动速度降低 30%") and str(entry.mechanics).contains("攻击速度降低 30%"),"gallery explains both thirty-percent reductions")
	check(str(entry.mechanics).contains("地下") and runtime.scan.detectConcealed,"underground marking agrees with the enabled runtime capability")
	check(str(entry.note).contains("不会强制出土") and str(entry.note).contains("仍待接入"),"underground marking is distinct from pending automatic burrowing")
	var clip_keys := ["dcMove","dcScan","dcHit","dcDeath"]
	check(entry.actions.size() == 4,"only the four delivered reconnaissance actions are listed")
	for i in clip_keys.size():
		var clip: Dictionary = runtime.clips[clip_keys[i]]
		var action: Dictionary = entry.actions[i]
		check(action.path == "res://assets/"+str(clip.path) and ResourceLoader.exists(action.path),"current runtime atlas "+clip_keys[i])
		check(action.frames.size() == [16,6,12,12][i],"delivered frame count "+clip_keys[i])
		var exact := true
		for j in action.frames.size():
			var rect: Array = action.frames[j].rect
			exact = exact and is_equal_approx(float(action.frames[j].duration),float(clip.durations[j]))
			exact = exact and rect == [float(j%int(clip.columns))*clip.frameSize,float(j/int(clip.columns))*clip.frameSize,clip.frameSize,clip.frameSize]
		check(exact,"gallery rectangles and timing equal runtime "+clip_keys[i])
		preview.action_picker.select(i+2); preview.action_picker.item_selected.emit(i+2)
		check(preview.player.current_action().path == action.path,"action menu selects current clip "+clip_keys[i])
	preview.player.select_mode(0)
	if DisplayServer.get_name() != "headless":
		await create_timer(.3).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://test-output/cover/dendritic-synchronized.png")
	var medicines: Dictionary = WarData.read("medicines")
	preview.set_category("medicines")
	check(medicines.runtime.canSell and medicines.runtime.medicineEffectsImplemented and medicines.runtime.enabledMedicineIds==["fever_pain_relief"],"medicine authority opens only the validated first medicine")
	for medicine in medicines.entries:
		preview.select_character(medicine.id)
		entry = preview.player.entry
		check(entry.medicineDefinition == "res://data/medicines.json" and entry.medicineDefinitionId == medicine.id,"medicine definition link "+medicine.id)
		check(entry.confirmation == medicine.confirmation and entry.status == medicine.gallery.status,"confirmation boundary matches authority "+medicine.id)
		check(entry.mechanics == medicine.gallery.mechanics and entry.note == medicine.gallery.note,"mechanic copy matches authority "+medicine.id)
		var released: bool = medicine.id in medicines.runtime.enabledMedicineIds
		check(entry.canPurchase==medicine.purchase.canSell and entry.canDeploy==medicine.purchase.canDeploy and entry.kind==(medicine.id if released else ""),"gallery purchase and deployment match individual release "+medicine.id)
		check(preview.status_label.text == medicine.gallery.status,"actual page shows the canonical status "+medicine.id)
		check(entry.actions.size() == medicine.assets.animations.size()+medicine.assets.stills.size(),"menu includes exactly delivered medicine assets "+medicine.id)
		if medicine.id == "expectorant":
			check(entry.actions.is_empty() and preview.player.mode == 1 and preview.pause_button.disabled,"expectorant remains portrait-only with no fake actions")
			check(entry.confirmation.mechanic == "draft" and entry.status.contains("草案"),"expectorant proposed effects remain explicitly draft")
	preview.close(); preview.queue_free(); await process_frame
	DirAccess.make_dir_recursive_absolute("res://test-output/cover")
	var file := FileAccess.open("res://test-output/cover/catalogue-sync.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"dendritic_cell and five canonical medicine entries only"},"  "))
	print("CATALOGUE SYNC DONE ",checks," checks ",failures)
	quit(0 if failures.is_empty() else 1)
