class_name WarTextures
extends RefCounted
## Bound decoded texture memory. IO is scheduled by update, never by _draw.
var cache: Dictionary = {}
var pending: Dictionary = {}
var wanted: Dictionary = {}
var pinned: Dictionary = {}
var bytes := 0
var budget := 160*1024*1024
var tick := 0

func request(path: String,keep := false) -> void:
	if path.is_empty(): return
	wanted[path] = true
	if keep: pinned[path] = true
	if cache.has(path):
		cache[path].used = tick
		return
	if pending.has(path) or pending.size() >= 4: return
	var full := "res://assets/"+path
	if ResourceLoader.exists(full):
		var error := ResourceLoader.load_threaded_request(full,"Texture2D")
		if error == OK: pending[path] = true

func get_texture(path: String) -> Texture2D:
	return cache[path].texture if cache.has(path) else null

func update() -> void:
	tick += 1
	for path in pending.keys():
		var status := ResourceLoader.load_threaded_get_status("res://assets/"+path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var texture := ResourceLoader.load_threaded_get("res://assets/"+path) as Texture2D
			if texture:
				var size := texture.get_width()*texture.get_height()*4
				cache[path] = {"texture":texture,"bytes":size,"used":tick}
				bytes += size
			pending.erase(path)
		elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			pending.erase(path)
	var candidates := cache.keys()
	candidates.sort_custom(func(a,b): return cache[a].used < cache[b].used)
	for path in candidates:
		if bytes <= budget: break
		if pinned.has(path) or wanted.has(path): continue
		bytes -= int(cache[path].bytes)
		cache.erase(path)
	wanted.clear()

func close() -> void:
	for path in pending:
		var status := ResourceLoader.load_threaded_get_status("res://assets/"+path)
		if status in [ResourceLoader.THREAD_LOAD_IN_PROGRESS,ResourceLoader.THREAD_LOAD_LOADED]:
			ResourceLoader.load_threaded_get("res://assets/"+path)
	pending.clear()
	cache.clear()
	wanted.clear()
	pinned.clear()
	bytes = 0
