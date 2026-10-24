class_name WarScenarios
extends RefCounted
var game: WarSimulation

func _init(owner: WarSimulation) -> void:
	game = owner

func begin_lung_defense() -> void:
	# This event uses the certified full-body lung, economy and infection patch.
	# Keep the frozen fullbody start untouched for its existing entry and tests.
	for e in game.units():
		if e.faction == 1: game.state.entities.erase(str(e.id))
	game.state.influenzaColonies = {"version":1,"groups":{}}
	var home := Vector2.INF
	var desired := Vector2(1232,1176)
	for radius in 45:
		for dx in range(-radius,radius+1,3):
			for dy in range(-radius,radius+1,3):
				var candidate := desired+Vector2(dx,dy)
				if game.navigation.organ_at(candidate,"worker") != "lung_l": continue
				if not game.economy._footprint_allowed(candidate,1.5): continue
				if candidate.distance_to(Vector2(1232.25549,1226.91052)) < 45: continue
				home = candidate
				break
			if home.is_finite(): break
		if home.is_finite(): break
	if not home.is_finite():
		push_error("No certified left-lung base site for lung defense")
		return
	var base := game.spawn("core",1,home,"building")
	if base.is_empty(): return
	var workers: Array[int] = []
	for radius in range(2,18):
		for x in range(-radius,radius+1):
			for y in range(-radius,radius+1):
				if maxi(absi(x),absi(y)) != radius: continue
				var point := home+Vector2(x,y)*2.4
				if game.navigation.organ_at(point,"worker") != "lung_l" or not game.navigation.point_allowed(point,0,"worker"): continue
				if point.distance_to(home) < 3.5 or workers.any(func(id): return WarData.point(game.entity(int(id))).distance_to(point) < 2.2): continue
				var worker := game.spawn("worker",1,point)
				if worker.is_empty() or int(worker.vesselLane) != 0:
					if not worker.is_empty(): game.state.entities.erase(str(worker.id))
					continue
				workers.append(int(worker.id))
				if workers.size() == 20: break
			if workers.size() == 20: break
		if workers.size() == 20: break
	workers.sort_custom(func(a,b): return WarData.point(game.entity(int(a))).distance_squared_to(home) > WarData.point(game.entity(int(b))).distance_squared_to(home))
	game.state.lungDefense = {"version":1,"phase":"preparing","elapsed":0.0,"preparationSeconds":120.0,
		"base":int(base.id),"workers":workers,"populationBonus":20,"organ":"lung_l","placement":0,"waveCount":13,"colony":""}
	game.navigation.blockers = game.entities().filter(func(e): return e.category == "building" and e.hp > 0 and not e.has("checkpointId"))
	game.notify("左肺防线 · 120 秒准备：指挥红细胞建造分裂兵巢，再训练白细胞")

func systemic() -> Dictionary:
	return game.state.systemicBattle if game.state.get("systemicBattle") is Dictionary else {}

func home() -> Vector2:
	if game.is_campaign():
		return WarData.point(game.navigation.campaign.home)
	if not systemic().is_empty():
		return WarData.point(systemic().front)
	var lung: Dictionary = game.state.get("lungSkirmish",{})
	if game.mode == "lung_skirmish" and lung.has("center"):
		return WarData.point(lung.center)
	for e in game.units():
		if e.faction == 1 and e.kind == "worker":
			return WarData.point(e)
	return Vector2(1000,1900)

func before_step(dt: float) -> void:
	var defense: Dictionary = game.state.get("lungDefense",{})
	if defense.get("phase","") == "preparing":
		defense.elapsed = minf(float(defense.preparationSeconds),float(defense.elapsed)+dt/maxf(1.0,game.speed))
	if defense.get("phase","") == "preparing" and float(defense.elapsed)+.000001 >= float(defense.preparationSeconds):
		var group := game.influenza.start_outbreak(str(defense.get("organ","lung_r")),int(defense.placement),int(defense.waveCount))
		if not group.is_empty():
			defense.phase = "infected"
			defense.colony = group.id
			game.notify(defense_name()+"感染地板出现 · 流感病毒入侵！")
	if game.is_campaign():
		_campaign_before(dt)
	var q := systemic()
	if q.is_empty() or str(q.get("result","")) == "overrun":
		return
	var k: Dictionary = WarData.config().SystemicConfig
	var produced := minf(float(k.oxygenCapacity)-float(q.oxygen),float(k.oxygenRate)*dt)
	q.oxygen += produced
	q.produced += produced
	for id in q.players:
		var e := game.entity(int(id))
		if not e.is_empty() and e.hp > 0 and e.has("combatReserve") and near(e,q.front,float(k.supplyRadius)):
			var amount := maxf(0,minf(float(k.reserveMax)-float(e.combatReserve),minf(float(k.reserveRecovery)*dt,
				minf(float(q.glucose)/float(k.resourcePerReserve),float(q.oxygen)/float(k.resourcePerReserve)))))
			e.combatReserve += amount
			q.glucose -= amount*float(k.resourcePerReserve)
			q.oxygen -= amount*float(k.resourcePerReserve)
			q.spent += amount*float(k.resourcePerReserve)
	var living := 0
	for id in q.enemies:
		var e := game.entity(int(id))
		if not e.is_empty() and e.hp > 0: living += 1
	q.livingEnemies = living
	var nest := game.entity(int(q.nest))
	if not nest.is_empty() and nest.hp > 0:
		q.growth = minf(float(k.growthPeriod),float(q.growth)+dt)
		if q.growth >= float(k.growthPeriod) and q.glucose >= float(k.growthCost) and living < int(k.pathogenCap):
			for i in 12:
				var p := WarData.point(nest)+Vector2.from_angle(i*PI/6)*3
				if not game.navigation.clear_segment(WarData.point(nest),p,0,"virus"): continue
				var e := game.spawn("virus",2,p)
				if e.is_empty(): continue
				e.systemicUnit = true
				e.attackDamage = float(k.pathogenDamage)
				q.enemies.append(e.id)
				q.ids[str(e.id)] = true
				q.glucose -= float(k.growthCost)
				q.consumed += float(k.growthCost)
				q.spawned += 1
				q.growth = 0
				break

func defense_name() -> String:
	return "左肺" if game.state.get("lungDefense",{}).get("organ","") == "lung_l" else "右肺"

func after_step(dt: float) -> void:
	var defense: Dictionary = game.state.get("lungDefense",{})
	if defense.get("phase","") in ["preparing","infected"] and not game.entities().any(func(e): return e.faction == 1 and e.hp > 0 and not e.has("checkpointId")):
		defense.phase = "failed"
		defense.finishedAt = game.state.time
		game.paused = true
		game.notify(defense_name()+"防线失守 · 可读取存档或重新开始")
	if defense.get("phase","") == "infected":
		var group: Dictionary = game.state.get("influenzaColonies",{}).get("groups",{}).get(defense.get("colony",""),{})
		if not group.is_empty() and group.get("cleared",false):
			defense.phase = "defended"
			defense.finishedAt = game.state.time
			game.notify(defense_name()+"防线稳固 · 感染地板已净化")
	if game.is_campaign():
		_campaign_after(dt)
	var q := systemic()
	if q.is_empty() or q.get("result",false): return
	var alive := 0
	var enemies := 0
	for id in q.players:
		var e := game.entity(int(id))
		if not e.is_empty() and e.hp > 0: alive += 1
	for id in q.enemies:
		var e := game.entity(int(id))
		if not e.is_empty() and e.hp > 0: enemies += 1
	q.livingEnemies = enemies
	var nest := game.entity(int(q.nest))
	if alive == 0:
		q.result = "overrun"
	elif (nest.is_empty() or nest.hp <= 0) and enemies == 0:
		q.secure += dt
		if q.secure >= float(WarData.config().SystemicConfig.secureSeconds): q.result = "defended"
	else:
		q.secure = 0
	if q.result:
		q.finishedAt = game.state.time
		game.notify("循环防线稳定 · 感染灶与病毒已清除" if q.result == "defended" else "循环防线失守 · 可从菜单重试")

func near(e: Dictionary,destination: Dictionary,radius: float) -> bool:
	return int(e.get("vesselLane",0)) == int(destination.get("lane",0)) and WarData.point(e).distance_to(WarData.point(destination)) <= radius

func shot(e: Dictionary) -> float:
	if systemic().is_empty() or not e.has("combatReserve"): return 1
	var k: Dictionary = WarData.config().SystemicConfig
	if e.combatReserve >= float(k.reservePerShot):
		e.combatReserve = maxf(0,float(e.combatReserve)-float(k.reservePerShot))
		return 1
	return float(k.exhaustedCooldown)

func speed_multiplier(e: Dictionary) -> float:
	var q := systemic()
	var spread := 1.0
	if WarData.is_pathogen(str(e.kind)) and int(e.get("vesselLane",0)) > 0:
		var gate: Dictionary = game.navigation.gates.get(e.get("spreadOriginGate",""),{})
		if gate.get("breached",false): spread = 2.0
	if q.is_empty() or not e.get("systemicUnit",false): return spread
	var k: Dictionary = WarData.config().SystemicConfig
	return spread*(float(k.bloodSpeed) if int(e.get("vesselLane",0)) > 0 else 1.0) * (float(k.courierSpeed) if int(e.id) == int(q.courier) else 1.0)

func isolate(closed: bool) -> bool:
	var q := systemic()
	if q.is_empty(): return false
	for e in game.units():
		for g in game.navigation.organs.lung_r.gateContracts.siege:
			var a := WarData.source_to_world(g.pipeAnchorSource)
			var b := WarData.source_to_world(g.tissueAnchorSource)
			if closed and Geometry2D.get_closest_point_to_segment(WarData.point(e),a,b).distance_to(WarData.point(e)) < WarData.radius(e.kind) and not (game.navigation.organ_at(WarData.point(e),e.kind) != "" or game.navigation.clear_segment(WarData.point(e),WarData.point(e),int(e.get("vesselLane",0)),e.kind)):
				game.notify("关口有细胞正在通过，请等通行结束后隔离")
				return false
	for id in q.gates:
		var gate: Dictionary = game.navigation.gates.get(id,{})
		if not gate.is_empty(): gate.isolated = closed
	q.isolated = closed
	for e in game.units(): game.reset_path(e)
	game.notify("右肺已隔离 · 补给暂停通行" if closed else "右肺恢复通行 · 运输路线自动重试")
	return true

func unit(e: Dictionary,dt: float) -> bool:
	if game.mode == "cell_test" and e.faction != 1: return true
	var q := systemic()
	if not q.is_empty():
		if int(e.id) == int(q.courier) and not e.orders.is_empty() and e.orders[0].kind == "supplyroute":
			_courier(e,q,dt)
			return true
		if e.get("systemicUnit",false) and e.faction == 2:
			var target := game.combat.enemy(e,16,false)
			if not target.is_empty():
				game.combat.fight(e,target,dt,true)
				return true
	if game.is_campaign() and e.kind == "virus":
		var enemy := game.combat.enemy(e,8,false)
		if not enemy.is_empty():
			game.combat.fight(e,enemy,dt,true)
		else:
			var zones: Array = game.navigation.campaign.zones
			var target_index := int(e.get("viralZone",1))-1 if game.state.campaign.map_id == "lungs_01" else 0
			if game.state.campaign.map_id != "lungs_01":
				for i in zones.size():
					if game.state.campaign.event.zones[i].control > -100:
						target_index = i
						break
			var target := WarData.point(zones[target_index])+Vector2(int(e.id)%5-2,0)*1.6
			game.go(e,target,dt,1.5,0)
		return true
	if game.state.get("fullbodyBattlefieldVersion",0) == 1 and WarData.is_pathogen(str(e.kind)):
		return _pathogen(e,dt)
	return false

func _pathogen(e: Dictionary,dt: float) -> bool:
	var defender := game.combat.enemy(e,float(WarData.spec(e.kind).get("vision",3)),false)
	if not defender.is_empty() and int(defender.get("vesselLane",0)) == int(e.get("vesselLane",0)) and game.navigation.clear_segment(WarData.point(e),WarData.point(defender),int(e.get("vesselLane",0)),e.kind) and game.combat.fight(e,defender,dt,true): return true
	var lane := int(e.get("vesselLane",0))
	var ports: Array = WarData.read("checkpoints").ports
	var port: Dictionary = {}
	for p in ports:
		if p.id == e.get("spreadTargetGate",""): port = p; break
	if port.is_empty() or (e.get("spreadPhase","") != "cross" and game.state.time >= float(e.get("checkpointThinkAt",0))):
		e.checkpointThinkAt = game.state.time+1
		var owner := game.navigation.organ_at(WarData.point(e),e.kind) if lane == 0 else ""
		var distance := INF
		for p in ports:
			if (owner != "" and p.organId == owner) or (owner == "" and p.organId != e.get("spreadOriginOrgan","")):
				var d := WarData.point(e).distance_squared_to(WarData.source_to_world(p.b if lane == 0 else p.a))
				if p.id == e.get("spreadTargetGate",""): d *= .8
				if d < distance: distance = d; port = p
		if not port.is_empty() and port.id != e.get("spreadTargetGate",""):
			e.spreadPhase = "approach"
			e.spreadDirection = "enter" if lane == 0 else "exit"
			e.spreadTargetGate = port.id
	if port.is_empty(): return true
	var gate: Dictionary = game.navigation.gates.get(port.id,{})
	if gate.is_empty(): return true
	var entering: bool = e.get("spreadDirection","") == "enter"
	var anchor := WarData.source_to_world(port.b if entering else port.a)
	var goal_lane := 0 if entering else int(port.lane)
	if e.get("spreadPhase","") != "cross" and (WarData.point(e).distance_to(anchor) > 3.5 or lane != goal_lane):
		game.go(e,anchor,dt,.025,goal_lane)
		return true
	if not gate.get("breached",false):
		game.combat.fight(e,gate,dt,true)
		return true
	e.spreadPhase = "cross"
	var target := WarData.source_to_world(port.a if entering else port.b)
	var target_lane := int(port.lane) if entering else 0
	if game.go(e,target,dt,.025,target_lane):
		if target_lane > 0:
			e.spreadOriginGate = port.id
			e.spreadOriginOrgan = port.organId
		e.erase("spreadTargetGate")
		e.erase("spreadPhase")
		e.erase("spreadDirection")
		e.checkpointThinkAt = 0
	return true

func _courier(e: Dictionary,q: Dictionary,dt: float) -> void:
	var k: Dictionary = WarData.config().SystemicConfig
	var glucose := float(e.cargo.get("food",0))
	if q.heartGlucose < 1 and glucose < 1:
		q.courierState = "心脏葡萄糖储备耗尽"
		return
	var destination: Dictionary = q.front if glucose > 0 else q.heart
	if glucose == 0 and float(e.cargo.get("oxygen",0)) == 0:
		if not near(e,q.front,2): destination = q.front
		else:
			var amount := minf(float(k.cargoCapacity),float(q.oxygen))
			if amount < 1:
				q.courierState = "等待肺部产氧"
				return
			e.cargo.oxygen = amount
			q.oxygen -= amount
			q.loaded += amount
			destination = q.heart
	q.courierState = "葡萄糖运往右肺" if glucose > 0 else ("氧气运往心脏" if destination == q.heart else "返回肺部装氧")
	if near(e,destination,1.5):
		if destination == q.heart:
			var amount := float(e.cargo.get("oxygen",0))
			q.heartOxygen += amount
			q.exported += amount
			e.cargo.erase("oxygen")
			var food := minf(float(k.cargoCapacity),minf(float(q.heartGlucose),float(q.heartOxygen)))
			q.heartGlucose -= food
			q.heartOxygen -= food
			e.cargo.food = food
		else:
			q.glucose += glucose
			q.delivered += glucose
			e.cargo.erase("food")
		game.reset_path(e)
		return
	if e.pathFailed: q.courierState = "隔离中 · 等待恢复通行" if q.get("isolated",false) else "通路受阻 · 自动重试"
	game.go(e,WarData.point(destination),dt,1,int(destination.get("lane",0)))

func reinforce() -> bool:
	if not game.is_campaign(): return false
	var r: Dictionary = game.state.campaign.reinforcements
	var spec: Dictionary = game.navigation.campaign.supply
	if game.state.campaign.event.status != "active" or float(r.cooldown) > 0 or float(r.supply) < float(spec.cost):
		game.notify("补给不足或调援正在冷却")
		return false
	if game.economy.population(1).x+int(spec.count) > 40: return false
	r.supply -= float(spec.cost)
	r.cooldown = float(spec.cooldown)
	r.queue = WarData.array(r.queue)
	r.queue.append({"remaining":int(spec.count),"eta":float(spec.arrival)})
	return true

func skip_wave() -> bool:
	if not game.is_campaign(): return false
	var event: Dictionary = game.state.campaign.event
	var waves: Array = game.navigation.campaign.waves
	if int(event.wave) >= waves.size() or int(event.pendingViruses) > 0: return false
	for e in game.units():
		if e.kind == "virus":
			game.notify("请先清除当前波次")
			return false
	event.elapsed = maxf(float(event.elapsed),float(waves[int(event.wave)].at))
	return true

func _campaign_before(dt: float) -> void:
	var c: Dictionary = game.state.campaign
	var event: Dictionary = c.event
	if event.status != "active": return
	var spec: Dictionary = game.navigation.campaign
	event.elapsed += dt
	var r: Dictionary = c.reinforcements
	r.cooldown = maxf(0,float(r.cooldown)-dt)
	r.regen += dt
	while r.regen >= float(spec.supply.period):
		r.regen -= float(spec.supply.period)
		r.supply = minf(float(spec.supply.max),float(r.supply)+1)
	r.queue = WarData.array(r.queue)
	for q in r.queue.duplicate():
		q.eta -= dt
		if q.eta <= 0:
			while q.remaining > 0:
				var p := _spawn_near(home(),"spear")
				if game.spawn("spear",1,p).is_empty(): break
				q.remaining -= 1
			if q.remaining <= 0: r.queue.erase(q)
	event.spawnQueue = WarData.array(event.get("spawnQueue",[]))
	while int(event.wave) < spec.waves.size() and event.elapsed >= float(spec.waves[int(event.wave)].at):
		var wave: Dictionary = spec.waves[int(event.wave)]
		var zones: Array = wave.get("zones",[mini(int(event.wave)+1,spec.zones.size())])
		for i in int(wave.count): event.spawnQueue.append(int(zones[i%zones.size()]))
		event.pendingViruses = event.spawnQueue.size()
		event.wave += 1
		game.notify("第 %d 波病毒入侵" % int(event.wave))
	event.spawnTimer = float(event.get("spawnTimer",0))-dt
	if int(event.pendingViruses) > 0 and event.spawnTimer <= 0:
		var zone_index := int(event.spawnQueue[0]) if not event.spawnQueue.is_empty() else 1
		var p := WarData.point(spec.zones[zone_index-1]) if c.map_id == "lungs_01" else WarData.point(spec.entry)
		if c.map_id != "lungs_01" and spec.get("entries") is Array:
			var entry_index := 1 if int(event.wave) == 2 else (int(event.pendingViruses)%2 if int(event.wave) == 3 else 0)
			p = WarData.point(spec.entries[entry_index])
		p = _spawn_near(p,"virus")
		var enemy := game.spawn("virus",2,p)
		if not enemy.is_empty():
			enemy.viralZone = zone_index
			if not event.spawnQueue.is_empty(): event.spawnQueue.pop_front()
			event.pendingViruses = event.spawnQueue.size()
			event.spawnTimer = .7
	if c.get("autoplay",false):
		c.autoplayTimer = float(c.get("autoplayTimer",0))-dt
		if c.autoplayTimer <= 0:
			c.autoplayTimer = 1.0
			for e in game.units():
				if e.faction == 1 and e.orders.is_empty():
					var zone: Dictionary = spec.zones[int(e.id)%spec.zones.size()]
					game.order(e,{"kind":"guard","x":zone.x,"y":zone.y,"lane":0})

func _spawn_near(p: Vector2,_kind: String) -> Vector2:
	for i in 200:
		var at := p+Vector2.from_angle(i*2.399)*sqrt(float(i))*1.5
		if game.navigation.campaign_clear(at,at):
			var free := true
			for e in game.units():
				if WarData.point(e).distance_to(at) < 1.5:
					free = false
					break
			if free: return at
	return p

func _campaign_after(dt: float) -> void:
	var c: Dictionary = game.state.campaign
	var event: Dictionary = c.event
	var spec: Dictionary = game.navigation.campaign
	if event.status == "completed":
		for trigger in WarData.array(spec.get("exits",[])):
			var bounds := Rect2(Vector2(trigger.x,trigger.y),Vector2(trigger.w,trigger.h))
			for e in game.units():
				if e.faction == 1 and bounds.has_point(WarData.point(e)):
					if trigger.target == "lungs_01": change_campaign("lungs_01"); return
					elif not c.get("awaitingContent",false):
						c.awaitingContent = true
						game.notify("下一段战役尚未开放，可继续探索当前地图")
		return
	if event.status != "active": return
	for zone in event.zones:
		zone.friendly = 0
		zone.hostile = 0
	for e in game.units():
		if e.kind == "worker": continue
		for i in spec.zones.size():
			var polygon := PackedVector2Array()
			var coords: Array = spec.zones[i].polygon
			for j in range(0,coords.size(),2): polygon.append(Vector2(coords[j],coords[j+1]))
			if Geometry2D.is_point_in_polygon(WarData.point(e),polygon):
				var field := "friendly" if e.faction == 1 else "hostile"
				event.zones[i][field] += 1
	for zone in event.zones:
		zone.contested = zone.friendly > 0 and zone.hostile > 0
		if not zone.contested and zone.friendly+zone.hostile > 0:
			var direction := 1.0 if zone.friendly > 0 else -1.0
			var n := maxf(zone.friendly,zone.hostile)
			zone.control = clampf(float(zone.control)+direction*float(spec.captureRate)*(1+minf(2,n-1)*.5)*dt,-100,100)
			zone.owner = 1 if zone.control >= 100 else (2 if zone.control <= -100 else 0)
	for index in spec.get("failureZones",[event.zones.size()]):
		if float(event.zones[int(index)-1].control) <= -100:
			event.status = "failed"
			game.state.outcome = "defeat"
			game.notify("防线失守，可从菜单重试")
			return
	var allies := 0
	var enemies := 0
	for e in game.units():
		if e.faction == 1: allies += 1
		elif e.kind == "virus": enemies += 1
	if allies == 0:
		event.status = "failed"
		game.state.outcome = "defeat"
		game.notify("防线失守，可从菜单重试")
		return
	var all_controlled := true
	for zone in event.zones:
		if zone.control < 100: all_controlled = false
	if all_controlled and enemies == 0 and int(event.pendingViruses) == 0 and int(event.wave) >= spec.waves.size():
		event.secure += dt
		if float(event.secure) >= float(spec.secureSeconds):
			event.status = "completed"
			c.completed[c.map_id] = true
			game.state.outcome = "victory"
			game.notify("地图已夺回，前往出口进入下一关")
	else:
		event.secure = 0

func change_campaign(target: String) -> void:
	var previous: Dictionary = game.state.campaign
	var time := float(game.state.time)
	var troops := game.units().filter(func(e): return e.faction == 1)
	var factions: Array = game.state.factions.duplicate(true)
	var data: Dictionary = WarData.read("starts/"+target).duplicate(true)
	data.time = time
	data.entities = {}
	data.factions = factions
	data.nextId = int(game.state.nextId)
	data.campaign.completed = previous.completed.duplicate(true)
	game.mode = target
	game.restore(data)
	for old in troops:
		var p := _spawn_near(WarData.point(game.navigation.campaign.entry),old.kind)
		var e := game.spawn(old.kind,1,p)
		if not e.is_empty():
			e.hp = old.hp
			e.cargo = old.cargo.duplicate(true)
			e.statuses = old.statuses.duplicate(true)
	game.notify("已进入"+str(game.navigation.campaign.name)+" · 小队与资源已保留")

func cell_action(action: String) -> void:
	if game.mode != "cell_test": return
	var test: Dictionary = game.state.cellTest
	var red := game.entity(int(test.red))
	var white := game.entity(int(test.white))
	if action in ["empty","oxygen","glucose"]:
		if not red.is_empty():
			red.cargo = {"oxygen":8} if action == "oxygen" else ({"food":8} if action == "glucose" else {})
			game.order(red,{"kind":"move","x":105 if red.x < 102 else 99,"y":99,"lane":0})
		if not white.is_empty(): game.order(white,{"kind":"move","x":104 if white.x < 102 else 99,"y":104,"lane":0})
	elif action == "build" and not red.is_empty():
		var b := game.entity(int(test.building))
		if not b.is_empty():
			b.complete = false; b.progress = 0; b.hp = 1
			game.order(red,{"kind":"build","target":b.id})
	elif action == "shoot" and not white.is_empty():
		var enemy := game.entity(int(test.virus))
		if enemy.is_empty():
			enemy = game.spawn("virus",0,WarData.point(white)+Vector2(5,0))
			if not enemy.is_empty(): test.virus = enemy.id
		if not enemy.is_empty(): game.order(white,{"kind":"attack","target":enemy.id})
	elif action in ["hit","death"]:
		for e in [red,white]:
			if not e.is_empty(): game.combat.damage({},e,.5 if action == "hit" else e.hp,true,"playtest")
	game.notify("动作测试已切换，按空格继续播放")

func transfer(e: Dictionary,organ: String) -> bool:
	if not game.organ_functions.can_transfer(e,organ):
		game.notify("需要进入心脏组织并选择合法器官，再进行转运")
		return false
	for room in game.navigation.organs[organ].rooms:
		var p := WarData.source_to_world(room.centerSource)
		if game.navigation.organ_at(p,e.kind) != organ or not game._position_free(e,p): continue
		e.x = p.x
		e.y = p.y
		e.previousX = p.x
		e.previousY = p.y
		e.vesselLane = 0
		e.requiresHeart = false
		e.orders = []
		game.reset_path(e)
		game.event("transfer",{"target":e.id})
		game.notify("已转运到"+str(game.navigation.organs[organ].name))
		return true
	return false
