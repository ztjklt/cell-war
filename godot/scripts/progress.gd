class_name WarProgress
extends RefCounted
## Simulation.lua's one-second sandbox outcome and six-step tutorial rules.
static func advance(state: Dictionary) -> void:
	for i in state.factions.size():
		var units := 0
		var production := 0
		var workers := 0
		var cores := 0
		for e in state.entities.values():
			if e.hp <= 0 or int(e.faction) != i+1: continue
			if e.category == "unit":
				units += 1
				if e.kind == "worker": workers += 1
			elif e.get("complete",false):
				if e.kind in ["core","barracks","range","workshop"]: production += 1
				if e.kind == "core": cores += 1
		state.factions[i].lost = units == 0 and production == 0
		state.factions[i].conquered = cores == 0 and workers == 0 and production == 0
	if state.factions[0].lost: state.outcome = "defeat"
	elif state.get("outcome","playing") == "playing" and state.factions[1].conquered and state.factions[2].conquered: state.outcome = "victory"
	if state.get("tutorial",1) == 1 and state.get("selectedOnce",false): state.tutorial = 2
	if state.get("tutorial",1) == 2 and state.get("delivered",0) > 0: state.tutorial = 3
	var lights := 0
	for e in state.entities.values():
		if e.hp > 0 and e.faction == 1 and e.kind == "fire": lights += 1
	if state.get("tutorial",1) == 3 and lights > 1: state.tutorial = 4
	if state.get("tutorial",1) == 4 and state.get("farmed",0) > 0: state.tutorial = 5
	if state.get("tutorial",1) == 5 and state.get("trained",0) > 0: state.tutorial = 6
