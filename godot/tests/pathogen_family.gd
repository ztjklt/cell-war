extends SceneTree
## Registered pathogen families must drive actual helper targeting and impacts.
var checks := 0
var failures: Array[String] = []
const VIRAL := "viral_family_probe"
const BACTERIAL := "bacterial_family_probe"
const PREVIEW := "unregistered_virus_preview"

func _initialize() -> void: call_deferred("run")

func check(value: bool,label: String) -> void:
	checks += 1
	if not value: failures.append(label); printerr("FAIL ",label)

func run() -> void:
	var config := WarData.config()
	check(["virus","herpes"].all(func(kind): return WarData.is_virus(kind) and not WarData.is_bacterium(kind)),"migrated virus identities keep their target family")
	check(["wolf","helicobacter"].all(func(kind): return WarData.is_bacterium(kind) and not WarData.is_virus(kind)),"migrated bacterial identities remain separate from viruses")
	check(WarData.is_pathogen("shadow") and WarData.pathogen_family("shadow").is_empty(),"stress spore keeps its pathogen gate rules without inventing a medicine family")
	check(["worker","spear","b_cell",WarMedicineHelpers.KIND,PREVIEW].all(func(kind): return WarData.pathogen_family(kind).is_empty()),"friendlies and previews have no inferred pathogen family")
	for pair in [[VIRAL,"virus"],[BACTERIAL,"bacterium"]]:
		check(not config.Data.units.has(pair[0]),"probe is not a released runtime identity: "+pair[0])
		config.Data.units[pair[0]] = WarData.spec("virus").duplicate(true)
		config.Data.units[pair[0]].pathogen = true
		config.Data.units[pair[0]].pathogenFamily = pair[1]
		config.Data.cellRadii[pair[0]] = WarData.radius("virus")
	check(WarData.is_virus(VIRAL) and WarData.is_bacterium(BACTERIAL),"explicit registered candidate families are recognized")
	config.Data.units[VIRAL].pathogen = false
	check(not WarData.is_virus(VIRAL),"a family label alone does not promote an identity to pathogen")
	config.Data.units[VIRAL].pathogen = true
	var game := WarSimulation.new(); game.start("cell_test",73)
	game.state.entities.clear(); game.navigation.blockers.clear()
	var helper := game.spawn(WarMedicineHelpers.KIND,1,Vector2(101,103))
	var target := game.spawn(VIRAL,2,Vector2(104,103))
	check(not helper.is_empty() and not target.is_empty(),"fixture uses the real spawn entry for registered medicine and pathogen")
	check(game.medicine_helpers._valid_target(helper,target,7),"real helper accepts a registered new virus without a per-species code edit")
	var bubbles := game.medicine_helpers.bubbles
	check(VIRAL in bubbles.tuning().targetKinds and BACTERIAL not in bubbles.tuning().targetKinds,"tuning reports the same registered viral targets used by actual impacts")
	check(bubbles.launch(helper,WarData.point(target),1) > 0,"real bound bubble is emitted toward the registered pathogen")
	var hp: float = target.hp
	bubbles.advance_simulation(.3,game.entities())
	check(is_equal_approx(target.hp,hp-4) and is_equal_approx(bubbles.speed_multiplier(target),.7),"registered virus receives actual combat damage and the original fixed slow")
	game.state.entities.erase(str(target.id))
	target = game.spawn(BACTERIAL,2,Vector2(104,103))
	check(not game.medicine_helpers._valid_target(helper,target,7),"bacterial pathogen remains outside the viral helper's target class")
	bubbles.advance_simulation(1.3,game.entities())
	check(bubbles.launch(helper,WarData.point(target),2) > 0,"control bubble has its own real shot sequence")
	hp = target.hp; bubbles.advance_simulation(.6,game.entities())
	check(target.hp == hp and bubbles.speed_multiplier(target) == 1,"bubble passing a bacterial pathogen cannot damage or slow it")
	game.state.entities.erase(str(target.id))
	var preview := {"id":9999,"kind":PREVIEW,"hp":100.0,"category":"unit","faction":2,"vesselLane":0,"x":104.0,"y":103.0}
	check(not game.medicine_helpers._valid_target(helper,preview,7),"an unregistered preview cannot acquire mechanics from its name")
	game.dispose()
	for kind in [VIRAL,BACTERIAL]: config.Data.units.erase(kind); config.Data.cellRadii.erase(kind)
	DirAccess.make_dir_recursive_absolute("res://test-output/pathogen-family")
	FileAccess.open("res://test-output/pathogen-family/checks.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"process-local temporary registrations; real helper targeting and combat callback; does not enable new life invasions"},"  "))
	print("PATHOGEN FAMILY ",checks-failures.size(),"/",checks)
	quit(0 if failures.is_empty() else 1)
