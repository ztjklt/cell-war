extends RefCounted
## Small, event-driven feedback for native catalogue controls.
## Each control owns at most one helper and one tween per animated property group.

const HELPER_META := &"_catalogue_motion_helper"

static func attach(control: Control) -> Node:
	var helper := _helper(control)
	if helper != null:
		helper.interactive = true
		helper._update_pivot()
		helper.refresh()
	return helper

static func reveal(control: Control, duration := .20) -> void:
	var helper := _helper(control)
	if helper != null:
		helper.reveal(duration)

static func stop(control: Control) -> void:
	if not is_instance_valid(control):
		return
	var helper: Variant = control.get_meta(HELPER_META) if control.has_meta(HELPER_META) else null
	if not is_instance_valid(helper) or not helper is Controller:
		return
	helper.shutdown()
	control.remove_meta(HELPER_META)
	control.remove_child(helper)
	helper.queue_free()

static func _helper(control: Control) -> Controller:
	if not is_instance_valid(control) or control.is_queued_for_deletion():
		return null
	var existing: Variant = control.get_meta(HELPER_META) if control.has_meta(HELPER_META) else null
	if is_instance_valid(existing) and existing is Controller and not existing.is_queued_for_deletion():
		return existing
	var helper := Controller.new()
	helper.name = "CatalogueMotion"
	helper.bind(control)
	control.set_meta(HELPER_META, helper)
	control.add_child(helper)
	return helper

class Controller extends Node:
	var interactive := false
	var target: Control
	var _base_scale := Vector2.ONE
	var _base_color := Color.WHITE
	var _base_pivot := Vector2.ZERO
	var _hovered := false
	var _down := false
	var _state := ""
	var _last_available := false
	var _motion: Tween
	var _reveal: Tween
	var _reveal_active := false
	var _reveal_color := Color.WHITE
	var _pending_reveal := -1.0
	var _connections: Array[Dictionary] = []
	var _stopped := false

	func bind(control: Control) -> void:
		target = control
		_base_scale = control.scale
		_base_color = control.self_modulate
		_base_pivot = control.pivot_offset
		process_mode = Node.PROCESS_MODE_ALWAYS
		_listen(control.mouse_entered, _on_hover.bind(true))
		_listen(control.mouse_exited, _on_hover.bind(false))
		_listen(control.focus_entered, refresh)
		_listen(control.focus_exited, _on_focus_exit)
		_listen(control.resized, _update_pivot)
		_listen(control.visibility_changed, refresh)
		# BaseButton.disabled and LineEdit.editable have no changed signal. Native
		# controls request a redraw when these states change; no frame polling is needed.
		_listen(control.draw, _on_draw)
		if control is BaseButton:
			_listen(control.button_down, _on_press.bind(true))
			_listen(control.button_up, _on_press.bind(false))
			_listen(control.toggled, _on_toggle)
		_update_pivot()
		control.set_meta(&"catalogue_motion_state", "idle")
		control.set_meta(&"catalogue_motion_running", false)
		control.set_meta(&"catalogue_reveal_running", false)

	func _ready() -> void:
		_update_pivot()
		refresh()
		if _pending_reveal >= 0.0:
			_start_reveal(_pending_reveal)

	func _exit_tree() -> void:
		_reset_motion()
		_reset_reveal()

	func _listen(signal_value: Signal, callback: Callable) -> void:
		signal_value.connect(callback)
		_connections.append({"signal": signal_value, "callback": callback})

	func _available() -> bool:
		if not is_instance_valid(target) or target.is_queued_for_deletion():
			return false
		if not target.is_inside_tree() or not target.is_visible_in_tree():
			return false
		if target is BaseButton and target.disabled:
			return false
		if target is LineEdit and not target.editable:
			return false
		return true

	## Call after changing disabled/editable for an immediate reset before redraw.
	func refresh() -> void:
		if _stopped or not is_instance_valid(target):
			return
		_last_available = _available()
		if not _last_available:
			_reset_motion()
			if target.is_inside_tree():
				_reset_reveal()
			return
		if not interactive:
			return
		var next_state := "idle"
		var amount := 1.0
		var tint := Color.WHITE
		if _down:
			next_state = "pressed"
			amount = .97
			tint = Color(.965, .965, .965, 1.0)
		elif _hovered or target.has_focus():
			next_state = "hover" if _hovered else "focus"
			amount = 1.02
			tint = Color(1.035, 1.025, 1.015, 1.0)
		elif target is BaseButton and target.toggle_mode and target.button_pressed:
			next_state = "selected"
			tint = Color(1.025, 1.015, 1.0, 1.0)
		if _state == next_state:
			return
		_state = next_state
		target.set_meta(&"catalogue_motion_state", _state)
		_kill_motion()
		var goal_scale := _base_scale * amount
		var goal_color := _base_color * tint
		if target.scale.is_equal_approx(goal_scale) and target.self_modulate.is_equal_approx(goal_color):
			return
		_update_pivot()
		_motion = _new_tween()
		_motion.set_parallel(true)
		var duration := .075 if _down else .14
		_motion.tween_property(target, "scale", goal_scale, duration)
		_motion.tween_property(target, "self_modulate", goal_color, duration)
		_motion.finished.connect(_on_motion_finished)
		target.set_meta(&"catalogue_motion_running", true)

	func _new_tween() -> Tween:
		return create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	func _on_hover(value: bool) -> void:
		_hovered = value
		refresh()

	func _on_press(value: bool) -> void:
		_down = value
		refresh()

	func _on_toggle(_value: bool) -> void:
		refresh()

	func _on_focus_exit() -> void:
		_down = false
		refresh()

	func _on_draw() -> void:
		if _last_available != _available():
			refresh()

	func _update_pivot() -> void:
		if interactive and is_instance_valid(target):
			target.pivot_offset = target.size * .5

	func _on_motion_finished() -> void:
		_motion = null
		if is_instance_valid(target):
			target.set_meta(&"catalogue_motion_running", false)

	func _kill_motion() -> void:
		if _motion != null and _motion.is_valid():
			_motion.kill()
		_motion = null
		if not _stopped and is_instance_valid(target):
			target.set_meta(&"catalogue_motion_running", false)

	func _reset_motion() -> void:
		_kill_motion()
		_hovered = false
		_down = false
		_state = "inactive"
		if is_instance_valid(target):
			if interactive:
				target.scale = _base_scale
				target.self_modulate = _base_color
			if not _stopped:
				target.set_meta(&"catalogue_motion_state", _state)

	func reveal(duration: float) -> void:
		if _stopped or not is_instance_valid(target):
			return
		if not _reveal_active:
			_reveal_color = target.modulate
		_kill_reveal()
		_reveal_active = true
		_pending_reveal = maxf(0.0, duration)
		var transparent := _reveal_color
		transparent.a = 0.0
		target.modulate = transparent
		if is_inside_tree():
			_start_reveal(_pending_reveal)

	func _start_reveal(duration: float) -> void:
		_pending_reveal = -1.0
		if not _available() or duration <= 0.0:
			_reset_reveal()
			return
		_reveal = _new_tween()
		_reveal.tween_property(target, "modulate", _reveal_color, duration)
		_reveal.finished.connect(_on_reveal_finished)
		target.set_meta(&"catalogue_reveal_running", true)

	func _on_reveal_finished() -> void:
		_reveal = null
		_reveal_active = false
		if is_instance_valid(target):
			target.set_meta(&"catalogue_reveal_running", false)

	func _kill_reveal() -> void:
		if _reveal != null and _reveal.is_valid():
			_reveal.kill()
		_reveal = null
		if not _stopped and is_instance_valid(target):
			target.set_meta(&"catalogue_reveal_running", false)

	func _reset_reveal() -> void:
		_kill_reveal()
		if _reveal_active and is_instance_valid(target):
			target.modulate = _reveal_color
		_reveal_active = false
		_pending_reveal = -1.0

	func shutdown() -> void:
		_stopped = true
		_reset_motion()
		_reset_reveal()
		for connection in _connections:
			var signal_value: Signal = connection.signal
			var callback: Callable = connection.callback
			if not signal_value.is_null() and signal_value.is_connected(callback):
				signal_value.disconnect(callback)
		_connections.clear()
		if is_instance_valid(target):
			if interactive:
				target.pivot_offset = _base_pivot
			for key in [&"catalogue_motion_state", &"catalogue_motion_running", &"catalogue_reveal_running"]:
				target.remove_meta(key)
