class_name WarSaveSession
extends RefCounted
## A selected run owns its own atomic file. Legacy slots are imported, never replaced.
const INTERVAL := 15.0
var active_path := ""
var title := ""
var created_at := ""
var view: Dictionary = {}
var since_save := 0.0
var last_saved := ""

func create(game: WarSimulation,name := "",camera_view := {}) -> Error:
	var old := [active_path,title,created_at,view.duplicate(true),last_saved]
	created_at = Time.get_datetime_string_from_system()
	title = name.strip_edges().left(60)
	if title.is_empty(): title = "左肺防线 · "+created_at.replace("T"," ")
	active_path = WarSave.directory+"/runs/"+str(Time.get_unix_time_from_system()).replace(".","-")+"-"+str(Time.get_ticks_usec())+".json"
	view = camera_view.duplicate(true)
	var result := save(game)
	if result != OK:
		active_path = old[0]; title = old[1]; created_at = old[2]; view = old[3]; last_saved = old[4]
	return result

func save(game: WarSimulation,camera_view := {}) -> Error:
	if active_path.is_empty(): return OK
	if not camera_view.is_empty(): view = camera_view.duplicate(true)
	var result := WarSave._write_to(game,active_path,{"profile":{"title":title,"createdAt":created_at},
		"view":view,"session":{"speed":game.speed,"selected":game.selected,"groups":game.groups}})
	since_save = 0.0
	if result == OK: last_saved = Time.get_datetime_string_from_system()
	else: game.notify("进度保存失败："+error_string(result)+"；请保留当前游戏并重试")
	return result

func resume(game: WarSimulation,source: String) -> Error:
	var data := document(source)
	if data.get("schema","") != WarSave.SCHEMA or not data.get("mode","fullbody") in WarSave.MODES or not data.get("snapshot") is Dictionary: return ERR_FILE_CORRUPT
	var error := WarSave.validate(data.snapshot)
	if not error.is_empty(): game.notify("存档未载入："+error); return ERR_FILE_CORRUPT
	# Prepare and, for legacy files, persist the imported run before touching the
	# live world. Failed imports must not clear selection, groups or UI state.
	var candidate := WarSimulation.new()
	candidate.mode = data.get("mode","fullbody")
	candidate.restore(data.snapshot)
	var profile: Dictionary = data.get("profile",{}) if data.get("profile") is Dictionary else {}
	var saved_session: Dictionary = data.get("session",{}) if data.get("session") is Dictionary else {}
	candidate.speed = clampf(float(saved_session.speed),1.0,4.0) if WarSave._number(saved_session.get("speed")) else 1.0
	for id in WarData.array(saved_session.get("selected",[])):
		if (id is float or id is int) and not candidate.entity(int(id)).is_empty(): candidate.selected.append(int(id))
	var groups := WarData.array(saved_session.get("groups",[]))
	for i in mini(groups.size(),candidate.groups.size()):
		candidate.groups[i] = WarData.array(groups[i]).filter(func(id): return (id is float or id is int) and not candidate.entity(int(id)).is_empty()).map(func(id): return int(id))
	var saved_view: Dictionary = data.get("view",{}).duplicate(true) if data.get("view") is Dictionary else {}
	var result := OK
	if source.get_base_dir() == WarSave.directory+"/runs":
		active_path = source
		title = str(profile.get("title","未命名存档"))
		created_at = str(profile.get("createdAt",data.get("savedAt","")))
		last_saved = str(data.get("savedAt",""))
		view = saved_view
	else:
		result = create(candidate,"旧存档 · "+str(data.get("savedAt","")),saved_view)
	if result == OK:
		game.mode = candidate.mode; game.restore(candidate.snapshot())
		game.speed = candidate.speed
		game.selected.assign(candidate.selected); game.groups = candidate.groups.duplicate(true)
		since_save = 0.0
	candidate.dispose()
	return result

static func document(source: String) -> Dictionary:
	var file := FileAccess.open(source,FileAccess.READ)
	if file == null or file.get_length() > WarSave.MAX_BYTES: return {}
	var parsed := JSON.new()
	if parsed.parse(file.get_as_text()) != OK or not parsed.data is Dictionary: return {}
	return parsed.data

static func records() -> Array[Dictionary]:
	var paths: Array[String] = []
	var runs := DirAccess.open(WarSave.directory+"/runs")
	if runs != null:
		for file in runs.get_files():
			if file.ends_with(".json"): paths.append(WarSave.directory+"/runs/"+file)
	for i in 4:
		if FileAccess.file_exists(WarSave.path(i)): paths.append(WarSave.path(i))
	if FileAccess.file_exists(WarSave.life_auto_path()): paths.append(WarSave.life_auto_path())
	var result: Array[Dictionary] = []
	for source in paths:
		var data := document(source)
		var snapshot: Dictionary = data.get("snapshot",{}) if data.get("snapshot") is Dictionary else {}
		var profile: Dictionary = data.get("profile",{}) if data.get("profile") is Dictionary else {}
		var valid: bool = data.get("schema","") == WarSave.SCHEMA and data.get("mode","fullbody") in WarSave.MODES and not snapshot.is_empty() and WarSave.validate(snapshot).is_empty()
		var name := str(profile.get("title","旧版生活自动档" if source == WarSave.life_auto_path() else "旧版槽位 "+source.get_file().get_basename().trim_prefix("slot_")))
		result.append({"path":source,"title":name if valid else "无法读取 · "+source.get_file(),"valid":valid,
			"savedAt":str(data.get("savedAt","")),"time":float(snapshot.get("time",0)) if valid else 0.0})
	result.sort_custom(func(a,b): return a.savedAt > b.savedAt if a.savedAt != b.savedAt else a.path > b.path)
	return result
