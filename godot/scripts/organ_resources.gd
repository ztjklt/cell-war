class_name WarOrganResources
extends RefCounted
## Renewable organ stations for new life runs. Frozen legacy scenarios keep their data.
var game: WarSimulation

func _init(owner: WarSimulation) -> void:
	game = owner

static func data() -> Dictionary:
	return WarData.read("organ_resources")

func enabled() -> bool:
	return game.state.get("organResources") is Dictionary

func begin() -> void:
	game.state.organResources = {"version":1,"refreshElapsed":0.0}
	game.state.resources = {}
	for spec in data().sources:
		var p := WarData.point(spec.point)
		# Never turn an arbitrary projected point into a resource on another layer.
		if game.navigation.organ_at(p,"worker") != spec.organ or not game.navigation.point_allowed(p,0,"worker"):
			push_error("Invalid organ resource station: "+str(spec.id))
			continue
		game.state.resources[spec.id] = {"id":spec.id,"kind":spec.kind,"organId":spec.organ,
			"x":p.x,"y":p.y,"amount":float(spec.capacity),"max":float(spec.capacity),
			"initialAmount":float(spec.capacity),"regen":float(spec.refillPerSecond),
			"resourcePoint":true,"organSource":true,"radius":2.2,"vesselLane":0,"contested":false}

func advance(dt: float) -> void:
	if not enabled(): return
	var model: Dictionary = game.state.organResources
	model.refreshElapsed += dt
	var period: float = data().refreshSeconds
	if float(model.refreshElapsed)+.000001 < period: return
	var elapsed := floorf((float(model.refreshElapsed)+.000001)/period)*period
	model.refreshElapsed = maxf(0,float(model.refreshElapsed)-elapsed)
	for node in game.state.resources.values():
		if not node.get("organSource",false): continue
		node.contested = contested(node)
		if not node.contested: node.amount = minf(float(node.max),float(node.amount)+float(node.regen)*elapsed)

func contested(node: Dictionary) -> bool:
	var p := WarData.point(node)
	var radius: float = data().contestRadius
	for e in game.units():
		if int(e.faction) <= 1 or int(e.get("vesselLane",0)) != 0: continue
		if WarData.point(e).distance_squared_to(p) > radius*radius: continue
		if game.navigation.organ_at(WarData.point(e),e.kind) != node.organId: continue
		if game.navigation.clear_segment(WarData.point(e),p,0,e.kind): return true
	return false

static func validate(state: Dictionary) -> String:
	if not state.has("organResources"): return ""
	var model: Variant = state.organResources
	if not model is Dictionary or model.get("version") != 1 or not _number(model.get("refreshElapsed")):
		return "器官资源版本或恢复计时无效"
	if float(model.refreshElapsed) < 0 or float(model.refreshElapsed) >= float(data().refreshSeconds)+.000001:
		return "器官资源恢复计时超出范围"
	if not state.get("resources") is Dictionary: return "器官采集站列表无效"
	for spec in data().sources:
		var node: Variant = state.resources.get(spec.id)
		if not node is Dictionary or node.get("id") != spec.id or node.get("kind") != spec.kind or node.get("organId") != spec.organ:
			return "器官采集站身份无效"
		if node.get("vesselLane",-1) != 0 or not node.get("organSource",false): return "器官采集站通行层无效"
		for field in ["x","y","amount","max","regen"]:
			if not _number(node.get(field)): return "器官采集站数值无效"
		if WarData.point(node).distance_to(WarData.point(spec.point)) > .001: return "器官采集站位置无效"
		if node.max != spec.capacity or node.regen != spec.refillPerSecond or node.amount < 0 or node.amount > node.max:
			return "器官采集站库存或恢复速度无效"
	return ""

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
