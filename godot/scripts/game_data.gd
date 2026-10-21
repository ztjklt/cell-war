class_name WarData
extends RefCounted

static var _cache: Dictionary = {}

static func read(path: String) -> Variant:
	if not _cache.has(path):
		var file := FileAccess.open("res://data/" + path + ".json", FileAccess.READ)
		if file == null:
			push_error("Missing game data: " + path)
			return {}
		var parser := JSON.new()
		if parser.parse(file.get_as_text()) != OK:
			push_error("Invalid game data: " + path)
			return {}
		_cache[path] = parser.data
	return _cache[path]

static func config() -> Dictionary:
	return read("config")

static func spec(kind: String) -> Dictionary:
	var data: Dictionary = config().Data
	return data.units.get(kind, data.buildings.get(kind, {}))

static func radius(kind: String) -> float:
	return float(config().Data.cellRadii.get(kind, 19.0 / 32.0))

static func is_pathogen(kind: String) -> bool:
	# Preserve the five migrated identities. New combat identities explicitly
	# opt in when registered; a catalogue illustration alone grants no passage.
	if kind in ["virus","wolf","shadow","herpes","helicobacter"]: return true
	return bool(config().Data.units.get(kind,{}).get("pathogen",false))

static func pathogen_family(kind: String) -> String:
	# Stable migrated identities; future species opt in through registered data.
	if kind in ["virus","herpes"]: return "virus"
	if kind in ["wolf","helicobacter"]: return "bacterium"
	if not is_pathogen(kind): return ""
	var family := str(config().Data.units.get(kind,{}).get("pathogenFamily",""))
	return family if family in ["virus","bacterium"] else ""

static func is_virus(kind: String) -> bool:
	return pathogen_family(kind) == "virus"

static func is_bacterium(kind: String) -> bool:
	return pathogen_family(kind) == "bacterium"

static func point(data: Variant) -> Vector2:
	if data is Vector2:
		return data
	if data is Array and data.size() >= 2:
		return Vector2(float(data[0]), float(data[1]))
	if data is Dictionary:
		return Vector2(float(data.get("x", 0)), float(data.get("y", 0)))
	return Vector2.ZERO

static func source_to_world(data: Variant) -> Vector2:
	return point(data) * 2.0 + Vector2(0, 512)

static func world_to_source(p: Vector2) -> Vector2:
	return (p - Vector2(0, 512)) * 0.5

static func values(data: Variant) -> Array:
	return data.values() if data is Dictionary else data

static func array(data: Variant) -> Array:
	return data if data is Array else []
