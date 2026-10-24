extends SceneTree
## Isolated regression fixture, not a substitute for a natural playthrough.
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game := WarSimulation.new(); game.start("lung_defense",73)
	var virus := game.spawn("virus",2,Vector2(1232,1210))
	var white := game.spawn("spear",1,Vector2(1232,1215))
	game.scenarios._pathogen(virus,.1)
	var reacts: bool = virus.get("pathGoal",Vector2.INF).distance_to(WarData.point(white)) < .01
	for frame in 200:
		game.update(.1)
		if frame%20 == 0: await process_frame
	var fights := float(white.hp) < float(white.maxHp)
	if not reacts: printerr("FAIL virus notices white cell within its actual vision and closes the ranged gap")
	if not fights: printerr("FAIL virus retaliates through normal movement and combat")
	game.dispose()
	# A cell across a closed vascular checkpoint must not distract its attacker
	# into chasing an unreachable target instead of breaking the actual gate.
	game = WarSimulation.new(); game.start("lung_defense",73)
	for e in game.units(): game.state.entities.erase(str(e.id))
	var port: Dictionary = {}
	for item in WarData.read("checkpoints").ports:
		if item.id == "lung_l.capillary.7.checkpoint.1": port = item
	virus = game.spawn("virus",2,WarData.source_to_world(port.b)); virus.vesselLane = 0
	white = game.spawn("worker",1,WarData.source_to_world(port.a)); white.vesselLane = int(port.lane)
	var gate: Dictionary = game.navigation.gates[port.id]
	var before := float(gate.hp)
	for frame in 160:
		game.update(.1)
		if frame%20 == 0: await process_frame
	var breaches := float(gate.hp) < before
	if not breaches: printerr("FAIL unreachable cell across the closed checkpoint must not prevent gate attacks")
	game.dispose()
	print("LEFT_LUNG_COMBAT ",int(reacts)+int(fights)+int(breaches),"/3")
	quit(0 if reacts and fights and breaches else 1)
