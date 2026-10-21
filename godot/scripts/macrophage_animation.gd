class_name WarMacrophageAnimation
extends RefCounted
## Pure sampler of current original atlases. It never hides a target or deals damage.
var _clips: Dictionary = {}

func _init() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/macrophage.json"))
	_clips = data.clips

func sample(view: Dictionary, moving := false) -> Dictionary:
	var key := str(view.get("pose","idle"))
	var elapsed := maxf(0.0,float(view.get("elapsed",0.0)))
	if key == "idle": key = "move"; elapsed = float(view.get("clock",0)) if moving else 0.0
	if not _clips.has(key): key = "move"; elapsed = 0.0
	var clip: Dictionary = _clips[key]
	var time := fposmod(elapsed,float(clip.duration)) if clip.loop else minf(elapsed,float(clip.duration))
	var frame: int = clip.frames.size()-1
	var end := 0.0
	for i in clip.frames.size():
		end += float(clip.frames[i].duration)
		if time < end-0.000000001: frame = i; break
	# The original remnant is painted into the chew frames. Without a confirmed
	# kill, hold the original clean closure through that segment; never fake prey.
	if key == "swallow" and not view.get("swallowed",false) and clip.frames[frame].phase == "chew": frame = 12
	if key == "chew" and not view.get("swallowed",false): frame = 0
	var item: Dictionary = clip.frames[frame]
	var finished := not bool(clip.loop) and elapsed >= float(clip.duration)-0.000000001
	var hidden := not bool(item.visible) or (key == "death" and finished)
	return {"key":key,"frame":frame,"path":clip.path,"rect":Rect2(item.rect[0],item.rect[1],item.rect[2],item.rect[3]),
		"anchor":Vector2(item.anchor[0],item.anchor[1]),"hidden":hidden,"finished":finished,"rotation":0.0,"mirror":false,"scale":Vector2.ONE}
