extends SceneTree
## Frozen copy of the pre-optimization selection order for differential checks.
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func reference(game: WarSimulation,e: Dictionary,reach: float,buildings := false) -> Dictionary:
	var best: Dictionary = {}
	var distance := reach*reach
	for other in game.entities():
		if other.hp <= 0 or other.faction == e.faction or (other.category != "unit" and not buildings): continue
		if e.faction > 0 and not game.visible(other,e.faction): continue
		var d := WarData.point(e).distance_squared_to(WarData.point(other))
		if d < distance or (is_equal_approx(d,distance) and (best.is_empty() or other.id < best.id)):
			best = other; distance = d
	return best

func check(game: WarSimulation,e: Dictionary,reach: float,buildings: bool,label: String) -> void:
	checks += 1
	var old := reference(game,e,reach,buildings)
	var now := game.combat.enemy(e,reach,buildings)
	if old.get("id",0) != now.get("id",0): failures.append(label+": old "+str(old.get("id",0))+" new "+str(now.get("id",0))); printerr("FAIL ",failures[-1])

func expected(game: WarSimulation,e: Dictionary,reach: float,buildings: bool,id: int,label: String) -> void:
	check(game,e,reach,buildings,label)
	checks += 1
	if int(game.combat.enemy(e,reach,buildings).get("id",0)) != id: failures.append(label+": wrong expected target"); printerr("FAIL ",failures[-1])

func move_to(e: Dictionary,p: Vector2) -> void: e.x = p.x; e.y = p.y

func run() -> void:
	var game := WarSimulation.new(); game.start("cell_test")
	game.state.entities.clear()
	var source := game.spawn("spear",1,Vector2(100,100))
	var near := game.spawn("virus",2,Vector2(101,100))
	var far := game.spawn("virus",2,Vector2(103,100))
	expected(game,source,5,false,int(near.id),"nearest living enemy")
	near.hp = 0; expected(game,source,5,false,int(far.id),"dead near skipped"); near.hp = near.maxHp
	near.faction = 1; expected(game,source,5,false,int(far.id),"ally skipped"); near.faction = 2
	move_to(near,Vector2(104,100)); move_to(far,Vector2(101,100)); expected(game,source,5,false,int(far.id),"new nearest after movement")
	move_to(near,Vector2(101,100)); move_to(far,Vector2(101,100)); expected(game,source,5,false,int(near.id),"same distance lower ID")
	move_to(near,Vector2(101.00000001,100)); check(game,source,5,false,"approximate equal distance")
	move_to(near,Vector2(105,100)); move_to(far,Vector2(106,100)); expected(game,source,5,false,int(near.id),"reach edge exact and beyond")
	move_to(near,Vector2(105.0000001,100)); check(game,source,5,false,"reach edge approximate")
	var building := game.spawn("store",2,Vector2(102,100),"building")
	expected(game,source,5,false,int(near.id),"building excluded"); expected(game,source,5,true,int(building.id),"building included")
	move_to(near,Vector2(101,100)); move_to(far,Vector2(104,100)); near.concealed = true
	expected(game,source,5,true,int(building.id),"concealed closer is skipped")
	near.erase("concealed")
	move_to(source,Vector2(300,300)); expected(game,source,5,true,0,"far targets skipped")
	move_to(source,Vector2(100,100)); source.faction = 0; check(game,source,5,true,"neutral source bypasses vision check")
	source.faction = 1; near.faction = 0; check(game,source,5,true,"neutral target candidate")
	near.faction = 2; building.hp = 0; check(game,source,5,true,"dead building excluded")
	# Deterministic authored positions including equal-distance and occlusion permutations.
	for i in 120:
		move_to(near,Vector2(100+float((i*37)%131)/20.0,100+float((i*17)%71)/30.0))
		move_to(far,Vector2(100+float((i*19)%127)/20.0,100-float((i*11)%67)/30.0))
		near.concealed = i%7 == 0; far.hp = 0 if i%11 == 0 else far.maxHp
		check(game,source,3.0+float(i%9)*.7,i%2==0,"permutation "+str(i))
	game.dispose()
	print("COMBAT ENEMY EQUIVALENCE ",checks-failures.size(),"/",checks)
	quit(0 if failures.is_empty() else 1)
