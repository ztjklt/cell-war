class_name WarResourceGeneration
extends RefCounted
## Same integer hash and per-chunk harvesting choices as the Lua sandbox.
var game: WarSimulation
var pending: Array = []
var enqueued: Dictionary = {}
var bases: Array[Vector2] = []

func _init(owner: WarSimulation) -> void:
	game = owner

static func hash_value(x: int,y: int,seed: int) -> float:
	var h := (x*374761393+y*668265263+seed*144269) & 0x7fffffff
	h = ((h ^ (h >> 13))*1274126177) & 0x7fffffff
	return float(h ^ (h >> 16))/2147483647.0

func reset() -> void:
	pending.clear()
	enqueued.clear()
	bases.clear()
	for e in game.entities():
		if e.kind == "core": bases.append(WarData.point(e)-Vector2.ONE*.5)

func update() -> void:
	if game.mode != "sandbox": return
	if not game.state.has("nativeGeneratedChunks"): game.state.nativeGeneratedChunks = {}
	for e in game.units():
		var p := WarData.point(e)
		for cy in range(maxi(0,int((p.y-21)/32)),mini(128,int((p.y+19)/32)+1)):
			for cx in range(maxi(0,int((p.x-21)/32)),mini(64,int((p.x+19)/32)+1)):
				var id := str(cy*64+cx+1)
				if game.state.nativeGeneratedChunks.has(id) or enqueued.has(id): continue
				enqueued[id] = true
				pending.append({"id":id,"cx":cx,"cy":cy,"row":0,"choices":{}})
	var deadline := Time.get_ticks_usec()+2000
	while not pending.is_empty() and Time.get_ticks_usec() < deadline:
		var job: Dictionary = pending[0]
		var y := int(job.cy)*32+1+int(job.row)
		for x in range(int(job.cx)*32+1,mini(2048,(int(job.cx)+1)*32)+1):
			var biome := game.survival.biome(Vector2(x,y))
			if biome.get("detail","") == "capillary": continue
			var total := 0.0
			var value := hash_value(x,y,int(game.state.seed)+19)
			for entry in biome.resources:
				total += float(entry[1])
				if value < total:
					var kind: String = entry[0]
					var score := hash_value(x,y,int(game.state.seed)+791)
					if not job.choices.has(kind) or score < float(job.choices[kind].score):
						job.choices[kind] = {"x":x,"y":y,"score":score}
					break
		job.row += 1
		if int(job.row) >= 32:
			for kind in job.choices:
				var p: Dictionary = job.choices[kind]
				var clear := true
				for base in bases:
					if absf(float(p.x)-base.x) <= 14 and absf(float(p.y)-base.y) <= 14: clear = false
				if clear: _place(kind,int(p.x),int(p.y),300 if kind == "wood" else 240)
			for base in bases:
				for fixed in [[6,-1,"wood"],[-8,2,"food"],[6,7,"oxygen"]]:
					var x := int(base.x)+int(fixed[0])
					var yy := int(base.y)+int(fixed[1])
					if x >= int(job.cx)*32+1 and x <= (int(job.cx)+1)*32 and yy >= int(job.cy)*32+1 and yy <= (int(job.cy)+1)*32:
						_place(fixed[2],x,yy,300)
			game.state.nativeGeneratedChunks[job.id] = true
			enqueued.erase(job.id)
			pending.pop_front()

func _place(kind: String,x: int,y: int,amount: float) -> void:
	var key := str((y-1)*4096+x)
	if game.state.resources.has(key): return
	var p := Vector2(x+.5,y+.5)
	var organ := game.navigation.organ_at(p)
	var detail: String = game.survival.biome(p).get("detail","")
	if detail == "flora": organ = "small_intestine"
	elif detail == "colon": organ = "large_intestine"
	elif detail == "stomach": organ = "stomach"
	if kind == "food" and organ in ["small_intestine","large_intestine"]: amount *= 2
	game.state.resources[key] = {"x":p.x,"y":p.y,"kind":kind,"amount":amount,"max":amount,
		"initialAmount":amount,"regen":0,"resourcePoint":true,"radius":2.2,"vesselLane":0,"organId":organ}
