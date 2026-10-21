extends SceneTree
const Service = preload("res://scripts/herpes_ambush.gd")
const Sampler = preload("res://scripts/herpes_ambush_animation.gd")
var checks := 0
var failures: Array[String]=[]

class World extends RefCounted:
	var entities: Array=[]
	var hits: Array=[]
	var pushes: Array=[]
	var wall_x := INF
	var legal := true
	var rate := 1.0
	var after_damage := Callable()
	var geometry_calls := 0
	func add(kind: String,faction: int,p: Vector2,lane := 0,category := "unit") -> Dictionary:
		var e := {"id":entities.size()+1,"kind":kind,"category":category,"faction":faction,
			"x":p.x,"y":p.y,"hp":100.0,"vesselLane":lane,"orderToken":0,"orders":[{"kind":"hold"}],"travelSpeed":0.0}
		entities.append(e); return e
	func geometry(a: Vector2,b: Vector2,_lane: int,_source: Dictionary,_target: Dictionary,_purpose: String) -> bool:
		geometry_calls+=1
		return not (is_finite(wall_x) and minf(a.x,b.x)<=wall_x and maxf(a.x,b.x)>=wall_x)
	func site(_p: Vector2,lane: int,_e: Dictionary) -> bool: return legal and lane==0
	func multiplier(_e: Dictionary,_field: String) -> float: return rate
	func damage(source: Dictionary,target: Dictionary,amount: float,direction: Vector2) -> void:
		target.hp=maxf(0,float(target.hp)-amount)
		hits.append({"source":int(source.id),"target":int(target.id),"amount":amount,"direction":[direction.x,direction.y]})
		if after_damage.is_valid(): after_damage.call()
	func push(source: Dictionary,target: Dictionary,direction: Vector2,strength: float) -> void:
		pushes.append({"source":int(source.id),"target":int(target.id),"strength":strength,"direction":[direction.x,direction.y]})
	func bind(service) -> void: service.bind_world(geometry,site,damage,push,multiplier)

func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures.append(label); printerr("FAIL ",label)

func fresh(enemy_distance := 10.0) -> Array:
	var world := World.new(); var service := Service.new(); world.bind(service)
	var actor := world.add("herpes",2,Vector2.ZERO)
	var enemy := world.add("spear",1,Vector2(enemy_distance,0))
	return [world,service,actor,enemy]

func step(world,service,seconds: float) -> void:
	check(service.advance_simulation(seconds,world.entities),"valid independent simulation step")

func roundtrip(world,service) -> Array:
	var copy := World.new(); copy.entities=JSON.parse_string(JSON.stringify(world.entities)); copy.wall_x=world.wall_x; copy.legal=world.legal; copy.rate=world.rate
	var restored := Service.new(); copy.bind(restored)
	var error: String=restored.restore(JSON.parse_string(JSON.stringify(service.snapshot())),copy.entities)
	check(error.is_empty(),"JSON stage restores: "+error)
	return [copy,restored,copy.entities[0],copy.entities[1]]

func art_checks() -> void:
	var d: Dictionary=Service.data()
	check(d.unitKind=="herpes" and d.unitDefinition.hp==100 and d.unitDefinition.speed==.35,"existing herpes identity hp and speed retained")
	check(d.unitDefinition.damage==12 and d.unitDefinition.range==1.5 and d.unitDefinition.cool==4,"first autonomous burst balance")
	check(d.burst.commitAt==.4 and d.burst.releaseFrame==9 and d.burst.knockback==3,"ninth source frame commits once at 400ms")
	check(d.clips.size()==6 and d.radius==WarData.radius("herpes"),"six approved clips and existing collision radius")
	for key in d.clips:
		var clip: Dictionary=d.clips[key]; var at := 0.0
		check(clip.frameCount==16 and clip.frameSize==768 and clip.columns==4 and clip.rows==4,"16 original atlas slots "+key)
		check(clip.anchorX==384 and clip.anchorY==512,"original fixed registration anchor "+key)
		for i in 16:
			check(Sampler.frame_at(clip,at+float(clip.durations[i])*.5,false)==i,"source frame reachable %s/%d"%[key,i+1])
			at+=float(clip.durations[i])
		check(is_equal_approx(at,float(clip.duration)),"original timing sum "+key)
	for record in d.assets: check(FileAccess.get_sha256("res://"+record.path)==record.sha256,"unchanged original art "+record.path)
	var e := {"id":1,"kind":"herpes","hp":100.0}
	for pair in [["active","haMove"],["burrowing","haBurrow"],["dormant","haDormant"],["emerging","haEmerge"],["burst","haBurst"],["hit","haHit"]]:
		check(Sampler.sample(e,{"phase":pair[0],"progress":0},0).key==pair[1],"phase sample "+pair[0])
	check(Sampler.sample(e,{"phase":"dormant"},0).requiresVisibilityGate,"static cyst never overrides enemy visibility")
	check(Sampler.sample(e,{"phase":"burst","progress":.4},0).frame==8,"commit shows ninth painted burst frame")
	check(Sampler.sample(e,{"phase":"burrowing","progress":0,"updatedAt":0},.07).frame==1,"render interpolation can show frames between ten-hertz simulation steps")
	check(Sampler.sample(e,{"phase":"burst","progress":0,"updatedAt":0,"rate":.7},.08).frame==1,"render interpolation respects slowed burst rate")
	e.hp=0; e.herpesDeathAt=0
	check(Sampler.sample(e,{"phase":"death","deathAt":0},2).get("hidden",false),"force hide death residual alpha after two seconds")
	check(Sampler.corpse_duration(.1)==2.1,"full two-second death plus simulation step")
	var hull := Sampler.standing_hull(e,Vector2.ZERO)
	check(hull.size()>=3 and Array(hull).all(func(p): return p.length()<=float(d.radius)+.00001),"neutral hull independent from glow and cyst")
	e.herpesFacingLeft=true
	var flipped := Sampler.standing_hull(e,Vector2.ZERO)
	check(is_equal_approx(flipped[0].x,-hull[0].x),"fixed collision hull mirrors without growing")

func ambush_checks() -> void:
	var f := fresh(); var w=f[0]; var s=f[1]; var e: Dictionary=f[2]; var enemy: Dictionary=f[3]
	step(w,s,2.999); check(s.state_for(1).phase=="active" and not e.concealed,"no premature burrow")
	step(w,s,.001); check(s.state_for(1).phase=="burrowing" and not e.concealed,"three quiet seconds start visible burrow")
	step(w,s,.999); check(s.state_for(1).phase=="burrowing","burrow has full one-second warning")
	step(w,s,.001); check(s.state_for(1).phase=="dormant" and WarDendriticCells.concealed(e),"burrow finishes with existing concealed interface")
	check(not s.allows_movement(e) and e.x==0 and e.y==0 and e.vesselLane==0,"underground changes neither real position nor lane")
	e["marked"]=true; step(w,s,.4)
	check(s.state_for(1).phase=="dormant" and e.burrowed and e.marked,"dendritic mark does not force emergence or get erased")
	enemy.x=2.5; step(w,s,.2)
	check(s.state_for(1).phase=="emerging" and not e.concealed and not e.burrowed,"same-plane radius boundary reveals at emergence start")
	step(w,s,.999); check(s.state_for(1).phase=="emerging","full visible emergence warning")
	step(w,s,.001); check(s.state_for(1).phase=="active" and w.hits.is_empty(),"enemy outside burst radius is not chased by hidden explosion")
	f=fresh(); w=f[0]; s=f[1]; e=f[2]; enemy=f[3]
	step(w,s,4); enemy.x=1; enemy.vesselLane=1; step(w,s,.2)
	check(s.state_for(1).phase=="dormant","overlapping other-plane enemy cannot awaken")
	enemy.vesselLane=0; w.wall_x=.5; step(w,s,.2)
	check(s.state_for(1).phase=="dormant","wall blocks sensing")
	w.wall_x=INF; enemy.hp=0; step(w,s,.2)
	check(s.state_for(1).phase=="dormant","dead enemy cannot awaken")
	enemy.hp=100; enemy.category="building"; step(w,s,.2)
	check(s.state_for(1).phase=="dormant","building alone cannot awaken")
	f=fresh(); w=f[0]; s=f[1]; e=f[2]; enemy=f[3]
	e.vesselLane=1; step(w,s,5)
	check(s.state_for(1).phase=="active" and not e.burrowed,"blood lane never burrows")
	e.vesselLane=0; w.legal=false; step(w,s,5)
	check(s.state_for(1).phase=="active","illegal tissue or gate landing never burrows")
	f=fresh(); w=f[0]; s=f[1]; e=f[2]
	step(w,s,2); e.x=.2; step(w,s,1.5)
	check(s.state_for(1).stationary==0 and s.state_for(1).phase=="active","real movement resets quiet preparation")
	e.travelSpeed=1; step(w,s,4)
	check(s.state_for(1).phase=="active","reported movement prevents stationary burrow")
	e.travelSpeed=0; step(w,s,3.2); s.notify_hit(e)
	check(s.state_for(1).phase=="hit" and not e.burrowed,"hit interrupts unfinished burrow")
	f=fresh(); w=f[0]; s=f[1]; e=f[2]
	step(w,s,4); s.notify_hit(e)
	check(s.state_for(1).phase=="emerging" and not e.concealed,"actual underground damage triggers visible emergence")
	step(w,s,.4); s.notify_hit(e)
	check(is_equal_approx(s.state_for(1).progress,.4),"repeat damage does not restart emergence")
	e.hp=0; s.notify_hit(e)
	check(s.state_for(1).phase=="death" and not e.concealed,"lethal damage takes priority over emergence")
	step(w,s,2); check(Sampler.sample(e,s.state_for(1),s.clock()).get("hidden",false),"lethal underground unit stays dead after full animation")
	var unbound := Service.new()
	check(not unbound.advance_simulation(5,w.entities) and unbound.clock()==0,"missing callbacks fail closed and do not advance")
	check(not unbound.bind_world(w.geometry,w.site,w.damage,Callable()) and not unbound.advance_simulation(1,w.entities),"missing explicit push callback cannot enable a partial module")
	f=fresh(1); w=f[0]; s=f[1]
	s.bind_world(func(_a,_b,_lane,_source,_target,_purpose): return "denied",func(_p,_lane,_e): return "denied",w.damage,w.push)
	step(w,s,5)
	check(w.hits.is_empty() and s.state_for(1).phase=="active","nonboolean geometry and site results fail closed")
	f=fresh(1); w=f[0]; s=f[1]
	s.bind_world(w.geometry,w.site,w.damage,w.push,func(_e,_field): return NAN)
	step(w,s,1)
	check(w.hits.is_empty() and s.state_for(1).progress==0,"nonfinite multiplier freezes attack instead of accelerating it")
	f=fresh(); w=f[0]; s=f[1]; e=f[2]
	step(w,s,2)
	var before: String=JSON.stringify(s.snapshot())
	check(s.advance(20,w.entities,true,2) and JSON.stringify(s.snapshot())==before,"paused wall-time wrapper changes no phase or clock")
	check(s.advance(.5,w.entities,false,2) and s.state_for(1).phase=="burrowing","time scale advances simulated quiet time once")

func burst_checks() -> void:
	var f := fresh(1); var w=f[0]; var s=f[1]; var e: Dictionary=f[2]; var enemy: Dictionary=f[3]
	step(w,s,.399); check(w.hits.is_empty() and s.state_for(1).phase=="burst","active enemy starts burst without instant damage")
	step(w,s,.001); check(enemy.hp==88 and w.hits.size()==1 and w.pushes.size()==1,"400ms submits damage and strong push once")
	check(w.pushes[0].strength==3 and s.state_for(1).committed,"original strong push retained as explicit callback")
	step(w,s,0); step(w,s,.4)
	check(w.hits.size()==1 and s.state_for(1).phase=="active","zero or later sample does not duplicate impact")
	step(w,s,3.199); check(w.hits.size()==1,"four-second cooldown starts at windup")
	step(w,s,.401); check(w.hits.size()==2,"next burst respects full cooldown then windup")
	f=fresh(1); w=f[0]; s=f[1]; e=f[2]; enemy=f[3]
	step(w,s,.2); s.notify_hit(e); step(w,s,.6)
	check(w.hits.is_empty() and s.state_for(1).phase=="hit" and s.state_for(1).cooldown>3,"hit cancels uncommitted burst without refund")
	f=fresh(1); w=f[0]; s=f[1]; e=f[2]
	step(w,s,.2); e.hp=0; s.notify_death(e); step(w,s,1)
	check(w.hits.is_empty() and w.pushes.is_empty() and s.state_for(1).phase=="death","death cancels every pending impact")
	f=fresh(1); w=f[0]; s=f[1]; e=f[2]; enemy=f[3]
	step(w,s,.2); e.orderToken=1; step(w,s,.1)
	check(w.hits.is_empty() and s.state_for(1).castId==1 and not s.state_for(1).committed,"new order cancels old windup without a second cast")
	f=fresh(1); w=f[0]; s=f[1]; e=f[2]; enemy=f[3]
	step(w,s,.2); enemy.x=2; step(w,s,.2)
	check(w.hits.is_empty() and s.state_for(1).committed,"leaving radius dodges pending burst")
	f=fresh(1); w=f[0]; s=f[1]; e=f[2]; enemy=f[3]
	var far: Dictionary=w.add("worker",1,Vector2(1.5,0))
	var other: Dictionary=w.add("worker",1,Vector2(1,0),1)
	var ally: Dictionary=w.add("worker",2,Vector2(1,0))
	var building: Dictionary=w.add("store",1,Vector2(1,0),0,"building")
	step(w,s,.4)
	check(enemy.hp==88 and far.hp==88 and other.hp==100 and ally.hp==100 and building.hp==100,"burst includes exact radius and filters plane faction category")
	f=fresh(.5); w=f[0]; s=f[1]; e=f[2]; enemy=f[3]
	far=w.add("worker",1,Vector2(1.4,0)); w.wall_x=1
	w.after_damage=func(): w.wall_x=INF; s.advance_simulation(.4,w.entities)
	step(w,s,.4); w.after_damage=Callable()
	check(enemy.hp==88 and far.hp==100 and w.hits.size()==1 and w.pushes.size()==1,"pre-impact victim set survives gate break and nested advance without hitting behind it")
	f=fresh(1); w=f[0]; s=f[1]; e=f[2]; enemy=f[3]; w.rate=.7
	step(w,s,.4); check(w.hits.is_empty() and is_equal_approx(s.state_for(1).progress,.28),"dendritic seventy-percent rate delays burst progress")
	step(w,s,.4/.7-.4); check(w.hits.size()==1,"seventy-percent attack commits after scaled windup")
	w.rate=1; step(w,s,.2)
	check(is_equal_approx(s.state_for(1).cooldown,3.4),"rate changes affect remaining cooldown and recovery without resetting")
	f=fresh(1); w=f[0]; s=f[1]
	step(w,s,4.4)
	check(w.hits.size()==2 and w.pushes.size()==2,"coarse simulation step preserves two legitimate cooldown cycles")

func save_checks() -> void:
	for elapsed in [2.0,3.5,4.0]:
		var f := fresh(); var w=f[0]; var s=f[1]
		step(w,s,elapsed); var pair := roundtrip(w,s); var copy=pair[0]; var restored=pair[1]
		check(restored.state_for(1).phase==s.state_for(1).phase and WarDendriticCells.concealed(pair[2])==WarDendriticCells.concealed(f[2]),"quiet/burrow/dormant flags reconstruct without effects")
		check(copy.hits.is_empty() and restored.drain_events().is_empty(),"restore emits no damage or feedback")
	var f := fresh(); var w=f[0]; var s=f[1]; var e: Dictionary=f[2]; var enemy: Dictionary=f[3]
	step(w,s,4); enemy.x=1; step(w,s,.2); step(w,s,.5)
	var pair := roundtrip(w,s); w=pair[0]; s=pair[1]; e=pair[2]; enemy=pair[3]
	check(s.state_for(1).phase=="emerging" and not e.concealed,"saved emergence remains visible")
	step(w,s,.5); step(w,s,.399); check(w.hits.is_empty(),"saved emergence cannot bypass windup")
	step(w,s,.001); check(w.hits.size()==1,"saved emergence has one eventual impact")
	f=fresh(1); w=f[0]; s=f[1]; step(w,s,.2)
	pair=roundtrip(w,s); w=pair[0]; s=pair[1]; step(w,s,.2)
	check(w.hits.size()==1 and w.pushes.size()==1,"saved uncommitted burst commits exactly once")
	var committed: Dictionary=s.snapshot()
	pair=roundtrip(w,s); w=pair[0]; s=pair[1]; step(w,s,.4)
	check(w.hits.is_empty() and w.pushes.is_empty() and s.state_for(1).committed,"saved committed burst cannot replay damage or push")
	f=fresh(1); w=f[0]; s=f[1]; e=f[2]; step(w,s,.2); s.notify_hit(e)
	pair=roundtrip(w,s); w=pair[0]; s=pair[1]; step(w,s,.8)
	check(w.hits.is_empty(),"saved cancelled burst does not resume after hit recovery")
	e=pair[2]; e.hp=0; s.notify_death(e); pair=roundtrip(w,s); step(pair[0],pair[1],2)
	check(pair[0].hits.is_empty() and Sampler.sample(pair[2],pair[1].state_for(1),pair[1].clock()).get("hidden",false),"saved death never returns to live attack")
	for mutation in ["phase","progress","committed","hits","clock","lane","json"]:
		var bad: Dictionary=committed.duplicate(true); var actor: Dictionary=bad.actors["1"]
		match mutation:
			"phase": actor.phase="teleport"
			"progress": actor.progress=INF
			"committed": actor.committed=false
			"hits": actor.hits=[2,2]
			"clock": actor.updatedAt=999
			"lane": actor.phase="dormant"; actor.progress=0; actor.lane=2
			"json": bad["extra"]=Vector2.ONE
		check(not Service.validate_snapshot(bad).is_empty(),"reject invalid save "+mutation)
	var before: String=JSON.stringify(s.snapshot()); var invalid: Dictionary=committed.duplicate(true); invalid.nextCastId=0
	check(not s.restore(invalid,w.entities).is_empty() and JSON.stringify(s.snapshot())==before,"invalid restore is atomic")
	check(not s.advance_simulation(NAN,w.entities) and not s.advance_simulation(-1,w.entities),"invalid clock steps fail closed")

func native_adapter_checks() -> void:
	var game := WarSimulation.new(); game.start("cell_test"); game.state.entities.clear(); game.navigation.blockers.clear()
	var actor := game.spawn("herpes",2,Vector2(100,100)); game.order(actor,{"kind":"hold"})
	var scanner := game.spawn("dendritic_cell",1,Vector2(105,100)); game.order(scanner,{"kind":"hold"})
	var service := Service.new()
	var geometry := func(a,b,lane,source,_target,_purpose): return game.navigation.clear_segment(a,b,lane,source.kind) and game.navigation.movement_clear(a,b,source.kind,int(source.faction))
	var site := func(p,lane,e): return lane==0 and game.navigation.point_allowed(p,lane,e.kind)
	var damage := func(source,target,amount,direction): game.combat.damage(source,target,amount,false,"herpes_burst",direction)
	var push := func(source,target,direction,_strength): game.combat.queue_knockback(source,target,direction,true)
	service.bind_world(geometry,site,damage,push,game.combat.multiplier)
	game.dendritic.refresh(); service.advance_simulation(4,game.entities())
	check(service.state_for(actor.id).phase=="dormant" and game.dendritic.marked(actor,1),"real dendritic scanner marks underground unit without surfacing")
	check(game.dendritic.multiplier(actor,"attackSpeedMultiplier")==.7 and game.dendritic.multiplier(actor,"moveMultiplier")==.7,"real mark keeps both original seventy-percent modifiers")
	service.advance_simulation(.2,game.entities())
	check(actor.burrowed,"real mark alone cannot trigger emerge")
	scanner.hp=0; game.dendritic.refresh()
	check(not game.dendritic.marked(actor,1) and game.combat.multiplier(actor,"attackSpeedMultiplier")==1,"leaving scan restores rate without changing burial")
	var victim := game.spawn("scout",1,Vector2(101.4,100)); game.order(victim,{"kind":"hold"}); victim.plateletLinks=[999]
	service.advance_simulation(.2,game.entities()); service.advance_simulation(1,game.entities()); service.advance_simulation(.4,game.entities())
	var before := WarData.point(victim); game.combat.resolve_knockback()
	var displacement := WarData.point(victim).distance_to(before)
	check(victim.hp<victim.maxHp and displacement>.09 and displacement<=.151,"native platelet wall resists explicit strong push through existing queue")
	victim.hp=0
	var ordinary := game.spawn("worker",1,Vector2(101.4,100)); game.order(ordinary,{"kind":"hold"})
	before=WarData.point(ordinary); game.combat.queue_knockback(actor,ordinary,Vector2.RIGHT,true); game.combat.resolve_knockback()
	check(WarData.point(ordinary).distance_to(before)>2.9 and WarData.point(ordinary).distance_to(before)<=3.001,"native ordinary unit receives original three-unit strong push")
	ordinary.x=101.4; ordinary.y=100
	var blocker := game.spawn("store",2,Vector2(104,100),"building"); game.navigation.blockers=[blocker]
	before=WarData.point(ordinary); game.combat.queue_knockback(actor,ordinary,Vector2.RIGHT,true); game.combat.resolve_knockback()
	displacement=WarData.point(ordinary).distance_to(before)
	check(displacement>.05 and displacement<2 and ordinary.vesselLane==0,"native strong push stops at building geometry and preserves lane")
	check(WarData.is_pathogen("herpes") and WarData.is_virus("herpes"),"existing pathogen and antiviral identity preserved")
	game.dispose()

func run() -> void:
	art_checks(); ambush_checks(); burst_checks(); save_checks(); native_adapter_checks()
	DirAccess.make_dir_recursive_absolute("res://test-output/herpes-ambush")
	var file := FileAccess.open("res://test-output/herpes-ambush/checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"Independent service/approved art/save fixtures plus existing dendritic and push adapters; no shared runtime enablement."},"  "))
	print("HERPES_AMBUSH ",checks-failures.size(),"/",checks)
	quit(0 if failures.is_empty() else 1)
