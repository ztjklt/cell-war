extends WarSimulation
## Separate diagnostic only: inclusive timers add overhead; never used as the benchmark.
var measured: Dictionary = {}

func record(label: String,began: int) -> void:
	var value: Dictionary = measured.get(label,{"calls":0,"usec":0})
	value.calls += 1; value.usec += Time.get_ticks_usec()-began
	measured[label] = value

func _update_unit(e: Dictionary,dt: float) -> void:
	var began := Time.get_ticks_usec()
	super._update_unit(e,dt)
	record("unitDispatchInclusive",began)

func _resolve_units() -> void:
	var began := Time.get_ticks_usec()
	super._resolve_units()
	record("unitSeparation",began)

func visible(e: Dictionary,faction := 1) -> bool:
	var began := Time.get_ticks_usec()
	var result := super.visible(e,faction)
	record("visibilityInclusive",began)
	return result

func go(e: Dictionary,target: Vector2,dt: float,reach := .05,target_lane := -1) -> bool:
	var began := Time.get_ticks_usec()
	var result := super.go(e,target,dt,reach,target_lane)
	record("movementInclusive",began)
	return result

func _position_free(e: Dictionary,p: Vector2) -> bool:
	var began := Time.get_ticks_usec()
	var result := super._position_free(e,p)
	record("movementOccupancy",began)
	return result
