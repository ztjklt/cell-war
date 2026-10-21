class_name WarInfectionPurification
extends RefCounted
## Minimum playable balance defaults, not user-approved final balance.
## Called only by the existing fixed-step colony service; no render-time timers.
const RED_REQUIRED := 1
const WHITE_REQUIRED := 1
const HOLD_SECONDS := 20.0
const FADE_SECONDS := 3.0
const WHITE_KINDS := ["spear","neutrophil"]
const STATUSES := ["waiting_red","waiting_white","contested","pending_births","fortified","purifying","purified"]
var _owner: WeakRef
var game: WarSimulation:
	get: return _owner.get_ref() as WarSimulation

func _init(owner: WarSimulation) -> void:
	_owner = weakref(owner)

static func patch(group: Dictionary) -> Dictionary:
	for zone in WarData.read("infection_zones").zones:
		if zone.organ != group.get("organ",""): continue
		for item in zone.placements:
			if item.id == group.get("id",""): return item
	return {}

static func footprint(group: Dictionary) -> Rect2:
	var region := patch(group)
	if region.is_empty(): return Rect2()
	var size := Vector2.ONE*float(region.side)
	return Rect2(WarData.point(region.center)-size*.5,size)

static func fresh_state(cleared := false) -> Dictionary:
	return {"version":1,"elapsed":HOLD_SECONDS if cleared else 0.0,
		"fadeElapsed":FADE_SECONDS if cleared else 0.0,
		"status":"purified" if cleared else "waiting_red","red":0,"white":0,"hostiles":0}

static func progress(group: Dictionary) -> float:
	return clampf(float(group.get("purification",{}).get("elapsed",0))/HOLD_SECONDS,0,1)

static func ground_opacity(group: Dictionary) -> float:
	if not group.get("cleared",false): return 1.0
	# Legacy cleared saves lack a fade clock and remain cleared on load.
	return 1.0-clampf(float(group.get("purification",{}).get("fadeElapsed",FADE_SECONDS))/FADE_SECONDS,0,1)

func reset(group: Dictionary) -> void:
	group.purification = fresh_state()
	group.cleared = false

func update(dt: float) -> void:
	if game.mode != "fullbody" or not game.is_fullbody(): return
	if not game.state.get("influenzaColonies") is Dictionary: return
	for group in game.state.influenzaColonies.groups.values():
		if not group.has("purification"):
			group.purification = fresh_state(bool(group.get("cleared",false)))
		var state: Dictionary = group.purification
		if group.get("cleared",false):
			state.fadeElapsed = minf(FADE_SECONDS,float(state.fadeElapsed)+maxf(0,dt))
			continue
		var rect := footprint(group)
		if rect.size.is_zero_approx(): continue
		state.red = 0; state.white = 0; state.hostiles = 0
		for e in game.entities():
			if e.hp <= 0 or int(e.get("vesselLane",0)) != 0 or not rect.has_point(WarData.point(e)): continue
			# A matching screen position on a different organ/vascular plane never counts.
			if game.navigation.organ_at(WarData.point(e),e.kind) != group.organ: continue
			if int(e.faction) > 1:
				state.hostiles += 1
			elif int(e.faction) == 1 and e.category == "unit":
				if e.kind == "worker": state.red += 1
				elif e.kind in WHITE_KINDS: state.white += 1
		var status := "purifying"
		if int(state.hostiles) > 0: status = "contested"
		elif not game.influenza.forts(group).is_empty(): status = "fortified"
		elif int(group.pending) > 0: status = "pending_births"
		elif int(state.red) < RED_REQUIRED: status = "waiting_red"
		elif int(state.white) < WHITE_REQUIRED: status = "waiting_white"
		if state.status == "purifying" and status != "purifying":
			game.event("infection_purification_interrupted",{"colony":group.id,"reason":status})
		state.status = status
		if status != "purifying":
			state.elapsed = 0.0
			continue
		state.elapsed = minf(HOLD_SECONDS,float(state.elapsed)+maxf(0,dt))
		if float(state.elapsed)+.000001 < HOLD_SECONDS: continue
		state.elapsed = HOLD_SECONDS; state.status = "purified"; state.fadeElapsed = 0.0
		group.cleared = true; group.pending = 0
		game.event("infection_purified",{"colony":group.id,"organ":group.organ})
		game.notify("感染区域已净化 · 已停止增殖")

static func validate(group: Dictionary) -> String:
	if not group.get("cleared") is bool: return "感染清除状态无效"
	if not group.has("purification"): return "" # Existing v1 colonies load without migration loss.
	var state: Variant = group.purification
	if not state is Dictionary or state.get("version") != 1 or not state.get("status") in STATUSES: return "感染净化记录无效"
	for field in ["elapsed","fadeElapsed","red","white","hostiles"]:
		if not WarSave._number(state.get(field)) or float(state[field]) < 0: return "感染净化数值无效"
	for field in ["red","white","hostiles"]:
		if float(state[field]) != int(state[field]) or state[field] > 4096: return "感染驻守人数无效"
	if state.elapsed > HOLD_SECONDS or state.fadeElapsed > FADE_SECONDS: return "感染净化进度无效"
	if bool(group.cleared) != (state.status == "purified"): return "感染净化状态不一致"
	if group.cleared and (not is_equal_approx(float(state.elapsed),HOLD_SECONDS) or int(group.pending) != 0): return "感染净化完成记录无效"
	if not group.cleared and (state.fadeElapsed > 0 or state.elapsed >= HOLD_SECONDS): return "感染净化阶段无效"
	if state.status not in ["purifying","purified"] and state.elapsed > 0: return "感染净化中断记录无效"
	var region := patch(group)
	if region.is_empty() or WarData.point(group.center).distance_to(WarData.point(region.center)) > .001 or group.get("targetGate","") != region.targetGate: return "感染净化位置无效"
	return ""
