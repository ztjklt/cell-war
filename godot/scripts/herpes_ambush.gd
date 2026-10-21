class_name WarHerpesAmbush
extends RefCounted
## Independent rules only. Binding all four world callbacks is required before advancing.
const EPS := .000001
const PHASES := ["active","burrowing","dormant","emerging","burst","hit","death"]
var _state := {"version":1,"clock":0.0,"nextCastId":0,"actors":{}}
var _geometry := Callable()
var _burrow_allowed := Callable()
var _damage := Callable()
var _push := Callable()
var _multiplier := Callable()
var _nearby := Callable()
var _events: Array = []
var _busy := false
var _event_time := 0.0

static func data() -> Dictionary: return WarData.read("herpes_ambush")

func bind_world(geometry: Callable,burrow_allowed: Callable,damage: Callable,push: Callable,
		multiplier := Callable(),nearby := Callable()) -> bool:
	if _busy: return false
	_geometry=geometry; _burrow_allowed=burrow_allowed; _damage=damage; _push=push
	_multiplier=multiplier; _nearby=nearby
	return ready()

func ready() -> bool:
	return _geometry.is_valid() and _burrow_allowed.is_valid() and _damage.is_valid() and _push.is_valid()

func clock() -> float: return float(_state.clock)
func advancing() -> bool: return _busy

static func is_actor(e: Dictionary) -> bool:
	return e.get("kind","")=="herpes" and e.get("category","")=="unit" and int(e.get("id",0))>0

func _ensure(e: Dictionary,at := -1.0) -> Dictionary:
	var key := str(int(e.id))
	if not _state.actors.has(key):
		if _state.actors.size()>=int(data().limits.actors): return {}
		var time := clock() if at<0 else at
		_state.actors[key]={"id":int(e.id),"phase":"active","progress":0.0,"stationary":0.0,"cooldown":0.0,
			"nextSenseAt":time,"castId":0,"committed":false,"hits":[],"x":float(e.x),"y":float(e.y),
			"lane":int(e.get("vesselLane",0)),"orderToken":int(e.get("orderToken",0)),"rate":1.0,
			"updatedAt":time,"deathAt":-1.0}
	return _state.actors[key]

func state_for(id: int) -> Dictionary: return _state.actors.get(str(id),{}).duplicate(true)

func _sync(e: Dictionary,s: Dictionary) -> void:
	e.burrowed = s.phase=="dormant"; e.concealed = s.phase=="dormant"
	if s.phase=="death": e.herpesDeathAt=float(s.deathAt)

func _emit(kind: String,s: Dictionary) -> void:
	_events.append({"kind":kind,"actor":int(s.id),"cast":int(s.castId),"time":_event_time})
	while _events.size()>int(data().limits.events): _events.pop_front()

func _phase(e: Dictionary,s: Dictionary,name: String) -> void:
	s.phase=name; s.progress=0.0; s.stationary=0.0
	if name=="dormant": s.nextSenseAt=_event_time
	_sync(e,s); _emit("herpes_"+name,s)

func _rate(e: Dictionary,field: String) -> float:
	if not _multiplier.is_valid(): return 1.0
	var raw: Variant=_multiplier.call(e,field)
	if not (raw is float or raw is int): return 0.0
	var value := float(raw)
	return clampf(value,0,32) if is_finite(value) else 0.0

func _legal(e: Dictionary) -> bool:
	if not ready() or int(e.get("vesselLane",0))!=int(data().ambush.tissueLane): return false
	var allowed: Variant=_burrow_allowed.call(WarData.point(e),int(e.get("vesselLane",0)),e)
	return allowed is bool and allowed

func _targets(e: Dictionary,all: Array,radius: float,purpose: String) -> Array:
	var result: Array=[]
	if not ready(): return result
	var candidates: Array=all
	if _nearby.is_valid():
		var nearby: Variant=_nearby.call(e,radius,all)
		# The complete host collection remains authoritative if an optional
		# spatial-index optimization is unavailable; geometry is still mandatory.
		if nearby is Array: candidates=nearby
	var seen: Dictionary={}
	for target in candidates:
		if not target is Dictionary or target.get("category","")!="unit" or float(target.get("hp",0))<=0: continue
		if int(target.get("id",0))<=0 or int(target.id)==int(e.id) or int(target.faction)==int(e.faction): continue
		if int(target.get("vesselLane",0))!=int(e.get("vesselLane",0)) or seen.has(str(int(target.id))): continue
		var delta := WarData.point(target)-WarData.point(e)
		if delta.length_squared()>radius*radius+EPS: continue
		var clear: Variant=_geometry.call(WarData.point(e),WarData.point(target),int(e.get("vesselLane",0)),e,target,purpose)
		if not clear is bool or not clear: continue
		seen[str(int(target.id))]=true
		result.append({"entity":target,"direction":delta.normalized() if delta.length_squared()>EPS else Vector2.RIGHT})
	result.sort_custom(func(a,b): return int(a.entity.id)<int(b.entity.id))
	if result.size()>int(data().limits.targets): result.resize(int(data().limits.targets))
	return result

func _begin_burst(e: Dictionary,s: Dictionary) -> bool:
	if not ready() or float(s.cooldown)>EPS or int(_state.nextCastId)>=1000000000: return false
	_state.nextCastId=int(_state.nextCastId)+1
	s.castId=int(_state.nextCastId); s.committed=false; s.hits=[]; s.cooldown=float(data().burst.cooldown)
	_phase(e,s,"burst")
	return true

func _commit(e: Dictionary,s: Dictionary,all: Array) -> void:
	if s.committed or s.phase!="burst" or float(e.get("hp",0))<=0: return
	# Determine the entire set against pre-impact geometry. An earlier callback
	# breaking a gate cannot admit a new victim behind that gate in this burst.
	var victims := _targets(e,all,float(data().burst.radius),"burst")
	s.committed=true; s.hits=[]
	for item in victims: s.hits.append(int(item.entity.id))
	_emit("herpes_burst_commit",s)
	for item in victims:
		var target: Dictionary=item.entity
		if float(target.hp)<=0 or int(target.faction)==int(e.faction): continue
		var before := float(target.hp)
		_damage.call(e,target,float(data().burst.damage),item.direction)
		if float(target.hp)<before:
			if is_actor(target):
				if float(target.hp)<=0: notify_death(target)
				else: notify_hit(target)
			if float(target.hp)>0: _push.call(e,target,item.direction,float(data().burst.knockback))

func notify_hit(e: Dictionary) -> void:
	if not is_actor(e): return
	if float(e.get("hp",0))<=0: notify_death(e); return
	var s := _ensure(e)
	if s.is_empty() or s.phase=="death": return
	var at := maxf(float(s.updatedAt),_event_time if _busy else clock())
	s.updatedAt=at; s.stationary=0.0
	if not _busy: _event_time=at
	if s.phase=="dormant": _phase(e,s,"emerging")
	elif s.phase not in ["emerging","hit"]: _phase(e,s,"hit")
	_sync(e,s)

func notify_death(e: Dictionary) -> void:
	if not is_actor(e) or float(e.get("hp",0))>0: return
	var s := _ensure(e)
	if s.is_empty() or s.phase=="death": return
	var at := maxf(float(s.updatedAt),_event_time if _busy else clock())
	s.updatedAt=at; s.deathAt=at
	if not _busy: _event_time=at
	_phase(e,s,"death")

func allows_movement(e: Dictionary) -> bool:
	return float(e.get("hp",0))>0 and _state.actors.get(str(int(e.get("id",0))),{}).get("phase","active")=="active"

func cancel_for_order(e: Dictionary) -> void:
	if not is_actor(e): return
	var s := _ensure(e)
	if s.is_empty(): return
	s.stationary=0.0; s.orderToken=int(e.get("orderToken",0))
	if s.phase in ["burrowing","burst"]:
		_event_time=clock(); _phase(e,s,"active")

func _elapse(s: Dictionary,seconds: float,rate: float) -> void:
	s.cooldown=maxf(0,float(s.cooldown)-seconds*rate)

func _advance_actor(e: Dictionary,s: Dictionary,all: Array) -> void:
	var cursor := float(s.updatedAt); var remaining := maxf(0,clock()-cursor)
	var rate := _rate(e,"attackSpeedMultiplier"); s.rate=rate
	var moved := WarData.point(e).distance_squared_to(Vector2(s.x,s.y))>EPS or int(e.get("vesselLane",0))!=int(s.lane)
	var moving := moved or float(e.get("travelSpeed",e.get("movementSpeed",0)))>.01
	var changed := int(e.get("orderToken",0))!=int(s.orderToken)
	_event_time=cursor
	if float(e.get("hp",0))<=0: notify_death(e)
	elif moved and s.phase in ["dormant","burrowing"]:
		_phase(e,s,"emerging" if s.phase=="dormant" else "active")
	elif changed and s.phase in ["burst","burrowing"]: _phase(e,s,"active")
	if moving or changed: s.stationary=0.0
	for _iteration in 10000:
		_event_time=cursor
		if s.phase=="death":
			s.progress=minf(float(data().clips.haDeath.duration),clock()-float(s.deathAt)); break
		if s.phase=="active":
			var close := _targets(e,all,float(data().burst.radius),"burst")
			if not close.is_empty() and float(s.cooldown)<=EPS and _begin_burst(e,s): continue
			var quiet := not moving and not changed and _legal(e) and _targets(e,all,float(data().ambush.senseRadius),"sense").is_empty()
			if not quiet: s.stationary=0.0
			if quiet and float(s.stationary)+EPS>=float(data().ambush.stationarySeconds): _phase(e,s,"burrowing"); continue
			if remaining<=EPS: break
			var used := remaining
			if quiet: used=minf(used,maxf(0,float(data().ambush.stationarySeconds)-float(s.stationary)))
			if not close.is_empty() and rate>EPS and float(s.cooldown)>EPS: used=minf(used,float(s.cooldown)/rate)
			_elapse(s,used,rate)
			if quiet: s.stationary=minf(float(data().ambush.stationarySeconds),float(s.stationary)+used)
			cursor+=used; remaining=maxf(0,remaining-used)
		elif s.phase=="dormant":
			if not _legal(e): _phase(e,s,"emerging"); continue
			if cursor+EPS>=float(s.nextSenseAt):
				s.nextSenseAt=cursor+float(data().ambush.senseInterval)
				if not _targets(e,all,float(data().ambush.senseRadius),"sense").is_empty(): _phase(e,s,"emerging"); continue
			if remaining<=EPS: break
			var used := minf(remaining,maxf(EPS,float(s.nextSenseAt)-cursor))
			_elapse(s,used,rate); cursor+=used; remaining=maxf(0,remaining-used)
		elif s.phase=="burst":
			if not s.committed and float(s.progress)+EPS>=float(data().burst.commitAt): _commit(e,s,all); continue
			if float(s.progress)+EPS>=float(data().burst.duration): _phase(e,s,"active"); continue
			if remaining<=EPS or rate<=EPS: break
			var boundary: float=data().burst.duration if s.committed else data().burst.commitAt
			var used := minf(remaining,maxf(0,boundary-float(s.progress))/rate)
			_elapse(s,used,rate); s.progress=float(s.progress)+used*rate; cursor+=used; remaining=maxf(0,remaining-used)
		else:
			var duration: float=data().clips.haHit.duration if s.phase=="hit" else (data().ambush.burrowSeconds if s.phase=="burrowing" else data().ambush.emergeSeconds)
			if s.phase=="burrowing" and not _legal(e): _phase(e,s,"active"); continue
			if float(s.progress)+EPS>=duration:
				if s.phase=="burrowing": _phase(e,s,"dormant")
				elif s.phase=="emerging" and not _targets(e,all,float(data().burst.radius),"burst").is_empty() and _begin_burst(e,s): pass
				else: _phase(e,s,"active")
				continue
			if remaining<=EPS: break
			var used := minf(remaining,maxf(0,duration-float(s.progress)))
			_elapse(s,used,rate); s.progress=float(s.progress)+used; cursor+=used; remaining=maxf(0,remaining-used)
	s.x=float(e.x); s.y=float(e.y); s.lane=int(e.get("vesselLane",0)); s.orderToken=int(e.get("orderToken",0)); s.updatedAt=clock()
	_sync(e,s)

func advance_simulation(dt: float,all_entities: Array) -> bool:
	if _busy or not ready() or not is_finite(dt) or dt<0 or dt>float(data().limits.maxStep): return false
	_busy=true
	var previous := clock(); _state.clock=previous+dt
	var actors: Array=all_entities.filter(func(e): return e is Dictionary and is_actor(e))
	actors.sort_custom(func(a,b): return int(a.id)<int(b.id))
	var seen: Dictionary={}
	for e in actors:
		var s := _ensure(e,previous)
		if s.is_empty(): continue
		seen[str(int(e.id))]=true; _advance_actor(e,s,all_entities)
	for key in _state.actors.keys():
		if seen.has(key): continue
		var s: Dictionary=_state.actors[key]
		if s.phase=="death" and clock()-float(s.deathAt)<=float(data().clips.haDeath.duration)+.1:
			s.progress=minf(float(data().clips.haDeath.duration),clock()-float(s.deathAt)); s.updatedAt=clock()
		else: _state.actors.erase(key)
	_event_time=clock(); _busy=false
	return true

func advance(real_dt: float,entities: Array,paused: bool,time_scale := 1.0) -> bool:
	if not is_finite(time_scale) or time_scale<0: return false
	return true if paused else advance_simulation(real_dt*time_scale,entities)

func drain_events() -> Array:
	var result := _events.duplicate(true); _events.clear(); return result

func snapshot() -> Dictionary: return _state.duplicate(true)

func restore(value: Variant,entities: Array=[]) -> String:
	if _busy: return "不能在爆发事务中替换疱疹状态"
	var error := validate_snapshot(value)
	if not error.is_empty(): return error
	var by_id: Dictionary={}
	for e in entities:
		if e is Dictionary: by_id[str(int(e.get("id",0)))]=e
	for key in value.actors:
		if by_id.has(key) and not is_actor(by_id[key]): return "疱疹状态对应错误单位"
	_state=value.duplicate(true); _events.clear(); _event_time=clock()
	for key in _state.actors:
		if by_id.has(key): _sync(by_id[key],_state.actors[key])
	return ""

static func _number(value: Variant,low: float,high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=low and float(value)<=high

static func _integer(value: Variant,low := 0,high := 1000000000) -> bool:
	return _number(value,low,high) and float(value)==float(int(value))

static func _json_safe(value: Variant,depth := 0) -> bool:
	if depth>8: return false
	if value==null or value is bool or value is String or value is int: return true
	if value is float: return is_finite(value)
	if value is Array:
		if value.size()>1024: return false
		for child in value:
			if not _json_safe(child,depth+1): return false
		return true
	if value is Dictionary:
		if value.size()>1024: return false
		for key in value:
			if not key is String or not _json_safe(value[key],depth+1): return false
		return true
	return false

static func validate_snapshot(value: Variant) -> String:
	if not _json_safe(value) or not value is Dictionary or value.get("version",0)!=1: return "疱疹状态版本或JSON值无效"
	if not _number(value.get("clock"),0,1000000000) or not _integer(value.get("nextCastId")): return "疱疹时钟或爆发编号无效"
	if not value.get("actors") is Dictionary or value.actors.size()>int(data().limits.actors): return "疱疹状态数量无效"
	var casts: Dictionary={}
	for key in value.actors:
		if not key.is_valid_int() or str(int(key))!=key or int(key)<=0: return "疱疹单位键无效"
		var s: Variant=value.actors[key]
		if not s is Dictionary or not _integer(s.get("id"),1) or int(s.id)!=int(key) or not s.get("phase","") in PHASES: return "疱疹阶段无效"
		for field in ["progress","stationary","cooldown","nextSenseAt","updatedAt"]:
			if not _number(s.get(field),0,1000000000): return "疱疹阶段数值无效"
		if float(s.updatedAt)>float(value.clock)+EPS or float(s.nextSenseAt)>float(value.clock)+float(data().ambush.senseInterval)+EPS: return "疱疹阶段时刻超前"
		if absf(float(s.updatedAt)-float(value.clock))>EPS: return "疱疹快照不是完整模拟步边界"
		if not _number(s.get("x"),-1000000,1000000) or not _number(s.get("y"),-1000000,1000000) or not _integer(s.get("lane"),0,4096) or not _integer(s.get("orderToken")): return "疱疹位置或命令无效"
		if not _number(s.get("rate"),0,32) or not _number(s.get("deathAt"),-1,float(value.clock)): return "疱疹倍率或死亡时刻无效"
		if float(s.cooldown)>float(data().burst.cooldown)+EPS or float(s.stationary)>float(data().ambush.stationarySeconds)+EPS: return "疱疹冷却或静止准备越界"
		var duration := 0.0
		if s.phase=="burst": duration=float(data().burst.duration)
		elif s.phase=="hit": duration=float(data().clips.haHit.duration)
		elif s.phase=="burrowing": duration=float(data().ambush.burrowSeconds)
		elif s.phase=="emerging": duration=float(data().ambush.emergeSeconds)
		elif s.phase=="death": duration=float(data().clips.haDeath.duration)
		if float(s.progress)>duration+EPS: return "疱疹动作进度越界"
		if s.phase in ["burrowing","dormant"] and int(s.lane)!=int(data().ambush.tissueLane): return "疱疹只能在合法组织层埋伏"
		if (s.phase=="death" and float(s.deathAt)<0) or (s.phase!="death" and float(s.deathAt)!=-1): return "疱疹死亡阶段冲突"
		if s.phase=="death" and absf(float(s.progress)-minf(float(data().clips.haDeath.duration),float(value.clock)-float(s.deathAt)))>EPS: return "疱疹死亡进度与时钟冲突"
		if not _integer(s.get("castId"),0,int(value.nextCastId)) or not s.get("committed") is bool or not s.get("hits") is Array or s.hits.size()>int(data().limits.targets): return "疱疹爆发账本无效"
		if int(s.castId)>0:
			if casts.has(str(int(s.castId))): return "疱疹爆发编号重复"
			casts[str(int(s.castId))]=true
		elif s.committed or not s.hits.is_empty(): return "疱疹未起手却已提交"
		if s.phase=="burst" and (int(s.castId)==0 or bool(s.committed)!=(float(s.progress)+EPS>=float(data().burst.commitAt))): return "疱疹提交位与帧进度冲突"
		if not s.committed and not s.hits.is_empty(): return "疱疹未提交已有命中"
		var hit_ids: Dictionary={}
		for id in s.hits:
			if not _integer(id,1) or int(id)==int(s.id) or hit_ids.has(str(int(id))): return "疱疹命中集合无效"
			hit_ids[str(int(id))]=true
	return ""
