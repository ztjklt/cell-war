extends SceneTree
## Full fixed-step lifecycle checks. No scene/UI, no direct life.advance shortcuts.
const SEED := 39462 # Naturally offers crowded_party; its original risk threshold is ~0.12.
const OUTPUT := "res://test-output/life-integration.json"
var failures: Array[String] = []
var checks := 0
var result := {"seed":SEED,"timing":[],"journey":{},"combat":{},"crisis":{}}

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,text: String) -> void:
	checks += 1
	if not value: failures.append(text); printerr("FAIL ",text)

func frame(game: WarSimulation,delta := .1) -> void:
	# Complete real queued route work with an offline budget; positions/combat still use STEP=.1.
	game.navigation.update(10000)
	game.update(delta)

func run_for(game: WarSimulation,seconds: float) -> void:
	for i in ceili(seconds/.1): frame(game)

func until_contact(game: WarSimulation,budget := 200.0) -> float:
	var began := float(game.state.time)
	for i in ceili(budget/.1):
		if not game.life.state().pending.is_empty(): break
		frame(game)
	return float(game.state.time)-began

func until_infection(game: WarSimulation,budget := 300.0) -> float:
	var began := float(game.state.time)
	for i in ceili(budget/.1):
		if int(game.life.state().outbreaks) > 0: break
		frame(game)
	return float(game.state.time)-began

func observe(event: Dictionary,stats: Dictionary) -> void:
	var kind: String = event.kind
	stats.counts[kind] = int(stats.counts.get(kind,0))+1
	if kind == "damage":
		if stats.friendlyIds.has(int(event.source)):
			stats.playerHits += 1; stats.playerDamage += float(event.amount)
		if stats.friendlyIds.has(int(event.target)):
			stats.enemyHits += 1; stats.enemyDamage += float(event.amount)
	if kind in ["life_offer","life_choice","life_invasion","influenza_fortress_started","influenza_fortress_complete","influenza_birth","death"] and stats.trace.size() < 200:
		var entry := event.duplicate(true); entry.branch = stats.get("branch","initial")
		stats.trace.append(entry)

func fresh(seed := SEED) -> WarSimulation:
	var game := WarSimulation.new(); game.start("life",seed)
	return game

func timing_case(speed: float,delta: float,with_pause: bool,mixed := false) -> void:
	print("LIFE INTEGRATION cadence ",speed,"x, delta=",delta," pause=",with_pause," mixed=",mixed)
	var game := fresh()
	game.speed = speed
	var active_input := 0.0
	var paused_input := 0.0
	var did_pause := false
	var paused_unchanged := true
	for i in 20000:
		if with_pause and not did_pause and active_input >= 60:
			game.paused = true
			var before := game.life.state().duplicate(true)
			var time := float(game.state.time)
			for p in 300: frame(game,.1); paused_input += .1
			paused_unchanged = game.life.state() == before and game.state.time == time
			game.paused = false; did_pause = true
		if mixed: game.speed = 1 if active_input < 90 else 2
		frame(game,delta); active_input += delta
		if not game.life.state().pending.is_empty(): break
	var s := game.life.state()
	check(not s.pending.is_empty(),"cadence produces a first outside contact")
	check(active_input >= 180-.000001 and active_input <= 180.25,"no first contact before three unpaused input minutes")
	check(float(s.activeElapsed) >= 180-.000001 and float(s.activeElapsed) <= 180.15,"life contact clock accounts for fixed-step quantisation")
	check(paused_unchanged,"paused update cannot advance contact, money, function or age")
	var first := {"speed":speed,"inputDelta":delta,"mixed":mixed,"pausedInputSeconds":paused_input,
		"activeInputSeconds":active_input,"simulatedSeconds":game.state.time,"event":s.pending.get("id","")}
	if not s.pending.is_empty():
		var item := WarLifeRun.definition(s.pending.id)
		var free_index := -1
		for i in item.options.size():
			if int(item.options[i].money) == 0: free_index = i; break
		check(free_index >= 0 and game.life.choose(int(s.pending.token),free_index),"cadence fixture replies to a naturally offered free choice")
		var expected_wait := float(s.nextDecisionAt)-float(s.activeElapsed)
		check(expected_wait >= 120 and expected_wait <= 180,"follow-up interval is configured two to three active minutes")
		var waited := 0.0
		for i in 20000:
			frame(game,delta); waited += delta
			if not s.pending.is_empty(): break
		check(not s.pending.is_empty() and waited+.000001 >= expected_wait and waited <= expected_wait+.25,"next contact cannot arrive early under full simulation")
		first["nextExpectedWait"] = expected_wait; first["nextActualInputWait"] = waited
	result.timing.append(first)
	game.dispose()

func spawn_defenders(game: WarSimulation,group: Dictionary,stats: Dictionary) -> Array[int]:
	var ids: Array[int] = []
	var center := WarData.point(group.center)
	for i in 600:
		if ids.size() >= 10: break
		var p := center+Vector2.from_angle(i*2.399963)*(7.5+float(i%9)*.8)
		if game.navigation.organ_at(p,"spear") != group.organ or not game.navigation.point_allowed(p,0,"spear"): continue
		var free := true
		for e in game.entities():
			if e.hp <= 0 or int(e.get("vesselLane",0)) != 0: continue
			var radius := float(WarData.spec(e.kind).get("size",1))*.5 if e.category == "building" else WarData.radius(e.kind)
			if p.distance_to(WarData.point(e)) < radius+WarData.radius("spear")+.2: free = false; break
		if not free: continue
		var unit := game.spawn("spear",1,p)
		if unit.is_empty(): continue
		unit.vesselLane = 0
		ids.append(int(unit.id)); stats.friendlyIds.append(int(unit.id))
	return ids

func direct_defenders(game: WarSimulation,group: Dictionary,ids: Array[int]) -> void:
	var enemies := game.influenza.members(group)+game.influenza.forts(group)
	if enemies.is_empty(): return
	for id in ids:
		var unit := game.entity(id)
		if unit.is_empty() or unit.hp <= 0: continue
		var target: Dictionary = enemies[0]
		for candidate in enemies:
			if WarData.point(unit).distance_squared_to(WarData.point(candidate)) < WarData.point(unit).distance_squared_to(WarData.point(target)): target = candidate
		game.submit_player({"action":"unit_order","unit":id,"order":{"kind":"attack","target":int(target.id)}})

func local_hostiles(game: WarSimulation,group: Dictionary) -> int:
	var count := 0
	var rect := WarInfectionPurification.footprint(group)
	for e in game.entities():
		if e.hp > 0 and int(e.faction) > 1 and int(e.get("vesselLane",0)) == 0 and rect.has_point(WarData.point(e)) and game.navigation.organ_at(WarData.point(e),e.kind) == group.organ: count += 1
	return count

func capture_red(game: WarSimulation,group: Dictionary) -> Dictionary:
	for y in [-3.0,-1.0,1.0,3.0]:
		for x in [-3.0,-1.0,1.0,3.0]:
			var p := WarData.point(group.center)+Vector2(x,y)
			if not game.navigation.point_allowed(p,0,"worker"): continue
			var free := true
			for e in game.units():
				if int(e.get("vesselLane",0)) == 0 and WarData.point(e).distance_to(p) < WarData.radius("worker")+WarData.radius(e.kind)+.15: free = false; break
			if not free: continue
			var red := game.spawn("worker",1,p)
			if red.is_empty(): continue
			red.vesselLane = 0
			game.submit_player({"action":"unit_order","unit":int(red.id),"order":{"kind":"hold"}})
			return red
	return {}

func purification(game: WarSimulation,group: Dictionary,defenders: Array[int],stats: Dictionary) -> Dictionary:
	var s := game.life.state()
	check(not group.cleared and int(s.recovered) == 0,"killing the enemies alone neither purifies nor unlocks life recovery")
	check(game.life._groups >= 1,"unpurified real source remains in the life infection budget")
	var red := capture_red(game,group)
	check(not red.is_empty(),"joint capture explicitly deploys a legal local red test cell")
	var white: Dictionary = {}
	for id in defenders:
		var candidate := game.entity(id)
		if not candidate.is_empty() and candidate.hp > 0: white = candidate; break
	check(not white.is_empty(),"at least one actual combat defender survives for joint capture")
	if red.is_empty() or white.is_empty(): return {"completed":false}
	game.submit_player({"action":"unit_order","unit":int(white.id),"order":{"kind":"guard","x":float(group.center[0])+2,"y":float(group.center[1]),"lane":0}})
	for i in 500:
		frame(game)
		if float(group.purification.elapsed) >= 5: break
	check(float(group.purification.elapsed) >= 5 and not group.cleared,"actual red-white occupancy advances a partial hold")
	var partial := float(group.purification.elapsed)
	check(WarSave.write(game,3) == OK and WarSave.read_slot(game,3) == OK,"mid-purification file save and restore succeed")
	group = game.state.influenzaColonies.groups[group.id]; s = game.life.state()
	check(is_equal_approx(float(group.purification.elapsed),partial),"restored hold retains its elapsed occupation")
	game.paused = true; var paused: Dictionary = game.snapshot().lifeRun
	run_for(game,5)
	check(game.life.state() == paused and is_equal_approx(float(group.purification.elapsed),partial),"paused full simulation preserves joint hold and life data")
	game.paused = false
	var completed_at := -1.0
	for i in 400:
		frame(game)
		if group.cleared: completed_at = float(game.state.time); break
	check(group.cleared and group.purification.status == "purified" and is_equal_approx(float(group.purification.elapsed),WarInfectionPurification.HOLD_SECONDS),"real full hold, not kills, completes joint purification")
	run_for(game,1.2)
	check(int(s.recovered) >= 1 and game.life.eligible(WarLifeRun.definition("after_infection")),"completed joint purification unlocks the life recovery follow-up")
	var recovered := int(s.recovered); run_for(game,2)
	check(int(s.recovered) == recovered,"completed purification is not repeatedly credited")
	check(int(stats.counts.get("infection_purified",0)) == 1,"joint purification emits one actual completion event")
	return {"completed":group.cleared,"partialSaved":partial,"completedAt":completed_at,"recovered":s.recovered,"redFixture":int(red.id),"whiteSurvivor":int(white.id)}

func journey(seed := SEED) -> void:
	print("LIFE INTEGRATION actual new run, paid/free branches and naturally directed flu")
	var game := fresh(seed)
	var stats := {"counts":{},"trace":[],"friendlyIds":[],"playerHits":0,"playerDamage":0.0,"enemyHits":0,"enemyDamage":0.0}
	game.combat_event.connect(func(event): observe(event,stats))
	check(game.units().size() == 1 and game.units()[0].kind == "worker" and int(game.units()[0].faction) == 1,"new life starts with exactly its original one red cell")
	check(game.state.influenzaColonies.groups.is_empty(),"new life has no duplicate legacy first outbreak")
	until_contact(game)
	var s := game.life.state()
	check(s.pending.get("id","") == "crowded_party","fixed seed naturally produces the documented first conversation")
	if s.pending.is_empty(): game.dispose(); return
	game.paused = true
	var pending_snapshot := game.snapshot()
	var pending_token := int(s.pending.token)
	var before_money := int(s.money)
	check(before_money == 320,"normal first income and living expense net twenty before the first reply")
	var pending_write := WarSave.write(game,1)
	check(pending_write == OK,"actual pending conversation writes to isolated manual slot")
	if pending_write != OK: game.dispose(); return
	check(WarSave.write(game,0) == OK,"test owns a separate legacy autosave marker")
	var marker := FileAccess.get_file_as_bytes(WarSave.path(0))
	check(WarSave.write_life_auto(game) == OK and FileAccess.get_file_as_bytes(WarSave.path(0)) == marker,"life autosave preserves the existing slot zero")
	frame(game,.25)
	check(game.life.state() == pending_snapshot.lifeRun,"pending conversation remains unchanged while paused")
	s.money = 0
	check(not game.life.choose(pending_token,1) and not s.pending.is_empty() and int(s.money) == 0,"unaffordable real offered reply is rejected atomically")
	check(WarSave.read_slot(game,1) == OK,"isolated file restores original pending conversation")
	s = game.life.state()
	check(s.pending == pending_snapshot.lifeRun.pending and int(s.rng) == int(pending_snapshot.lifeRun.rng) and int(s.money) == before_money,"pending identity, transaction token, RNG and money survive file restore")
	stats.branch = "free"
	check(game.life.choose(pending_token,0),"free reply settles from a naturally offered conversation")
	var free_rate := game.life.risk_rate()
	check(int(s.money) == before_money and s.pending.is_empty(),"free reply consumes offer without charging")
	game.paused = false
	until_infection(game)
	var free_at := float(game.state.time)
	check(int(s.outbreaks) == 1,"free branch still allows a probabilistic natural infection")
	check(WarSave.read_slot(game,1) == OK,"paid branch restarts from same persisted pending snapshot")
	game.paused = true; s = game.life.state()
	stats.branch = "paid"
	var original_function := float(s.function)
	check(game.life.choose(pending_token,1),"paid reply settles from the restored offered transaction")
	check(int(s.money) == before_money-20 and is_equal_approx(float(s.function),original_function-1),"paid reply charges twenty and applies the authored function cost once")
	check(not game.life.choose(pending_token,1) and int(s.money) == before_money-20,"same restored token cannot charge twice")
	var paid_rate := game.life.risk_rate()
	check(paid_rate > free_rate and s.exposures.size() == 1,"authored exposure and function changes raise actual life risk")
	game.paused = false
	until_infection(game)
	var paid_at := float(game.state.time)
	check(int(s.outbreaks) == 1 and paid_at < free_at,"matched deterministic paid branch reaches infection sooner without forcing hazard or RNG")
	result.journey = {"firstEvent":"crowded_party","firstAt":pending_snapshot.time,"pendingToken":pending_token,
		"beforeMoney":before_money,"paidCost":20,"freeRiskPerMinute":free_rate,"paidRiskPerMinute":paid_rate,
		"freeFirstInfectionAt":free_at,"paidFirstInfectionAt":paid_at,"riskThresholdWasForced":false}
	if game.state.influenzaColonies.groups.is_empty(): game.dispose(); return
	var group: Dictionary = game.state.influenzaColonies.groups.values()[0]
	var initial_count := int(group.pending)
	check(group.organ in ["lung_l","lung_r"] and initial_count >= 10 and initial_count <= 20,"director chooses a certified lung group with the existing batch limit")
	check(group.lifeSource == "crowded_party","actual colony retains decision provenance")
	run_for(game,2)
	var population := game.influenza.members(group)
	check(population.size() == initial_count and int(group.pending) == 0,"pending batch becomes real live viruses through full simulation")
	for entity in population:
		check(int(entity.vesselLane) == 0 and game.navigation.organ_at(WarData.point(entity),"virus") == group.organ,"naturally born virus occupies its real authored tissue plane")
	var began := float(game.state.time)
	var fort: Dictionary = {}
	for i in 1200:
		frame(game)
		for site in game.influenza.forts(group):
			if site.get("complete",false): fort = site; break
		if not fort.is_empty(): break
	check(not fort.is_empty(),"ten real builders finish a fortress without progress or hp overrides")
	var construction_completed := not fort.is_empty()
	var stall: Dictionary = {}
	if fort.is_empty():
		var sites := game.influenza.forts(group)
		if sites.is_empty(): result.combat = {"constructionFailed":true,"waited":float(game.state.time)-began,"trace":stats.trace}; game.dispose(); return
		fort = sites[0]
		stall = {"colony":group.id,"fortress":int(fort.id),"fortressPoint":[fort.x,fort.y],"progress":fort.progress,"center":group.center,"waited":float(game.state.time)-began,"workers":[]}
		for id in fort.builders:
			var worker := game.entity(int(id))
			stall.workers.append({"id":int(id),"point":[worker.x,worker.y],"slot":worker.get("fluBuildSlot",[]),"state":worker.get("combatState",""),"pathFailed":worker.get("pathFailed",false),"pathPending":worker.get("pathPending",false),"pathSize":worker.get("path",[]).size(),"workedAt":worker.get("fluWorkedAt",-1)})
	var complete_at := float(game.state.time) if construction_completed else -1.0
	check(int(group.produced) == 0,"fortress has not yet produced before its valid first incubation period")
	check(WarSave.write(game,2) == OK,"actual complete fortress and life state persist together")
	var fort_id := int(fort.id)
	var saved_growth := float(fort.growthElapsed)
	check(WarSave.read_slot(game,2) == OK,"active real colony reloads from isolated slot")
	s = game.life.state(); group = game.state.influenzaColonies.groups[group.id]; fort = game.entity(fort_id)
	check(is_equal_approx(float(fort.growthElapsed),saved_growth) and int(group.produced) == 0,"reload preserves incubation without a duplicate birth")
	game.paused = true
	var paused_life := s.duplicate(true)
	run_for(game,15)
	check(game.life.state() == paused_life and is_equal_approx(float(fort.growthElapsed),saved_growth),"pause freezes real colony incubation and pending life data")
	game.paused = false
	var birth_at := -1.0
	if construction_completed:
		for i in 400:
			frame(game)
			if int(group.produced) > 0: break
		birth_at = float(game.state.time)
		check(int(group.produced) == 1 and birth_at-complete_at >= 29.9 and birth_at-complete_at <= 30.2,"full simulation produces exactly one first child at thirty seconds across reload")
	print("LIFE INTEGRATION deploy explicit legal test defenders; normal combat begins")
	var defenders := spawn_defenders(game,group,stats)
	check(defenders.size() == 10,"test explicitly deploys ten legal legacy white cells; start gift is not assumed")
	var before_function := float(s.function)
	var battle_at := float(game.state.time)
	for i in 2400:
		if i%30 == 0: direct_defenders(game,group,defenders)
		frame(game)
		if local_hostiles(game,group) == 0 and game.influenza.forts(group).is_empty(): break
	check(int(stats.playerHits) > 0 and int(stats.counts.get("projectile_spawn",0)) > 0 and int(stats.counts.get("projectile_impact",0)) > 0,"real queued attacks release projectiles that deal non-synthetic damage")
	check(int(stats.counts.get("death",0)) > 0,"real combat resolves actual deaths")
	check(game.entity(fort_id).is_empty() or float(game.entity(fort_id).get("hp",0)) <= 0,"real defenders destroy the actual flu fortress")
	check(local_hostiles(game,group) == 0 and game.influenza.forts(group).is_empty(),"real combat removes local source enemies and all source forts without direct hp deletion")
	var remaining_escaped := game.influenza.members(group).size()
	var battle_seconds := float(game.state.time)-battle_at
	var purified := purification(game,group,defenders,stats)
	s = game.life.state(); group = game.state.influenzaColonies.groups[group.id]
	check(WarSave.validate(game.snapshot()).is_empty(),"post-combat life/colony/unit snapshot remains valid")
	result.combat = {"organ":group.organ,"batch":initial_count,"outbreakAt":paid_at,"fortressCompleteAt":complete_at,
		"firstBirthAt":birth_at,"defenders":defenders.size(),"battleSeconds":battle_seconds,"battleAndCaptureSeconds":float(game.state.time)-battle_at,"escapedMembersAfterLocalCombat":remaining_escaped,
		"cleared":group.cleared,"constructionCompleted":construction_completed,"incubationVerified":birth_at > 0,"constructionStall":stall,"purification":purified,"functionBeforeBattle":before_function,"functionAfterBattle":s.function,
		"stats":stats,"fixture":"ten explicitly spawned legal spear cells with unchanged health/damage; submitted normal attack commands"}
	game.dispose()

func crisis_cases() -> void:
	print("LIFE INTEGRATION controlled boundary branches through real choices and full update")
	var game := fresh()
	var pending_read := WarSave.read_slot(game,1)
	check(pending_read == OK,"crisis starts from the genuinely offered persisted conversation")
	if pending_read != OK: game.dispose(); return
	var s := game.life.state()
	# A boundary setup is explicit. We do not claim a healthy body naturally declined to this state.
	s.function = .5
	check(game.life.choose(int(s.pending.token),1) and s.phase == "crisis","authored negative choice enters crisis from a half-point boundary fixture")
	var began := float(game.state.time)
	game.paused = true
	var paused_life := s.duplicate(true); run_for(game,20)
	check(s == paused_life,"paused full update cannot consume crisis rescue time")
	game.paused = false
	run_for(game,59.8)
	check(s.phase == "crisis" and float(s.crisisRemaining) > 0,"crisis does not end before sixty simulated seconds")
	for i in 5:
		frame(game)
		if s.phase == "ended": break
	check(s.phase == "ended" and game.paused and float(s.finishedAge) == float(s.age),"unrecovered real-step crisis ends once and records age")
	var duration := float(game.state.time)-began
	check(duration >= 59.9 and duration <= 60.2,"crisis ending obeys the configured time window")
	var ended := game.snapshot()
	run_for(game,20); game.step(.1)
	check(game.life.state() == ended.lifeRun and game.state.time == ended.time,"ended life cannot progress or settle repeatedly")
	check(WarSave.write_life_auto(game) == OK,"ended boundary branch persists to its independent auto file")
	check(WarSave.read_slot(game,1) == OK,"rescue branch restores the same pending transaction")
	s = game.life.state(); s.function = 0.0; s.phase = "crisis"; s.crisisRemaining = 5.0
	var money := int(s.money)
	check(game.life.choose(int(s.pending.token),0) and float(s.function) >= 2 and s.phase == "living","existing positive free pending choice can rescue a controlled crisis")
	game.paused = false; run_for(game,10)
	check(s.phase == "living" and int(s.money) == money,"rescued state continues normally without charging the free choice")
	check(WarSave.validate(game.snapshot()).is_empty(),"rescued state remains loadable")
	result.crisis = {"setup":"persisted real offer; only boundary function/phase/countdown set in the test",
		"deathAfterSimulatedSeconds":duration,"finishedAge":ended.lifeRun.finishedAge,
		"rescueRequiresExistingPendingChoice":true,"noNaturalDecadesClaim":true}
	game.dispose()

func run() -> void:
	var began := Time.get_ticks_msec()
	var original_directory := WarSave.directory
	var seed := SEED
	var journey_only := "--journey-only" in OS.get_cmdline_user_args()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="): seed = int(arg.trim_prefix("--seed="))
	result.seed = seed; result.runMode = "journey-only" if journey_only else "full"
	result.loadedSourceSha256 = {}
	for dependency in ["scripts/life_run.gd","scripts/influenza_colonies.gd","scripts/infection_purification.gd","scripts/combat.gd","scripts/navigation.gd","scripts/simulation.gd","scripts/organ_resources.gd","data/organ_resources.json","data/life_balance.json","data/life_decisions.json"]:
		result.loadedSourceSha256[dependency] = FileAccess.get_sha256("res://"+dependency)
	WarSave.directory = "user://test-saves/bug-audit-life-integration"+("/seed-%d" % seed if seed != SEED else "")+"/run-%d-%d" % [Time.get_unix_time_from_system(),OS.get_process_id()]
	if not journey_only:
		timing_case(1,.1,true)
		timing_case(2,.1,true)
		timing_case(1,1.0/60,false)
		timing_case(1,.1,true,true)
	journey(seed)
	crisis_cases()
	result.checks = checks; result.failures = failures; result.wallMilliseconds = Time.get_ticks_msec()-began
	result.saveDirectory = WarSave.directory
	result.scope = "WarSimulation.update -> native fixed steps, real navigation, construction, incubation and combat; no UI scenes and no direct life.advance or synthetic damage"
	result.limits = ["headless wall-clock accelerated simulation is not hours of rendered user play","defenders and capture red are explicit fixtures, not trained or transported from the original start in this test","crisis uses controlled boundary preconditions","no medicine, additional pathogen, off-line progress, cloud save or phone acceptance"]
	DirAccess.make_dir_recursive_absolute("res://test-output")
	var output := OUTPUT if not journey_only and seed == SEED else OUTPUT.get_basename()+"-seed-%d.json" % seed
	var file := FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  ",true,true))
	WarSave.directory = original_directory
	print("LIFE INTEGRATION ",checks," checks, failures=",failures," ms=",result.wallMilliseconds)
	quit(0 if failures.is_empty() else 1)
