class_name WarAdenovirusAnimation
extends RefCounted
## Pure presentation sampler. No actor mutation or attack/event dispatch.
var _clips: Dictionary = {}

func _init() -> void:
	var definition: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/adenovirus.json"))
	_clips = definition.clips

func sample(view: Dictionary, moving := false) -> Dictionary:
	var name := str(view.get("pose","idle"))
	var elapsed := maxf(0.0,float(view.get("elapsed",0.0)))
	if name == "idle":
		name = "move"; elapsed = float(view.get("clock",0.0)) if moving else 0.0
	if not _clips.has(name): name = "move"; elapsed = 0.0
	var clip: Dictionary = _clips[name]
	var hidden := name == "death" and elapsed >= float(clip.duration)-0.000000001
	var time := fposmod(elapsed,float(clip.duration)) if clip.loop else minf(elapsed,float(clip.duration))
	var frame: int = clip.durations.size()-1
	var boundary := 0.0
	for i in clip.durations.size():
		boundary += float(clip.durations[i])
		if time < boundary-0.000000001: frame = i; break
	return {"clip":name, "frame":frame, "path":"res://assets/"+str(clip.path),
		"rect":Rect2((frame % int(clip.columns))*int(clip.frameSize),int(frame/int(clip.columns))*int(clip.frameSize),int(clip.frameSize),int(clip.frameSize)),
		"anchor":Vector2(float(clip.anchorX),float(clip.anchorY)), "rotation":0.0,
		"mirror":false, "scale":Vector2.ONE, "hidden":hidden}
