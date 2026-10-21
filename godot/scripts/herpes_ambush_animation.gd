class_name WarHerpesAmbushAnimation
extends RefCounted
## Pure sampling; no sensing, damage, state transitions, or visibility overrides.
static func data() -> Dictionary: return WarData.read("herpes_ambush")

static func frame_at(clip: Dictionary,elapsed: float,loop: bool) -> int:
	var t := maxf(0,elapsed)
	if loop: t=fmod(t,float(clip.duration))
	var end := 0.0
	for i in clip.durations.size():
		end+=float(clip.durations[i])
		if t<end-.0000001: return i
	return clip.durations.size()-1

static func sample(actor: Dictionary,state: Dictionary,time: float,moving := 0.0) -> Dictionary:
	var phase: String=state.get("phase","active")
	var elapsed := float(state.get("progress",0))
	var interpolation := maxf(0,time-float(state.get("updatedAt",time)))
	if phase not in ["active","dormant","death"]:
		elapsed+=interpolation*(float(state.get("rate",1)) if phase=="burst" else 1.0)
	var key := "haMove"; var loop := false
	if float(actor.get("hp",1))<=0 or phase=="death":
		phase="death"; key="haDeath"
		elapsed=maxf(elapsed,time-float(actor.get("herpesDeathAt",state.get("deathAt",time))))
		if elapsed+0.000001>=float(data().clips.haDeath.duration): return {"hidden":true,"key":key,"frame":15,"family":"herpes_ambush"}
	elif phase=="dormant":
		return {"key":"haDormant","clip":data().dormant,"frame":0,"family":"herpes_ambush","angle":0.0,
			"mirror":bool(actor.get("herpesFacingLeft",false)),"concealed":true,"requiresVisibilityGate":true}
	elif phase=="burrowing": key="haBurrow"
	elif phase=="emerging": key="haEmerge"
	elif phase=="burst": key="haBurst"
	elif phase=="hit": key="haHit"
	else:
		elapsed=time+int(actor.get("id",0))*.071 if moving>.02 else 0.0; loop=moving>.02
	var clip: Dictionary=data().clips[key]
	return {"key":key,"clip":clip,"frame":frame_at(clip,elapsed,loop),"family":"herpes_ambush",
		"mirror":bool(actor.get("herpesFacingLeft",false)),"angle":0.0,"concealed":false}

static func standing_hull(actor: Dictionary,position: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	for xy in data().body.hull:
		var p := Vector2(xy[0],xy[1])
		if actor.get("herpesFacingLeft",false): p.x=-p.x
		result.append(position+p*float(data().radius))
	return result

static func corpse_duration(step := .1) -> float: return float(data().clips.haDeath.duration)+step
