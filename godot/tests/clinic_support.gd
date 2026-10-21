extends SceneTree
## Damage is measured through the live combat entry, including an in-flight
## projectile whose shooter has already left the entity table.
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,label: String) -> void:
	checks += 1
	if not value: failures.append(label); printerr("FAIL ",label)

func dealt(game: WarSimulation,source: Dictionary,target: Dictionary,raw := false) -> float:
	target.hp = 100.0
	game.combat.damage(source,target,10.0,raw,"test")
	return 100.0-float(target.hp)

func run() -> void:
	var game := WarSimulation.new()
	game.start("cell_test")
	game.state.entities.clear(); game.navigation.blockers.clear()
	var clinic := game.spawn("clinic",1,Vector2(100,100),"building")
	var source := game.spawn("spear",1,Vector2(104,100))
	var target := game.spawn("virus",2,Vector2(108,100))
	check(is_equal_approx(dealt(game,source,target),12.5),"completed nearby clinic applies the existing twenty-five percent bonus")
	check(is_equal_approx(dealt(game,source,target,true),10),"raw damage retains its bypass contract")
	clinic.complete = false
	check(is_equal_approx(dealt(game,source,target),10),"unfinished clinic provides no support")
	clinic.complete = true; clinic.hp = 0
	check(is_equal_approx(dealt(game,source,target),10),"destroyed clinic provides no support")
	clinic.hp = clinic.maxHp; clinic.faction = 2
	check(is_equal_approx(dealt(game,source,target),10),"enemy clinic cannot buff the attacker")
	clinic.faction = 1
	var second := game.spawn("clinic",1,Vector2(100,102),"building")
	check(is_equal_approx(dealt(game,source,target),12.5),"overlapping clinics do not multiply the bonus twice")
	second.hp = 0
	source.x = 107.0
	check(is_equal_approx(dealt(game,source,target),12.5),"the original seven-unit radius includes its edge")
	source.x = 107.01
	check(is_equal_approx(dealt(game,source,target),10),"support stops immediately outside the existing radius")
	source.x = 104.0; source.vesselLane = 145
	check(is_equal_approx(dealt(game,source,target),10),"a projected blood lane cannot receive a tissue clinic bonus")
	source.vesselLane = 0
	# An isolated ground-map fixture supplies an actual blocked terrain sample;
	# it does not change the authored organ geometry or any gameplay route.
	var grid := game.navigation.campaign_grid
	var at := Vector2i((Vector2(102,100)-grid.origin).round())
	var index := at.y*grid.width+at.x
	var original := grid.valid[index]
	grid.valid[index] = 0
	check(game.navigation.point_allowed(WarData.point(clinic),0,"spear") and game.navigation.point_allowed(WarData.point(source),0,"spear") and not game.navigation.clear_segment(WarData.point(clinic),WarData.point(source),0,"spear"),"terrain fixture has valid endpoints separated by a real blocked segment")
	check(is_equal_approx(dealt(game,source,target),10),"nearby support cannot cross an impassable terrain gap")
	grid.valid[index] = original
	var saved := game.snapshot()
	check(WarSave.validate(saved).is_empty(),"clinic support needs no new persistent save fields")
	game.restore(saved)
	source = game.entity(int(source.id)); target = game.entity(int(target.id))
	check(is_equal_approx(dealt(game,source,target),12.5),"restored living clinic retains normal support")
	# The shooter dies after launch. The surviving projectile must retain its
	# source plane when damage is resolved, rather than defaulting to tissue.
	source.vesselLane = 145; target.vesselLane = 145; target.hp = 100.0; target.x = 106.0
	game.combat.launch(source,target,10,{"speed":14,"ttl":1,"style":"granule"})
	check(game.state.combatProjectiles.size()==1,"real projectile was emitted before removing its shooter")
	game.state.entities.erase(str(source.id))
	game.combat.update_projectiles(.4)
	check(game.state.combatProjectiles.is_empty() and is_equal_approx(float(target.hp),90),"orphaned projectile preserves its original lane and receives no cross-layer clinic bonus")
	game.dispose()
	DirAccess.make_dir_recursive_absolute("res://test-output/bug-audit-20261021")
	var file := FileAccess.open("res://test-output/bug-audit-20261021/clinic-support.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"Actual combat damage and projectile collision; isolated ground-map terrain fixture, not full-map navigation acceptance."},"  "))
	print("CLINIC SUPPORT ",checks-failures.size(),"/",checks)
	quit(0 if failures.is_empty() else 1)
