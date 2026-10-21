extends SceneTree
## Original seed73 red, real submitted moves and full fixed-step simulation.
## Only the life director is removed for route/economy isolation; never move
## actors by assignment, manufacture resources or add navigation connections.
const OUT := "res://test-output/organ-access/"
const TARGETS := ["liver","kidney_l","kidney_r","brain","pancreas","bladder","heart"]
var checks := 0
var failures: Array[String] = []
var report := {"seed":73,"routes":[],"economy":{},"scope":"original red and resources; real submit_player/update; lifeRun removed only for isolated route and economy branches"}

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,label: String) -> bool:
	checks += 1
	if not value: failures.append(label); printerr("FAIL ",label)
	return value

func fresh(isolate := true) -> WarSimulation:
	var game := WarSimulation.new(); game.start("life",73)
	if isolate: game.state.erase("lifeRun")
	return game

func red_cell(game: WarSimulation) -> Dictionary:
	return game.units().filter(func(e): return e.kind == "worker" and int(e.faction) == 1)[0]

func frame(game: WarSimulation) -> void:
	game.navigation.update(20000)
	game.update(.1)

func point_record(game: WarSimulation,red: Dictionary) -> Dictionary:
	return {"time":game.state.time,"point":[red.x,red.y],"lane":int(red.get("vesselLane",0)),
		"organ":game.organ_functions.organ(red),"pathIndex":red.pathIndex,"pathSize":red.path.size(),
		"pathFailed":red.pathFailed,"pathPending":red.pathPending,"request":red.get("request",0)}

func stocks(game: WarSimulation) -> Dictionary:
	return {"wood":game.economy.stock(1,"wood"),"food":game.economy.stock(1,"food"),"oxygen":game.economy.stock(1,"oxygen")}

func write_json(name: String,value: Dictionary) -> void:
	var file := FileAccess.open(OUT+name+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(value,"  ",true,true))

func add_candidate(game: WarSimulation,organ: String,list: Array,p: Vector2,label: String) -> void:
	if game.navigation.organ_at(p,"worker") != organ or not game.navigation.point_allowed(p,0,"worker"): return
	for item in list:
		if WarData.point(item.point).distance_to(p) < .1: return
	list.append({"point":[p.x,p.y],"label":label})

func candidates(game: WarSimulation,organ: String,origin: Vector2) -> Array:
	var list: Array = []
	for gate in game.navigation.organs[organ].gateContracts[WarNavigation.profile("worker")]:
		var p := WarData.source_to_world(gate.tissueAnchorSource)
		add_candidate(game,organ,list,p,gate.id+":tissue")
	for room in game.navigation.organs[organ].rooms:
		add_candidate(game,organ,list,WarData.point(room.rallyWorld),str(room.id)+":rally")
		add_candidate(game,organ,list,WarData.source_to_world(room.centerSource),str(room.id)+":center")
	list.sort_custom(func(a,b): return origin.distance_squared_to(WarData.point(a.point)) < origin.distance_squared_to(WarData.point(b.point)))
	return list

func probe(game: WarSimulation,red: Dictionary,target: Vector2) -> Dictionary:
	# Planning selects candidates; success is certified only by actual movement below.
	var receipt := {"done":false,"points":0,"reason":"timeout","length":0.0}
	var callback := func(_token,path,reason):
		receipt.done = true; receipt.points = path.size(); receipt.reason = reason
		for i in range(1,path.size()): receipt.length += path[i-1].p.distance_to(path[i].p)
	game.navigation.path_ready.connect(callback)
	var token := game.navigation.request(red,target,0)
	var began := Time.get_ticks_msec()
	while not receipt.done and Time.get_ticks_msec()-began < 15000: game.navigation.update(20000)
	game.navigation.cancel(token)
	game.navigation.path_ready.disconnect(callback)
	return receipt

func attempt_route(organ: String,candidate: Dictionary,index: int,probes: Array) -> Dictionary:
	var game := fresh(); var red := red_cell(game)
	var origin := WarData.point(red)
	var target := WarData.point(candidate.point)
	check(game.units().size() == 1 and int(red.id) == 25,"route starts with original single red: "+organ)
	check(origin.distance_to(Vector2(996.700932,1907.7375)) < .001 and int(red.vesselLane) == 0,"route starts at original position and layer: "+organ)
	var row := {"organ":organ,"candidate":candidate,"attempt":index,"original":[origin.x,origin.y],"redId":int(red.id),
		"probes":probes,"trace":[point_record(game,red)],"transitions":[],"pathEvents":[],"travelled":0.0,"maxStep":0.0,"arrived":false,"beforeStock":stocks(game)}
	var callback := func(token,path,reason):
		if row.pathEvents.size() < 20: row.pathEvents.append({"time":game.state.time,"token":token,"points":path.size(),"reason":reason})
	game.navigation.path_ready.connect(callback)
	game.submit_player({"action":"unit_order","unit":int(red.id),"order":{"kind":"move","x":target.x,"y":target.y,"lane":0}})
	var last := origin
	var last_lane := 0
	var last_motion := 0.0
	for i in 60000:
		frame(game)
		var p := WarData.point(red)
		var distance := p.distance_to(last)
		row.travelled += distance; row.maxStep = maxf(float(row.maxStep),distance)
		if distance > .000001: last_motion = float(game.state.time)
		last = p
		var lane := int(red.get("vesselLane",0))
		if lane != last_lane:
			var entry := point_record(game,red); entry.previousLane = last_lane
			row.transitions.append(entry); last_lane = lane
		if i%10 == 0: row.trace.append(point_record(game,red))
		if red.orders.is_empty() and lane == 0 and p.distance_to(target) <= .051 and game.navigation.organ_at(p,"worker") == organ:
			row.arrived = true; break
		if float(game.state.time)-last_motion > 35: break
		if i > 0 and i%3000 == 0: print("ORGAN ACCESS ",organ," t=",game.state.time," p=",p," lane=",lane," failed=",red.pathFailed)
	# Let the production tick clear travelSpeed before quoting an arrived actor.
	if row.arrived:
		for i in 2: frame(game)
	row.terminal = point_record(game,red); row.elapsed = game.state.time
	row.stock = stocks(game); row.actor = red.duplicate(true)
	row.availableActions = game.organ_functions.available_actions(int(red.id))
	row.quotePositionValid = game.organ_functions.organ(red) == organ and WarOrganFunctions.stationary(red)
	if organ == "heart": row.heartTransferEligible = game.organ_functions.can_transfer(red,"liver")
	if organ in ["kidney_l","kidney_r"]:
		row.kidney = {"organHook":red.get("organ",""),"hp":red.hp,"maxHp":red.maxHp,"progress":red.get("kidneyProgress",0),"note":"healthy original red has no toxin/impurities to cleanse; no artificial damage/status fixture"}
	if row.arrived:
		check(row.quotePositionValid,"actual arrived actor is stationary on intended organ tissue: "+organ)
		for quote in row.availableActions:
			check(quote.ok or quote.reason in ["需要先完成稳定生产研究","糖原或净化杂质储备不足","缺少氧气","缺少葡萄糖","缺少蛋白质"],"real quote is eligible or denied only by actual stock/tech/reserve: "+str(quote.action))
		if organ == "heart": check(row.heartTransferEligible,"original red really reaches heart transfer eligibility; transfer is not executed")
		if organ in ["kidney_l","kidney_r"]: check(row.kidney.organHook == organ,"real status loop sees the reached kidney: "+organ)
	check(float(row.maxStep) <= float(WarData.spec("worker").speed)*WarSimulation.STEP*WarBloodFlow.DOWNSTREAM+.005,"every movement tick respects existing speed and flow budget: "+organ)
	check(game.units().size() == 1 and game.state.influenzaColonies.groups.is_empty(),"isolated route adds no units or infection groups: "+organ)
	game.navigation.path_ready.disconnect(callback)
	write_json(organ+"-attempt-%d" % index,row)
	if not row.arrived: write_json(organ+"-blocked-snapshot-%d" % index,game.snapshot())
	print("ORGAN ACCESS RESULT ",organ," arrived=",row.arrived," time=",row.elapsed," point=",row.terminal.point," actions=",row.availableActions)
	game.dispose()
	return row

func organ_route(organ: String) -> void:
	var game := fresh(); var red := red_cell(game)
	var list := candidates(game,organ,WarData.point(red))
	check(not list.is_empty(),"authored legal operation candidates exist: "+organ)
	var probes: Array = []
	var choices: Array = []
	for candidate in list:
		var receipt := probe(game,red,WarData.point(candidate.point))
		probes.append({"candidate":candidate,"receipt":receipt})
		if int(receipt.points) > 0: choices.append(candidate)
	game.dispose()
	# A failed plan is not a geometric impossibility claim. Still issue a real
	# move to authored candidates so blocked reports contain retries and state.
	if choices.is_empty(): choices = list
	var attempts: Array = []
	var arrived := false
	for i in mini(3,choices.size()):
		var row := attempt_route(organ,choices[i],i,probes)
		attempts.append(row)
		if row.arrived: arrived = true; break
	check(arrived,"original seed73 red actually reaches at least one legal operation point: "+organ)
	report.routes.append({"organ":organ,"arrived":arrived,"attempts":attempts})
	write_json("progress",report)

func paid_build(game: WarSimulation,red: Dictionary,kind: String,site: Vector2) -> Dictionary:
	var began := float(game.state.time)
	var before := stocks(game)
	game.submit_player({"action":"place","building":kind,"x":site.x,"y":site.y,"ids":[int(red.id)]})
	var building: Dictionary = {}
	for i in 1500:
		frame(game)
		for e in game.entities():
			if e.category == "building" and e.kind == kind and int(e.faction) == 1 and WarData.point(e).distance_to(site) < .1: building = e; break
		if not building.is_empty() and building.complete: break
	var entry := {"kind":kind,"site":[site.x,site.y],"began":began,"ended":game.state.time,"elapsed":float(game.state.time)-began,
		"before":before,"after":stocks(game),"complete":not building.is_empty() and building.complete,"red":point_record(game,red),"building":building}
	if not entry.complete: write_json("bootstrap-build-blocked-"+kind,{"attempt":entry,"snapshot":game.snapshot()})
	return entry

func farm_site(game: WarSimulation,red: Dictionary) -> Dictionary:
	var origin := WarData.point(red)
	var list: Array = []
	for y in range(-24,25):
		for x in range(-24,25):
			var p := game.economy.build_point("farm",origin+Vector2(x,y))
			if p.distance_to(origin) < 3 or game.navigation.organ_at(p,"worker") != "small_intestine": continue
			if p.distance_to(WarData.point(game.state.resources["small_intestine.wood"])) < 4: continue
			if not game.economy.can_place("farm",p,[int(red.id)]): continue
			list.append(p)
	list.sort_custom(func(a,b): return origin.distance_squared_to(a) < origin.distance_squared_to(b))
	var inspected: Array = []
	for p: Vector2 in list:
		for i in 16:
			var approach := p+Vector2.from_angle((origin-p).angle()+i*TAU/16)*2.05
			if not game.navigation.point_allowed(approach,0,"worker") or not game.navigation.movement_clear(approach,approach,"worker",1): continue
			var receipt := probe(game,red,approach)
			inspected.append({"site":[p.x,p.y],"approach":[approach.x,approach.y],"receipt":receipt})
			if int(receipt.points) > 0:
				report.economy.farmSearch = {"legalSites":list.size(),"inspected":inspected}
				return {"site":p,"approach":approach}
	report.economy.farmSearch = {"legalSites":list.size(),"inspected":inspected}
	return {}

func economic_bootstrap() -> void:
	var game := fresh(); var red := red_cell(game)
	var result := {"scope":"normal paid construction and harvesting from the original single red and 160 protein/125 glucose/0 oxygen; only lifeRun removed",
		"initial":stocks(game),"original":[red.x,red.y],"builds":[],"proteinDeposits":[],"farmDeposits":[]}
	game.submit_player({"action":"unit_order","unit":int(red.id),"order":{"kind":"move","x":994.0,"y":1907.5,"lane":0}})
	for i in 80: frame(game)
	check(WarData.point(red).distance_to(Vector2(994,1907.5)) < .1,"bootstrap uses a real initial move out of the small birth patch")
	var store := paid_build(game,red,"store",Vector2(985,1906))
	result.builds.append(store)
	check(store.complete and is_equal_approx(float(store.before.wood)-float(store.after.wood),30),"bootstrap really builds the thirty-protein local depot")
	if not store.complete: report.economy.bootstrap = result; game.dispose(); return
	var source: Dictionary = game.state.resources["small_intestine.wood"]
	game.submit_player({"action":"unit_order","unit":int(red.id),"order":{"kind":"harvest","resource":source.id,"x":source.x,"y":source.y}})
	for i in 2400:
		var delivered := float(game.state.get("delivered",0))
		frame(game)
		if float(game.state.get("delivered",0)) > delivered:
			result.proteinDeposits.append({"time":game.state.time,"amount":float(game.state.delivered)-delivered,"stock":stocks(game),"red":point_record(game,red)})
		if result.proteinDeposits.size() >= 2: break
	check(result.proteinDeposits.size() == 2 and game.economy.stock(1,"wood") == 158,"two real local loads restore twenty-eight protein without a heart trip")
	var choice := farm_site(game,red)
	check(not choice.is_empty(),"a legal farm site has an actually planned approach near the local depot")
	if choice.is_empty(): report.economy.bootstrap = result; game.dispose(); return
	# Normal player pre-positioning; the original red still walks every metre.
	var approach: Vector2 = choice.approach
	game.submit_player({"action":"unit_order","unit":int(red.id),"order":{"kind":"move","x":approach.x,"y":approach.y,"lane":0}})
	for i in 2000:
		frame(game)
		if red.orders.is_empty(): break
	result.farmApproach = point_record(game,red)
	check(WarData.point(red).distance_to(approach) < .1,"original red really walks to the farm construction approach")
	var farm := paid_build(game,red,"farm",choice.site)
	result.builds.append(farm)
	check(farm.complete and is_equal_approx(float(farm.before.wood)-float(farm.after.wood),15),"normal construction buys and completes a fifteen-protein glucose source")
	if not farm.complete: report.economy.bootstrap = result; game.dispose(); return
	game.submit_player({"action":"unit_order","unit":int(red.id),"order":{"kind":"farm","target":int(farm.building.id)}})
	for i in 12000:
		var delivered := float(game.state.get("delivered",0))
		var food := game.economy.stock(1,"food")
		frame(game)
		if float(game.state.get("delivered",0)) > delivered:
			result.farmDeposits.append({"time":game.state.time,"amount":float(game.state.delivered)-delivered,"foodDelta":game.economy.stock(1,"food")-food,"stock":stocks(game),"red":point_record(game,red)})
		if float(game.state.time) >= 1101: break
	result.ended = game.state.time; result.finalStock = stocks(game)
	result.foodBatches = game.state.factions[0].food.duplicate(true)
	result.stomachGlucose = game.economy.stomach_glucose(1)
	result.red = red.duplicate(true)
	check(not result.farmDeposits.is_empty() and float(result.farmDeposits[0].time) < 180,"original red actually supplies new glucose before the first three-minute decision")
	check(result.foodBatches.all(func(batch): return float(batch.born) > 0) and game.economy.stock(1,"food") > 0,"normal local farming sustains real fresh glucose after the initial batch expires")
	check(result.stomachGlucose == 0,"farm glucose does not masquerade as the clinic's stomach-only glucose")
	check(game.units().size() == 1 and int(red.id) == 25 and game.economy.stock(1,"oxygen") == 0,"bootstrap uses no created red or oxygen grant")
	report.economy.bootstrap = result
	write_json("bootstrap",result)
	print("ORGAN ACCESS BOOTSTRAP first farm delivery=",result.farmDeposits[0].time if not result.farmDeposits.is_empty() else -1," final food=",result.finalStock.food," wood=",result.finalStock.wood)
	game.dispose()

func calendar_reference() -> void:
	var game := fresh(false); var red := red_cell(game)
	var threshold := float(game.life.state().riskThreshold)
	var before := stocks(game)
	var expired_at := -1.0
	for i in 60000:
		frame(game)
		if expired_at < 0 and game.economy.stock(1,"food") == 0: expired_at = game.state.time
		if int(game.life.state().outbreaks) > 0: break
	var life: Dictionary = game.life.state().duplicate(true)
	report.economy.calendar = {"scope":"untouched seed73, actual full simulation, original red holds, no choices or resource spending; stop at first natural outbreak",
		"before":before,"after":stocks(game),"initialFoodExpiredAt":expired_at,"life":life,"redHp":red.hp,"redPoint":[red.x,red.y],"thresholdWasForced":false,"initialThreshold":threshold}
	check(expired_at >= 1080 and expired_at <= 1081.1,"initial unpreserved 125 glucose really expires at three 360-second days")
	check(int(life.outbreaks) == 1,"unmodified seed73 reference reaches its natural first infection")
	check(red.hp > 0 and game.economy.stock(1,"wood") == 160,"empty glucose alone does not kill or prevent the original red from obtaining protein")
	print("ORGAN ACCESS CALENDAR first natural infection=",game.state.time," food expired=",expired_at)
	write_json("calendar",report.economy.calendar)
	game.dispose()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var began := Time.get_ticks_msec()
	report.loadedSourceSha256 = {}
	for dependency in ["scripts/navigation.gd","scripts/navigation_grid.gd","scripts/blood_flow.gd","scripts/simulation.gd","scripts/economy.gd","scripts/scenarios.gd","scripts/combat.gd","scripts/organ_functions.gd","scripts/organ_resources.gd","scripts/life_run.gd","scripts/medicine_supply.gd","scripts/medicine_helpers.gd","data/life_balance.json","data/organ_functions.json","data/organ_resources.json","data/config.json","data/organs.json","data/starts/fullbody.json","data/blood_siege.json","data/vessels.json"]:
		report.loadedSourceSha256[dependency] = FileAccess.get_sha256("res://"+dependency)
	var single := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--organ="): single = arg.trim_prefix("--organ=")
	if "--calendar-only" in OS.get_cmdline_user_args(): calendar_reference()
	elif "--economy-only" in OS.get_cmdline_user_args(): economic_bootstrap()
	else:
		for organ in TARGETS:
			if single.is_empty() or organ == single: organ_route(organ)
		if single.is_empty() and not "--routes-only" in OS.get_cmdline_user_args():
			economic_bootstrap()
			calendar_reference()
	report.checks = checks; report.failures = failures; report.wallMilliseconds = Time.get_ticks_msec()-began
	report.changedDependencies = []
	for dependency in report.loadedSourceSha256:
		if FileAccess.get_sha256("res://"+dependency) != report.loadedSourceSha256[dependency]: report.changedDependencies.append(dependency)
	var suffix := "-"+single if not single.is_empty() else ("-calendar" if "--calendar-only" in OS.get_cmdline_user_args() else ("-economy" if "--economy-only" in OS.get_cmdline_user_args() else ""))
	write_json("checks"+suffix,report)
	print("ORGAN ACCESS ",checks-failures.size(),"/",checks," ms=",report.wallMilliseconds)
	quit(0 if failures.is_empty() else 1)
