class_name WarMedicineSupply
extends RefCounted
## Money -> inventory -> certified local deployment. All mutations use requests.
const MEDICINE := "fever_pain_relief"
var game: WarSimulation
var helpers: WarMedicineHelpers
var staging := false # Explicit integration tests only, removed from player interfaces.


func _init(owner: WarSimulation, helper_service: WarMedicineHelpers, staging_test := false) -> void:
	game = owner; helpers = helper_service; staging = staging_test


static func definition() -> Dictionary:
	for entry in WarData.read("medicines").entries:
		if entry.id == MEDICINE: return entry
	return {}


func enabled() -> bool:
	return game != null and game.life.enabled() and game.mode == "fullbody" and not game.is_campaign() and str(game.life.state().phase) != "ended"


func released() -> bool:
	return enabled() and (staging or (bool(WarMedicineHelpers.data().releaseEnabled) and bool(definition().purchase.canSell) and bool(definition().purchase.canDeploy)))


func begin() -> void:
	game.state.medicineSupply = {"version":1, "runId":Crypto.new().generate_random_bytes(12).hex_encode(),
		"issued":0, "receiptFloor":0, "receipts":{}, "inventory":{MEDICINE:0},
		"purchased":0, "deployed":0}


func state() -> Dictionary:
	return game.state.get("medicineSupply", {})


func reset() -> void:
	if not game.life.enabled(): return
	if not game.state.has("medicineSupply"): begin()
	var s := state()
	s.version = int(s.version)
	for key in ["issued", "receiptFloor", "purchased", "deployed"]: s[key] = int(s[key])
	s.inventory[MEDICINE] = int(s.inventory[MEDICINE])
	for receipt in s.receipts.values():
		for key in ["sequence", "quantity", "cost", "helper"]: receipt[key] = int(receipt.get(key, 0))


func count() -> int:
	return int(state().get("inventory", {}).get(MEDICINE, 0))


func quote_purchase(medicine := MEDICINE, quantity := 1) -> Dictionary:
	var result := {"ok":false, "reason":"药品尚未开放", "medicine":medicine, "quantity":quantity,
		"unitPrice":int(definition().balanceDefaults.values.purchasePrice), "inventory":count()}
	if medicine != MEDICINE or not released() or state().is_empty(): return result
	if quantity < 1 or quantity > int(WarMedicineHelpers.data().tuning.purchaseQuantityLimit): result.reason = "购买数量无效"; return result
	if count() + quantity > int(WarMedicineHelpers.data().tuning.inventoryLimit): result.reason = "药品库存已满"; return result
	result.cost = int(result.unitPrice) * quantity
	result.money = int(game.life.state().money)
	if int(result.money) < int(result.cost): result.reason = "金钱不足"; return result
	result.ok = true; result.reason = ""
	return result


func quote_deployment(actor_id: int, selected_ids: Array = []) -> Dictionary:
	var result := {"ok":false, "reason":"需要选中本阵营存活红细胞", "actor":actor_id, "inventory":count()}
	if not released() or state().is_empty(): result.reason = "药品尚未开放"; return result
	var ids: Array = selected_ids if not selected_ids.is_empty() else game.selected
	var worker := game.entity(actor_id)
	var selected := ids.any(func(id): return WarMedicineHelpers._integer(id, 1) and int(id) == actor_id)
	if not selected or worker.is_empty() or worker.kind != "worker" or int(worker.faction) != 1 or float(worker.hp) <= 0: return result
	if count() <= 0: result.reason = "药品库存不足"; return result
	var active := game.units().filter(func(e): return e.kind == MEDICINE)
	if active.size() >= int(WarMedicineHelpers.data().tuning.activeHelperLimit): result.reason = "药品助手数量已满"; return result
	var placement := helpers.find_placement(worker)
	if not placement.ok: result.reason = placement.reason; return result
	result.merge(placement, true)
	return result


func reserve_request() -> Dictionary:
	if not enabled() or state().is_empty() or int(state().issued) >= 2147483646: return {}
	state().issued = int(state().issued) + 1
	return {"runId":str(state().runId), "sequence":int(state().issued)}


func queue_purchase(medicine := MEDICINE, quantity := 1) -> Dictionary:
	var quote := quote_purchase(medicine, quantity)
	if not quote.ok: return quote
	return _queue("medicine_buy", {"medicine":medicine, "quantity":quantity, "unitPrice":quote.unitPrice})


func queue_deployment(actor_id: int) -> Dictionary:
	var quote := quote_deployment(actor_id)
	if not quote.ok: return quote
	return _queue("medicine_deploy", {"medicine":MEDICINE, "actor":actor_id})


func _queue(action: String, payload: Dictionary) -> Dictionary:
	var pending: Array = game.state.commands.filter(func(c): return str(c.get("action", "")).begins_with("medicine_"))
	if pending.size() >= int(WarMedicineHelpers.data().tuning.queueLimit): return {"ok":false, "reason":"药品操作队列已满"}
	var request := reserve_request()
	if request.is_empty(): return {"ok":false, "reason":"药品请求不可用"}
	var command := payload.duplicate(true); command.action = action; command.request = request
	game.submit_player(command)
	return {"ok":true, "queued":true, "request":request, "reason":""}


func cancel_queued(request: Dictionary) -> Dictionary:
	var validation := _request(request)
	if not validation.ok: return validation
	if validation.has("receipt"): return validation.receipt.duplicate(true)
	for index in game.state.commands.size():
		var command: Dictionary = game.state.commands[index]
		var pending: Dictionary = command.get("request", {})
		if pending.get("runId", "") == request.runId and int(pending.get("sequence", 0)) == int(request.sequence) and command.get("action", "") in ["medicine_buy", "medicine_deploy"]:
			game.state.commands.remove_at(index)
			return _settle(request, "cancel", {"ok":false, "reason":"已取消", "cancelled":true})
	return {"ok":false, "reason":"该请求已执行或不在队列中"}


func purchase(request: Dictionary, medicine: String, quantity: int, expected_price: int) -> Dictionary:
	var validation := _request(request)
	if not validation.ok: return validation
	if validation.has("receipt"): return validation.receipt.duplicate(true)
	if game.paused: return {"ok":false, "reason":"暂停中，请通过命令队列执行"}
	var quote := quote_purchase(medicine, quantity)
	if not quote.ok: return _settle(request, "buy", quote)
	if expected_price != int(quote.unitPrice): return _settle(request, "buy", {"ok":false, "reason":"报价已变化，请重新购买"})
	var cost := int(quote.cost)
	game.life.state().money = int(game.life.state().money) - cost
	game.life.state().spent = int(game.life.state().spent) + cost
	state().inventory[MEDICINE] = count() + quantity
	state().purchased = int(state().purchased) + quantity
	game.event("medicine_purchase", {"medicine":MEDICINE, "quantity":quantity, "cost":cost, "sequence":request.sequence})
	return _settle(request, "buy", {"ok":true, "reason":"", "quantity":quantity, "cost":cost})


func deploy(request: Dictionary, actor_id: int, selected_ids: Array) -> Dictionary:
	var validation := _request(request)
	if not validation.ok: return validation
	if validation.has("receipt"): return validation.receipt.duplicate(true)
	if game.paused: return {"ok":false, "reason":"暂停中，请通过命令队列执行"}
	var quote := quote_deployment(actor_id, selected_ids)
	if not quote.ok: return _settle(request, "deploy", quote)
	var helper := helpers.spawn_at(quote, actor_id)
	if helper.is_empty(): return _settle(request, "deploy", {"ok":false, "reason":"落点已被占用，请重新派遣"})
	state().inventory[MEDICINE] = count() - 1
	state().deployed = int(state().deployed) + 1
	return _settle(request, "deploy", {"ok":true, "reason":"", "helper":int(helper.id), "organ":quote.organ})


func _request(request: Dictionary) -> Dictionary:
	if not enabled() or state().is_empty(): return {"ok":false, "reason":"当前模式不提供药品"}
	if request.get("runId", "") != str(state().runId): return {"ok":false, "reason":"请求不属于当前世界"}
	if not WarMedicineHelpers._integer(request.get("sequence"), 1) or int(request.sequence) > int(state().issued): return {"ok":false, "reason":"药品请求编号无效"}
	var key := str(int(request.sequence))
	if state().receipts.has(key): return {"ok":true, "receipt":state().receipts[key]}
	if int(request.sequence) <= int(state().receiptFloor): return {"ok":false, "reason":"药品请求已过期"}
	return {"ok":true}


func _settle(request: Dictionary, action: String, result: Dictionary) -> Dictionary:
	var receipt := {"ok":bool(result.ok), "reason":str(result.get("reason", "")), "action":action,
		"medicine":MEDICINE, "sequence":int(request.sequence), "quantity":maxi(0, int(result.get("quantity", 0))),
		"cost":int(result.get("cost", 0)) if result.ok else 0, "helper":int(result.get("helper", 0)), "time":float(game.state.time)}
	if result.get("cancelled", false): receipt.cancelled = true
	if result.has("organ"): receipt.organ = result.organ
	state().receipts[str(int(request.sequence))] = receipt
	while state().receipts.size() > int(WarMedicineHelpers.data().tuning.receiptLimit):
		var lowest := 2147483647
		for key in state().receipts: lowest = mini(lowest, int(key))
		state().receiptFloor = maxi(int(state().receiptFloor), lowest)
		state().receipts.erase(str(lowest))
	return receipt.duplicate(true)


static func validate_state(world: Dictionary) -> String:
	if not world.has("medicineSupply"): return ""
	if not world.get("lifeRun") is Dictionary: return "药品库存缺少生活模式"
	var s: Variant = world.medicineSupply
	if not s is Dictionary or s.get("version") != 1 or not s.get("runId") is String or str(s.runId).length() != 24: return "药品库存版本或世界标识无效"
	for key in ["issued", "receiptFloor", "purchased", "deployed"]:
		if not WarMedicineHelpers._integer(s.get(key), 0): return "药品库存计数无效"
	if int(s.receiptFloor) > int(s.issued) or int(s.deployed) > int(s.purchased): return "药品库存计数顺序无效"
	if not s.get("inventory") is Dictionary or s.inventory.keys() != [MEDICINE]: return "药品库存种类无效"
	if not WarMedicineHelpers._integer(s.inventory[MEDICINE], 0) or int(s.inventory[MEDICINE]) > int(WarMedicineHelpers.data().tuning.inventoryLimit): return "药品库存数量无效"
	if int(s.inventory[MEDICINE]) != int(s.purchased) - int(s.deployed): return "药品库存收支不符"
	if not s.get("receipts") is Dictionary or s.receipts.size() > int(WarMedicineHelpers.data().tuning.receiptLimit): return "药品操作记录无效"
	for key in s.receipts:
		if not key is String or not key.is_valid_int() or str(int(key)) != key: return "药品操作编号无效"
		var r: Variant = s.receipts[key]
		if not r is Dictionary or not r.get("ok") is bool or r.get("medicine", "") != MEDICINE: return "药品操作记录身份无效"
		if not WarMedicineHelpers._integer(r.get("sequence"), 1) or int(r.sequence) != int(key) or int(r.sequence) > int(s.issued) or int(r.sequence) <= int(s.receiptFloor): return "药品操作记录序号无效"
		if r.get("action", "") not in ["buy", "deploy", "cancel"]: return "药品操作类型无效"
		for field in ["quantity", "cost", "helper"]:
			if not WarMedicineHelpers._integer(r.get(field), 0): return "药品操作数值无效"
		if not WarMedicineHelpers._number(r.get("time")) or float(r.time) < 0: return "药品操作时间无效"
	for command in WarData.array(world.get("commands", [])):
		if not command is Dictionary or command.get("action", "") not in ["medicine_buy", "medicine_deploy"]: continue
		var request: Variant = command.get("request")
		if not request is Dictionary or request.get("runId", "") != s.runId or not WarMedicineHelpers._integer(request.get("sequence"), 1): return "药品排队请求身份无效"
		if int(request.sequence) > int(s.issued) or command.get("medicine", "") != MEDICINE: return "药品排队请求种类无效"
		if command.action == "medicine_buy":
			if not WarMedicineHelpers._integer(command.get("quantity"), 1) or int(command.quantity) > int(WarMedicineHelpers.data().tuning.purchaseQuantityLimit) or not WarMedicineHelpers._integer(command.get("unitPrice"), 0): return "药品排队购买数值无效"
		elif not WarMedicineHelpers._integer(command.get("actor"), 1) or not command.get("ids") is Array: return "药品排队派遣对象无效"
	return ""


func dispose() -> void:
	game = null; helpers = null
