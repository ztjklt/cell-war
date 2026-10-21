extends SceneTree
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,text: String) -> void:
	checks += 1
	if not value: failures.append(text); printerr("FAIL ",text)

func pending(game: WarSimulation,id: String) -> Dictionary:
	var s := game.life.state()
	s.serial += 1; s.pending = {"id":id,"token":s.serial,"offeredAt":s.activeElapsed}; s.revision += 1
	return s

func run() -> void:
	WarSave.directory = "user://test-saves/life-mechanism"
	var game := WarSimulation.new()
	game.start("life",73)
	var s := game.life.state()
	check(game.mode == "fullbody" and s.money == 300 and s.function == 85,"new life uses native body with independent money and function")
	game.step(.1)
	check(game.state.influenzaColonies.groups.is_empty(),"life does not stack legacy initial infection")
	game.life.begin(73); s = game.life.state(); s.riskThreshold = 1e6
	game.life.advance(179.9)
	check(s.pending.is_empty(),"no initial contact before three active minutes")
	game.life.advance(.1)
	check(not s.pending.is_empty(),"first contact at three active minutes")
	var first_id: String = s.pending.id
	check(WarLifeRun.definition(first_id).options.size() == 3,"offered conversation has three authored choices")
	var token := int(s.pending.token)
	check(game.life.choose(token,0),"first offered choice settles")
	var money := int(s.money)
	check(not game.life.choose(token,0) and int(s.money) == money,"repeated submission cannot settle twice")
	var wait := float(s.nextDecisionAt)-float(s.activeElapsed)
	check(wait >= 120 and wait <= 180,"subsequent contacts spaced two to three active minutes after reply")
	game.life.advance(wait-.1); check(s.pending.is_empty(),"no early follow-up")
	game.life.advance(.2); check(not s.pending.is_empty(),"follow-up becomes available after full interval")
	var retained: Dictionary = s.pending.duplicate(true)
	game.life.advance(600)
	check(s.pending == retained,"unanswered conversation stays single without catch-up queue")
	game.life.begin(73); s = game.life.state(); game.speed = 2; s.riskThreshold = 1e6
	game.life.advance(358)
	check(s.pending.is_empty(),"double speed does not shorten outside contact to ninety seconds")
	game.life.advance(2)
	check(not s.pending.is_empty(),"double speed waits three active minutes for initial contact")
	game.speed = 1; game.paused = true
	var before := game.snapshot()
	game.update(.25)
	check(game.life.state() == before.lifeRun,"pause freezes money, body, effects and decision clock")
	game.paused = false
	var seen: Dictionary = {}
	for item in WarLifeRun.catalogue():
		check(not seen.has(item.id) and item.options.size() == 3,"unique complete event "+item.id)
		seen[item.id] = true
		for i in item.options.size():
			game.life.begin(73); s = pending(game,item.id)
			var option: Dictionary = item.options[i]
			check(game.life.choose(int(s.pending.token),i),"authored option settles "+item.id+str(i))
			check(int(s.money) == 300+int(option.money),"authored money "+item.id+str(i))
			check(is_equal_approx(float(s.function),clampf(85+float(option.function),0,100)),"authored function "+item.id+str(i))
			check(s.history.back().reply == option.reply,"own response retained "+item.id+str(i))
			check(WarSave.validate(game.snapshot()).is_empty(),"option snapshot validates "+item.id+str(i))
	check(seen.size() == 40,"all forty events and 120 choices execute")
	game.life.begin(73); s = pending(game,"lunch_choice"); s.money = 0
	check(not game.life.choose(int(s.pending.token),0) and not s.pending.is_empty(),"unaffordable reply neither charges nor consumes offer")
	check(game.life.choose(int(s.pending.token),2),"cashless player retains a valid choice")
	game.life.begin(73); s = game.life.state()
	check(not game.life.eligible(WarLifeRun.definition("study_opportunity")),"follow-up requires prior study")
	s = pending(game,"study"); game.life.choose(int(s.pending.token),0)
	check(game.life.eligible(WarLifeRun.definition("study_opportunity")),"prior study unlocks linked outside conversation")
	s = pending(game,"late_work"); game.life.choose(int(s.pending.token),2)
	check(game.life.eligible(WarLifeRun.definition("morning_after")) and not s.effects.is_empty(),"late night unlocks morning aftermath and delayed wear")
	s.riskThreshold = 1e6; game.life.advance(241)
	check(s.effects.is_empty(),"temporary consequences expire")
	game.life.begin(177); game.life.advance(180); s = game.life.state()
	var snapshot := game.snapshot()
	check(WarSave.write_life_auto(game) == OK,"independent life autosave writes atomically")
	check(WarSave.life_auto_path() != WarSave.path(0),"life autosave separate from legacy slot zero")
	game.life.choose(int(s.pending.token),0)
	var read_error := WarSave.read_life_auto(game)
	check(read_error == OK and game.life.state() == snapshot.lifeRun,"load retains offered identity, RNG, time, money and pending options")
	var loaded := game.life.state()
	game.life.choose(int(loaded.pending.token),0)
	var outcome := game.life.state().duplicate(true)
	game.restore(snapshot); game.life.choose(int(game.life.state().pending.token),0)
	check(game.life.state() == outcome,"restored offer resolves deterministically without reroll")
	var bad := game.snapshot(); bad.lifeRun.function = NAN
	check(not WarSave.validate(bad).is_empty(),"non-finite function rejected")
	bad = game.snapshot(); bad.lifeRun.pending = {"id":"unknown","token":bad.lifeRun.serial}
	check(not WarSave.validate(bad).is_empty(),"unknown pending conversation rejected")
	bad = game.snapshot(); bad.lifeRun.history[0].erase("money")
	check(not WarSave.validate(bad).is_empty(),"malformed dialogue transaction rejected before restore")
	game.life.begin(73); s = game.life.state(); s.function = 90
	var healthy := game.life.risk_rate(); s.function = 20
	check(game.life.risk_rate() > healthy,"lower function increases hazard under equal exposure")
	s = pending(game,"crowded_party"); game.life.choose(int(s.pending.token),2)
	var exposed := game.life.risk_rate(); s.exposures = []
	check(exposed > game.life.risk_rate(),"outside exposure independently affects risk")
	s.activeElapsed = 181.0; s.elapsed = 181.0; s.riskThreshold = .00001
	game.life._external(1)
	check(s.outbreaks == 1 and game.state.influenzaColonies.groups.size() == 1,"director creates exactly one certified lung colony")
	var colony: Dictionary = game.state.influenzaColonies.groups.values()[0]
	check(colony.organ in ["lung_l","lung_r"] and colony.pending >= 10 and colony.pending <= 20,"existing flu count and organ contract retained")
	for i in 5: game.influenza.before_step(0)
	check(game.influenza.members(colony).size() >= 10,"directed outbreak creates real viruses")
	for e in game.influenza.members(colony):
		check(int(e.vesselLane) == 0 and game.navigation.organ_at(WarData.point(e),"virus") == colony.organ,"birth retains legal organ/tissue plane")
	check(WarSave.validate(game.snapshot()).is_empty(),"real directed infection saves with its life source")
	for e in game.influenza.members(colony): e.hp = 0
	game.influenza.after_step(0); game.life._refresh_load()
	check(not colony.cleared and int(s.recovered) == 0 and not game.life.eligible(WarLifeRun.definition("after_infection")),"kills alone do not unlock recovery before joint purification")
	check(game.life._groups == 1,"uncleared source retains its active infection budget without living enemies")
	var red: Dictionary = game.units().filter(func(e): return e.kind == "worker" and e.faction == 1)[0]
	red.x = float(colony.center[0])-2; red.y = float(colony.center[1]); red.vesselLane = 0
	var white := game.spawn("spear",1,WarData.point(colony.center)+Vector2(2,0))
	white.vesselLane = 0
	game.order(red,{"kind":"hold"}); game.order(white,{"kind":"hold"})
	game.influenza.after_step(WarInfectionPurification.HOLD_SECONDS); game.life._refresh_load()
	check(colony.cleared and int(s.recovered) == 1 and game.life.eligible(WarLifeRun.definition("after_infection")),"completed red-white joint purification unlocks recovery conversation")
	game.life._refresh_load()
	check(int(s.recovered) == 1,"clearance is not counted every frame")
	game.life.begin(73); s = game.life.state(); s.function = 0; s.phase = "crisis"; s.crisisRemaining = .2
	game.life.advance(.3)
	check(s.phase == "ended" and game.paused and float(s.finishedAge) > 0,"sustained crisis ends life once with age recorded")
	var ended := s.duplicate(true); game.life.advance(100)
	check(s == ended,"ended life cannot continue or repeatedly settle")
	game.start("systemic")
	check(not game.life.enabled() and WarSave.validate(game.snapshot()).is_empty(),"legacy mode remains independent and loadable")
	game.start("life",510); s = game.life.state()
	for i in 2160:
		game.life.advance(10)
		if not s.pending.is_empty():
			var item := WarLifeRun.definition(s.pending.id)
			for index in item.options.size():
				if game.life.affordable(item.options[index]): game.life.choose(int(s.pending.token),index); break
		if s.phase == "ended": break
	check(s.history.size() <= 40 and s.effects.size() < 4 and s.exposures.size() < 4,"six-hour accelerated state check keeps histories and effects bounded")
	check(s.money >= 0 and s.function >= 0 and s.function <= 100 and WarSave.validate(game.snapshot()).is_empty(),"long-run state remains valid with life calendar and repeated decisions")
	DirAccess.make_dir_recursive_absolute("res://test-output")
	var file := FileAccess.open("res://test-output/life-run.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"events":40,"choices":120,"failures":failures},"  "))
	game.dispose()
	print("LIFE RUN ",checks," checks, failures=",failures)
	quit(0 if failures.is_empty() else 1)
