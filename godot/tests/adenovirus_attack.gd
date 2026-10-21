extends SceneTree
var checks := 0
var failures: Array[String] = []
var hits: Array = []
var pushes: Array = []
var mode := "all"
var service: WarAdenovirusAttack
var navigation := WarNavigation.new()
var callback_probe := false
var atomic_ok := false
var gate_breached := false

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ",label)

func actor(id: int, x := 0.0, faction := 1, kind := "adenovirus", lane := 0, category := "unit") -> Dictionary:
	return {"id":id,"x":x,"y":0.0,"hp":180.0,"faction":faction,"kind":kind,
		"category":category,"vesselLane":lane,"orderToken":0,"hitTime":-1.0}

func fresh() -> WarAdenovirusAttack:
	hits.clear(); pushes.clear(); mode = "all"; callback_probe = false; atomic_ok = false; gate_breached = false
	service = WarAdenovirusAttack.new()
	service.bind_world(damage,geometry,push)
	return service

func damage(source: Dictionary, target: Dictionary, amount: float, info: Dictionary) -> void:
	hits.append({"id":target.id,"amount":amount,"info":info})
	target.hp -= amount
	if mode == "blast_gate" and target.id == 2: gate_breached = true
	if callback_probe:
		atomic_ok = service.snapshot().is_empty() and not service.advance_simulation(0,[]) and not service.restore({}) and service.begin(source,Vector2.ZERO,99) == 0
	if target.kind == "adenovirus": service.notify_hit(target,Vector2(source.x-target.x,0))

func push(_source: Dictionary,target: Dictionary,delta: Vector2,_info: Dictionary) -> void:
	pushes.append({"id":target.id,"delta":delta})
	target.x += delta.x; target.y += delta.y

func geometry(a: Vector2,b: Vector2,lane: int,source: Dictionary,target: Dictionary,purpose: String) -> Variant:
	if mode == "deny": return false
	if mode == "truthy": return 1
	if mode == "impact_deny" and purpose == "impact": return false
	if mode == "wall" and purpose == "target": return false
	if mode == "push_clip" and purpose == "push": return b.x < 1.121
	if mode == "nav": return navigation.clear_segment(a,b,lane,"worker")
	if mode == "gate": return navigation.movement_clear(a,b,"worker",int(source.faction))
	if mode == "blast_gate" and purpose == "target" and target.id == 3: return gate_breached
	return target.is_empty() or int(target.vesselLane) == lane

func run() -> void:
	var s := fresh()
	var source := actor(1)
	var target := actor(2,1.0,2,"worker")
	check(s.tuning().damage == 18 and s.tuning().radius == 2.4 and s.tuning().cooldown == 2.4,"initial combat tuning")
	var definition: Dictionary = WarData.read("adenovirus")
	check(definition.unitSpec.hp == 180 and definition.unitSpec.speed == 1.8 and definition.unitSpec.vision == 9 and definition.unitSpec.pathogen,"candidate spec and pathogen marker")
	check(not definition.battleEnabled,"independent candidate is not admitted to battle")
	var unbound := WarAdenovirusAttack.new()
	check(unbound.begin(source,Vector2.ZERO,1) == 0,"unbound service cannot attack")
	unbound.bind_world(damage,Callable(),push)
	check(unbound.begin(source,Vector2.ZERO,1) == 0,"damage binding without geometry remains closed")
	mode = "truthy"; check(s.begin(source,Vector2.ZERO,1) == 0,"geometry must return bool true")
	mode = "deny"; check(s.begin(source,Vector2.ZERO,1) == 0,"blocked cast does not consume sequence")
	mode = "all"; check(s.begin(source,Vector2(3,0),1) == 0,"cast reach enforced")
	check(s.begin(source,Vector2.ZERO,1) == 1,"legal windup succeeds")
	check(s.begin(source,Vector2.ZERO,1) == 0,"same sequence cannot restart attack")
	var friendly := actor(3,.5,1,"worker")
	var other_lane := actor(4,.5,2,"worker",2)
	var building := actor(5,.5,2,"barracks",0,"building")
	var dead := actor(6,.5,2,"worker"); dead.hp = 0
	var far := actor(7,2.5,2,"worker")
	var world := [source,target,friendly,other_lane,building,dead,far]
	s.advance_simulation(.819,world)
	check(hits.is_empty() and s.presentation(1).warning.visible,"819ms warns without damage")
	var sampled := WarAdenovirusAnimation.new()
	for i in 40: sampled.sample(s.presentation(1),true)
	check(hits.is_empty(),"render sampling cannot produce effects")
	callback_probe = true
	s.advance_simulation(.001,world)
	check(hits.size() == 2 and hits[0].id == 2 and hits[1].id == 5,"820ms damages only hostile same-layer live units and buildings")
	check(target.hp == 162 and building.hp == 162,"single damage is eighteen")
	check(pushes.size() == 1 and is_equal_approx(pushes[0].delta.length(),.35),"only surviving unit receives 0.35 push")
	check(not s.presentation(1).warning.visible and s.presentation(1).cast.resolved,"impact disables warning and commits resolved state")
	check(atomic_ok,"callbacks cannot save, restore, reenter or begin during atomic impact")
	for i in 10: s.advance_simulation(.05,world)
	check(hits.size() == 2,"repeated frames cannot repeat an impact")
	s.notify_hit(source,Vector2.LEFT); s.advance_simulation(2,world)
	check(hits.size() == 2,"post-impact hit cannot repeat or undo damage")
	check(s.begin(source,Vector2.ZERO,1) == 0 and s.begin(source,Vector2.ZERO,2) > 0,"sequence ledger persists after cooldown")

	s = fresh(); source = actor(1); target = actor(2,1,2,"worker")
	s.begin(source,Vector2.ZERO,1); s.advance_simulation(.4,[source,target]); target.x = 3
	check(s.presentation(1).warning.point == [0.0,0.0],"warning remains at fixed real coordinate")
	s.advance_simulation(.42,[source,target]); check(hits.is_empty(),"moving out of the locked region dodges")
	for reason in ["hit","hitTime","order","dead","lane","move","missing"]:
		s = fresh(); source = actor(1); target = actor(2,1,2,"worker")
		s.begin(source,Vector2.ZERO,1); s.advance_simulation(.5,[source,target])
		if reason == "hit": s.notify_hit(source,Vector2.RIGHT)
		if reason == "hitTime": source.hitTime = .5
		if reason == "order": source.orderToken = 1
		if reason == "dead": source.hp = 0
		if reason == "lane": source.vesselLane = 1
		if reason == "move": source.x = .1
		s.advance_simulation(.4,[target] if reason == "missing" else [source,target])
		check(hits.is_empty() and not s.presentation(1).warning.visible,"pre-impact cancellation: "+reason)
	s = fresh(); source = actor(1); target = actor(2,1,2,"worker")
	s.begin(source,Vector2.ZERO,1); s.notify_hit(source,Vector2.LEFT)
	s.advance_simulation(.2,[source,target]); s.notify_hit(source,Vector2.RIGHT)
	check(s.presentation(1).pose == "hit-left" and is_equal_approx(s.presentation(1).elapsed,.2),"hit side and reaction start remain locked")
	check(s.begin(source,Vector2.ZERO,2) == 0,"cannot cast during hit reaction")
	s.advance_simulation(1,[source,target]); check(s.begin(source,Vector2.ZERO,2) == 0,"interrupted attack still consumes cooldown")
	s.advance_simulation(1.2,[source,target]); check(s.begin(source,Vector2.ZERO,2) > 0,"interrupted caster becomes ready at 2.4 seconds")
	s = fresh(); source = actor(1); target = actor(2,1,2,"worker")
	s.begin(source,Vector2.ZERO,1); s.advance(1,[source,target],true,2)
	check(s.clock() == 0 and hits.is_empty(),"pause freezes windup")
	s.advance(.41,[source,target],false,2); check(hits.size() == 1,"time scale uses simulation time")
	s = fresh(); source = actor(1); target = actor(2,1,2,"worker")
	s.begin(source,Vector2.ZERO,1); s.advance_simulation(5,[source,target])
	check(hits.size() == 1 and s.presentation(1).pose == "idle","large delta resolves exactly once and completes recovery")
	s = fresh(); source = actor(1); target = actor(2,1,2,"worker")
	s.begin(source,Vector2.ZERO,1); mode = "impact_deny"; s.advance_simulation(.82,[source,target])
	check(hits.is_empty() and s.presentation(1).cast.resolved,"new obstruction at impact blocks and consumes the impact")
	s = fresh(); source = actor(1); target = actor(2,1,2,"worker")
	s.begin(source,Vector2.ZERO,1); mode = "wall"; s.advance_simulation(.82,[source,target])
	check(hits.is_empty(),"wall occludes target despite radius overlap")
	s = fresh(); source = actor(1); target = actor(2,1,2,"worker")
	s.begin(source,Vector2.ZERO,1); mode = "push_clip"; s.advance_simulation(.82,[source,target])
	check(hits.size() == 1 and is_equal_approx(target.x,1.1),"push clips before a wall instead of tunnelling")

	# Real navigation API with a thin hole, not an endpoint-only or distance-only oracle.
	var rings := [{"outer":PackedVector2Array([Vector2(-5,-5),Vector2(5,-5),Vector2(5,5),Vector2(-5,5)]),
		"holes":[PackedVector2Array([Vector2(.1,-1),Vector2(.2,-1),Vector2(.2,1),Vector2(.1,1)])]}]
	navigation.profiles[WarNavigation.profile("worker")] = {"domains":{41:rings}}
	s = fresh(); source = actor(1,-1,1,"adenovirus",41); target = actor(2,.5,2,"worker",41)
	mode = "nav"
	check(s.begin(source,Vector2(-.5,0),1) > 0,"cast in explicit navigation lane")
	s.advance_simulation(.82,[source,target])
	check(hits.is_empty(),"actual navigation segment check rejects a tissue hole between endpoints")
	s = fresh(); source = actor(1,-1,1,"adenovirus",41); mode = "nav"
	check(s.begin(source,Vector2(.5,0),1) == 0,"windup cannot place locked center across hole")
	navigation.blockers = [actor(99,0,2,"gate",0,"building")]
	check(not navigation.movement_clear(Vector2(-3,0),Vector2(3,0),"worker",1),"existing navigation rejects an unbreached hostile gate")
	s = fresh(); source = actor(1,-3); target = actor(2,1,2,"worker")
	s.begin(source,Vector2(-1,0),1); mode = "gate"; s.advance_simulation(.82,[source,target])
	check(hits.is_empty(),"gate adapter rejects blast crossing the gate")
	s = fresh(); source = actor(1); target = actor(2,.5,2,"gate",0,"building"); target.hp = 1
	var behind_gate := actor(3,1,2,"worker")
	s.begin(source,Vector2.ZERO,1); mode = "blast_gate"; s.advance_simulation(.82,[source,target,behind_gate])
	check(gate_breached and hits.size() == 1 and behind_gate.hp == 180,"gate breached by this impact still shields targets from this same impact")

	s = fresh(); source = actor(1); target = actor(2,1,2,"worker")
	s.begin(source,Vector2.ZERO,1); s.advance_simulation(.4,[source,target])
	var before: Dictionary = JSON.parse_string(JSON.stringify(s.snapshot()))
	var restored := WarAdenovirusAttack.new()
	check(restored.restore(before),"JSON roundtrip restores pre-impact windup")
	check(not restored.advance_simulation(.42,[source,target]) and hits.is_empty(),"restored unbound cast cannot damage")
	restored.bind_world(damage,geometry,push); service = restored
	check(restored.advance_simulation(.42,[source,target]) and hits.size() == 1,"pre-impact restore resolves remaining impact once")
	var after: Dictionary = JSON.parse_string(JSON.stringify(restored.snapshot()))
	check(restored.restore(after) and hits.size() == 1,"load itself produces no effects")
	restored.advance_simulation(.2,[source,target]); check(hits.size() == 1,"post-impact restore cannot replay damage")
	var stable := restored.snapshot()
	for mutation in ["overdue","early_resolved","nan","fraction_id","bad_origin","bad_rule","bad_time","duplicate_cast","bad_hit","unknown_field","overflow_vector"]:
		var bad := before.duplicate(true)
		match mutation:
			"overdue": bad.clock = 1.0
			"early_resolved": bad.sources["1"].cast.resolved = true
			"nan": bad.clock = NAN
			"fraction_id": bad.nextCastId = 1.5
			"bad_origin": bad.sources["1"].cast.origin = [0,"x"]
			"bad_rule": bad.rules.damage = 999
			"bad_time": bad.sources["1"].cast.born = 2
			"duplicate_cast": bad.sources["2"] = bad.sources["1"].duplicate(true)
			"bad_hit": bad.sources["1"].hitAt = -.5
			"unknown_field": bad.sources["1"].injected = "unexpected"
			"overflow_vector": bad.sources["1"].cast.origin = [1e300,1e300]
		check(not restored.restore(bad) and restored.snapshot() == stable,"transactional rejection: "+mutation)
	check(not restored.advance_simulation(.1,[source,target,target]) and restored.snapshot() == stable,"duplicate world IDs rejected before time advances")
	check(not restored.advance_simulation(NAN,[source,target]),"nonfinite delta rejected")
	restored.advance_simulation(.5,[source,target])
	var cooldown_save: Dictionary = JSON.parse_string(JSON.stringify(restored.snapshot()))
	check(restored.restore(cooldown_save) and restored.begin(source,Vector2.ZERO,2) == 0,"cooldown survives a save with no active cast")
	restored.advance_simulation(1,[source,target])
	check(restored.begin(source,Vector2.ZERO,1) == 0 and restored.begin(source,Vector2.ZERO,2) > 0,"restored sequence ledger prevents old attack replay")
	# Simultaneous enemy casters: the first impact interrupts the other's pending cast.
	s = fresh(); source = actor(1); target = actor(2,1,2)
	s.begin(source,Vector2.ZERO,1); s.begin(target,Vector2(1,0),1); s.advance_simulation(.82,[source,target])
	check(hits.size() == 1 and s.presentation(2).pose == "hit-left","damage callback interrupts another caster within the same atomic step")

	for name in definition.clips:
		var clip: Dictionary = definition.clips[name]
		var time := 0.0
		check(ResourceLoader.exists("res://assets/"+str(clip.path)),"original atlas exists: "+name)
		for i in clip.durations.size():
			var result := sampled.sample({"pose":name,"elapsed":time+float(clip.durations[i])*.5})
			check(result.frame == i and not result.mirror and result.rotation == 0 and result.scale == Vector2.ONE,"original frame/front/no procedural scale: "+name+" "+str(i))
			time += float(clip.durations[i])
	check(sampled.sample({"pose":"slam","elapsed":.819}).frame == 8 and sampled.sample({"pose":"slam","elapsed":.82}).frame == 9,"animation impact begins at 820ms")
	check(sampled.sample({"pose":"move","elapsed":1.333}).frame == 0,"jump move loops at original duration")
	check(sampled.sample({"pose":"slam","elapsed":3.0}).frame == 15,"single attack animation clamps rather than looping")
	check(sampled.sample({"pose":"idle","clock":.8},false).frame == 0,"idle does not fabricate breathing or walking")
	check(not sampled.sample({"pose":"death","elapsed":1.599}).hidden and sampled.sample({"pose":"death","elapsed":1.6}).hidden,"death ends without replay")
	s = fresh(); source = actor(1); source.hp = 0; s.notify_death(source)
	s.advance_simulation(.5,[source]); s.notify_death(source)
	check(s.presentation(1).pose == "death" and is_equal_approx(s.presentation(1).elapsed,.5),"repeated death notification does not restart death")
	var death_save: Dictionary = JSON.parse_string(JSON.stringify(s.snapshot()))
	check(s.restore(death_save) and is_equal_approx(s.presentation(1).elapsed,.5),"death pose time survives JSON restore")
	s.advance_simulation(1.1,[source]); check(sampled.sample(s.presentation(1)).hidden,"restored death reaches hidden final state")
	s = fresh(); source = actor(1); s.notify_hit(source,Vector2.LEFT); s.advance_simulation(.3,[source])
	var hit_save: Dictionary = JSON.parse_string(JSON.stringify(s.snapshot()))
	check(s.restore(hit_save) and s.presentation(1).pose == "hit-left" and is_equal_approx(s.presentation(1).elapsed,.3),"locked hit side and time survive JSON restore")
	navigation.dispose()
	DirAccess.make_dir_recursive_absolute("res://test-output/adenovirus")
	FileAccess.open("res://test-output/adenovirus/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"independent service and all 80 original animation frames; no public integration"},"  "))
	print("ADENOVIRUS TESTS ",checks," checks; failures: ",failures)
	quit(0 if failures.is_empty() else 1)
