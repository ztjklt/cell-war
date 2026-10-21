extends SceneTree
var results: Array = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var nav := WarNavigation.new()
	var receipt: Dictionary = {}
	nav.path_ready.connect(func(_token,path,reason): receipt.path = path; receipt.reason = reason)
	var organs := nav.organs
	for pair in [["small_intestine","heart"],["lung_r","heart"],["heart","lung_r"],
		["liver","stomach"],["brain","heart"],["kidney_l","bladder"]]:
		var a := WarData.source_to_world(organs[pair[0]].rooms[0].centerSource)
		var b := WarData.source_to_world(organs[pair[1]].rooms[0].centerSource)
		# Several legacy room markers are in isolated decorative pockets in the
		# current obstacle revision. Exercise the explicit usable organ ports.
		if pair[0] in ["heart","stomach"]:
			a = WarData.source_to_world(organs[pair[0]].gateContracts.siege[-1].tissueAnchorSource)
		if pair[1] in ["heart","stomach"]:
			b = WarData.source_to_world(organs[pair[1]].gateContracts.siege[-1].tissueAnchorSource)
		receipt.clear()
		var start := Time.get_ticks_msec()
		nav.request({"x":a.x,"y":a.y,"kind":"worker","faction":1,"vesselLane":0},b,0)
		while receipt.is_empty() and Time.get_ticks_msec()-start < 30000:
			nav.update(20000)
		var row := {"from":pair[0],"to":pair[1],"pass":not receipt.get("path",[]).is_empty(),
			"reason":receipt.get("reason","timeout"),"milliseconds":Time.get_ticks_msec()-start,"waypoints":receipt.get("path",[]).size()}
		var raw_path: Array = []
		for waypoint in receipt.get("path",[]):
			raw_path.append({"x":waypoint.p.x,"y":waypoint.p.y,"lane":waypoint.lane,"organ":waypoint.get("organ","")})
		row.path = raw_path
		results.append(row)
		print(pair," pass=",row.pass," waypoints=",row.waypoints," ms=",row.milliseconds)
	DirAccess.make_dir_recursive_absolute("res://test-output")
	var file := FileAccess.open("res://test-output/routes.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"  "))
	var errors := 0
	for row in results:
		if not row.pass: errors += 1
	quit(0 if errors == 0 else 1)
