extends SceneTree
var checks := 0
var failures: Array[String] = []
var evidence: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,label: String) -> void:
	checks += 1
	if not value: failures.append(label); printerr("FAIL ",label)

func near(value: float,expected: float,label: String,tolerance := .001) -> void:
	check(absf(value-expected)<=tolerance,label)

func target(id: int,p: Vector2,faction := 2,lane := 0,category := "unit") -> Dictionary:
	return {"id":id,"kind":"virus" if category=="unit" else "store","category":category,"faction":faction,"hp":100.0,"x":p.x,"y":p.y,"vesselLane":lane,"radius":.15 if category=="unit" else .5}

func service() -> WarTCells:
	var s := WarTCells.new()
	s.bind_world(func(_a,_b,_lane,_source,_purpose): return true,func(_p,_lane,_source): return true)
	return s

func json_copy(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value,"",false,true))

func events(s: WarTCells,kind: String) -> Array:
	return s.drain_events().filter(func(e): return e.kind==kind)

func art() -> void:
	var d := WarTCells.data()
	check(d.unitDefinition.at=="barracks" and d.unitDefinition.tier==2 and d.unitDefinition.hp==105 and d.unitDefinition.pop==2,"independent unit definition keeps the agreed first defaults")
	check(d.unitDefinition.cost=={"wood":25.0,"food":20.0,"oxygen":5.0} and d.unitDefinition.train==22,"training cost includes protein, glucose and oxygen")
	check(not d.runtimeIntegrated or WarData.config().Data.units.has("t_cell"),"integration metadata cannot claim a live role without unit registration")
	var counts := {"tBlink":16,"tThrow":16,"tHit":12,"tDeath":12}
	var total := 0
	for key in counts:
		var clip: Dictionary = d.clips[key]
		check(clip.durations.size()==counts[key] and ResourceLoader.exists("res://assets/"+clip.path),"complete real atlas for "+key)
		check(d.outlines[key].size()==counts[key] and d.outlines[key].all(func(p): return p.size()>=3),"painted body picking outlines for "+key)
		var mode: String = {"tBlink":"blink","tThrow":"throw","tHit":"hit","tDeath":"dead"}[key]
		var time := 0.0; var all_frames := true
		for i in clip.durations.size():
			var mid := time+float(clip.durations[i])*.5
			var sample := WarTCells.sample_state({"mode":mode,"since":0.0,"progress":mid},mid)
			all_frames = all_frames and int(sample.frame)==i and sample.key==key
			time += float(clip.durations[i]); total += 1
		check(all_frames and is_equal_approx(time,float(clip.duration)),"every source frame and duration sampled in "+key)
	check(total==56,"all fifty-six confirmed frames remain active")
	near(float(d.weapon.windup),.55,"first detached-knife art is frame eight at 550ms",.000001)
	check(d.weapon.releaseFrame==7 and d.projectileArt.frame==7,"weapon release uses zero-based frame seven")
	var body: Dictionary = d.clips.tThrow.bodyRects[7]; var knife: Dictionary = d.projectileArt.rect
	check(not Rect2(body.x,body.y,body.w,body.h).intersects(Rect2(knife.x,knife.y,knife.w,knife.h)),"body-only crop excludes the separately rendered released knife")
	var texture: Texture2D = load("res://assets/"+str(d.projectileArt.path))
	var image := texture.get_image()
	var r: Dictionary = d.projectileArt.atlasRect
	var crop := image.get_region(Rect2i(r.x,r.y,r.w,r.h))
	var visible := false; var clear := false
	for y in crop.get_height():
		for x in crop.get_width():
			var a := crop.get_pixel(x,y).a
			visible = visible or a>.5; clear = clear or a==0
	check(visible and clear,"real knife crop contains original painted pixels and transparent alpha")
	check(WarTCells.sample_state({"mode":"blink","since":0},.31).hidden and not WarTCells.sample_state({"mode":"blink","since":0},.42).hidden,"blink disappears during the two chosen frames and returns on arrival")
	check(WarTCells.sample_state({"mode":"dead","since":0},1.439).frame==11 and WarTCells.sample_state({"mode":"dead","since":0},1.44).hidden,"twelve-frame side-fall completes once and then hides")

func movement() -> void:
	var source := WarTCells.unit_record(1,1,Vector2(100,100))
	var closed := WarTCells.new()
	check(not closed.set_route(source,[{"x":120,"y":100,"lane":0}],1),"missing navigation adapters fail closed")
	var s := service()
	check(s.set_route(source,[{"p":Vector2(120,100),"lane":0}],1),"host-approved path is normalized to plain serializable coordinates")
	check(not s.set_route(source,[{"x":130,"y":100,"lane":0}],1),"stale path sequence cannot reset blink cadence")
	s.advance(.24,[source]); near(source.x,100,"launch frames do not teleport the cell")
	s.advance(.175,[source]); near(source.x,102.835,"first burst spends one speed-times-cycle movement allowance")
	check(source.vesselLane==0 and source.y==100,"blink stays on its approved plane and has no vertical jump")
	check(s.state_for(1).trail.size()>0 and s.state_for(1).trail.size()<=8,"afterimages use bounded real position history")
	check(WarTCells.validate_snapshot(s.snapshot()).is_empty(),"arrival/recovery state is serializable")
	s.advance(.53,[source]); near(source.x,102.835,"recovery cannot consume another movement allowance")
	s.advance(3.8,[source])
	var distance := float(source.x)-100
	check(distance <= 3.0*(float(s.snapshot().clock)+.945)+.01,"long-run displacement respects cadence budget instead of visual travel speed")
	evidence.move = {"distance":distance,"seconds":s.snapshot().clock,"speed":3.0,"oneCycleAllowance":2.835}
	var before := JSON.stringify(s.snapshot()); var x := float(source.x)
	s.advance(10,[source],true,4)
	check(JSON.stringify(s.snapshot())==before and source.x==x,"pause freezes movement and afterimage ages")
	var a := service(); var b := service(); var aa := WarTCells.unit_record(2,1,Vector2(100,100)); var bb := aa.duplicate(true)
	a.set_route(aa,[{"x":140,"y":100,"lane":0}],1); b.set_route(bb,[{"x":140,"y":100,"lane":0}],1)
	a.advance(.5,[aa],false,2); b.advance_simulation(1,[bb])
	near(aa.x,bb.x,"wall-time speed adapter and simulation-time adapter agree")
	var rates := {"move":.7}
	var slow := service(); slow.bind_world(func(_a,_b,_l,_e,_p): return true,func(_p,_l,_e): return true,Callable(),Callable(),func(_e,field): return rates.move if field=="moveMultiplier" else 1.0)
	var slowed := WarTCells.unit_record(3,1,Vector2(100,100)); slow.set_route(slowed,[{"x":120,"y":100,"lane":0}],1); slow.advance(.415,[slowed])
	near(float(slowed.x)-100,2.835*.7,"movement slowdown shortens a real burst by thirty percent")
	var reorder := service(); var r := WarTCells.unit_record(4,1,Vector2(100,100))
	reorder.set_route(r,[{"x":140,"y":100,"lane":0}],1); reorder.advance(.415,[r]); reorder.stop(r)
	reorder.set_route(r,[{"x":140,"y":100,"lane":0}],2); reorder.advance(.4,[r])
	near(r.x,102.835,"stop and reorder do not grant a fresh burst before its cadence")
	var wall := service(); var w := WarTCells.unit_record(5,1,Vector2(100,100))
	wall.bind_world(func(a,b,_l,_e,_p): return maxf(a.x,b.x)<101.5,func(p,_l,_e): return p.x<101.5)
	wall.set_route(w,[{"x":110,"y":100,"lane":0}],1); wall.advance(.5,[w])
	check(w.x==100 and wall.state_for(5).needsRoute,"full-segment wall blocks the burst before departure")
	var occupied := service(); var o := WarTCells.unit_record(6,1,Vector2(100,100))
	occupied.bind_world(func(_a,_b,_l,_e,_p): return true,func(p,_l,_e): return p.x<102)
	occupied.set_route(o,[{"x":110,"y":100,"lane":0}],1); occupied.advance(.5,[o])
	check(o.x==100 and occupied.state_for(6).needsRoute,"occupied landing cannot become an implicit teleport")
	var lane := service(); var l := WarTCells.unit_record(7,1,Vector2(100,100))
	lane.set_route(l,[{"x":110,"y":100,"lane":1}],1); lane.advance(.5,[l])
	check(l.x==100 and l.vesselLane==0 and events(lane,"t_route_required").any(func(e): return e.reason=="lane_transition_required"),"different-lane waypoint requests a certified host transition instead of jumping a gate")
	var dynamic := service(); var d := WarTCells.unit_record(8,1,Vector2(100,100)); var state := {"open":true}
	dynamic.bind_world(func(_a,_b,_l,_e,_p): return state.open,func(_p,_l,_e): return state.open)
	dynamic.set_route(d,[{"x":110,"y":100,"lane":0}],1); dynamic.advance(.3,[d]); x = d.x; state.open = false; dynamic.advance(.2,[d])
	check(d.x==x and dynamic.state_for(8).needsRoute,"new obstruction during transit stops at the last safe position")
	check(not dynamic.set_route(d,[{"p":"bad","lane":0}],2) and not dynamic.set_route(d,[{"x":INF,"y":100,"lane":0}],2),"malformed paths cannot become zero-point or infinite teleports")
	var flinch:=service(); var f:=WarTCells.unit_record(9,1,Vector2(100,100))
	flinch.set_route(f,[{"x":110,"y":100,"lane":0}],1); flinch.advance(.3,[f]); x=f.x; flinch.notify_hit(f); flinch.advance(.2,[f])
	check(f.x==x and flinch.sample(f).key=="tHit","hit interrupts an in-progress burst at its current safe position")
	var reduction:=service(); var reduced:=WarTCells.unit_record(10,1,Vector2(100,100)); var factor:={"move":1.0}
	reduction.bind_world(func(_a,_b,_l,_e,_p):return true,func(_p,_l,_e):return true,Callable(),Callable(),func(_e,field):return factor.move if field=="moveMultiplier" else 1.0)
	reduction.set_route(reduced,[{"x":110,"y":100,"lane":0}],1); reduction.advance(.3,[reduced]); factor.move=.7; reduction.advance(.2,[reduced])
	check(float(reduced.x)-100<=2.835*.7+.001 and reduction.state_for(10).needsRoute,"new mid-burst slow lowers remaining allowance without snapping backward or granting distance")

func attacks() -> void:
	var s := service(); var source := WarTCells.unit_record(1,1,Vector2(100,100)); var enemy := target(2,Vector2(104,100))
	check(s.begin_attack(source,enemy),"throw starts as a real windup rather than immediate damage")
	s.advance(.549,[source,enemy]); check(s.projectiles().is_empty() and enemy.hp==100,"no knife before source release keyframe")
	s.advance(.001,[source,enemy]); check(s.projectiles().size()==1 and enemy.hp==100,"one independent knife emits at 550ms")
	check(not s.begin_attack(source,enemy),"busy or cooling attack cannot emit a duplicate")
	s.advance(.3,[source,enemy]); near(enemy.hp,86,"swept knife collision damages once")
	check(s.projectiles().is_empty() and events(s,"t_knife_spawn").size()==1,"hit consumes the projectile and emission commits once")
	s.advance(2,[source,enemy]); near(enemy.hp,86,"recovery and idle do not replay the previous hit")
	var interrupted := service(); source = WarTCells.unit_record(3,1,Vector2(100,100)); enemy = target(4,Vector2(104,100))
	interrupted.begin_attack(source,enemy); interrupted.advance(.2,[source,enemy]); source.hp -= 1; interrupted.notify_hit(source); interrupted.advance(1,[source,enemy])
	check(enemy.hp==100 and interrupted.projectiles().is_empty(),"hit interrupts an unreleased throw")
	var died := service(); source = WarTCells.unit_record(5,1,Vector2(100,100)); enemy = target(6,Vector2(104,100))
	died.begin_attack(source,enemy); source.hp = 0; died.advance(1,[source,enemy])
	check(enemy.hp==100 and died.projectiles().is_empty() and died.sample(source).key=="tDeath","death cancels pending attack and selects side-fall")
	var released := service(); source = WarTCells.unit_record(7,1,Vector2(100,100)); enemy = target(8,Vector2(104,100))
	released.begin_attack(source,enemy); released.advance(.55,[source,enemy]); source.hp=0; released.advance(.4,[source,enemy])
	near(enemy.hp,86,"already released knife continues independently after source death")
	var cancelled := service(); source = WarTCells.unit_record(9,1,Vector2(100,100)); enemy = target(10,Vector2(104,100))
	cancelled.begin_attack(source,enemy); source.orderToken += 1; cancelled.advance(1,[source,enemy])
	check(enemy.hp==100 and cancelled.projectiles().is_empty(),"changed order token invalidates pending windup")
	var speed := service(); source = WarTCells.unit_record(11,1,Vector2(100,100)); enemy = target(12,Vector2(104,100))
	speed.bind_world(func(_a,_b,_l,_e,_p): return true,func(_p,_l,_e): return true,Callable(),Callable(),func(_e,field): return 2.0*1.15*.7 if field=="attackSpeedMultiplier" else 1.0)
	speed.begin_attack(source,enemy); speed.advance(.55/(2*1.15*.7),[source,enemy])
	check(speed.projectiles().size()==1,"B bonus, brain command and dendritic slow compose through one attack-rate input")
	near(float(speed.state_for(11).cooldown),.85,"same composed rate drives actual cooldown progression",.00001)
	var other_lane := target(13,Vector2(104,100),2,1)
	check(not service().begin_attack(WarTCells.unit_record(14,1,Vector2(100,100)),other_lane),"same projection on another lane is not an attack target")
	check(not service().begin_attack(WarTCells.unit_record(15,1,Vector2(100,100)),target(16,Vector2(106.01,100))),"unit centre beyond range cannot initiate a throw")

func collisions() -> void:
	var s := service(); var source := WarTCells.unit_record(1,1,Vector2(100,100)); var enemy := target(2,Vector2(104,100))
	s.begin_attack(source,enemy); s.advance(.55,[source,enemy]); enemy.y=103; s.advance(.5,[source,enemy])
	check(enemy.hp==100 and s.projectiles().is_empty(),"fixed-direction knife can be dodged and expires at range")
	var wall := service(); source=WarTCells.unit_record(3,1,Vector2(100,100)); enemy=target(4,Vector2(104,100)); var closed := {"value":false}
	wall.bind_world(func(a,b,_l,_e,purpose): return purpose!="knife" or not closed.value or maxf(a.x,b.x)<102,func(_p,_l,_e): return true)
	wall.begin_attack(source,enemy); wall.advance(.55,[source,enemy]); closed.value=true; wall.advance(.5,[source,enemy])
	check(enemy.hp==100 and wall.projectiles().is_empty(),"terrain or newly closed gate blocks the actual flight")
	var building := service(); source=WarTCells.unit_record(5,1,Vector2(100,100)); enemy=target(6,Vector2(104,100)); var depot:=target(7,Vector2(102,100),1,0,"building")
	building.begin_attack(source,enemy); building.advance(1,[source,enemy,depot])
	check(enemy.hp==100 and depot.hp==100 and building.projectiles().is_empty(),"friendly building blocks without friendly damage")
	var front := service(); source=WarTCells.unit_record(8,1,Vector2(100,100)); enemy=target(9,Vector2(104,100)); depot=target(10,Vector2(102,100),2,0,"building")
	front.begin_attack(source,enemy); front.advance(1,[source,enemy,depot])
	check(enemy.hp==100 and depot.hp==86,"nearest enemy building receives the single impact")
	var swept := service(); source=WarTCells.unit_record(11,1,Vector2(100,100)); enemy=target(12,Vector2(103.14159,100)); enemy.radius=.001
	swept.begin_attack(source,enemy); swept.advance(2,[source,enemy]); near(enemy.hp,86,"large delta and thin target still use swept contact")
	var tie := service(); source=WarTCells.unit_record(13,1,Vector2(100,100)); var a:=target(15,Vector2(104,100)); var b:=target(14,Vector2(104,100))
	tie.begin_attack(source,a); tie.advance(1,[source,a,b]); check(a.hp==100 and b.hp==86,"equal contacts resolve deterministically by entity id")
	var ally := service(); source=WarTCells.unit_record(16,1,Vector2(100,100)); enemy=target(17,Vector2(104,100)); var friendly:=target(18,Vector2(102,100),1); var projection:=target(19,Vector2(101,100),2,1)
	ally.begin_attack(source,enemy); ally.advance(1,[source,enemy,friendly,projection]); check(enemy.hp==86 and friendly.hp==100 and projection.hp==100,"friendly units and different-lane projections are not hit")

func serialization() -> void:
	var s:=service(); var source:=WarTCells.unit_record(1,1,Vector2(100,100)); var enemy:=target(2,Vector2(104,100))
	s.begin_attack(source,enemy); s.advance(.3,[source,enemy]); var checkpoint: Dictionary=json_copy(s.snapshot())
	check(WarTCells.validate_snapshot(checkpoint).is_empty(),"pending windup snapshot is plain valid JSON")
	var restored:=service(); var copy_source:Dictionary=json_copy(source); var copy_enemy:Dictionary=json_copy(enemy)
	check(restored.restore(checkpoint) and restored.drain_events().is_empty() and copy_enemy.hp==100,"restore itself neither emits nor damages")
	restored.advance(.5,[copy_source,copy_enemy]); near(copy_enemy.hp,86,"restored pending windup emits and impacts once")
	check(events(restored,"t_knife_spawn").size()==1,"restored pending cast commits one spawn")
	var after: Dictionary=json_copy(restored.snapshot()); check(restored.restore(after),"post-impact snapshot restores")
	restored.advance(2,[copy_source,copy_enemy]); near(copy_enemy.hp,86,"post-impact restore never replays consumed damage")
	var flying:=service(); source=WarTCells.unit_record(3,1,Vector2(100,100)); enemy=target(4,Vector2(104,100))
	flying.begin_attack(source,enemy); flying.advance(.6,[source,enemy]); checkpoint=json_copy(flying.snapshot())
	check(checkpoint.projectiles.size()==1 and checkpoint.actors["3"].fired,"in-flight snapshot records already committed release")
	var resume:=service(); resume.restore(checkpoint); resume.advance(.5,[source,enemy]); near(enemy.hp,86,"restored live knife completes once")
	check(events(resume,"t_knife_spawn").is_empty(),"restoring a live knife does not create another one")
	var unchanged:=JSON.stringify(resume.snapshot()); var bad:=checkpoint.duplicate(true); bad.projectiles.append(bad.projectiles[0].duplicate(true))
	check(not resume.restore(bad) and JSON.stringify(resume.snapshot())==unchanged,"duplicate projectile IDs fail atomically")
	bad=checkpoint.duplicate(true); bad.projectiles[0].dx=0; bad.projectiles[0].dy=0
	check(not resume.restore(bad),"invalid projectile direction is rejected")
	bad=checkpoint.duplicate(true); bad.actors["3"].fired=false
	check(not resume.restore(bad),"corrupt release flag cannot replay a previously committed throw")
	var moving:=service(); source=WarTCells.unit_record(5,1,Vector2(100,100)); moving.set_route(source,[{"p":Vector2(120,100),"lane":0}],1); moving.advance(.3,[source])
	checkpoint=json_copy(moving.snapshot()); check(WarTCells.validate_snapshot(checkpoint).is_empty(),"mid-burst position/route/trail state serializes without Vector2 objects")
	var mover:=service(); check(mover.restore(checkpoint),"mid-burst state restores with host bindings retained")
	var original:=source.duplicate(true); moving.advance(.2,[original]); mover.advance(.2,[source]); near(source.x,original.x,"restored burst continues to the same safe landing")
	bad=checkpoint.duplicate(true); bad.actors["5"].route[0].x=NAN
	check(not mover.restore(bad),"nonfinite route coordinates are rejected")
	bad=checkpoint.duplicate(true); bad.actors["5"].blink.allowance=1000
	check(not mover.restore(bad),"forged movement budget is rejected")

func authored_navigation() -> void:
	var nav:=WarNavigation.new(); var start:=Vector2.ZERO
	for room in nav.organs.stomach.rooms:
		var p:=WarData.source_to_world(room.centerSource)
		if nav.organ_at(p,"spear")=="stomach" and nav.clear_segment(p,p+Vector2(5,0),0,"spear"): start=p; break
	check(not start.is_zero_approx(),"real authored organ supplies a same-plane clear segment")
	if not start.is_zero_approx():
		var s:=WarTCells.new(); var source:=WarTCells.unit_record(1,1,start)
		s.bind_world(func(a,b,lane,_e,_purpose): return nav.clear_segment(a,b,lane,"spear"),func(p,lane,_e): return nav.point_allowed(p,lane,"spear"))
		s.set_route(source,[{"p":start+Vector2(5,0),"lane":0}],1); s.advance(.5,[source])
		check(source.x>start.x and nav.clear_segment(start,WarData.point(source),0,"spear"),"actual authored navigation accepts only a legal blink segment")
		var blocked:=WarTCells.new(); var stopped:=WarTCells.unit_record(2,1,start)
		blocked.bind_world(func(a,b,lane,_e,_p): return nav.clear_segment(a,b,lane,"spear"),func(p,lane,_e): return nav.point_allowed(p,lane,"spear"))
		blocked.set_route(stopped,[{"p":start,"lane":145}],1); blocked.advance(.5,[stopped])
		check(WarData.point(stopped)==start and stopped.vesselLane==0,"authored plane boundary still requires a host-certified gate handoff")
	nav.dispose()

func run() -> void:
	art(); movement(); attacks(); collisions(); serialization(); authored_navigation()
	DirAccess.make_dir_recursive_absolute("res://test-output/t-cells")
	evidence.checks=checks; evidence.failures=failures; evidence.scope="Independent rules, actual 56-frame sampling and authored-navigation adapter tests; no shared runtime hooks or trainable unit registration."
	var file:=FileAccess.open("res://test-output/t-cells/checks.json",FileAccess.WRITE); file.store_string(JSON.stringify(evidence,"  ",true,true))
	print("T_CELLS ",checks-failures.size(),"/",checks)
	quit(0 if failures.is_empty() else 1)
