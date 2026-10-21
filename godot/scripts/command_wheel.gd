class_name WarCommandWheel
extends Control
## Two-click orders: opening and cancelling never mutate the simulation.
signal confirmed(action: String,point: Vector2,append: bool,ids: Array,context: Dictionary)
var hud: WarHUD
var buttons: Array[WarCommandButton] = []
var center_button: Button
var summary: Label
var feedback: Label
var anchor := Vector2.ZERO
var center := Vector2.ZERO
var target_world := Vector2.ZERO
var saved_ids: Array = []
var append := false
var context: Dictionary = {}
var page := -1
var animation: Tween
var committing := false
var feedback_error := false
var arc_progress := 0.0:
	set(value):
		arc_progress = value
		queue_redraw()

func setup(owner: WarHUD) -> void:
	hud = owner
	name = "CommandWheel"
	z_index = 70
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	center_button = Button.new()
	center_button.text = "×"
	center_button.tooltip_text = "取消 · Esc"
	center_button.custom_minimum_size = Vector2(44,44)
	center_button.size = Vector2(44,44)
	WarUISkin.apply_button(center_button)
	center_button.pressed.connect(_center_pressed)
	add_child(center_button)
	summary = Label.new()
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary.add_theme_font_size_override("font_size",12)
	summary.add_theme_color_override("font_color",WarUISkin.INK)
	summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(summary)
	feedback = Label.new()
	feedback.custom_minimum_size.x = 296
	feedback.size = Vector2(296,42)
	feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.add_theme_font_size_override("font_size",13)
	feedback.add_theme_color_override("font_color",WarUISkin.INK)
	feedback.add_theme_stylebox_override("normal",StyleBoxEmpty.new())
	feedback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(feedback)
	WarFacetSurface.attach(feedback,WarUISkin.CREAM,3,10)
	hide()

func _center_pressed() -> void:
	if committing: return
	if page >= 0: _show_orders()
	else: close()

func open(at: Vector2,point: Vector2,queued: bool) -> void:
	close()
	saved_ids.clear()
	for id in hud.game.selected:
		var e := hud.game.entity(id)
		if not e.is_empty() and e.faction == 1 and e.hp > 0: saved_ids.append(int(id))
	if saved_ids.is_empty():
		hud.game.notify("先选择要指挥的细胞")
		return
	anchor = at
	target_world = point
	append = queued or hud.append_orders
	context = _target_context(at)
	show()
	_show_orders()
	if animation: animation.kill()
	modulate.a = 0
	animation = create_tween()
	arc_progress = 0
	animation.set_parallel(true)
	animation.tween_property(self,"modulate:a",1.0,.12)
	animation.tween_property(self,"arc_progress",1.0,.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _target_context(at: Vector2) -> Dictionary:
	var result := {"target":0,"resource":""}
	var displayed: Vector2 = hud.get_parent().get_canvas_transform().affine_inverse()*at
	for e in hud.game.entities():
		if hud.game.visible(e) and hud.world.pick(e,displayed):
			result.target = int(e.id)
			break
	if int(result.target) == 0:
		for key in hud.game.state.resources:
			var resource: Dictionary = hud.game.state.resources[key]
			if (resource.amount > 0 or resource.get("organSource",false)) and target_world.distance_to(WarData.point(resource)) <= float(resource.get("radius",2.2)):
				result.resource = key
				break
	return result

func _show_orders() -> void:
	page = -1
	feedback_error = false
	var entries: Array = []
	var units := false
	var attackers := false
	var worker := false
	var building := false
	for id in saved_ids:
		var e := hud.game.entity(id)
		units = units or e.get("category","") == "unit"
		attackers = attackers or (e.get("category","") == "unit" and e.get("kind","") not in ["b_cell","dendritic_cell"])
		worker = worker or e.get("kind","") == "worker"
		building = building or e.get("category","") == "building"
	if units:
		entries.append({"title":"移动","action":"move"})
		var target := hud.game.entity(int(context.target))
		var enemy: bool = not target.is_empty() and target.faction != 1
		if attackers: entries.append({"title":"攻击目标" if enemy else "进攻","action":"attack" if enemy else "attackmove","accent":"primary"})
		entries.append({"title":"驻守","action":"guard"})
		entries.append({"title":"撤退","action":"retreat"})
		entries.append({"title":"停止","action":"stop"})
		if worker:
			if not target.is_empty() and target.faction == 1 and target.category == "building" and (not target.get("complete",true) or target.hp < target.maxHp):
				entries.append({"title":"维修" if target.get("complete",true) else "协助建造","action":"repair" if target.get("complete",true) else "build"})
			elif not target.is_empty() and target.faction == 1 and target.kind == "farm" and target.hp > 0 and target.get("complete",false):
				pass # This target exposes cultivation below, rather than new placement.
			elif not str(context.resource).is_empty(): entries.append({"title":"采集","action":"harvest"})
			elif not hud.game.is_campaign(): entries.append({"title":"建造","action":"build_menu"})
			if not target.is_empty() and target.faction == 1 and target.category == "building" and target.kind == "farm" and target.hp > 0 and target.get("complete",false):
				entries.append({"title":"培育葡萄糖","action":"farm","accent":"sage","tooltip":"红细胞在培养床工作，产出后自动运回补给点并继续培育"})
			if hud.game.mode == "sandbox" and not target.is_empty() and target.faction == 1 and target.category == "building" and target.hp > 0 and float(target.get("fire",0)) > 0:
				entries.append({"title":"灭火","action":"extinguish","accent":"sage","tooltip":"红细胞前往建筑扑灭火灾；修复生命使用维修指令"})
	elif building:
		entries.append({"title":"生产管理","action":"production"})
		entries.append({"title":"集结到此","action":"rally"})
	var service := hud._organ_service()
	if service != null and saved_ids.size() == 1 and not service.available_actions(int(saved_ids[0]),1).is_empty(): entries.append({"title":"器官协作","action":"organ_menu"})
	center_button.text = "×"
	center_button.tooltip_text = "取消 · Esc"
	summary.text = "%d 个已选" % saved_ids.size()
	feedback.text = "选择指令确认"+(" · 追加队列" if append else "")
	var context_target := hud.game.entity(int(context.target))
	if hud.game.mode == "sandbox" and context_target.get("category","") == "building" and float(context_target.get("fire",0)) > 0: feedback.text = "建筑正在燃烧 · 灭火阻止损失，维修恢复生命"
	_update_resource_feedback()
	_render(entries)

func _update_resource_feedback() -> void:
	if page != -1 or feedback_error: return
	var resource: Dictionary = hud.game.state.resources.get(str(context.get("resource","")),{})
	if resource.get("organSource",false):
		feedback.text = hud.resource_station_text(resource)+"\n选择采集后自动运输 · 空站可等候"

func _show_builds(index: int) -> void:
	page = index
	var kinds: Array = WarData.config().Data.buildOrder
	var pages := ceili(kinds.size()/5.0)
	var entries: Array = []
	for i in range(index*5,mini(index*5+5,kinds.size())):
		var kind: String = kinds[i]
		var spec := WarData.spec(kind)
		var reason := ""
		if int(hud.game.state.factions[0].tier) < int(spec.get("tier",1)): reason = "需要科技等级 %d" % int(spec.tier)
		for resource in spec.get("cost",{}):
			if hud.game.economy.stock(1,resource) < float(spec.cost[resource]): reason = "资源不足"
		entries.append({"title":spec.name,"action":"place:"+kind,"disabled":not reason.is_empty(),"tooltip":hud.cost_text(spec.cost)+(" · "+reason if not reason.is_empty() else "")})
	if pages > 1: entries.append({"title":"下一页","action":"next"})
	center_button.text = "‹"
	center_button.tooltip_text = "返回指令 · Esc 取消"
	summary.text = "建造 %d / %d" % [index+1,pages]
	feedback.text = "在刚才点击的位置建造 · 悬停查看花费"
	_render(entries)

func _render(entries: Array) -> void:
	for btn in buttons:
		remove_child(btn)
		btn.queue_free()
	buttons.clear()
	for entry in entries:
		var btn := WarCommandButton.new()
		add_child(btn)
		var action: String = entry.action
		btn.configure(entry.title,action,entry.get("accent",""))
		btn.disabled = entry.get("disabled",false)
		btn.tooltip_text = entry.get("tooltip",entry.title)
		btn.pressed.connect(_choose.bind(action))
		buttons.append(btn)
	reflow(true)

func reflow(animate := false) -> void:
	if committing: return
	var view := get_viewport_rect().size
	var phone := view.x < 720
	var radius := (110.0 if phone else 128.0) if buttons.size() >= 8 else (99.0 if phone else 112.0)
	var resource: Dictionary = hud.game.state.resources.get(str(context.get("resource","")),{})
	var feedback_height := 108.0 if page == -1 and resource.get("organSource",false) else 42.0
	var extent := Vector2(maxf(148 if phone else 168,radius+(41 if phone else 47)+8),maxf(200 if phone else 212,radius+42+feedback_height+8))
	center = anchor.clamp(extent,view-extent)
	center_button.position = center-center_button.size*.5
	summary.position = center+Vector2(-56,27)
	summary.size = Vector2(112,22)
	feedback.position = center+Vector2(-148,radius+42)
	feedback.size = Vector2(296,feedback_height)
	for i in buttons.size():
		var btn := buttons[i]
		btn.custom_minimum_size = Vector2(82,76) if phone else Vector2(94,80)
		btn.size = btn.custom_minimum_size
		var angle := -PI*.5+float(i)*TAU/buttons.size()
		var direction := Vector2.from_angle(angle)
		var destination := center+direction*radius-btn.size*.5
		if animate: btn.reveal(center+direction*radius*.35-btn.size*.5,destination,i*.018)
		else: btn.settle(destination)
	queue_redraw()

func _choose(action: String) -> void:
	if committing: return
	if action == "build_menu": _show_builds(0)
	elif action == "next": _show_builds((page+1)%ceili(WarData.config().Data.buildOrder.size()/5.0))
	elif action == "organ_menu": close(); hud.show_organ_actions()
	else: confirmed.emit(action,target_world,append,saved_ids.duplicate(),context.duplicate())

func present_error(text: String) -> void:
	feedback_error = true
	feedback.text = text

func confirm(action: String) -> void:
	if committing: return
	committing = true
	if animation: animation.kill()
	var chosen: WarCommandButton
	for btn in buttons:
		btn.settle(btn.position)
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.focus_mode = Control.FOCUS_NONE
		if btn.action == action: chosen = btn
	animation = create_tween().set_parallel(true)
	animation.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	animation.tween_property(self,"arc_progress",0.0,.16)
	for node in [center_button,summary,feedback]: animation.tween_property(node,"modulate:a",0.0,.12)
	for btn in buttons:
		if btn == chosen: continue
		animation.tween_property(btn,"position",btn.position.lerp(center-btn.size*.5,.45),.16)
		animation.tween_property(btn,"modulate:a",0.0,.13)
	if chosen != null:
		chosen.z_index = 5
		animation.tween_property(chosen,"scale",Vector2.ONE*1.08,.07)
		animation.tween_property(chosen,"position",anchor-chosen.size*.5,.23).set_delay(.07).set_ease(Tween.EASE_IN_OUT)
		animation.tween_property(chosen,"scale",Vector2.ONE*.24,.23).from(Vector2.ONE*1.08).set_delay(.07).set_ease(Tween.EASE_IN_OUT)
		animation.tween_property(chosen,"modulate:a",0.0,.08).set_delay(.25)
	animation.tween_callback(_acknowledge.bind(action)).set_delay(.33)

func _acknowledge(action: String) -> void:
	animation = null
	var pulse := WarOrderPulse.new()
	hud.root.add_child(pulse)
	pulse.configure(anchor,action,hud.game.paused)
	close()

func close() -> void:
	if animation: animation.kill()
	committing = false
	for btn in buttons:
		remove_child(btn)
		btn.queue_free()
	buttons.clear()
	if center_button != null:
		for node in [center_button,summary,feedback]: node.modulate.a = 1
	hide()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		accept_event()
		if committing: return
		if event.pressed and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]: close()

func _process(_delta: float) -> void:
	if not visible: return
	if committing: return
	_update_resource_feedback()
	if hud.menu.visible or hud.home.visible or hud.world.layer == 6 or hud.game.selected != saved_ids:
		close()
		return
	for id in saved_ids:
		if hud.game.entity(int(id)).is_empty(): close(); return

func _draw() -> void:
	if not visible: return
	var color := Color(WarUISkin.MUTED,.35*arc_progress)
	var radius := 99.0 if get_viewport_rect().size.x < 720 else 112.0
	draw_arc(center,radius,-PI*.5,-PI*.5+TAU*maxf(.001,arc_progress),96,color,1,true)
	if center.distance_to(anchor) > 4:
		draw_line(anchor,center,color,1,true)
		draw_arc(anchor,5,0,TAU,20,WarUISkin.INK,1,true)
