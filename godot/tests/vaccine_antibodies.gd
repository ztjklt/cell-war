extends SceneTree
const Service=preload("res://scripts/vaccine_antibodies.gd")
var checks:=0
var failures: Array[String]=[]

func _initialize() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures.append(message); printerr("FAIL ",message)
func near(a: float,b: float,message: String,tolerance:=.0001) -> void: check(absf(a-b)<=tolerance,message)

func actor(id: int,p:=Vector2.ZERO,kind:="virus",faction:=2,hp:=100.0,lane:=0) -> Dictionary:
	return {"id":id,"x":p.x,"y":p.y,"kind":kind,"category":"unit","faction":faction,"hp":hp,"vesselLane":lane,"statuses":{}}
func vaccine(id:=101,p:=Vector2.ZERO,lane:=0) -> Dictionary: return actor(id,p,"vaccine",1,90,lane)
func ground(_p,_lane,_owner,_radius): return true
func segment(_a,_b,_lane,_actor): return true
func virus(e): return WarData.is_virus(e.kind)
func damage(_owner,target,amount,_cause,_contact): target.hp=maxf(0,float(target.hp)-amount)
func fixture(overrides: Dictionary={}):
	var value=Service.new(overrides); value.bind_world(damage,ground,segment,virus); value.begin("vaccine-world-0001"); return value
func event(target: Dictionary,serial: int,cause:="attack",amount:=1.0,attacker: Dictionary={}) -> Dictionary:
	var before:=float(target.hp); target.hp=maxf(0,before-amount)
	return {"worldId":"vaccine-world-0001","hitId":serial,"source":actor(201,Vector2(1,0)) if attacker.is_empty() else attacker,"target":target,"damage":minf(amount,before),"hpBefore":before,"cause":cause}
func roundtrip(value: Dictionary) -> Dictionary: return JSON.parse_string(JSON.stringify(value,"",false,true))

func test_configuration_and_trigger() -> void:
	var value=fixture(); var v:=vaccine()
	check(value.ready() and not value.tuning().releaseEnabled,"independent service configured but purchasing remains closed")
	var tune: Dictionary=value.tuning()
	for pair in [["damage",8.0],["dropCooldownSeconds",1.0],["contactRadius",.45],["antibodyLifetimeSeconds",12.0]]: near(tune.values[pair[0]],pair[1],"first adjustable default "+pair[0])
	check(tune.helperProposal.price==120 and tune.helperProposal.health==90 and tune.helperProposal.moveSpeed==2.0 and tune.helperProposal.helperLifetimeSeconds==90,"candidate helper defaults match authorized first pass")
	for rules in [{"damage":NAN},{"contactRadius":0},{"searchStep":0},{"maxPerHelper":13},{"maxAntibodies":129},{"maxEvents":1.5},{"unknown":1}]: check(not Service.new(rules).ready(),"invalid tuning rejected "+str(rules))
	var closed=Service.new(); closed.begin("vaccine-world-0001")
	check(closed.notify_hit(event(v,1))==0 and closed.antibodies().is_empty(),"unbound predicates and damage fail closed")
	var notice:=event(v,1)
	check(value.notify_hit(notice)==1,"real positive enemy attack drops one antibody")
	check(value.antibodies().size()==1,"animation's illustrated two antibodies do not determine gameplay count")
	check(value.notify_hit(notice)==0 and value.last_error()=="duplicate_or_old_hit","same hit serial cannot drop twice")
	check(value.notify_hit(event(v,2))==0 and value.last_error()=="cooldown","second valid hit during one-second cooldown settles without dropping")
	check(value.advance_simulation(1,[],1),"independent simulation clock advances")
	check(value.notify_hit(event(v,3))==2,"fresh actual hit after cooldown drops once")
	check(value.notify_hit(notice)==0,"old hit is not revived when cooldown ends")
	check(value.notify_hit(event(v,2))==0,"cooldown-rejected hit cannot replay later")
	var copy: Array=value.antibodies(); copy[0].x=999
	check(value.antibodies()[0].x!=999,"public drop list cannot mutate service positions")
	var death:=vaccine(102,Vector2(2,0)); death.hp=4
	check(value.notify_hit(event(death,4,"projectile",4))>0 and death.hp==0,"lethal real enemy hit may drop a final antibody")
	check(value.advance_simulation(.1,[],2) and value.antibodies().size()==3,"source disappearance and death do not clear its ground antibodies")
	value.dispose(); closed.dispose()

func test_rejected_hits() -> void:
	for cause in ["burn","slow","poison","bleed","expired","medicine_expired","vaccine_antibody","medicine_bubble","environment","self","animation"]:
		var value=fixture(); check(value.notify_hit(event(vaccine(),1,cause))==0 and value.antibodies().is_empty(),"excluded cause "+cause); value.dispose()
	for cause in ["attack","projectile","collision"]:
		var value=fixture(); check(value.notify_hit(event(vaccine(),1,cause))==1,"explicit active-attack whitelist "+cause); value.dispose()
	for mutation in ["zero","self","ally","neutral","building","wrong_kind","no_hp_before","inconsistent_hp","old_world","fractional_id","nan_damage"]:
		var value=fixture(); var v:=vaccine(); var notice:=event(v,1)
		match mutation:
			"zero": notice.damage=0; notice.hpBefore=v.hp
			"self": notice.source=v.duplicate(true)
			"ally": notice.source.faction=1
			"neutral": notice.source.faction=0
			"building": notice.source.category="building"
			"wrong_kind": notice.target.kind="worker"
			"no_hp_before": notice.erase("hpBefore")
			"inconsistent_hp": notice.target.hp=20
			"old_world": notice.worldId="vaccine-old-world"
			"fractional_id": notice.hitId=1.5
			"nan_damage": notice.damage=NAN
		check(value.notify_hit(notice)==0 and value.antibodies().is_empty(),"invalid real-hit contract rejected "+mutation); value.dispose()
	var value=fixture(); var dead_attacker:=actor(201); dead_attacker.hp=0
	check(value.notify_hit(event(vaccine(),1,"projectile",1,dead_attacker))>0,"previously emitted enemy projectile may be valid after its attacker dies")
	value.dispose()

func test_ground_and_caps() -> void:
	var value=fixture(); var v:=vaccine(101,Vector2(8,6),3)
	var seen: Array=[]
	value.bind_world(damage,func(p,lane,_owner,radius):
		seen.append([p,lane,radius]); return p.distance_to(Vector2(8.25,6))<.001,segment,virus)
	check(value.notify_hit(event(v,1))==1,"bounded nearby ground search finds legal same-layer point")
	var drop: Dictionary=value.antibodies()[0]
	check(Vector2(drop.x,drop.y).distance_to(Vector2(8.25,6))<.001 and drop.vesselLane==3,"nearby result uses actual anchor position and exact source lane")
	check(seen.all(func(call): return call[1]==3 and is_equal_approx(call[2],.45)),"ground callback gets actual lane and authorized contact radius")
	value.dispose(); value=fixture()
	var probes: Array=[]
	value.bind_world(damage,func(p,_lane,_owner,_radius): probes.append(p); return false,segment,virus)
	check(value.notify_hit(event(vaccine(),1))==0,"no certified ground means no drop")
	check(probes.size()<=81 and probes.all(func(p): return p.length()<=1.2501),"failed search is finite and stays within1.25 units")
	value.bind_world(damage,ground,segment,virus)
	check(value.notify_hit(event(vaccine(),1))==0,"ground failure settles hit serial and cannot be retried after geometry changes")
	value.dispose(); value=fixture()
	value.bind_world(damage,ground,func(_a,_b,_lane,_owner): return false,virus)
	check(value.notify_hit(event(vaccine(),1))==0,"segment rejection prevents dropping across a wall despite legal endpoint")
	value.bind_world(damage,func(_p,_l,_o,_r): return "true",segment,virus)
	check(value.notify_hit(event(vaccine(),2))==0,"truthy non-boolean ground does not authorize placement")
	value.dispose(); value=fixture({"dropCooldownSeconds":0.0})
	for serial in 12: check(value.notify_hit(event(vaccine(),serial+1))>0,"one helper can accumulate independent antibody "+str(serial+1))
	var before: Array=value.antibodies()
	check(value.notify_hit(event(vaccine(),13))==0 and value.antibodies()==before,"per-helper cap12 never overwrites existing antibodies")
	for serial in range(13,129):
		var owner_id:=102+int((serial-13)/12)
		value.notify_hit(event(vaccine(owner_id,Vector2(owner_id,0)),serial+1))
	check(value.antibodies().size()==128,"global antibody capacity reaches128 across helpers")
	before=value.antibodies()
	check(value.notify_hit(event(vaccine(999),1000))==0 and value.antibodies()==before,"global cap128 fails without eviction")
	value.dispose()

func test_contact_sweep_and_layers() -> void:
	var value=fixture(); var v:=vaccine(); value.notify_hit(event(v,1))
	var target:=actor(1,Vector2(-3,0))
	check(value.advance_simulation(0,[target],1),"prime a real target's committed position")
	target.x=3
	check(value.advance_simulation(.1,[target],2),"fast virus crossing whole antibody is swept")
	near(target.hp,92,"fast crossing deals8 damage once")
	check(value.antibodies().is_empty(),"first legal virus contact atomically consumes the antibody")
	check(not value.advance_simulation(.1,[target],2) and target.hp==92,"duplicate host tick cannot replay damage or age clock")
	check(value.advance_simulation(.1,[target],3) and target.hp==92,"later frames cannot replay consumed contact")
	var contacts: Array=value.drain_events().filter(func(e): return e.kind=="antibody_contact")
	check(contacts.size()==1 and contacts[0].contactId=="vaccine-world-0001:antibody:1","one observational contact event with a stable committed contact identity")
	value.dispose()
	for variant in ["ally","bacterium","unknown_pathogen","other_lane","dead","building"]:
		value=fixture(); value.notify_hit(event(vaccine(),1)); target=actor(1)
		match variant:
			"ally": target.faction=1
			"bacterium": target.kind="helicobacter"
			"unknown_pathogen": target.kind="shadow"
			"other_lane": target.vesselLane=2
			"dead": target.hp=0
			"building": target.category="building"
		value.advance_simulation(.1,[target],1)
		check(value.antibodies().size()==1,"noneligible overlap preserves antibody: "+variant); value.dispose()
	value=fixture(); value.notify_hit(event(vaccine(),1)); target=actor(1,Vector2(-3,0))
	value.advance_simulation(0,[target],1); target.x=3; target.vesselLane=2
	value.advance_simulation(.1,[target],2)
	check(target.hp==100 and value.antibodies().size()==1,"untraced layer change does not connect projected crossing")
	value.dispose(); value=fixture(); value.notify_hit(event(vaccine(),1)); target=actor(1,Vector2(-3,0))
	value.advance_simulation(0,[target],1); target.x=3
	var path: Dictionary={"1":[{"from":Vector2(-3,0),"to":Vector2(-3,2),"lane":0,"start":0.0,"end":.3},{"from":Vector2(-3,2),"to":Vector2(3,2),"lane":0,"start":.3,"end":.7},{"from":Vector2(3,2),"to":Vector2(3,0),"lane":0,"start":.7,"end":1.0}]}
	check(value.advance_simulation(.1,[target],2,path) and target.hp==100,"verified bent path avoids a false straight-line contact")
	value.dispose(); value=fixture(); value.notify_hit(event(vaccine(),1)); target=actor(1,Vector2(-3,0))
	value.advance_simulation(0,[target],1); target.x=3
	value.bind_world(damage,ground,func(a,b,_lane,_actor): return not (a.x<-.5 and b.x>-.5),virus)
	value.advance_simulation(.1,[target],2)
	check(target.hp==100 and value.antibodies().size()==1,"wall before antibody blocks swept contact")
	value.dispose()
	# Same instant: deterministic lower target id; dead target is skipped for later drops.
	value=fixture({"dropCooldownSeconds":0.0}); value.notify_hit(event(vaccine(),1)); value.notify_hit(event(vaccine(),2))
	var a:=actor(1,Vector2.ZERO,"herpes",2,8); var b:=actor(2)
	value.advance_simulation(.1,[b,a],1)
	check(a.hp==0 and b.hp==92 and value.antibodies().is_empty(),"two drops each consume once; second skips newly dead first target")
	value.dispose()

func test_pause_expiry_and_save() -> void:
	var value=fixture(); var v:=vaccine(); value.notify_hit(event(v,1))
	var initial: Dictionary=value.snapshot()
	v.x=99; v.y=88
	check(value.advance(5,[v],1,true,2) and value.snapshot()==initial,"pause freezes age cooldown and positions")
	check(value.advance(.5,[],1,false,2),"2x adapter advances one simulation second")
	near(value.clock(),1,"one clock authority at2x")
	var drop: Dictionary=value.antibodies()[0]
	check(drop.x==0 and drop.y==0,"owner movement and release animation never move the ground object")
	value.advance_simulation(10.9,[],2)
	check(value.antibodies().size()==1,"antibody persists until actual12-second expiry")
	value.advance_simulation(.1,[],3)
	check(value.antibodies().is_empty(),"antibody expires at12 simulation seconds")
	value.dispose()
	# Cross before expiry inside a large tick still hits; at expiry does not.
	value=fixture(); value.notify_hit(event(vaccine(),1)); var target:=actor(1,Vector2(-3,0))
	value.advance_simulation(0,[target],1); target.x=3
	value.advance_simulation(20,[target],2)
	check(target.hp==92,"large tick uses contact time before expiry, not end-of-tick age")
	value.dispose(); value=fixture(); value.notify_hit(event(vaccine(),1)); target=actor(1,Vector2(-3,0))
	value.advance_simulation(11.95,[target],1); target.x=3
	value.advance_simulation(1,[target],2)
	check(target.hp==100 and value.antibodies().is_empty(),"crossing after expiry cannot resurrect damage")
	value.dispose()
	value=fixture(); value.notify_hit(event(vaccine(),1))
	value.advance_simulation(11.95,[],1); target=actor(1)
	value.advance_simulation(.1,[target],2)
	check(target.hp==100,"first-observed endpoint does not fabricate presence before expiry")
	value.dispose(); value=fixture(); value.notify_hit(event(vaccine(),1))
	value.advance_simulation(11.95,[],1); target=actor(1)
	var spawn_path: Dictionary={"1":[{"from":Vector2.ZERO,"to":Vector2.ZERO,"lane":0,"start":.8,"end":1.0}]}
	value.advance_simulation(.1,[target],2,spawn_path)
	check(target.hp==100,"explicit late-spawn fraction cannot hit an already expired antibody")
	value.dispose(); value=fixture(); target=actor(1,Vector2(-3,0))
	check(value.begin("vaccine-world-0001",0,[target]),"begin can seed actual initial positions without committing a fake tick")
	value.notify_hit(event(vaccine(),1)); target.x=3; value.advance_simulation(.1,[target],1)
	check(target.hp==92,"seeded first actual tick sweeps movement without a separate prime update")
	value.dispose()
	value=fixture(); var notice:=event(vaccine(),10); value.notify_hit(notice); target=actor(1,Vector2(-2,0))
	value.advance_simulation(.25,[target],7)
	initial=value.snapshot(); var loaded=fixture()
	check(Service.validate_snapshot(roundtrip(initial)).is_empty() and loaded.restore(roundtrip(initial)),"independent snapshot JSON validates and restores transactionally")
	check(loaded.snapshot()==initial and loaded.drain_events().is_empty(),"restore preserves drops cooldown serials and positions without replay events")
	check(loaded.notify_hit(notice)==0,"restored hit high-water mark prevents duplicate drop")
	check(not loaded.advance_simulation(.25,[target],7),"restored step commit prevents duplicate simulation tick")
	target.x=2; loaded.advance_simulation(.25,[target],8)
	near(target.hp,92,"restored prior position still sweeps an actual fast crossing")
	var after:=loaded.snapshot(); var spent=fixture(); spent.restore(roundtrip(after))
	check(spent.antibodies().is_empty() and not spent.advance_simulation(.25,[target],8) and target.hp==92,"saved consumed object and committed tick never replay damage")
	var late:=event(vaccine(),11); loaded.begin("vaccine-world-0002")
	check(loaded.antibodies().is_empty() and loaded.notify_hit(late)==0,"new world drops old objects and rejects old-world notifications")
	for field in ["negative_clock","bad_next_id","nan_position","bad_lane","extra_drop","wrong_owner","bad_lifetime","fractional_step","bad_rules","bad_source"]:
		var bad:=initial.duplicate(true)
		match field:
			"negative_clock": bad.clock=-1
			"bad_next_id": bad.nextAntibodyId=1
			"nan_position": bad.antibodies[0].x=NAN
			"bad_lane": bad.antibodies[0].vesselLane=2
			"extra_drop": bad.antibodies.append(bad.antibodies[0].duplicate(true))
			"wrong_owner": bad.antibodies[0].owner.kind="worker"
			"bad_lifetime": bad.antibodies[0].expiresAt=999
			"fractional_step": bad.lastStepId=1.5
			"bad_rules": bad.rules.damage=-8
			"bad_source": bad.sources.clear()
		var before: Dictionary=spent.snapshot()
		check(not spent.restore(bad) and spent.snapshot()==before,"invalid snapshot leaves state intact: "+field)
	value.dispose(); loaded.dispose(); spent.dispose()

func test_callbacks_motion_and_sampling() -> void:
	var value=fixture(); value.notify_hit(event(vaccine(),1)); var target:=actor(1)
	value.bind_world(damage,ground,segment,func(_e): return "true")
	check(value.advance_simulation(.1,[target],1) and target.hp==100,"nonboolean virus classification fails closed")
	value.bind_world(Callable(),ground,segment,virus)
	check(not value.advance_simulation(.1,[target],2) and value.antibodies().size()==1,"missing damage callback cannot consume an antibody")
	value.bind_world(damage,ground,segment,virus)
	var before: Dictionary=value.snapshot()
	check(not value.advance_simulation(.1,[target,target],2) and value.snapshot()==before,"duplicate actor ids reject entire step")
	var bad_path: Dictionary={"1":[{"from":Vector2.ZERO,"to":Vector2.ONE,"lane":0,"start":.2,"end":1.0}]}
	check(not value.advance_simulation(.1,[target],2,bad_path) and value.snapshot()==before,"incomplete motion rejects transaction before time or damage")
	var observations: Array=[]
	value.bind_world(func(_o,t,amount,_cause,_id):
		t.hp-=amount; observations.append(value.snapshot().is_empty()); observations.append(not value.advance_simulation(.1,[t],3)); observations.append(value.antibodies().is_empty()),ground,segment,virus)
	check(value.advance_simulation(.1,[target],2) and observations==[true,true,true] and target.hp==92,"contact commits consumption before callback and blocks reentrant save or advance")
	value.dispose()
	# Explicit host classification extension: registered virus only, never name guessing.
	WarData.config().Data.units.vaccine_test_virus={"pathogen":true,"pathogenFamily":"virus"}
	value=fixture(); value.notify_hit(event(vaccine(),1)); target=actor(1,Vector2.ZERO,"vaccine_test_virus")
	value.advance_simulation(.1,[target],1)
	check(target.hp==92,"host WarData.is_virus callback explicitly extends future registered viruses")
	WarData.config().Data.units.erase("vaccine_test_virus"); value.dispose()
	value=fixture(); var v:=vaccine(); v.hitTime=0; value.notify_hit(event(v,1))
	var clips: Dictionary=Service.data().clips
	for key in ["move","hit","release","death"]:
		check(clips[key].durations.size()==16 and ResourceLoader.exists("res://assets/"+clips[key].path),"existing approved16-frame atlas available: "+key)
		check(Service.frame(clips[key],0,false)==0 and Service.frame(clips[key],clips[key].duration+1,false)==15,"sample first/last frame of "+key)
	check(value.sample_actor(v,.2,0,false).key=="hit","actual hit timestamp samples hit independently")
	check(value.sample_actor(v,clips.hit.duration+.2,0,false).key=="release","successful drop schedules release visual after hit")
	check(value.antibodies().size()==1,"sampling hit/release never generates additional drops")
	v.died=.2; check(value.sample_actor(v,.4,0,true).key=="death","death overrides pending release visual")
	check(value.sample_actor(v,3,0,true).get("hidden",false),"death visual finishes after approved clip")
	var visual: Dictionary=value.sample_antibody(1)
	check(visual.x==0 and visual.y==0 and ResourceLoader.exists("res://assets/"+visual.visual.path),"independent ground sample uses existing antibody image at fixed position")
	check(value.sample_antibody(999).get("hidden",false),"unknown ground sample stays hidden")
	check(value.sample_actor(v,clips.hit.duration+.2,0,false).containsIllustratedDrops and clips.release.embeddedAntibodyIllustrationCount==2,"candidate marks the two embedded release illustrations as a future body-isolation gate")
	check(not Service.data().releaseEnabled,"candidate data does not open vaccination sales")
	var item: Dictionary=WarData.read("medicines").entries.filter(func(e): return e.id=="vaccine")[0]
	check(not item.purchase.canSell and not item.purchase.canDeploy and not item.actualEffect.runtimeImplemented,"shared catalogue remains unimplemented and closed for vaccine")
	value.dispose()

func run() -> void:
	test_configuration_and_trigger(); test_rejected_hits(); test_ground_and_caps(); test_contact_sweep_and_layers(); test_pause_expiry_and_save(); test_callbacks_motion_and_sampling()
	DirAccess.make_dir_recursive_absolute("res://test-output/vaccine")
	FileAccess.open("res://test-output/vaccine/antibodies.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":checks-failures.size(),"total":checks,"failures":failures,"scope":"independent_candidate_only","engine":Engine.get_version_info().string},"  "))
	print("VACCINE ANTIBODIES ",checks-failures.size(),"/",checks," ",failures)
	quit(0 if failures.is_empty() else 1)
