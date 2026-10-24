extends SceneTree
## Native input, layout and lifetime checks for catalogue control feedback.
## ./godot/run.sh --headless --script res://tests/catalogue_motion.gd

var checks := 0
var failures: Array[String] = []
var motion: Script
var stage: Control
var button: Button
var field: LineEdit
var sibling: Button
var presses := 0
var toggles := 0
var edited := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if value:
		print("PASS ", message)
	else:
		failures.append(message)
		printerr("FAIL ", message)

func wait_real(seconds := .22) -> void:
	await create_timer(seconds, true, false, true).timeout

func move_mouse(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	root.push_input(event)
	await process_frame

func mouse_button(down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = button.get_global_rect().get_center()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	root.push_input(event)
	await process_frame

func key(code: int, down: bool, unicode_value := 0) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.unicode = unicode_value
	event.pressed = down
	root.push_input(event)
	await process_frame

func run() -> void:
	check(ResourceLoader.exists("res://scripts/catalogue_motion.gd"), "native motion component exists")
	if not failures.is_empty():
		quit(1)
		return
	motion = load("res://scripts/catalogue_motion.gd")
	root.size = Vector2i(640, 480)
	root.content_scale_size = Vector2i(640, 480)
	stage = Control.new()
	stage.size = Vector2(640, 480)
	root.add_child(stage)
	var column := VBoxContainer.new()
	column.position = Vector2(30, 40)
	column.size = Vector2(280, 260)
	stage.add_child(column)
	button = Button.new()
	button.text = "Catalogue choice"
	button.custom_minimum_size = Vector2(280, 64)
	button.self_modulate = Color(.91, .88, .84, .8)
	var base_color := button.self_modulate
	button.pressed.connect(func(): presses += 1)
	button.toggled.connect(func(_on: bool): toggles += 1)
	var effect: Node = motion.attach(button)
	check(effect != null and effect == motion.attach(button), "attach is idempotent before ready")
	check(button.get_child_count() == 1, "only one non-Control helper child is attached")
	column.add_child(button)
	sibling = Button.new()
	sibling.text = "Sibling"
	sibling.custom_minimum_size = Vector2(280, 64)
	column.add_child(sibling)
	field = LineEdit.new()
	field.custom_minimum_size = Vector2(280, 50)
	field.text_changed.connect(func(_value: String): edited += 1)
	column.add_child(field)
	var field_effect: Node = motion.attach(field)
	await wait_real()
	check(not effect.is_processing() and not effect.is_physics_processing(), "motion does not scan controls every frame")
	check(effect.process_mode == Node.PROCESS_MODE_ALWAYS, "helper stays active during SceneTree pause")
	check(button.pivot_offset.is_equal_approx(button.size * .5), "scale pivot uses the control center after layout")
	check(motion.attach(button) == effect and button.mouse_entered.get_connections().size() == 1, "repeated attach does not duplicate listeners")
	var original_position := button.position
	var original_size := button.size
	var original_minimum := button.get_combined_minimum_size()
	var sibling_position := sibling.position
	await move_mouse(button.get_global_rect().get_center())
	await wait_real()
	check(button.scale.x > 1.0 and button.scale.x <= 1.025, "native hover enlarges the button subtly")
	check(button.position == original_position and button.size == original_size and button.get_combined_minimum_size() == original_minimum, "hover leaves container geometry and minimum size unchanged")
	check(sibling.position == sibling_position, "hover does not move sibling controls")
	await mouse_button(true)
	await wait_real(.12)
	check(button.scale.x < 1.0 and button.scale.x >= .965, "native mouse press compresses the button")
	await mouse_button(false)
	await wait_real()
	check(presses == 1 and button.scale.x > 1.0, "release preserves the native pressed signal and restores hover")
	button.release_focus()
	await move_mouse(Vector2(600, 440))
	await wait_real()
	check(button.scale.is_equal_approx(Vector2.ONE) and button.self_modulate.is_equal_approx(base_color), "mouse exit returns to original scale and color")
	for _i in 16:
		button.mouse_entered.emit()
		button.button_down.emit()
		button.button_up.emit()
		button.mouse_exited.emit()
	await wait_real()
	check(button.scale.is_equal_approx(Vector2.ONE), "rapid press and hover reversals settle exactly at rest")
	check(not bool(button.get_meta("catalogue_motion_running", true)), "finished feedback leaves no running tween")
	button.mouse_entered.emit()
	await wait_real(.04)
	button.hide()
	check(button.scale.is_equal_approx(Vector2.ONE) and button.self_modulate.is_equal_approx(base_color), "hiding cancels feedback and restores appearance immediately")
	check(not bool(button.get_meta("catalogue_motion_running", true)), "hidden control keeps no active feedback tween")
	button.show()
	button.mouse_entered.emit()
	await wait_real(.04)
	button.disabled = true
	effect.refresh()
	check(button.scale.is_equal_approx(Vector2.ONE) and button.self_modulate.is_equal_approx(base_color), "refresh immediately resets a disabled button")
	button.disabled = false
	effect.refresh()
	button.mouse_entered.emit()
	await wait_real(.04)
	button.disabled = true
	await wait_real()
	check(button.scale.is_equal_approx(Vector2.ONE), "native disabled redraw also resets without explicit refresh")
	button.disabled = false
	effect.refresh()
	button.grab_focus()
	await wait_real()
	check(button.scale.x > 1.0, "native keyboard focus receives the same gentle emphasis")
	await key(KEY_SPACE, true)
	await wait_real(.12)
	check(button.scale.x < 1.0, "keyboard activation receives press feedback")
	await key(KEY_SPACE, false)
	check(presses == 2, "keyboard release emits one unmodified native pressed signal")
	button.toggle_mode = true
	await key(KEY_SPACE, true)
	await key(KEY_SPACE, false)
	check(button.button_pressed and toggles == 1 and presses == 3, "toggle selection and signal counts remain native")
	field.grab_focus()
	await key(KEY_A, true, 97)
	await key(KEY_A, false, 97)
	await wait_real()
	check(field.text == "a" and edited == 1 and field.scale.x > 1.0, "focused LineEdit keeps native editing and feedback")
	field.editable = false
	field_effect.refresh()
	check(field.scale.is_equal_approx(Vector2.ONE), "readonly LineEdit cancels focus feedback")
	field.editable = true
	field_effect.refresh()
	field.release_focus()
	button.button_pressed = false
	button.release_focus()
	await wait_real()
	Engine.time_scale = .05
	paused = true
	button.mouse_entered.emit()
	await wait_real(.22)
	check(button.scale.x > 1.019, "feedback finishes in real time during pause and slow simulation")
	paused = false
	Engine.time_scale = 1.0
	button.mouse_exited.emit()
	await wait_real()
	var panel := PanelContainer.new()
	panel.position = Vector2(360, 30)
	panel.size = Vector2(220, 160)
	panel.pivot_offset = Vector2(5, 7)
	panel.modulate = Color(.8, .9, 1.0, .65)
	stage.add_child(panel)
	var panel_color := panel.modulate
	var panel_size := panel.size
	motion.reveal(panel, .2)
	check(is_zero_approx(panel.modulate.a), "reveal starts transparently")
	check(panel.pivot_offset == Vector2(5, 7), "reveal leaves the existing transform pivot untouched")
	await wait_real(.05)
	check(panel.modulate.a > 0.0 and panel.modulate.a < panel_color.a, "reveal interpolates native opacity")
	motion.reveal(panel, .1)
	await wait_real(.18)
	check(panel.modulate.is_equal_approx(panel_color) and panel.size == panel_size, "restarted reveal preserves original tint alpha and layout")
	check(not bool(panel.get_meta("catalogue_reveal_running", true)), "completed reveal clears its running state")
	motion.reveal(panel)
	panel.hide()
	check(panel.modulate.is_equal_approx(panel_color), "hidden reveal resets original opacity immediately")
	panel.show()
	motion.reveal(panel)
	panel.scale = Vector2(.9, .9)
	panel.self_modulate = Color(.7, .8, .9, 1.0)
	stage.hide()
	check(button.scale.is_equal_approx(Vector2.ONE) and panel.modulate.is_equal_approx(panel_color), "hiding an ancestor cancels descendant feedback and reveals")
	check(panel.scale == Vector2(.9, .9) and panel.self_modulate == Color(.7, .8, .9, 1.0), "canceling a reveal leaves unrelated transform and self tint unchanged")
	stage.show()
	button.mouse_entered.emit()
	motion.reveal(button)
	motion.stop(button)
	check(button.scale.is_equal_approx(Vector2.ONE) and button.self_modulate.is_equal_approx(base_color) and button.modulate == Color.WHITE, "stop restores feedback and reveal appearance")
	check(button.mouse_entered.get_connections().is_empty() and not button.has_meta("catalogue_motion_state"), "stop disconnects only motion signals and removes its metadata")
	check(not button.has_meta("catalogue_motion_running") and not button.has_meta("catalogue_reveal_running"), "stop removes animation metadata after detaching the helper")
	check(button.pressed.get_connections().size() == 1 and button.toggled.get_connections().size() == 1, "stop preserves application signal listeners")
	motion.stop(button)
	var reattached: Node = motion.attach(button)
	check(reattached != null and reattached != effect and button.get_child_count() == 1, "stopped controls can be attached again without duplicate children")
	for _i in 24:
		var transient := Button.new()
		stage.add_child(transient)
		motion.attach(transient)
		transient.mouse_entered.emit()
		motion.reveal(transient)
		transient.queue_free()
	stage.queue_free()
	await wait_real(.3)
	check(get_processed_tweens().is_empty(), "rapid control rebuilds and release leave no scene tweens")
	print("CATALOGUE_MOTION ", checks - failures.size(), "/", checks)
	quit(1 if not failures.is_empty() else 0)
