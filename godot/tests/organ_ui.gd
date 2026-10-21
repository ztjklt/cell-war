extends "res://tests/opening_flow.gd"
## UI fixtures supply legal tissue positions, researched tech and resources.
## Genuine unmodified-start coverage belongs to opening_flow.gd.
const ORGAN_OUT := "res://test-output/organ-ui/"

func tissue(organ: String,kind := "worker") -> Vector2:
	for room in main.game.navigation.organs[organ].rooms:
		var point := WarData.source_to_world(room.centerSource)
		if main.game.navigation.organ_at(point,kind) == organ and main.game.navigation.point_allowed(point,0,kind): return point
	var box: Array = main.game.navigation.organs[organ].sourceBox
	for y in range(int(box[1]),int(box[3]),2):
		for x in range(int(box[0]),int(box[2]),2):
			var point := WarData.source_to_world([x,y])
			if main.game.navigation.organ_at(point,kind) == organ and main.game.navigation.point_allowed(point,0,kind): return point
	return Vector2.ZERO

func bank(wood: float,oxygen: float,food: float) -> void:
	var faction: Dictionary = main.game.state.factions[0]
	faction.stock.wood = wood; faction.stock.oxygen = oxygen
	faction.food = [{"amount":food,"born":main.game.state.time,"stomachGlucose":food}]

func fixture(organ: String,kind := "worker") -> Dictionary:
	if main.hud.menu.visible: main.hud.close_menu()
	main.start("life"); main.game.paused = false
	var point := tissue(organ,kind)
	var actor: Dictionary
	if kind == "worker":
		actor = main.game.units().filter(func(e): return e.faction == 1)[0]
		actor.x = point.x; actor.y = point.y; actor.previousX = point.x; actor.previousY = point.y
		actor.orders.clear(); actor.vesselLane = 0; actor.travelSpeed = 0
	else:
		actor = main.game.spawn(kind,1,point,"building")
		actor.complete = true; actor.progress = 1; actor.hp = actor.maxHp
	main.game.organ_functions.reset_cache()
	main.focus(main.world.display_point(point),18)
	await frames(12)
	await click(screen(point))
	check(main.game.selected == [int(actor.id)],"physical map click selects the legal "+organ+" actor")
	return actor

func organ_entry(action: String) -> Dictionary:
	for entry in main.hud.organ_buttons:
		if entry.action == action: return entry
	return {}

func open_organ() -> void:
	await create_timer(.2).timeout
	await press(main.hud.organ_button)
	check(main.hud.menu.visible and main.game.paused,"actual selection-panel button opens the paused organ menu")

func resume() -> void:
	await press(named_button(main.hud.menu_body,"返回游戏"))
	check(not main.game.paused,"return button restores the running state")
	main.game.update(.15); await frames()

func capture_organ(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ORGAN_OUT+name+".png")

func menu_copy() -> String:
	var text := ""
	for node in main.hud.menu_body.find_children("*","Label",true,false): text += node.text+"\n"
	return text

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ORGAN_OUT)
	WarSave.directory = "user://test-saves/organ-ui-%d" % Time.get_ticks_usec()
	root.size = Vector2i(1440,900)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main); current_scene = main
	main.set_process(false)
	var actor := await fixture("liver")
	bank(100,4,40)
	await open_organ()
	check(main.hud.organ_buttons.size() == 3,"liver lists its three data-defined local actions")
	check(menu_copy().contains("葡萄糖 20") and menu_copy().contains("氧气 4") and menu_copy().contains("蛋白质 8"),"liver menu shows structured actual cost and gain")
	var process := organ_entry("liver_process")
	await press(process.button)
	check(main.game.state.commands.size() == 1 and main.game.state.commands[0].action == "organ_action" and int(main.game.state.commands[0].actor) == int(actor.id),"paused physical organ button submits the real actor command")
	check(is_equal_approx(main.game.economy.stock(1,"food"),40) and is_equal_approx(main.game.economy.stock(1,"oxygen"),4),"organ menu never spends before simulation resumes")
	check(process.button.disabled and process.condition.text.contains("已排队"),"duplicate queued organ operation is visibly blocked")
	var store := organ_entry("liver_store")
	check(store.button.disabled and store.condition.text.contains("预留"),"other pending organ cost reserves the shared oxygen budget")
	check(organ_entry("liver_release").button.disabled,"insufficient glycogen has no spendable release button")
	await capture_organ("liver-pending")
	await resume()
	check(is_equal_approx(main.game.economy.stock(1,"wood"),108) and is_equal_approx(main.game.economy.stock(1,"food"),20) and is_equal_approx(main.game.economy.stock(1,"oxygen"),0),"resumed normal organ command pays once and produces the real eight protein")
	await open_organ()
	process = organ_entry("liver_process")
	check(process.button.disabled and process.condition.text.contains("冷却") and process.condition.text.contains("剩余"),"real post-action cooldown and remaining seconds are visible")
	await capture_organ("liver-cooldown")

	actor = await fixture("liver"); bank(100,2,40)
	await open_organ()
	await press(organ_entry("liver_store").button)
	await resume()
	check(is_equal_approx(main.game.organ_functions.faction_state(1).glycogen,20),"actual storage button creates the glycogen reserve on resume")
	await open_organ()
	check(main.hud.organ_reserves.text.contains("糖原储备 20 / 120"),"current glycogen and capacity are shown")
	await press(organ_entry("liver_release").button)
	await resume()
	check(is_equal_approx(main.game.organ_functions.faction_state(1).glycogen,0) and is_equal_approx(main.game.economy.stock(1,"food"),38),"actual release button converts twenty glycogen to eighteen glucose")

	actor = await fixture("brain","lab"); bank(100,10,100)
	await open_organ()
	var command := organ_entry("brain_command")
	check(command.button.disabled and command.condition.text.contains("稳定生产研究"),"brain lab explains the actual missing research prerequisite")
	main.game.state.factions[0].tech.tier2 = true; main.game.state.factions[0].tier = 2
	main.hud._process(.2); await frames()
	check(not command.button.disabled and menu_copy().contains("攻速 +15% · 20 秒"),"researched brain lab offers the data-defined command and duration")
	await press(command.button)
	await capture_organ("brain-command-pending")
	await resume()
	check(is_equal_approx(main.game.economy.stock(1,"oxygen"),2) and float(main.game.organ_functions.faction_state(1).commandUntil) > main.game.state.time,"actual brain command consumes oxygen and starts the real faction effect")

	actor = await fixture("pancreas"); bank(100,10,100)
	await open_organ()
	await press(organ_entry("pancreas_regulate").button)
	await resume()
	check(is_equal_approx(main.game.economy.stock(1,"food"),95) and is_equal_approx(main.game.economy.stock(1,"oxygen"),6),"actual pancreatic control pays its listed initial cost")
	var core: Dictionary = main.game.spawn("core",1,tissue("liver"),"building")
	core.complete = true; core.progress = 1; core.hp = core.maxHp
	var barracks: Dictionary = main.game.spawn("barracks",1,tissue("pancreas","barracks"),"building")
	barracks.complete = true; barracks.progress = 1; barracks.hp = barracks.maxHp
	bank(100,6,9.6)
	await click(screen(WarData.point(barracks)+Vector2(1,0)))
	check(main.game.selected == [int(barracks.id)],"physical building edge click selects the pancreas production fixture")
	await press(named_button(main.hud.root,"≡"))
	await press(named_button(main.hud.menu_body,"建设与生产"))
	var train: Button
	for entry in main.hud.production_buttons:
		if entry.kind == "spear": train = entry.button; break
	check(train != null and train.text.contains("9.6"),"training menu shows the actual discounted 9.6 glucose without integer truncation")
	await press(train)
	await press(train)
	check(main.game.state.commands.size() == 1 and main.hud.production_feedback.text.contains("预留"),"discounted training budget blocks oversubscribing its exact fractional stock")
	await resume()
	check(barracks.queue.size() == 1 and is_equal_approx(barracks.queue[0].cost.food,9.6) and is_zero_approx(main.game.economy.stock(1,"food")),"resuming actual discounted training pays exactly the cost shown by the HUD")
	await capture_organ("pancreas-discounted-training")

	actor = await fixture("bladder"); bank(100,2,0)
	await open_organ()
	var recycle := organ_entry("bladder_recycle")
	check(recycle.button.disabled and recycle.condition.text.contains("杂质储备不足"),"recycling explains the missing purified-waste prerequisite")
	main.game.organ_functions.faction_state(1).waste = 10
	main.hud._process(.2); await frames()
	check(main.hud.organ_reserves.text.contains("净化杂质 10 / 200") and not recycle.button.disabled,"actual waste reserve unlocks its displayed recycling cost")
	await press(recycle.button)
	await capture_organ("bladder-recycle-pending")
	await resume()
	check(is_equal_approx(main.game.economy.stock(1,"wood"),102) and is_zero_approx(main.game.economy.stock(1,"oxygen")) and is_zero_approx(main.game.organ_functions.faction_state(1).waste),"normal recycling command consumes ten waste/two oxygen and returns two protein")
	await press(named_button(main.hud.root,"≡"))
	await press(named_button(main.hud.menu_body,"指挥手册"))
	await press(named_button(main.hud.menu_body,"器官分工与补给"))
	var headings := 0
	for node in main.hud.menu_body.get_children():
		if node is Label:
			for organ in WarOrganFunctions.data().organs.values():
				if node.text.begins_with(str(organ.name)+" · "): headings += 1
	check(headings == 12 and menu_copy().contains("必须由红细胞采集并运输入库"),"existing handbook exposes all twelve organ roles and explicit physical transport")
	await capture_organ("organ-handbook")
	await press(named_button(main.hud.menu_body,"返回游戏"))
	await click(screen(WarData.point(actor)+Vector2(2,0)),MOUSE_BUTTON_RIGHT)
	await create_timer(.35).timeout
	var organ_menu: Button
	for button in main.hud.wheel.buttons:
		if button.action == "organ_menu": organ_menu = button; break
	check(organ_menu != null,"local red cell also exposes organ collaboration in the real command wheel")
	await capture_organ("organ-command-wheel")
	await press(organ_menu)
	check(main.hud.menu.visible and not main.hud.wheel.visible and main.game.state.commands.is_empty(),"actual organ wheel badge opens existing menu without issuing a spending command")
	var output := {"checks":checks,"failures":failures,"displayServer":DisplayServer.get_name(),"physicalWindowInput":true,"fixture":"independent organ HUD fixtures supply legal actor tissue positions, selected local lab/core/barracks, technology and bounded funds/reserves; camera/scroll exposure driven by test; all spending occurs only via submitted commands and actual simulation","isolatedSaveDirectory":WarSave.directory}
	var mode := "headless" if DisplayServer.get_name() == "headless" else "native"
	FileAccess.open(ORGAN_OUT+"organ-ui-"+mode+".json",FileAccess.WRITE).store_string(JSON.stringify(output,"  "))
	print("ORGAN UI ",checks," checks, failures=",failures)
	main.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
