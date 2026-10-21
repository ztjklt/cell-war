class_name WarCombat
extends RefCounted
var game: WarSimulation
# Collect impacts until every unit has completed this tick, so update order
# cannot immediately undo a hit with movement. Rendering interpolates the push.
var _knockbacks: Dictionary = {}
const HIT_PUSH_MIN := 0.14
const HIT_PUSH_MAX := 0.38

func _init(owner: WarSimulation) -> void:
	game = owner

func enemy(e: Dictionary, reach: float, buildings := false) -> Dictionary:
	var best: Dictionary = {}
	var distance := reach*reach
	for other in game.entities():
		if other.hp <= 0 or other.faction == e.faction or (other.category != "unit" and not buildings):
			continue
		var d := WarData.point(e).distance_squared_to(WarData.point(other))
		# Candidates beyond the current best cannot win, including the existing
		# approximate-distance tie rule. Avoid a full visibility scan for them.
		if d > distance and not is_equal_approx(d,distance):
			continue
		if e.faction > 0 and not game.visible(other,e.faction):
			continue
		if d < distance or (is_equal_approx(d,distance) and (best.is_empty() or other.id < best.id)):
			best = other
			distance = d
	return best

func enemy_in_area(e: Dictionary, center: Vector2, radius: float, buildings := false) -> Dictionary:
	# Guard orders are anchored to their assigned point.  Searching around the
	# defender itself would let it chase a target away from its post forever.
	var best: Dictionary = {}
	var post_radius_squared := radius*radius
	var best_distance := INF
	for other in game.entities():
		if other.hp <= 0 or other.faction == e.faction or (other.category != "unit" and not buildings): continue
		var from_post := center.distance_squared_to(WarData.point(other))
		if from_post > post_radius_squared: continue
		if e.faction > 0 and not game.visible(other,e.faction): continue
		var from_defender := WarData.point(e).distance_squared_to(WarData.point(other))
		if best.is_empty() or from_defender < best_distance or (is_equal_approx(from_defender,best_distance) and other.id < best.id):
			best = other
			best_distance = from_defender
	return best

func multiplier(e: Dictionary, field: String) -> float:
	var value := 1.0
	for kind in e.get("statuses",{}):
		var config: Dictionary = WarData.config().CombatConfig.statuses.get(kind,{})
		value *= float(e.statuses[kind].get(field,config.get(field,1.0)))
	if field == "attackSpeedMultiplier": value *= game.b_cells.speed_multiplier(e)
	value *= game.dendritic.multiplier(e,field)
	value *= game.organ_functions.multiplier(e,field)
	if field == "moveMultiplier": value *= game.medicine_helpers.speed_multiplier(e)
	return value

func apply_status(e: Dictionary,kind: String,options: Dictionary) -> bool:
	if e.hp <= 0 or not WarData.config().CombatConfig.statuses.has(kind) or float(options.get("duration",1)) <= 0:
		return false
	e.statuses[kind] = options.duplicate(true)
	return true

func update_status(e: Dictionary,dt: float) -> void:
	var config: Dictionary = WarData.config().CombatConfig
	for kind in e.statuses.keys():
		var status: Dictionary = e.statuses[kind]
		var active := minf(dt,float(status.get("duration",dt)))
		var rate := float(status.get("damagePerSecond",config.statuses.get(kind,{}).get("damagePerSecond",0)))
		if rate > 0:
			damage({},e,rate*active,true,kind)
		if status.has("duration"):
			status.duration -= dt
			if status.duration <= 0:
				e.statuses.erase(kind)
	game.organ_functions.update_unit(e,dt)

func clinic_multiplier(source: Dictionary) -> float:
	if source.is_empty(): return 1.0
	var aura: Dictionary = WarData.config().CombatConfig.aura
	var origin := WarData.point(source)
	var lane := int(source.get("vesselLane",0))
	for building in game.entities():
		if building.kind != aura.building or building.faction != source.faction or building.hp <= 0 or not building.get("complete",false): continue
		# Screen-space overlap never joins tissue to a blood vessel. The original
		# radius and non-stacking bonus still apply within a clear terrain segment.
		if int(building.get("vesselLane",0)) != lane: continue
		var at := WarData.point(building)
		if origin.distance_squared_to(at) > float(aura.radius)*float(aura.radius): continue
		if game.navigation.clear_segment(at,origin,lane,str(source.kind)):
			return float(aura.attackMultiplier)
	return 1.0

func damage(source: Dictionary,target: Dictionary,amount: float,raw := false,cause := "attack",impact_direction := Vector2.ZERO) -> void:
	if target.hp <= 0 or amount <= 0:
		return
	if not raw:
		if target.kind == "heavy":
			amount *= .65
		if source.get("kind","") == "siege" and target.category == "building":
			amount *= 2.4
		if not source.is_empty():
			amount *= multiplier(source,"attackMultiplier")
			var faction := int(source.faction)
			if faction > 0 and game.state.factions[faction-1].tech.get("weapons",false):
				amount *= 1.25
			amount *= clinic_multiplier(source)
	var actual := minf(target.hp,amount)
	target.hp = maxf(0,target.hp-amount)
	var family := "red" if target.kind == "worker" else ("white" if target.kind in ["spear","neutrophil"] else "")
	if not family.is_empty():
		var duration: float = WarData.config().CellAnimationData[family+"Hit"].duration
		if not target.has("cellHitStarted") or float(game.state.time)-float(target.cellHitStarted) >= duration: target.cellHitStarted = game.state.time
	elif target.kind == "virus":
		if not target.has("cellHitStarted") or float(game.state.time)-float(target.cellHitStarted) >= WarInfluenzaAnimation.hit_duration(): target.cellHitStarted = game.state.time
	elif target.kind == "scout":
		if not target.has("cellHitStarted") or float(game.state.time)-float(target.cellHitStarted) >= float(WarPlatelets.data().clips.plateletHit.duration): target.cellHitStarted = game.state.time
	elif target.kind == "dendritic_cell":
		if not target.has("cellHitStarted") or float(game.state.time)-float(target.cellHitStarted) >= float(WarDendriticCells.data().clips.dcHit.duration): target.cellHitStarted = game.state.time
	target.hitTime = game.state.time
	if target.kind == WarTCellRuntime.KIND: game.t_cells.hit(target)
	target.lastAttacker = source.get("id",0)
	if actual > 0 and cause in ["attack","projectile","collision"]:
		queue_knockback(source,target,impact_direction,cause == "collision")
	game.effects.append({"p":WarData.point(target),"amount":actual,"born":game.state.time,"duration":.7})
	game.event("damage",{"source":source.get("id",0),"target":target.id,"amount":actual,"cause":cause})
	if target.hp <= 0 and target.has("checkpointId"):
		var hostile := WarData.is_pathogen(str(source.get("kind","")))
		target.breached = hostile
		target.faction = 0 if hostile else 1
		target.hp = target.maxHp
		for e in game.units():
			if WarData.is_pathogen(str(e.kind)): game.reset_path(e)
		game.notify("血管关口失守，病原体可跨器官扩散" if hostile else "血管关口已夺回，病原体通路封锁")
	elif target.hp <= 0:
		if WarPlatelets.is_platelet(target): game.platelets.detach(target)
		target.combatState = "dead"
		game.event("death",{"source":source.get("id",0),"target":target.id})

func queue_knockback(source: Dictionary,target: Dictionary,direction := Vector2.ZERO,collision := false) -> void:
	if target.get("category","") != "unit" or target.hp <= 0 or source.is_empty(): return
	if direction.is_zero_approx():
		if not source.has("x") or not source.has("y"): return
		direction = WarData.point(target)-WarData.point(source)
	if direction.is_zero_approx():
		direction = Vector2.RIGHT.rotated(float(source.get("weaponHeading",source.get("moveHeading",0))))
	var distance := clampf(WarData.radius(target.kind)*.45,HIT_PUSH_MIN,HIT_PUSH_MAX)
	if collision:
		distance = maxf(distance,float(WarData.spec(source.kind).get("contact",{}).get("knockback",0)))
	distance *= WarPlatelets.push_scale(target)
	var id := int(target.id)
	var pending: Dictionary = _knockbacks.get(id,{"push":Vector2.ZERO,"limit":distance})
	pending.limit = maxf(float(pending.limit),distance)
	pending.push = ((pending.push as Vector2)+direction.normalized()*distance).limit_length(pending.limit)
	_knockbacks[id] = pending

func resolve_knockback() -> void:
	for id in _knockbacks:
		var target := game.entity(id)
		if target.is_empty() or target.hp <= 0: continue
		var push: Vector2 = _knockbacks[id].push
		var p := WarData.point(target)
		var start := p
		var remaining := push.length()
		var direction := push.normalized()
		while remaining > .000001:
			var length := minf(.05,remaining)
			var next := p+direction*length
			# Keep the exact organ/vascular lane; impulses never use a gate transition.
			if not game.navigation.clear_segment(p,next,int(target.get("vesselLane",0)),target.kind) or not game._position_free(target,next): break
			p = next
			target.x = p.x
			target.y = p.y
			if target.has("renderTrail"): target.renderTrail.append(p)
			remaining -= length
		if p.distance_squared_to(start) > .00000001:
			game.reset_path(target)
			target.movementSpeed = 0.0
	_knockbacks.clear()

func _target_geometry(target: Dictionary,source_lane: int) -> Dictionary:
	var geometry := {"point":WarData.point(target),"lane":int(target.get("vesselLane",0)),
		"radius":float(WarData.spec(target.kind).get("size",1))*.5 if target.category == "building" else 0.0}
	if target.has("checkpointId"):
		for port in WarData.read("checkpoints").ports:
			if port.id == target.checkpointId:
				geometry.point = WarData.source_to_world(port.a if source_lane > 0 else port.b)
				geometry.lane = int(port.lane) if source_lane > 0 else 0
				geometry.radius = .8
				break
	return geometry

func _firing_solution(source: Dictionary,target: Dictionary,weapon_range := -1.0) -> Dictionary:
	var lane := int(source.get("vesselLane",0))
	var geometry := _target_geometry(target,lane)
	var reach := weapon_range if weapon_range >= 0 else float(WarData.spec(source.kind).get("range",1.5))
	geometry.clear = lane == int(geometry.lane) and game.navigation.clear_segment(WarData.point(source),geometry.point,lane,source.kind)
	# Units retain their existing centre-based weapon range. Buildings contribute
	# only their own physical radius; this is also used at release and impact.
	geometry.in_range = geometry.clear and WarData.point(source).distance_to(geometry.point) <= reach+float(geometry.radius)+.000001
	return geometry

func fight(e: Dictionary,t: Dictionary,dt: float,chase: bool) -> bool:
	if e.get("kind","") == WarTCellRuntime.KIND: return game.t_cells.cells.begin_attack(e,t)
	if e.get("kind","") in ["b_cell","dendritic_cell"] or e.hp <= 0 or t.hp <= 0 or e.faction == t.faction:
		return false
	# A previously acquired target can hide again when its scanner moves or dies.
	if int(e.faction) > 0 and not game.visible(t,int(e.faction)): return false
	var spec := WarData.spec(e.kind)
	var p := WarData.point(e)
	var solution := _firing_solution(e,t)
	var target: Vector2 = solution.point
	var config: Dictionary = spec.get("projectile",{})
	if config.get("targetKinds") is Dictionary and not config.targetKinds.get(t.kind,false):
		return false
	var target_lane := int(solution.lane)
	var clear: bool = solution.clear
	if solution.in_range:
		e.weaponHeading = (target-p).angle()
		e.weaponTarget = int(t.id)
		e.weaponTargetTime = game.state.time
		e.combatState = "attack"
		if float(e.cooldown) <= 0:
			var amount := float(e.get("attackDamage",spec.get("damage",0)))
			e.shotTime = game.state.time
			e.shotSpeed = maxf(.01,multiplier(e,"attackSpeedMultiplier"))
			e.cooldown = float(spec.get("cool",1))
			if not config.is_empty() and not t.has("checkpointId"):
				if config.has("windup"):
					e.cellShot = {"target":t.id,"started":game.state.time,"releaseAt":game.state.time+float(config.windup)/float(e.shotSpeed),
						"orderToken":e.orderToken,"damage":amount,"config":config.duplicate(true)}
				else:
					launch(e,t,amount,config)
			else:
				damage(e,t,amount)
				e.cooldown *= game.scenarios.shot(e)
		return true
	if chase and e.category == "unit":
		e.weaponHeading = (target-p).angle()
		e.weaponTarget = int(t.id)
		e.weaponTargetTime = game.state.time
		game.go(e,target,dt,maxf(.2,float(spec.get("range",1.5))-0.1) if clear else .5,target_lane)
		return true
	return false

func launch(e: Dictionary,t: Dictionary,amount: float,config: Dictionary) -> void:
	if e.get("kind","") == WarTCellRuntime.KIND: return
	if e.get("kind","") in ["b_cell","dendritic_cell"]: return
	if game.state.combatProjectiles.size() >= 128:
		return
	var delta := WarData.point(t)-WarData.point(e)
	if delta.length_squared() < .00001:
		return
	var p := WarData.point(e)
	var origin := p
	var direction := delta.normalized()
	if config.get("style","") == "granule":
		var muzzle := WarData.radius(e.kind)*2.0/1.02*(210.0/512.0)
		if game.navigation.clear_segment(p,p+direction*muzzle,int(e.get("vesselLane",0)),e.kind):
			p += direction*muzzle
	game.state.nextProjectileId = int(game.state.get("nextProjectileId",0))+1
	game.state.combatProjectiles.append({"id":game.state.nextProjectileId,"source":e.id,"sourceKind":e.kind,
		"faction":e.faction,"x":p.x,"y":p.y,"dx":direction.x,"dy":direction.y,
		"speed":float(config.speed),"ttl":float(config.ttl),"damage":amount,
		"targetKinds":config.get("targetKinds",{}),"style":config.get("style",""),"vesselLane":int(e.get("vesselLane",0)),"born":game.state.time})
	var bullet: Dictionary = game.state.combatProjectiles.back()
	bullet.launchX = origin.x; bullet.launchY = origin.y
	bullet.weaponRange = float(WarData.spec(e.kind).get("range",1.5))
	e.cooldown *= game.scenarios.shot(e)
	game.event("projectile_spawn",{"source":e.id,"target":t.id})

func update_projectiles(dt: float) -> void:
	for e in game.units():
		if e.has("cellShot") and game.state.time >= e.cellShot.releaseAt:
			var shot: Dictionary = e.cellShot
			e.erase("cellShot")
			var target := game.entity(int(shot.target))
			if e.hp <= 0 or target.is_empty() or target.hp <= 0 or target.faction == e.faction or e.orderToken != shot.orderToken or float(e.get("hitTime",-1)) > float(shot.started):
				continue
			if int(e.faction) > 0 and not game.visible(target,int(e.faction)): continue
			if _firing_solution(e,target).in_range:
				launch(e,target,shot.damage,shot.config)
	for i in range(game.state.combatProjectiles.size()-1,-1,-1):
		var bullet: Dictionary = game.state.combatProjectiles[i]
		var p := WarData.point(bullet)
		var distance := float(bullet.speed)*minf(dt,bullet.ttl)
		var remove := false
		while distance > .000001:
			var step := minf(.2,distance)
			var next := p+Vector2(bullet.dx,bullet.dy)*step
			if not game.navigation.clear_segment(p,next,int(bullet.get("vesselLane",0)),bullet.sourceKind):
				remove = true
				break
			var hit: Dictionary = {}
			var nearest := INF
			for target in game.entities():
				if target.hp <= 0 or target.get("vesselLane",0) != bullet.get("vesselLane",0) or target.has("checkpointId"):
					continue
				if target.faction == bullet.faction and not (bullet.style == "granule" and target.category == "building"):
					continue
				if not bullet.targetKinds.is_empty() and not bullet.targetKinds.get(target.kind,false):
					continue
				var geometry := _target_geometry(target,int(bullet.get("vesselLane",0)))
				var radius := float(geometry.radius) if target.category == "building" else WarData.radius(target.kind)
				var d := next.distance_to(WarData.point(target))
				if d <= radius and d < nearest:
					if bullet.has("launchX") and bullet.has("launchY") and bullet.has("weaponRange"):
						var launch_source := {"kind":bullet.sourceKind,"x":bullet.launchX,"y":bullet.launchY,"vesselLane":int(bullet.get("vesselLane",0))}
						if not _firing_solution(launch_source,target,float(bullet.weaponRange)).in_range: continue
					hit = target
					nearest = d
			p = next
			distance -= step
			if not hit.is_empty():
				var source := game.entity(int(bullet.source))
				if source.is_empty():
					source = {"id":bullet.source,"faction":bullet.faction,"kind":bullet.sourceKind,"x":p.x,"y":p.y,"vesselLane":int(bullet.get("vesselLane",0)),"statuses":{}}
				if hit.faction != bullet.faction:
					damage(source,hit,bullet.damage,false,"projectile",Vector2(bullet.dx,bullet.dy))
				game.event("projectile_impact",{"target":hit.id})
				remove = true
				break
		bullet.x = p.x
		bullet.y = p.y
		bullet.ttl -= dt
		if remove or bullet.ttl <= 0:
			game.state.combatProjectiles.remove_at(i)

func contacts(_dt: float) -> void:
	for e in game.units():
		# units() is a live snapshot; an earlier contact in this same loop may kill e.
		if e.hp <= 0: continue
		var contact: Dictionary = WarData.spec(e.kind).get("contact",{})
		if contact.is_empty():
			continue
		var touching: Dictionary = {}
		for t in game.units():
			if t.faction == e.faction or t.get("vesselLane",0) != e.get("vesselLane",0):
				continue
			var radius := WarData.radius(e.kind)+WarData.radius(t.kind)+.03
			if WarData.point(e).distance_to(WarData.point(t)) > radius:
				continue
			touching[str(t.id)] = true
			if not e.get("contactHits",{}).has(str(t.id)) and game.state.time >= float(e.get("nextContactHit",0)):
				damage(e,t,float(contact.damage),true,"collision")
				e.nextContactHit = game.state.time+float(contact.cool)
		e.contactHits = touching
