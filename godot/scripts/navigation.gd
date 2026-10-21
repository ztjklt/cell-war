class_name WarNavigation
extends RefCounted

signal path_ready(token: int, path: Array, reason: String)
var organs: Dictionary
var profiles: Dictionary = {}
var grids: Dictionary = {}
var queue: Array = []
var active: Dictionary = {}
var token := 0
var gates: Dictionary = {}
var campaign: Dictionary = {}
var campaign_grid: WarGrid
var ground_mode := false
var enabled_organs: Array = []
var blockers: Array = []
var _lane_boxes: Dictionary = {}
var _crossings: Dictionary = {}
var blood_flow := WarBloodFlow.new(WarData.read("vessels"))

func _init() -> void:
	organs = WarData.read("organs")
	enabled_organs = organs.keys()

func grid(organ: String, profile: String) -> WarGrid:
	var key := organ + "_" + profile
	if not grids.has(key):
		grids[key] = WarGrid.new(WarData.read("navigation/" + key))
	return grids[key]

static func profile(kind: String) -> String:
	return "scout" if WarData.radius(kind) * 0.5 <= 0.21875 else "siege"

func organ_at(p: Vector2, kind := "worker") -> String:
	var pr := profile(kind)
	# Heart's foreground cutaway has precedence over a lung behind it.
	if enabled_organs.has("heart") and _box_has(organs.heart.sourceBox, p):
		if WarGrid.inside(grid("heart",pr).rings,p):
			return "heart"
		return ""
	for id in organs:
		if not enabled_organs.has(id): continue
		if _box_has(organs[id].sourceBox,p) and WarGrid.inside(grid(id,pr).rings,p):
			return id
	return ""

func _box_has(box: Array, p: Vector2) -> bool:
	var q := WarData.world_to_source(p)
	return q.x >= box[0] and q.x <= box[2] and q.y >= box[1] and q.y <= box[3]

func _network(pr: String) -> Dictionary:
	if profiles.has(pr):
		return profiles[pr]
	var graph := AStar2D.new()
	var meta: Dictionary = {}
	var lane_nodes: Dictionary = {}
	var endpoints: Dictionary = {}
	var domains: Dictionary = {}
	var data: Dictionary = WarData.read("blood_"+pr)
	for key in data.domains:
		domains[int(key)] = WarGrid.prepare_rings(data.domains[key])
	var id := 1
	for lane in WarData.read("vessels").lanes:
		var index := int(lane.lane)
		lane_nodes[index] = []
		for point in lane.points:
			var p := WarData.point(point)
			graph.add_point(id,p)
			meta[id] = {"p":p,"lane":index,"organ":""}
			var previous: Array = lane_nodes[index]
			if not previous.is_empty():
				graph.connect_points(previous[-1],id)
			previous.append(id)
			id += 1
		var first: int = lane_nodes[index][0]
		var last: int = lane_nodes[index][-1]
		for pair in [[str(lane.a),first],[str(lane.b),last]]:
			if not endpoints.has(pair[0]):
				endpoints[pair[0]] = []
			endpoints[pair[0]].append(pair[1])
	# Share only named endpoints; projected crossings remain disconnected.
	for group in endpoints.values():
		for a in group:
			for b in group:
				if a < b and graph.get_point_position(a).distance_to(graph.get_point_position(b)) < 0.02:
					graph.connect_points(a,b)
	# Authored local adapters also join lanes in their interiors (notably the
	# repaired bowel network). Those connections have explicit polygon contracts.
	for join in data.joins:
		var a_lane := int(join.aLane)
		var b_lane := int(join.bLane)
		if not lane_nodes.has(a_lane) or not lane_nodes.has(b_lane): continue
		var at := WarData.source_to_world(join.get("source",[0,0]))
		var a_id := _closest_unchecked(at,lane_nodes[a_lane],meta)
		var b_id := _closest_unchecked(at,lane_nodes[b_lane],meta)
		if a_id < 0 or b_id < 0 or a_id == b_id: continue
		var combined: Array = domains[a_lane].duplicate()
		combined.append_array(domains[b_lane])
		combined.append_array(WarGrid.prepare_rings(join.get("safeRings",[])))
		if WarGrid.segment_inside(combined,meta[a_id].p,meta[b_id].p):
			graph.connect_points(a_id,b_id)
	var gate_nodes: Dictionary = {}
	for oid in organs:
		var g := grid(oid,pr)
		gate_nodes[oid] = []
		for gate in organs[oid].gateContracts[pr]:
			var outer := WarData.source_to_world(gate.tissueAnchorSource)
			var inner := WarData.source_to_world(gate.pipeAnchorSource)
			var lane := int(gate.laneIndex)
			var component := g.component(outer)
			if component == 0 or not lane_nodes.has(lane):
				continue
			var outer_id := id
			id += 1
			var inner_id := id
			id += 1
			graph.add_point(outer_id,outer)
			graph.add_point(inner_id,inner)
			meta[outer_id] = {"p":outer,"lane":0,"organ":oid,"gate":gate.id,"component":component}
			meta[inner_id] = {"p":inner,"lane":lane,"organ":"","gate":gate.id}
			graph.connect_points(outer_id,inner_id)
			var best := _nearest_lane_node(inner,lane,lane_nodes,meta,domains)
			if best >= 0:
				graph.connect_points(inner_id,best)
			gate_nodes[oid].append(outer_id)
			for other in gate_nodes[oid]:
				if other != outer_id and meta[other].component == component:
					graph.connect_points(other,outer_id)
	var result := {"graph":graph,"meta":meta,"lanes":lane_nodes,"domains":domains,"gates":gate_nodes,"next":id}
	profiles[pr] = result
	return result

func _closest_unchecked(p: Vector2,candidates: Array,meta: Dictionary) -> int:
	var best := -1
	var distance := INF
	for id in candidates:
		var d := p.distance_squared_to(meta[id].p)
		if d < distance:
			distance = d
			best = int(id)
	return best

func _nearest_lane_node(p: Vector2, lane: int, lane_nodes: Dictionary, meta: Dictionary, domains: Dictionary) -> int:
	var candidates: Array = []
	for id in lane_nodes.get(lane,[]):
		candidates.append([p.distance_squared_to(meta[id].p),id])
	candidates.sort_custom(func(a,b): return a[0] < b[0])
	for i in mini(12,candidates.size()):
		var id: int = candidates[i][1]
		if WarGrid.segment_inside(domains.get(lane,[]),p,meta[id].p):
			return id
	return -1

func pick_lane(p: Vector2, kind := "worker", preferred := -1) -> int:
	if not campaign.is_empty() or ground_mode:
		return 0 if campaign_clear(p,p) else -1
	var pr := profile(kind)
	var network := _network(pr)
	if preferred > 0 and WarGrid.inside(network.domains.get(preferred,[]),p):
		return preferred
	for lane in range(203,211):
		if WarGrid.inside(network.domains.get(lane,[]),p):
			return lane
	if organ_at(p,kind) != "":
		return 0
	for lane in network.domains:
		if WarGrid.inside(network.domains[lane],p):
			return lane
	return -1

func clear_segment(a: Vector2,b: Vector2,lane: int,kind := "worker") -> bool:
	if not campaign.is_empty() or ground_mode:
		return campaign_clear(a,b)
	var pr := profile(kind)
	if lane > 0:
		return WarGrid.segment_inside(_network(pr).domains.get(lane,[]),a,b)
	var oid := organ_at(a,kind)
	return oid != "" and WarGrid.segment_inside(grid(oid,pr).rings,a,b)

func point_allowed(p: Vector2,lane: int,kind: String) -> bool:
	return lane >= 0 and clear_segment(p,p,lane,kind)

func command_lane(p: Vector2,kind: String,preferred := -1) -> int:
	# OrganBattlefield.commandLane: membrane endpoints, cardiac cavities, current
	# blood lane, then the closest visible blood surface above the tissue floor.
	if ground_mode or not campaign.is_empty(): return pick_lane(p,kind,preferred)
	var pr := profile(kind)
	var radius := WarData.radius(kind)
	for oid in enabled_organs:
		for gate in organs[oid].gateContracts[pr]:
			var a := WarData.source_to_world(gate.pipeAnchorSource)
			var b := WarData.source_to_world(gate.tissueAnchorSource)
			var reach := minf(radius,a.distance_to(b)*.45)
			if p.distance_squared_to(b) <= reach*reach and point_allowed(p,0,kind): return 0
			if p.distance_squared_to(a) <= reach*reach and point_allowed(p,int(gate.laneIndex),kind): return int(gate.laneIndex)
	var current := pick_lane(p,kind)
	if current >= 203 and current <= 210: return current
	if preferred > 0 and point_allowed(p,preferred,kind): return preferred
	var best := -1
	var nearest := INF
	for lane in WarData.read("vessels").lanes:
		var index := int(lane.lane)
		if not _lane_boxes.has(index):
			var bounds := Rect2(WarData.point(lane.points[0]),Vector2.ZERO)
			for point in lane.points: bounds = bounds.expand(WarData.point(point))
			_lane_boxes[index] = bounds.grow(float(lane.width)*.5)
		if not _lane_boxes[index].has_point(p) or not point_allowed(p,index,kind): continue
		if not _crossings.has(index):
			var crossing: Dictionary = WarData.read("presentation").crossings.get(str(index),{})
			_crossings[index] = WarGrid.prepare_rings(crossing.get("rings",[]))
		if WarGrid.inside(_crossings[index],p): continue
		var distance := INF
		for i in range(1,lane.points.size()):
			var a := WarData.point(lane.points[i-1])
			var b := WarData.point(lane.points[i])
			distance = minf(distance,p.distance_to(Geometry2D.get_closest_point_to_segment(p,a,b)))
		if distance < nearest and distance <= float(lane.width)*.5: best = index; nearest = distance
	return best if best >= 0 else current

func request(entity: Dictionary, target: Vector2, target_lane := -1) -> int:
	token += 1
	var job := {"token":token,"from":WarData.point(entity),"to":target,"kind":entity.kind,
		"lane":int(entity.get("vesselLane",0)),"target_lane":target_lane,"faction":int(entity.faction)}
	# Keep delivery asynchronous: the simulation registers this token after return.
	# Certified direct routes need not wait behind a distant organ's grid search.
	job.direct = not _direct_path(job).is_empty()
	queue.append(job)
	return token

func _direct_path(job: Dictionary) -> Array:
	var a: Vector2 = job.from
	var b: Vector2 = job.to
	var lane := int(job.lane)
	var target_lane := int(job.target_lane)
	if not campaign.is_empty() or ground_mode:
		if campaign_clear(a,b) and movement_clear(a,b,job.kind,job.faction):
			return [{"p":a,"lane":0,"organ":"campaign"},{"p":b,"lane":0,"organ":"campaign"}]
		return []
	if target_lane < 0: target_lane = pick_lane(b,job.kind,lane)
	if target_lane != lane or not clear_segment(a,b,lane,job.kind): return []
	var organ := organ_at(a,job.kind) if lane == 0 else ""
	if lane == 0 and (organ.is_empty() or organ_at(b,job.kind) != organ or not movement_clear(a,b,job.kind,job.faction)): return []
	return [{"p":a,"lane":lane,"organ":organ},{"p":b,"lane":lane,"organ":organ}]

func building_approach(entity: Dictionary,building: Dictionary,reach: float) -> Vector2:
	var center := WarData.point(building)
	var origin := WarData.point(entity)
	var extent := float(WarData.spec(building.kind).get("size",1))*.5+WarData.radius(entity.kind)
	var side := extent+.12
	var preferred := center+(origin-center).normalized()*minf(side,reach*.95)
	var organ := organ_at(center,entity.kind) if campaign.is_empty() and not ground_mode else ""
	var friendly_gate: bool = building.kind == "gate" and int(building.faction) == int(entity.faction)
	var valid := func(point: Vector2) -> bool:
		if not point_allowed(point,0,entity.kind): return false
		if not organ.is_empty() and organ_at(point,entity.kind) != organ: return false
		var offset := (point-center).abs()
		if not friendly_gate and offset.x < extent and offset.y < extent: return false
		return movement_clear(point,point,entity.kind,int(entity.faction))
	# Keep existing axial/otherwise valid approaches exactly as before.
	if valid.call(preferred): return preferred
	# A radial distance can still lie inside the square collision footprint at a
	# diagonal. Sample the four exterior sides, bounded by the actual work reach.
	var radius := maxf(reach*.95,side)
	var span := minf(side,sqrt(maxf(0,radius*radius-side*side)))
	var candidates: Array[Vector2] = []
	for i in 9:
		var along := lerpf(-span,span,float(i)/8)
		for offset in [Vector2(-side,along),Vector2(side,along),Vector2(along,-side),Vector2(along,side)]:
			var point: Vector2 = center+offset
			if valid.call(point): candidates.append(point)
	candidates.sort_custom(func(a,b): return origin.distance_squared_to(a) < origin.distance_squared_to(b))
	# Prefer a genuinely clear local route; a projected vascular position cannot
	# take this tissue shortcut. Other reachable sides use the ordinary planner.
	for point in candidates:
		if int(entity.get("vesselLane",0)) == 0 and clear_segment(origin,point,0,entity.kind) and movement_clear(origin,point,entity.kind,int(entity.faction)):
			return point
	for point in candidates:
		var job := {"from":origin,"to":point,"kind":entity.kind,"faction":int(entity.faction),"lane":int(entity.get("vesselLane",0)),"target_lane":0}
		if not _plan(job).is_empty(): return point
	return Vector2.INF

func cancel(request_token: int) -> void:
	queue = queue.filter(func(job): return job.token != request_token)
	if active.get("token",0) == request_token:
		active = {}

func _plan(job: Dictionary) -> Array:
	var a: Vector2 = job.from
	var b: Vector2 = job.to
	var lane: int = job.lane
	var target_lane: int = job.target_lane
	if not campaign.is_empty() or ground_mode:
		return [{"p":a,"lane":0,"organ":"campaign"},{"p":b,"lane":0,"organ":"campaign"}]
	if target_lane < 0:
		target_lane = pick_lane(b,job.kind,lane)
	if target_lane < 0:
		return []
	var pr := profile(job.kind)
	var network := _network(pr)
	var graph: AStar2D = network.graph
	var meta: Dictionary = network.meta
	var ao := organ_at(a,job.kind) if lane == 0 else ""
	var bo := organ_at(b,job.kind) if target_lane == 0 else ""
	if lane == target_lane and (lane > 0 or ao == bo) and clear_segment(a,b,lane,job.kind):
		if lane > 0 or movement_clear(a,b,job.kind,job.faction):
			return [{"p":a,"lane":lane,"organ":ao},{"p":b,"lane":lane,"organ":bo}]
	if lane == 0 and target_lane == 0 and ao != "" and ao == bo:
		var g := grid(ao,pr)
		var from_component := g.component(a)
		var to_component := g.component(b)
		# A certified polygon attachment can bridge a corridor narrower than the
		# lattice, exactly as WarGrid.begin already permits. Do not detour to a
		# distant gate solely because the two nearest cells have different labels.
		if from_component > 0 and to_component > 0 and (from_component == to_component or g.attachment(a,to_component) >= 0 or g.attachment(b,from_component) >= 0):
			return [{"p":a,"lane":0,"organ":ao},{"p":b,"lane":0,"organ":bo}]
	# Gate control can differ by faction without changing static geometry.
	for oid in network.gates:
		for id in network.gates[oid]:
			var gate: Dictionary = gates.get(meta[id].gate,{})
			var pathogen := WarData.is_pathogen(str(job.kind))
			var blocked: bool = not enabled_organs.has(oid) or gate.get("isolated",false) or (pathogen and not gate.get("breached",false))
			graph.set_point_disabled(id,blocked)
	var start: int = network.next
	var end := start+1
	graph.add_point(start,a)
	graph.add_point(end,b)
	for item in [[start,a,lane,ao],[end,b,target_lane,bo]]:
		var id: int = item[0]
		var p: Vector2 = item[1]
		var at_lane: int = item[2]
		var organ: String = item[3]
		meta[id] = {"p":p,"lane":at_lane,"organ":organ}
		if at_lane > 0:
			var near := _nearest_lane_node(p,at_lane,network.lanes,meta,network.domains)
			if near >= 0:
				graph.connect_points(id,near)
		elif organ != "":
			var component := grid(organ,pr).component(p)
			for other in network.gates[organ]:
				if component > 0 and (meta[other].component == component or grid(organ,pr).attachment(p,int(meta[other].component)) >= 0):
					graph.connect_points(id,other)
	var route: Array = []
	for id in graph.get_id_path(start,end):
		route.append(meta[id].duplicate())
	graph.remove_point(start)
	graph.remove_point(end)
	meta.erase(start)
	meta.erase(end)
	return route

func update(budget_usec := 3500) -> void:
	var deadline := Time.get_ticks_usec()+budget_usec
	for job in queue.duplicate():
		if Time.get_ticks_usec() >= deadline: break
		if not job.get("direct",false): continue
		# Buildings can have appeared since enqueueing; never reuse a stale clearance.
		var path := _direct_path(job)
		job.direct = false
		if path.is_empty(): continue
		queue.erase(job)
		path_ready.emit(job.token,path,"")
	while Time.get_ticks_usec() < deadline:
		if active.is_empty():
			if queue.is_empty():
				return
			active = queue.pop_front()
			active.legs = _plan(active)
			active.path = []
			active.index = 1
			if active.legs.is_empty():
				_finish("没有可通行的路线")
				continue
			active.path.append(active.legs[0])
		if active.has("search"):
			var search: WarGrid = active.search
			if not search.advance(maxi(100,deadline-Time.get_ticks_usec())):
				return
			if not search.found:
				var previous: Dictionary = active.legs[active.index-1]
				var next: Dictionary = active.legs[active.index]
				var detour := _building_corner_detour(previous.p,next.p,active.kind,int(active.faction),previous.organ)
				if detour.is_empty():
					_finish("组织通路受阻")
				else:
					for i in range(1,detour.size()-1): active.path.append({"p":detour[i],"lane":0,"organ":previous.organ})
					active.path.append(next) # Retain any authored gate/component metadata.
					active.erase("search")
					active.index += 1
				continue
			var leg: Dictionary = active.legs[active.index]
			for p in search.path():
				active.path.append({"p":p,"lane":0,"organ":leg.organ})
			active.path.append(leg)
			active.erase("search")
			active.index += 1
		if active.index >= active.legs.size():
			_finish("")
			continue
		var previous: Dictionary = active.legs[active.index-1]
		var next: Dictionary = active.legs[active.index]
		if previous.lane == 0 and next.lane == 0 and previous.organ == next.organ:
			var g: WarGrid = campaign_grid if previous.organ == "campaign" else grid(previous.organ,profile(active.kind))
			g.blockers = blockers
			g.moving_radius = WarData.radius(active.kind)
			g.moving_faction = int(active.faction)
			var direct := campaign_clear(previous.p,next.p) if previous.organ == "campaign" else WarGrid.segment_inside(g.rings,previous.p,next.p)
			direct = direct and movement_clear(previous.p,next.p,active.kind,active.faction)
			if direct:
				active.path.append(next)
				active.index += 1
			else:
				var search_from := _grid_search_endpoint(g,previous.p,active.kind,int(active.faction))
				var search_to := _grid_search_endpoint(g,next.p,active.kind,int(active.faction))
				if not search_from.is_finite() or not search_to.is_finite():
					_finish("目标附近被建筑阻挡")
				elif g.begin(search_from,search_to):
					active.search = g
				else:
					_finish("目标不在同一通行区域")
		else:
			active.path.append(next)
			active.index += 1

func _grid_search_endpoint(g: WarGrid,p: Vector2,kind: String,faction: int) -> Vector2:
	var nearest := g.nearest(p)
	if nearest >= 0 and not g.point_blocked(g.position_of(nearest)): return p
	# A legal exact approach point can round to a lattice cell inside a building.
	# Attach the search to a nearby free cell instead. The actual endpoint stays
	# in active.legs, and both added links require exact terrain/building clearance.
	var at := Vector2i(((p-g.origin)/g.spacing).round())
	var best := Vector2.INF
	var distance := INF
	for y in range(maxi(0,at.y-12),mini(g.height,at.y+13)):
		for x in range(maxi(0,at.x-12),mini(g.width,at.x+13)):
			var index := y*g.width+x
			if not g.valid[index]: continue
			var q := g.position_of(index)
			var d := p.distance_squared_to(q)
			if d >= distance or g.point_blocked(q): continue
			var clear: bool = g.segment_validator.call(p,q) if g.segment_validator.is_valid() else WarGrid.segment_inside(g.rings,p,q)
			if clear and movement_clear(p,q,kind,faction): best = q; distance = d
	return best

func _building_corner_detour(a: Vector2,b: Vector2,kind: String,faction: int,organ: String) -> Array[Vector2]:
	# Dynamic building clearance can leave a real corridor narrower than the
	# lattice spacing. Only after grid failure, try exact visible obstacle corners.
	# Every edge uses the same authored tissue polygons and building sweeps; this
	# never adds vascular connections or changes collision radii.
	var bounds := Rect2(a,b-a).abs().grow(12)
	var nearby: Array = []
	for blocker in blockers:
		if blocker.kind == "gate" and int(blocker.faction) == faction: continue
		var extent := float(WarData.spec(blocker.kind).get("size",1))*.5+WarData.radius(kind)
		var rect := Rect2(WarData.point(blocker)-Vector2.ONE*extent,Vector2.ONE*extent*2)
		if rect.intersects(bounds): nearby.append({"rect":rect,"distance":rect.get_center().distance_squared_to(a)})
	if nearby.is_empty(): return []
	nearby.sort_custom(func(x,y): return x.distance < y.distance)
	var points: Array[Vector2] = [a,b]
	for item in nearby.slice(0,16):
		# Margin is numerical clearance outside the unchanged collision footprint.
		var rect: Rect2 = item.rect.grow(.01)
		for point in [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]:
			if not point_allowed(point,0,kind) or not movement_clear(point,point,kind,faction): continue
			if organ != "campaign" and organ_at(point,kind) != organ: continue
			if not points.has(point): points.append(point)
	var graph := AStar2D.new()
	for i in points.size(): graph.add_point(i,points[i])
	for i in points.size():
		for j in range(i+1,points.size()):
			if clear_segment(points[i],points[j],0,kind) and movement_clear(points[i],points[j],kind,faction): graph.connect_points(i,j)
	var route: Array[Vector2] = []
	for id in graph.get_id_path(0,1): route.append(points[id])
	return route

func _finish(reason: String) -> void:
	var completed := active
	active = {}
	path_ready.emit(completed.token,completed.path if reason.is_empty() else [],reason)

func set_campaign(spec: Dictionary) -> void:
	campaign = spec
	ground_mode = false
	queue.clear()
	active = {}
	if spec.is_empty():
		campaign_grid = null
		return
	var bounds: Dictionary = spec.bounds
	var width := int(bounds.w)
	var height := int(bounds.h)
	var mask := Marshalls.base64_to_raw(spec.walkableBase64)
	var adj := PackedByteArray()
	adj.resize(mask.size())
	for y in height:
		for x in width:
			var at := y*width+x
			if mask[at] == 0:
				continue
			for bit in 8:
				var d: Vector2i = WarGrid.DIRS[bit]
				var q := Vector2i(x,y)+d
				if q.x < 0 or q.y < 0 or q.x >= width or q.y >= height or mask[q.y*width+q.x] == 0:
					continue
				if d.x != 0 and d.y != 0 and (mask[y*width+q.x] == 0 or mask[q.y*width+x] == 0):
					continue
				adj[at] |= 1<<bit
	var components := mask.duplicate()
	campaign_grid = WarGrid.new({"width":width,"height":height,
		"origin":[float(bounds.x)*.5,float(bounds.y)*.5-256],"step":.5,
		"validBase64":spec.walkableBase64,"adjacencyBase64":Marshalls.raw_to_base64(adj),
		"componentBase64":Marshalls.raw_to_base64(components),"safeRings":[]})
	campaign_grid.segment_validator = campaign_clear

func set_ground(which: String) -> void:
	campaign = {}
	ground_mode = true
	if which == "sandbox":
		var data: Dictionary = WarData.read("sandbox/grid").duplicate(true)
		var file := FileAccess.open("res://data/sandbox/valid.bin",FileAccess.READ)
		data.valid = file.get_buffer(file.get_length())
		file = FileAccess.open("res://data/sandbox/adjacency.bin",FileAccess.READ)
		data.adjacency = file.get_buffer(file.get_length())
		data.components = data.valid
		campaign_grid = WarGrid.new(data)
	else:
		var mask := PackedByteArray()
		mask.resize(70*70)
		mask.fill(1)
		var adj := PackedByteArray()
		adj.resize(mask.size())
		for y in 70:
			for x in 70:
				for bit in 8:
					var q: Vector2i = Vector2i(x,y)+WarGrid.DIRS[bit]
					if q.x >= 0 and q.y >= 0 and q.x < 70 and q.y < 70: adj[y*70+x] |= 1<<bit
		campaign_grid = WarGrid.new({"width":70,"height":70,"origin":[37.5,-218.5],"step":.5,
			"valid":mask,"adjacency":adj,"components":mask,"safeRings":[]})
	campaign_grid.segment_validator = campaign_clear

func campaign_clear(a: Vector2,b: Vector2) -> bool:
	if campaign_grid == null:
		return false
	var count := maxi(1,ceili(a.distance_to(b)*4.0))
	for i in count+1:
		var p := a.lerp(b,float(i)/count)
		var q := Vector2i((p-campaign_grid.origin).round())
		if q.x < 0 or q.y < 0 or q.x >= campaign_grid.width or q.y >= campaign_grid.height or campaign_grid.valid[q.y*campaign_grid.width+q.x] == 0:
			return false
	return true

func movement_clear(a: Vector2,b: Vector2,kind: String,faction: int) -> bool:
	for blocker in blockers:
		if blocker.kind == "gate" and int(blocker.faction) == faction: continue
		var radius := float(WarData.spec(blocker.kind).get("size",1))*.5+WarData.radius(kind)
		var rect := Rect2(WarData.point(blocker)-Vector2.ONE*radius,Vector2.ONE*radius*2)
		if rect.has_point(a) or rect.has_point(b): return false
		var p := rect.position
		var q := rect.end
		var points := [p,Vector2(q.x,p.y),q,Vector2(p.x,q.y)]
		for i in 4:
			if Geometry2D.segment_intersects_segment(a,b,points[i],points[(i+1)%4]) != null: return false
	return true

func dispose() -> void:
	if campaign_grid != null: campaign_grid.segment_validator = Callable()
	profiles.clear()
	grids.clear()
	queue.clear()
	active = {}
