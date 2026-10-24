extends SceneTree
## Offline crops of approved GPT artwork; never used by the running game.
## ./godot/run.sh --headless --script /absolute/repository/scripts/godot_tools/build_catalogue_components.gd

const SOURCE_DIRECTORY := "assets/image/catalogue-components-20261024"
const OUTPUT_DIRECTORY := "godot/assets/ui/catalogue/components"
const PANEL_CROP := Rect2i(42, 46, 1170, 1166)
const ICON_CELL := 362
const ICON_ALPHA_THRESHOLD := .25
const ICON_CANVAS := 24
const ICON_GLYPH := 20
const ICON_NAMES := ["left", "right", "play", "pause", "replay", "search", "close", "down", "cell", "map", "building", "check"]

var repository := ""
var entries: Array[Dictionary] = []
var errors: Array[String] = []

func _initialize() -> void:
	call_deferred("build")

func fail(message: String) -> void:
	errors.append(message)
	printerr("CATALOGUE COMPONENTS: ", message)

func load_source(relative_path: String, expected_size := Vector2i.ZERO) -> Image:
	var image := Image.load_from_file(repository.path_join(relative_path))
	if image == null or image.is_empty():
		fail("cannot decode " + relative_path)
		return null
	if expected_size != Vector2i.ZERO and image.get_size() != expected_size:
		fail("unexpected dimensions in " + relative_path + ": " + str(image.get_size()))
		return null
	image.convert(Image.FORMAT_RGBA8)
	return image

func rect_values(rect: Rect2i) -> Array[int]:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]

func save_component(image: Image, name_value: String, source_path: String, source_size: Vector2i, crop: Rect2i, extra: Dictionary = {}) -> void:
	var relative_path := OUTPUT_DIRECTORY.path_join(name_value + ".png")
	var absolute_path := repository.path_join(relative_path)
	var error := image.save_png(absolute_path)
	if error != OK:
		fail("cannot save " + relative_path + ": " + error_string(error))
		return
	var row := {
		"id": name_value,
		"source": source_path,
		"source_sha256": FileAccess.get_sha256(repository.path_join(source_path)),
		"source_size": [source_size.x, source_size.y],
		"crop_rect": rect_values(crop),
		"output": relative_path,
		"output_resource": "res://" + relative_path.trim_prefix("godot/"),
		"output_sha256": FileAccess.get_sha256(absolute_path),
		"output_size": [image.get_width(), image.get_height()],
		"alpha_preserved": true,
	}
	row.merge(extra)
	entries.append(row)

func alpha_bounds(image: Image, cell: Rect2i) -> Rect2i:
	var minimum := cell.end
	var maximum := cell.position - Vector2i.ONE
	for y in range(cell.position.y, cell.end.y):
		for x in range(cell.position.x, cell.end.x):
			if image.get_pixel(x, y).a > ICON_ALPHA_THRESHOLD:
				minimum.x = mini(minimum.x, x)
				minimum.y = mini(minimum.y, y)
				maximum.x = maxi(maximum.x, x)
				maximum.y = maxi(maximum.y, y)
	if maximum.x < minimum.x or maximum.y < minimum.y:
		return Rect2i()
	return Rect2i(minimum, maximum - minimum + Vector2i.ONE)

func pack_panels() -> void:
	var source_path := SOURCE_DIRECTORY.path_join("ivory-original.png")
	var source := load_source(source_path, Vector2i(1254, 1254))
	if source == null:
		return
	if source.get_used_rect() != PANEL_CROP:
		fail("ivory artwork used rect changed; review its crop before packing")
		return
	for definition in [{"name": "panel", "size": 256, "slice": 32}, {"name": "surface", "size": 128, "slice": 16}, {"name": "track", "size": 24, "slice": 4}]:
		var image := source.get_region(PANEL_CROP)
		image.resize(definition.size, definition.size, Image.INTERPOLATE_LANCZOS)
		save_component(image, definition.name, source_path, source.get_size(), PANEL_CROP, {
			"processing": "crop_and_resize",
			"recommended_texture_margins": [definition.slice, definition.slice, definition.slice, definition.slice],
			"center_alpha": image.get_pixel(definition.size / 2, definition.size / 2).a,
		})

func pack_icons() -> void:
	var source_path := SOURCE_DIRECTORY.path_join("icons-original.png")
	var source := load_source(source_path, Vector2i(1448, 1086))
	if source == null:
		return
	for index in ICON_NAMES.size():
		var cell := Rect2i((index % 4) * ICON_CELL, (index / 4) * ICON_CELL, ICON_CELL, ICON_CELL)
		var crop := alpha_bounds(source, cell)
		if not crop.has_area():
			fail("no opaque icon pixels in cell " + str(index))
			continue
		var glyph := source.get_region(crop)
		var scale_value := float(ICON_GLYPH) / float(maxi(crop.size.x, crop.size.y))
		var glyph_size := Vector2i(maxi(1, roundi(crop.size.x * scale_value)), maxi(1, roundi(crop.size.y * scale_value)))
		glyph.resize(glyph_size.x, glyph_size.y, Image.INTERPOLATE_LANCZOS)
		var canvas := Image.create(ICON_CANVAS, ICON_CANVAS, false, Image.FORMAT_RGBA8)
		canvas.fill(Color.TRANSPARENT)
		var offset := Vector2i((ICON_CANVAS - glyph_size.x) / 2, (ICON_CANVAS - glyph_size.y) / 2)
		canvas.blit_rect(glyph, Rect2i(Vector2i.ZERO, glyph_size), offset)
		save_component(canvas, "icon-" + ICON_NAMES[index], source_path, source.get_size(), crop, {
			"processing": "alpha_bound_crop_resize_center_on_transparent_canvas",
			"cell_index": index,
			"cell_rect": rect_values(cell),
			"bound_alpha_threshold": ICON_ALPHA_THRESHOLD,
			"threshold_affects_bounds_only": true,
			"glyph_size": [glyph_size.x, glyph_size.y],
			"glyph_offset": [offset.x, offset.y],
			"scale": scale_value,
		})

func draft_record(filename: String, generation_source := "") -> Dictionary:
	var relative_path := SOURCE_DIRECTORY.path_join(filename)
	var image := load_source(relative_path)
	if image == null:
		return {}
	var result := {
		"source": relative_path,
		"source_sha256": FileAccess.get_sha256(repository.path_join(relative_path)),
		"source_size": [image.get_width(), image.get_height()],
		"status": "rejected",
		"used_at_runtime": false,
		"reason": "alpha中心不透明度错误；只保留生成草稿，不用于运行。",
		"center_alpha": image.get_pixel(image.get_width() / 2, image.get_height() / 2).a,
	}
	if not generation_source.is_empty():
		result["generation_source"] = generation_source
	return result

func build() -> void:
	var script_path: String = ProjectSettings.globalize_path(get_script().resource_path).simplify_path()
	repository = script_path.get_base_dir().get_base_dir().get_base_dir()
	var error := DirAccess.make_dir_recursive_absolute(repository.path_join(OUTPUT_DIRECTORY))
	if error != OK:
		fail("cannot create output directory: " + error_string(error))
		quit(1)
		return
	pack_panels()
	pack_icons()
	var rejected := [
		draft_record("sage-draft.png"),
		draft_record("sage-draft-v2.png", "/Users/jitian/.codex/generated_images/01a16983-ad12-77d1-abab-b8a1d42cb860/exec-28dea33f-7883-4772-bb54-6cbd34c72266.png"),
	]
	if not errors.is_empty():
		quit(1)
		return
	var manifest_path := repository.path_join(SOURCE_DIRECTORY.path_join("components.json"))
	var manifest := FileAccess.open(manifest_path, FileAccess.WRITE)
	if manifest == null:
		fail("cannot write packaging manifest")
		quit(1)
		return
	manifest.store_string(JSON.stringify({
		"schema": 1,
		"type": "derived_catalogue_components",
		"generator": "scripts/godot_tools/build_catalogue_components.gd",
		"generator_sha256": FileAccess.get_sha256(script_path),
		"source_art": "GPT-generated empty ivory panel and 4 by 3 icon atlas, accepted for catalogue components.",
		"processing": "Only crop, Lanczos resize, and transparent icon canvas placement; no painting, masking, color replacement, or runtime source dependencies.",
		"resampling": "Image.INTERPOLATE_LANCZOS",
		"pixel_format": "RGBA8",
		"runtime_directory": OUTPUT_DIRECTORY,
		"entries": entries,
		"rejected_drafts": rejected,
	}, "  ") + "\n")
	manifest.close()
	print("CATALOGUE COMPONENTS: ", entries.size(), " PNGs; manifest ", SOURCE_DIRECTORY.path_join("components.json"))
	quit(0)
