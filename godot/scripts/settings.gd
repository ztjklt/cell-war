class_name WarSettings
extends RefCounted
## Small, local-only presentation preferences. Gameplay saves remain separate.
static var storage_path := "user://settings.json"
const DEFAULTS := {
	"version": 1,
	"volume": 40.0,
	"muted": false,
	"fullscreen": false,
	"vsync": true,
	"fps": 60,
	"showPaths": true,
}

var values: Dictionary = DEFAULTS.duplicate(true)

func load_from_disk() -> void:
	values = DEFAULTS.duplicate(true)
	var file := FileAccess.open(storage_path, FileAccess.READ)
	if file == null:
		return
	var parsed := JSON.new()
	if parsed.parse(file.get_as_text()) != OK or not parsed.data is Dictionary:
		return
	for key in DEFAULTS:
		if parsed.data.has(key):
			values[key] = parsed.data[key]
	_normalize()

func save_to_disk() -> void:
	_normalize()
	var file := FileAccess.open(storage_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(values, "", false, true))

func apply(window: Window) -> void:
	_normalize()
	AudioServer.set_bus_mute(0, muted())
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(.001, volume() / 100.0)))
	Engine.max_fps = fps()
	if DisplayServer.get_name() != "headless":
		window.mode = Window.MODE_FULLSCREEN if fullscreen() else Window.MODE_WINDOWED
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync() else DisplayServer.VSYNC_DISABLED)

func reset(window: Window) -> void:
	values = DEFAULTS.duplicate(true)
	save_to_disk()
	apply(window)

func volume() -> float:
	return clampf(float(values.get("volume", 40.0)), 0.0, 100.0)

func muted() -> bool:
	return bool(values.get("muted", false))

func fullscreen() -> bool:
	return bool(values.get("fullscreen", false))

func vsync() -> bool:
	return bool(values.get("vsync", true))

func fps() -> int:
	var target := int(values.get("fps", 60))
	return target if target in [30, 60, 120] else 60

func show_paths() -> bool:
	return bool(values.get("showPaths", true))

func set_volume(value: float) -> void:
	values.volume = clampf(value, 0.0, 100.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(.001, volume() / 100.0)))
	save_to_disk()

func set_muted(value: bool) -> void:
	values.muted = value
	AudioServer.set_bus_mute(0, value)
	save_to_disk()

func set_fullscreen(value: bool, window: Window) -> void:
	values.fullscreen = value
	if DisplayServer.get_name() != "headless":
		window.mode = Window.MODE_FULLSCREEN if value else Window.MODE_WINDOWED
	save_to_disk()

func set_vsync(value: bool) -> void:
	values.vsync = value
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if value else DisplayServer.VSYNC_DISABLED)
	save_to_disk()

func set_fps(value: int) -> void:
	values.fps = value if value in [30, 60, 120] else 60
	Engine.max_fps = fps()
	save_to_disk()

func set_show_paths(value: bool) -> void:
	values.showPaths = value
	save_to_disk()

func _normalize() -> void:
	values.version = 1
	values.volume = clampf(float(values.get("volume", 40.0)), 0.0, 100.0)
	values.muted = bool(values.get("muted", false))
	values.fullscreen = bool(values.get("fullscreen", false))
	values.vsync = bool(values.get("vsync", true))
	values.fps = fps()
	values.showPaths = bool(values.get("showPaths", true))
