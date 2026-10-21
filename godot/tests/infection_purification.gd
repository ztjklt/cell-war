extends SceneTree
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("FAIL ",message)

func fixture(game: WarSimulation,organ := "lung_r",index := 0) -> Dictionary:
	game.start("fullbody",73)
	game.state.influenzaColonies = {"version":1,"groups":{}}
	var group := game.influenza.start_outbreak(organ,index,10)
	group.pending = 0
	return group

func defender(game: WarSimulation,group: Dictionary,kind: String,offset := Vector2.ZERO,faction := 1) -> Dictionary:
	var e := game.spawn(kind,faction,WarData.point(group.center)+offset)
	check(not e.is_empty(),"certified position supports "+kind)
	if e.is_empty(): return e
	e.vesselLane = 0
	game.order(e,{"kind":"hold"})
	return e

func tick(game: WarSimulation,seconds: float) -> void:
	for i in roundi(seconds/WarSimulation.STEP): game.step(WarSimulation.STEP)

func run() -> void:
	WarSave.directory = "user://test-saves/purification"
	var game := WarSimulation.new()
	var group := fixture(game)
	game.influenza.after_step(1)
	check(not group.cleared and group.purification.elapsed == 0,"no passive clearance when all viruses are gone")
	var red := defender(game,group,"worker",Vector2(-2,0))
	game.influenza.after_step(1)
	check(group.purification.status == "waiting_white" and group.purification.elapsed == 0,"red alone cannot purify")
	red.hp = 0
	var white := defender(game,group,"spear",Vector2(2,0))
	game.influenza.after_step(1)
	check(group.purification.status == "waiting_red" and group.purification.elapsed == 0,"white alone cannot purify")
	red.hp = red.maxHp
	game.influenza.after_step(5)
	check(group.purification.status == "purifying" and is_equal_approx(group.purification.elapsed,5),"red and white jointly advance")
	white.vesselLane = 1
	game.influenza.after_step(.1)
	check(group.purification.status == "waiting_white" and group.purification.elapsed == 0,"projected blood-lane white cannot occupy tissue")
	white.vesselLane = 0
	game.influenza.after_step(5)
	var hostile := defender(game,group,"virus",Vector2(0,3),2)
	game.influenza.after_step(.1)
	check(group.purification.status == "contested" and group.purification.elapsed == 0,"hostile entry interrupts and resets hold")
	hostile.vesselLane = 1
	game.influenza.after_step(.1)
	check(group.purification.status == "purifying","enemy projected on another vascular plane does not contest tissue")
	hostile.vesselLane = 0; hostile.faction = 3
	game.influenza.after_step(.1)
	check(group.purification.status == "contested" and group.purification.elapsed == 0,"any hostile faction can interrupt")
	hostile.hp = 0
	game.influenza.after_step(5)
	white.x += 20
	game.influenza.after_step(.1)
	check(group.purification.status == "waiting_white" and group.purification.elapsed == 0,"leaving the small patch resets hold")
	white.x -= 20
	group.pending = 1
	game.influenza.after_step(5)
	check(group.purification.status == "pending_births" and group.purification.elapsed == 0,"pending births block purification")
	group.pending = 0
	var fort := game.spawn("flu_fortress",2,WarData.point(group.center),"building")
	fort.fluColony = group.id
	game.influenza.after_step(5)
	check(group.purification.status in ["contested","fortified"] and group.purification.elapsed == 0,"living fortress blocks purification")
	fort.x += 20
	game.influenza.after_step(5)
	check(group.purification.status == "fortified","expanded fortress outside source footprint must also be destroyed")
	fort.hp = 0
	game.state.entities.erase(str(fort.id))
	game.influenza.after_step(5)
	var progress := float(group.purification.elapsed)
	game.paused = true
	for i in 10: game.update(.25)
	check(group.purification.elapsed == progress,"pause freezes occupation")
	game.paused = false
	white.hp = 0
	game.influenza.after_step(.1)
	check(group.purification.elapsed == 0,"dead white cannot maintain occupation")
	white.hp = white.maxHp
	# The real fixed-step path, rather than only calling the mechanism directly.
	tick(game,9.9)
	check(not group.cleared and is_equal_approx(group.purification.elapsed,9.9),"real simulation advances fractional continuous hold")
	check(WarSave.validate(game.snapshot()).is_empty(),"mid-purification snapshot validates")
	check(WarSave.write(game,1) == OK,"mid-purification save writes through native save service")
	var resumed := WarSimulation.new()
	check(WarSave.read_slot(resumed,1) == OK,"mid-purification native load succeeds")
	var loaded: Dictionary = resumed.state.influenzaColonies.groups[group.id]
	var completions := [0]
	resumed.combat_event.connect(func(event):
		if event.kind == "infection_purified": completions[0] += 1)
	check(is_equal_approx(loaded.purification.elapsed,9.9),"load preserves hold progress")
	tick(resumed,10)
	check(not loaded.cleared,"no early completion after load")
	tick(resumed,.1)
	check(loaded.cleared and loaded.purification.status == "purified" and loaded.pending == 0,"full twenty seconds completes once and empties queue")
	check(is_equal_approx(WarInfectionPurification.ground_opacity(loaded),1),"fade starts at full ground opacity")
	var batches := int(loaded.batches); var produced := int(loaded.produced)
	resumed.influenza.before_step(60)
	resumed.influenza.after_step(1.5)
	check(loaded.batches == batches and loaded.produced == produced and resumed.influenza.members(loaded).is_empty(),"purified source does not spawn or construct")
	check(is_equal_approx(WarInfectionPurification.ground_opacity(loaded),.5),"ground fades halfway after 1.5 simulated seconds")
	check(completions[0] == 1,"completed purification event fires once")
	check(WarSave.write(resumed,2) == OK,"half-faded purified save succeeds")
	var faded := WarSimulation.new()
	check(WarSave.read_slot(faded,2) == OK,"half-faded native load succeeds")
	var fading: Dictionary = faded.state.influenzaColonies.groups[group.id]
	check(is_equal_approx(WarInfectionPurification.ground_opacity(fading),.5),"fade is restored rather than restarted")
	faded.paused = true
	faded.update(.25)
	check(is_equal_approx(WarInfectionPurification.ground_opacity(fading),.5),"pause freezes the fade")
	faded.influenza.after_step(1.5)
	check(WarInfectionPurification.ground_opacity(fading) == 0 and WarInfectionZones.live_patches(faded).is_empty(),"purified ground disappears after three simulated seconds")
	check(faded.influenza._spawn_virus(fading,WarData.point(fading.center)).is_empty(),"even direct stale birth helper rejects a purified source")
	# Legacy saved groups remain loadable; already-cleared groups do not reinfect.
	var old := resumed.snapshot()
	old.influenzaColonies.groups[group.id].erase("purification")
	check(WarSave.validate(old).is_empty(),"legacy colony save accepted without new timer fields")
	faded.restore(old)
	faded.influenza.after_step(.1)
	check(faded.state.influenzaColonies.groups[group.id].cleared and WarInfectionZones.live_patches(faded).is_empty(),"legacy cleared save remains clear")
	# A new explicit exposure is a new batch, and resets only this patch.
	var again := faded.influenza.start_outbreak("lung_r",0,10)
	check(not again.cleared and again.purification.elapsed == 0 and again.pending == 10 and again.batches == batches+1,"explicit new outbreak resets prior purification")
	var second := faded.influenza.start_outbreak("lung_l",0,10)
	check(WarInfectionZones.live_patches(faded).size() == 2,"two independent active infection surfaces")
	check(WarInfectionPurification.footprint(again) != WarInfectionPurification.footprint(second),"different organs retain independent certified footprints")
	# Corrupt timers/placement state is rejected before replacing the live game.
	var broken := resumed.snapshot()
	broken.influenzaColonies.groups[group.id].purification.elapsed = -1
	check(not WarSave.validate(broken).is_empty(),"negative hold progress rejected")
	broken = resumed.snapshot(); broken.influenzaColonies.groups[group.id].purification.fadeElapsed = INF
	check(not WarSave.validate(broken).is_empty(),"non-finite fade rejected")
	broken = resumed.snapshot(); broken.influenzaColonies.groups[group.id].purification.status = "purifying"
	check(not WarSave.validate(broken).is_empty(),"inconsistent cleared state rejected")
	broken = resumed.snapshot(); broken.influenzaColonies.groups[group.id].purification.red = 1.5
	check(not WarSave.validate(broken).is_empty(),"fractional participant count rejected")
	broken = resumed.snapshot(); broken.influenzaColonies.groups[group.id].center[0] += 2
	check(not WarSave.validate(broken).is_empty(),"modified certified source position rejected")
	# The life director consumes the existing cleared contract; no life module edits.
	var life_game := WarSimulation.new()
	life_game.start("life",73)
	var life_group := life_game.influenza.start_outbreak("lung_r",0,10)
	life_group.pending = 0
	defender(life_game,life_group,"worker",Vector2(-2,0))
	defender(life_game,life_group,"neutrophil",Vector2(2,0))
	life_game.life._refresh_load()
	check(int(life_game.life.state().recovered) == 0,"destroying threat without occupation does not award life recovery")
	tick(life_game,20)
	life_game.life._refresh_load()
	check(life_group.cleared and int(life_game.life.state().recovered) == 1 and life_game.life.eligible(WarLifeRun.definition("after_infection")),"joint purification unlocks existing recovery conversation")
	life_game.life._refresh_load()
	check(int(life_game.life.state().recovered) == 1,"life recovery is not counted repeatedly")
	check(WarSave.validate(life_game.snapshot()).is_empty(),"life save includes valid purification state")
	life_game.dispose()
	# Clearing the local source must not erase remote enemies or let them rebuild it.
	var leftovers := WarSimulation.new()
	var source_group := fixture(leftovers)
	defender(leftovers,source_group,"worker",Vector2(-2,0))
	defender(leftovers,source_group,"spear",Vector2(2,0))
	var remote := WarData.point(leftovers.influenza.zone("lung_r").placements[1].center)
	for i in 10:
		var survivor := leftovers.spawn("virus",2,remote+Vector2((i%5-2)*1.8,(i/5)*2.0))
		check(not survivor.is_empty(),"remote surviving virus has certified tissue position")
		if survivor.is_empty(): continue
		survivor.vesselLane = 0; survivor.fluColony = source_group.id
	leftovers.influenza.after_step(WarInfectionPurification.HOLD_SECONDS)
	check(source_group.cleared and leftovers.influenza.members(source_group).size() == 10,"local purification keeps already-escaped viruses alive")
	leftovers.influenza.before_step(60); leftovers.influenza.after_step(60)
	leftovers.influenza._start_site(source_group,leftovers.influenza.members(source_group))
	check(leftovers.influenza.forts(source_group).is_empty() and source_group.produced == 0,"escaped members cannot rebuild or resume births from purified source")
	leftovers.dispose()
	# Legacy modes do not start, occupy, or render this fullbody-only mechanism.
	for mode in ["systemic","lung_skirmish","cell_test","sandbox","trachea_01"]:
		var isolated := WarSimulation.new()
		isolated.start(mode,73)
		isolated.influenza.before_step(1); isolated.influenza.after_step(1)
		check(not isolated.state.has("influenzaColonies") and WarInfectionZones.live_patches(isolated).is_empty(),"legacy mode remains independent: "+mode)
		isolated.dispose()
	# All existing authored organs retain the same deterministic source footprint.
	for zone in WarData.read("infection_zones").zones:
		var sample := {"id":zone.placements[0].id,"organ":zone.organ,"cleared":false}
		check(WarInfectionPurification.footprint(sample).has_point(WarData.point(zone.placements[0].center)),"certified capture footprint: "+zone.organ)
	DirAccess.remove_absolute(WarSave.path(1)); DirAccess.remove_absolute(WarSave.path(2))
	game.dispose(); resumed.dispose(); faded.dispose()
	DirAccess.make_dir_recursive_absolute("res://test-output/purification")
	var file := FileAccess.open("res://test-output/purification/checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"holdSeconds":WarInfectionPurification.HOLD_SECONDS,"redRequired":WarInfectionPurification.RED_REQUIRED,"whiteRequired":WarInfectionPurification.WHITE_REQUIRED,"fadeSeconds":WarInfectionPurification.FADE_SECONDS},"  "))
	print("INFECTION PURIFICATION ",checks-failures.size(),"/",checks)
	quit(0 if failures.is_empty() else 1)
