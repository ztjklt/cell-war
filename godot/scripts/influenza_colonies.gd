class_name WarInfluenzaColonies
extends RefCounted
## Infection groups retain their builders; living population grants fortress slots.
var game: WarSimulation
var purification: WarInfectionPurification
const WORK_RADIUS := 4.2
const APPROACH_RADIUS := 6.2

func _init(owner: WarSimulation) -> void:
	game = owner
	purification = WarInfectionPurification.new(owner)

static func data() -> Dictionary:
	return WarData.read("influenza_fortress")

func state() -> Dictionary:
	if not game.state.get("influenzaColonies") is Dictionary:
		game.state.influenzaColonies = {"version":1,"groups":{}}
	return game.state.influenzaColonies

func zone(organ: String) -> Dictionary:
	for item in WarData.read("infection_zones").zones:
		if item.organ == organ: return item
	return {}

func start_outbreak(organ: String,index := 0,count := 0) -> Dictionary:
	if game.mode != "fullbody": return {}
	var region := zone(organ)
	if region.is_empty(): return {}
	var patch: Dictionary = region.placements[posmod(index,region.placements.size())]
	var rules: Dictionary = data().rules
	var amount := clampi(count,int(rules.waveMin),int(rules.waveMax)) if count > 0 else int(rules.waveMin)+posmod(int(game.state.seed)+int(game.state.nextId)*7,int(rules.waveMax)-int(rules.waveMin)+1)
	var groups: Dictionary = state().groups
	var id: String = patch.id
	if not groups.has(id):
		groups[id] = {"id":id,"organ":organ,"center":patch.center.duplicate(),"targetGate":patch.targetGate,
			"pending":0,"batches":0,"produced":0,"nextBuildCheck":0.0,"cleared":false}
	var group: Dictionary = groups[id]
	purification.reset(group)
	group.pending = mini(4096,int(group.pending)+amount)
	group.batches += 1; group.cleared = false
	game.event("influenza_outbreak",{"organ":organ,"count":amount,"colony":id})
	game.notify("%s出现流感感染 · 本批 %d 个病毒" % [region.name,amount])
	return group

func members(group: Dictionary) -> Array:
	return game.units().filter(func(e): return e.kind == "virus" and e.hp > 0 and e.get("fluColony","") == group.id)

func forts(group: Dictionary) -> Array:
	return game.entities().filter(func(e): return e.kind == "flu_fortress" and e.hp > 0 and e.get("fluColony","") == group.id)

func before_step(dt: float) -> void:
	if game.mode != "fullbody": return
	# Existing small encounters/campaigns and the paused art preview keep their starts.
	if game.mode == "fullbody" and not game.state.has("influenzaColonies"):
		start_outbreak("lung_r")
	if not game.state.get("influenzaColonies") is Dictionary: return
	for group in state().groups.values():
		if group.get("cleared",false): continue
		if int(group.pending) > 0:
			for i in mini(4,int(group.pending)):
				var e := _spawn_virus(group,WarData.point(group.center))
				if e.is_empty(): break
				group.pending -= 1
		for fort in forts(group):
			if not fort.get("complete",false): continue
			var period: float = data().rules.spawnPeriod
			fort.growthElapsed = float(fort.get("growthElapsed",0))+dt
			while float(fort.growthElapsed)+.000001 >= period:
				var e := _spawn_virus(group,WarData.point(fort))
				if e.is_empty(): fort.growthElapsed = period; break
				fort.growthElapsed = maxf(0,float(fort.growthElapsed)-period)
				group.produced += 1
				game.event("influenza_birth",{"fortress":fort.id,"unit":e.id,"colony":group.id})

func after_step(dt: float) -> void:
	if game.mode != "fullbody": return
	if not game.state.get("influenzaColonies") is Dictionary: return
	purification.update(dt)
	for group in state().groups.values():
		if group.get("cleared",false): continue
		var population := members(group)
		var buildings := forts(group)
		for fort in buildings:
			if fort.get("complete",false): continue
			_repair_team(fort,population)
			var working := 0
			for id in fort.builders:
				var e := game.entity(int(id))
				if e.is_empty() or e.hp <= 0: continue
				if is_equal_approx(float(e.get("fluWorkedAt",-100)),float(game.state.time)): working += 1
			if working < int(data().rules.builders): continue
			fort.progress = minf(1,float(fort.progress)+dt/float(data().rules.buildSeconds))
			fort.hp = maxf(float(fort.hp),float(fort.maxHp)*float(fort.progress))
			if float(fort.progress) >= .999999:
				fort.complete = true; fort.progress = 1.0; fort.growthElapsed = 0.0
				_release(fort)
				game.event("influenza_fortress_complete",{"fortress":fort.id,"colony":group.id})
				game.notify("流感要塞建成 · 每 30 秒孵化 1 个病毒")
		var unfinished := buildings.any(func(e): return not e.get("complete",false))
		if not unfinished and population.size()/int(data().rules.builders) >= buildings.size()+1 and float(game.state.time) >= float(group.nextBuildCheck):
			group.nextBuildCheck = float(game.state.time)+1.0
			_start_site(group,population)

func unit(e: Dictionary,dt: float) -> bool:
	if e.kind != "virus" or not e.has("fluColony"): return false
	var site := game.entity(int(e.get("fluBuildSite",0)))
	if site.is_empty() or site.hp <= 0 or site.get("complete",false):
		if e.has("fluBuildSite"):
			e.erase("fluBuildSite"); e.erase("fluBuildSlot"); game.reset_path(e)
		return _yield_construction_access(e,dt)
	# Builders use the same actual combat system as attacking viruses.
	var enemy := game.combat.enemy(e,float(WarData.spec("virus").vision),true)
	if not enemy.is_empty():
		game.combat.fight(e,enemy,dt,true)
		return true
	var hit := float(e.get("cellHitStarted",-100))
	if float(game.state.time)-hit < WarInfluenzaAnimation.hit_duration(): return true
	var slot := WarData.point(e.fluBuildSlot)
	# Each builder must occupy its reserved station, rather than stopping anywhere
	# on the near side of the fortress and sealing off later workers' routes.
	var within_reach := int(e.get("vesselLane",0)) == 0 and WarData.point(e).distance_to(slot) <= .18
	var destination := _builder_destination(e,site,slot)
	var arrived := game.go(e,destination,dt,.14,0) if not within_reach else true
	if within_reach or (arrived and destination.distance_to(slot) < .001):
		game.reset_path(e)
		e.weaponHeading = (WarData.point(site)-WarData.point(e)).angle()
		e.cellWorkTime = game.state.time
		e.fluWorkedAt = game.state.time
		e.combatState = "build"
	return true

func _builder_destination(e: Dictionary,site: Dictionary,slot: Vector2) -> Vector2:
	var center := WarData.point(site)
	var from := WarData.point(e)-center
	var wanted := (slot-center).angle()
	var gap := wrapf(wanted-from.angle(),-PI,PI)
	if absf(gap) < .07: return slot
	# Circulate outside the reserved stations before approaching radially. Going
	# straight to a far-side slot cuts through colleagues already drilling.
	var angle := from.angle()
	if from.length() >= APPROACH_RADIUS-.15:
		angle += clampf(gap,-.24,.24)
	var destination := center+Vector2.from_angle(angle)*APPROACH_RADIUS
	# Old saved construction sites were not checked for an outer access ring.
	# Keep their movement subject to real terrain/navigation rather than teleport.
	if not game.navigation.point_allowed(destination,0,"virus"): return slot
	return destination

func _yield_construction_access(e: Dictionary,dt: float) -> bool:
	var group: Dictionary = game.state.get("influenzaColonies",{}).get("groups",{}).get(e.fluColony,{})
	if group.is_empty(): return false
	var site := game.entity(int(e.get("fluYieldSite",0)))
	if site.is_empty() or site.hp <= 0 or site.get("complete",false):
		if e.has("fluYieldSite"):
			e.erase("fluYieldSite"); e.erase("fluYieldPoint"); game.reset_path(e)
		site = {}
		for candidate in forts(group):
			if not candidate.get("complete",false) and WarData.point(e).distance_to(WarData.point(candidate)) < APPROACH_RADIUS+1.5:
				site = candidate; break
	if site.is_empty(): return false
	var enemy := game.combat.enemy(e,float(WarData.spec("virus").vision),true)
	if not enemy.is_empty():
		game.combat.fight(e,enemy,dt,true)
		return true
	if not e.has("fluYieldPoint"):
		var center := WarData.point(site)
		var angle := (WarData.point(e)-center).angle()
		for i in 17:
			var offset := 0.0 if i == 0 else ceilf(float(i)/2)*(.22 if i%2 else -.22)
			var destination := center+Vector2.from_angle(angle+offset)*(APPROACH_RADIUS+2.0)
			if game.navigation.organ_at(destination,"virus") != group.organ or not game.navigation.clear_segment(WarData.point(e),destination,0,"virus"): continue
			if not _free(destination,WarData.radius("virus"),[int(e.id)]): continue
			e.fluYieldSite = site.id; e.fluYieldPoint = [destination.x,destination.y]
			game.reset_path(e)
			break
	if not e.has("fluYieldPoint"): return false
	# Unassigned colony members physically step outside the work/access circles,
	# then wait until completion. They are not counted among the ten builders.
	game.go(e,WarData.point(e.fluYieldPoint),dt,.14,0)
	return true

func _free(p: Vector2,radius: float,ignored: Array = []) -> bool:
	if not game.navigation.point_allowed(p,0,"virus"): return false
	for e in game.entities():
		if e.hp <= 0 or ignored.has(int(e.id)): continue
		if e.category == "building":
			var half := (6.6 if e.has("checkpointId") else float(WarData.spec(e.kind).get("size",1))*.5)+radius
			if Rect2(WarData.point(e)-Vector2.ONE*half,Vector2.ONE*half*2).has_point(p): return false
		elif int(e.get("vesselLane",0)) == 0 and p.distance_to(WarData.point(e)) < radius+WarData.radius(e.kind)+.08: return false
	return true

func _spawn_virus(group: Dictionary,origin: Vector2) -> Dictionary:
	if group.get("cleared",false): return {}
	if game.state.entities.size() >= 4096: return {}
	for i in 140:
		var p := origin+Vector2.from_angle(i*2.399963)*(.0 if i == 0 else 4.2+sqrt(float(i-1))*.38)
		# Keep all births in the authored organ/tissue plane, never a projected blood lane.
		if game.navigation.organ_at(p,"virus") != group.organ or not _free(p,WarData.radius("virus")): continue
		# Reserve the original small central footprint for the first fortress.
		if forts(group).is_empty() and Rect2(WarData.point(group.center)-Vector2.ONE*3,Vector2.ONE*6).has_point(p): continue
		var e := game.spawn("virus",2,p)
		if e.is_empty(): continue
		e.vesselLane = 0; e.fluColony = group.id
		e.spreadTargetGate = group.targetGate
		return e
	return {}

func _site_allowed(p: Vector2,group: Dictionary) -> bool:
	var half: float = data().rules.size*.5
	var corners := [p+Vector2(-half,-half),p+Vector2(half,-half),p+Vector2(half,half),p+Vector2(-half,half)]
	if game.navigation.organ_at(p,"virus") != group.organ: return false
	var grid := game.navigation.grid(group.organ,"siege")
	if grid.component(p) != grid.component(WarData.point(group.center)): return false
	for i in 4:
		if not game.navigation.clear_segment(corners[i],corners[(i+1)%4],0,"virus"): return false
	for fort in forts(group):
		if WarData.point(fort).distance_to(p) < float(data().rules.minimumSpacing): return false
	return _free(p,half+.3)

func _start_site(group: Dictionary,population: Array) -> void:
	if group.get("cleared",false): return
	var builders := population.filter(func(e): return not e.has("fluBuildSite") and int(e.get("vesselLane",0)) == 0 and game.navigation.organ_at(WarData.point(e),"virus") == group.organ)
	var needed: int = data().rules.builders
	if builders.size() < needed: return
	var candidates: Array = []
	for patch in zone(group.organ).placements: candidates.append(WarData.point(patch.center))
	for i in 80: candidates.append(WarData.point(group.center)+Vector2.from_angle(i*2.399963)*sqrt(float(i+1))*5)
	# Start at this infection's own reserved clearing before expanding locally.
	# Authored placement order is an index, not a construction priority: choosing
	# the organ's first patch can send all ten workers through a distant bottleneck.
	var origin := WarData.point(group.center)
	candidates.sort_custom(func(a,b): return a.distance_squared_to(origin) < b.distance_squared_to(origin))
	for p in candidates:
		if not _site_allowed(p,group): continue
		var accessible := true
		for i in 32:
			var a: Vector2 = p+Vector2.from_angle(i*TAU/32)*APPROACH_RADIUS
			var b: Vector2 = p+Vector2.from_angle((i+1)*TAU/32)*APPROACH_RADIUS
			if game.navigation.organ_at(a,"virus") != group.organ or not game.navigation.clear_segment(a,b,0,"virus"):
				accessible = false; break
		if not accessible: continue
		builders.sort_custom(func(a,b): return WarData.point(a).distance_squared_to(p) < WarData.point(b).distance_squared_to(p))
		var team := builders.slice(0,needed)
		# Own unassigned viruses can be crossing the future stations temporarily;
		# builders still wait for their actual collision clearance when approaching.
		var ignored: Array = population.map(func(e): return int(e.id))
		var slots: Array = []
		for i in needed:
			var slot: Vector2 = p+Vector2.from_angle(i*TAU/needed)*WORK_RADIUS
			if not _free(slot,WarData.radius("virus"),ignored): break
			slots.append(slot)
		if slots.size() != needed: continue
		# Preserve angular order around the site, avoiding crossing worker routes.
		team.sort_custom(func(a,b): return (WarData.point(a)-p).angle() < (WarData.point(b)-p).angle())
		slots.sort_custom(func(a,b): return (a-p).angle() < (b-p).angle())
		var offset := 0
		var best := INF
		for shift in needed:
			var distance := 0.0
			for i in needed: distance += WarData.point(team[i]).distance_squared_to(slots[(i+shift)%needed])
			if distance < best: best = distance; offset = shift
		var fort := game.spawn("flu_fortress",2,p,"building")
		if fort.is_empty(): continue
		fort.vesselLane = 0; fort.fluColony = group.id; fort.complete = false
		fort.progress = 0.0; fort.hp = float(fort.maxHp)*.15
		fort.builders = []; fort.buildSlots = []; fort.growthElapsed = 0.0
		for i in needed:
			var slot: Vector2 = slots[i]
			fort.buildSlots.append([slot.x,slot.y])
			_assign(team[(i-offset+needed)%needed],fort,slot)
		game.event("influenza_fortress_started",{"fortress":fort.id,"builders":fort.builders.duplicate(),"colony":group.id})
		return

func _assign(e: Dictionary,fort: Dictionary,slot: Vector2) -> void:
	e.erase("fluYieldSite"); e.erase("fluYieldPoint")
	e.fluBuildSite = fort.id; e.fluBuildSlot = [slot.x,slot.y]
	fort.builders.append(int(e.id)); game.reset_path(e)

func _repair_team(fort: Dictionary,population: Array) -> void:
	fort.builders = fort.builders.filter(func(id): return not game.entity(int(id)).is_empty() and game.entity(int(id)).hp > 0)
	var needed: int = data().rules.builders
	for e in population:
		if fort.builders.size() >= needed: break
		if e.has("fluBuildSite") or int(e.get("vesselLane",0)) != 0: continue
		var taken: Array = fort.builders.map(func(id): return game.entity(int(id)).get("fluBuildSlot",[]))
		for raw in fort.buildSlots:
			if not taken.has(raw): _assign(e,fort,WarData.point(raw)); break

func _release(fort: Dictionary) -> void:
	for id in fort.builders:
		var e := game.entity(int(id))
		if not e.is_empty():
			e.erase("fluBuildSite"); e.erase("fluBuildSlot"); game.reset_path(e)
	fort.builders = []

static func validate_state(snapshot: Dictionary) -> String:
	if not snapshot.has("influenzaColonies"): return ""
	var value: Variant = snapshot.influenzaColonies
	if not value is Dictionary or not value.get("groups") is Dictionary or value.get("version",0) != 1: return "流感群落存档无效"
	if not snapshot.get("entities") is Dictionary: return "流感单位存档无效"
	if value.groups.size() > 4096: return "流感群落数量无效"
	for key in value.groups:
		var group: Variant = value.groups[key]
		if not group is Dictionary or group.get("id","") != key: return "流感群落编号无效"
		if not group.get("center") is Array or group.center.size() != 2: return "流感感染位置无效"
		for n in group.center:
			if not WarSave._number(n): return "流感感染位置无效"
		if not WarData.read("infection_zones").zones.any(func(z): return z.organ == group.get("organ","")): return "流感感染器官无效"
		for field in ["pending","batches","produced"]:
			if not WarSave._number(group.get(field)) or group[field] < 0 or float(group[field]) != int(group[field]): return "流感数量无效"
		if group.pending > 4096 or not WarSave._number(group.get("nextBuildCheck")): return "流感刷怪队列无效"
		var purification_error := WarInfectionPurification.validate(group)
		if not purification_error.is_empty(): return purification_error
	for e in snapshot.entities.values():
		if not e.has("fluColony"): continue
		if not value.groups.has(e.fluColony) or not e.kind in ["virus","flu_fortress"]: return "流感群落归属无效"
		if e.kind != "flu_fortress": continue
		if not WarSave._number(e.get("growthElapsed")) or e.growthElapsed < 0 or e.growthElapsed > float(data().rules.spawnPeriod)+.0001: return "流感孵化进度无效"
		if not WarSave._number(e.get("progress")) or e.progress < 0 or e.progress > 1: return "流感施工进度无效"
		if not e.get("builders") is Array or e.builders.size() > int(data().rules.builders): return "流感施工队无效"
		for id in e.builders:
			if not WarSave._number(id) or int(id) != float(id) or id <= 0: return "流感施工队无效"
		if not e.get("buildSlots") is Array or e.buildSlots.size() != int(data().rules.builders): return "流感施工位置无效"
		for slot in e.buildSlots:
			if not slot is Array or slot.size() != 2 or not WarSave._number(slot[0]) or not WarSave._number(slot[1]): return "流感施工位置无效"
	return ""
