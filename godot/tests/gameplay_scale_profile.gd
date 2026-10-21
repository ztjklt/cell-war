extends SceneTree
const Fixture := preload("res://tests/fixtures/gameplay_scale_fixture.gd")
const Probe := preload("res://tests/fixtures/gameplay_scale_probe.gd")

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var report := {"scope":"Separate inclusive-counter diagnostic, same authored fixture; instrumentation overhead means this is not the benchmark.","phases":[]}
	for combat_phase in [false,true]:
		var game := Probe.new()
		var fixture: Dictionary = Fixture.populate(game)
		Fixture.issue(game,fixture,combat_phase)
		var began := Time.get_ticks_usec()
		for i in 10: game.update(.1)
		var item := {"phase":"combat" if combat_phase else "movement","steps":10,"wallMs":(Time.get_ticks_usec()-began)/1000.0,"inclusiveCounters":game.measured.duplicate(true),"counts":Fixture.counts(game)}
		report.phases.append(item)
		print("SCALE DIAGNOSTIC ",item)
		game.dispose()
	DirAccess.make_dir_recursive_absolute("res://test-output/gameplay-scale")
	var file := FileAccess.open("res://test-output/gameplay-scale/profile.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ",true,true))
	quit()
