class_name WarSurvival
extends RefCounted
## Classic three-faction settlement loop. Full-body encounters do not opt in.
var game: WarSimulation
var biomes := PackedByteArray()

func _init(owner: WarSimulation) -> void:
	game = owner

func random() -> float:
	game.state.rng = (int(game.state.rng)*1664525+1013904223) % 4294967296
	return float(game.state.rng)/4294967296.0

func biome(p: Vector2) -> Dictionary:
	if biomes.is_empty():
		var file := FileAccess.open("res://data/sandbox/biomes.bin",FileAccess.READ)
		biomes = file.get_buffer(file.get_length())
	var x := clampi(int(p.x),0,2047)
	var y := clampi(int(p.y),0,4095)
	return WarData.config().Data.biomes[int(biomes[y*2048+x])-1]

func nearest(e: Dictionary,kinds: Array) -> Dictionary:
	var best: Dictionary = {}
	var distance := INF
	for b in game.entities():
		if b.hp <= 0 or b.faction != e.faction or b.category != "building" or not b.get("complete",false) or not b.kind in kinds: continue
		var d := WarData.point(e).distance_squared_to(WarData.point(b))
		if d < distance: distance = d; best = b
	return best

func unit(e: Dictionary,dt: float) -> bool:
	if game.mode != "sandbox": return false
	if float(e.get("satiety",100)) < 30 or e.get("returning",false):
		var home := nearest(e,["core","store"])
		if home.is_empty(): return false
		var p := WarData.point(home)
		if WarData.point(e).distance_to(p) > 5:
			e.returning = true
			game.go(e,p,dt,4.5,0)
			return true
		if float(e.get("satiety",100)) < 65:
			for kind in e.cargo: game.economy.add(int(e.faction),kind,e.cargo[kind])
			e.cargo = {}
			return true
		e.returning = false
		game.reset_path(e)
	return false

func update(dt: float) -> void:
	for faction in range(2,4):
		var fa: Dictionary = game.state.factions[faction-1]
		fa.ai.timer -= dt
		if fa.ai.timer <= 0:
			fa.ai.timer = 6.0+(faction-2)*.5
			think(faction)
	if int(game.state.tick) % 10 != 0: return
	var day := int(float(game.state.time)/360)+1
	if day > int(game.state.get("lastDay",1)):
		game.state.lastDay = day
		for resource in game.state.resources.values(): resource.amount = minf(float(resource.max),float(resource.amount)+float(resource.max)*.025)
		game.notify("第 %d 天" % day)
	var season := ((day-1)/8)%4
	var climate: Dictionary = WarData.config().Data.climate[season]
	var night := fmod(float(game.state.time),360)/360 >= .75
	var rain: bool = climate.get("rain",false) and sin(float(game.state.time)*.004) > .1
	for e in game.units():
		if e.faction <= 0: continue
		var supply := nearest(e,["core","store"])
		var fire := nearest(e,["fire"])
		var shelter := nearest(e,["house","core"])
		var kitchen := nearest(e,["kitchen"])
		var supplied := not supply.is_empty() and WarData.point(e).distance_to(WarData.point(supply)) < float(WarData.spec(supply.kind).get("supply",13))
		var lit := not fire.is_empty() and WarData.point(e).distance_to(WarData.point(fire)) < 9
		var sheltered := not shelter.is_empty() and WarData.point(e).distance_to(WarData.point(shelter)) < 5
		var cooked := not kitchen.is_empty() and WarData.point(e).distance_to(WarData.point(kitchen)) < 15
		e.satiety = maxf(0,float(e.get("satiety",100))-.075)
		e.feedTimer = float(e.get("feedTimer",0))+1
		if supplied and e.satiety < 70 and e.feedTimer > 5 and game.economy.stock(int(e.faction),"food") >= 3:
			game.economy.pay(int(e.faction),{"food":3})
			e.satiety = minf(100,float(e.satiety)+(40 if cooked else 30))
			e.feedTimer = 0
		e.wet = clampf(float(e.get("wet",0))+(.8 if rain and not sheltered else -.5),0,100)
		var target := float(climate.temperature)
		var terrain := biome(WarData.point(e))
		target += float(terrain.get("temperature",0))
		e.wet = clampf(float(e.wet)+float(terrain.get("wet",0)),0,100)
		if lit: target = maxf(target,22)
		if sheltered: target += 8 if season == 1 else (-8 if season == 3 else 0)
		target -= float(e.wet)*.08
		if game.state.factions[int(e.faction)-1].tech.get("insulation",false): target = (target+22)*.5
		e.temp = lerpf(float(e.get("temp",22)),target,.025)
		if e.satiety <= 0: game.combat.damage({},e,.9,true,"hunger")
		if e.temp < 0 or e.temp > 40: game.combat.damage({},e,.6,true,"temperature")
		e.sanity = clampf(float(e.get("sanity",100))+(-.28 if night and not lit and not sheltered else (.3 if sheltered else .08))-(.2 if e.satiety <= 0 else 0),0,100)
		if e.sanity < 18:
			e.panic = float(e.get("panic",0))+1
			if e.panic > 40:
				e.panic = 0
				var shadow := game.spawn("shadow",0,WarData.point(e)+Vector2(3,3))
				if not shadow.is_empty(): shadow.life = 35
	for b in game.entities():
		if b.category != "building" or b.hp <= 0: continue
		if float(b.get("fire",0)) > 0:
			game.combat.damage({},b,.8 if rain else 4,true,"fire")
			b.fire = maxf(0,float(b.fire)-(.1 if rain else .008))
		if climate.has("fireRisk") and not b.kind in ["fire","wall"] and random() < float(climate.fireRisk): b.fire = 1
	var lost: Array = []
	for faction in range(1,4):
		var living := 0
		for e in game.entities():
			if e.faction == faction and e.hp > 0 and (e.category == "unit" or e.kind in ["core","barracks","range","workshop"]): living += 1
		game.state.factions[faction-1].lost = living == 0
		lost.append(living == 0)
	if lost[0]: game.state.outcome = "defeat"; game.notify("胞群全灭，可以读取存档继续。")
	elif lost[1] and lost[2]: game.state.outcome = "victory"; game.notify("已战胜两个阵营，可继续生存。")

func think(faction: int) -> void:
	var fa: Dictionary = game.state.factions[faction-1]
	if fa.get("lost",false): return
	var workers: Array = []
	var troops: Array = []
	var buildings: Dictionary = {}
	for e in game.entities():
		if e.faction != faction or e.hp <= 0: continue
		if e.kind == "worker": workers.append(e)
		elif e.category == "unit": troops.append(e)
		elif e.get("complete",false): buildings[e.kind] = e
	if workers.is_empty() and buildings.is_empty(): return
	var base: Dictionary = buildings.get("core",buildings.get("store",workers[0] if not workers.is_empty() else {}))
	if base.is_empty(): return
	var idle: Array = workers.filter(func(e): return e.orders.is_empty() or e.pathFailed)
	var pop := game.economy.population(faction)
	var plan: String = ""
	if not buildings.has("core"): plan = "core"
	elif pop.y < mini(40,pop.x+5): plan = "house"
	elif not buildings.has("barracks"): plan = "barracks"
	elif not buildings.has("farm"): plan = "farm"
	elif not buildings.has("lab"): plan = "lab"
	elif not buildings.has("kitchen"): plan = "kitchen"
	elif int(fa.tier) >= 2 and not buildings.has("range"): plan = "range"
	elif int(fa.tier) >= 3 and not buildings.has("workshop"): plan = "workshop"
	if not idle.is_empty() and not plan.is_empty():
		var already := false
		for e in game.entities():
			if e.faction == faction and e.kind == plan and not e.get("complete",false): already = true
		if not already:
			for i in 30:
				var p := WarData.point(base)+Vector2(random()-.5,random()-.5)*22
				if game.economy.place(plan,p,[int(idle[0].id)],faction): break
	if buildings.has("core") and buildings.core.queue.is_empty():
		if workers.size() < mini(14,int(pop.y*.45)): game.economy.train(buildings.core,"worker")
		elif troops.size() < 1: game.economy.train(buildings.core,"scout")
	for kind in ["barracks","range","workshop"]:
		if buildings.has(kind) and buildings[kind].queue.is_empty() and game.economy.stock(faction,"food") > 30:
			game.economy.train(buildings[kind],"archer" if kind == "range" else ("siege" if kind == "workshop" else "spear"))
	if buildings.has("lab") and not fa.get("researching",false):
		for tech in ["tier2","storage","insulation","tier3","weapons"]:
			if not fa.tech.get(tech,false): game.economy.research(buildings.lab,tech); break
	for worker in idle:
		var job: Dictionary = {}
		for b in game.entities():
			if b.faction == faction and b.category == "building" and b.hp > 0:
				if not b.get("complete",false): job = {"kind":"build","target":b.id}; break
				if float(b.get("fire",0)) > 0: job = {"kind":"extinguish","target":b.id}; break
				if b.kind == "farm":
					var staffed := false
					for other in workers:
						if not other.orders.is_empty() and other.orders[0].get("target",0) == b.id: staffed = true
					if not staffed: job = {"kind":"farm","target":b.id}; break
		if job.is_empty():
			var best := ""
			var distance := INF
			for key in game.state.resources:
				var r: Dictionary = game.state.resources[key]
				var d := WarData.point(worker).distance_squared_to(WarData.point(r))
				if r.amount > 0 and d < distance and d < 80*80:
					best = key; distance = d
			if not best.is_empty(): job = {"kind":"harvest","resource":best}
		if not job.is_empty(): game.order(worker,job)
	var known := game.entities().filter(func(e): return e.kind == "core" and e.faction != faction and e.faction > 0 and game.visible(e,faction))
	for troop in troops:
		if not troop.orders.is_empty() and not troop.pathFailed: continue
		var target := WarData.point(base)+Vector2.from_angle(int(troop.id)*2.4)*7
		var kind := "guard"
		if troops.size() >= (13 if faction == 2 else 7) and not known.is_empty():
			target = WarData.point(known[0]); kind = "attackmove"
		game.order(troop,{"kind":kind,"x":target.x,"y":target.y,"lane":0})
