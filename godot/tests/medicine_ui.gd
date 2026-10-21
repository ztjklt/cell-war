extends "res://tests/opening_flow.gd"
## Actual money/inventory/queue UI. Optional staging is explicit test-only service gate.
const MED_OUT := "res://test-output/medicine-ui/"
var staged := false
var red: Dictionary

func medicine_card() -> Dictionary:
	return main.hud.medicine_cards.get(WarMedicineSupply.MEDICINE,{})

func open_medicines() -> void:
	if main.hud.menu.visible: await press(named_button(main.hud.menu_body,"返回游戏"))
	await press(named_button(main.hud.root,"≡"))
	await press(named_button(main.hud.menu_body,"药品补给"))
	check(main.hud.menu.visible and main.game.paused,"actual menu opens the paused medicine supply page")

func resume_commands() -> void:
	if main.hud.menu.visible: await press(named_button(main.hud.menu_body,"返回游戏"))
	if main.game.paused: await press(main.hud.pause_button)
	main.game.update(.15); await frames(12)

func confirm_deploy() -> bool:
	if not await press(medicine_card().deploy): return false
	if not check(named_button(main.hud.menu_body,"确认派遣 · 消耗库存 1") != null,"deployment opens an explicit inventory confirmation"): return false
	return await press(named_button(main.hud.menu_body,"确认派遣 · 消耗库存 1"))

func make_room_for_helper() -> bool:
	# Read-only geometry chooses a nearby walk target; only real UI moves the red cell.
	for attempt in 3:
		if main.game.medicine_helpers.find_placement(red).ok: return true
		var start := WarData.point(red)
		var goal := Vector2.INF
		for radius in [.5,1.0,1.5,2.0,3.0]:
			for i in 24:
				var p: Vector2 = start+Vector2.from_angle(TAU*i/24)*radius
				if not main.game.navigation.point_allowed(p,0,"worker") or not main.game.navigation.clear_segment(start,p,0,"worker"): continue
				var probe := red.duplicate(); probe.x = p.x; probe.y = p.y
				if main.game.medicine_helpers.find_placement(probe).ok: goal = p; break
			if goal != Vector2.INF: break
		if goal == Vector2.INF: return false
		if not await move_to(goal): return false
		await advance(4)
	return main.game.medicine_helpers.find_placement(red).ok

func queued(action: String) -> Array:
	return main.game.state.commands.filter(func(command): return command.get("action","") == action)

func helpers() -> Array:
	return main.game.units().filter(func(entity): return entity.kind == WarMedicineSupply.MEDICINE)

func capture_medicine(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(MED_OUT+name+".png")

func save_row() -> HBoxContainer:
	for child in main.hud.menu_body.get_children():
		if child is HBoxContainer and child.get_child(0).text == "槽位 1": return child
	return null

func open_saves() -> void:
	if main.hud.menu.visible: await press(named_button(main.hud.menu_body,"返回游戏"))
	await press(named_button(main.hud.root,"≡"))
	await press(named_button(main.hud.menu_body,"本地存档"))

func exercise() -> void:
	await frames(12)
	await press(main.hud.home.buttons[0])
	if not main.game.medicine_supply.released() and "--medicine-ui-staging" in OS.get_cmdline_user_args():
		main.game.medicine_supply.staging = true; staged = true
	if not check(main.game.medicine_supply.released(),"real supply release is open (or explicitly requested service staging fixture)"): return
	red = main.game.units().filter(func(entity): return entity.faction == 1 and entity.kind == "worker")[0]
	check(int(main.game.life.state().money) == 300 and main.game.medicine_supply.count() == 0,"genuine new life retains original wallet and zero free medicine")
	await click(screen(WarData.point(red)))
	for i in 6: key(KEY_Q)
	var began := Time.get_ticks_msec()
	while main.camera_travel.active and Time.get_ticks_msec()-began < 2500: await process_frame
	await check_initial_escape(red)
	if not check(await make_room_for_helper(),"original red cell reaches a legal deployment anchor using only real movement"): return
	await open_medicines()
	check(medicine_card().deploy.disabled and medicine_card().condition.text.contains("库存不足"),"zero inventory visibly prevents deployment")
	for id in main.hud.medicine_cards:
		if id != WarMedicineSupply.MEDICINE:
			check(main.hud.medicine_cards[id].buy.disabled and main.hud.medicine_cards[id].buy.text == "尚未实装","other medicine cannot be sold: "+id)
	for i in 3: await press(medicine_card().buy)
	check(queued("medicine_buy").size() == 3 and int(main.game.life.state().money) == 300 and main.game.medicine_supply.count() == 0,"paused clicks queue three purchases without spending or granting inventory early")
	check(medicine_card().buy.disabled and medicine_card().condition.text.contains("预留") and main.hud.medicine_balance.text.contains("240"),"fourth purchase is blocked by the actual 240 money reservation")
	await capture_medicine("purchases-reserved")
	var cancel: Button = main.hud.medicine_pending_rows.values()[0]
	await press(cancel)
	check(queued("medicine_buy").size() == 2 and int(main.game.life.state().money) == 300,"actual pending purchase cancellation removes one request without changing the wallet")
	await press(main.hud.medicine_pending_rows.values()[0])
	await resume_commands()
	check(main.game.medicine_supply.count() == 1 and int(main.game.life.state().money) == 220 and int(main.game.life.state().spent) == 80,"normal resumed buy command spends eighty and creates exactly one inventory")
	await open_medicines()
	if not await press(medicine_card().deploy): return
	check(main.game.medicine_supply.count() == 1 and queued("medicine_deploy").is_empty(),"opening deployment confirmation does not consume or enqueue medicine")
	await press(named_button(main.hud.menu_body,"取消派遣"))
	check(main.game.medicine_supply.count() == 1 and queued("medicine_deploy").is_empty(),"actual confirmation cancel leaves inventory and queue intact")
	if not await confirm_deploy(): return
	if not check(queued("medicine_deploy").size() == 1 and main.game.medicine_supply.count() == 1,"confirmation queues the selected original red cell without consuming early"): return
	check(medicine_card().deploy.disabled and medicine_card().condition.text.contains("待执行派遣预留"),"one medicine cannot be double-booked by continuous deploy clicks")
	await press(main.hud.medicine_pending_rows.values()[0])
	check(queued("medicine_deploy").is_empty() and main.game.medicine_supply.count() == 1,"actual queued deployment cancel preserves inventory")
	if not await confirm_deploy(): return
	await resume_commands()
	if not check(helpers().size() == 1 and main.game.medicine_supply.count() == 0,"real resumed deployment creates one helper and consumes exactly one medicine"): return
	var helper: Dictionary = helpers()[0]
	check(float(helper.medicineRemaining) > 89 and float(helper.medicineRemaining) <= 90 and int(helper.vesselLane) == 0,"helper has the real ninety-second tissue lifecycle")
	check(main.game.navigation.organ_at(WarData.point(helper),helper.kind) == main.game.navigation.organ_at(WarData.point(red),"worker"),"actual helper enters the same organ as the selected red cell")
	await capture_medicine("helper-deployed")
	await open_medicines()
	check(medicine_card().deploy.disabled and medicine_card().condition.text.contains("库存不足"),"used-up medicine remains visibly unavailable after actual deployment")
	await press(medicine_card().buy)
	await resume_commands()
	check(int(main.game.life.state().money) == 140 and main.game.medicine_supply.count() == 1,"second real purchase supplies the later validation and save cases")
	await click(screen(WarData.point(helper)))
	check(main.game.selected == [int(helper.id)],"actual map click selects the helper as an intentionally wrong deployment actor")
	await open_medicines()
	check(medicine_card().deploy.disabled and medicine_card().condition.text.contains("存活红细胞"),"wrong selected unit clearly prevents deployment without consuming stock")
	await press(named_button(main.hud.menu_body,"返回游戏"))
	await click(screen(WarData.point(red)))
	await open_medicines()
	red.vesselLane = 1 # Explicit negative UI fixture: projected blood is not legal tissue.
	main.hud._process(.2); await frames()
	check(medicine_card().deploy.disabled and medicine_card().condition.text.contains("组织落点") and main.game.medicine_supply.count() == 1,"illegal blood-lane anchor has no deployment button and preserves stock")
	await capture_medicine("illegal-deployment-anchor")
	red.vesselLane = 0; main.hud._process(.2); await frames()
	await press(named_button(main.hud.menu_body,"返回游戏"))
	await press(main.hud.pause_button)
	check(main.game.paused,"actual pause control freezes pending medicine before saving")
	await open_medicines()
	await press(medicine_card().buy)
	if not check(queued("medicine_buy").size() == 1,"real third purchase is pending before save"): return
	var request: Dictionary = queued("medicine_buy")[0].request.duplicate(true)
	await open_saves()
	await press(named_button(save_row(),"保存"))
	check(FileAccess.file_exists(WarSave.path(1)),"physical save writes the isolated medicine inventory and pending request")
	await resume_commands()
	check(main.game.medicine_supply.count() == 2 and int(main.game.life.state().money) == 60,"saved pending purchase genuinely changes stock and money after resume")
	await open_medicines()
	check(medicine_card().buy.disabled and medicine_card().condition.text.contains("金钱不足"),"actual third purchase leaves sixty money and visibly disables unaffordable buying")
	var commands := queued("medicine_buy").size()
	await click(medicine_card().buy.get_global_rect().get_center())
	check(queued("medicine_buy").size() == commands and int(main.game.life.state().money) == 60,"physical click on disabled insufficient-money button cannot submit or spend")
	await capture_medicine("insufficient-money")
	await press(named_button(main.hud.menu_body,"返回游戏"))
	await press(main.hud.pause_button)
	await open_saves()
	await press(named_button(save_row(),"读取"))
	red = main.game.entity(int(red.id))
	await open_medicines()
	check(main.game.medicine_supply.count() == 1 and helpers().size() == 1 and int(main.game.life.state().money) == 140,"actual load restores the original wallet, stock and single active helper without replay")
	var restored: Dictionary = queued("medicine_buy")[0].request if queued("medicine_buy").size() == 1 else {}
	check(str(restored.get("runId","")) == str(request.runId) and int(restored.get("sequence",0)) == int(request.sequence),"saved pending purchase retains its original idempotent request")
	check(medicine_card().inventory.text.contains("库存 1") and main.hud.medicine_balance.text.contains("140") and main.hud.medicine_balance.text.contains("80"),"reopened player page displays restored inventory, reservation and money")
	await press(main.hud.medicine_pending_rows.values()[0])
	check(main.game.medicine_supply.count() == 1 and queued("medicine_buy").is_empty() and int(main.game.life.state().money) == 140,"restored pending request can be cancelled without consuming money or inventory")
	await capture_medicine("restored-medicine-supply")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(MED_OUT)
	WarSave.directory = "user://test-saves/medicine-ui-%d" % Time.get_ticks_usec()
	root.size = Vector2i(1440,900)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main); current_scene = main; main.set_process(false)
	await exercise()
	var mode := "headless" if DisplayServer.get_name() == "headless" else "native"
	var result := {"checks":checks,"failures":failures,"displayServer":DisplayServer.get_name(),"explicitServiceStaging":staged,"physicalWindowInput":true,"fixture":"new life original 300 money, zero medicine, original red moved by real commands; no injected medicine/money; one explicit blood-lane negative fixture restored before continuing; main process suspended, normal .15 updates execute actual commands","isolatedSaveDirectory":WarSave.directory}
	FileAccess.open(MED_OUT+"medicine-ui-"+mode+("-staging" if staged else "")+".json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("MEDICINE UI ",checks," checks, staging=",staged,", failures=",failures)
	main.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
