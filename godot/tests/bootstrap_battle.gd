extends SceneTree
## Player-strategy replay: original life start, paid construction/training,
## real walks, natural epidemics and legal life replies. No injected fighters.
const OUT := "res://test-output/bootstrap-battle/"
const SEED := 39462
const FRONT := Vector2(1213.735746,1283.639579)
const BASE_ROOM := Vector2(1089.1505,1932.91453)
var output_dir := OUT
var game: WarSimulation
var checks := 0
var failures: Array[String] = []
var phase := "opening"
var roles: Dictionary = {25:"home_builder"}
var soldiers: Array[int] = []
var birth_ids: Dictionary = {25:true}
var home_core: Dictionary = {}
var home_barracks: Dictionary = {}
var front_core: Dictionary = {}
var front_barracks: Dictionary = {}
var first_colony := ""
var attack_launched := false
var farm_ready := false
var founder_id := 0
var next_control := 0.0
var next_print := 100.0
var destinations: Dictionary = {}
var report := {"seed":SEED,"controllerVersion":2,"scope":"one uninterrupted original life run, natural hazards retained; only real player commands; no spawn/position/resource/progress overrides or transfer",
	"events":[],"commands":[],"births":[],"choices":[],"stages":[],"counts":{},"playerDamage":0.0,"enemyDamage":0.0,"losses":[],"march":{}}

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,label: String) -> bool:
	checks += 1
	if not value: failures.append(label); printerr("FAIL ",label)
	return value

func stock() -> Dictionary:
	return {"wood":game.economy.stock(1,"wood"),"food":game.economy.stock(1,"food"),"oxygen":game.economy.stock(1,"oxygen"),"population":game.economy.population(1)}

func actor(id: int) -> Dictionary:
	return game.entity(id)

func alive() -> bool:
	return game.life.state().phase != "ended" and not game.units().filter(func(e): return e.faction == 1).is_empty()

func original() -> Dictionary:
	return actor(25)

func group() -> Dictionary:
	return game.state.influenzaColonies.groups.get(first_colony,{})

func position(e: Dictionary) -> Dictionary:
	return {"id":int(e.id),"kind":e.kind,"point":[e.x,e.y],"lane":int(e.get("vesselLane",0)),"organ":game.organ_functions.organ(e),"hp":e.hp,"orders":e.orders.duplicate(true),"failed":e.pathFailed,"pending":e.pathPending}

func write_json(name: String,value: Dictionary) -> void:
	var file := FileAccess.open(output_dir+name+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(value,"  ",true,true))

func stage(name: String,extra := {}) -> void:
	var item := {"name":name,"time":game.state.time,"stock":stock(),"function":game.life.state().function,"money":game.life.state().money,"phase":phase}
	item.merge(extra); report.stages.append(item)
	print("BOOTSTRAP STAGE ",name," t=",game.state.time," stock=",item.stock)
	write_json("progress",report)

func submit(command: Dictionary) -> void:
	report.commands.append({"time":game.state.time,"command":command.duplicate(true)})
	game.submit_player(command)

func order(e: Dictionary,kind: String,p := Vector2.INF,target := 0) -> void:
	if e.is_empty() or e.hp <= 0: return
	var current: Dictionary = e.orders[0] if not e.orders.is_empty() else {}
	if current.get("kind","") == kind:
		if kind in ["hold","attack"] and (kind == "hold" or int(current.get("target",0)) == target): return
		if p.is_finite() and WarData.point(current).distance_to(p) < .01: return
	var command := {"kind":kind}
	if p.is_finite(): command.merge({"x":p.x,"y":p.y,"lane":0})
	if target > 0: command.target = target
	submit({"action":"unit_order","unit":int(e.id),"order":command})

func observe(event: Dictionary) -> void:
	report.counts[event.kind] = int(report.counts.get(event.kind,0))+1
	if event.kind == "life_invasion" and first_colony.is_empty():
		for item in game.state.influenzaColonies.groups.values():
			if item.organ == event.organ: first_colony = item.id; break
	if event.kind == "damage":
		var source := actor(int(event.source)); var victim := actor(int(event.target))
		if not source.is_empty() and int(source.faction) == 1: report.playerDamage += float(event.amount)
		if not victim.is_empty() and int(victim.faction) == 1: report.enemyDamage += float(event.amount)
	if event.kind == "death":
		var victim := actor(int(event.target))
		if not victim.is_empty() and int(victim.faction) == 1: report.losses.append({"time":game.state.time,"actor":position(victim)})
	if event.kind in ["life_invasion","influenza_fortress_started","influenza_fortress_complete","influenza_birth","death","infection_purified"] and report.events.size() < 1600:
		report.events.append(event.duplicate(true))

func life_reply() -> void:
	var state := game.life.state()
	if state.pending.is_empty(): return
	var event := WarLifeRun.definition(state.pending.id)
	var option := -1
	if int(state.decisionCount) == 0 and event.id == "crowded_party": option = 1
	else:
		var best := -INF
		for i in event.options.size():
			var item: Dictionary = event.options[i]
			if not game.life.affordable(item): continue
			var score := float(item.function)+4*float(item.get("effect",{}).get("ratePerMinute",0))+.015*float(item.money)
			if item.has("exposure"): score -= 2*maxf(0,float(item.exposure.multiplier)-1)
			if score > best: best = score; option = i
	if option < 0: return
	var record := {"time":game.state.time,"event":event.id,"token":state.pending.token,"option":option,"label":event.options[option].label,"beforeFunction":state.function,"beforeMoney":state.money}
	record.accepted = game.life.choose(int(state.pending.token),option)
	record.afterFunction = state.function; record.afterMoney = state.money
	report.choices.append(record)

func slot(center: Vector2,index: int,kind := "spear",organ := "lung_l") -> Vector2:
	for i in 160:
		var n := index+i
		var p := center+Vector2(float(n%7)-3,float(n/7)-2)*2.2
		if game.navigation.organ_at(p,kind) != organ or not game.navigation.point_allowed(p,0,kind) or not game.navigation.movement_clear(p,p,kind,1): continue
		if not game.navigation.clear_segment(center,p,0,kind): continue
		var used := false
		for goal in destinations.values():
			if p.distance_to(goal) < 1.6: used = true; break
		if not used: return p
	return center

func discover() -> void:
	for e in game.units():
		if e.faction != 1 or birth_ids.has(int(e.id)): continue
		birth_ids[int(e.id)] = true
		report.births.append({"time":game.state.time,"actor":position(e),"maxHp":e.maxHp,"damage":WarData.spec(e.kind).get("damage",0),"trainedCounter":game.state.get("trained",0)})
		if e.kind == "worker":
			if not roles.values().has("protein"):
				roles[int(e.id)] = "protein"
				var source: Dictionary = game.state.resources["small_intestine.wood"]
				submit({"action":"unit_order","unit":int(e.id),"order":{"kind":"harvest","resource":source.id,"x":source.x,"y":source.y}})
			else:
				roles[int(e.id)] = "founder"; founder_id = int(e.id)
				var goal := slot(FRONT,0,"worker")
				destinations[int(e.id)] = goal; order(e,"move",goal)
		elif e.kind == "spear":
			soldiers.append(int(e.id)); roles[int(e.id)] = "soldier"
			var goal := slot(FRONT,soldiers.size()+3)
			destinations[int(e.id)] = goal; order(e,"move",goal)

func military() -> void:
	var source := group()
	var ready := 0
	for id in soldiers:
		var e := actor(id)
		if e.is_empty() or e.hp <= 0: continue
		if game.organ_functions.organ(e) == "lung_l" and WarData.point(e).distance_to(FRONT) < 28: ready += 1
	if not attack_launched and ready >= 4 and not source.is_empty():
		attack_launched = true; stage("four-trained-spear-reach-front",{"ready":ready,"source":source.duplicate(true)})
	for id in soldiers:
		var e := actor(id)
		if e.is_empty() or e.hp <= 0: continue
		var target: Dictionary = {}
		var nearest := INF
		for hostile in game.entities():
			if hostile.hp <= 0 or hostile.faction < 2 or int(hostile.get("vesselLane",0)) != int(e.get("vesselLane",0)): continue
			var distance := WarData.point(e).distance_to(WarData.point(hostile))
			if distance < 10 and distance < nearest: target = hostile; nearest = distance
		if not target.is_empty(): order(e,"attack",Vector2.INF,int(target.id)); continue
		if attack_launched and not source.is_empty() and game.organ_functions.organ(e) == source.organ:
			var forts := game.influenza.forts(source)
			var visible_forts := forts.filter(func(fort): return game.visible(fort,1))
			if not visible_forts.is_empty():
				var fort: Dictionary = visible_forts[0]
				for other in visible_forts:
					if WarData.point(e).distance_squared_to(WarData.point(other)) < WarData.point(e).distance_squared_to(WarData.point(fort)): fort = other
				order(e,"attack",Vector2.INF,int(fort.id))
			else:
				var goal: Vector2 = destinations.get(id,FRONT)
				if not WarInfectionPurification.footprint(source).has_point(goal):
					goal = slot(WarData.point(source.center),soldiers.find(id))
					destinations[id] = goal
				if WarData.point(e).distance_to(goal) < .1: order(e,"hold")
				else: order(e,"attackmove",goal)
		else:
			var goal: Vector2 = destinations.get(id,FRONT)
			if WarData.point(e).distance_to(goal) < .1: order(e,"hold")
			else: order(e,"move",goal)

func auto_train() -> void:
	if not farm_ready or founder_id == 0: return
	var producer := front_barracks if not front_barracks.is_empty() and front_barracks.get("complete",false) else home_barracks
	if producer.is_empty() or producer.hp <= 0 or not producer.get("complete",false): return
	var count := 0
	for id in soldiers:
		if not actor(id).is_empty() and actor(id).hp > 0: count += 1
	for e in [home_barracks,front_barracks]:
		if not e.is_empty(): count += e.queue.size()
	var limit := 16 if not front_core.is_empty() and front_core.get("complete",false) else 7
	if count >= limit or producer.queue.size() >= 2 or report.births.size() >= 55: return
	var pop := game.economy.population(1)
	if pop.x+1 > pop.y or game.economy.stock(1,"wood") < 15 or game.economy.stock(1,"food") < 12: return
	submit({"action":"train","target":int(producer.id),"unit":"spear"})

func frame() -> void:
	game.navigation.update(20000); game.update(.1)
	life_reply(); discover()
	if float(game.state.time) >= next_control:
		next_control = float(game.state.time)+1.0
		auto_train(); military()
	for id in roles:
		var e := actor(id)
		if e.is_empty(): continue
		var key := str(id)
		if not report.march.has(key): report.march[key] = {"travelled":0.0,"last":[e.x,e.y],"lastLane":int(e.get("vesselLane",0)),"maxStep":0.0,"transitions":[],"samples":[]}
		var data: Dictionary = report.march[key]
		var distance := WarData.point(e).distance_to(WarData.point(data.last))
		data.travelled += distance; data.maxStep = maxf(float(data.maxStep),distance); data.last = [e.x,e.y]
		if int(data.lastLane) != int(e.get("vesselLane",0)):
			data.transitions.append({"time":game.state.time,"point":[e.x,e.y],"from":data.lastLane,"to":e.get("vesselLane",0)})
			data.lastLane = int(e.get("vesselLane",0))
		if int(game.state.tick)%100 == 0: data.samples.append({"time":game.state.time,"position":position(e)})
	if float(game.state.time) >= next_print:
		next_print += 100
		print("BOOTSTRAP ",phase," t=",game.state.time," f=",game.life.state().function," armyBorn=",soldiers.size()," units=",game.units().size()," forts=",game.entities().filter(func(e): return e.kind == "flu_fortress").size()," stock=",stock())
		var actors: Array = []
		for e in game.units():
			if e.faction == 1: actors.append(position(e))
		write_json("live",{"time":game.state.time,"phase":phase,"actors":actors,"roles":roles,"source":group().duplicate(true),"stock":stock()})

func move_actor(id: int,p: Vector2,budget := 180.0) -> bool:
	var e := actor(id)
	if e.is_empty(): return false
	order(e,"move",p)
	var began := float(game.state.time)
	while alive() and float(game.state.time)-began < budget:
		frame(); e = actor(id)
		if e.is_empty() or e.hp <= 0: return false
		if int(e.get("vesselLane",0)) == 0 and WarData.point(e).distance_to(p) < .1 and e.orders.is_empty(): return true
	return false

func probe(e: Dictionary,p: Vector2) -> bool:
	var receipt := {"done":false,"okay":false,"token":-1}
	var callback := func(token,path,_reason):
		if token == receipt.token: receipt.done = true; receipt.okay = not path.is_empty()
	game.navigation.path_ready.connect(callback)
	receipt.token = game.navigation.request(e,p,0)
	var began := Time.get_ticks_msec()
	while not receipt.done and Time.get_ticks_msec()-began < 5000: game.navigation.update(20000)
	game.navigation.cancel(int(receipt.token)); game.navigation.path_ready.disconnect(callback)
	return receipt.okay

func site(e: Dictionary,kind: String,center: Vector2,organ: String) -> Dictionary:
	var options: Array = []
	for y in range(-15,16):
		for x in range(-15,16):
			var p := game.economy.build_point(kind,center+Vector2(x,y))
			if game.navigation.organ_at(p,"worker") != organ or not game.economy.can_place(kind,p,[int(e.id)]): continue
			if game.state.resources.values().any(func(r): return WarData.point(r).distance_to(p) < float(WarData.spec(kind).size)*.5+2.5): continue
			options.append(p)
	options.sort_custom(func(a,b): return a.distance_squared_to(WarData.point(e)) < b.distance_squared_to(WarData.point(e)))
	var reach := float(WarData.spec(kind).size)*.5+1.1
	for p: Vector2 in options:
		for i in 16:
			var approach := p+Vector2.from_angle((WarData.point(e)-p).angle()+i*TAU/16)*reach
			if not game.navigation.point_allowed(approach,0,e.kind) or not game.navigation.movement_clear(approach,approach,e.kind,1): continue
			if probe(e,approach): return {"point":p,"approach":approach}
	return {}

func build(id: int,kind: String,p: Vector2,budget := 180.0) -> Dictionary:
	var e := actor(id)
	if e.is_empty(): return {}
	var before := stock()
	submit({"action":"place","building":kind,"x":p.x,"y":p.y,"ids":[id]})
	var began := float(game.state.time)
	var building: Dictionary = {}
	while alive() and float(game.state.time)-began < budget:
		frame()
		for candidate in game.entities():
			if candidate.faction == 1 and candidate.kind == kind and WarData.point(candidate).distance_to(p) < .1: building = candidate; break
		if not building.is_empty() and building.get("complete",false):
			stage("built-"+kind,{"id":building.id,"point":[p.x,p.y],"beforeStock":before,"elapsed":float(game.state.time)-began,"builder":id})
			return building
		if float(game.state.time)-began > 2 and building.is_empty(): break
	stage("build-failed-"+kind,{"point":[p.x,p.y],"actor":position(e),"message":game.message,"building":building.duplicate(true)})
	return {}

func build_near(id: int,kind: String,center: Vector2,organ: String) -> Dictionary:
	var e := actor(id)
	if e.is_empty(): return {}
	var choice := site(e,kind,center,organ)
	if choice.is_empty(): stage("no-site-"+kind,{"builder":id,"position":position(e)}); return {}
	if not move_actor(id,choice.approach,180): stage("approach-failed-"+kind,{"builder":id,"position":position(e),"choice":choice}); return {}
	return build(id,kind,choice.point)

func local_hostiles(source: Dictionary) -> int:
	var total := 0
	var rect := WarInfectionPurification.footprint(source)
	for e in game.entities():
		if e.hp > 0 and int(e.faction) >= 2 and int(e.get("vesselLane",0)) == 0 and rect.has_point(WarData.point(e)) and game.navigation.organ_at(WarData.point(e),e.kind) == source.organ: total += 1
	return total

func run_strategy() -> void:
	check(game.units().size() == 1 and original().kind == "worker" and game.economy.stock(1,"wood") == 160 and game.economy.stock(1,"food") == 125,"untouched original single red and starting resources")
	check(WarData.config().Data.unitOrder.has("spear") and not WarData.config().Data.unitOrder.has("neutrophil") and WarData.spec("spear").hp == 150 and WarData.spec("spear").damage == 15,"player production identity is the confirmed spear 150HP/15 damage")
	if not check(move_actor(25,Vector2(994,1907.5),30),"original red really leaves its birth pocket"): return
	var compact := "--compact-layout" in OS.get_cmdline_user_args()
	report.layout = "compact-swapped" if compact else "local-depot-and-open-organ-base"
	if not compact:
		var depot := build(25,"store",Vector2(985,1906))
		if not check(not depot.is_empty(),"original red actually builds its starting protein depot"): return
		var source: Dictionary = game.state.resources["small_intestine.wood"]
		submit({"action":"unit_order","unit":25,"order":{"kind":"harvest","resource":source.id,"x":source.x,"y":source.y}})
		var began := float(game.state.time)
		while alive() and float(game.state.time)-began < 180 and float(game.state.get("delivered",0)) < 56: frame()
		if not check(game.economy.stock(1,"wood") == 186,"four real protein loads fund the broader base without granting resources"): return
		stage("four-protein-loads",{"actor":position(original())})
		if not check(move_actor(25,BASE_ROOM,1000),"original red walks to an authored open intestine clearing"): return
		home_core = build_near(25,"core",BASE_ROOM,"small_intestine")
	else: home_core = build(25,"core",Vector2(987.5,1905.5))
	if not check(not home_core.is_empty(),"normal paid home core completes"): return
	if compact: home_barracks = build(25,"barracks",Vector2(981.5,1905.5))
	else: home_barracks = build_near(25,"barracks",BASE_ROOM,"small_intestine")
	if not check(not home_barracks.is_empty(),"normal paid home barracks completes"): return
	var farm := build_near(25,"farm",WarData.point(home_core),"small_intestine")
	if not check(not farm.is_empty(),"normal paid home farm completes"): return
	if "--opening-only" in OS.get_cmdline_user_args():
		report.partial = "opening-only replay; no flu-clear claim"
		return
	farm_ready = true
	order(original(),"farm",Vector2.INF,int(farm.id))
	submit({"action":"train","target":int(home_core.id),"unit":"worker"})
	submit({"action":"train","target":int(home_core.id),"unit":"worker"})
	phase = "march-and-supply"
	var began := float(game.state.time)
	while alive() and float(game.state.time)-began < 2000:
		frame()
		var founder := actor(founder_id)
		if not founder.is_empty() and game.organ_functions.organ(founder) == "lung_l" and WarData.point(founder).distance_to(FRONT) < 18: break
	var founder := actor(founder_id)
	if not check(not founder.is_empty() and game.organ_functions.organ(founder) == "lung_l","normally trained expedition red physically reaches the lung"): return
	stage("founder-reaches-lung",{"actor":position(founder),"firstColony":first_colony,"source":group().duplicate(true)})
	phase = "forward-outpost"
	front_core = build_near(founder_id,"core",FRONT,"lung_l")
	if not check(not front_core.is_empty(),"trained red builds a real paid forward core"): return
	front_barracks = build_near(founder_id,"barracks",FRONT,"lung_l")
	if not check(not front_barracks.is_empty(),"trained red builds a real paid forward barracks"): return
	phase = "clear-and-purify"
	began = float(game.state.time)
	var capture_ordered := false
	while alive() and float(game.state.time)-began < 2200:
		frame()
		var source := group()
		if source.is_empty(): continue
		if source.cleared: break
		founder = actor(founder_id)
		if not capture_ordered and not founder.is_empty() and game.influenza.forts(source).is_empty() and local_hostiles(source) == 0:
			var goal := slot(WarData.point(source.center),1,"worker")
			destinations[founder_id] = goal; order(founder,"guard",goal); capture_ordered = true
			stage("red-ordered-to-cleared-source",{"goal":[goal.x,goal.y],"actor":position(founder)})
	check(not group().is_empty() and group().get("cleared",false),"first naturally triggered flu source is actually jointly purified")
	if not group().is_empty() and group().get("cleared",false):
		for i in 15: frame()
		check(int(game.life.state().recovered) >= 1,"real-life recovery is credited after actual trained-red and trained-spear hold")
		stage("first-source-purified",{"source":group().duplicate(true),"escapedLivingMembers":game.influenza.members(group()).size()})

func inspect_compact() -> void:
	# Read-only path diagnostics of this test's earlier real failed run; never
	# resume it as a successful bootstrap or alter its actors/blockers.
	game.restore(WarData.read("../test-output/bootstrap-battle/march-4-final-snapshot"))
	game.navigation.blockers = game.entities().filter(func(e): return e.category == "building" and e.hp > 0 and not e.has("checkpointId"))
	var red := actor(25); var building := actor(58)
	var center := WarData.point(building)
	var selected := game.navigation.building_approach(red,building,2.7)
	var points: Array = []
	for y in range(-11,12):
		for x in range(-11,12):
			var p := center+Vector2(x,y)*.25
			if p.distance_to(center) > 2.7 or not game.navigation.point_allowed(p,0,"worker") or not game.navigation.movement_clear(p,p,"worker",1): continue
			points.append({"point":[p.x,p.y],"plan":probe(red,p),"straight":game.navigation.clear_segment(WarData.point(red),p,0,"worker") and game.navigation.movement_clear(WarData.point(red),p,"worker",1)})
	write_json("compact-static-diagnostic",{"scope":"read-only planning from the exact real failed snapshot, no simulated arrival claims","red":position(red),"building":building,"selectedApproach":selected,"freeWorkPoints":points,"snapshotTime":game.state.time})
	print("COMPACT DIAGNOSTIC free work points=",points.size()," with complete plans=",points.filter(func(p): return p.plan).size()," chosen=",selected)

func run() -> void:
	if "--compact-layout" in OS.get_cmdline_user_args(): output_dir += "compact-recheck/"
	DirAccess.make_dir_recursive_absolute(output_dir)
	var began := Time.get_ticks_msec()
	report.loadedSourceSha256 = {}
	for path in ["scripts/simulation.gd","scripts/navigation.gd","scripts/economy.gd","scripts/combat.gd","scripts/influenza_colonies.gd","scripts/infection_purification.gd","scripts/life_run.gd","data/config.json","data/life_balance.json","data/life_decisions.json","data/organ_resources.json"]:
		report.loadedSourceSha256[path] = FileAccess.get_sha256("res://"+path)
	game = WarSimulation.new(); game.start("life",SEED)
	if "--inspect-compact" in OS.get_cmdline_user_args():
		inspect_compact(); game.dispose(); quit(); return
	game.combat_event.connect(observe)
	run_strategy()
	report.checks = checks; report.failures = failures; report.finishedAt = game.state.time; report.wallMilliseconds = Time.get_ticks_msec()-began
	report.life = game.life.state().duplicate(true); report.finalStock = stock(); report.firstColony = first_colony
	report.finalActors = []
	for e in game.units():
		if e.faction == 1: report.finalActors.append(position(e))
	report.changedDependencies = []
	for path in report.loadedSourceSha256:
		if report.loadedSourceSha256[path] != FileAccess.get_sha256("res://"+path): report.changedDependencies.append(path)
	write_json("checks",report); write_json("final-snapshot",game.snapshot())
	print("BOOTSTRAP BATTLE ",checks-failures.size(),"/",checks," t=",game.state.time," ms=",report.wallMilliseconds," failures=",failures)
	game.dispose()
	quit(0 if failures.is_empty() else 1)
