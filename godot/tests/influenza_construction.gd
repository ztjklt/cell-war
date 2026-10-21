extends SceneTree
var failures: Array[String] = []
var checks := 0
var report := {"cases":[]}

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("FAIL ",message)

func frame(game: WarSimulation) -> void:
	game.navigation.update(10000)
	game.update(.1)

func site_snapshot(game: WarSimulation,site: Dictionary) -> Dictionary:
	var record := {"fortress":site.id,"point":[site.x,site.y],"progress":site.progress,"complete":site.complete,"workers":[]}
	for id in site.builders:
		var e := game.entity(int(id))
		if e.is_empty(): continue
		var slot := WarData.point(e.get("fluBuildSlot",[]))
		var blocked: Array = []
		for other in game.units():
			if other.id != e.id and WarData.point(other).distance_to(WarData.point(e)) < 2.5: blocked.append(other.id)
		record.workers.append({"id":id,"point":[e.x,e.y],"slot":[slot.x,slot.y],"distanceToSlot":WarData.point(e).distance_to(slot),"distanceToSite":WarData.point(e).distance_to(WarData.point(site)),"pathIndex":e.pathIndex,"path":e.get("path",[]),"pathPending":e.pathPending,"pathFailed":e.pathFailed,"state":e.get("combatState",""),"workedAt":e.get("fluWorkedAt",-1),"nearby":blocked})
	return record

func natural_case() -> void:
	var game := WarSimulation.new(); game.start("life",39462)
	for i in 2000:
		frame(game)
		if not game.life.state().pending.is_empty(): break
	check(game.life.state().pending.get("id","") == "crowded_party","same seed naturally offers crowded_party")
	game.life.choose(int(game.life.state().pending.token),1)
	for i in 3000:
		frame(game)
		if not game.state.influenzaColonies.groups.is_empty(): break
	check(not game.state.influenzaColonies.groups.is_empty(),"natural paid branch creates real outbreak")
	if game.state.influenzaColonies.groups.is_empty(): game.dispose(); return
	var group: Dictionary = game.state.influenzaColonies.groups.values()[0]
	check(group.id == "lung_l.patch.4","retains the reported fourth-left-lung placement")
	var began := float(game.state.time)
	var site: Dictionary = {}
	var witnessed_team: Array = []
	for i in 1220:
		frame(game)
		var buildings := game.influenza.forts(group)
		if not buildings.is_empty(): site = buildings[0]
		if not site.is_empty() and not site.complete and float(site.progress) > 0:
			witnessed_team = site_snapshot(game,site).workers
		if not site.is_empty() and site.complete: break
	check(not site.is_empty() and site.complete,"natural site four finishes with real ten-worker construction within 122 seconds")
	if not site.is_empty():
		check(WarData.point(site).distance_to(WarData.point(group.center)) < .001,"first fortress uses its own reserved infection source")
		check(witnessed_team.size() == 10 and witnessed_team.all(func(e): return e.distanceToSlot <= .18 and is_equal_approx(float(e.workedAt),float(witnessed_team[0].workedAt))),"all ten builders physically reach their own stations in the same tick")
		check(game.influenza.members(group).size() == 13,"all thirteen naturally spawned viruses survive construction")
	var record := {"id":group.id,"started":began,"elapsed":float(game.state.time)-began,"population":game.influenza.members(group).size()}
	if not site.is_empty(): record.site = site_snapshot(game,site)
	report.cases.append(record)
	DirAccess.make_dir_recursive_absolute("res://test-output/influenza-construction")
	var file := FileAccess.open("res://test-output/influenza-construction/natural-snapshot.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(game.snapshot(),"  ",true,true))
	game.dispose()

func placement_case(index: int) -> void:
	var game := WarSimulation.new(); game.start("fullbody",73)
	game.state.influenzaColonies = {"version":1,"groups":{}}
	var group := game.influenza.start_outbreak("lung_l",index,13)
	var site: Dictionary = {}
	for i in 1200:
		frame(game)
		var buildings := game.influenza.forts(group)
		if not buildings.is_empty(): site = buildings[0]
		if not site.is_empty() and site.complete: break
	check(not site.is_empty() and site.complete,"thirteen-virus real construction completes at "+group.id)
	report.cases.append({"id":group.id,"elapsed":game.state.time,"complete":not site.is_empty() and site.complete,"progress":site.get("progress",0),"point":[site.get("x",0),site.get("y",0)]})
	game.dispose()

func blocked_station_case() -> void:
	var game := WarSimulation.new(); game.start("fullbody",73)
	game.state.influenzaColonies = {"version":1,"groups":{}}
	var group := game.influenza.start_outbreak("lung_l",3,13)
	var site: Dictionary = {}
	for i in 30:
		frame(game)
		var buildings := game.influenza.forts(group)
		if not buildings.is_empty(): site = buildings[0]; break
	check(not site.is_empty(),"blocked-station fixture uses a real assigned construction site")
	if site.is_empty(): game.dispose(); return
	var farthest: Dictionary = {}
	var distance := -1.0
	for id in site.builders:
		var worker := game.entity(int(id))
		var d := WarData.point(worker).distance_to(WarData.point(worker.fluBuildSlot))
		if d > distance: distance = d; farthest = worker
	var blocker := game.spawn("store",2,WarData.point(farthest.fluBuildSlot),"building")
	check(not blocker.is_empty() and distance > .5,"explicit friendly obstruction is placed before the last worker reaches its station")
	for i in 200: frame(game)
	check(not site.complete and is_zero_approx(float(site.progress)),"nine available stations do not silently count as ten builders")
	# Remove only the explicitly injected obstruction, never alter virus/fortress hp or progress.
	game.state.entities.erase(str(blocker.id))
	for i in 600:
		frame(game)
		if site.complete: break
	check(site.complete,"real movement resumes construction after station obstruction is removed")
	report.cases.append({"id":"controlled-station-obstruction","completed":site.complete,"elapsed":game.state.time})
	game.dispose()

func reload_case() -> void:
	var directory := WarSave.directory
	WarSave.directory = "user://test-saves/influenza-construction"
	var game := WarSimulation.new(); game.start("fullbody",73)
	game.state.influenzaColonies = {"version":1,"groups":{}}
	var group := game.influenza.start_outbreak("lung_l",3,13)
	var site: Dictionary = {}
	for i in 300:
		frame(game)
		var buildings := game.influenza.forts(group)
		if not buildings.is_empty(): site = buildings[0]
		if not site.is_empty() and float(site.progress) >= .3: break
	check(not site.is_empty() and not site.complete and float(site.progress) >= .3,"real partially built site reaches reload checkpoint")
	if site.is_empty(): game.dispose(); WarSave.directory = directory; return
	var id := int(site.id); var progress := float(site.progress)
	check(WarSave.write(game,1) == OK,"construction stations and local yield state save natively")
	var loaded := WarSimulation.new()
	check(WarSave.read_slot(loaded,1) == OK,"partial construction native restore validates")
	var restored := loaded.entity(id)
	check(is_equal_approx(float(restored.progress),progress) and restored.builders.size() == 10,"restore retains partial work and ten builder assignments")
	for i in 600:
		frame(loaded)
		if restored.complete: break
	check(restored.complete,"restored builders physically finish without progress reset or instant completion")
	game.dispose(); loaded.dispose()
	DirAccess.remove_absolute(WarSave.path(1)); WarSave.directory = directory

func run() -> void:
	natural_case()
	if not OS.get_cmdline_user_args().has("--natural-only"):
		for i in 8: placement_case(i)
		blocked_station_case()
		reload_case()
	report.checks = checks; report.failures = failures
	DirAccess.make_dir_recursive_absolute("res://test-output/influenza-construction")
	var file := FileAccess.open("res://test-output/influenza-construction/checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ",true,true))
	print("INFLUENZA CONSTRUCTION ",checks-failures.size(),"/",checks)
	quit(0 if failures.is_empty() else 1)
