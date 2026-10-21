extends SceneTree
const Service = preload("res://scripts/pneumococcus.gd")
const Sampler = preload("res://scripts/pneumococcus_animation.gd")
var checks := 0
var failures: Array[String] = []

class TestNavigation extends RefCounted:
	var wall_x := INF
	func clear_segment(a: Vector2,b: Vector2,_lane: int,_kind: String) -> bool:
		return not (is_finite(wall_x) and minf(a.x,b.x) <= wall_x and maxf(a.x,b.x) >= wall_x)

class TestCombat extends RefCounted:
	var hits: Array = []
	var rate := 1.0
	var after_damage := Callable()
	func multiplier(_e: Dictionary,_field: String) -> float: return rate
	func _target_geometry(target: Dictionary,lane: int) -> Dictionary:
		var side: Array = target.get("gateSides",{}).get(str(lane),[])
		return {"point":Vector2(side[0],side[1]) if side.size()==2 else WarData.point(target),
			"lane":lane if side.size()==2 else int(target.vesselLane),"radius":float(target.get("collisionSize",2))*.5}
	func damage(source: Dictionary,target: Dictionary,amount: float,_raw: bool,_cause: String,direction: Vector2) -> void:
		if target.hp <= 0: return
		target.hp = maxf(0,float(target.hp)-amount)
		hits.append({"source":source.id,"target":target.id,"amount":amount,"direction":[direction.x,direction.y]})
		if after_damage.is_valid(): after_damage.call()

class TestGame extends RefCounted:
	var state := {"time":0.0,"entities":{}}
	var paused := false
	var navigation := TestNavigation.new()
	var combat := TestCombat.new()
	var events: Array = []
	func entity(id: int) -> Dictionary: return state.entities.get(str(id),{})
	func entities() -> Array: return state.entities.values()
	func event(kind: String,fields: Dictionary) -> void: events.append({"kind":kind,"fields":fields.duplicate(true)})
	func add(kind: String,faction: int,p: Vector2,category := "unit",lane := 0) -> Dictionary:
		var id: int = state.entities.size()+1
		var e := {"id":id,"kind":kind,"category":category,"faction":faction,"x":p.x,"y":p.y,
			"hp":120.0 if kind=="pneumococcus" else 100.0,"vesselLane":lane,"orderToken":0,"statuses":{}}
		if category=="building": e.collisionSize = 2.0
		state.entities[str(id)] = e
		return e

func _initialize() -> void: call_deferred("run")

func check(value: bool,label: String) -> void:
	checks += 1
	if not value: failures.append(label); printerr("FAIL ",label)

func fresh(p := Vector2(4,0)) -> Array:
	var game := TestGame.new(); var service := Service.new(game)
	var source := game.add("pneumococcus",2,Vector2.ZERO)
	var target := game.add("worker",1,p)
	return [game,service,source,target]

func advance(game,service,time: float) -> void:
	game.state.time = time; service.step()

func saved_copy(game,service) -> Array:
	var copy := TestGame.new()
	copy.state = JSON.parse_string(JSON.stringify(game.state))
	var restored := Service.new(copy)
	check(restored.restore(JSON.parse_string(JSON.stringify(service.snapshot()))).is_empty(),"JSON save restore validates")
	return [copy,restored]

func event_count(game,kind: String) -> int:
	return game.events.filter(func(e): return e.kind==kind).size()

func art_checks() -> void:
	var data: Dictionary = Service.data()
	check(data.unit.hp==120 and data.unit.range==7 and data.unit.damage==12 and data.unit.cool==1.8 and data.unit.speed==2.1,"authorized first-balance unit spec")
	check(data.unit.pathogen and data.projectile.speed==12 and data.projectile.ttl==.85,"candidate pathogen protocol and projectile balance")
	check(data.projectile.releaseFrame==9 and data.projectile.windup==.667,"frame nine is exactly 667ms at baseline")
	check(data.clips.size()==6,"six clips are separate, including independent projectile")
	var e := {"id":0,"kind":"pneumococcus","hp":120.0}
	for key in data.clips:
		var clip: Dictionary = data.clips[key]
		check(clip.frameCount==16 and clip.durations.size()==16,"16 timings in "+key)
		check(clip.columns==4 and clip.rows==4 and clip.frameSize==512,"4x4 atlas contract in "+key)
		check(data.outlines[key].size()==16,"16 outline slots in "+key)
		var elapsed := 0.0
		for i in 16:
			var t: float = elapsed+float(clip.durations[i])*.5
			check(Sampler.frame_at(clip,t,false)==i,"reachable source frame %s/%d"%[key,i+1])
			elapsed += float(clip.durations[i])
		check(is_equal_approx(elapsed,float(clip.duration)),"duration sum in "+key)
	for asset in data.assets:
		check(FileAccess.file_exists("res://"+asset.path) and FileAccess.get_sha256("res://"+asset.path)==asset.sha256,"approved PNG unchanged "+asset.path)
	var death := Image.new()
	check(death.load_png_from_buffer(FileAccess.get_file_as_bytes("res://assets/"+str(data.clips.pnDeath.path)))==OK,"source death atlas decodes")
	check(death.get_region(Rect2i(1536,1536,512,512)).get_used_rect().size==Vector2i.ZERO,"death frame sixteen fully transparent")
	check(Sampler.sample(e,10,0,false).frame==0,"standing unit does not walk")
	e.pneumoShotAt = 0.0; e.pneumoShotSpeed = 1.0
	check(Sampler.sample(e,.667,0,false).key=="pnShoot" and Sampler.sample(e,.667,0,false).frame==8,"release samples ninth source frame")
	e.pneumoHitAt = .2; e.pneumoHitSide = "left"
	check(Sampler.sample(e,.3,0,false).key=="pnHitLeft","hit takes priority over spit")
	e.pneumoDeathAt = .25
	check(Sampler.sample(e,.3,0,true).key=="pnDeath","death takes priority over hit")
	check(Sampler.sample(e,1.85,0,true).get("hidden",false) and Sampler.sample(e,100,1,true).get("hidden",false),"death stays hidden after 1.6s")
	check(is_equal_approx(Sampler.corpse_duration(.1),1.7),"corpse includes full death plus simulation step")
	e = {"id":0,"kind":"pneumococcus","pneumoShotAt":0.0,"pneumoShotCancelled":true}
	check(Sampler.sample(e,.8,0,false).key=="pnMove","cancelled spit cannot resume after hit")
	check(Sampler.sample(e,20,1,false).angle==0,"body never inherits generic continuous spin")
	var hull := Sampler.standing_hull(e,Vector2.ZERO)
	check(hull.size()>=3 and Array(hull).all(func(p): return p.length()<=.72001),"static neutral hull fits actual body radius")
	e.pneumoFacingLeft = true
	var mirrored := Sampler.standing_hull(e,Vector2.ZERO)
	check(is_equal_approx(mirrored[0].x,-hull[0].x) and is_equal_approx(mirrored[0].y,hull[0].y),"standing hull follows mirror without effects")
	check(Sampler.projectile_sample({"born":0},.2).key=="pnProjectile","projectile has its independent sampler")

func combat_checks() -> void:
	var f := fresh(); var g = f[0]; var s = f[1]; var e: Dictionary = f[2]; var t: Dictionary = f[3]
	check(s.try_attack(e,t),"baseline shot starts")
	advance(g,s,.666)
	check(s.projectiles().is_empty() and g.combat.hits.is_empty(),"no early launch or instant melee damage")
	advance(g,s,.667)
	check(s.projectiles().size()==1 and event_count(g,"pneumococcus_projectile_spawn")==1,"exactly one launch at 667ms")
	check(s.state().casts.is_empty() and g.combat.hits.is_empty(),"release is not impact damage")
	advance(g,s,.667)
	check(s.projectiles().size()==1 and event_count(g,"pneumococcus_projectile_spawn")==1,"same timestamp cannot release twice")
	advance(g,s,1.2); advance(g,s,1.3)
	check(t.hp==88 and g.combat.hits.size()==1 and s.projectiles().is_empty(),"one projectile deals twelve once")
	advance(g,s,1.79)
	check(not s.try_attack(e,t),"cooldown excludes before 1.8s")
	advance(g,s,1.8)
	check(s.try_attack(e,t),"cooldown allows next shot at 1.8s")
	f=fresh(Vector2(7.001,0)); g=f[0]; s=f[1]; e=f[2]; t=f[3]
	check(not s.try_attack(e,t),"range excludes outside seven")
	t.x=7.0; check(s.try_attack(e,t),"range includes seven")
	f=fresh(); g=f[0]; s=f[1]; e=f[2]; t=f[3]; t.vesselLane=2
	check(not s.try_attack(e,t),"cannot acquire a target on another plane")
	t.vesselLane=0; g.navigation.wall_x=2
	check(not s.try_attack(e,t),"wall prevents acquisition")
	f=fresh(Vector2(6,0)); g=f[0]; s=f[1]; e=f[2]; t=f[3]
	s.try_attack(e,t); advance(g,s,.667); t.y=3
	var direction: Dictionary=s.projectiles()[0].duplicate(true)
	advance(g,s,.9)
	check(s.projectiles()[0].dx==direction.dx and s.projectiles()[0].dy==direction.dy,"flight direction never tracks moving target")
	advance(g,s,2)
	check(t.hp==100 and s.projectiles().is_empty() and s.state().recent[-1].outcome=="expired","miss expires after .85s with no damage")
	f=fresh(Vector2(6,0)); g=f[0]; s=f[1]; e=f[2]; t=f[3]
	var block: Dictionary=g.add("store",2,Vector2(3,0),"building")
	s.try_attack(e,t); advance(g,s,1.3)
	check(g.combat.hits.is_empty() and block.hp==100 and t.hp==100 and s.projectiles().is_empty(),"friendly building blocks without friendly damage")
	check(s.state().recent[-1].outcome=="blocked","friendly building consumes projectile once")
	f=fresh(Vector2(6,0)); g=f[0]; s=f[1]; e=f[2]; t=f[3]
	g.add("store",2,Vector2(3,0),"building",1)
	g.add("worker",2,Vector2(2,0))
	s.try_attack(e,t); advance(g,s,1.3)
	check(g.combat.hits.size()==1 and t.hp==88,"other-plane building and friendly unit do not intercept")
	f=fresh(Vector2(6,0)); g=f[0]; s=f[1]; e=f[2]; t=f[3]
	s.try_attack(e,t); advance(g,s,.667); g.navigation.wall_x=2
	advance(g,s,1.3)
	check(t.hp==100 and s.projectiles().is_empty() and s.state().recent[-1].outcome=="blocked","wall appearing in flight blocks coarse-step projectile")
	f=fresh(Vector2(6,0)); g=f[0]; s=f[1]; e=f[2]; t=f[3]
	s.try_attack(e,t); advance(g,s,.667); t.vesselLane=1
	advance(g,s,2)
	check(t.hp==100,"target changing plane cannot be struck")
	f=fresh(); g=f[0]; s=f[1]; e=f[2]; t=f[3]
	s.try_attack(e,t); advance(g,s,.2); s.notify_hit(e,Vector2.RIGHT); advance(g,s,.8)
	check(s.projectiles().is_empty() and s.state().casts.is_empty() and e.pneumoShotCancelled,"hit interrupts before emission")
	check(e.pneumoHitSide=="left","rightward push selects left incoming hit")
	e.pneumoFacingLeft=true; advance(g,s,1.3); s.notify_hit(e,Vector2.RIGHT)
	check(e.pneumoHitSide=="right","mirroring changes incoming side in local art")
	advance(g,s,2.4); s.notify_hit(e,Vector2.LEFT)
	check(e.pneumoHitSide=="left","opposite push plus mirror selects left local art")
	e.pneumoFacingLeft=false; advance(g,s,3.5); s.notify_hit(e,Vector2.LEFT)
	check(e.pneumoHitSide=="right","unmirrored leftward push selects right incoming art")
	f=fresh(); g=f[0]; s=f[1]; e=f[2]; t=f[3]
	s.try_attack(e,t); advance(g,s,.2); e.hp=0; s.notify_death(e); advance(g,s,1)
	check(s.projectiles().is_empty() and g.combat.hits.is_empty(),"death before launch cancels shot")
	f=fresh(); g=f[0]; s=f[1]; e=f[2]; t=f[3]
	s.try_attack(e,t); advance(g,s,.667); e.hp=0; s.notify_death(e); g.state.entities.erase(str(e.id)); advance(g,s,1.2)
	check(t.hp==88 and g.combat.hits.size()==1,"already-fired projectile survives shooter removal")
	f=fresh(); g=f[0]; s=f[1]; e=f[2]; t=f[3]
	s.try_attack(e,t); advance(g,s,.3); e.orderToken=1; advance(g,s,.8)
	check(s.projectiles().is_empty() and s.state().recent[-1].outcome=="cancelled","changed command token cancels pending shot")
	f=fresh(); g=f[0]; s=f[1]; e=f[2]; t=f[3]
	g.combat.rate=2; s.try_attack(e,t)
	check(is_equal_approx(s.state().casts.values()[0].releaseAt,.3335) and is_equal_approx(e.pneumoNextAttackAt,.9),"existing attack-speed modifier scales baseline cadence and windup together")
	g.paused=true; advance(g,s,0)
	check(s.projectiles().is_empty() and not s.try_attack(e,t),"pause does not start or advance shots")

func save_checks() -> void:
	var f := fresh(); var g=f[0]; var s=f[1]; var e: Dictionary=f[2]; var t: Dictionary=f[3]
	s.try_attack(e,t); advance(g,s,.4)
	var pair := saved_copy(g,s); var copy=pair[0]; var restored=pair[1]
	advance(copy,restored,.666); check(restored.projectiles().is_empty(),"saved pending cast remains pending before release")
	advance(copy,restored,.667); advance(copy,restored,.667)
	check(event_count(copy,"pneumococcus_projectile_spawn")==1 and restored.projectiles().size()==1,"saved pending cast emits once")
	advance(copy,restored,.8)
	var in_flight: Dictionary = restored.snapshot(); pair=saved_copy(copy,restored); copy=pair[0]; restored=pair[1]
	advance(copy,restored,1.2); advance(copy,restored,1.2)
	check(copy.entity(2).hp==88 and copy.combat.hits.size()==1 and event_count(copy,"pneumococcus_projectile_spawn")==0,"saved fired projectile hits once without respawn")
	pair=saved_copy(copy,restored); copy=pair[0]; restored=pair[1]
	advance(copy,restored,3)
	check(copy.entity(2).hp==88 and copy.combat.hits.is_empty() and restored.projectiles().is_empty(),"saved completed hit cannot replay")
	check(restored.state().resolvedThrough==1,"terminal shot has a persistent anti-replay watermark")
	var bad: Dictionary = in_flight.duplicate(true); bad.resolvedThrough=1
	check(not Service.validate_state(bad).is_empty(),"save rejects flying ID already completed")
	bad=in_flight.duplicate(true); bad.projectiles.values()[0].dx=2
	check(not Service.validate_state(bad).is_empty(),"save rejects non-normalized direction")
	bad=in_flight.duplicate(true); bad.projectiles.values()[0].damage=NAN
	check(not Service.validate_state(bad).is_empty(),"save rejects nonfinite damage")
	bad=in_flight.duplicate(true); bad.nextShotId=3
	check(not Service.validate_state(bad).is_empty(),"save rejects missing issued stages")
	bad=in_flight.duplicate(true); bad.projectiles.values()[0].lastUpdatedAt=100
	check(not Service.validate_state(bad).is_empty(),"save rejects flight time beyond expiry")
	bad=in_flight.duplicate(true); bad.recent=[{"id":1,"time":.7,"outcome":"hit"}]
	check(not Service.validate_state(bad).is_empty(),"save rejects replay of a terminal history ID")
	bad=in_flight.duplicate(true); bad.projectiles={}; bad.finished={"1":"hit"}
	check(not Service.validate_state(bad).is_empty(),"save rejects unmerged completion watermark")
	bad=in_flight.duplicate(true); bad.extra=Vector2.ONE
	check(not Service.validate_state(bad).is_empty(),"save rejects noncanonical object values")
	var before:=JSON.stringify(restored.snapshot())
	check(not restored.restore(bad).is_empty() and JSON.stringify(restored.snapshot())==before,"invalid restore is atomic")
	f=fresh(); g=f[0]; s=f[1]; e=f[2]; t=f[3]
	s.try_attack(e,t); advance(g,s,.2); s.notify_hit(e,Vector2.RIGHT)
	pair=saved_copy(g,s); advance(pair[0],pair[1],2)
	check(pair[1].projectiles().is_empty() and pair[0].combat.hits.is_empty(),"saved cancelled cast cannot relaunch")

func boundary_checks() -> void:
	var f := fresh(Vector2(6,0)); var g=f[0]; var s=f[1]; var e: Dictionary=f[2]; var t: Dictionary=f[3]
	var front: Dictionary=g.add("store",1,Vector2(3,0),"building")
	s.try_attack(e,t); advance(g,s,1.3)
	check(front.hp==88 and t.hp==100 and g.combat.hits.size()==1,"nearest enemy building consumes a single projectile")
	f=fresh(Vector2(6,0)); g=f[0]; s=f[1]; e=f[2]; t=f[3]
	front=g.add("worker",1,Vector2(3,0))
	s.try_attack(e,t); advance(g,s,1.3)
	check(front.hp==88 and t.hp==100 and g.combat.hits.size()==1,"first enemy unit intercepts without piercing")
	f=fresh(Vector2(6,0)); g=f[0]; s=f[1]; e=f[2]; t=f[3]
	front=g.add("gate",2,Vector2(3,0),"building")
	s.try_attack(e,t); advance(g,s,1.3)
	check(front.hp==100 and t.hp==100 and s.state().recent[-1].reason=="friendly_building","friendly same-plane gate stops flight without damage")
	f=fresh(Vector2(100,0)); g=f[0]; s=f[1]; e=f[2]; t=f[3]
	e.vesselLane=3; t.category="building"; t.kind="gate"; t.collisionSize=1.6; t.gateSides={"3":[4,0]}
	check(s.try_attack(e,t),"checkpoint endpoint adapter acquires gate on source plane")
	advance(g,s,1.2)
	check(t.hp==88 and g.combat.hits.size()==1,"checkpoint endpoint blocks and takes one hit without crossing plane")
	f=fresh(Vector2(6,0)); g=f[0]; s=f[1]; e=f[2]; t=f[3]
	e.vesselLane=3; t.vesselLane=3
	front=g.add("gate",2,Vector2(100,0),"building"); front.gateSides={"3":[3,0]}
	s.try_attack(e,t); advance(g,s,1.3)
	check(front.hp==100 and t.hp==100 and s.projectiles().is_empty(),"two-sided friendly gate intercepts at source-plane endpoint")
	f=fresh(); g=f[0]; s=f[1]; e=f[2]; t=f[3]
	s.try_attack(e,t); t.hp=0; advance(g,s,.667)
	check(s.projectiles().is_empty() and e.pneumoCastState=="cancelled","target death interrupts pending emission")
	f=fresh(); g=f[0]; s=f[1]; e=f[2]; t=f[3]
	s.try_attack(e,t); advance(g,s,.667)
	var view: Array=s.projectiles(); view[0].dx=-1
	check(s.projectiles()[0].dx==1,"renderer projectile copy cannot alter live trajectory")
	var callback_save: Dictionary={}
	g.combat.after_damage=func():
		callback_save.world=JSON.parse_string(JSON.stringify(g.state))
		callback_save.service=s.snapshot()
		s.step()
	advance(g,s,1.2); g.combat.after_damage=Callable()
	check(g.combat.hits.size()==1 and callback_save.service.projectiles.is_empty() and callback_save.service.resolvedThrough==1,"damage callback observes consumed projectile and nested step cannot hit twice")
	var loaded := TestGame.new(); loaded.state=callback_save.world
	var resumed := Service.new(loaded)
	var restore_error: String=resumed.restore(callback_save.service)
	check(restore_error.is_empty(),"post-damage callback snapshot validates: "+restore_error)
	advance(loaded,resumed,3)
	check(loaded.entity(2).hp==88 and loaded.combat.hits.is_empty(),"post-damage snapshot restores without replay")
	# A slow first cast keeps later completed IDs out of order. This ledger must
	# remain bounded and survive JSON without resurrecting the completed shots.
	f=fresh(); g=f[0]; s=f[1]; e=f[2]; t=f[3]; t.hp=100000.0
	g.combat.rate=.01; s.try_attack(e,t); g.combat.rate=1
	for _i in 127: s.try_attack(g.add("pneumococcus",2,Vector2.ZERO),t)
	advance(g,s,1)
	check(s.state().casts.size()==1 and s.state().finished.size()==127 and s.state().resolvedThrough==0,"out-of-order completions retain bounded terminal ledger")
	var extra: Dictionary=g.add("pneumococcus",2,Vector2.ZERO)
	var ledger_error: String=Service.validate_state(s.snapshot())
	check(not s.try_attack(extra,t) and ledger_error.is_empty(),"128-stage cap includes terminal IDs behind slow pending cast: "+ledger_error)
	var pair := saved_copy(g,s); loaded=pair[0]; resumed=pair[1]
	advance(loaded,resumed,67.2)
	check(loaded.combat.hits.size()==1 and resumed.state().resolvedThrough==128 and resumed.state().finished.is_empty(),"JSON out-of-order save completes prefix without replaying 127 hits")
	check(resumed.try_attack(loaded.entity(extra.id),loaded.entity(t.id)),"completed prefix releases capacity for future attacks")

func run() -> void:
	art_checks(); combat_checks(); save_checks(); boundary_checks()
	DirAccess.make_dir_recursive_absolute("res://test-output/pneumococcus")
	var file:=FileAccess.open("res://test-output/pneumococcus/independent-service.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"Independent service/asset/save fixtures; public hooks and real battlefield are not integrated."},"  "))
	print("PNEUMOCOCCUS ",checks-failures.size(),"/",checks)
	quit(0 if failures.is_empty() else 1)
