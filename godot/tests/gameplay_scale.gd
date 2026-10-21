extends SceneTree
## Unmodified WarSimulation.update(.1), including its ordinary 3500us navigation budget.
const Fixture := preload("res://tests/fixtures/gameplay_scale_fixture.gd")
const OUT := "res://test-output/gameplay-scale/"
const SOURCES := ["simulation","combat","navigation","economy","cell_shape","save_game","t_cell_runtime"]
var game: WarSimulation
var fixture: Dictionary
var failures: Array[String] = []
var checks := 0
var durations: Array[float] = []
var event_counts: Dictionary = {}
var last_positions: Dictionary = {}
var report := {"method":"Real fixed .1s update calls; default navigation budget; metrics exclude fixture checks, reporting and file I/O. 60s movement/harvesting then 60s combat; actual native-file restore at 60s. Natural casualties retained.","samples":[],"events":[],"badValues":[],"stalls":[],"restore":{},"peaks":{},"sourceStart":{},"sourceEnd":{}}

func _initialize() -> void: call_deferred("run")

func check(value: bool,label: String) -> void:
	checks += 1
	if not value: failures.append(label); printerr("FAIL ",label)

func hashes() -> Dictionary:
	var result := {}
	for source in SOURCES: result[source] = FileAccess.get_sha256("res://scripts/"+source+".gd")
	return result

func stats(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {}
	var sorted := values.duplicate(); sorted.sort()
	var total := 0.0
	for value in sorted: total += value
	return {"count":values.size(),"medianMs":sorted[sorted.size()/2],"p95Ms":sorted[mini(sorted.size()-1,ceili(sorted.size()*.95)-1)],"maxMs":sorted[-1],"meanMs":total/values.size()}

func write_json(name: String,value: Dictionary) -> void:
	var file := FileAccess.open(OUT+name+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(value,"  ",true,true))

func observe(event: Dictionary) -> void:
	event_counts[event.kind] = int(event_counts.get(event.kind,0))+1
	if event.kind in ["damage","death","resource_delivered"] and report.events.size() < 250: report.events.append(event.duplicate(true))

func identity() -> Dictionary:
	var result := {}
	for e in game.entities(): result[str(int(e.id))] = {"p":WarData.point(e),"lane":int(e.get("vesselLane",0)),"hp":e.hp,"orders":e.orders.duplicate(true),"cargo":e.cargo.duplicate(true)}
	return result

func same_orders(expected: Array,actual: Array) -> bool:
	if expected.size() != actual.size(): return false
	for i in expected.size():
		if not expected[i] is Dictionary or not actual[i] is Dictionary: return false
		if expected[i].size() != actual[i].size(): return false
		for key in expected[i]:
			if not actual[i].has(key): return false
			var a: Variant = expected[i][key]; var b: Variant = actual[i][key]
			if (a is int or a is float) and (b is int or b is float):
				if not is_equal_approx(float(a),float(b)): return false
			elif a != b: return false
	return true

func restore_midway() -> void:
	var before := identity()
	var time_before := float(game.state.time)
	var write_began := Time.get_ticks_usec()
	var written := WarSave.write(game,1)
	var write_ms := (Time.get_ticks_usec()-write_began)/1000.0
	check(written == OK,"midrun snapshot passes native validation and writes a real file: "+game.message)
	var size := 0
	if written == OK:
		var file := FileAccess.open(WarSave.path(1),FileAccess.READ)
		size = file.get_length()
	var read_began := Time.get_ticks_usec()
	var read := WarSave.read_slot(game,1) if written == OK else ERR_FILE_CORRUPT
	var read_ms := (Time.get_ticks_usec()-read_began)/1000.0
	check(read == OK,"midrun snapshot actually reloads from its file: "+game.message)
	var preserved := before.size() == game.entities().size() and is_equal_approx(time_before,float(game.state.time))
	var differences: Array = []
	for key in before:
		var actor := game.entity(int(key))
		if actor.is_empty(): preserved = false; differences.append({"id":key,"reason":"missing"}); continue
		var expected: Dictionary = before[key]
		var same: bool = WarData.point(actor).distance_to(expected.p) < .000001 and int(actor.vesselLane) == expected.lane and is_equal_approx(actor.hp,expected.hp) and same_orders(expected.orders,actor.orders) and actor.cargo == expected.cargo
		if not same and differences.size() < 12: differences.append({"id":key,"expected":expected,"actual":{"p":WarData.point(actor),"lane":int(actor.vesselLane),"hp":actor.hp,"orders":actor.orders,"cargo":actor.cargo}})
		preserved = preserved and same
	check(preserved,"file restore preserves every live actor position/layer/health/order/cargo and clock")
	report.restore = {"at":time_before,"writeError":written,"readError":read,"bytes":size,"writeMs":write_ms,"readMs":read_ms,"preserved":preserved,"differences":differences,"path":WarSave.path(1)}
	write_json("restored-snapshot",game.snapshot())

func sample() -> void:
	var count: Dictionary = Fixture.counts(game)
	count.time = game.state.time
	count.delivered = game.state.get("delivered",0)
	count.wallStats = stats(durations)
	report.samples.append(count)
	for key in ["entities","units","friendly","hostile","projectiles","corpses","effects","navigationPending","pathPending","pathFailed"]:
		report.peaks[key] = maxi(int(report.peaks.get(key,0)),int(count[key]))
	for actor in game.units():
		var p := WarData.point(actor)
		var id := int(actor.id)
		if not p.is_finite() or not is_finite(float(actor.hp)) or actor.hp < 0 or actor.hp > actor.maxHp+.00001:
			report.badValues.append({"id":id,"time":game.state.time,"p":p,"hp":actor.hp})
		if last_positions.has(id) and not actor.orders.is_empty() and str(actor.orders[0].kind) in ["move","attackmove","harvest"]:
			if p.distance_to(last_positions[id]) < .01: report.stalls.append({"id":id,"kind":actor.kind,"time":game.state.time,"p":p,"order":actor.orders[0].duplicate(true),"pending":actor.pathPending,"failed":actor.pathFailed})
		last_positions[id] = p
	print("SCALE t=",game.state.time," units=",count.units," friendly=",count.friendly," hostile=",count.hostile," nav=",count.navigationPending,"/",count.navigationActive," median/P95/max ms=",count.wallStats)
	write_json("progress",report)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	WarSave.directory = "user://test-saves/gameplay-scale"
	var restore_probe := OS.get_cmdline_user_args().has("--restore-probe")
	var seconds := 2.0 if OS.get_cmdline_user_args().has("--pilot") or restore_probe else 120.0
	report.sourceStart = hashes()
	var setup_began := Time.get_ticks_usec()
	game = WarSimulation.new(); fixture = Fixture.populate(game)
	report.setupMs = (Time.get_ticks_usec()-setup_began)/1000.0
	report.fixture = fixture
	check(fixture.errors.is_empty(),"all fixture spawn and depot sites are legal: "+str(fixture.errors))
	var initial: Dictionary = Fixture.counts(game)
	report.initial = initial
	check(initial.friendly == 40 and initial.hostile == 80,"explicit initial population is exactly forty friendlies and eighty pathogens")
	check(fixture.buildings.size() == 4,"four completed legal depots are explicitly injected")
	var overlaps := 0
	var units := game.units()
	for i in units.size():
		for j in range(i+1,units.size()):
			if not WarCellShape.contact(units[i],units[j]).is_empty(): overlaps += 1
	check(overlaps == 0,"initial actors are spaced with no polygon contacts")
	write_json("initial-snapshot",game.snapshot())
	if not failures.is_empty():
		report.failures = failures; write_json("setup-failure",report); game.dispose(); quit(1); return
	game.combat_event.connect(observe)
	Fixture.issue(game,fixture,false)
	var wall_began := Time.get_ticks_usec()
	for i in ceili(seconds/.1):
		var step_began := Time.get_ticks_usec()
		game.update(.1)
		durations.append((Time.get_ticks_usec()-step_began)/1000.0)
		if (i+1)%80 == 0 and i < 590: Fixture.issue(game,fixture,false)
		if i == 599 or (restore_probe and i == 19):
			restore_midway()
			Fixture.issue(game,fixture,true)
		if i == 0 or (i+1)%100 == 0 or i == ceili(seconds/.1)-1: sample()
		if (i+1)%100 == 0: await process_frame
	report.wallSeconds = (Time.get_ticks_usec()-wall_began)/1000000.0
	report.fixedStepMs = stats(durations)
	report.stepDurationsMs = durations
	report.simulatedSeconds = game.state.time
	report.final = Fixture.counts(game)
	report.eventCounts = event_counts
	report.sourceEnd = hashes()
	report.sourcesUnchangedDuringRun = report.sourceStart == report.sourceEnd
	check(report.badValues.is_empty(),"no sampled nonfinite or invalid unit state")
	check(is_equal_approx(float(game.state.time),seconds),"fixed steps really advance the full requested simulated interval")
	if seconds >= 120:
		check(not report.restore.is_empty() and report.restore.preserved,"full run includes a successful actual file restore")
		check(int(event_counts.get("damage",0)) > 0,"normal battle actually deals damage")
		check(float(game.state.get("delivered",0)) > 0,"actual harvesting includes at least one real deposit")
	report.failures = failures; report.checks = checks
	var prefix := "restore-probe" if restore_probe else ("pilot" if seconds < 120 else "checks")
	write_json(prefix,report); write_json(prefix+"-snapshot",game.snapshot())
	game.combat_event.disconnect(observe); game.dispose()
	print("GAMEPLAY SCALE ",checks-failures.size(),"/",checks," ",prefix," ",report.fixedStepMs)
	quit(0 if failures.is_empty() else 1)
