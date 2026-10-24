class_name WarVaccineAntibodies
extends RefCounted
## Independent candidate. No entity spawning, shop, shared simulation or save hooks.
## Host callbacks must prove geometry/classification and settle synchronous damage.
const SCHEMA := "cell-war-vaccine-antibodies/v1"
const MEDICINE := "vaccine"
const ACTIVE_CAUSES := ["attack", "projectile", "collision"]
const MAX_ID := 2147483647
const EPS := .000001
var _rules: Dictionary = {}
var _world_id := ""
var _clock := 0.0
var _next_id := 1
var _last_hit_id := 0
var _last_step_id := 0
var _drops: Array = []
var _sources: Dictionary = {}
var _positions: Dictionary = {}
var _events: Array = []
var _damage := Callable()
var _ground := Callable()
var _segment := Callable()
var _is_virus := Callable()
var _busy := false
var _error := ""


static func data() -> Dictionary:
	return WarData.read("vaccine_antibodies")


func _init(overrides: Dictionary = {}) -> void:
	var rules: Dictionary = data().rules.duplicate(true)
	# Operational bound, independent of medicine balance.
	rules.maxContactsPerStep = 16384
	for key in overrides:
		if not rules.has(key): _error="unknown_tuning"; return
		rules[key]=overrides[key]
	if not _valid_rules(rules): _error="invalid_tuning"; return
	_rules=_normalize_rules(rules)


## damage(owner,target,amount,cause,contact_id); ground(point,lane,owner,radius);
## segment(from,to,lane,actor); is_virus(actor). All three predicates require bool.
func bind_world(damage: Callable, ground: Callable, segment: Callable, is_virus: Callable) -> bool:
	if _busy: _error="busy"; return false
	_damage=damage; _ground=ground; _segment=segment; _is_virus=is_virus
	return true


func begin(world_id: String, simulation_clock := 0.0, initial_actors: Array = []) -> bool:
	if _busy or not ready() or not _valid_world_id(world_id) or not _number(simulation_clock) or simulation_clock<0:
		_error="invalid_begin"; return false
	var positions: Dictionary={}
	if initial_actors.size()>int(_rules.maxTrackedActors): _error="actor_capacity"; return false
	for actor in initial_actors:
		if not actor is Dictionary or not _actor(actor) or positions.has(str(int(actor.id))): _error="invalid_initial_actors"; return false
		var p:=Vector2(actor.x,actor.y)
		positions[str(int(actor.id))]={"x":p.x,"y":p.y,"vesselLane":int(actor.vesselLane)}
	_world_id=world_id; _clock=float(simulation_clock)
	_next_id=1; _last_hit_id=0; _last_step_id=0
	_drops.clear(); _sources.clear(); _positions=positions; _events.clear(); _error=""
	return true


func ready() -> bool: return not _rules.is_empty()
func last_error() -> String: return _error
func clock() -> float: return _clock
func antibodies() -> Array: return _drops.duplicate(true)
func tuning() -> Dictionary:
	return {"status":"first_pass_adjustable","releaseEnabled":false,"values":_rules.duplicate(true),"helperProposal":data().helperProposal.duplicate(true)}


func _bound() -> bool:
	return _damage.is_valid() and _ground.is_valid() and _segment.is_valid() and _is_virus.is_valid()


## Only host post-damage events. hitId is a globally monotonic combat-damage serial
## within worldId, assigned once at the real hit, persisted by the future adapter.
## Eligible notifications settle their serial even when cooldown/capacity/ground fails.
func notify_hit(event: Dictionary) -> int:
	_error=""
	if _busy: _error="busy"; return 0
	if not ready() or _world_id.is_empty() or not _bound(): _error="bindings_or_world_required"; return 0
	if event.get("worldId","")!=_world_id or not _integer(event.get("hitId"),1): _error="invalid_hit_identity"; return 0
	if int(event.hitId)<=_last_hit_id: _error="duplicate_or_old_hit"; return 0
	if not event.get("source") is Dictionary or not event.get("target") is Dictionary: _error="invalid_hit_actors"; return 0
	var source: Dictionary=event.source; var target: Dictionary=event.target
	if not _actor(source) or not _actor(target) or target.kind!=MEDICINE or target.category!="unit" or source.category!="unit": _error="invalid_hit_actors"; return 0
	if int(source.id)==int(target.id) or int(source.faction)==int(target.faction) or int(source.faction)<=0 or int(target.faction)<=0: _error="not_enemy_attack"; return 0
	if event.get("cause","") not in ACTIVE_CAUSES: _error="not_active_attack"; return 0
	if not _number(event.get("damage")) or float(event.damage)<=0 or not _number(event.get("hpBefore")) or float(event.hpBefore)<=0:
		_error="not_positive_damage"; return 0
	if float(event.damage)>float(event.hpBefore)+EPS or absf(maxf(0,float(event.hpBefore)-float(event.damage))-float(target.hp))>.0001:
		_error="not_post_damage_event"; return 0
	_last_hit_id=int(event.hitId)
	_busy=true
	_prune_sources()
	var key:=str(int(target.id))
	var previous: Dictionary=_sources.get(key,{"readyAt":0.0})
	if _clock+EPS<float(previous.readyAt): return _drop_failure("cooldown")
	if _drops.size()>=int(_rules.maxAntibodies) or _count_for(int(target.id))>=int(_rules.maxPerHelper) or _next_id>=MAX_ID:
		return _drop_failure("antibody_capacity")
	if not _sources.has(key) and _sources.size()>=int(_rules.maxSourceRecords): return _drop_failure("source_capacity")
	var point:=_placement(target)
	if not point.is_finite(): return _drop_failure("no_legal_ground")
	var owner:=_owner(target)
	var drop: Dictionary={"id":_next_id,"owner":owner,"x":point.x,"y":point.y,"vesselLane":int(target.vesselLane),"born":_clock,"expiresAt":_clock+float(_rules.antibodyLifetimeSeconds)}
	_drops.append(drop); _next_id+=1
	_sources[key]={"readyAt":_clock+float(_rules.dropCooldownSeconds),"lastDropAt":_clock}
	_record("antibody_drop",{"antibody":drop.duplicate(true),"hitId":int(event.hitId)},_clock)
	_busy=false; _error=""
	return int(drop.id)


func _drop_failure(reason: String) -> int:
	_busy=false; _error=reason; return 0


func _placement(target: Dictionary) -> Vector2:
	var origin:=Vector2(target.x,target.y)
	var lane:=int(target.vesselLane)
	var candidates: Array[Vector2]=[origin]
	var rings:=int(floorf(float(_rules.searchRadius)/float(_rules.searchStep)+EPS))
	for ring in range(1,rings+1):
		for index in int(_rules.searchDirections):
			candidates.append(origin+Vector2.from_angle(TAU*index/float(_rules.searchDirections))*float(ring)*float(_rules.searchStep))
	for point in candidates:
		if _predicate(_ground.call(point,lane,_owner(target),float(_rules.contactRadius))) and _predicate(_segment.call(origin,point,lane,target.duplicate(true))): return point
	return Vector2.INF


## Use this wall-time adapter OR advance_simulation, never both. step_id is the
## host tick serial, not the number of times this method has been called.
func advance(real_delta: float, entities: Array, step_id: int, paused := false, time_scale := 1.0, motion: Dictionary = {}) -> bool:
	if not _number(real_delta) or real_delta<0 or not _number(time_scale) or time_scale<0:
		_error="invalid_delta"; return false
	if paused or is_zero_approx(time_scale): return true
	return advance_simulation(real_delta*time_scale,entities,step_id,motion)


## motion[id] may supply verified piecewise paths. Each segment is
## {from:Vector2,to:Vector2,lane:int,start:0..1,end:0..1}; contiguous in time/space.
## Otherwise same-lane positions are swept linearly from the last committed tick.
## Layer changes without an explicit path test only the final position at tick end.
func advance_simulation(delta: float, entities: Array, step_id: int, motion: Dictionary = {}) -> bool:
	_error=""
	if _busy: _error="busy"; return false
	if not ready() or _world_id.is_empty() or not _bound(): _error="bindings_or_world_required"; return false
	if not _number(delta) or delta<0 or not is_finite(_clock+delta): _error="invalid_delta"; return false
	if not _integer(step_id,1) or step_id<=_last_step_id: _error="duplicate_or_old_step"; return false
	if entities.size()>int(_rules.maxTrackedActors): _error="actor_capacity"; return false
	var world: Dictionary={}
	for actor in entities:
		if not actor is Dictionary or not _actor(actor): _error="invalid_actor"; return false
		var key:=str(int(actor.id))
		if world.has(key): _error="duplicate_actor"; return false
		world[key]=actor
	var paths:=_paths(world,motion)
	if not paths.ok: _error="invalid_motion"; return false
	if delta==0:
		for path in paths.paths.values():
			for segment in path:
				if segment.from.distance_to(segment.to)>EPS: _error="movement_without_time"; return false
	_busy=true
	var start:=_clock; var end:=_clock+delta
	var contacts: Array=[]
	for drop in _drops:
		for actor in world.values():
			if not _eligible(drop,actor): continue
			var at:=_contact_time(drop,actor,paths.paths[str(int(actor.id))],start,delta)
			if at<0: continue
			contacts.append({"drop":int(drop.id),"target":int(actor.id),"at":at})
			if contacts.size()>int(_rules.maxContactsPerStep): _busy=false; _error="contact_capacity"; return false
	contacts.sort_custom(func(a,b):
		if float(a.at)!=float(b.at): return a.at<b.at
		return a.drop<b.drop if a.drop!=b.drop else a.target<b.target)
	# Commit the step and end positions before dispatch. Reentrant save/advance is
	# rejected; host saves at an end-of-step boundary with the matching world HP.
	_clock=end; _last_step_id=step_id; _positions={}
	for key in world:
		var actor: Dictionary=world[key]
		var point:=Vector2(actor.x,actor.y)
		_positions[key]={"x":point.x,"y":point.y,"vesselLane":int(actor.vesselLane)}
	for contact in contacts:
		var index:=_index(int(contact.drop))
		if index<0: continue
		var drop: Dictionary=_drops[index]; var target: Dictionary=world[str(int(contact.target))]
		if not _eligible(drop,target): continue # Another antibody may already have killed it.
		_drops.remove_at(index) # Consume once BEFORE the synchronous damage callback.
		var before:=float(target.hp)
		var contact_id:=_world_id+":antibody:"+str(int(drop.id))
		_damage.call(drop.owner.duplicate(true),target,float(_rules.damage),"vaccine_antibody",contact_id)
		_record("antibody_contact",{"antibody":int(drop.id),"target":int(target.id),"contactId":contact_id,"requestedDamage":float(_rules.damage),"damage":maxf(0,before-float(target.hp)),"x":drop.x,"y":drop.y,"vesselLane":drop.vesselLane},float(contact.at))
	for index in range(_drops.size()-1,-1,-1):
		if float(_drops[index].expiresAt)<=_clock+EPS:
			_record("antibody_expired",{"antibody":int(_drops[index].id)},float(_drops[index].expiresAt)); _drops.remove_at(index)
	_prune_sources(); _busy=false; _error=""
	return true


func _paths(world: Dictionary,motion: Dictionary) -> Dictionary:
	for key in motion:
		if not key is String or not world.has(key): return {"ok":false}
	var result: Dictionary={}
	for key in world:
		var actor: Dictionary=world[key]; var point:=Vector2(actor.x,actor.y); var lane:=int(actor.vesselLane)
		var previous: Dictionary=_positions.get(key,{"x":point.x,"y":point.y,"vesselLane":lane})
		var origin:=Vector2(previous.x,previous.y)
		if not motion.has(key):
			var known_same_lane: bool=_positions.has(key) and int(previous.vesselLane)==lane
			result[key]=[{"from":origin if known_same_lane else point,"to":point,"lane":lane,"start":0.0 if known_same_lane else 1.0,"end":1.0}]
			continue
		var supplied: Variant=motion[key]
		if not supplied is Array or supplied.is_empty() or supplied.size()>int(_rules.maxSegmentsPerActor): return {"ok":false}
		var segments: Array=[]; var last_point:=origin; var last_fraction:=0.0
		for segment in supplied:
			if not segment is Dictionary or not _integer(segment.get("lane"),0): return {"ok":false}
			var a:=_point(segment.get("from")); var b:=_point(segment.get("to"))
			if not a.is_finite() or not b.is_finite() or not _number(segment.get("start")) or not _number(segment.get("end")): return {"ok":false}
			var lo:=float(segment.start); var hi:=float(segment.end)
			if segments.is_empty() and not _positions.has(key): last_fraction=lo # Newly observed spawn may appear partway through the tick.
			if lo<0 or hi>1 or hi<lo or absf(lo-last_fraction)>EPS or (not segments.is_empty() or _positions.has(key)) and a.distance_to(last_point)>.001: return {"ok":false}
			if segments.is_empty() and _positions.has(key) and int(segment.lane)!=int(previous.vesselLane): return {"ok":false}
			if hi==lo and a.distance_to(b)>.001: return {"ok":false}
			segments.append({"from":a,"to":b,"lane":int(segment.lane),"start":lo,"end":hi}); last_point=b; last_fraction=hi
		if absf(last_fraction-1)>EPS or last_point.distance_to(point)>.001 or int(segments[-1].lane)!=lane: return {"ok":false}
		result[key]=segments
	return {"ok":true,"paths":result}


func _eligible(drop: Dictionary,actor: Dictionary) -> bool:
	return float(actor.hp)>0 and actor.category=="unit" and int(actor.id)!=int(drop.owner.id) and int(actor.faction)>0 and int(actor.faction)!=int(drop.owner.faction) and _predicate(_is_virus.call(actor.duplicate(true)))


func _contact_time(drop: Dictionary,actor: Dictionary,segments: Array,start: float,delta: float) -> float:
	var center:=Vector2(drop.x,drop.y); var lane:=int(drop.vesselLane)
	if not _predicate(_ground.call(center,lane,drop.owner.duplicate(true),float(_rules.contactRadius))): return -1
	var limit:=clampf((float(drop.expiresAt)-start)/delta,0,1) if delta>0 else 1.0
	for segment in segments:
		if float(segment.start)>limit: break
		var hi:=minf(float(segment.end),limit)
		var ratio: float=(hi-float(segment.start))/(float(segment.end)-float(segment.start)) if segment.end>segment.start else 0.0
		var a: Vector2=segment.from; var b: Vector2=a.lerp(segment.to,ratio)
		if int(segment.lane)==lane:
			var fraction:=_circle_contact(a,b,center,float(_rules.contactRadius))
			if fraction>=0:
				var at:=start+delta*lerpf(float(segment.start),hi,fraction)
				var point:=a.lerp(b,fraction)
				if at<float(drop.expiresAt)-EPS and _predicate(_segment.call(a,point,lane,actor.duplicate(true))) and _predicate(_segment.call(center,point,lane,actor.duplicate(true))): return at
		# A path cannot emerge from behind a rejected earlier wall segment.
		if not _predicate(_segment.call(a,b,int(segment.lane),actor.duplicate(true))): return -1
	return -1


func _count_for(owner_id: int) -> int:
	return _drops.filter(func(drop): return int(drop.owner.id)==owner_id).size()


func _index(id: int) -> int:
	for index in _drops.size():
		if int(_drops[index].id)==id: return index
	return -1


func _prune_sources() -> void:
	var visual_time: float=data().clips.hit.duration+data().clips.release.duration
	for key in _sources.keys():
		if _count_for(int(key))==0 and _clock>=maxf(float(_sources[key].readyAt),float(_sources[key].lastDropAt)+visual_time): _sources.erase(key)


func _record(kind: String,fields: Dictionary,at: float) -> void:
	var event:=fields.duplicate(true); event.kind=kind; event.time=at; _events.append(event)
	while _events.size()>int(_rules.maxEvents): _events.pop_front()


func drain_events() -> Array:
	if _busy: return []
	var result:=_events.duplicate(true); _events.clear(); return result


func sample_actor(actor: Dictionary,time: float,moving: float,dead: bool) -> Dictionary:
	var clips: Dictionary=data().clips
	var key: String="move"; var elapsed:=0.0; var loop:=true
	var hit_at:=float(actor.get("hitTime",-100.0))
	var last_drop:=float(_sources.get(str(int(actor.id)),{}).get("lastDropAt",-100.0))
	var release_at:=last_drop+float(clips.hit.duration)
	if dead:
		key="death"; elapsed=maxf(0,time-float(actor.get("died",time))); loop=false
		if elapsed>=float(clips.death.duration): return {"hidden":true}
	elif time>=hit_at and time<hit_at+float(clips.hit.duration): key="hit"; elapsed=time-hit_at; loop=false
	elif time>=release_at and time<release_at+float(clips.release.duration): key="release"; elapsed=time-release_at; loop=false
	elif moving>.02: elapsed=time+int(actor.id)*.071
	return {"key":key,"clip":clips[key],"frame":frame(clips[key],elapsed,loop),"family":MEDICINE,"containsIllustratedDrops":key=="release"}


static func frame(clip: Dictionary,elapsed: float,loop: bool) -> int:
	var remaining:=fposmod(elapsed,float(clip.duration)) if loop else maxf(0,elapsed)
	for index in clip.durations.size():
		if remaining<float(clip.durations[index]): return index
		remaining-=float(clip.durations[index])
	return clip.durations.size()-1


func sample_antibody(id: int) -> Dictionary:
	var index:=_index(id)
	if index<0: return {"hidden":true}
	var drop: Dictionary=_drops[index]
	return {"id":id,"x":drop.x,"y":drop.y,"vesselLane":drop.vesselLane,"age":_clock-float(drop.born),"remaining":maxf(0,float(drop.expiresAt)-_clock),"visual":data().antibodyVisual.duplicate(true)}


func snapshot() -> Dictionary:
	if _busy or _world_id.is_empty(): return {} # Never export a half-applied damage transaction.
	return {"schema":SCHEMA,"medicineId":MEDICINE,"worldId":_world_id,"clock":_clock,"nextAntibodyId":_next_id,"lastHitId":_last_hit_id,"lastStepId":_last_step_id,"rules":_rules.duplicate(true),"antibodies":_drops.duplicate(true),"sources":_sources.duplicate(true),"positions":_positions.duplicate(true)}


func restore(value: Dictionary) -> bool:
	if _busy: _error="busy"; return false
	var result:=_validate_snapshot(value)
	if result.is_empty(): _error="invalid_snapshot"; return false
	_world_id=result.worldId; _clock=float(result.clock); _next_id=int(result.nextAntibodyId)
	_last_hit_id=int(result.lastHitId); _last_step_id=int(result.lastStepId); _rules=result.rules
	_drops=result.antibodies; _sources=result.sources; _positions=result.positions; _events.clear(); _error=""
	return true


static func validate_snapshot(value: Dictionary) -> String:
	return "" if not _validate_snapshot(value).is_empty() else "invalid_vaccine_antibody_snapshot"


static func _validate_snapshot(value: Dictionary) -> Dictionary:
	if value.get("schema")!=SCHEMA or value.get("medicineId")!=MEDICINE or not _valid_world_id(value.get("worldId")): return {}
	if not _number(value.get("clock")) or float(value.clock)<0 or not _integer(value.get("nextAntibodyId"),1): return {}
	if not _integer(value.get("lastHitId"),0) or not _integer(value.get("lastStepId"),0): return {}
	if not value.get("rules") is Dictionary or not _valid_rules(value.rules): return {}
	if not value.get("antibodies") is Array or value.antibodies.size()>int(value.rules.maxAntibodies): return {}
	if not value.get("sources") is Dictionary or value.sources.size()>int(value.rules.maxSourceRecords): return {}
	if not value.get("positions") is Dictionary or value.positions.size()>int(value.rules.maxTrackedActors): return {}
	var result:=value.duplicate(true); result.rules=_normalize_rules(result.rules)
	var ids: Dictionary={}; var counts: Dictionary={}
	for drop in result.antibodies:
		if not drop is Dictionary or not _integer(drop.get("id"),1) or int(drop.id)>=int(result.nextAntibodyId) or ids.has(int(drop.id)): return {}
		ids[int(drop.id)]=true
		if not drop.get("owner") is Dictionary or not _actor(drop.owner) or drop.owner.kind!=MEDICINE or drop.owner.category!="unit" or int(drop.owner.faction)<=0: return {}
		if not _integer(drop.get("vesselLane"),0) or int(drop.vesselLane)!=int(drop.owner.vesselLane) or not _point([drop.get("x"),drop.get("y")]).is_finite(): return {}
		if not _number(drop.get("born")) or not _number(drop.get("expiresAt")) or float(drop.born)<0 or float(drop.born)>float(result.clock)+EPS: return {}
		if float(drop.expiresAt)<=float(result.clock)+EPS or absf(float(drop.expiresAt)-float(drop.born)-float(result.rules.antibodyLifetimeSeconds))>EPS: return {}
		var key:=str(int(drop.owner.id)); counts[key]=int(counts.get(key,0))+1
		if counts[key]>int(result.rules.maxPerHelper) or not result.sources.has(key): return {}
		drop.id=int(drop.id); drop.vesselLane=int(drop.vesselLane); _normalize_actor(drop.owner)
		var p:=Vector2(drop.x,drop.y); drop.x=p.x; drop.y=p.y
	for key in result.sources:
		if not _key(key) or not result.sources[key] is Dictionary: return {}
		var source: Dictionary=result.sources[key]
		if not _number(source.get("readyAt")) or not _number(source.get("lastDropAt")) or float(source.lastDropAt)<0 or float(source.lastDropAt)>float(result.clock)+EPS: return {}
		if absf(float(source.readyAt)-float(source.lastDropAt)-float(result.rules.dropCooldownSeconds))>EPS: return {}
	for key in result.positions:
		if not _key(key) or not result.positions[key] is Dictionary: return {}
		var p: Dictionary=result.positions[key]
		if not _integer(p.get("vesselLane"),0) or not _point([p.get("x"),p.get("y")]).is_finite(): return {}
		var point:=Vector2(p.x,p.y); p.x=point.x; p.y=point.y; p.vesselLane=int(p.vesselLane)
	return result


static func _valid_rules(rules: Dictionary) -> bool:
	var expected: Array=data().rules.keys()+["maxContactsPerStep"]
	if rules.size()!=expected.size(): return false
	for key in rules:
		if not key in expected or not _number(rules[key]): return false
	for key in ["antibodyLifetimeSeconds","contactRadius","damage","searchStep"]:
		if float(rules[key])<=0 or float(rules[key])>10000: return false
	for key in ["dropCooldownSeconds","searchRadius"]:
		if float(rules[key])<0 or float(rules[key])>10000: return false
	if rules.searchRadius/rules.searchStep>16: return false
	var bounds: Dictionary={"searchDirections":32,"maxPerHelper":12,"maxAntibodies":128,"maxSourceRecords":4096,"maxTrackedActors":16384,"maxSegmentsPerActor":256,"maxEvents":4096,"maxContactsPerStep":65536}
	for key in bounds:
		if not _integer(rules[key],1) or int(rules[key])>int(bounds[key]): return false
	return true


static func _normalize_rules(rules: Dictionary) -> Dictionary:
	var result:=rules.duplicate(true)
	for key in result: result[key]=int(result[key]) if key.begins_with("max") or key=="searchDirections" else float(result[key])
	return result


static func _owner(actor: Dictionary) -> Dictionary:
	var p:=Vector2(actor.x,actor.y)
	return {"id":int(actor.id),"kind":str(actor.kind),"category":str(actor.category),"faction":int(actor.faction),"hp":float(actor.hp),"x":p.x,"y":p.y,"vesselLane":int(actor.vesselLane),"statuses":{}}


static func _normalize_actor(actor: Dictionary) -> void:
	for key in ["id","faction","vesselLane"]: actor[key]=int(actor[key])
	var p:=Vector2(actor.x,actor.y); actor.x=p.x; actor.y=p.y


static func _actor(actor: Dictionary) -> bool:
	return _integer(actor.get("id"),1) and actor.get("kind") is String and not str(actor.kind).is_empty() and actor.get("category") is String and _integer(actor.get("faction"),0) and _integer(actor.get("vesselLane"),0) and _number(actor.get("hp")) and float(actor.hp)>=0 and _point([actor.get("x"),actor.get("y")]).is_finite()


static func _point(value: Variant) -> Vector2:
	if value is Vector2: return value if value.is_finite() else Vector2.INF
	if value is Array and value.size()==2 and _number(value[0]) and _number(value[1]):
		var p:=Vector2(float(value[0]),float(value[1])); return p if p.is_finite() and maxf(absf(p.x),absf(p.y))<=10000000 else Vector2.INF
	return Vector2.INF


static func _number(value: Variant) -> bool: return (value is int or value is float) and is_finite(float(value))
static func _integer(value: Variant,minimum: int) -> bool: return _number(value) and float(value)==floorf(float(value)) and float(value)>=minimum and float(value)<=MAX_ID
static func _predicate(value: Variant) -> bool: return value is bool and value
static func _key(value: Variant) -> bool: return value is String and value.is_valid_int() and str(int(value))==value and _integer(int(value),1)


static func _valid_world_id(value: Variant) -> bool:
	if not value is String or value.length()<8 or value.length()>96: return false
	for c in value.to_utf8_buffer():
		if not (c>=48 and c<=57 or c>=65 and c<=90 or c>=97 and c<=122 or c in [45,95]): return false
	return true


static func _circle_contact(a: Vector2,b: Vector2,center: Vector2,radius: float) -> float:
	var offset:=a-center; var c:=offset.length_squared()-radius*radius
	if c<=0: return 0
	var direction:=b-a; var length:=direction.length_squared()
	if length<=.000000000001: return -1
	var projection:=offset.dot(direction); var discriminant:=projection*projection-length*c
	if discriminant<0: return -1
	var fraction:=(-projection-sqrt(discriminant))/length
	return clampf(fraction,0,1) if fraction>=-EPS and fraction<=1+EPS else -1


func dispose() -> void:
	if _busy: return
	_damage=Callable(); _ground=Callable(); _segment=Callable(); _is_virus=Callable()
	_drops.clear(); _events.clear(); _sources.clear(); _positions.clear()
