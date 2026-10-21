extends SceneTree
var checks := 0
var failures: Array[String] = []
var points: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,label: String) -> void:
	checks += 1
	if not value: failures.append(label); printerr("FAIL ",label)

func inside(game: WarSimulation,id: String,kind := "worker") -> Vector2:
	var key := id+":"+kind
	if points.has(key): return points[key]
	for room in game.navigation.organs[id].rooms:
		var p := WarData.source_to_world(room.centerSource)
		if game.navigation.organ_at(p,kind) == id and game.navigation.point_allowed(p,0,kind): points[key] = p; return p
	var box: Array = game.navigation.organs[id].sourceBox
	for y in range(int(box[1]),int(box[3]),2):
		for x in range(int(box[0]),int(box[2]),2):
			var p := WarData.source_to_world([x,y])
			if game.navigation.organ_at(p,kind) == id and game.navigation.point_allowed(p,0,kind): points[key] = p; return p
	push_error("No real tissue fixture for "+key)
	return Vector2.ZERO

func move_to(e: Dictionary,p: Vector2) -> void:
	e.x = p.x; e.y = p.y; e.previousX = p.x; e.previousY = p.y; e.travelSpeed = 0.0
	e.vesselLane = 0; e.orders = []

func run() -> void:
	var game := WarSimulation.new(); game.start("fullbody"); game.paused = false
	game.state.entities.clear(); game.navigation.blockers.clear()
	for f in game.state.factions:
		f.stock = {"wood":1000.0,"oxygen":1000.0}; f.food = [{"amount":1000.0,"born":0.0,"stomachGlucose":1000.0}]
	var service := game.organ_functions
	var events: Array = []
	var receive := func(event):
		if str(event.kind).begins_with("organ_"): events.append(event)
	game.combat_event.connect(receive)
	check(service.enabled() and WarOrganFunctions.data().organs.size()==12,"all twelve authored organ identities are documented")
	for id in game.navigation.organs:
		var sample := game.spawn("worker",1,inside(game,id))
		check(service.organ(sample)==id,"exact authored tissue detected: "+id)
		game.state.entities.erase(str(sample.id))
	var worker := game.spawn("worker",1,inside(game,"liver"))
	service.reset_cache()
	for i in 100: service.organ(worker)
	check(service.location_queries==1,"one hundred stationary queries reuse one location lookup")
	worker.vesselLane = 1
	check(service.organ(worker)=="" and not service.request("liver_process",worker.id).ok,"projected blood-vessel overlap cannot activate liver functions")
	worker.vesselLane = 0
	game.order(worker,{"kind":"move","x":worker.x+2,"y":worker.y})
	check(not service.request("liver_process",worker.id).ok,"moving worker cannot process nutrients")
	game.order(worker,{"kind":"hold"})
	var stock_before := game.economy.stock(1,"wood")
	var glucose_before := game.economy.stock(1,"food")
	var oxygen_before := game.economy.stock(1,"oxygen")
	check(service.request("liver_process",worker.id).ok,"explicit liver processing action succeeds")
	check(is_equal_approx(game.economy.stock(1,"wood")-stock_before,8) and is_equal_approx(glucose_before-game.economy.stock(1,"food"),20) and is_equal_approx(oxygen_before-game.economy.stock(1,"oxygen"),4),"processing really spends glucose/oxygen and produces protein")
	var unchanged := JSON.stringify(game.state.factions)
	check(not service.request("liver_process",worker.id).ok and JSON.stringify(game.state.factions)==unchanged,"same-faction cooldown blocks repeated payment and gain")
	var other := game.spawn("worker",2,inside(game,"liver")+Vector2(1,0))
	check(not service.request("liver_process",other.id).ok,"player cannot spend an enemy faction's stock")
	game.state.time += 15
	game.state.factions[0].stock.oxygen = 0.0
	unchanged = JSON.stringify(game.state.factions)
	check(not service.request("liver_process",worker.id).ok and JSON.stringify(game.state.factions)==unchanged,"insufficient oxygen rejects action atomically")
	game.state.factions[0].stock.oxygen = 1000.0
	check(service.request("liver_store",worker.id).ok and service.faction_state(1).glycogen==20,"explicit storage creates bounded glycogen")
	for i in 5:
		game.state.time += 10
		service.request("liver_store",worker.id)
	check(service.faction_state(1).glycogen==120,"six deposits reach the configured glycogen capacity")
	game.state.time += 10; unchanged = JSON.stringify(game.state.factions)
	check(not service.request("liver_store",worker.id).ok and JSON.stringify(game.state.factions)==unchanged,"full reserve does not silently consume another batch")
	var stomach_before := game.economy.stomach_glucose(1)
	glucose_before = game.economy.stock(1,"food")
	check(service.request("liver_release",worker.id).ok,"explicit reserve withdrawal succeeds")
	check(service.faction_state(1).glycogen==100 and is_equal_approx(game.economy.stock(1,"food")-glucose_before,18) and game.economy.stomach_glucose(1)==stomach_before,"withdrawal loses two units and cannot forge stomach-only glucose")
	var fstate := JSON.stringify(service.state())
	var treasury := JSON.stringify(game.state.factions)
	game.paused = true; game.update(1)
	check(not service.request("liver_process",worker.id).ok and JSON.stringify(service.state())==fstate and JSON.stringify(game.state.factions)==treasury,"paused time neither advances cooldown nor spends resources")
	game.paused = false
	move_to(worker,inside(game,"brain"))
	check(not service.request("brain_command",worker.id).ok,"brain command requires the real tier-two research")
	game.state.factions[0].tech.tier2 = true; game.state.factions[0].tier = 2
	check(service.request("brain_command",worker.id).ok,"researched faction can explicitly issue a brain command")
	var ally := game.spawn("spear",1,inside(game,"liver"))
	var enemy := game.spawn("spear",2,inside(game,"liver"))
	check(is_equal_approx(service.multiplier(ally,"attackSpeedMultiplier"),1.15),"active command grants a fifteen-percent faction-wide attack cadence bonus")
	check(service.multiplier(enemy,"attackSpeedMultiplier")==1 and service.multiplier(worker,"attackSpeedMultiplier")==1 and service.multiplier(ally,"attackMultiplier")==1,"command does not affect enemies, workers or per-hit damage")
	check(not service.request("brain_command",worker.id).ok,"multiple actors cannot stack or refresh the command during its cooldown")
	game.state.time += 20
	check(service.multiplier(ally,"attackSpeedMultiplier")==1,"command expires after its configured twenty seconds")
	var lab := game.spawn("lab",1,inside(game,"brain"),"building")
	check(is_equal_approx(service.production_rate(lab,{"tech":"storage"}),1.25) and service.production_rate(lab,{"unit":"spear"})==1,"brain accelerates research queues rather than unrelated training")
	lab.vesselLane = 1
	check(service.production_rate(lab,{"tech":"storage"})==1,"brain research speed never leaks through a projected vessel")
	lab.vesselLane = 0; lab.complete = false
	check(service.production_rate(lab,{"tech":"storage"})==1,"unfinished lab cannot grant research speed")
	lab.complete = true
	var protein_before := game.economy.stock(1,"wood")
	check(game.economy.research(lab,"storage") and protein_before-game.economy.stock(1,"wood")==40,"brain reuses an actual paid existing research queue")
	check(is_equal_approx(float(lab.queue[0].remaining)/service.production_rate(lab,lab.queue[0]),36),"forty-five-second research has a thirty-six-second organ rate budget")
	move_to(worker,inside(game,"pancreas"))
	check(service.request("pancreas_regulate",worker.id).ok,"pancreas regulation is an explicit paid action")
	var barracks := game.spawn("barracks",1,inside(game,"liver"),"building")
	var discounted := service.training_cost(barracks,"spear")
	check(is_equal_approx(float(discounted.food),9.6) and discounted.wood==15,"regulation reduces only new training glucose by twenty percent")
	glucose_before = game.economy.stock(1,"food")
	check(game.economy.pay(1,discounted) and is_equal_approx(glucose_before-game.economy.stock(1,"food"),9.6),"quoted training cost can pay the exact reduced glucose amount")
	check(lab.queue[0].cost.wood==40,"activation does not retrospectively refund an existing queue")
	barracks.vesselLane = 1
	check(service.training_cost(barracks,"spear").food==12,"production in a projected vessel receives no tissue discount")
	barracks.vesselLane = 0
	game.state.time += 90
	check(service.training_cost(barracks,"spear").food==12 and not service.request("pancreas_regulate",worker.id).ok,"efficiency expires before its longer cooldown permits reuse")
	move_to(ally,inside(game,"kidney_l","spear"))
	ally.maxHp = 150.0; ally.hp = 100.0; ally.impurities = 9.0
	ally.statuses = {"toxin":{},"fatigue":{},"slow":{"duration":10}}
	service.update_unit(ally,1.9)
	check(ally.statuses.has("toxin") and ally.statuses.has("fatigue") and ally.hp==100,"kidney retains the original two-second preparation")
	service.update_unit(ally,.1)
	check(not ally.statuses.has("toxin") and not ally.statuses.has("fatigue") and ally.statuses.has("slow") and ally.impurities==0,"kidney clears only configured toxins/fatigue and impurities")
	check(service.faction_state(1).waste==10,"filtered impurities and one toxin clearance enter the bladder ledger")
	service.update_unit(ally,.5)
	check(is_equal_approx(float(ally.hp),100.55),"post-preparation recovery preserves original one-point-one HP per second")
	var hp_before := float(ally.hp); var progress := float(ally.kidneyProgress)
	game.paused = true; service.update_unit(ally,10)
	check(ally.hp==hp_before and ally.kidneyProgress==progress,"pause cannot progress passive recovery")
	game.paused = false; ally.vesselLane = 1; ally.statuses.toxin = {}
	service.update_unit(ally,10)
	check(ally.hp==hp_before and ally.kidneyProgress==0 and ally.statuses.has("toxin"),"blood lane over a kidney neither heals nor purifies and resets preparation")
	ally.vesselLane = 0; ally.statuses = {"fatigue":{}}; ally.impurities = 2; ally.kidneyProgress = 0.0
	var legacy_hp := float(ally.hp)
	for i in 8:
		service.update_unit(ally,.5)
	check(is_equal_approx(float(ally.hp),legacy_hp+2.2) and ally.impurities==0 and ally.statuses.is_empty(),"extracted kidney kernel matches the frozen four-second recovery result")
	move_to(ally,inside(game,"kidney_r","spear")); ally.kidneyProgress = 0.0; ally.statuses.toxin = {}; ally.impurities = 300
	service.update_unit(ally,2)
	check(service.faction_state(1).waste==200,"filtrate ledger caps safely and discards overflow")
	move_to(worker,inside(game,"bladder")); service.faction_state(1).waste = 10
	protein_before = game.economy.stock(1,"wood"); oxygen_before = game.economy.stock(1,"oxygen")
	check(service.request("bladder_recycle",worker.id).ok,"worker can explicitly recycle filtered waste in bladder tissue")
	check(service.faction_state(1).waste==0 and game.economy.stock(1,"wood")-protein_before==2 and oxygen_before-game.economy.stock(1,"oxygen")==2,"recycling consumes ten waste and two oxygen for two protein")
	game.state.time += 15; unchanged = JSON.stringify(game.state.factions)
	check(not service.request("bladder_recycle",worker.id).ok and JSON.stringify(game.state.factions)==unchanged,"empty filtrate ledger cannot produce free resources")
	game.state.factions[0].tier = 3
	game.spawn("core",1,WarData.point(barracks)+Vector2(20,0),"building")
	check(service.strong_training_allowed(barracks,"heavy") and game.economy.train(barracks,"heavy"),"liver gate reuses actual paid strong-cell training")
	game.economy.update(float(WarData.spec("heavy").train))
	var trained: Array = game.units().filter(func(e): return e.kind=="heavy" and e.faction==1)
	check(trained.size()==1 and trained[0].get("requiresHeart",false),"real production retains the required heart-transfer flag")
	var strong := game.spawn("heavy",1,inside(game,"liver","heavy")); strong.requiresHeart = true
	service.update_unit(strong,.1)
	check(strong.requiresHeart and service.strong_training_allowed(barracks,"heavy"),"existing liver cultivation preserves the heart-transfer requirement")
	barracks.vesselLane = 1
	check(not service.strong_training_allowed(barracks,"heavy"),"strong-cell cultivation rejects a vessel projected over the liver")
	barracks.vesselLane = 0
	move_to(strong,inside(game,"heart","heavy")); strong.vesselLane = 1
	service.update_unit(strong,.1)
	check(strong.requiresHeart and not service.can_transfer(strong,"liver"),"projected heart vessel does not activate transfer or clear its requirement")
	strong.vesselLane = 0; service.update_unit(strong,.1)
	check(not strong.requiresHeart and service.can_transfer(strong,"liver") and not service.can_transfer(strong,"pancreas"),"actual heart tissue enables the existing allowed transfer destinations")
	check(service.available_actions(worker.id).size()==1,"bladder UI action discovery exposes the local recycle command")
	var snapshot := game.snapshot()
	check(WarOrganFunctions.validate_state(snapshot).is_empty() and WarSave.validate(snapshot).is_empty(),"organ ledger fits the current save envelope")
	var serialized: Dictionary = JSON.parse_string(JSON.stringify(snapshot))
	game.restore(serialized); game.paused = false; service.reset_cache()
	check(service.faction_state(1).glycogen==100 and service.faction_state(1).waste==0 and service.faction_state(1).cooldowns.has("bladder_recycle"),"JSON save round trip retains reserves and cooldown deadlines")
	game.state.time += (6 if game.state.factions[0].tech.get("storage",false) else 3)*360+1; game.economy.update(0)
	check(game.economy.stock(1,"food")==0 and service.faction_state(1).glycogen==100,"reserved glycogen survives the original food-spoilage clock")
	var previous_directory := WarSave.directory
	WarSave.directory = "user://test-saves/organ-functions"
	check(WarSave.write(game,0)==OK,"real local save writes an organ ledger without external dependencies")
	service.faction_state(1).glycogen = 0
	check(WarSave.read_slot(game,0)==OK,"real local save can be loaded")
	service.reset_cache()
	check(service.faction_state(1).glycogen==100 and service.faction_state(1).cooldowns.has("bladder_recycle"),"actual disk round trip restores the protected reserve and action deadlines")
	WarSave.directory = previous_directory
	var invalid := snapshot.duplicate(true); invalid.organFunctions.factions[0].glycogen = -1
	check(not WarOrganFunctions.validate_state(invalid).is_empty(),"negative glycogen is rejected")
	invalid = snapshot.duplicate(true); invalid.organFunctions.factions[0].waste = 201
	check(not WarOrganFunctions.validate_state(invalid).is_empty(),"waste beyond capacity is rejected")
	invalid = snapshot.duplicate(true); invalid.organFunctions.factions[0].cooldowns.fake = 1
	check(not WarOrganFunctions.validate_state(invalid).is_empty(),"unknown action cooldown is rejected")
	invalid = snapshot.duplicate(true); invalid.organFunctions.factions[0].pancreasUntil = NAN
	check(not WarOrganFunctions.validate_state(invalid).is_empty(),"nonfinite effect deadline is rejected")
	invalid = snapshot.duplicate(true); invalid.entities[str(ally.id)].kidneyProgress = -1
	check(not WarOrganFunctions.validate_state(invalid).is_empty(),"negative kidney preparation is rejected")
	invalid = snapshot.duplicate(true); invalid.entities[str(ally.id)].impurities = INF
	check(not WarOrganFunctions.validate_state(invalid).is_empty(),"nonfinite impurities are rejected before recovery can consume them")
	invalid = snapshot.duplicate(true); invalid.entities = []
	check(not WarOrganFunctions.validate_state(invalid).is_empty(),"malformed entity collections fail validation without throwing")
	invalid = snapshot.duplicate(true); invalid.erase("organFunctions")
	check(WarOrganFunctions.validate_state(invalid).is_empty(),"older saves without organ state remain supported")
	check(events.any(func(e): return e.kind=="organ_action") and events.any(func(e): return e.kind=="organ_purified"),"paid actions and purification emit structured simulation events")
	game.combat_event.disconnect(receive)
	game.mode = "sandbox"
	check(not service.enabled(),"classic sandbox biomes do not silently activate authored body functions")
	game.dispose()
	DirAccess.make_dir_recursive_absolute("res://test-output/organ-functions")
	var report := FileAccess.open("res://test-output/organ-functions/checks.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"events":events.size(),"boundary":"Service contracts; actual queued simulation is checked separately in organ_functions_integration.gd."},"  "))
	print("ORGAN_FUNCTIONS ",checks-failures.size(),"/",checks)
	quit(0 if failures.is_empty() else 1)
