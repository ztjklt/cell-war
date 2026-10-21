class_name WarOrganFunctions
extends RefCounted
## Organ service; the combat status loop owns its single per-unit recovery call.
## No world/entity scan: callers pass the unit already visited by their tick loop.
var game: WarSimulation
var _locations: Dictionary = {}
var location_queries := 0
const LOCATION_CACHE_LIMIT := 4096

func _init(owner: WarSimulation) -> void:
	game = owner

static func data() -> Dictionary:
	return WarData.read("organ_functions")

func enabled() -> bool:
	return game != null and not game.state.is_empty() and not game.navigation.ground_mode and game.mode != "sandbox" and not game.is_campaign()

func state() -> Dictionary:
	if not game.state.has("organFunctions"):
		var factions: Array = []
		for i in 3: factions.append({"glycogen":0.0,"waste":0.0,"cooldowns":{},"commandUntil":0.0,"pancreasUntil":0.0})
		game.state.organFunctions = {"schema":1,"factions":factions}
	return game.state.organFunctions

func faction_state(faction: int) -> Dictionary:
	return state().factions[faction-1] if faction >= 1 and faction <= 3 else {}

func reset_cache() -> void:
	_locations.clear()
	location_queries = 0

func dispose() -> void:
	reset_cache()
	game = null

func organ(e: Dictionary) -> String:
	if not enabled() or e.is_empty() or float(e.get("hp",0)) <= 0 or int(e.get("vesselLane",0)) != 0: return ""
	var signature := [e.get("kind","worker"),float(e.get("x",0)),float(e.get("y",0))]
	var key := str(int(e.get("id",-1)))
	if _locations.has(key) and _locations[key].signature == signature: return _locations[key].organ
	location_queries += 1
	var found := game.navigation.organ_at(WarData.point(e),str(e.get("kind","worker")))
	if _locations.size() >= LOCATION_CACHE_LIMIT: _locations.clear()
	_locations[key] = {"signature":signature,"organ":found}
	return found

static func stationary(e: Dictionary) -> bool:
	if e.get("category","") == "building": return e.get("complete",false)
	if float(e.get("travelSpeed",0)) > .01: return false
	var orders: Array = e.get("orders",[])
	return orders.is_empty() or orders[0].get("kind","") in ["hold","stop"]

func quote(action: String,actor_id: int,controller := 1,allow_paused_preview := false) -> Dictionary:
	var spec: Dictionary = data().actions.get(action,{})
	var e := game.entity(actor_id)
	var result := {"ok":false,"action":action,"actor":actor_id,"reason":"操作不可用"}
	if spec.is_empty() or not enabled(): return result
	if game.paused and not allow_paused_preview: result.reason = "时间暂停，恢复后再执行器官操作"; return result
	if e.is_empty() or int(e.get("faction",0)) != controller or controller < 1 or controller > 3 or float(e.get("hp",0)) <= 0:
		result.reason = "需要本阵营存活单位或建筑"; return result
	if e.kind not in spec.actorKinds or not stationary(e): result.reason = "需要停下的红细胞或已完成的研究站"; return result
	if organ(e) != spec.organ: result.reason = "需要进入对应器官的真实组织地面"; return result
	var f := faction_state(controller)
	var ready_at := float(f.cooldowns.get(action,0))
	result.cooldownRemaining = maxf(0,ready_at-float(game.state.time))
	if result.cooldownRemaining > .000001: result.reason = "器官操作冷却中"; return result
	if spec.has("requiredTech") and not game.state.factions[controller-1].tech.get(spec.requiredTech,false): result.reason = "需要先完成稳定生产研究"; return result
	if float(f.glycogen) < float(spec.get("glycogenCost",0)) or float(f.waste) < float(spec.get("wasteCost",0)):
		result.reason = "糖原或净化杂质储备不足"; return result
	if float(f.glycogen)+float(spec.get("glycogenGain",0)) > float(data().limits.glycogen): result.reason = "糖原储备已满"; return result
	for kind in spec.cost:
		if game.economy.stock(controller,kind)+.000001 < float(spec.cost[kind]): result.reason = "缺少"+str(WarData.config().Data.names[kind]); return result
	result.merge({"ok":true,"reason":"","organ":spec.organ,"cost":spec.cost.duplicate(true),"cooldown":spec.cooldown},true)
	return result

func available_actions(actor_id: int,controller := 1) -> Array:
	var result: Array = []
	var e := game.entity(actor_id)
	if e.is_empty(): return result
	var at := organ(e)
	for action in data().actions:
		if data().actions[action].organ == at and e.kind in data().actions[action].actorKinds:
			var q := quote(action,actor_id,controller,true)
			q.name = data().actions[action].name
			q.description = data().actions[action].description
			result.append(q)
	return result

func request(action: String,actor_id: int,controller := 1) -> Dictionary:
	# This is the sole resource-spending entry point, called by an explicit player command.
	var result := quote(action,actor_id,controller)
	if not result.ok: return result
	var spec: Dictionary = data().actions[action]
	if not game.economy.pay(controller,spec.cost): result.ok = false; result.reason = "资源不足"; return result
	var f := faction_state(controller)
	f.glycogen = float(f.glycogen)+float(spec.get("glycogenGain",0))-float(spec.get("glycogenCost",0))
	f.waste = float(f.waste)-float(spec.get("wasteCost",0))
	for kind in spec.get("gain",{}): game.economy.add(controller,kind,float(spec.gain[kind]),"liver" if spec.organ == "liver" else "")
	f.cooldowns[action] = float(game.state.time)+float(spec.cooldown)
	if action == "brain_command": f.commandUntil = float(game.state.time)+float(spec.duration)
	if action == "pancreas_regulate": f.pancreasUntil = float(game.state.time)+float(spec.duration)
	game.event("organ_action",{"source":actor_id,"faction":controller,"action":action,"organ":spec.organ,"cost":spec.cost.duplicate(true)})
	return result

func multiplier(e: Dictionary,field: String) -> float:
	if not enabled() or field != "attackSpeedMultiplier" or e.get("category","") != "unit" or float(e.get("hp",0)) <= 0: return 1.0
	var faction := int(e.get("faction",0))
	if faction < 1 or faction > 3 or e.kind in ["worker","b_cell","dendritic_cell"] or WarData.spec(e.kind).get("medicineHelper",false): return 1.0
	return float(data().actions.brain_command.attackSpeedMultiplier) if float(faction_state(faction).commandUntil) > float(game.state.time) else 1.0

func training_cost(building: Dictionary,kind: String) -> Dictionary:
	var cost: Dictionary = WarData.spec(kind).get("cost",{}).duplicate(true)
	var faction := int(building.get("faction",0))
	if faction < 1 or faction > 3 or organ(building).is_empty(): return cost
	if float(faction_state(faction).pancreasUntil) > float(game.state.time) and cost.has("food"):
		# Stable resource prices: 12 * 0.8 must be payable with exactly 9.6,
		# rather than requiring 9.600000000000001 from binary multiplication.
		cost.food = roundf(float(cost.food)*float(data().actions.pancreas_regulate.trainingFoodMultiplier)*1000.0)/1000.0
	return cost

func production_rate(building: Dictionary,queue: Dictionary) -> float:
	# The existing queue, cost, tier checks, completion and cancellation remain authoritative.
	return float(data().organs.brain.researchRate) if queue.has("tech") and building.get("kind","") == "lab" and float(building.get("hp",0)) > 0 and building.get("complete",false) and organ(building) == "brain" else 1.0

func strong_training_allowed(building: Dictionary,kind: String) -> bool:
	if kind not in data().organs.liver.strongKinds: return true
	return organ(building) == "liver"

func can_transfer(e: Dictionary,destination: String) -> bool:
	# Existing scenarios.transfer owns placement, navigation and the transfer event.
	return e.get("category","") == "unit" and organ(e) == "heart" and game.navigation.organs.has(destination) and destination not in ["heart","pancreas","bladder"]

func update_unit(e: Dictionary,dt: float) -> void:
	# Called exactly once by combat.update_status, replacing the legacy kidney block.
	if not enabled() or game.paused or dt <= 0 or e.get("category","") != "unit" or float(e.get("hp",0)) <= 0: return
	var at := organ(e)
	e.organ = at
	if at == "heart": e.requiresHeart = false
	if at not in ["kidney_l","kidney_r"] or int(e.get("faction",0)) <= 0 or int(e.get("faction",0)) > 3:
		e.kidneyProgress = 0.0
		return
	var config: Dictionary = WarData.config().CombatConfig
	var needs: bool = float(e.hp) < float(e.maxHp) or float(e.get("impurities",0)) > 0
	for kind in e.get("statuses",{}): needs = needs or config.statuses.get(kind,{}).get("clearOrgan","") == "kidney"
	if not needs: return
	var before := float(e.get("kidneyProgress",0))
	e.kidneyProgress = before+dt
	e.combatState = "recovering"
	if float(e.kidneyProgress) < float(config.kidney.cleanseSeconds): return
	var waste := maxf(0,float(e.get("impurities",0)))
	var cleared: Array = []
	for kind in e.get("statuses",{}).keys():
		if config.statuses.get(kind,{}).get("clearOrgan","") == "kidney":
			cleared.append(kind); e.statuses.erase(kind)
			if kind == "toxin": waste += float(data().kidney.wastePerToxinClear)
	e.impurities = 0.0
	e.hp = minf(float(e.maxHp),float(e.hp)+float(config.kidney.healPerSecond)*minf(dt,float(e.kidneyProgress)-float(config.kidney.cleanseSeconds)))
	var f := faction_state(int(e.faction))
	var accepted := minf(waste,maxf(0,float(data().limits.waste)-float(f.waste)))
	f.waste = float(f.waste)+accepted
	if waste > 0 or not cleared.is_empty() or before < float(config.kidney.cleanseSeconds):
		game.event("organ_purified",{"target":e.id,"faction":e.faction,"organ":at,"cleared":cleared,"wasteAccepted":accepted,"wasteDiscarded":waste-accepted})

static func validate_state(snapshot: Dictionary) -> String:
	if not snapshot.get("entities",{}) is Dictionary: return "器官单位数据无效"
	for e in snapshot.get("entities",{}).values():
		if not e is Dictionary: return "器官单位数据无效"
		for field in ["kidneyProgress","impurities"]:
			if e.has(field) and (not _number(e[field]) or float(e[field]) < 0): return "肾休整或杂质数值无效"
	if not snapshot.has("organFunctions"): return ""
	var section: Variant = snapshot.organFunctions
	if not section is Dictionary or section.get("schema",0) != 1 or not section.get("factions") is Array or section.factions.size() != 3: return "器官功能存档结构无效"
	for f in section.factions:
		if not f is Dictionary: return "器官阵营数据无效"
		for field in ["glycogen","waste","commandUntil","pancreasUntil"]:
			if not _number(f.get(field)) or float(f[field]) < 0: return "器官资源或时限无效"
		if float(f.glycogen) > float(data().limits.glycogen) or float(f.waste) > float(data().limits.waste): return "器官储备超出容量"
		if not f.get("cooldowns") is Dictionary: return "器官冷却无效"
		for key in f.cooldowns:
			if not data().actions.has(key) or not _number(f.cooldowns[key]) or float(f.cooldowns[key]) < 0: return "器官冷却无效"
	return ""

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
