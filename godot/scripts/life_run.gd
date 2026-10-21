class_name WarLifeRun
extends RefCounted
## Life decisions are simulation state. The chat view only submits a stable choice ID.
var game: WarSimulation
var _load_clock := 0.0
var _load := 0.0
var _groups := 0

func _init(owner: WarSimulation) -> void:
	game = owner

static func rules() -> Dictionary:
	return WarData.read("life_balance")

static func catalogue() -> Array:
	return WarData.read("life_decisions").events

static func definition(id: String) -> Dictionary:
	for item in catalogue():
		if item.id == id: return item
	return {}

func enabled() -> bool:
	return game.state.get("lifeRun") is Dictionary

func state() -> Dictionary:
	return game.state.get("lifeRun",{})

func begin(seed: int) -> void:
	var k := rules()
	game.state.lifeRun = {"version":1,"elapsed":0.0,"activeElapsed":0.0,"age":float(k.startingAge),
		"money":int(k.startingMoney),"function":float(k.startingFunction),"phase":"living","crisisRemaining":float(k.crisisSeconds),
		"rng":posmod(seed,2147483646)+1,"serial":0,"revision":0,"decisionCount":0,
		"pending":{},"nextDecisionAt":float(k.firstDecisionAfter),"incomeElapsed":0.0,
		"effects":[],"exposures":[],"flags":{},"cooldowns":{},"lastCategory":"","history":[],
		"riskHazard":0.0,"riskThreshold":1.0,"nextOutbreakAt":float(k.externalGracePeriod),
		"outbreaks":0,"recovered":0,"clearedGroups":[],"lastChoice":"","lastChange":"生活节奏由你决定",
		"earned":0,"spent":0,"peakInfections":0,"finishedAge":0.0}
	state().riskThreshold = -log(maxf(.000001,random()))
	# The life director owns its first infection. Legacy fullbody keeps its own start.
	game.state.influenzaColonies = {"version":1,"groups":{}}
	reset()

func reset() -> void:
	_load_clock = 0; _load = 0; _groups = 0
	if not enabled(): return
	var s := state()
	# JSON parses numbers as doubles. Restore transaction identifiers and counters.
	for key in ["version","money","rng","serial","revision","decisionCount","outbreaks","recovered","earned","spent","peakInfections"]: s[key] = int(s[key])
	if not s.pending.is_empty(): s.pending.token = int(s.pending.token)
	for key in s.flags: s.flags[key] = int(s.flags[key])
	for entry in s.history: entry.money = int(entry.money)

func random() -> float:
	var s := state()
	s.rng = (int(s.rng)*48271)%2147483647
	return float(s.rng)/2147483647.0

func eligible(item: Dictionary) -> bool:
	var s := state()
	var req: Dictionary = item.get("requires",{})
	if float(s.function) > float(req.get("maxFunction",100)): return false
	if int(s.money) > int(req.get("maxMoney",2147483647)): return false
	if int(s.decisionCount) < int(req.get("minDecisions",0)): return false
	if req.has("flag") and int(s.flags.get(req.flag,0)) <= 0: return false
	if req.has("anyFlags") and not req.anyFlags.any(func(key): return int(s.flags.get(key,0)) > 0): return false
	if req.get("exposed",false) and s.exposures.is_empty(): return false
	if req.get("recovered",false) and int(s.recovered) == 0: return false
	return float(s.activeElapsed) >= float(s.cooldowns.get(item.id,0))

func offer() -> void:
	var s := state()
	if not enabled() or s.phase == "ended" or not s.pending.is_empty(): return
	var candidates: Array = catalogue().filter(func(item): return eligible(item) and item.category != s.lastCategory)
	if candidates.is_empty(): candidates = catalogue().filter(func(item): return eligible(item))
	if candidates.is_empty(): s.nextDecisionAt = float(s.activeElapsed)+rules().decisionIntervalMin; return
	# Prioritise recovery at low function while keeping other offers possible.
	var weights: Array[float] = []
	var total := 0.0
	for item in candidates:
		var weight := 1.0
		if item.id in ["decline_warning","low_function_rest"] and float(s.function) < 40: weight = 4.0
		if item.category == "后续": weight *= 1.5
		total += weight; weights.append(weight)
	var chosen: Dictionary = candidates.back()
	var draw := random()*total
	for i in candidates.size():
		draw -= weights[i]
		if draw <= 0: chosen = candidates[i]; break
	s.serial += 1
	s.pending = {"id":chosen.id,"token":int(s.serial),"offeredAt":float(s.activeElapsed)}
	s.revision += 1
	game.event("life_offer",{"decision":chosen.id,"token":s.serial})

func affordable(option: Dictionary) -> bool:
	return enabled() and int(state().money)+int(option.money) >= 0

func choose(token: int,index: int) -> bool:
	if not enabled(): return false
	var s := state()
	if s.phase == "ended" or s.pending.is_empty() or int(s.pending.token) != token: return false
	var item := definition(str(s.pending.id))
	if index < 0 or index >= item.options.size(): return false
	var option: Dictionary = item.options[index]
	if not affordable(option): return false
	var before := float(s.function)
	s.money += int(option.money)
	s.earned += maxi(0,int(option.money)); s.spent += maxi(0,-int(option.money))
	s.function = clampf(before+float(option.function),0,100)
	if option.has("effect"):
		s.effects.append({"source":item.id,"remaining":float(option.effect.duration),"rate":float(option.effect.ratePerMinute)})
	if option.has("exposure"):
		s.exposures.append({"source":item.id,"kind":option.exposure.kind,"remaining":float(option.exposure.duration),"multiplier":float(option.exposure.multiplier)})
	for key in option.get("flags",{}): s.flags[key] = clampi(int(s.flags.get(key,0))+int(option.flags[key]),0,12)
	s.decisionCount += 1; s.revision += 1; s.lastCategory = item.category; s.lastChoice = item.id
	s.history.append({"id":item.id,"title":item.title,"speaker":item.speaker,"role":item.role,"line":item.line,"own":item.own,
		"label":option.label,"reply":option.reply,"money":int(option.money),"function":float(s.function)-before,"age":s.age})
	while s.history.size() > int(rules().historyLimit): s.history.pop_front()
	s.cooldowns[item.id] = float(s.activeElapsed)+900.0
	s.pending = {}
	s.nextDecisionAt = float(s.activeElapsed)+lerpf(float(rules().decisionIntervalMin),float(rules().decisionIntervalMax),random())
	s.lastChange = "%s · 金钱 %+d，机能 %+.0f" % [option.label,int(option.money),float(s.function)-before]
	game.notify(s.lastChange)
	game.event("life_choice",{"decision":item.id,"option":index,"token":token})
	_check_crisis(0)
	return true

static func effect_text(option: Dictionary) -> String:
	var text := "金钱 %+d  ·  机能 %+.0f" % [int(option.money),float(option.function)]
	if option.has("effect"): text += "\n随后恢复%s · 4分钟" % ("加快" if float(option.effect.ratePerMinute) > 0 else "减慢")
	if option.has("exposure"): text += "\n呼吸道接触风险%s · 4分钟" % ("增加" if float(option.exposure.multiplier) > 1 else "降低")
	return text

func advance(dt: float) -> void:
	if not enabled() or state().phase == "ended": return
	var s := state()
	var k := rules()
	s.elapsed += dt
	# A speed-up never makes outside contacts arrive sooner than 2 real active minutes.
	s.activeElapsed += dt/maxf(1.0,game.speed)
	s.age = float(k.startingAge)+float(s.elapsed)/float(k.secondsPerYear)
	s.incomeElapsed += dt
	while float(s.incomeElapsed) >= float(k.incomePeriod):
		s.incomeElapsed -= float(k.incomePeriod)
		s.money += int(k.regularIncome)-int(k.basicExpense)
		s.earned += int(k.regularIncome); s.spent += int(k.basicExpense)
	var effect_delta := 0.0
	for effect in s.effects:
		var used := minf(dt,float(effect.remaining))
		effect_delta += float(effect.rate)*used/60.0
		effect.remaining = maxf(0,float(effect.remaining)-dt)
	s.effects = s.effects.filter(func(e): return float(e.remaining) > 0)
	for exposure in s.exposures: exposure.remaining = maxf(0,float(exposure.remaining)-dt)
	s.exposures = s.exposures.filter(func(e): return float(e.remaining) > 0)
	_load_clock -= dt
	if _load_clock <= 0:
		_refresh_load(); _load_clock = 1.0
	var wear := float(k.baseWearPerMinute)+pow(maxf(0,float(s.age)-float(k.agingStartsAt)),2)*float(k.agingWearFactor)
	s.function = clampf(float(s.function)+effect_delta+(float(k.baseRecoveryPerMinute)-wear-_load)*dt/60.0,0,100)
	_check_crisis(dt)
	if s.phase == "ended": return
	if s.pending.is_empty() and float(s.activeElapsed) >= float(s.nextDecisionAt): offer()
	_external(dt)

func _refresh_load() -> void:
	var s := state()
	var active: Dictionary = {}
	var count := 0
	for entity in game.entities():
		if entity.hp > 0 and entity.has("fluColony"):
			active[entity.fluColony] = true
			if entity.kind == "virus": count += 1
	for group in game.state.get("influenzaColonies",{}).get("groups",{}).values():
		# Killing a wave does not finish its regional infection. Keep the source in
		# the budget/load until the red-white purification service marks it clear.
		if not group.get("cleared",false): active[group.id] = true
		if group.cleared and int(group.get("lifeClearedBatch",0)) < int(group.batches):
			group.lifeClearedBatch = int(group.batches)
			if not s.clearedGroups.has(group.id): s.clearedGroups.append(group.id)
			s.recovered += 1
	_groups = active.size()
	s.peakInfections = maxi(int(s.peakInfections),_groups)
	_load = minf(float(rules().infectionLossPerMinuteCap),_groups*float(rules().infectionLossPerGroup)+count*float(rules().infectionLossPerVirus))

func risk_rate() -> float:
	if not enabled(): return 0
	var s := state()
	var exposure := 1.0
	for item in s.exposures: exposure *= float(item.multiplier)
	exposure = clampf(exposure,.35,float(rules().exposureMultiplierCap))
	var q := clampf((100-float(s.function))/100,0,1)
	return float(rules().externalRatePerMinute)*(1+2.5*q)*exposure*(1+maxf(0,float(s.age)-45)*.012)

func _external(dt: float) -> void:
	var s := state()
	if float(s.activeElapsed) < float(rules().externalGracePeriod) or float(s.elapsed) < float(s.nextOutbreakAt): return
	if _groups >= int(rules().activeInfectionLimit): return
	s.riskHazard += risk_rate()*dt/60.0
	if float(s.riskHazard) < float(s.riskThreshold): return
	var organ := "lung_r" if random() < .5 else "lung_l"
	var zone := game.influenza.zone(organ)
	if zone.is_empty(): return
	var index := mini(zone.placements.size()-1,int(random()*zone.placements.size()))
	var q := (100-float(s.function))/100
	var amount := clampi(10+roundi(q*8)+int(random()*3),10,20)
	var group := game.influenza.start_outbreak(organ,index,amount)
	if group.is_empty(): return
	group.lifeSource = str(s.lastChoice)
	s.outbreaks += 1; s.riskHazard = 0.0; s.riskThreshold = -log(maxf(.000001,random()))
	s.nextOutbreakAt = float(s.elapsed)+float(rules().externalCooldown)
	_load_clock = 0
	game.event("life_invasion",{"organ":organ,"count":amount,"decision":s.lastChoice,"function":s.function})

func _check_crisis(dt: float) -> void:
	var s := state()
	if float(s.function) >= float(rules().safeFunction):
		s.phase = "living"; s.crisisRemaining = float(rules().crisisSeconds)
	elif float(s.function) <= 0 or s.phase == "crisis":
		if s.phase != "crisis": game.notify("小脑：身体进入危急状态，请尽快控制感染、争取恢复。")
		s.phase = "crisis"; s.crisisRemaining = maxf(0,float(s.crisisRemaining)-dt)
		if float(s.crisisRemaining) <= 0:
			s.phase = "ended"; s.finishedAge = s.age; s.revision += 1
			game.paused = true
			game.notify("本次生命历程结束 · 存活至 %.1f 岁" % float(s.age))

static func validate(snapshot: Dictionary) -> String:
	if not snapshot.has("lifeRun"): return ""
	if not snapshot.lifeRun is Dictionary: return "生活记录无效"
	var s: Dictionary = snapshot.lifeRun
	if s.get("version",0) != 1 or not s.get("phase","") in ["living","crisis","ended"]: return "生活版本或阶段无效"
	for key in ["elapsed","activeElapsed","age","money","function","crisisRemaining","rng","serial","revision","decisionCount","nextDecisionAt","incomeElapsed","riskHazard","riskThreshold","nextOutbreakAt","outbreaks","recovered","earned","spent","peakInfections","finishedAge"]:
		var value: Variant = s.get(key)
		if not (value is float or value is int) or not is_finite(float(value)) or float(value) < 0: return "生活数值无效："+key
	if float(s.function) > 100 or float(s.money) > 1e12 or int(s.money) != float(s.money): return "金钱或机能范围无效"
	if int(s.rng) < 1 or int(s.rng) >= 2147483647 or float(s.riskThreshold) <= 0: return "生活随机状态无效"
	for key in ["rng","serial","revision","decisionCount","outbreaks","recovered","earned","spent","peakInfections"]:
		if float(s[key]) != int(s[key]): return "生活计数无效："+key
	for key in ["pending","flags","cooldowns"]:
		if not s.get(key) is Dictionary: return "生活状态无效："+key
	for key in ["effects","exposures","history","clearedGroups"]:
		if not s.get(key) is Array: return "生活列表无效："+key
	if s.effects.size() > 64 or s.exposures.size() > 64 or s.history.size() > 40 or s.clearedGroups.size() > 56: return "生活列表超过上限"
	if not s.pending.is_empty():
		var token: Variant = s.pending.get("token")
		if definition(str(s.pending.get("id",""))).is_empty() or not (token is float or token is int) or not is_finite(float(token)): return "待选事件无效"
		if int(token) != float(token) or int(token) != int(s.serial) or int(token) <= 0: return "待选事件编号无效"
	for effect in s.effects+s.exposures:
		if not effect is Dictionary or definition(str(effect.get("source",""))).is_empty(): return "生活效果来源无效"
		var remaining: Variant = effect.get("remaining")
		if not (remaining is int or remaining is float) or not is_finite(float(remaining)) or float(remaining) <= 0 or float(remaining) > 240: return "生活效果时间无效"
		var key := "rate" if effect.has("rate") else "multiplier"
		var value: Variant = effect.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or absf(float(value)) > 3: return "生活效果数值无效"
	for entry in s.history:
		if not entry is Dictionary or definition(str(entry.get("id",""))).is_empty(): return "对话历史无效"
		for key in ["title","speaker","role","line","own","label","reply"]:
			if not entry.get(key) is String or entry[key].length() > 500: return "对话内容无效"
		for key in ["money","function","age"]:
			var value: Variant = entry.get(key)
			if not (value is float or value is int) or not is_finite(float(value)): return "对话结算无效"
		if int(entry.money) != float(entry.money) or absf(float(entry.money)) > 100000 or absf(float(entry.function)) > 100 or float(entry.age) < 0: return "对话结算范围无效"
	for value in s.flags.values():
		if not (value is int or value is float) or not is_finite(float(value)) or int(value) != float(value) or float(value) < 0 or float(value) > 12: return "生活标记无效"
	for id in s.clearedGroups:
		if not id is String: return "已清除感染记录无效"
	for value in s.cooldowns.values():
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0: return "生活冷却无效"
	for key in ["lastCategory","lastChoice","lastChange"]:
		if not s.get(key) is String or s[key].length() > 500: return "生活摘要无效"
	return ""
