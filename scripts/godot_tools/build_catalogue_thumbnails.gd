extends SceneTree
## Offline derivation of catalogue thumbnails; never used by the running game.
## Run from the repository root:
## ./godot/run.sh --headless --script ../scripts/godot_tools/build_catalogue_thumbnails.gd

const CATALOGUE := "res://data/character_catalogue.json"
const OUTPUT_DIRECTORY := "res://assets/ui/catalogue/thumbnails"
const MANIFEST := "assets/image/catalogue-stage-20261024/thumbnails.json"
const MAX_EDGE := 192

func _initialize() -> void:
	call_deferred("build")

func fail(message: String) -> void:
	printerr("CATALOGUE THUMBNAILS: "+message)
	quit(1)

func build() -> void:
	var catalogue_file := FileAccess.open(CATALOGUE,FileAccess.READ)
	if catalogue_file == null:
		fail("cannot open "+CATALOGUE); return
	var catalogue = JSON.parse_string(catalogue_file.get_as_text())
	if not catalogue is Dictionary or not catalogue.get("entries") is Array:
		fail("catalogue must contain an entries array"); return
	var rows: Array[Dictionary] = []
	var thumbnails: Array[Image] = []
	var seen: Dictionary = {}
	var unique_sources: Dictionary = {}
	var source_bytes := 0
	var thumbnail_bytes := 0
	for entry in catalogue.entries:
		var id := str(entry.get("id",""))
		var source_path := str(entry.get("portrait",""))
		if id.is_empty() or id.validate_filename() != id or seen.has(id):
			fail("invalid or duplicate entry id: "+id); return
		seen[id] = true
		if not source_path.begins_with("res://assets/") or not FileAccess.file_exists(source_path):
			fail("missing local portrait for "+id); return
		var source := Image.load_from_file(ProjectSettings.globalize_path(source_path))
		if source == null or source.is_empty():
			fail("cannot decode portrait for "+id); return
		var used := source.get_used_rect()
		if used.size.x <= 0 or used.size.y <= 0:
			fail("portrait is fully transparent for "+id); return
		var thumbnail := source.get_region(used)
		thumbnail.convert(Image.FORMAT_RGBA8)
		var scale := minf(1.0,float(MAX_EDGE)/float(maxi(used.size.x,used.size.y)))
		var output_size := Vector2i(maxi(1,roundi(used.size.x*scale)),maxi(1,roundi(used.size.y*scale)))
		if output_size != used.size:
			thumbnail.resize(output_size.x,output_size.y,Image.INTERPOLATE_LANCZOS)
		var output_path := OUTPUT_DIRECTORY.path_join(id+".png")
		if not unique_sources.has(source_path):
			unique_sources[source_path] = true
			source_bytes += source.get_width()*source.get_height()*4
		thumbnail_bytes += output_size.x*output_size.y*4
		rows.append({
			"id":id,
			"name":str(entry.get("name",id)),
			"source":"godot/"+source_path.trim_prefix("res://"),
			"source_resource":source_path,
			"source_sha256":FileAccess.get_sha256(source_path),
			"source_size":[source.get_width(),source.get_height()],
			"crop_rect":[used.position.x,used.position.y,used.size.x,used.size.y],
			"output":"godot/"+output_path.trim_prefix("res://"),
			"output_resource":output_path,
			"output_size":[output_size.x,output_size.y],
			"scale":scale,
		})
		thumbnails.append(thumbnail)
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIRECTORY))
	if error != OK:
		fail("cannot create thumbnail directory: "+error_string(error)); return
	for index in rows.size():
		var output_path: String = rows[index].output_resource
		error = thumbnails[index].save_png(output_path)
		if error != OK:
			fail("cannot save "+output_path+": "+error_string(error)); return
		rows[index]["output_sha256"] = FileAccess.get_sha256(output_path)
	var repository := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir()
	var manifest_path := repository.path_join(MANIFEST)
	error = DirAccess.make_dir_recursive_absolute(manifest_path.get_base_dir())
	if error != OK:
		fail("cannot create manifest directory: "+error_string(error)); return
	var manifest_file := FileAccess.open(manifest_path,FileAccess.WRITE)
	if manifest_file == null:
		fail("cannot write thumbnail manifest"); return
	manifest_file.store_string(JSON.stringify({
		"schema":1,
		"type":"derived_catalogue_thumbnails",
		"generator":"scripts/godot_tools/build_catalogue_thumbnails.gd",
		"catalogue":"godot/data/character_catalogue.json",
		"catalogue_sha256":FileAccess.get_sha256(CATALOGUE),
		"artwork_note":"派生缩略图，不是新美术；原立绘保持不变。仅用于角色目录卡片，详情继续使用原立绘与原动作。",
		"processing":"Godot Image 读取原 PNG，用 get_used_rect() 裁剪非透明有效区域；等比缩小到最长边 192 像素，不放大；Lanczos 重采样，输出 RGBA8 PNG。",
		"max_edge":MAX_EDGE,
		"upscaling":false,
		"resampling":"Image.INTERPOLATE_LANCZOS",
		"memory_estimate_note":"尺寸 × 4 字节的 RGBA8 基础层估算；原图按来源路径去重，缩略图按 24 个输出统计。不含导入压缩、mipmap、缓存或驱动开销，不是实测显存。",
		"unique_source_images":unique_sources.size(),
		"source_rgba8_bytes":source_bytes,
		"thumbnail_rgba8_bytes":thumbnail_bytes,
		"entries":rows,
	},"  ")+"\n")
	manifest_file.close()
	print("CATALOGUE THUMBNAILS: ",rows.size()," derived PNGs; RGBA8 estimate ",source_bytes," -> ",thumbnail_bytes," bytes")
	quit(0)
