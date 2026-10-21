class_name WarPneumococcusAnimation
extends RefCounted
## Six approved painted clips. No gameplay events are emitted by this sampler.

static func data() -> Dictionary:
	return WarData.read("pneumococcus")

static func frame_at(clip: Dictionary,elapsed: float,loop: bool) -> int:
	var t := maxf(0,elapsed)
	if loop: t = fmod(t,float(clip.duration))
	var end := 0.0
	for i in clip.durations.size():
		end += float(clip.durations[i])
		if t < end-.0000001: return i
	return clip.durations.size()-1

static func sample(e: Dictionary,time: float,moving: float,dead: bool) -> Dictionary:
	var clips: Dictionary = data().clips
	var key := "pnMove"
	var elapsed := time+int(e.get("id",0))*.071 if moving > .02 else 0.0
	var loop := true
	if dead or e.has("deathTime") or e.has("pneumoDeathAt"):
		key = "pnDeath"; loop = false
		elapsed = maxf(0,time-float(e.get("pneumoDeathAt",e.get("deathTime",e.get("died",time)))))
		if elapsed >= float(clips.pnDeath.duration): return {"hidden":true,"key":key,"frame":15,"family":"pneumococcus"}
	else:
		var hit := float(e.get("pneumoHitAt",-100))
		var shot := float(e.get("pneumoShotAt",-100))
		var rate := maxf(.01,float(e.get("pneumoShotSpeed",1)))
		if time >= hit and time-hit < float(clips.pnHitRight.duration):
			key = "pnHitLeft" if e.get("pneumoHitSide","right") == "left" else "pnHitRight"
			elapsed = time-hit; loop = false
		elif not e.get("pneumoShotCancelled",false) and time >= shot and (time-shot)*rate < float(clips.pnShoot.duration):
			key = "pnShoot"; elapsed = (time-shot)*rate; loop = false
	var clip: Dictionary = clips[key]
	return {"key":key,"clip":clip,"frame":frame_at(clip,elapsed,loop),"family":"pneumococcus",
		"mirror":bool(e.get("pneumoFacingLeft",false)),"angle":0.0}

static func projectile_sample(projectile: Dictionary,time: float) -> Dictionary:
	var clip: Dictionary = data().clips.pnProjectile
	return {"key":"pnProjectile","clip":clip,"frame":frame_at(clip,time-float(projectile.get("born",time)),true),
		"family":"pneumococcus","worldCanvasSize":float(data().projectile.worldCanvasSize)}

static func corpse_duration(step := .1) -> float:
	return float(data().clips.pnDeath.duration)+step

static func standing_hull(e: Dictionary,position: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	var radius: float = data().body.radius
	for xy in data().body.hull:
		var p := Vector2(xy[0],xy[1])
		if e.get("pneumoFacingLeft",false): p.x = -p.x
		points.append(position+p*radius)
	return points
