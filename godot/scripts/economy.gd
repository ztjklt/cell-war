class_name WarEconomy
extends RefCounted
var game: WarSimulation

func _init(owner: WarSimulation) -> void:
	game = owner

static func _stable_resource_amount(value: float) -> float:
	# Remove binary subtraction tails near a real quoted price, keeping genuinely
	# fractional harvest amounts intact. UI affordability and payment share stock().
	var decimal := roundf(value*1000.0)/1000.0
	return decimal if absf(value-decimal) <= .000000001 else value

func stock(faction: int,kind: String) -> float:
	if not WarData.config().Data.activeResources.get(kind,false):
		return 0
	var fa: Dictionary = game.state.factions[faction-1]
	if kind != "food":
		return _stable_resource_amount(float(fa.stock.get(kind,0)))
	var total := 0.0
	for batch in WarData.array(fa.food):
		total += float(batch.amount)
	return _stable_resource_amount(total)

func stomach_glucose(faction: int) -> float:
	var total := 0.0
	for batch in game.state.factions[faction-1].food:
		total += float(batch.get("stomachGlucose",0))
	return _stable_resource_amount(total)

func add(faction: int,kind: String,amount: float,source := "") -> void:
	if not WarData.config().Data.activeResources.get(kind,false):
		return
	var fa: Dictionary = game.state.factions[faction-1]
	if kind == "food":
		fa.food.append({"amount":amount,"born":game.state.time,"stomachGlucose":amount if source == "stomach" else 0})
	else:
		fa.stock[kind] = float(fa.stock.get(kind,0))+amount

func pay(faction: int,cost: Dictionary,stomach := false) -> bool:
	for kind in cost:
		if stock(faction,kind) < float(cost[kind]):
			if faction == 1: game.notify("缺少"+str(WarData.config().Data.names[kind]))
			return false
	if stomach and stomach_glucose(faction) < float(cost.get("food",0)):
		if faction == 1: game.notify("缺少胃部葡萄糖")
		return false
	for kind in cost:
		var remaining := float(cost[kind])
		if kind == "food":
			var food: Array = game.state.factions[faction-1].food
			for batch in food:
				var take := minf(remaining,float(batch.get("stomachGlucose",0)) if stomach else batch.amount)
				batch.amount -= take
				batch.stomachGlucose = maxf(0,float(batch.get("stomachGlucose",0))-take)
				remaining -= take
			food.assign(food.filter(func(b): return b.amount > 0))
		else:
			game.state.factions[faction-1].stock[kind] = stock(faction,kind)-remaining
	return true

func population(faction: int,queued := true) -> Vector2i:
	var count := 0
	var cap := 0
	for e in game.entities():
		if e.faction != faction or e.hp <= 0:
			continue
		if e.category == "unit":
			count += int(WarData.spec(e.kind).get("pop",0))
		elif e.get("complete",false):
			cap += int(WarData.spec(e.kind).get("pop",0))
		if queued:
			for q in e.queue:
				if q.has("unit"):
					count += int(WarData.spec(q.unit).get("pop",0))
	if game.is_campaign():
		cap = 40
	if faction == 1 and game.state.get("lungDefense") is Dictionary:
		cap += int(game.state.lungDefense.get("populationBonus",0))
	return Vector2i(count,mini(cap,40))

func train(building: Dictionary,kind: String) -> bool:
	var spec := WarData.spec(kind)
	var fa: Dictionary = game.state.factions[int(building.faction)-1]
	if building.category != "building" or building.hp <= 0 or not building.get("complete",false) or spec.get("at","") != building.kind or int(fa.tier) < int(spec.get("tier",1)):
		return false
	var pop := population(int(building.faction))
	if pop.x+int(spec.get("pop",0)) > pop.y:
		if int(building.faction) == 1: game.notify("人口已满，需要更多栖息泡")
		return false
	var in_liver := game.organ_functions.strong_training_allowed(building,kind)
	if game.mode == "sandbox": in_liver = game.survival.biome(WarData.point(building)).get("detail","") == "liver"
	if kind in ["heavy","siege"] and not in_liver:
		if int(building.faction) == 1: game.notify("强力细胞只能在肝脏训练")
		return false
	var cost := game.organ_functions.training_cost(building,kind)
	if building.queue.size() >= 6 or not pay(int(building.faction),cost):
		return false
	building.queue.append({"unit":kind,"remaining":float(spec.train),"total":float(spec.train),"cost":cost.duplicate(true)})
	return true

func research(building: Dictionary,kind: String) -> bool:
	var spec: Dictionary = WarData.config().Data.tech.get(kind,{})
	var fa: Dictionary = game.state.factions[int(building.faction)-1]
	if spec.is_empty() or building.kind != "lab" or building.hp <= 0 or not building.get("complete",false) or fa.tech.get(kind,false) or fa.get("researching",false) or int(fa.tier) < int(spec.tier):
		return false
	if not pay(int(building.faction),spec.cost):
		return false
	building.queue.append({"tech":kind,"remaining":float(spec.time),"total":float(spec.time),"cost":spec.cost.duplicate(true)})
	fa.researching = kind
	return true

func build_point(kind: String,p: Vector2) -> Vector2:
	# Both build-menu clicks and wheel commands pass through the camera transform.
	# Recover an exact grid boundary before floor() selects the neighbouring cell.
	if absf(p.x-roundf(p.x)) < .0005: p.x = roundf(p.x)
	if absf(p.y-roundf(p.y)) < .0005: p.y = roundf(p.y)
	var offset := .5 if int(WarData.spec(kind).get("size",1)) % 2 != 0 else 0.0
	return p.floor()+Vector2.ONE*offset

func can_place(kind: String,p: Vector2,workers: Array[int],faction := 1) -> bool:
	var spec := WarData.spec(kind)
	if game.is_campaign() or spec.is_empty() or not WarData.config().Data.buildings.has(kind) or workers.is_empty():
		return false
	var has_worker := false
	for id in workers:
		var e := game.entity(id)
		if e.get("kind","") == "worker" and int(e.get("faction",0)) == faction and float(e.get("hp",0)) > 0: has_worker = true
	if not has_worker:
		if faction == 1: game.notify("请先选择红细胞")
		return false
	if int(game.state.factions[faction-1].tier) < int(spec.get("tier",1)):
		if faction == 1: game.notify("需要先完成科技研究")
		return false
	var radius := float(spec.get("size",1))*.5
	if not _footprint_allowed(p,radius):
		if faction == 1: game.notify("建筑需要完整的组织地面")
		return false
	for e in game.entities():
		if e.hp <= 0: continue
		var offset := (WarData.point(e)-p).abs()
		if e.category == "building":
			var extent := radius+float(WarData.spec(e.kind).get("size",1))*.5
			# Occupancy is an axis-aligned square, including unfinished blueprints.
			# Strict overlap preserves the original legal shared edges/corners.
			if offset.x < extent and offset.y < extent:
				if faction == 1: game.notify("建筑占地与现有建筑重叠")
				return false
		elif e.category == "unit" and int(e.get("vesselLane",0)) == 0:
			# Match the expanded square used by movement's building clearance.
			# A projected unit on another vascular plane cannot occupy tissue.
			var extent := radius+WarData.radius(e.kind)
			if offset.x < extent and offset.y < extent:
				if faction == 1: game.notify("这里有%s，无法放置建筑" % str(WarData.spec(e.kind).get("name","单位")))
				return false
	return true

func place(kind: String,p: Vector2,workers: Array[int],faction := 1,append := false) -> bool:
	p = build_point(kind,p)
	if not can_place(kind,p,workers,faction): return false
	var spec := WarData.spec(kind)
	if not pay(faction,spec.get("cost",{}),kind == "clinic"):
		return false
	var building := game.spawn(kind,faction,p,"building")
	if building.is_empty():
		for resource in spec.cost:
			add(faction,resource,spec.cost[resource],"stomach" if kind == "clinic" else "")
		return false
	building.complete = false
	building.progress = 0.0
	building.hp = maxf(30,float(spec.hp)*.15)
	building.attackAura = kind == "clinic"
	for id in workers:
		var e := game.entity(id)
		if not e.is_empty() and e.kind == "worker":
			game.order(e,{"kind":"build","target":building.id},append)
	return true

func _footprint_allowed(p: Vector2,radius: float) -> bool:
	var lower := p-Vector2.ONE*radius
	var upper := p+Vector2.ONE*radius
	if game.navigation.ground_mode:
		# Test every raster cell covered by the square, including internal holes.
		# Use the same rounded cell coordinates as campaign_clear().
		var grid := game.navigation.campaign_grid
		if grid == null: return false
		var first := Vector2i((lower-grid.origin).round())
		var last := Vector2i((upper-grid.origin).round())
		if first.x < 0 or first.y < 0 or last.x >= grid.width or last.y >= grid.height: return false
		for y in range(first.y,last.y+1):
			for x in range(first.x,last.x+1):
				if grid.valid[y*grid.width+x] == 0: return false
		return true
	var organ := game.navigation.organ_at(p)
	if organ.is_empty(): return false
	var corners := [lower,Vector2(upper.x,lower.y),upper,Vector2(lower.x,upper.y)]
	var rings: Array = game.navigation.grid(organ,WarNavigation.profile("worker")).rings
	for i in 4:
		if game.navigation.organ_at(corners[i]) != organ: return false
		# Four valid corners can still straddle a concave wall. Exact sweeps retain
		# the authored polygon boundary without rasterizing or widening the tissue.
		if not WarGrid.segment_inside(rings,corners[i],corners[(i+1)%4]): return false
	# A hole wholly enclosed by the footprint never intersects its four edges.
	# Reject it too; overlapping legal rings, if present, keep their union rule.
	var footprint := Rect2(lower,upper-lower)
	for ring in rings:
		for hole in ring.holes:
			for point in hole:
				if footprint.has_point(point) and not WarGrid.inside(rings,point): return false
	return true

func cancel_production(building: Dictionary,index: int) -> void:
	if index < 0 or index >= building.queue.size():
		return
	var q: Dictionary = building.queue[index]
	for kind in q.cost:
		add(int(building.faction),kind,floorf(float(q.cost[kind])*.75))
	if q.has("tech"):
		game.state.factions[int(building.faction)-1].researching = false
	building.queue.remove_at(index)

func update(dt: float) -> void:
	# A destroyed laboratory must not permanently lock its faction's research.
	for i in game.state.factions.size():
		var fa: Dictionary = game.state.factions[i]
		if fa.get("researching",false):
			var active := game.entities().any(func(e): return e.faction == i+1 and e.hp > 0 and e.kind == "lab" and e.get("complete",false) and e.queue.any(func(q): return q.get("tech","") == fa.researching))
			if not active: fa.researching = false
	for e in game.entities():
		if e.category != "building" or e.hp <= 0 or not e.get("complete",false) or e.faction <= 0 or e.queue.is_empty():
			continue
		var q: Dictionary = e.queue[0]
		q.remaining = maxf(0,q.remaining-dt*game.organ_functions.production_rate(e,q))
		if q.remaining > 0:
			continue
		if q.has("tech"):
			var fa: Dictionary = game.state.factions[int(e.faction)-1]
			fa.tech[q.tech] = true
			fa.researching = false
			if q.tech == "tier2": fa.tier = 2
			if q.tech == "tier3": fa.tier = 3
			game.notify("研究完成："+str(WarData.config().Data.tech[q.tech].name))
			e.queue.pop_front()
		else:
			var pop := population(int(e.faction),false)
			if pop.x+int(WarData.spec(q.unit).get("pop",0)) > pop.y:
				continue
			var p := WarData.point(e)+Vector2(float(WarData.spec(e.kind).get("size",2)),0)
			for i in 24:
				var candidate := p+Vector2.from_angle(i*2.399)*sqrt(float(i))*.5
				if not _production_point_free(q.unit,int(e.faction),candidate): continue
				var unit := game.spawn(q.unit,int(e.faction),candidate)
				if not unit.is_empty():
					unit.requiresHeart = q.unit in ["heavy","siege"]
					if e.has("rally"): game.order(unit,{"kind":"move","x":e.rally.x,"y":e.rally.y})
					e.queue.pop_front()
					if e.faction == 1: game.state.trained = int(game.state.get("trained",0))+1
					break
	if int(game.state.tick) % 10 == 0:
		for fa in game.state.factions:
			var ttl := (6 if fa.tech.get("storage",false) else 3)*360
			fa.food = fa.food.filter(func(batch): return game.state.time-batch.born <= ttl)

func _production_point_free(kind: String,faction: int,p: Vector2) -> bool:
	# Production occurs on tissue; a projected blood vessel is not a spare exit.
	if not game.navigation.point_allowed(p,0,kind) or not game.navigation.movement_clear(p,p,kind,faction): return false
	var newborn := {"id":-1,"kind":kind,"x":p.x,"y":p.y}
	for other in game.units():
		if int(other.get("vesselLane",0)) == 0 and not WarCellShape.contact(newborn,other).is_empty(): return false
	return true

func harvest(e: Dictionary,order: Dictionary,dt: float) -> void:
	if e.kind != "worker":
		game.finish_order(e)
		return
	var resource: Dictionary = game.state.resources.get(str(order.get("resource","")),{})
	if resource.is_empty():
		var goal := WarData.point(order)
		var distance := INF
		for r in game.state.resources.values():
			var d := WarData.point(r).distance_squared_to(goal)
			if d < distance and r.amount > 0:
				distance = d
				resource = r
	if e.get("delivering",false):
		var destination := _delivery_point(e)
		var reach := 1.5
		for b in game.entities():
			if b.category == "building" and WarData.point(b).distance_to(destination) < .1:
				reach = float(WarData.spec(b.kind).get("size",1))*.5+1
		if game.go(e,destination,dt,reach,0):
			for kind in e.cargo:
				var amount := float(e.cargo[kind])
				if e.faction == 1: game.state.delivered = float(game.state.get("delivered",0))+amount
				if game.state.get("systemicBattle") is Dictionary and kind in ["oxygen","food"]:
					var field := "heartOxygen" if kind == "oxygen" else "heartGlucose"
					game.state.systemicBattle[field] += amount
				else:
					# Mixed cargo keeps exact stomach provenance for clinic costs.
					var stomach_amount := minf(amount,maxf(0,float(e.get("cargoStomachGlucose",0)))) if kind == "food" else 0.0
					if stomach_amount > 0: add(int(e.faction),kind,stomach_amount,"stomach")
					if amount > stomach_amount: add(int(e.faction),kind,amount-stomach_amount)
			e.cargo = {}
			e.cargoStomachGlucose = 0
			e.delivering = false
			game.notify("采集物资已运抵补给点，完成入库")
		return
	if not resource.is_empty() and resource.get("organSource",false) and (resource.get("contested",false) or float(resource.amount) < float(WarOrganResources.data().collectionAmount)):
		# A depleted renewable station is still a valid repeatable assignment.
		if game.go(e,WarData.point(resource),dt,1.5,0): e.combatState = "harvest"
		return
	if resource.is_empty() or resource.amount <= 0:
		game.finish_order(e)
		return
	if not game.go(e,WarData.point(resource),dt,1.5,int(resource.get("vesselLane",0))):
		return
	e.combatState = "harvest"
	e.work = float(e.get("work",0))+dt
	var period := float(WarOrganResources.data().collectionSeconds) if resource.get("organSource",false) else .7
	var yield_amount := float(WarOrganResources.data().collectionAmount) if resource.get("organSource",false) else 2.0
	var capacity := float(WarOrganResources.data().capacityPerRedCell) if resource.get("organSource",false) else 14.0
	if e.work >= period:
		e.work -= period
		var amount := minf(resource.amount,yield_amount)
		resource.amount -= amount
		e.cargo[resource.kind] = float(e.cargo.get(resource.kind,0))+amount
		if resource.get("organId","") == "stomach" and resource.kind == "food":
			e.cargoStomachGlucose = float(e.get("cargoStomachGlucose",0))+amount
		var total := 0.0
		for n in e.cargo.values(): total += float(n)
		if total >= capacity or resource.amount <= 0:
			e.delivering = true
			game.reset_path(e)

func _delivery_point(e: Dictionary) -> Vector2:
	if game.is_fullbody() and int(e.get("vesselLane",0)) == 0:
		var origin := WarData.point(e)
		var organ := game.navigation.organ_at(origin,e.kind)
		var local := Vector2(INF,INF)
		var nearest := INF
		if not organ.is_empty():
			var grid := game.navigation.grid(organ,WarNavigation.profile(e.kind))
			var origin_component := grid.component(origin)
			for b in game.entities():
				if b.faction != e.faction or b.hp <= 0 or not b.kind in ["core","store"] or not b.get("complete",false) or int(b.get("vesselLane",0)) != 0: continue
				var p := WarData.point(b)
				if game.navigation.organ_at(p,e.kind) != organ: continue
				var same_component := origin_component >= 0 and grid.component(p) == origin_component
				if not same_component and not game.navigation.clear_segment(origin,p,0,e.kind): continue
				var distance := origin.distance_squared_to(p)
				if distance < nearest: nearest = distance; local = p
			if nearest < INF: return local
	var gate: Dictionary = game.navigation.gates.get("heart.capillary.145.checkpoint.1",{})
	if not gate.is_empty():
		for g in game.navigation.organs.heart.gateContracts.siege:
			if g.id == gate.checkpointId: return WarData.source_to_world(g.tissueAnchorSource)
	var best := game.scenarios.home()
	var distance := INF
	for b in game.entities():
		if b.faction == e.faction and b.kind in ["core","store"] and b.hp > 0 and b.get("complete",false):
			var d := WarData.point(e).distance_squared_to(WarData.point(b))
			if d < distance:
				distance = d
				best = WarData.point(b)
	return best

func construct(e: Dictionary,order: Dictionary,dt: float) -> void:
	var building := game.entity(int(order.get("target",0)))
	if e.kind != "worker" or building.is_empty() or building.hp <= 0 or building.category != "building" or building.faction != e.faction:
		game.finish_order(e)
		return
	if order.kind == "farm" and (building.kind != "farm" or not building.get("complete",false)):
		game.finish_order(e)
		return
	# Another worker may have completed the repair earlier in this same step.
	# Finish before travel/work/payment, including old queued full-health targets.
	if order.kind in ["repair","build"] and building.get("complete",false) and building.hp >= building.maxHp:
		game.finish_order(e)
		return
	if order.kind == "farm" and e.get("delivering",false):
		harvest(e,{"resource":""},dt)
		return
	var reach := float(WarData.spec(building.kind).get("size",1))*.5+1.2
	if not game.go(e,WarData.point(building),dt,reach,0):
		return
	e.combatState = "build"
	e.cellWorkTime = game.state.time
	if order.kind == "farm" and building.kind == "farm" and building.get("complete",false):
		var season := (int(float(game.state.time)/360)/8)%4
		building.harvest = float(building.get("harvest",0))+dt*float(WarData.config().Data.climate[season].farmRate)
		if building.harvest >= 25:
			building.harvest -= 25
			e.cargo.food = float(e.cargo.get("food",0))+8
			if e.faction == 1: game.state.farmed = float(game.state.get("farmed",0))+8
			e.delivering = true
			game.reset_path(e)
		return
	if order.kind == "extinguish":
		building.fire = maxf(0,float(building.get("fire",0))-dt*.2)
		if building.fire <= 0: game.finish_order(e)
		return
	if building.get("complete",false):
		e.work = float(e.get("work",0))+dt
		if e.work >= 1 and pay(int(e.faction),{"wood":1}):
			e.work -= 1
			building.hp = minf(building.maxHp,building.hp+20)
		if building.hp >= building.maxHp: game.finish_order(e)
	else:
		building.progress = minf(1,float(building.progress)+dt/float(WarData.spec(building.kind).get("time",10)))
		building.hp = maxf(building.hp,building.maxHp*building.progress)
		if building.progress >= 1:
			building.complete = true
			game.combat.apply_status(e,"fatigue",{})
			game.finish_order(e)
			game.notify("建造完成："+str(WarData.spec(building.kind).name))
