extends SceneTree
## Ensures the preview archive exposes a scrollable building section.
var failures: Array[String] = []

func check(value: bool, text: String) -> void:
	if value: print("PASS "+text)
	else:
		failures.append(text)
		printerr("FAIL "+text)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var preview := WarCoverPreview.new()
	root.add_child(preview)
	preview.open()
	for _frame in 2: await process_frame
	preview.show_buildings()
	for _frame in 2: await process_frame
	check(preview.page == "buildings" and preview.building_view.visible,"building preview is the third archive section")
	var scroll := preview.building_view.get_node_or_null("BuildingPreviewScroll") as ScrollContainer
	check(scroll != null and scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,"building preview supports vertical phone scrolling")
	check(preview.building_tab.button_pressed and not preview.character_tab.button_pressed and not preview.map_tab.button_pressed,"building tab selects independently")
	preview.queue_free()
	await process_frame
	print("COVER PREVIEW ",failures)
	quit(0 if failures.is_empty() else 1)
