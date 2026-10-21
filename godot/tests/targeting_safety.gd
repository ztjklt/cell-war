extends SceneTree
## Stale target locks and same-step death must obey existing combat identities.
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,label: String) -> void:
	checks += 1
	if not value: failures.append(label); printerr("FAIL ",label)

func fixture() -> WarSimulation:
	var game := WarSimulation.new(); game.start("cell_test",73)
	game.state.entities.clear(); game.navigation.blockers.clear()
	return game

func run() -> void:
	var game := fixture()
	var white := game.spawn("spear",1,Vector2(101,103))
	var hidden := game.spawn("herpes",2,Vector2(104,103)); hidden.burrowed = true
	check(not game.visible(hidden,1),"fixture concealed enemy is not visible to a normal white cell")
	check(not game.combat.fight(white,hidden,.1,true) and not white.has("cellShot") and not white.pathPending,"old explicit target ID cannot start an attack or chase after concealment")
	game.dispose()
	game = fixture()
	white = game.spawn("spear",1,Vector2(101,103))
	hidden = game.spawn("herpes",2,Vector2(104,103)); hidden.burrowed = true
	var scout := game.spawn("dendritic_cell",1,Vector2(100,103))
	game.order(scout,{"kind":"hold"}); game.dendritic.refresh()
	check(game.visible(hidden,1),"real stationary dendritic scan reveals the concealed enemy")
	check(game.combat.fight(white,hidden,.1,false) and white.has("cellShot"),"revealed target supports the ordinary delayed shot")
	game.order(scout,{"kind":"move","x":100.0,"y":106.0,"lane":0})
	check(not game.visible(hidden,1),"real move order immediately removes the scan mark")
	game.state.time = .4
	game.combat.update_projectiles(0)
	check(game.state.combatProjectiles.is_empty() and not white.has("cellShot"),"release rechecks visibility and consumes a now-invalid delayed shot without firing")
	game.dispose()
	game = fixture()
	white = game.spawn("spear",1,Vector2(101,103))
	hidden = game.spawn("herpes",2,Vector2(104,103))
	check(game.combat.fight(white,hidden,.1,false),"visible enemy starts a valid delayed shot")
	game.state.time = .4; game.combat.update_projectiles(0)
	check(game.state.combatProjectiles.size() == 1,"valid delayed shot creates one real airborne projectile")
	hidden.burrowed = true
	var hp: float = hidden.hp
	game.combat.update_projectiles(.4)
	check(hidden.hp < hp and game.state.combatProjectiles.is_empty(),"concealment does not grant immunity to a projectile already in flight")
	game.dispose()
	game = fixture()
	var source := game.spawn("herpes",2,Vector2(101,103))
	var victim := game.spawn("worker",1,Vector2(101.2,103))
	game.combat.damage(victim,source,source.hp,true,"test")
	hp = victim.hp
	check(source.hp == 0 and not game.entity(int(source.id)).is_empty(),"fixture reaches the real interval between lethal damage and end-of-step removal")
	game.combat.contacts(.1)
	check(victim.hp == hp and game.combat._knockbacks.is_empty(),"dead contact attacker cannot deal posthumous damage or queue a push")
	game.dispose()
	game = fixture()
	source = game.spawn("herpes",2,Vector2(101,103))
	victim = game.spawn("worker",1,Vector2(101.2,103))
	game.combat.damage(source,victim,victim.hp,true,"test")
	game.combat.contacts(.1)
	check(not source.has("nextContactHit") and source.get("contactHits",{}).is_empty(),"dead contact target cannot consume a living attacker's next contact cooldown")
	game.dispose()
	game = fixture()
	source = game.spawn("herpes",2,Vector2(101,103))
	victim = game.spawn("herpes",3,Vector2(101.2,103))
	game.combat.damage({},source,source.hp-2,true,"test")
	game.combat.damage({},victim,victim.hp-2,true,"test")
	game.combat.contacts(.1)
	check(victim.hp == 0,"first live contact attacker lethally hits the next actor during iteration")
	check(source.hp == 2 and not victim.has("nextContactHit"),"actor killed earlier in the same contact iteration cannot retaliate from the stale actor list")
	game.dispose()
	DirAccess.make_dir_recursive_absolute("res://test-output/targeting-safety")
	FileAccess.open("res://test-output/targeting-safety/checks.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"fixture":"isolated authored cell_test terrain; spawned combat actors and explicit burrow flag; real scan orders, delayed projectile loop and lethal damage API; not automatic herpes-ambush acceptance"},"  "))
	print("TARGETING SAFETY ",checks-failures.size(),"/",checks)
	quit(0 if failures.is_empty() else 1)
