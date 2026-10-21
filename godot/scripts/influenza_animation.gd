class_name WarInfluenzaAnimation
extends RefCounted
## Reviewed twenty-frame skin for the existing virus kind; combat rules stay unchanged.

static func data() -> Dictionary:
	return WarData.read("influenza")

static func hit_duration() -> float:
	return float(data().clips.fluHit.duration)

static func corpse_duration(e: Dictionary) -> float:
	return float(data().clips.fluDeath.duration)+WarSimulation.STEP if e.kind == "virus" else 1.92

static func sample(e: Dictionary,time: float,moving: float,dead: bool) -> Dictionary:
	var clips: Dictionary = data().clips
	var key := "fluMove"
	var elapsed := 0.0
	var loop := false
	if dead or e.has("deathTime"):
		key = "fluDeath"
		elapsed = maxf(0,time-float(e.get("deathTime",e.get("died",time))))
		if elapsed >= float(clips[key].duration): return {"hidden":true,"key":key,"frame":19}
	else:
		var hit := float(e.get("cellHitStarted",e.get("hitTime",-100)))
		var shot := float(e.get("shotTime",-100))
		var attack_window := minf(float(clips.fluAttack.duration),float(WarData.spec("virus").get("cool",1.2)))
		if time >= hit and time-hit < hit_duration():
			key = "fluHit"; elapsed = time-hit
		elif time >= shot and time-shot < attack_window:
			key = "fluAttack"
			# Fit the complete painted bite into the existing attack interval.
			elapsed = (time-shot)*float(clips.fluAttack.duration)/attack_window
		elif absf(time-float(e.get("cellWorkTime",-100))) <= WarSimulation.STEP+.05:
			key = "fluBuild"; elapsed = time; loop = true
		else:
			loop = true
			elapsed = time+int(e.id)*.071 if moving > .02 else 0.0
	var clip: Dictionary = clips[key]
	var t := maxf(0,elapsed)
	if loop: t = fmod(t,float(clip.duration))
	var frame := 19
	var end := 0.0
	for i in clip.durations.size():
		end += float(clip.durations[i])
		if t < end-.000001: frame = i; break
	return {"key":key,"clip":clip,"frame":frame,"family":"influenza"}
