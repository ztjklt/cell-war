class_name WarCataloguePlayer
extends Control
## Gallery-only playback. Source timing and rectangles are frozen in the catalogue.
signal playback_changed
var textures := WarTextures.new()
var entry: Dictionary = {}
var mode := 0 # 0: complete action cycle, 1: portrait, 2+: individual action
var action_index := 0
var frame_index := 0
var elapsed := 0.0
var playing := true
var cycles := 0
var loaded := false
var portrait_regions: Dictionary = {}
const END_HOLD := .35

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	textures.budget = 56*1024*1024
	resized.connect(queue_redraw)
	visibility_changed.connect(_visibility)
	_visibility()

func _visibility() -> void:
	set_process(is_visible_in_tree())
	if not is_visible_in_tree():
		textures.close()
		loaded = false

func select(value: Dictionary) -> void:
	entry = value
	mode = 0 if not entry.actions.is_empty() else 1
	playing = true
	cycles = 0
	restart()

func select_mode(value: int) -> void:
	mode = value
	playing = true
	restart()

func restart() -> void:
	action_index = maxi(0,mode-2)
	elapsed = 0
	frame_index = 0
	loaded = false
	playback_changed.emit()
	queue_redraw()

func toggle_playing() -> void:
	playing = not playing
	playback_changed.emit()

func current_action() -> Dictionary:
	if entry.is_empty() or mode == 1 or entry.actions.is_empty(): return {}
	return entry.actions[action_index]

func current_path() -> String:
	if entry.is_empty(): return ""
	var action := current_action()
	return str(entry.portrait if action.is_empty() else action.path).trim_prefix("res://assets/")

func cycle_duration() -> float:
	var action := current_action()
	if action.is_empty(): return 0
	return float(action.duration)+(0.0 if action.get("sourceLoop",false) else END_HOLD)

func _process(delta: float) -> void:
	var path := current_path()
	if path.is_empty(): return
	textures.request(path)
	textures.update()
	loaded = textures.get_texture(path) != null
	if loaded and playing: advance(delta)
	queue_redraw()

func advance(delta: float) -> void:
	var action := current_action()
	if action.is_empty(): return
	elapsed += delta
	# Hold the final pose briefly, then restart or proceed to the next action.
	# Advance at most one action per rendered frame so every action can load.
	if elapsed >= cycle_duration():
		var remainder := fmod(elapsed,cycle_duration())
		elapsed = 0 if mode == 0 else remainder
		if mode == 0:
			action_index = (action_index+1)%entry.actions.size()
			if action_index == 0: cycles += 1
		else: cycles += 1
		action = current_action()
		loaded = false
		playback_changed.emit()
	var time := 0.0
	frame_index = action.frames.size()-1
	for i in action.frames.size():
		time += float(action.frames[i].duration)
		if elapsed < time:
			frame_index = i
			break

func _draw() -> void:
	var path := current_path()
	var texture := textures.get_texture(path)
	if texture == null:
		draw_string(WarUISkin.BODY,Vector2(20,size.y*.5),"正在加载角色…",HORIZONTAL_ALIGNMENT_LEFT,-1,15,WarUISkin.MUTED)
		return
	var source := Rect2(Vector2.ZERO,texture.get_size())
	var action := current_action()
	if action.is_empty():
		if not portrait_regions.has(path): portrait_regions[path] = texture.get_image().get_used_rect()
		source = portrait_regions[path]
	else:
		var rect: Array = action.frames[frame_index].rect
		source = Rect2(rect[0],rect[1],rect[2],rect[3])
	var fit := minf((size.x-24)/maxf(source.size.x,1),(size.y-16)/maxf(source.size.y,1))
	var extent := source.size*fit
	draw_texture_rect_region(texture,Rect2((size-extent)*.5,extent),source)

func _exit_tree() -> void:
	textures.close()
