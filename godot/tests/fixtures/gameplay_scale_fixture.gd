extends RefCounted
## Explicit performance fixture, never a natural-life or balance acceptance run.
const FRONTS := [
	{"organ":"lung_r","center":Vector2(788.9045,1226.91455),"station":"lung_r.oxygen"},
	{"organ":"lung_l","center":Vector2(1256.25549,1306.91052),"station":"lung_l.oxygen"},
	{"organ":"liver","center":Vector2(856.02882,1510.91254),"station":"large_intestine.wood"},
	{"organ":"small_intestine","center":Vector2(1089.1505,1932.91453),"station":"small_intestine.wood"}]

static func free_point(game: WarSimulation,p: Vector2,kind: String,organ: String) -> bool:
	if game.navigation.organ_at(p,kind) != organ or not game.navigation.point_allowed(p,0,kind): return false
	if game.navigation.pick_lane(p,kind) != 0 or not game.navigation.movement_clear(p,p,kind,1): return false
	for other in game.units():
		if int(other.vesselLane) == 0 and p.distance_to(WarData.point(other)) < WarData.radius(kind)+WarData.radius(other.kind)+.18: return false
	return true

static func find_point(game: WarSimulation,wanted: Vector2,kind: String,organ: String,anchor: Vector2) -> Vector2:
	for i in 1800:
		var p := wanted+Vector2.from_angle(i*2.39996323)*(.36*sqrt(float(i)))
		if free_point(game,p,kind,organ) and game.navigation.clear_segment(anchor,p,0,kind): return p
	return Vector2.INF

static func full_footprint(game: WarSimulation,p: Vector2,kind: String,organ: String) -> bool:
	var half := float(WarData.spec(kind).size)*.5
	var divisions := ceili(half*8)
	for y in range(divisions+1):
		for x in range(divisions+1):
			var at := p+Vector2(lerpf(-half,half,float(x)/divisions),lerpf(-half,half,float(y)/divisions))
			if game.navigation.organ_at(at) != organ: return false
	# Check complete cross sections as well as samples, including holes/concavities.
	for i in range(divisions+1):
		var offset := lerpf(-half,half,float(i)/divisions)
		if not game.navigation.clear_segment(p+Vector2(-half,offset),p+Vector2(half,offset),0,"worker"): return false
		if not game.navigation.clear_segment(p+Vector2(offset,-half),p+Vector2(offset,half),0,"worker"): return false
	return true

static func add_store(game: WarSimulation,wanted: Vector2,organ: String) -> Dictionary:
	for i in 400:
		var p := game.economy.build_point("store",wanted+Vector2.from_angle(i*2.39996323)*(.6*sqrt(float(i))))
		if not game.economy.can_place("store",p,[25]) or not full_footprint(game,p,"store",organ): continue
		var store := game.spawn("store",1,p,"building")
		game.navigation.blockers = game.entities().filter(func(e): return e.category == "building" and e.hp > 0 and not e.has("checkpointId"))
		return store
	return {}

static func populate(game: WarSimulation) -> Dictionary:
	game.start("life",73)
	# Isolate the load from the life director and medicine inventory. No hidden outbreaks.
	for key in ["lifeRun","medicineSupply","medicineRuntime"]: game.state.erase(key)
	game.state.influenzaColonies = {"version":1,"groups":{}}
	var fixture := {"scope":"Injected load fixture on authored fullbody terrain: original red retained; 39 friendlies, 80 existing pathogens and 4 completed depots explicitly injected; life/medicine directors isolated, empty influenza groups; no actor relocation, healing, replenishment, speed or road changes.","actors":[],"buildings":[],"errors":[]}
	for site in [{"p":Vector2(985,1906),"organ":"small_intestine"},{"p":Vector2(809,1295),"organ":"lung_r"},{"p":Vector2(1214,1295),"organ":"lung_l"},{"p":Vector2(892,1860),"organ":"large_intestine"}]:
		var building := add_store(game,site.p,site.organ)
		if building.is_empty(): fixture.errors.append("No legal depot in "+site.organ)
		else: fixture.buildings.append({"id":building.id,"point":WarData.point(building),"organ":site.organ,"complete":building.complete})
	fixture.actors.append({"id":25,"role":"original_harvester","station":"small_intestine.wood","start":WarData.point(game.entity(25)),"front":-1})
	for index in FRONTS.size():
		var front: Dictionary = FRONTS[index]
		var friendly: Array[String] = ["worker","spear","spear","spear","spear","spear","b_cell","dendritic_cell","scout"]
		if index < 3: friendly.append("worker")
		var hostile: Array[String] = []
		for i in 20: hostile.append("virus" if i < 14 else ("wolf" if i < 16 else ("herpes" if i < 18 else "helicobacter")))
		for side in [0,1]:
			var kinds: Array = friendly if side == 0 else hostile
			var wanted: Vector2 = front.center+Vector2(-10 if side == 0 else 10,0)
			for kind in kinds:
				var p := find_point(game,wanted,kind,front.organ,front.center)
				if not p.is_finite(): fixture.errors.append("No spaced legal point for "+kind+" in "+front.organ); continue
				var actor := game.spawn(kind,side+1,p)
				if actor.is_empty(): fixture.errors.append("Spawn rejected "+kind); continue
				fixture.actors.append({"id":int(actor.id),"role":"harvester" if kind == "worker" else ("friendly" if side == 0 else "hostile"),"station":front.station,"start":p,"front":index,"kind":kind})
	game.platelets.update(); game.b_cells.refresh(); game.dendritic.refresh()
	return fixture

static func issue(game: WarSimulation,fixture: Dictionary,combat_phase: bool) -> void:
	for item in fixture.actors:
		var actor := game.entity(int(item.id))
		if actor.is_empty() or actor.hp <= 0: continue
		if item.role in ["harvester","original_harvester"]:
			if actor.orders.is_empty():
				var source: Dictionary = game.state.resources[item.station]
				game.order(actor,{"kind":"harvest","resource":item.station,"x":source.x,"y":source.y})
			continue
		var front: Dictionary = FRONTS[int(item.front)]
		if combat_phase:
			if actor.kind in ["b_cell","dendritic_cell","scout"]: game.order(actor,{"kind":"hold"})
			else: game.order(actor,{"kind":"attackmove","x":front.center.x,"y":front.center.y,"lane":0})
		else:
			# Keep live movement orders; no coordinate writes and no cancelled path jobs.
			var dest: Vector2 = item.start+Vector2(0,.6 if int(game.state.time/8)%2 == 0 else -.6)
			if actor.orders.is_empty() and game.navigation.clear_segment(WarData.point(actor),dest,0,actor.kind) and game.navigation.movement_clear(dest,dest,actor.kind,int(actor.faction)):
				game.order(actor,{"kind":"move","x":dest.x,"y":dest.y,"lane":0})

static func counts(game: WarSimulation) -> Dictionary:
	var result := {"entities":game.entities().size(),"units":0,"friendly":0,"hostile":0,"projectiles":game.state.combatProjectiles.size(),"corpses":game.corpses.size(),"effects":game.effects.size(),"navigationPending":game.navigation.queue.size(),"navigationActive":0 if game.navigation.active.is_empty() else 1,"pathPending":0,"pathFailed":0,"kinds":{}}
	for e in game.units():
		result.units += 1
		if e.faction == 1: result.friendly += 1
		else: result.hostile += 1
		result.kinds[e.kind] = int(result.kinds.get(e.kind,0))+1
		if e.pathPending: result.pathPending += 1
		if e.pathFailed: result.pathFailed += 1
	return result
