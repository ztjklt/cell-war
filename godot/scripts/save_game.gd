class_name WarSave
extends RefCounted
const SCHEMA := "cell-war-godot/1"
const MAX_BYTES := 16*1024*1024
static var directory := "user://saves"

static func path(slot: int) -> String:
	return directory+"/slot_%d.json" % clampi(slot,0,3)

static func write(game: WarSimulation,slot: int) -> Error:
	var result := _write_to(game,path(slot))
	if result == OK: game.notify("已保存到本地槽位 %d" % slot)
	return result

static func life_auto_path() -> String:
	return directory+"/life/auto.json"

static func write_life_auto(game: WarSimulation) -> Error:
	return _write_to(game,life_auto_path())

static func _write_to(game: WarSimulation,destination: String) -> Error:
	DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
	var snapshot := game.snapshot()
	var error := validate(snapshot)
	if not error.is_empty():
		game.notify("存档失败："+error)
		return ERR_INVALID_DATA
	var envelope := {"schema":SCHEMA,"mode":game.mode,"snapshot":snapshot,
		"savedAt":Time.get_datetime_string_from_system(true)}
	var file := FileAccess.open(destination+".tmp",FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(envelope,"",true,true))
	file.flush()
	file.close()
	var result := DirAccess.rename_absolute(destination+".tmp",destination)
	return result

static func read_slot(game: WarSimulation,slot: int) -> Error:
	return _read_from(game,path(slot))

static func read_life_auto(game: WarSimulation) -> Error:
	return _read_from(game,life_auto_path())

static func _read_from(game: WarSimulation,source: String) -> Error:
	var file := FileAccess.open(source,FileAccess.READ)
	if file == null: return ERR_FILE_NOT_FOUND
	if file.get_length() > MAX_BYTES: return ERR_FILE_CORRUPT
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return ERR_FILE_CORRUPT
	var data: Dictionary = parser.data
	if data.get("schema","") != SCHEMA or not data.get("snapshot") is Dictionary:
		return ERR_FILE_UNRECOGNIZED
	var error := validate(data.snapshot)
	if not error.is_empty():
		game.notify("存档未载入："+error)
		return ERR_FILE_CORRUPT
	# Validate before replacing the live state, so malformed saves leave it intact.
	game.mode = data.get("mode","fullbody")
	game.restore(data.snapshot)
	game.notify("已恢复本地存档")
	return OK

static func validate(state: Dictionary) -> String:
	var t_error := WarTCellRuntime.validate_state(state)
	if not t_error.is_empty(): return t_error
	var resources_error := WarOrganResources.validate(state)
	if not resources_error.is_empty(): return resources_error
	var organs_error := WarOrganFunctions.validate_state(state)
	if not organs_error.is_empty(): return organs_error
	var life_error := WarLifeRun.validate(state)
	if not life_error.is_empty(): return life_error
	var influenza_error := WarInfluenzaColonies.validate_state(state)
	if not influenza_error.is_empty(): return influenza_error
	var medicine_supply_error := WarMedicineSupply.validate_state(state)
	if not medicine_supply_error.is_empty(): return medicine_supply_error
	var medicine_helper_error := WarMedicineHelpers.validate_state(state)
	if not medicine_helper_error.is_empty(): return medicine_helper_error
	if not state.get("entities") is Dictionary or not state.get("factions") is Array or state.factions.size() != 3:
		return "阵营或单位数据无效"
	if not _number(state.get("time",-1)) or float(state.time) < 0:
		return "时间数据无效"
	if not _number(state.get("nextId")) or int(state.nextId) < 1 or int(state.nextId) != float(state.nextId) or state.entities.size() > 4096:
		return "单位编号范围无效"
	var ids: Dictionary = {}
	for key in state.entities:
		var e: Variant = state.entities[key]
		if not e is Dictionary or not WarData.config().Data.units.has(e.get("kind","")) and not WarData.config().Data.buildings.has(e.get("kind","")):
			return "未知细胞或建筑"
		if not _number(e.get("id")) or int(e.id) != float(e.id) or int(e.id) <= 0 or str(int(e.id)) != key or ids.has(key):
			return "单位编号无效"
		ids[key] = true
		for field in ["x","y","hp","maxHp","faction"]:
			if not _number(e.get(field)): return "单位数值无效"
		if e.hp < 0 or e.maxHp <= 0 or e.hp > e.maxHp or e.faction < 0 or e.faction > 3 or e.faction != int(e.faction):
			return "生命或阵营数据无效"
		if e.x < 0 or e.x > 2048 or e.y < 0 or e.y > 4096:
			return "单位超出地图"
		if int(e.id) >= int(state.nextId): return "单位编号超出分配范围"
		if not _number(e.get("vesselLane",0)) or int(e.get("vesselLane",0)) < 0 or int(e.get("vesselLane",0)) > 211: return "通行层无效"
		if not e.get("category","") in ["unit","building"]: return "单位类别无效"
		if not e.get("statuses",{}) is Dictionary or not e.get("cargo",{}) is Dictionary: return "状态或携带物无效"
		if not e.get("orders",[]) is Array and not e.get("orders",{}) is Dictionary:
			return "命令队列无效"
		for kind in e.get("statuses",{}):
			if not WarData.config().CombatConfig.statuses.has(kind): return "未知状态效果"
			var status: Variant = e.statuses[kind]
			if not status is Dictionary: return "状态效果无效"
			for field in ["duration","moveMultiplier","attackMultiplier","attackSpeedMultiplier","damagePerSecond"]:
				if status.has(field) and (not _number(status[field]) or status[field] < 0): return "状态效果数值无效"
		for kind in e.get("cargo",{}):
			if not _number(e.cargo[kind]) or float(e.cargo[kind]) < 0: return "携带物数值无效"
		if e.get("queue",[]) is Array:
			for q in e.queue:
				if not q is Dictionary or not _number(q.get("remaining")) or q.remaining < 0: return "生产队列无效"
				if not WarData.config().Data.units.has(q.get("unit","")) and not WarData.config().Data.tech.has(q.get("tech","")): return "未知生产项目"
	for faction in state.factions:
		if not faction is Dictionary or not faction.get("stock") is Dictionary or not faction.get("food") is Array:
			return "资源数据无效"
		for kind in ["wood","oxygen"]:
			if not _number(faction.stock.get(kind,0)) or float(faction.stock.get(kind,0)) < 0: return "资源数值无效"
		for batch in faction.food:
			if not batch is Dictionary or not _number(batch.get("amount")) or batch.amount < 0 or not _number(batch.get("born")): return "葡萄糖数据无效"
	if state.get("campaign") is Dictionary:
		var map_id: String = state.campaign.get("map_id","")
		if not map_id in ["nasal_01","trachea_01","lungs_01"]: return "战役地图不可用"
	var projectiles: Variant = state.get("combatProjectiles",[])
	if not projectiles is Array and not (projectiles is Dictionary and projectiles.is_empty()): return "弹道列表无效"
	if projectiles is Array:
		if projectiles.size() > 128: return "弹道数量无效"
		for p in projectiles:
			if not p is Dictionary or not WarData.config().Data.units.has(p.get("sourceKind","")): return "弹道来源无效"
			for field in ["x","y","dx","dy","speed","ttl","damage"]:
				if not _number(p.get(field)): return "弹道数值无效"
			if p.speed <= 0 or p.ttl <= 0 or p.damage < 0 or absf(float(p.dx)*float(p.dx)+float(p.dy)*float(p.dy)-1) > .0001: return "弹道方向或生命无效"
	return ""

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
