extends SceneTree
## Exercise an explicitly registered future pathogen against the existing gate
## graph and capture rules. The temporary identity is confined to this process.
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,label: String) -> void:
	checks += 1
	if not value: failures.append(label); printerr("FAIL ",label)

func run() -> void:
	var config := WarData.config()
	var probe := "gate_identity_probe"
	check(not config.Data.units.has(probe),"test identity is absent from normal runtime configuration")
	check(["virus","wolf","shadow","herpes","helicobacter"].all(func(kind): return WarData.is_pathogen(kind)),"all five migrated pathogens retain their gate identity")
	check(["worker","spear","b_cell","dendritic_cell","fever_pain_relief","unknown_preview"].all(func(kind): return not WarData.is_pathogen(kind)),"defenders, medicine helper and unknown preview remain outside the pathogen class")
	config.Data.units[probe] = WarData.spec("virus").duplicate(true)
	config.Data.units[probe].pathogen = true
	config.Data.cellRadii[probe] = WarData.radius("virus")
	var game := WarSimulation.new(); game.start("fullbody",73)
	var network := game.navigation._network(WarNavigation.profile(probe))
	var anchor: Dictionary = network.meta[network.gates.lung_r[0]]
	var gate: Dictionary = game.navigation.gates[anchor.gate]
	var contract: Dictionary = {}
	for item in game.navigation.organs.lung_r.gateContracts[WarNavigation.profile(probe)]:
		if item.id == anchor.gate: contract = item; break
	check(not contract.is_empty(),"fixture uses an existing certified right-lung gate contract")
	var tissue := WarData.source_to_world(contract.tissueAnchorSource)
	var blood := WarData.source_to_world(contract.pipeAnchorSource)
	var job := {"from":tissue,"to":blood,"lane":0,"target_lane":int(contract.laneIndex),"kind":probe,"faction":2}
	check(game.navigation._plan(job).is_empty(),"new registered pathogen cannot leave through an intact vascular gate")
	var source := game.spawn(probe,2,tissue)
	check(not source.is_empty(),"registered identity can use the real spawn entry on certified tissue")
	check(game.scenarios.unit(source,.1) and not str(source.get("spreadTargetGate","")).is_empty(),"registered pathogen receives the existing gate-approach behavior")
	game.combat.damage(source,gate,float(gate.hp)+1,true,"test")
	check(gate.get("breached",false) and int(gate.faction)==0,"registered pathogen actually breaches a defeated gate rather than recapturing it for defenders")
	check(not game.navigation._plan(job).is_empty(),"the same gate becomes usable only after its real breach state changes")
	var friendly := game.spawn("worker",1,tissue)
	game.combat.damage(friendly,gate,float(gate.hp)+1,true,"test")
	check(not gate.get("breached",false) and int(gate.faction)==1,"defender damage still recaptures the gate")
	check(game.navigation._plan(job).is_empty(),"recapture closes the registered pathogen's route again")
	job.kind = "worker"; job.faction = 1
	check(not game.navigation._plan(job).is_empty(),"normal defender keeps its original authorized transition")
	game.dispose()
	config.Data.units.erase(probe); config.Data.cellRadii.erase(probe)
	check(not WarData.spec(probe).has("pathogen"),"temporary registration is removed after the regression")
	DirAccess.make_dir_recursive_absolute("res://test-output/bug-audit-20261021")
	var file := FileAccess.open("res://test-output/bug-audit-20261021/pathogen-identity.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"Real authored gate graph and combat capture entry with a temporary registered test identity; not new-pathogen combat or life-spawn acceptance."},"  "))
	print("PATHOGEN IDENTITY ",checks-failures.size(),"/",checks)
	quit(0 if failures.is_empty() else 1)
