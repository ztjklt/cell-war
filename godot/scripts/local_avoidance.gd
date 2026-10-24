class_name WarLocalAvoidance
extends RefCounted
## A short detour around cells, preserving the certified route and current plane.
## Run only on contact; every edge still passes terrain, building and swept-hull checks.
var jobs: Dictionary = {}
var remaining_usec := 3000

func route(game: WarSimulation,e: Dictionary,target: Vector2) -> Array:
	var origin := WarData.point(e)
	var lane := int(e.get("vesselLane",0))
	var goal := target
	if not game.navigation.clear_segment(goal,target,lane,e.kind) or (lane == 0 and not game.navigation.movement_clear(goal,target,e.kind,int(e.faction))):
		jobs.erase(int(e.id))
		return []
	var neighbors := game.units().filter(func(other): return other.id != e.id and int(other.get("vesselLane",0)) == lane and origin.distance_to(WarData.point(other)) < 16)
	var id := int(e.id)
	if jobs.has(id) and (jobs[id].origin.distance_to(origin) > .05 or jobs[id].goal.distance_to(goal) > .5 or jobs[id].lane != lane): jobs.erase(id)
	if not jobs.has(id):
		jobs[id] = {"origin":origin,"goal":goal,"lane":lane,"open":[Vector2i.ZERO],"costs":{Vector2i.ZERO:0.0},"parents":{},"closed":{},"attempts":0}
	var job: Dictionary = jobs[id]
	var open: Array = job.open
	var costs: Dictionary = job.costs
	var parents: Dictionary = job.parents
	var closed: Dictionary = job.closed
	var offsets := [Vector2i(1,0),Vector2i(1,1),Vector2i(0,1),Vector2i(-1,1),Vector2i(-1,0),Vector2i(-1,-1),Vector2i(0,-1),Vector2i(1,-1)]
	var began := Time.get_ticks_usec()
	while int(job.attempts) < 480 and not open.is_empty():
		if Time.get_ticks_usec()-began >= remaining_usec:
			remaining_usec = 0
			return [] # Continue the same bounded search on the next simulation tick.
		job.attempts += 1
		var best := 0
		var score := INF
		for i in open.size():
			var value: float = costs[open[i]]+(origin+Vector2(open[i])*.4).distance_to(goal)
			if value < score: score = value; best = i
		var cell: Vector2i = open.pop_at(best)
		var at := origin+Vector2(cell)*.4
		if cell != Vector2i.ZERO and at.distance_to(goal) < .4 and _clear(game,e,at,goal,lane,neighbors):
			var result: Array = [{"p":goal,"lane":lane}]
			while cell != Vector2i.ZERO:
				result.push_front({"p":origin+Vector2(cell)*.4,"lane":lane})
				cell = parents[cell]
			remaining_usec -= Time.get_ticks_usec()-began
			jobs.erase(id)
			return result
		closed[cell] = true
		for offset in offsets:
			var next: Vector2i = cell+offset
			if closed.has(next) or absi(next.x) > 30 or absi(next.y) > 30: continue
			var end := origin+Vector2(next)*.4
			var cost: float = costs[cell]+at.distance_to(end)
			if cost >= float(costs.get(next,INF)): continue
			if not _clear(game,e,at,end,lane,neighbors): continue
			costs[next] = cost; parents[next] = cell
			if not open.has(next): open.append(next)
	remaining_usec -= Time.get_ticks_usec()-began
	jobs.erase(id)
	return []

static func _clear(game: WarSimulation,e: Dictionary,a: Vector2,b: Vector2,lane: int,neighbors: Array) -> bool:
	# Broad-phase first, then exact hulls. Never manufacture a new lane transition.
	for other in neighbors:
		var radius := WarData.radius(e.kind)+WarData.radius(other.kind)+.04
		if Geometry2D.get_closest_point_to_segment(WarData.point(other),a,b).distance_squared_to(WarData.point(other)) > radius*radius: continue
		if not WarCellShape.sweep(e,other,a,b-a,.02).is_empty(): return false
	if lane == 0 and not game.navigation.movement_clear(a,b,e.kind,int(e.faction)): return false
	return game.navigation.clear_segment(a,b,lane,e.kind)
