extends SceneTree
## Actual queued commands and WarSimulation.update; organ-local setup is explicit,
## not an opening-economy or end-to-end travel acceptance fixture.
var checks := 0
var failures: Array[String] = []
var points: Dictionary = {}
var events: Array = []
var evidence: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,label: String) -> void:
	checks += 1
	if not value: failures.append(label); printerr("FAIL ",label)

func advance(game: WarSimulation,seconds: float) -> void:
	for i in int(round(seconds/.1)): game.update(.1)

func fresh() -> WarSimulation:
	var game := WarSimulation.new(); game.start("life",73)
	game.state.entities.clear(); game.navigation.blockers.clear(); game.paused = false
	game.economy.add(1,"wood",500); game.economy.add(1,"food",500); game.economy.add(1,"oxygen",500)
	game.combat_event.connect(func(event): events.append(event))
	return game

func point(game: WarSimulation,id: String,kind := "worker") -> Vector2:
	var key := id+":"+kind
	if points.has(key): return points[key]
	for room in game.navigation.organs[id].rooms:
		var p := WarData.source_to_world(room.centerSource)
		if game.navigation.organ_at(p,kind)==id and game.navigation.point_allowed(p,0,kind): points[key] = p; return p
	var box: Array = game.navigation.organs[id].sourceBox
	for y in range(int(box[1]),int(box[3]),2):
		for x in range(int(box[0]),int(box[2]),2):
			var p := WarData.source_to_world([x,y])
			if game.navigation.organ_at(p,kind)==id and game.navigation.point_allowed(p,0,kind): points[key] = p; return p
	push_error("Missing tissue fixture: "+key)
	return Vector2.ZERO

func actor(game: WarSimulation,id: String,kind := "worker",category := "unit") -> Dictionary:
	var e := game.spawn(kind,1,point(game,id,kind),category)
	if not e.is_empty(): e.vesselLane = 0; game.order(e,{"kind":"hold"})
	return e

func issue(game: WarSimulation,action: String,e: Dictionary) -> void:
	game.submit_player({"action":"organ_action","organAction":action,"actor":e.id})

func count_events(kind: String,start := 0) -> int:
	var count := 0
	for i in range(start,events.size()):
		if events[i].kind==kind: count += 1
	return count

func run() -> void:
	var game := fresh()
	var red := actor(game,"liver")
	var wood := game.economy.stock(1,"wood"); var food := game.economy.stock(1,"food"); var oxygen := game.economy.stock(1,"oxygen")
	game.paused = true
	var preview: Array = game.organ_functions.available_actions(red.id)
	check(preview.any(func(q): return q.action=="liver_process" and q.ok),"paused menu can show a ready processing action")
	check(not game.organ_functions.quote("liver_process",red.id).ok and not game.organ_functions.request("liver_process",red.id).ok,"paused preview does not enable direct spending")
	issue(game,"liver_process",red); issue(game,"liver_process",red)
	advance(game,1)
	check(game.state.time==0 and game.state.commands.size()==2 and game.economy.stock(1,"wood")==wood and game.economy.stock(1,"food")==food,"paused duplicate commands queue without time or resource mutations")
	game.paused = false; advance(game,.1)
	check(game.state.commands.is_empty() and game.economy.stock(1,"wood")==wood+8 and game.economy.stock(1,"food")==food-20 and game.economy.stock(1,"oxygen")==oxygen-4,"resume executes one paid conversion and rejects duplicate by cooldown")
	check(count_events("organ_action")==1,"duplicate queued operation emits one successful action event")
	check(game.organ_functions.available_actions(red.id).any(func(q): return q.action=="liver_process" and not q.ok and q.cooldownRemaining>0),"menu exposes the actual post-execution cooldown")
	var before := JSON.stringify(game.state.factions)
	issue(game,"unknown_operation",red); advance(game,.1)
	check(JSON.stringify(game.state.factions)==before,"unknown queued operation is rejected without charging")
	red.vesselLane = 145; issue(game,"liver_store",red); advance(game,.1)
	check(game.organ_functions.faction_state(1).glycogen==0,"queued liver storage cannot activate through a projected vessel")
	red.vesselLane = 0; issue(game,"liver_store",red); advance(game,.1)
	check(game.organ_functions.faction_state(1).glycogen==20,"queued liver storage creates a real reserve")
	issue(game,"liver_release",red); advance(game,.1)
	check(game.organ_functions.faction_state(1).glycogen==0 and game.economy.stock(1,"food")==food-22,"queued release exchanges twenty stored glycogen for eighteen glucose")
	game.dispose()

	game = fresh(); red = actor(game,"pancreas")
	var barracks := actor(game,"liver","barracks","building")
	game.spawn("core",1,WarData.point(barracks)+Vector2(15,0),"building")
	issue(game,"pancreas_regulate",red); advance(game,.1)
	check(game.organ_functions.faction_state(1).pancreasUntil>game.state.time,"actual command activates pancreas regulation")
	# Keep only the discounted price: the old undiscounted affordability test
	# would reject this queue, so this checks real payment rather than a quote.
	game.state.factions[0].food = [{"amount":9.6,"born":game.state.time,"stomachGlucose":0.0}]
	wood = game.economy.stock(1,"wood")
	game.submit_player({"action":"train","target":barracks.id,"unit":"spear"}); advance(game,.1)
	check(barracks.queue.size()==1 and is_zero_approx(game.economy.stock(1,"food")) and game.economy.stock(1,"wood")==wood-15,"queued training can afford and spend only its actual discounted cost")
	check(not barracks.queue.is_empty() and is_equal_approx(float(barracks.queue[0].cost.food),9.6) and barracks.queue[0].cost.wood==15,"queue persists actual payment for cancellation and save")
	# The live HUD uses this existing cancellation API; retain its integer
	# rounding and ensure repeated activation cannot refund a removed item.
	game.economy.cancel_production(barracks,0)
	check(game.economy.stock(1,"food")==7 and game.economy.stock(1,"wood")==wood-4,"cancellation refunds floor(actual cost times seventy-five percent)")
	before = JSON.stringify(game.state.factions)
	game.economy.cancel_production(barracks,0); advance(game,.1)
	check(barracks.queue.is_empty() and JSON.stringify(game.state.factions)==before,"removed queue item cannot be refunded a second time")
	game.spawn("house",1,WarData.point(barracks)+Vector2(-10,0),"building")
	game.state.factions[0].food = [{"amount":57.6,"born":game.state.time,"stomachGlucose":0.0}]
	for i in 6: game.submit_player({"action":"train","target":barracks.id,"unit":"spear"})
	advance(game,.1)
	check(barracks.queue.size()==6 and is_zero_approx(game.economy.stock(1,"food")),"six real discounted queues consume an exact fifty-seven-point-six budget despite repeated floating subtraction")
	game.state.factions[0].food = [{"amount":.123456789,"born":game.state.time,"stomachGlucose":0.0}]
	check(game.economy.stock(1,"food")==.123456789,"precision cleanup preserves genuinely fractional harvest stock")
	evidence.discount = {"foodPaid":9.6,"foodRefunded":7,"proteinPaid":15,"proteinRefunded":11}
	game.dispose()

	game = fresh()
	var lab := actor(game,"brain","lab","building")
	game.state.factions[0].tier = 2
	wood = game.economy.stock(1,"wood")
	game.submit_player({"action":"research","target":lab.id,"tech":"storage"}); advance(game,35.9)
	check(lab.queue.size()==1 and not game.state.factions[0].tech.get("storage",false) and is_equal_approx(float(lab.queue[0].remaining),.125),"actual brain research remains incomplete just before thirty-six seconds")
	advance(game,.1)
	check(lab.queue.is_empty() and game.state.factions[0].tech.get("storage",false) and game.economy.stock(1,"wood")==wood-40,"forty-five-second research completes at thirty-six seconds with its original payment")
	evidence.brainResearchSeconds = game.state.time
	game.dispose()

	game = fresh(); lab = actor(game,"liver","lab","building"); game.state.factions[0].tier = 2
	game.submit_player({"action":"research","target":lab.id,"tech":"storage"}); advance(game,36)
	check(lab.queue.size()==1 and is_equal_approx(float(lab.queue[0].remaining),9),"non-brain research keeps the original forty-five-second cadence")
	game.dispose()

	game = fresh(); lab = actor(game,"brain","lab","building")
	game.state.factions[0].tech.tier2 = true
	var white := actor(game,"liver","spear")
	var target := game.spawn("virus",0,WarData.point(white)+Vector2(4,0)); target.hp = 10000.0; target.maxHp = 10000.0; target.attackDamage = 0.0
	game.order(target,{"kind":"hold"}); game.order(white,{"kind":"attack","target":target.id})
	issue(game,"brain_command",lab); advance(game,.1)
	check(white.has("cellShot") and is_equal_approx(float(white.shotSpeed),1.15) and is_equal_approx(float(white.cellShot.releaseAt)-float(white.shotTime),.35/1.15),"brain command reaches actual combat windup and animation shotSpeed")
	advance(game,.1)
	check(is_equal_approx(float(white.cooldown),.885),"real attack cooldown advances once at the command's fifteen-percent rate")
	game.dispose()

	game = fresh(); white = actor(game,"kidney_l","spear")
	white.hp = 100.0; white.statuses = {"toxin":{},"fatigue":{}}; white.impurities = 9.0
	var event_start := events.size()
	advance(game,1.9)
	check(white.statuses.has("toxin") and white.statuses.has("fatigue") and is_equal_approx(float(white.kidneyProgress),1.9) and is_equal_approx(float(white.hp),98.1),"real kidney preparation lasts nineteen ticks while toxin still damages")
	advance(game,.1)
	check(not white.statuses.has("toxin") and not white.statuses.has("fatigue") and is_equal_approx(float(white.hp),98) and game.organ_functions.faction_state(1).waste==10,"twentieth tick clears configured states and deposits filtrate exactly once")
	advance(game,1)
	check(is_equal_approx(float(white.hp),99.1) and is_equal_approx(float(white.kidneyProgress),3) and game.organ_functions.faction_state(1).waste==10,"one-second recovery adds one-point-one HP without duplicate filtration")
	check(count_events("organ_purified",event_start)==1,"continuous recovery does not spam repeated purification events")
	game.paused = true; before = JSON.stringify(game.snapshot()); advance(game,2)
	check(JSON.stringify(game.snapshot())==before,"pause freezes actual kidney, organ resources and deadlines together")
	game.paused = false; white.vesselLane = 145; white.statuses.toxin = {}; advance(game,.1)
	check(white.kidneyProgress==0 and white.statuses.has("toxin") and is_equal_approx(float(white.hp),99),"kidney effects stop immediately on a blood-vessel layer")
	red = actor(game,"bladder"); wood = game.economy.stock(1,"wood"); oxygen = game.economy.stock(1,"oxygen")
	issue(game,"bladder_recycle",red); advance(game,.1)
	check(game.organ_functions.faction_state(1).waste==0 and game.economy.stock(1,"wood")==wood+2 and game.economy.stock(1,"oxygen")==oxygen-2,"queued bladder action consumes real kidney filtrate and oxygen")
	evidence.kidney = {"preparationSeconds":2,"hpAfterThreeSeconds":99.1,"filtrate":10,"purificationEvents":count_events("organ_purified",event_start)}
	game.dispose()

	game = fresh()
	var strong := actor(game,"heart","heavy"); strong.requiresHeart = true; strong.vesselLane = 145
	advance(game,.1)
	check(strong.requiresHeart and not game.scenarios.transfer(strong,"liver"),"heart bounding box cannot unlock a blood-lane strong cell")
	strong.vesselLane = 0; advance(game,.1)
	check(not strong.requiresHeart and game.scenarios.transfer(strong,"liver") and game.navigation.organ_at(WarData.point(strong),strong.kind)=="liver" and int(strong.vesselLane)==0,"real heart tissue enables original safe-placement transfer")
	barracks = actor(game,"liver","barracks","building"); game.spawn("core",1,WarData.point(barracks)+Vector2(15,0),"building")
	game.state.factions[0].tier = 3; barracks.vesselLane = 145
	food = game.economy.stock(1,"food"); game.submit_player({"action":"train","target":barracks.id,"unit":"heavy"}); advance(game,.1)
	check(barracks.queue.is_empty() and game.economy.stock(1,"food")==food,"actual strong-cell queue rejects projected liver production without payment")
	game.dispose()

	await save_round_trip()
	await local_depot()
	DirAccess.make_dir_recursive_absolute("res://test-output/organ-functions")
	evidence.checks = checks; evidence.failures = failures
	evidence.scope = "Real simulation/command integration with legal organ-local fixtures; not native HUD or full-map travel acceptance. Cancellation uses the existing live-HUD economy API."
	var file := FileAccess.open("res://test-output/organ-functions/integration.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence,"  ",true,true))
	print("ORGAN_INTEGRATION ",checks-failures.size(),"/",checks)
	quit(0 if failures.is_empty() else 1)

func save_round_trip() -> void:
	var previous_directory := WarSave.directory; WarSave.directory = "user://test-saves/organ-functions-integration"
	var game := fresh(); var red := actor(game,"liver"); var pancreas := actor(game,"pancreas"); var lab := actor(game,"brain","lab","building")
	var recovering := actor(game,"kidney_r","spear"); recovering.hp = 100.0; recovering.impurities = 9.0; recovering.statuses.toxin = {}
	game.state.factions[0].tech.tier2 = true
	game.paused = true; issue(game,"liver_store",red); issue(game,"pancreas_regulate",pancreas); issue(game,"brain_command",lab)
	var food := game.economy.stock(1,"food"); var oxygen := game.economy.stock(1,"oxygen")
	check(WarSave.write(game,0)==OK and WarSave.read_slot(game,0)==OK and game.state.commands.size()==3,"real local save retains three paused, unpaid organ commands")
	game.paused = false; var event_start := events.size(); advance(game,1)
	check(game.state.commands.is_empty() and game.organ_functions.faction_state(1).glycogen==20 and game.economy.stock(1,"food")==food-25 and game.economy.stock(1,"oxygen")==oxygen-13,"restored queued commands spend once after resume")
	check(WarSave.write(game,1)==OK,"active effects and partial kidney preparation write through normal save validation")
	var saved_time := float(game.state.time); var clock := game.organ_functions.faction_state(1).duplicate(true)
	advance(game,1.5)
	check(WarSave.read_slot(game,1)==OK,"normal local load restores the active organ run")
	recovering = game.entity(int(recovering.id))
	check(is_equal_approx(float(game.state.time),saved_time) and game.organ_functions.faction_state(1)==clock and is_equal_approx(float(recovering.kidneyProgress),1),"restore preserves reserve, effect/cooldown deadlines and one-second kidney progress")
	check(game.organ_functions.location_queries==0,"restore invalidates cached organ identities")
	food = game.economy.stock(1,"food"); oxygen = game.economy.stock(1,"oxygen"); advance(game,1)
	check(game.organ_functions.faction_state(1).waste==10 and not recovering.statuses.has("toxin") and game.economy.stock(1,"food")==food and game.economy.stock(1,"oxygen")==oxygen,"restored preparation completes without replaying paid commands")
	check(count_events("organ_action",event_start)==3,"save/load never replays already committed organ actions")
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(WarSave.path(1)))
	envelope.snapshot.organFunctions.factions[0].waste = 201
	var corrupt := FileAccess.open(WarSave.path(2),FileAccess.WRITE); corrupt.store_string(JSON.stringify(envelope)); corrupt.close()
	var before := JSON.stringify(game.snapshot())
	check(WarSave.read_slot(game,2)==ERR_FILE_CORRUPT and JSON.stringify(game.snapshot())==before,"actual corrupted reserve save is rejected before live-state replacement")
	var legacy := game.snapshot(); legacy.erase("organFunctions")
	check(WarSave.validate(legacy).is_empty(),"existing saves without new organ ledger still validate")
	game.dispose(); WarSave.directory = previous_directory

func local_depot() -> void:
	var game := WarSimulation.new(); game.start("life",73)
	var red: Dictionary = game.units().filter(func(e): return e.faction==1)[0]
	var origin := WarData.point(red); var grid := game.navigation.grid("small_intestine",WarNavigation.profile("worker"))
	var destination := Vector2(INF,INF)
	for i in 64:
		var p := origin+Vector2.from_angle(i*TAU/64)*4
		if game.navigation.organ_at(p,"worker")=="small_intestine" and game.navigation.point_allowed(p,0,"worker") and grid.component(p)!=grid.component(origin) and game.navigation.clear_segment(origin,p,0,"worker"):
			destination = p; break
	check(is_finite(destination.x),"authored spawn has a directly reachable neighboring component for depot regression")
	if is_finite(destination.x):
		var depot := game.spawn("store",1,destination,"building"); depot.vesselLane = 0
		check(game.economy._delivery_point(red).distance_to(destination)<.001,"exact direct tissue connection can select a local depot across coarse components")
		red.vesselLane = 145
		check(game.economy._delivery_point(red).distance_to(destination)>1,"blood-lane courier cannot use tissue-only local-depot shortcut")
		evidence.depot = {"origin":[origin.x,origin.y],"destination":[destination.x,destination.y],"components":[grid.component(origin),grid.component(destination)],"exactSegment":true}
	game.dispose()
