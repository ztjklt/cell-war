extends SceneTree
var failures: Array[String] = []
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL: "+label)

func _initialize() -> void:
	call_deferred("run")

func measured(game: WarSimulation, lane: int, along: bool, kind := "worker") -> float:
	var data: Dictionary = WarData.read("vessels").lanes[lane-1]
	var points: Array = data.points
	# Long enough to avoid arrival easing; sample well inside an actual segment.
	var best := 1
	for i in range(1,points.size()):
		if WarData.point(points[i-1]).distance_to(WarData.point(points[i])) > WarData.point(points[best-1]).distance_to(WarData.point(points[best])): best = i
	var a := WarData.point(points[best-1])
	var b := WarData.point(points[best])
	var p := a.lerp(b,.5)
	var direction := game.navigation.blood_flow.direction(lane,p)
	if direction == Vector2.ZERO: direction = (b-a).normalized()
	if not along: direction = -direction
	var target := p+direction*10
	var spec := WarData.spec(kind)
	var base := float(spec.speed)
	var e := {"id":9000,"kind":kind,"faction":1,"category":"unit","hp":100.0,
		"x":p.x,"y":p.y,"vesselLane":lane,"orders":[],"statuses":{},
		"pathGoal":target,"path":[{"p":target,"lane":lane}],"pathIndex":0,
		"pathPending":false,"pathFailed":false,"lastTravel":game.state.time,"movementSpeed":base}
	game.state.entities = {"9000":e}
	game.go(e,target,.1)
	return p.distance_to(WarData.point(e))/(base*.1)

func run() -> void:
	var game := WarSimulation.new()
	game.start("fullbody")
	var flow := game.navigation.blood_flow
	var report: Array = []
	for data in WarData.read("vessels").lanes:
		var lane := int(data.lane)
		if data.system not in ["artery","vein"]: continue
		var entry: Dictionary = flow.lanes[lane]
		var points: PackedVector2Array = entry.points
		var middle := maxi(1,points.size()/2)
		var p := (points[middle-1]+points[middle])*.5
		var direction := flow.direction(lane,p)
		check(direction.length() > .99,"nonzero flow lane %d" % lane)
		check(is_equal_approx(flow.multiplier(lane,p,direction),3.0),"downstream lane %d" % lane)
		check(is_equal_approx(flow.multiplier(lane,p,-direction),.4),"upstream lane %d" % lane)
		report.append({"lane":lane,"name":data.name,"color":"blue" if entry.blue else "red","flow":"a_to_b" if entry.sign > 0 else "b_to_a"})
	for lane in [9,13,16,17,23,25,38,39,88,89,150,211]:
		check(flow.lanes[lane].sign > 0,"systemic direction lane %d" % lane)
	for lane in [2,3,5,6,8,172,173,174,175]:
		check(flow.lanes[lane].sign < 0,"pulmonary follows color lane %d" % lane)
	check(flow.multiplier(0,Vector2.ZERO,Vector2.RIGHT) == 1,"tissue neutral")
	check(flow.multiplier(203,Vector2.ZERO,Vector2.RIGHT) == 1,"heart chamber neutral")
	check(flow.multiplier(4,Vector2.ZERO,Vector2.RIGHT) == 1,"exchange bed neutral")
	check(flow.multiplier(9,Vector2.ZERO,Vector2.ZERO) == 1,"idle neutral")
	for kind in ["worker","spear","virus"]:
		for lane in [9,13,2,5]:
			for along in [true,false]:
				var expected := 3.0 if along else .4
				check(absf(measured(game,lane,along,kind)-expected) < .001,"actual %s lane %d downstream=%s" % [kind,lane,along])
	# A bent red tube can turn back toward the heart without reversing its current.
	var bent := WarBloodFlow.new({"lanes":[
		{"lane":1,"a":1,"b":2,"system":"valve","points":[[0,0],[1,0]],"width":1},
		{"lane":2,"a":2,"b":3,"system":"artery","points":[[1,0],[10,0],[10,10],[5,10]],"width":2}]})
	check(bent.direction(2,Vector2(7,10)).dot(Vector2.LEFT) > .99,"bend follows local tangent")
	check(bent.multiplier(2,Vector2(7,10),Vector2.LEFT) == 3,"bent downstream boost")
	check(bent.multiplier(2,Vector2(10,0),Vector2.DOWN) == 3,"exact bend enters next segment")
	# Crossed projected tubes keep independent flow directions.
	var crossing := WarBloodFlow.new({"lanes":[
		{"lane":1,"a":1,"b":2,"system":"artery","points":[[-10,0],[10,0]],"width":2},
		{"lane":2,"a":3,"b":4,"system":"vein","points":[[0,-10],[0,10]],"width":2}]})
	check(crossing.direction(1,Vector2.ZERO).dot(Vector2.RIGHT) > .99,"crossing keeps red lane")
	check(crossing.direction(2,Vector2.ZERO).dot(Vector2.DOWN) > .99,"crossing keeps blue lane")
	# One simulation tick spends the remaining time using the new lane's speed.
	var saved_flow := game.navigation.blood_flow
	game.navigation.blood_flow = WarBloodFlow.new({"lanes":[
		{"lane":1,"a":1,"b":2,"system":"artery","points":[[0,0],[.3,0]],"width":2},
		{"lane":2,"a":3,"b":4,"system":"vein","points":[[10,0],[.3,0]],"width":2}]})
	var base := float(WarData.spec("worker").speed)
	var mixed := {"id":9000,"kind":"worker","faction":1,"category":"unit","hp":100.0,
		"x":0.0,"y":0.0,"vesselLane":1,"orders":[],"statuses":{},
		"pathGoal":Vector2(10,0),"path":[{"p":Vector2(.3,0),"lane":2},{"p":Vector2(10,0),"lane":2}],
		"pathIndex":0,"pathPending":false,"pathFailed":false,"lastTravel":game.state.time,"movementSpeed":base}
	game.state.entities = {"9000":mixed}
	game.go(mixed,Vector2(10,0),1)
	check(absf(float(mixed.x)-(.3+(base-.3/3)*.4)) < .0001,"lane change spends correct remaining time")
	# Switching to tissue in the same tick removes the vessel boost immediately.
	mixed.x = 0.0; mixed.vesselLane = 1; mixed.pathIndex = 0; mixed.movementSpeed = base
	mixed.path[0].lane = 0; mixed.path[1].lane = 0
	game.go(mixed,Vector2(10,0),1)
	check(absf(float(mixed.x)-(.3+base-.3/3)) < .0001,"blood exit restores tissue speed")
	game.navigation.blood_flow = saved_flow
	DirAccess.make_dir_recursive_absolute("res://test-output")
	var file := FileAccess.open("res://test-output/blood-flow.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"directions":report},"  "))
	game.dispose()
	print("Blood flow: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
