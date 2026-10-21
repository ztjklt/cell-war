class_name WarSimulation
extends RefCounted

signal message_changed(text: String)
signal combat_event(event: Dictionary)
signal state_replaced
const STEP := 0.1
var state: Dictionary = {}
var navigation := WarNavigation.new()
var selected: Array[int] = []
var groups: Array = [[],[],[]]
var paused := false
var speed := 1.0
var accumulator := 0.0
var mode := "fullbody"
var message := ""
var combat: WarCombat
var economy: WarEconomy
var scenarios: WarScenarios
var survival: WarSurvival
var resource_generation: WarResourceGeneration
var organ_resources: WarOrganResources
var organ_functions: WarOrganFunctions
var influenza: WarInfluenzaColonies
var life: WarLifeRun
var platelets: WarPlatelets
var b_cells: WarBCells
var dendritic: WarDendriticCells
var medicine_helpers: WarMedicineHelpers
var medicine_supply: WarMedicineSupply
var t_cells: WarTCellRuntime
var _requests: Dictionary = {}
var corpses: Array = []
var effects: Array = []

func _init() -> void:
	combat = WarCombat.new(self)
	economy = WarEconomy.new(self)
	scenarios = WarScenarios.new(self)
	survival = WarSurvival.new(self)
	resource_generation = WarResourceGeneration.new(self)
	organ_resources = WarOrganResources.new(self)
	organ_functions = WarOrganFunctions.new(self)
	influenza = WarInfluenzaColonies.new(self)
	life = WarLifeRun.new(self)
	platelets = WarPlatelets.new(self)
	b_cells = WarBCells.new(self)
	dendritic = WarDendriticCells.new(self)
	medicine_helpers = WarMedicineHelpers.new(self)
	medicine_supply = WarMedicineSupply.new(self, medicine_helpers)
	t_cells = WarTCellRuntime.new(self)
	navigation.path_ready.connect(_path_ready)

func start(which := "fullbody",seed := 73) -> void:
	mode = "fullbody" if which == "life" else which
	var data: Dictionary = WarData.read("starts/"+mode).duplicate(true)
	if which == "sandbox":
		data.seed = seed
		data.rng = seed
		data.resources = {}
		data.nativeGeneratedChunks = {}
	restore(data)
	if which == "life":
		# New survival runs start with a red cell. Frozen legacy starts and loaded
		# saves keep their authored squads; this is only the new-game entry.
		for e in units():
			if e.faction == 1 and e.kind != "worker": state.entities.erase(str(e.id))
		life.begin(seed)
		organ_resources.begin()
		organ_functions.state()
		medicine_helpers.begin()
		medicine_supply.begin()
	paused = which == "systemic" or which == "lung_skirmish"
	notify("点击地图选定观察坐标，Q 拉近 / E 拉远；右键展开指令，空格暂停。")

func restore(data: Dictionary) -> void:
	state = data.duplicate(true)
	state.entities = state.get("entities",{})
	if state.entities is Array:
		var by_id: Dictionary = {}
		for entity in state.entities:
			by_id[str(int(entity.id))] = entity
		state.entities = by_id
	state.resources = state.get("resources",{})
	state.commands = WarData.array(state.get("commands",[]))
	state.combatProjectiles = WarData.array(state.get("combatProjectiles",[]))
	state.time = float(state.get("time",0))
	state.tick = int(state.get("tick",0))
	for entity in entities():
		entity.id = int(entity.id)
		entity.faction = int(entity.faction)
		entity.orders = WarData.array(entity.get("orders",[]))
		entity.queue = WarData.array(entity.get("queue",[]))
		entity.path = []
		entity.pathIndex = 0
		entity.pathPending = false
		entity.pathFailed = false
		entity.statuses = entity.get("statuses",{})
		entity.cargo = entity.get("cargo",{})
		entity.previousX = entity.x
		entity.previousY = entity.y
		entity.combatState = "idle"
		entity.travelSpeed = 0.0
		entity.erase("cellShot")
		entity.erase("plateletLinks")
		entity.erase("plateletLinkStarted")
	_requests.clear()
	navigation.queue.clear()
	navigation.active = {}
	navigation.gates.clear()
	for entity in entities():
		if entity.has("checkpointId"):
			navigation.gates[entity.checkpointId] = entity
	navigation.set_campaign(WarData.read("campaigns/"+state.campaign.map_id) if is_campaign() else {})
	navigation.enabled_organs = ["stomach"] if state.get("gastricBattlefieldVersion",0) == 1 else navigation.organs.keys()
	if mode in ["sandbox","cell_test"]:
		navigation.set_ground(mode)
		for e in entities(): e.vesselLane = 0
	selected.clear()
	groups = [[],[],[]]
	accumulator = 0.0
	corpses.clear()
	effects.clear()
	combat._knockbacks.clear()
	resource_generation.reset()
	life.reset()
	organ_functions.reset_cache()
	medicine_helpers.reset()
	medicine_supply.reset()
	t_cells.reset()
	navigation.blockers = entities().filter(func(e): return e.category == "building" and e.hp > 0 and not e.has("checkpointId"))
	platelets.update()
	b_cells.refresh()
	dendritic.refresh()
	state_replaced.emit()

func entities() -> Array:
	return state.get("entities",{}).values()

func units() -> Array:
	return entities().filter(func(e): return e.category == "unit" and e.hp > 0)

func entity(id: int) -> Dictionary:
	return state.get("entities",{}).get(str(id),{})

func is_fullbody() -> bool:
	return state.get("fullbodyBattlefieldVersion",0) == 1

func is_campaign() -> bool:
	return state.get("campaign") is Dictionary

func notify(text: String) -> void:
	message = text
	message_changed.emit(text)

func event(kind: String, fields: Dictionary) -> void:
	var entry := fields.duplicate()
	entry.kind = kind
	entry.time = state.time
	combat_event.emit(entry)

func update(delta: float) -> void:
	resource_generation.update()
	navigation.blockers = entities().filter(func(e): return e.category == "building" and e.hp > 0 and not e.has("checkpointId"))
	navigation.update()
	if paused:
		return
	accumulator += minf(delta,.25)*speed
	var count := 0
	while accumulator >= STEP and count < 8:
		step(STEP)
		accumulator -= STEP
		count += 1

func step(dt: float) -> void:
	if life.enabled() and life.state().phase == "ended": return
	if mode == "sandbox" and state.get("outcome","") == "defeat": return
	_process_player_commands()
	navigation.blockers = entities().filter(func(e): return e.category == "building" and e.hp > 0 and not e.has("checkpointId"))
	state.time += dt
	state.tick += 1
	organ_resources.advance(dt)
	medicine_helpers.before_step(dt)
	scenarios.before_step(dt)
	influenza.before_step(dt)
	b_cells.refresh()
	dendritic.refresh()
	for e in units():
		e.previousX = e.x
		e.previousY = e.y
		e.renderTrail = [WarData.point(e)]
		e.cooldown = maxf(0,float(e.get("cooldown",0))-dt*combat.multiplier(e,"attackSpeedMultiplier"))
		if e.cooldown < .000001: e.cooldown = 0.0 # Do not add a whole tick for floating-point residue.
		e.combatState = "idle"
		e.travelSpeed = 0.0
		combat.update_status(e,dt)
		if e.hp <= 0:
			continue
		_update_unit(e,dt)
	for e in entities():
		if e.category == "building" and e.hp > 0:
			e.cooldown = maxf(0,float(e.get("cooldown",0))-dt)
			if e.kind == "tower" and e.get("complete",true):
				var target := combat.enemy(e,10,true)
				if not target.is_empty():
					combat.fight(e,target,dt,false)
	combat.update_projectiles(dt)
	combat.contacts(dt)
	combat.resolve_knockback()
	t_cells.advance(dt)
	economy.update(dt)
	influenza.after_step(dt)
	scenarios.after_step(dt)
	life.advance(dt)
	if mode == "sandbox": survival.update(dt)
	if mode == "sandbox" and int(state.tick)%10 == 0:
		var before: String = state.get("outcome","playing")
		WarProgress.advance(state)
		if state.outcome != before:
			notify("胞群全灭。可以读取手动存档继续。" if state.outcome == "defeat" else "内域属于你。已战胜两个阵营，可继续生存。")
	_resolve_units()
	platelets.update()
	b_cells.refresh()
	dendritic.refresh()
	for e in entities():
		if e.hp <= 0:
			var corpse: Dictionary = e.duplicate(true)
			corpse.died = state.time
			if e.kind != "flu_fortress": corpses.append(corpse)
			state.entities.erase(str(e.id))
			selected.erase(e.id)
	corpses = corpses.filter(func(e): return state.time-e.died < _corpse_duration(e))
	effects = effects.filter(func(e): return state.time-e.born < e.get("duration",.7))
	medicine_helpers.capture()

func _corpse_duration(e: Dictionary) -> float:
	if e.kind == WarTCellRuntime.KIND: return float(WarTCells.data().clips.tDeath.duration)+STEP
	if e.kind == WarMedicineHelpers.KIND: return float(WarMedicineHelpers.data().clips.death.duration)+STEP
	if e.kind == "dendritic_cell": return float(WarDendriticCells.data().clips.dcDeath.duration)+STEP
	if e.kind == "b_cell": return float(WarBCells.data().clips.bDeath.duration)+STEP
	if e.kind == "scout": return float(WarPlatelets.data().clips.plateletDeath.duration)+STEP
	return WarInfluenzaAnimation.corpse_duration(e)

func _update_unit(e: Dictionary, dt: float) -> void:
	e.age = float(e.get("age",0))+dt
	if e.has("life"):
		e.life -= dt
		if e.life <= 0: combat.damage({},e,e.hp,true,"expired"); return
	if medicine_helpers.unit(e,dt): return
	if influenza.unit(e,dt): return
	if survival.unit(e,dt): return
	if scenarios.unit(e,dt):
		return
	if t_cells.unit(e,dt): return
	var order: Dictionary = e.orders[0] if not e.orders.is_empty() else {}
	var kind: String = order.get("kind","")
	if e.kind == "b_cell":
		if kind == "attack":
			finish_order(e) # Explicit attacks cannot turn a support cell into a shooter.
			e.combatState = "buff"
			return
		if WarBCells.can_emit(e):
			e.combatState = "buff"
			return
	if e.kind == "dendritic_cell":
		if kind == "attack":
			finish_order(e)
			e.combatState = "scanning"
			return
		if WarDendriticCells.can_scan(e,float(state.time)):
			e.combatState = "scanning"
			return
	if WarPlatelets.is_platelet(e) and (order.is_empty() or kind in ["hold","stop"]):
		e.combatState = "defend"
		return
	if kind in ["harvest","gather"]:
		economy.harvest(e,order,dt)
		return
	if kind in ["build","repair","farm","extinguish"]:
		economy.construct(e,order,dt)
		return
	var can_attack: bool = e.kind not in ["b_cell","dendritic_cell"] and kind != "move" and kind != "retreat" and kind != "supplyroute"
	if can_attack:
		var target := entity(int(order.get("target",0))) if kind == "attack" else {}
		if target.is_empty() or target.hp <= 0:
			target = combat.enemy(e,float(WarData.spec(e.kind).get("vision",10)),kind == "attackmove")
		if not target.is_empty() and combat.fight(e,target,dt,kind != "hold"):
			return
	if order.is_empty() or kind == "hold":
		return
	if kind == "attack":
		if entity(int(order.get("target",0))).is_empty():
			finish_order(e)
		return
	var destination := Vector2(float(order.get("x",e.x)),float(order.get("y",e.y)))
	if go(e,destination,dt,.05,int(order.get("lane",-1))):
		if kind != "guard":
			finish_order(e)

func order(e: Dictionary, command: Dictionary, append := false) -> void:
	if not append:
		if WarPlatelets.is_platelet(e): platelets.detach(e)
		reset_path(e)
		e.orders = []
		e.erase("cellShot")
		e.movementSpeed = 0.0
		e.travelSpeed = 0.0
		e.orderToken = int(e.get("orderToken",0))+1
	e.orders.append(command.duplicate(true))
	e.pathFailed = false

func finish_order(e: Dictionary) -> void:
	if not e.orders.is_empty():
		e.orders.pop_front()
	reset_path(e)

func reset_path(e: Dictionary) -> void:
	if e.get("request",0) != 0:
		navigation.cancel(int(e.request))
		_requests.erase(int(e.request))
	e.request = 0
	e.path = []
	e.pathIndex = 0
	e.pathPending = false
	e.pathFailed = false
	e.erase("pathGoal")

func go(e: Dictionary, target: Vector2, dt: float, reach := .05, target_lane := -1) -> bool:
	if e.kind == WarTCellRuntime.KIND: return t_cells.go(e,target,dt,reach,target_lane)
	var p := WarData.point(e)
	if not navigation.ground_mode and e.kind in ["heavy","siege"] and e.get("requiresHeart",false):
		var destination := navigation.organ_at(target,e.kind)
		if navigation._box_has(navigation.organs.heart.sourceBox,target): destination = "heart"
		if not destination in ["liver","heart"]:
			if not e.pathFailed: notify("强力细胞需要先到心脏，再向其他器官转运")
			e.pathFailed = true
			return false
	var arrived_on_plane := target_lane < 0 or int(e.get("vesselLane",0)) == target_lane
	if p.distance_to(target) <= reach and arrived_on_plane:
		reset_path(e)
		return true
	if e.get("pathGoal",Vector2(INF,INF)).distance_to(target) > .5:
		reset_path(e)
	if not e.pathPending and e.path.is_empty():
		if e.pathFailed:
			if state.time < float(e.get("retryAt",0)):
				return false
			e.pathFailed = false
		var destination := target
		if reach > .1:
			for blocker in navigation.blockers:
				if WarData.point(blocker).distance_to(target) < .1:
					destination = navigation.building_approach(e,blocker,reach)
					break
		if not destination.is_finite():
			e.pathGoal = target; e.pathFailed = true; e.retryAt = float(state.time)+3.0
			if selected.has(int(e.id)): notify("建筑周围没有可通行的施工位置")
			return false
		var request := navigation.request(e,destination,target_lane)
		e.request = request
		e.pathGoal = target
		e.pathPending = true
		_requests[request] = int(e.id)
	if e.pathPending:
		return false
	var spec := WarData.spec(e.kind)
	var velocity := float(spec.get("speed",2.4)) * combat.multiplier(e,"moveMultiplier")
	if float(e.get("satiety",100)) < 20 or float(e.get("sanity",100)) < 25 or float(e.get("temp",22)) < 5 or float(e.get("temp",22)) > 35: velocity *= .65
	var organ := navigation.organ_at(p,e.kind) if not is_campaign() and int(e.get("vesselLane",0)) == 0 else ""
	if organ in ["small_intestine","large_intestine"]:
		velocity *= float(WarData.config().CombatConfig.intestine.moveMultiplier)
	elif mode == "sandbox":
		velocity *= float(survival.biome(p).get("move",1))
	velocity *= scenarios.speed_multiplier(e)
	if state.time-float(e.get("lastTravel",-10)) > dt*1.5: e.movementSpeed = 0.0
	e.lastTravel = state.time
	var wanted := velocity*clampf((p.distance_to(target)-reach)/.7,.22,1)
	e.movementSpeed = lerpf(float(e.get("movementSpeed",0)),wanted,1-exp(-dt/.14))
	var distance := float(e.movementSpeed)*dt
	while distance > .000001 and int(e.pathIndex) < e.path.size():
		var waypoint: Dictionary = e.path[e.pathIndex]
		var next: Vector2 = waypoint.p
		var length := p.distance_to(next)
		var flow := 1.0
		if not navigation.ground_mode and not is_campaign():
			flow = navigation.blood_flow.multiplier(int(e.get("vesselLane",0)),p,next-p)
		var step := minf(distance*flow,length)
		var proposed := p.move_toward(next,step)
		if not _position_free(e,proposed):
			e.blockedSince = float(e.get("blockedSince",state.time))
			if state.time-float(e.blockedSince) > 1.5:
				reset_path(e)
				e.erase("blockedSince")
			return false
		if length > .00001:
			e.moveHeading = (next-p).angle()
		p = proposed
		e.x = p.x
		e.y = p.y
		if e.has("renderTrail"): e.renderTrail.append(p)
		e.travelSpeed = velocity*flow
		e.combatState = "move"
		# Spend base-speed distance so a bend/lane change within this tick can
		# recalculate the current without inheriting the previous tube's bonus.
		distance -= step/flow
		if p.distance_to(next) <= .0001:
			e.vesselLane = int(waypoint.lane)
			e.pathIndex += 1
		else:
			break
	if int(e.pathIndex) >= e.path.size() and not e.path.is_empty():
		e.path = []
		e.pathIndex = 0
	return p.distance_to(target) <= reach and (target_lane < 0 or int(e.get("vesselLane",0)) == target_lane)

func _path_ready(request: int, path: Array, reason: String) -> void:
	var e := entity(int(_requests.get(request,0)))
	_requests.erase(request)
	if e.is_empty() or int(e.get("request",0)) != request:
		return
	e.pathPending = false
	e.path = path
	e.pathIndex = 1 if path.size() > 1 else 0
	e.pathFailed = path.is_empty()
	e.retryAt = float(state.time)+3.0
	if not reason.is_empty() and selected.has(e.id):
		notify(reason)

func _position_free(e: Dictionary,p: Vector2) -> bool:
	if int(e.get("vesselLane",0)) == 0:
		for blocker in navigation.blockers:
			if blocker.kind == "gate" and blocker.faction == e.faction: continue
			var radius := float(WarData.spec(blocker.kind).get("size",1))*.5+WarData.radius(e.kind)
			if Rect2(WarData.point(blocker)-Vector2.ONE*radius,Vector2.ONE*radius*2).has_point(p): return false
	for other in units():
		if other.id == e.id or int(other.get("vesselLane",0)) != int(e.get("vesselLane",0)):
			continue
		var overlap := WarCellShape.contact(e,other,p,Vector2(INF,INF),.002)
		if not overlap.is_empty() and p.distance_to(WarData.point(other)) < WarData.point(e).distance_to(WarData.point(other))-.000001:
			return false
	return true

func _resolve_units() -> void:
	var list := units()
	list.sort_custom(func(a,b): return int(a.id) < int(b.id))
	for attempt in 24:
		var changed := false
		for i in list.size():
			for j in range(i+1,list.size()):
				var a: Dictionary = list[i]
				var b: Dictionary = list[j]
				if a.get("vesselLane",0) != b.get("vesselLane",0): continue
				var contact := WarCellShape.contact(a,b,Vector2(INF,INF),Vector2(INF,INF),.002)
				if contact.is_empty() or float(contact[0]) <= .000001: continue
				changed = true
				var displacement: Vector2 = contact[1]*(float(contact[0])+.000002)
				var a_weight := WarPlatelets.push_scale(a)
				var b_weight := WarPlatelets.push_scale(b)
				var total := a_weight+b_weight
				for pair in [[a,WarData.point(a),WarData.point(a)+displacement*a_weight/total],[b,WarData.point(b),WarData.point(b)-displacement*b_weight/total]]:
					var e: Dictionary = pair[0]
					if navigation.clear_segment(pair[1],pair[2],int(e.get("vesselLane",0)),e.kind): e.x = pair[2].x; e.y = pair[2].y
		if not changed: return

func issue(kind: String, target := Vector2.ZERO, append := false, target_id := 0) -> void:
	submit_player({"action":"issue","kind":kind,"x":target.x,"y":target.y,"append":append,"target":target_id,"ids":selected.duplicate()})

func submit_player(command: Dictionary) -> void:
	if not command.has("ids"): command.ids = selected.duplicate()
	state.commands.append(command.duplicate(true))
	if paused: notify("命令已排队，恢复时间后执行")

func _process_player_commands() -> void:
	var commands: Array = WarData.array(state.get("commands",[]))
	state.commands = []
	for command in commands:
		match command.get("action",""):
			"issue":
				var old := selected.duplicate()
				selected.assign(command.ids)
				_execute_issue(command.kind,Vector2(command.x,command.y),command.get("append",false),int(command.get("target",0)))
				selected.assign(old)
			"unit_order":
				var e := entity(int(command.unit))
				if not e.is_empty(): order(e,command.order,command.get("append",false))
			"reinforce": scenarios.reinforce()
			"place":
				var workers: Array[int] = []
				workers.assign(command.ids)
				economy.place(command.building,Vector2(command.x,command.y),workers,1,command.get("append",false))
			"skip_wave": scenarios.skip_wave()
			"isolate": scenarios.isolate(command.closed)
			"train":
				var e := entity(int(command.target))
				if not e.is_empty(): economy.train(e,command.unit)
			"research":
				var e := entity(int(command.target))
				if not e.is_empty(): economy.research(e,command.tech)
			"medicine_buy":
				if not command.get("request") is Dictionary or not WarMedicineHelpers._integer(command.get("quantity"),1) or not WarMedicineHelpers._integer(command.get("unitPrice"),0):
					notify("药品命令无效")
				else:
					var result := medicine_supply.purchase(command.request,str(command.get("medicine","")),int(command.quantity),int(command.unitPrice))
					notify("已购买退烧止痛药" if result.ok else str(result.reason))
			"medicine_deploy":
				if not command.get("request") is Dictionary or command.get("medicine","") != WarMedicineHelpers.KIND or not WarMedicineHelpers._integer(command.get("actor"),1):
					notify("药品命令无效")
				else:
					var result := medicine_supply.deploy(command.request,int(command.actor),command.get("ids",[]))
					notify("降温消防员已派遣" if result.ok else str(result.reason))
			"organ_action":
				var action := str(command.get("organAction",""))
				var result := organ_functions.request(action,int(command.get("actor",0)),1)
				notify(str(WarOrganFunctions.data().actions[action].name) if result.ok else str(result.reason))
			"rally":
				var e := entity(int(command.target))
				if not e.is_empty() and e.category == "building" and e.faction == 1: e.rally = {"x":command.x,"y":command.y}

func _execute_issue(kind: String, target := Vector2.ZERO, append := false, target_id := 0) -> void:
	var troops: Array = []
	for id in selected:
		var e := entity(id)
		if not e.is_empty() and e.faction == 1 and e.category == "unit": troops.append(e)
	troops.sort_custom(func(a,b): return int(a.id) < int(b.id))
	var places: Dictionary = {}
	if is_fullbody() and kind in ["move","attackmove"] and not troops.is_empty():
		var profile: Dictionary = troops[0]
		var preferred := int(profile.get("vesselLane",0))
		for e in troops:
			if WarData.radius(e.kind) > WarData.radius(profile.kind): profile = e
			if int(e.get("vesselLane",0)) != preferred: preferred = -1
		var lane := navigation.command_lane(target,profile.kind,preferred)
		if not navigation.point_allowed(target,lane,profile.kind):
			notify("专用通路和组织墙不能进入，请选择有足够净空的地面")
			return
		places = formation(troops,target,lane)
	if kind in ["move","attackmove"] and not troops.is_empty() and troops.all(func(e): return WarPlatelets.is_platelet(e)):
		var preferred := int(troops[0].get("vesselLane",0))
		var lane := navigation.command_lane(target,"scout",preferred) if is_fullbody() else navigation.pick_lane(target,"scout",preferred)
		if lane >= 0:
			var line := platelets.formation(troops,target,lane)
			if not line.is_empty(): places = line
	for e in troops:
		if kind in ["stop","hold"]:
			if e.kind == WarTCellRuntime.KIND: t_cells.stop_order(e,kind=="stop")
			reset_path(e)
			e.orders = [] if kind == "stop" else [{"kind":"hold"}]
			e.erase("cellShot")
			if e.kind == WarMedicineHelpers.KIND: e.erase("medicineAttack")
			e.movementSpeed = 0.0
			continue
		var p := target
		if kind == "retreat": p = scenarios.home()
		var command := {"kind":kind,"x":p.x,"y":p.y,"target":target_id}
		if places.has(int(e.id)):
			if places[int(e.id)].get("failed",false): order(e,{"kind":"stop"},false); continue
			command.merge(places[int(e.id)],true)
		else: command.lane = navigation.pick_lane(p,e.kind,int(e.get("vesselLane",0))) if not is_campaign() else 0
		order(e,command,append)
	if not troops.is_empty(): notify("已向 %d 个细胞下达命令" % troops.size())

func formation(troops: Array,target: Vector2,lane: int) -> Dictionary:
	# Teammate local_navigation.lua's isolated repair: a clear nearby single-cell
	# move keeps its target, without relaxing geometry, changing lanes or teleporting.
	if is_fullbody() and troops.size() == 1:
		var e: Dictionary = troops[0]
		var start := WarData.point(e)
		if lane == int(e.get("vesselLane",0)) and start.distance_squared_to(target) <= 64 and navigation.point_allowed(target,lane,e.kind) and navigation.clear_segment(start,target,lane,e.kind) and navigation.movement_clear(start,target,e.kind,int(e.faction)):
			var clear := true
			for other in units():
				if other.id != e.id and int(other.get("vesselLane",0)) == lane and not WarCellShape.contact(e,other,target).is_empty(): clear = false; break
			if clear: return {int(e.id):{"x":target.x,"y":target.y,"lane":lane}}
	# OrganBattlefieldCore.formation's deterministic ring search and tissue gap.
	var result: Dictionary = {}
	var largest := 0.0
	var selected_ids: Array = []
	for e in troops: largest = maxf(largest,WarData.radius(e.kind)); selected_ids.append(int(e.id))
	var reserved: Array = []
	var blockers := units().filter(func(e): return not selected_ids.has(int(e.id)))
	for e in troops:
		var placed := false
		for ring in 49:
			var radius := ring*.5
			var count := 1 if ring == 0 else maxi(12,ceili(radius*PI*4))
			for i in count:
				var p := target+Vector2.from_angle(float(i)*TAU/count)*radius
				if not navigation.point_allowed(p,lane,e.kind): continue
				var gap := largest*2+.2 if lane == 0 else .15
				var free := true
				for other in reserved+blockers:
					var clearance := WarData.radius(e.kind)+WarData.radius(other.kind)+gap
					if p.distance_squared_to(WarData.point(other)) < clearance*clearance: free = false; break
				if free:
					result[int(e.id)] = {"x":p.x,"y":p.y,"lane":lane}
					reserved.append({"x":p.x,"y":p.y,"kind":e.kind})
					placed = true
					break
			if placed: break
		if not placed: result[int(e.id)] = {"failed":true}
	return result

func spawn(kind: String, faction: int, p: Vector2, category := "unit") -> Dictionary:
	var lane := navigation.pick_lane(p,kind) if not is_campaign() else 0
	if lane < 0 or ((is_campaign() or navigation.ground_mode) and not navigation.campaign_clear(p,p)):
		return {}
	var spec := WarData.spec(kind)
	if spec.is_empty():
		return {}
	var id := int(state.nextId)
	state.nextId = id+1
	var e := {"id":id,"kind":kind,"faction":faction,"category":category,"x":p.x,"y":p.y,
		"previousX":p.x,"previousY":p.y,"hp":float(spec.hp),"maxHp":float(spec.hp),
		"vesselLane":lane,"complete":true,"progress":1.0,"cooldown":0.0,
		"orders":[],"path":[],"pathIndex":0,"pathPending":false,"pathFailed":false,
		"queue":[],"cargo":{},"statuses":{},"orderToken":0,"combatState":"idle"}
	state.entities[str(id)] = e
	return e

func visible(e: Dictionary, faction := 1) -> bool:
	if e.faction == faction:
		return true
	if WarDendriticCells.concealed(e): return dendritic.marked(e,faction)
	if dendritic.marked(e,faction): return true
	for ally in entities():
		if ally.faction == faction and ally.hp > 0:
			var vision := float(WarData.spec(ally.kind).get("vision",10))
			if WarData.point(e).distance_to(WarData.point(ally)) <= vision:
				return true
	return false

func snapshot() -> Dictionary:
	medicine_helpers.capture()
	var result := state.duplicate(true)
	result.tCellRuntime = t_cells.snapshot()
	for e in result.entities.values():
		for key in ["path","pathGoal","request","cellShot","previousX","previousY","blockedSince","renderTrail"]:
			e.erase(key)
		for key in ["plateletLinks","plateletLinkStarted"]: e.erase(key)
		e.pathPending = false
		e.pathFailed = false
	return result

func dispose() -> void:
	if navigation.path_ready.is_connected(_path_ready): navigation.path_ready.disconnect(_path_ready)
	navigation.dispose()
	combat.game = null
	economy.game = null
	scenarios.game = null
	survival.game = null
	resource_generation.game = null
	organ_resources.game = null
	organ_functions.dispose()
	influenza.game = null
	life.game = null
	platelets.game = null
	b_cells._sources.clear()
	b_cells.game = null
	dendritic._sources.clear()
	medicine_helpers.dispose()
	medicine_supply.dispose()
	t_cells.dispose()
	dendritic.game = null
