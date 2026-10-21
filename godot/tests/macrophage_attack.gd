extends SceneTree
var checks := 0
var failures: Array[String] = []
var service: WarMacrophageAttack
var hits: Array = []
var mode := "all"
var speed := 1.0
var target_radius := .4
var source_radius := 1.0625
var receipt_mode := "valid"
var atomic_probe := false
var atomic_ok := false
var navigation := WarNavigation.new()

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ",label)

func actor(id: int, kind := "siege", faction := 1, x := 0.0, hp := 380.0, lane := 0, category := "unit") -> Dictionary:
	return {"id":id,"kind":kind,"faction":faction,"x":x,"y":0.0,"hp":hp,"vesselLane":lane,"category":category,"orderToken":0,"hitTime":-1.0}

func fresh() -> WarMacrophageAttack:
	hits.clear(); mode = "all"; speed = 1.0; target_radius = .4; source_radius = 1.0625
	receipt_mode = "valid"; atomic_probe = false; atomic_ok = false
	service = WarMacrophageAttack.new(); service.bind_world(damage,geometry,radius,attack_speed)
	return service

func damage(source: Dictionary,target: Dictionary,amount: float,info: Dictionary) -> Variant:
	hits.append({"source":source.id,"target":target.id,"amount":amount,"info":info.duplicate(true)})
	var before := float(target.hp)
	target.hp = maxf(0.0,before-amount); target.lastAttacker = int(source.id)
	var receipt := {"sourceId":source.id,"targetId":target.id,"castId":info.castId,"actualDamage":before-target.hp,"killedBySource":target.hp <= 0}
	if receipt_mode == "other_kill": target.lastAttacker = 999; receipt.killedBySource = false
	if receipt_mode == "false_credit": target.lastAttacker = 999
	if receipt_mode == "wrong_cast": receipt.castId += 1
	if receipt_mode == "wrong_damage": receipt.actualDamage += 1
	if receipt_mode == "missing": return null
	if atomic_probe:
		atomic_ok = service.snapshot().is_empty() and not service.restore({}) and not service.advance_simulation(0,[]) and service.begin(source,target,99) == 0
	if target.kind == "siege": service.notify_hit(target)
	return receipt

func geometry(a: Vector2,b: Vector2,lane: int,source: Dictionary,_target: Dictionary,phase: String) -> Variant:
	if mode == "deny": return false
	if mode == "truthy": return 1
	if mode == "bite_blocked" and phase == "bite": return false
	if mode == "nav": return navigation.clear_segment(a,b,lane,"siege")
	if mode == "wall": return navigation.movement_clear(a,b,"siege",int(source.faction))
	return true

func radius(e: Dictionary) -> Variant:
	return source_radius if e.kind == "siege" else target_radius

func attack_speed(_source: Dictionary) -> float:
	return speed

func run() -> void:
	var definition: Dictionary = WarData.read("macrophage")
	check(definition.unitKind == "siege" and not definition.battleEnabled,"candidate is existing siege, not heavy or a newly enabled unit")
	var expected := {"hp":380,"pop":2,"speed":1.3,"vision":11,"cool":3.5,"damage":50,"range":2.2,"train":50,"tier":3,"at":"workshop"}
	for key in expected: check(definition.unitSpec[key] == expected[key],"candidate preserves value: "+key)
	check(definition.unitSpec.cost.food == 25 and definition.unitSpec.cost.wood == 55,"unchanged protein/sugar cost")
	check(definition.proposedChanges.range.to == 2.2,"only proposed global rule change is close range")
	var s := fresh(); var source := actor(1); var target := actor(2,"virus",2,2.0,100.0)
	var unbound := WarMacrophageAttack.new()
	check(unbound.begin(source,target,1) == 0,"no implicit damage without bindings")
	unbound.bind_world(damage,geometry,Callable())
	check(unbound.begin(source,target,1) == 0,"missing radius callback fails closed")
	unbound.bind_world(damage,Callable(),radius)
	check(unbound.begin(source,target,1) == 0,"missing geometry callback fails closed")
	unbound.bind_world(Callable(),geometry,radius)
	check(unbound.begin(source,target,1) == 0,"missing damage callback fails closed")
	mode = "truthy"; check(s.begin(source,target,1) == 0,"truthy non-bool geometry rejected")
	mode = "deny"; check(s.begin(source,target,1) == 0,"blocked windup rejected")
	mode = "all"; target_radius = NAN; check(s.begin(source,target,1) == 0,"nonfinite target radius rejected")
	target_radius = -.1; check(s.begin(source,target,1) == 0,"negative target radius rejected")
	target_radius = .4; source_radius = NAN; check(s.begin(source,target,1) == 0,"invalid source radius rejected")
	source_radius = 1.0625; speed = NAN; check(s.begin(source,target,1) == 0,"invalid unified speed rejected")
	speed = 1; source.kind = "heavy"; check(s.begin(source,target,1) == 0,"heavy identity cannot use macrophage action")
	source.kind = "siege"; target.faction = 1; check(s.begin(source,target,1) == 0,"cannot bite teammate")
	target.faction = 2; target.vesselLane = 1; check(s.begin(source,target,1) == 0,"projected overlap cannot connect layers")
	target.vesselLane = 0; target.x = 2.21; check(s.begin(source,target,1) == 0,"unit centre beyond 2.2 is out of range")
	target.x = 2.2; check(s.begin(source,target,1) == 1,"exact close-range boundary starts attack")
	check(s.begin(source,target,1) == 0,"duplicate sequence rejected")
	s.advance_simulation(.939,[source,target]); check(hits.is_empty(),"no damage before 940ms closure")
	var sampler := WarMacrophageAnimation.new()
	for i in 40: sampler.sample(s.presentation(1),true)
	check(hits.is_empty(),"animation has no damage side effect")
	atomic_probe = true; s.advance_simulation(.001,[source,target])
	check(hits.size() == 1 and hits[0].amount == 50 and target.hp == 50,"closure invokes exactly one real damage50, not an instant kill")
	check(not s.presentation(1).swallowed and target.hp > 0 and not target.has("hidden"),"survivor remains visible and unconsumed")
	check(atomic_ok,"damage transaction blocks save, load and reentry")
	s.advance_simulation(.6,[source,target]); var result := sampler.sample(s.presentation(1))
	check(result.frame == 12,"failed swallow holds clean original closure without painted remnant")
	s.advance_simulation(1.2,[source,target]); check(sampler.sample(s.presentation(1)).frame >= 29,"failed swallow still reaches original recovery")
	s.advance_simulation(.4,[source,target]); check(hits.size() == 1 and s.presentation(1).pose == "idle","recovery does not repeat damage")
	check(s.begin(source,target,2) == 0,"3.5-second cooldown exceeds 3.14-second recovery")
	s.advance_simulation(.36,[source,target]); check(s.begin(source,target,2) > 0,"ready after original cooldown")

	s = fresh(); source = actor(1); target = actor(2,"virus",2,1.0,40.0)
	s.begin(source,target,1); s.advance_simulation(.94,[source,target])
	check(target.hp == 0 and s.presentation(1).swallowed,"real killing bite credits swallow of low-health pathogen")
	var events := s.drain_events()
	check(events.filter(func(e): return e.type == "swallow_success").size() == 1,"one swallow-success event")
	check(not source.has("food") and source.hp == 380 and not target.has("hidden") and not target.has("remnant"),"no resources, healing, hidden victim or remnant entity")
	s.advance_simulation(.36,[source,target]); check(sampler.sample(s.presentation(1)).frame == 15,"successful swallow plays original painted chewing segment")
	s.notify_hit(source); s.advance_simulation(3,[source,target])
	check(hits.size() == 1,"post-bite hit cannot replay damage or success")
	for receipt_case in ["other_kill","false_credit","wrong_cast","wrong_damage","missing"]:
		s = fresh(); source = actor(1); target = actor(2,"virus",2,1,20)
		receipt_mode = receipt_case; s.begin(source,target,1); s.advance_simulation(.94,[source,target])
		check(not s.presentation(1).swallowed,"no swallow without attributable own kill: "+receipt_case)
	for kind in ["worker","unknown_future_pathogen"]:
		s = fresh(); source = actor(1); target = actor(2,kind,2,1,20); target.pathogen = true
		s.begin(source,target,1); s.advance_simulation(.94,[source,target])
		check(not s.presentation(1).swallowed,"only centrally registered pathogen kind can be swallowed: "+kind)
	s = fresh(); source = actor(1); target = actor(2,"barracks",2,3.0,40,0,"building"); target_radius = 1
	check(s.begin(source,target,1) > 0,"building uses real near-surface radius for contact")
	s.advance_simulation(.94,[source,target])
	check(hits.size() == 1 and hits[0].amount == 50 and not s.presentation(1).swallowed,"building receives one base50 and no swallow success")

	for reason in ["hit","hitTime","death","order","source_move","source_layer","source_missing","target_escape","target_layer","target_dead","target_missing","target_friend","target_kind","wall"]:
		s = fresh(); source = actor(1); target = actor(2,"virus",2,1,20)
		s.begin(source,target,1); s.advance_simulation(.5,[source,target])
		match reason:
			"hit": s.notify_hit(source)
			"hitTime": source.hitTime = .5
			"death": source.hp = 0
			"order": source.orderToken += 1
			"source_move": source.x = .2
			"source_layer": source.vesselLane = 1
			"target_escape": target.x = 2.3
			"target_layer": target.vesselLane = 1
			"target_dead": target.hp = 0; target.lastAttacker = 999
			"target_friend": target.faction = 1
			"target_kind": target.kind = "herpes"
			"wall": mode = "bite_blocked"
		var world: Array = [source,target]
		if reason == "source_missing": world = [target]
		if reason == "target_missing": world = [source]
		s.advance_simulation(.44,world)
		check(hits.is_empty() and not s.presentation(1).swallowed,"pre-bite interruption/miss: "+reason)
	s = fresh(); source = actor(1); target = actor(2,"virus",2,1,20)
	var bystander := actor(3,"virus",2,1.1,20)
	s.begin(source,target,1); target.x = 4; s.advance_simulation(.94,[source,target,bystander])
	check(hits.is_empty() and bystander.hp == 20,"fixed target does not retarget a nearby bystander")
	s = fresh(); source = actor(1); target = actor(2,"virus",2,1,20)
	s.begin(source,target,1); s.advance_simulation(.94,[source,target,bystander])
	check(hits.size() == 1 and bystander.hp == 20,"melee is single target, never area damage")

	var rings := [{"outer":PackedVector2Array([Vector2(-5,-5),Vector2(5,-5),Vector2(5,5),Vector2(-5,5)]),
		"holes":[PackedVector2Array([Vector2(.1,-1),Vector2(.2,-1),Vector2(.2,1),Vector2(.1,1)])]}]
	navigation.profiles[WarNavigation.profile("siege")] = {"domains":{41:rings}}
	s = fresh(); source = actor(1,"siege",1,-1,380,41); target = actor(2,"virus",2,.5,20,41); mode = "nav"
	check(s.begin(source,target,1) == 0,"actual navigation segment refuses a thin hole despite valid endpoints")
	navigation.blockers = [actor(99,"barracks",2,0,200,0,"building")]
	s = fresh(); source = actor(1,"siege",1,-1); target = actor(2,"virus",2,1,20); mode = "wall"
	check(s.begin(source,target,1) == 0,"existing building blocker rejects close-range attack")

	s = fresh(); source = actor(1); target = actor(2,"virus",2,1,100)
	speed = 2.0; s.begin(source,target,1); s.advance_simulation(.469,[source,target])
	check(hits.is_empty(),"combined speed2 windup has not bitten at469ms")
	s.advance_simulation(.001,[source,target]); check(hits.size() == 1 and sampler.sample(s.presentation(1)).frame == 11,"combined speed2 bite and frame agree at470ms")
	speed = .7; s.advance_simulation(.1,[source,target])
	check(is_equal_approx(s.snapshot().sources["1"].cooldown,2.49),"cooldown consumes current unified multiplier after buff changes")
	check(is_equal_approx(s.presentation(1).elapsed,1.14),"started action retains original shotSpeed snapshot")
	s = fresh(); source = actor(1); target = actor(2,"virus",2,1,100)
	speed = 2.0*1.25*.7; s.begin(source,target,1); s.advance_simulation(.94/speed,[source,target])
	check(hits.size() == 1,"service accepts host combined B/brain/dendritic multiplier once")
	s = fresh(); source = actor(1); target = actor(2,"virus",2,1,100)
	s.begin(source,target,1); s.advance(2,[source,target],true,4)
	check(s.clock() == 0 and hits.is_empty(),"pause freezes action and cooldown")
	s.advance(.47,[source,target],false,2); check(hits.size() == 1,"time scale applies once")
	s = fresh(); source = actor(1); target = actor(2,"virus",2,1,100)
	s.begin(source,target,1); s.advance_simulation(5,[source,target])
	check(hits.size() == 1 and s.presentation(1).pose == "idle","large fixed step bites once and completes recovery")

	s = fresh(); source = actor(1); target = actor(2,"virus",2,1,40)
	s.begin(source,target,1); s.advance_simulation(.4,[source,target])
	var before: Dictionary = JSON.parse_string(JSON.stringify(s.snapshot()))
	var restored := WarMacrophageAttack.new()
	check(restored.restore(before) and hits.is_empty(),"load before bite has no side effects")
	check(not restored.advance_simulation(.54,[source,target]),"loaded service remains closed before callbacks are rebound")
	restored.bind_world(damage,geometry,radius,attack_speed); service = restored
	restored.advance_simulation(.54,[source,target]); check(hits.size() == 1 and restored.presentation(1).swallowed,"pre-bite save resolves one remaining bite")
	var after: Dictionary = JSON.parse_string(JSON.stringify(restored.snapshot()))
	check(restored.restore(after) and restored.drain_events().is_empty(),"post-bite restore does not re-emit swallow reward/event")
	restored.advance_simulation(.3,[source,target]); check(hits.size() == 1 and restored.presentation(1).swallowed,"post-bite restore keeps chewing without damage replay")
	var stable := restored.snapshot()
	for mutation in ["overdue","early_resolved","nan","fraction_id","bad_vector","rule","speed","unknown","duplicate","false_swallow","building_swallow"]:
		var bad := before.duplicate(true)
		match mutation:
			"overdue": bad.clock = 1
			"early_resolved": bad.sources["1"].cast.resolved = true
			"nan": bad.clock = NAN
			"fraction_id": bad.nextCastId = 1.5
			"bad_vector": bad.sources["1"].cast.origin = [1e300,0]
			"rule": bad.rules.damage = 999
			"speed": bad.sources["1"].cast.speed = -1
			"unknown": bad.sources["1"].injected = true
			"duplicate": bad.sources["3"] = bad.sources["1"].duplicate(true)
			"false_swallow": bad.sources["1"].cast.swallowed = true
			"building_swallow": bad = after.duplicate(true); bad.sources["1"].cast.targetCategory = "building"
		check(not restored.restore(bad) and restored.snapshot() == stable,"transactional save rejection: "+mutation)
	check(not restored.advance_simulation(.1,[source,target,target]) and restored.snapshot() == stable,"duplicate world ID cannot partially advance time")
	speed = NAN; check(not restored.advance_simulation(.1,[source,target]) and restored.snapshot() == stable,"invalid changing multiplier cannot partially update state")
	speed = 1; restored.advance_simulation(2,[source,target])
	var cooling: Dictionary = JSON.parse_string(JSON.stringify(restored.snapshot()))
	target.hp = 100
	check(restored.restore(cooling) and restored.begin(source,target,2) == 0,"remaining cooldown persists after action has ended")
	restored.advance_simulation(.3,[source,target]); check(restored.begin(source,target,1) == 0 and restored.begin(source,target,2) > 0,"restored sequence ledger prevents replay after cooldown")
	s = fresh(); source = actor(1); s.notify_hit(source); s.advance_simulation(.2,[source]); s.notify_hit(source)
	var hit_state: Dictionary = JSON.parse_string(JSON.stringify(s.snapshot()))
	check(s.restore(hit_state) and s.presentation(1).pose == "hit" and is_equal_approx(s.presentation(1).elapsed,.2),"hit notification and save never rewind reaction")
	source.hp = 0; s.notify_death(source); s.advance_simulation(1,[source]); s.notify_death(source)
	var death_state: Dictionary = JSON.parse_string(JSON.stringify(s.snapshot()))
	check(s.restore(death_state) and s.presentation(1).pose == "death" and is_equal_approx(s.presentation(1).elapsed,1),"death notification and save never rewind death")

	for name in definition.clips:
		var clip: Dictionary = definition.clips[name]; var time := 0.0
		check(ResourceLoader.exists(clip.path),"current atlas exists: "+name)
		for i in clip.frames.size():
			result = sampler.sample({"pose":name,"elapsed":time+float(clip.frames[i].duration)*.5,"swallowed":true})
			check(result.frame == i and result.anchor == Vector2(256,440) and not result.mirror and result.scale == Vector2.ONE,"original frame and anchor: "+name+" "+str(i))
			time += float(clip.frames[i].duration)
	check(sampler.sample({"pose":"swallow","elapsed":.939}).frame == 10 and sampler.sample({"pose":"swallow","elapsed":.94}).frame == 11,"visually reviewed first closure is frame12 at940ms")
	check(sampler.sample({"pose":"swallow","elapsed":4,"swallowed":true}).frame == 33,"battle swallowing is single-shot despite source preview loop flag")
	check(sampler.sample({"pose":"chew","elapsed":4,"swallowed":true}).frame == 15,"remnant-only sampling does not loop battle effects")
	check(sampler.sample({"pose":"move","elapsed":1.44}).frame == 0,"move preserves original 1440ms loop")
	for item in [[1.674,false],[1.675,true],[1.795,false],[1.945,true],[2.065,false],[2.215,true],[2.515,true],[5.0,true]]:
		check(sampler.sample({"pose":"death","elapsed":item[0]}).hidden == item[1],"original two-flash death visibility at "+str(item[0]))
	check(not sampler.sample({"pose":"death","elapsed":1.675}).finished and sampler.sample({"pose":"death","elapsed":2.515}).finished,"first invisible flash must not destroy corpse before later flashes")
	navigation.dispose()
	DirAccess.make_dir_recursive_absolute("res://test-output/macrophage")
	FileAccess.open("res://test-output/macrophage/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"independent siege melee candidate; all 99 current display frames; no public integration"},"  "))
	print("MACROPHAGE TESTS ",checks," checks; failures: ",failures)
	quit(0 if failures.is_empty() else 1)
