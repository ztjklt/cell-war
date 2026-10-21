class_name WarTCellRuntime
extends RefCounted
## Host bridge. Only native navigation callbacks approve paths and layer edges.
const KIND := "t_cell"
const NEAR := .002
var game: WarSimulation
var cells := WarTCells.new()
var _plans: Dictionary = {}
var _jobs: Dictionary = {}
var _serial := 0

func _init(owner: WarSimulation) -> void:
	game = owner
	_bind()
	game.navigation.path_ready.connect(_path_ready)

func _bind() -> void:
	cells.bind_world(_geometry,_landing,
		func(source,target,amount,direction): game.combat.damage(source,target,amount,false,"projectile",direction),
		func(target): return float(WarTCells.data().radius) if target.kind==KIND else WarData.radius(target.kind),
		_multiplier,_target_geometry)

func reset() -> void:
	_jobs.clear(); _plans.clear(); _serial = 0
	cells = WarTCells.new(); _bind()
	var saved: Dictionary = game.state.get("tCellRuntime",{})
	if saved.is_empty(): cells.restore({"schema":WarTCells.SCHEMA,"clock":float(game.state.time),"nextProjectileId":1,"actors":{},"projectiles":[]})
	else:
		cells.restore(saved.cells); _plans = saved.plans.duplicate(true); _serial = int(saved.serial)
		for plan in _plans.values(): plan.request = 0; plan.sent = -1
	game.state.erase("tCellRuntime") # Capture the current service at snapshot boundaries.

func snapshot() -> Dictionary:
	var plans := _plans.duplicate(true)
	for plan in plans.values(): plan.request = 0
	return {"version":1,"cells":cells.snapshot(),"plans":plans,"serial":_serial}

func dispose() -> void:
	if game == null: return
	if game.navigation.path_ready.is_connected(_path_ready): game.navigation.path_ready.disconnect(_path_ready)
	cells.bind_world(Callable(),Callable()); _plans.clear(); _jobs.clear(); game = null

func _sync_order(e: Dictionary) -> void:
	var key := str(int(e.id)); var plan: Dictionary = _plans.get(key,{})
	if not plan.is_empty() and int(plan.orderToken)!=int(e.orderToken):
		_cancel_request(plan)
		if not _in_transit(e,plan): _plans.erase(key)
		else: plan.orderToken = int(e.orderToken); plan.parked = true; plan.sent = -1
		cells.stop(e)
		e.tCellStopped = false

func stop_order(e: Dictionary,stopped := true) -> void:
	var plan: Dictionary = _plans.get(str(int(e.id)),{})
	if not plan.is_empty():
		_cancel_request(plan)
		if not _in_transit(e,plan): _plans.erase(str(int(e.id)))
		else: plan.parked = true; plan.sent = -1
	cells.stop(e); e.tCellStopped = stopped

func _cancel_request(plan: Dictionary) -> void:
	var token := int(plan.get("request",0))
	if token>0: game.navigation.cancel(token); _jobs.erase(token); plan.request = 0

func go(e: Dictionary,target: Vector2,_dt: float,reach := .05,target_lane := -1) -> bool:
	_sync_order(e)
	if target_lane < 0: target_lane = game.navigation.command_lane(target,KIND,int(e.vesselLane))
	if target_lane<0: return false
	if WarData.point(e).distance_to(target)<=reach and int(e.vesselLane)==target_lane:
		stop_order(e,false); return true
	var key := str(int(e.id)); var plan: Dictionary = _plans.get(key,{})
	var changed := plan.is_empty() or Vector2(plan.goalX,plan.goalY).distance_to(target)>.5 or int(plan.goalLane)!=target_lane
	if changed and not plan.is_empty() and _in_transit(e,plan):
		plan.goalX = target.x; plan.goalY = target.y; plan.goalLane = target_lane; plan.reach = reach; plan.parked = false
		var leg: Dictionary = plan.legs[int(plan.leg)]
		leg.returning = target_lane==int(leg.a.lane) and (target_lane>0 or game.navigation.organ_at(target,KIND)==str(leg.a.get("organ","")))
		plan.sent = -1; cells.stop(e); _feed(e,plan); return false
	if changed:
		if not plan.is_empty(): _cancel_request(plan)
		cells.stop(e)
		plan = {"orderToken":int(e.orderToken),"goalX":target.x,"goalY":target.y,"goalLane":target_lane,"reach":reach,"legs":[],"leg":0,"sent":-1,"request":0,"retryAt":0.0,"parked":false}
		_plans[key] = plan
	plan.parked = false; e.tCellStopped = false
	if plan.legs.is_empty() and int(plan.request)==0 and float(game.state.time)>=float(plan.retryAt):
		var destination := target
		if reach>.1:
			for b in game.navigation.blockers:
				if WarData.point(b).distance_to(target)<.1: destination = game.navigation.building_approach(e,b,reach); break
			for other in game.units():
				if int(other.id)!=int(e.id) and WarData.point(other).distance_to(target)<.1:
					destination = target+(WarData.point(e)-target).normalized()*maxf(float(WarTCells.data().radius)+WarData.radius(other.kind)+.1,reach-.1)
					break
		if not destination.is_finite(): plan.retryAt = float(game.state.time)+1; return false
		var token := game.navigation.request(e,destination,target_lane)
		plan.request = token; _jobs[token] = int(e.id)
	_feed(e,plan)
	return false

func _plain(node: Dictionary) -> Dictionary:
	var p := WarData.point(node.p) if node.get("p") is Vector2 else WarData.point(node)
	return {"x":p.x,"y":p.y,"lane":int(node.lane),"gate":str(node.get("gate","")),"organ":str(node.get("organ",""))}

func _path_ready(token: int,path: Array,_reason: String) -> void:
	if not _jobs.has(token): return
	var id := int(_jobs[token]); _jobs.erase(token)
	var e := game.entity(id); var plan: Dictionary = _plans.get(str(id),{})
	if e.is_empty() or plan.is_empty() or int(plan.request)!=token or int(plan.orderToken)!=int(e.orderToken): return
	plan.request = 0; plan.legs = []; plan.leg = 0; plan.sent = -1
	if path.is_empty(): plan.retryAt = float(game.state.time)+1; return
	var group: Array = [_plain(path[0])]
	for i in range(1,path.size()):
		var a := _plain(path[i-1]); var b := _plain(path[i])
		if int(a.lane)!=int(b.lane):
			var edge := _certify(a,b)
			if edge.is_empty(): plan.legs = []; plan.retryAt = float(game.state.time)+1; return
			plan.legs.append({"type":"lane","points":group,"lane":int(a.lane)})
			edge.type = "handoff"; edge.returning = false; plan.legs.append(edge); group = [b]
		else: group.append(b)
	plan.legs.append({"type":"lane","points":group,"lane":int(group[-1].lane)})
	_feed(e,plan)

func _certify(a: Dictionary,b: Dictionary) -> Dictionary:
	if game.navigation.ground_mode or game.is_campaign(): return {}
	var net := game.navigation._network(WarNavigation.profile(KIND))
	var first: Array = []; var second: Array = []
	for id in net.meta:
		var node: Dictionary = net.meta[id]
		if int(node.lane)==int(a.lane) and (node.p as Vector2).distance_to(WarData.point(a))<=NEAR: first.append(int(id))
		if int(node.lane)==int(b.lane) and (node.p as Vector2).distance_to(WarData.point(b))<=NEAR: second.append(int(id))
	for x in first:
		for y in second:
			if net.graph.are_points_connected(x,y): return {"a":a,"b":b,"aNode":x,"bNode":y}
	return {}

func _edge_valid(e: Dictionary,leg: Dictionary) -> bool:
	var net := game.navigation._network(WarNavigation.profile(KIND))
	var x := int(leg.aNode); var y := int(leg.bNode)
	if not net.meta.has(x) or not net.meta.has(y) or not net.graph.are_points_connected(x,y): return false
	var a: Dictionary = net.meta[x]; var b: Dictionary = net.meta[y]
	if int(e.vesselLane) not in [int(a.lane),int(b.lane)]: return false
	if int(a.lane)!=int(leg.a.lane) or int(b.lane)!=int(leg.b.lane) or (a.p as Vector2).distance_to(WarData.point(leg.a))>NEAR or (b.p as Vector2).distance_to(WarData.point(leg.b))>NEAR: return false
	var gate := str(a.get("gate",b.get("gate","")))
	if not gate.is_empty():
		if gate!=str(b.get("gate","")): return false
		var checkpoint: Dictionary = game.navigation.gates.get(gate,{})
		var organ := str(a.get("organ",b.get("organ","")))
		if organ.is_empty(): organ = str(b.get("organ",""))
		if checkpoint.is_empty() or float(checkpoint.get("hp",0))<=0 or checkpoint.get("isolated",false) or not game.navigation.enabled_organs.has(organ): return false
		if int(checkpoint.faction)!=int(e.faction) and not checkpoint.get("breached",false): return false
	return true

func _in_transit(e: Dictionary,plan: Dictionary) -> bool:
	if int(plan.get("leg",0))>=plan.get("legs",[]).size(): return false
	var leg: Dictionary = plan.legs[int(plan.leg)]
	return leg.type=="handoff" and WarData.point(e).distance_to(WarData.point(leg.a))>NEAR and WarData.point(e).distance_to(WarData.point(leg.b))>NEAR

func _handoff(e: Dictionary) -> Dictionary:
	var plan: Dictionary = _plans.get(str(int(e.id)),{})
	if plan.is_empty() or int(plan.leg)>=plan.legs.size(): return {}
	var leg: Dictionary = plan.legs[int(plan.leg)]
	return leg if leg.type=="handoff" else {}

func _on_edge(p: Vector2,leg: Dictionary) -> bool:
	return Geometry2D.get_closest_point_to_segment(p,WarData.point(leg.a),WarData.point(leg.b)).distance_to(p)<=NEAR

func _feed(e: Dictionary,plan: Dictionary) -> void:
	if plan.get("parked",false) or plan.legs.is_empty(): return
	var s := cells.state_for(int(e.id))
	if not s.is_empty() and s.mode not in ["idle"]: return
	while int(plan.leg)<plan.legs.size():
		var leg: Dictionary = plan.legs[int(plan.leg)]
		var destination: Dictionary = leg.points[-1] if leg.type=="lane" else (leg.a if leg.returning else leg.b)
		if WarData.point(e).distance_to(WarData.point(destination))<=NEAR:
			if leg.type=="handoff":
				if not _edge_valid(e,leg) or not game.navigation.point_allowed(WarData.point(destination),int(destination.lane),KIND): return
				e.vesselLane = int(destination.lane)
				game.event("t_lane_handoff",{"source":e.id,"lane":e.vesselLane,"aNode":leg.aNode,"bNode":leg.bNode})
				if leg.returning: plan.legs = []; plan.leg = 0; plan.sent = -1; return
			plan.leg = int(plan.leg)+1; plan.sent = -1; continue
		if int(plan.sent)==int(plan.leg) and not s.get("needsRoute",false): return
		var path: Array = []
		if leg.type=="lane": path = leg.points
		else:
			if not _edge_valid(e,leg) or not _on_edge(WarData.point(e),leg): return
			path = [{"x":e.x,"y":e.y,"lane":int(e.vesselLane)},{"x":destination.x,"y":destination.y,"lane":int(e.vesselLane)}]
		_serial += 1
		if cells.set_route(e,path,_serial): plan.sent = int(plan.leg)
		return
	plan.legs = []; plan.leg = 0; plan.sent = -1

func _geometry(a: Vector2,b: Vector2,lane: int,e: Dictionary,purpose: String) -> bool:
	var edge := _handoff(e)
	if purpose=="blink" and not edge.is_empty():
		return _edge_valid(e,edge) and _on_edge(a,edge) and _on_edge(b,edge) and _buildings_clear(a,b,e)
	return game.navigation.clear_segment(a,b,lane,KIND) and (purpose=="knife" or lane>0 or _buildings_clear(a,b,e))

func _buildings_clear(a: Vector2,b: Vector2,e: Dictionary) -> bool:
	for blocker in game.navigation.blockers:
		if blocker.has("checkpointId") or blocker.kind=="gate" and int(blocker.faction)==int(e.faction): continue
		var radius := float(WarData.spec(blocker.kind).get("size",1))*.5+float(WarTCells.data().radius)
		if WarTCells._box_contact(a,b,WarData.point(blocker),radius)>=0: return false
	return true

func _landing(p: Vector2,lane: int,e: Dictionary) -> bool:
	var edge := _handoff(e)
	if not edge.is_empty():
		if not _edge_valid(e,edge) or not _on_edge(p,edge): return false
	elif not game.navigation.point_allowed(p,lane,KIND): return false
	if (lane==0 or not edge.is_empty()) and not _buildings_clear(p,p,e): return false
	var body := hull(e,p)
	for other in game.units():
		if int(other.id)==int(e.id): continue
		var relevant: bool = int(other.vesselLane)==lane or not edge.is_empty() and int(other.vesselLane) in [int(edge.a.lane),int(edge.b.lane)]
		if not relevant: continue
		var polygon := hull(other,WarData.point(other)) if other.kind==KIND else WarCellShape.hull(other)
		if not Geometry2D.intersect_polygons(body,polygon).is_empty(): return false
	return true

func _multiplier(e: Dictionary,field: String) -> float:
	var value := game.combat.multiplier(e,field)
	if field!="moveMultiplier": return value
	if float(e.get("satiety",100))<20 or float(e.get("sanity",100))<25 or float(e.get("temp",22))<5 or float(e.get("temp",22))>35: value *= .65
	if game.mode=="sandbox": value *= float(game.survival.biome(WarData.point(e)).get("move",1))
	elif int(e.vesselLane)==0 and game.navigation.organ_at(WarData.point(e),KIND) in ["small_intestine","large_intestine"]: value *= float(WarData.config().CombatConfig.intestine.moveMultiplier)
	if not game.navigation.ground_mode and not game.is_campaign(): value *= game.navigation.blood_flow.multiplier(int(e.vesselLane),WarData.point(e),Vector2.from_angle(float(e.get("moveHeading",0))))
	return value*game.scenarios.speed_multiplier(e)

func _target_geometry(source: Dictionary,target: Dictionary) -> Dictionary:
	var result := game.combat._target_geometry(target,int(source.vesselLane))
	if target.category=="unit": result.radius = float(WarTCells.data().radius) if target.kind==KIND else WarData.radius(target.kind)
	result.targetable = game.visible(target,int(source.faction))
	result.blocks = not target.has("checkpointId") or target.get("isolated",false) or int(target.faction)!=int(source.faction) and not target.get("breached",false)
	if target.has("checkpointId") and not result.blocks: result.targetable = false
	return result

func unit(e: Dictionary,dt: float) -> bool:
	if e.kind!=KIND: return false
	_sync_order(e)
	var order: Dictionary = e.orders[0] if not e.orders.is_empty() else {}
	var command := str(order.get("kind",""))
	if command in ["move","retreat","supplyroute"]:
		if go(e,WarData.point(order),dt,1.6 if command=="retreat" else .05,int(order.get("lane",-1))): game.finish_order(e)
		return true
	if command=="stop": stop_order(e,true); game.finish_order(e); return true
	if command not in ["","attack","attackmove","guard","hold"]: game.finish_order(e); return true
	var target := game.entity(int(order.get("target",0))) if command=="attack" else (game.guard_enemy(e,order) if command=="guard" else game.combat.enemy(e,float(WarTCells.data().unitDefinition.vision),command=="attackmove"))
	if not target.is_empty() and (float(target.hp)<=0 or target.faction==e.faction or not game.visible(target,int(e.faction))):
		stop_order(e,false)
		if command=="attack" and float(target.hp)<=0: game.finish_order(e)
		return true
	if not target.is_empty():
		if cells.begin_attack(e,target):
			var plan: Dictionary = _plans.get(str(int(e.id)),{})
			if not plan.is_empty():
				_cancel_request(plan)
				if _in_transit(e,plan): plan.parked = true
				else: _plans.erase(str(int(e.id)))
			e.combatState = "attack"; return true
		if cells.last_error()=="range_lane_or_geometry" and command!="hold" and not e.get("tCellStopped",false):
			var geometry := _target_geometry(e,target)
			go(e,geometry.point,dt,maxf(.2,float(WarTCells.data().weapon.range)-.2),int(geometry.lane))
		return true
	if command=="attack": game.finish_order(e)
	elif command in ["attackmove","guard"] and go(e,WarData.point(order),dt,.05,int(order.get("lane",-1))) and command!="guard": game.finish_order(e)
	return true

func advance(dt: float) -> void:
	# Host calls after ordinary impacts/knockback so an incoming hit wins a release.
	cells.advance_simulation(dt,game.entities())
	for e in game.units():
		if e.kind!=KIND: continue
		var plan: Dictionary = _plans.get(str(int(e.id)),{})
		if not plan.is_empty():
			var state := cells.state_for(int(e.id))
			if state.get("needsRoute",false) and _handoff(e).is_empty(): plan.legs = []; plan.leg = 0; plan.sent = -1; plan.retryAt = float(game.state.time)+.2
			else: _feed(e,plan)
	for event in cells.drain_events(): game.event(str(event.kind),event)
	for key in _plans.keys():
		var owner := game.entity(int(key))
		if owner.is_empty() or float(owner.hp)<=0: _plans.erase(key)

func hit(e: Dictionary) -> void:
	cells.notify_hit(e,float(game.state.time))
	var plan: Dictionary = _plans.get(str(int(e.id)),{})
	if not plan.is_empty():
		plan.sent = -1
		if not _in_transit(e,plan): _cancel_request(plan); _plans.erase(str(int(e.id)))

func sample(e: Dictionary,time: float) -> Dictionary:
	return cells.sample(e,time)

static func normalized(key: String,frame: int,field: String) -> PackedVector2Array:
	var d := WarTCells.data(); var source: Array = d.hull if field=="hull" else d.outlines.get(key,d.outlines.tBlink)[clampi(frame,0,d.outlines.get(key,d.outlines.tBlink).size()-1)]
	var result := PackedVector2Array()
	for p in source: result.append(Vector2(p[0],p[1]))
	return result

static func hull(e: Dictionary,p: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	for q in normalized("",0,"hull"): result.append(p+q*float(WarTCells.data().radius))
	return result

static func validate_state(state: Dictionary) -> String:
	if not state.has("tCellRuntime"): return ""
	var saved: Variant = state.tCellRuntime
	if not saved is Dictionary or saved.get("version")!=1 or not saved.get("cells") is Dictionary or not WarTCells.validate_snapshot(saved.cells).is_empty() or not saved.get("plans") is Dictionary: return "T细胞运行状态无效"
	if not state.get("entities") is Dictionary or not WarTCells._number(state.get("time")) or absf(float(saved.cells.clock)-float(state.time))>.00001: return "T细胞与世界时钟无效"
	if not WarTCells._integer(saved.get("serial"),0,2147483647) or saved.plans.size()>256: return "T细胞路径序号无效"
	for actor in saved.cells.actors.values():
		if int(actor.sequence)>int(saved.serial): return "T细胞路径序号倒退"
	for key in saved.plans:
		if not key is String or not key.is_valid_int() or not state.entities.has(key): return "T细胞路径单位无效"
		var e: Variant = state.entities[key]; var p: Variant = saved.plans[key]
		if not e is Dictionary or e.get("kind")!=KIND or not p is Dictionary or not p.get("legs") is Array or not WarTCells._integer(p.get("leg"),0,p.legs.size()): return "T细胞路径无效"
		if p.legs.size()>1024: return "T细胞路径过长"
		for field in ["goalX","goalY","reach","retryAt"]:
			if not WarTCells._number(p.get(field)) or float(p[field])<0: return "T细胞路径数值无效"
		if not WarTCells._lane(p.get("goalLane")) or not WarTCells._integer(p.get("orderToken"),0,2147483647) or not p.get("parked") is bool: return "T细胞路径参数无效"
		for leg in p.legs:
			if not leg is Dictionary or leg.get("type","") not in ["lane","handoff"]: return "T细胞路径段无效"
			var nodes: Array = leg.get("points",[]) if leg.type=="lane" else [leg.get("a",{}),leg.get("b",{})]
			if nodes.is_empty() or nodes.size()>512: return "T细胞路径节点无效"
			for node in nodes:
				if not node is Dictionary or not WarTCells._number(node.get("x")) or not WarTCells._number(node.get("y")) or not WarTCells._point(WarData.point(node)) or not WarTCells._lane(node.get("lane")): return "T细胞路径坐标无效"
			if leg.type=="handoff" and (not WarTCells._id(leg.get("aNode")) or not WarTCells._id(leg.get("bNode")) or not leg.get("returning") is bool): return "T细胞交接凭据无效"
	return ""
