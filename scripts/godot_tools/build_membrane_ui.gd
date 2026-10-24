extends SceneTree
## Offline packing of GPT originals: crop and Lanczos resize only, no painting.
const SOURCE := "assets/image/global-ui-20261024/"
const RUNTIME := "godot/assets/ui/membrane/"
const DEFINITIONS := [
	["panel","square-original.png",Vector2i(256,256),38],
	["surface","square-original.png",Vector2i(128,128),18],
	["badge","square-original.png",Vector2i(128,128),20],
	["compact","square-original.png",Vector2i(64,64),10],
	["micro","square-original.png",Vector2i(32,32),5],
	["button","button-original.png",Vector2i(256,72),24],
	["track","button-original.png",Vector2i(32,12),4],
	["knob","knob-original.png",Vector2i(24,24),0],
]

func _initialize() -> void:
	call_deferred("build")

func build() -> void:
	var repo: String = get_script().resource_path.get_base_dir().get_base_dir().get_base_dir()
	if repo.begins_with("res://"): repo = ProjectSettings.globalize_path(repo)
	DirAccess.make_dir_recursive_absolute(repo.path_join(RUNTIME))
	DirAccess.make_dir_recursive_absolute(repo.path_join(SOURCE+"runtime"))
	var generation: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(repo.path_join(SOURCE+"generation.json")))
	var rows: Array[Dictionary] = []
	for spec in DEFINITIONS:
		var input: String = repo.path_join(SOURCE+spec[1])
		var original := Image.load_from_file(input)
		assert(original != null and not original.is_empty(),"Missing GPT original")
		var b: Array = generation.accepted[spec[1]].alphaAbove8Bounds
		var crop := Rect2i(b[0],b[1],b[2]-b[0],b[3]-b[1])
		var image := original.get_region(crop)
		image.resize(spec[2].x,spec[2].y,Image.INTERPOLATE_LANCZOS)
		assert(image.get_pixel(image.get_width()/2,image.get_height()/2).a >= .95,"Opaque writing area required")
		var filename: String = spec[0]+".png"
		var source := SOURCE+"runtime/"+filename
		assert(image.save_png(repo.path_join(source)) == OK)
		assert(image.save_png(repo.path_join(RUNTIME+filename)) == OK)
		rows.append({"id":spec[0],"original":SOURCE+spec[1],"originalSha256":FileAccess.get_sha256(input),
			"crop":[crop.position.x,crop.position.y,crop.size.x,crop.size.y],"size":[spec[2].x,spec[2].y],
			"slice":spec[3],"source":source,"path":"assets/ui/membrane/"+filename,
			"bytes":FileAccess.get_file_as_bytes(repo.path_join(source)).size(),"sha256":FileAccess.get_sha256(repo.path_join(source))})
	var file := FileAccess.open(repo.path_join(SOURCE+"components.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"generator":"scripts/godot_tools/build_membrane_ui.gd","processing":"crop and Lanczos resize only; alpha preserved","entries":rows},"  ")+"\n")
	print("MEMBRANE_COMPONENTS ",rows.size())
	quit()
