extends SceneTree
## Test-only hook insertion. Production WarSimulation is not patched by this suite.
class HostSimulation extends WarSimulation:
	var bridge: WarPathogenRuntime
	func _update_unit(e: Dictionary,dt: float) -> void:
		if bridge != null and bridge.unit(e,dt): return
		if e.get("fixturePassive",false): return
		super._update_unit(e,dt)
	func step(dt: float) -> void:
		super.step(dt)
		if bridge != null:
			bridge.advance(dt)
			combat.resolve_knockback()
	func dispose() -> void:
		if bridge != null: bridge.dispose(); bridge = null
		super.dispose()

var checks := 0
var failures: Array[String] = []
var events: Array = []
var saved_config: Dictionary
var report: Dictionary = {}

func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ",label)

func fresh(mode := "cell_test",keep_gates := false) -> HostSimulation:
	var game := HostSimulation.new(); game.start(mode); game.paused = false
	for key in game.state.entities.keys():
		if not keep_gates or not game.state.entities[key].has("checkpointId"): game.state.entities.erase(key)
	if not keep_gates: game.navigation.gates.clear()
	game.state.influenzaColonies = {"version":1,"groups":{}}
	game.navigation.blockers.clear(); game.bridge = WarPathogenRuntime.new(game)
	game.combat_event.connect(func(e): events.append(e))
	return game

func ticks(game: HostSimulation,count: int) -> void:
	for i in count: game.navigation.update(100000); game.update(.1)

func target(game: HostSimulation,point: Vector2,hp := 1000.0,lane := 0) -> Dictionary:
	var e := game.spawn("b_cell",1,point)
	if not e.is_empty(): e.hp = hp; e.maxHp = hp; e.vesselLane = lane; e.fixturePassive = true
	return e

func damage_count(source_id: int,start: int) -> int:
	return events.slice(start).filter(func(e): return e.kind == "damage" and int(e.source) == source_id).size()

func pair(game: HostSimulation) -> Dictionary:
	var value := {"world":game.snapshot(),"runtime":game.bridge.snapshot()}
	return JSON.parse_string(JSON.stringify(value))

func restore_pair(value: Dictionary) -> HostSimulation:
	var game := fresh()
	game.bridge.dispose(); game.bridge = null
	game.restore(value.world); game.bridge = WarPathogenRuntime.new(game)
	check(game.bridge.restore(value.runtime),"runtime restores with same real world clock and actors")
	return game

func run() -> void:
	saved_config = WarData.config().duplicate(true)
	var file_hash := FileAccess.get_sha256("res://data/config.json")
	var game := fresh()
	check(game.bridge.spawn("adenovirus",2,Vector2(100,100),0).is_empty(),"illustration/candidate alone does not register or spawn adenovirus")
	check(game.bridge.spawn("pneumococcus",2,Vector2(100,100),0).is_empty(),"illustration/candidate alone does not register or spawn pneumococcus")
	game.dispose()
	# In-memory registration is limited to this isolated test process.
	WarData.config().Data.units.pneumococcus = WarPneumococcus.data().unit.duplicate(true)
	WarData.config().Data.units.adenovirus = WarData.read("adenovirus").unitSpec.duplicate(true)
	WarData.config().Data.cellRadii.pneumococcus = .72
	WarData.config().Data.cellRadii.adenovirus = .8 # Test-only circle; production hull review remains pending.
	check(WarData.is_bacterium("pneumococcus") and not WarData.is_virus("pneumococcus"),"registered pneumococcus has bacterium family")
	check(WarData.is_virus("adenovirus") and not WarData.is_bacterium("adenovirus"),"registered adenovirus has virus family")
	for kind in WarPathogenRuntime.KINDS:
		game = fresh(); var source := game.bridge.spawn(kind,2,Vector2(100,100),0)
		var enemy := target(game,Vector2(106 if kind == "pneumococcus" else 102,100))
		var start := events.size()
		game.order(source,{"kind":"attack","target":enemy.id})
		ticks(game,7 if kind == "pneumococcus" else 9)
		check(enemy.hp == 1000,"real simulation has no premature hit: "+kind)
		ticks(game,6 if kind == "pneumococcus" else 1)
		check(enemy.hp == 1000-(12 if kind == "pneumococcus" else 18),"one dedicated real WarCombat hit: "+kind)
		check(damage_count(int(source.id),start) == 1,"no legacy fight/launch duplicate: "+kind)
		check(game.state.combatProjectiles.is_empty(),"independent attack never enters generic projectile queue: "+kind)
		var before := float(enemy.hp); var at := WarData.point(source)
		check(game.bridge.advance(.1) and game.bridge.unit(source,.1),"duplicate dispatch returns safely: "+kind)
		check(enemy.hp == before and WarData.point(source) == at,"same tick cannot damage or move twice: "+kind)
		if kind == "adenovirus": check(is_equal_approx(float(enemy.x),102.35),"actual WarCombat knockback resolver applies one 0.35 slam push")
		game.dispose()

	for kind in WarPathogenRuntime.KINDS:
		game = fresh(); var source := game.bridge.spawn(kind,2,Vector2(100,100),0)
		var enemy := target(game,Vector2(110,100)); game.order(source,{"kind":"attack","target":enemy.id})
		ticks(game,70)
		check(source.x > 100 and enemy.hp < 1000,"ordinary real go approaches and attacks: "+kind)
		check(source.vesselLane == 0 and not source.has("viralBuilder"),"approach preserves layer and does not become influenza builder: "+kind)
		game.dispose()

	for kind in WarPathogenRuntime.KINDS:
		game = fresh(); var source := game.bridge.spawn(kind,2,Vector2(100,100),0)
		var enemy := target(game,Vector2(102,100)); game.order(source,{"kind":"attack","target":enemy.id})
		ticks(game,3); game.combat.damage({},source,1,true,"fixture_incoming"); ticks(game,8)
		check(enemy.hp == 1000,"real incoming damage interrupts before release: "+kind)
		game.dispose()
		game = fresh(); source = game.bridge.spawn(kind,2,Vector2(100,100),0); enemy = target(game,Vector2(102,100))
		game.order(source,{"kind":"attack","target":enemy.id}); ticks(game,3)
		game.order(source,{"kind":"move","x":96,"y":100,"lane":0}); ticks(game,12)
		check(enemy.hp == 1000 and source.x < 100,"real order token cancels and ordinary movement resumes: "+kind)
		game.dispose()

	game = fresh(); var source := game.bridge.spawn("pneumococcus",2,Vector2(100,100),0); var enemy := target(game,Vector2(106,100))
	game.order(source,{"kind":"attack","target":enemy.id}); ticks(game,8)
	check(game.bridge.projectiles().size() == 1,"667ms release produces a real independent in-flight kernel")
	var friend := game.spawn("barracks",2,Vector2(103,100),"building"); var friend_hp := float(friend.hp)
	ticks(game,4); check(enemy.hp == 1000 and friend.hp == friend_hp and game.bridge.projectiles().is_empty(),"actual friendly building blocks kernel without friendly damage")
	game.dispose()

	game = fresh(); source = game.bridge.spawn("pneumococcus",2,Vector2(100,100),0); enemy = target(game,Vector2(106,100))
	game.order(source,{"kind":"attack","target":enemy.id}); ticks(game,8); enemy.y = 103
	ticks(game,5); check(enemy.hp == 1000,"moving after release dodges fixed straight kernel")
	game.dispose()
	game = fresh(); source = game.bridge.spawn("adenovirus",2,Vector2(100,100),0); enemy = target(game,Vector2(102,100))
	game.order(source,{"kind":"attack","target":enemy.id}); ticks(game,3); enemy.x = 106
	ticks(game,7); check(enemy.hp == 1000,"moving out of locked slam area dodges")
	game.dispose()

	for kind in WarPathogenRuntime.KINDS:
		game = fresh(); source = game.bridge.spawn(kind,2,Vector2(100,100),0); enemy = target(game,Vector2(102,100))
		game.order(source,{"kind":"attack","target":enemy.id}); ticks(game,3)
		var save := pair(game)
		check(not save.runtime.is_empty() and WarPathogenRuntime.validate_snapshot(save.runtime,save.world).is_empty(),"canonical world/runtime save validates: "+kind)
		game.dispose(); game = restore_pair(save); source = game.entity(int(source.id)); enemy = game.entity(int(enemy.id))
		ticks(game,8); check(enemy.hp == 1000-(12 if kind == "pneumococcus" else 18),"pre-release restore resolves exactly once: "+kind)
		var after := pair(game); var hp := float(enemy.hp); game.dispose(); game = restore_pair(after)
		enemy = game.entity(int(enemy.id)); ticks(game,2)
		check(enemy.hp == hp,"post-hit restore never replays: "+kind)
		game.dispose()

	game = fresh(); source = game.bridge.spawn("pneumococcus",2,Vector2(100,100),0); enemy = target(game,Vector2(106,100))
	game.order(source,{"kind":"attack","target":enemy.id}); ticks(game,8)
	var flying := pair(game)
	check(flying.runtime.pneumococcus.projectiles.size() == 1,"in-flight state included in paired save")
	game.dispose(); game = restore_pair(flying); enemy = game.entity(int(enemy.id)); ticks(game,5)
	check(enemy.hp == 988,"restored straight kernel deals one actual hit")
	var stable := game.bridge.snapshot()
	for mutation in ["clock","tick","ledger","stale_projectile"]:
		var bad: Dictionary = flying.runtime.duplicate(true); var world: Dictionary = flying.world.duplicate(true)
		match mutation:
			"clock": bad.time += 1
			"tick": bad.tick += 1
			"ledger": bad.pneumococcus.resolvedThrough = bad.pneumococcus.nextShotId
			"stale_projectile":
				var key: String = bad.pneumococcus.projectiles.keys()[0]
				bad.pneumococcus.projectiles[key].lastUpdatedAt -= .01
				world.pneumococcusCombat = bad.pneumococcus.duplicate(true)
		check(not WarPathogenRuntime.validate_snapshot(bad,world).is_empty(),"paired save rejects "+mutation)
	check(game.bridge.snapshot() == stable,"failed validation cannot mutate live state")
	game.dispose()

	game = fresh(); source = game.bridge.spawn("adenovirus",2,Vector2(100,100),0); enemy = target(game,Vector2(102,100))
	game.order(source,{"kind":"attack","target":enemy.id}); ticks(game,3)
	var paused := pair(game); game.paused = true; ticks(game,15)
	check(pair(game) == paused,"actual host pause freezes independent clock and attack state")
	game.paused = false
	var refused_during_damage: Array[bool] = []
	var save_probe := func(e):
		if e.kind == "damage" and int(e.source) == int(source.id): refused_during_damage.append(game.bridge.snapshot().is_empty()))
	game.combat_event.connect(save_probe)
	ticks(game,7)
	check(refused_during_damage == [true],"actual WarCombat callback cannot save a half-applied independent impact")
	game.combat_event.disconnect(save_probe)
	check(game.state.influenzaColonies.groups.is_empty(),"neither new species recruits influenza builders or colonies")
	game.dispose()

	gate_tests()
	WarData._cache.config = saved_config
	check(FileAccess.get_sha256("res://data/config.json") == file_hash,"global config file was never changed by temporary registrations")
	check(WarData.spec("pneumococcus").is_empty() and WarData.spec("adenovirus").is_empty(),"temporary registrations are removed after isolated test")
	DirAccess.make_dir_recursive_absolute("res://test-output/pathogens")
	report.checks = checks; report.failures = failures
	report.scope = "Real WarSimulation/navigation/combat through test-only hook insertion; shared production hooks not installed. Adenovirus radius 0.8 is a test fixture."
	FileAccess.open("res://test-output/pathogens/integration.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("PATHOGEN INTEGRATION ",checks-failures.size(),"/",checks," ",failures)
	quit(0 if failures.is_empty() else 1)

func gate_tests() -> void:
	var game := fresh("fullbody",true)
	var port: Dictionary = {}; var direction := Vector2.ZERO
	# Locate a genuine authored port whose tissue surface supports both sides of
	# a same-plane barrier fixture. No navigation oracle is replaced.
	for candidate in WarData.read("checkpoints").ports:
		var center := WarData.source_to_world(candidate.b)
		for i in 16:
			var d := Vector2.from_angle(i*TAU/16)
			if game.navigation.clear_segment(center-d*2,center+d*1.3,0,"adenovirus"):
				port = candidate; direction = d; break
		if not port.is_empty(): break
	check(not port.is_empty(),"found certified real tissue gate fixture")
	if port.is_empty(): game.dispose(); return
	var gate: Dictionary = game.navigation.gates[port.id]
	var center := WarData.source_to_world(port.b)
	var source := game.bridge.spawn("adenovirus",2,center-direction*2,0)
	var behind := target(game,center+direction*1.3)
	check(not source.is_empty() and not behind.is_empty(),"real gate-side actors spawn on certified tissue")
	if source.is_empty() or behind.is_empty(): game.dispose(); return
	gate.hp = 10; game.order(source,{"kind":"attack","target":gate.id})
	ticks(game,10)
	check(gate.get("breached",false),"actual adenovirus damage breaches the authored gate")
	check(behind.hp == 1000,"same slam cannot pass a gate breached by that slam")
	check(source.vesselLane == 0,"slam does not teleport across gate or projected layer")
	report.gate = {"id":port.id,"tissue":[center.x,center.y],"lane":int(port.lane),"behindHp":behind.hp}
	var geometry := game.bridge.target_geometry(gate,int(port.lane))
	check(geometry.point == WarData.source_to_world(port.a) and int(geometry.lane) == int(port.lane),"blood-side target geometry uses original authored endpoint")
	var wrong := game.bridge.target_geometry(gate,int(port.lane)+1)
	check(int(wrong.lane) != int(port.lane)+1,"unrelated projected lane cannot target this port")
	game.dispose()
	for kind in WarPathogenRuntime.KINDS:
		game = fresh("fullbody",true); gate = game.navigation.gates[port.id]
		var pipe := WarData.source_to_world(port.a); var launch := Vector2(INF,INF)
		for i in 32:
			var point := pipe+Vector2.from_angle(i*TAU/32)*2.0
			if game.navigation.clear_segment(point,pipe,int(port.lane),kind): launch = point; break
		check(launch.is_finite(),"found certified blood-side approach: "+kind)
		if not launch.is_finite(): game.dispose(); continue
		source = game.bridge.spawn(kind,2,launch,int(port.lane))
		check(not source.is_empty(),"explicit blood-lane spawn uses certified point: "+kind)
		if source.is_empty(): game.dispose(); continue
		gate.hp = 10; var start := events.size()
		game.order(source,{"kind":"attack","target":gate.id}); ticks(game,10)
		check(gate.get("breached",false) and damage_count(int(source.id),start) == 1,"real blood-side attack hits authored gate endpoint once: "+kind)
		check(source.vesselLane == int(port.lane),"attack retains its original firing plane: "+kind)
		game.order(source,{"kind":"move","x":center.x,"y":center.y,"lane":0})
		for i in 200:
			ticks(game,1)
			if source.orders.is_empty(): break
		if source.vesselLane != 0 or WarData.point(source).distance_to(center) >= .06: print("CROSS ",kind," ",WarData.point(source)," goal ",center," lane ",source.vesselLane," path ",source.path," failed ",source.pathFailed," pending ",source.pathPending," orders ",source.orders)
		check(source.vesselLane == 0 and WarData.point(source).distance_to(center) < .06,"normal go crosses only the now-breached certified gate: "+kind)
		game.dispose()
	game = fresh("fullbody",true)
	var hole_point := Vector2(INF,INF)
	for organ in game.navigation.organs:
		for ring in game.navigation.grid(organ,"siege").rings:
			for hole in ring.holes:
				var mean := Vector2.ZERO
				for point in hole: mean += point
				mean /= hole.size()
				if Geometry2D.is_point_in_polygon(mean,hole) and not game.navigation.point_allowed(mean,0,"adenovirus"):
					hole_point = mean; break
			if hole_point.is_finite(): break
		if hole_point.is_finite(): break
	check(hole_point.is_finite(),"located a real authored organ hole")
	if hole_point.is_finite():
		check(game.bridge.spawn("adenovirus",2,hole_point,0).is_empty() and game.bridge.spawn("pneumococcus",2,hole_point,0).is_empty(),"spawn interface rejects actual tissue holes for both species")
	game.dispose()
