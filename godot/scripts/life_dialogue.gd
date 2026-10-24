class_name WarLifeDialogue
extends Control
## Live external conversations on the desk phone; presentation never advances time.
signal incoming_message
const INK := WarUISkin.INK
const MUTED := WarUISkin.MUTED
const ON_DESK := WarUISkin.INK
const ENTER_SECONDS := .34
var hud: WarHUD
var panel: MarginContainer
var phone: WarDeskPhone
var event_button: Button
var folded_note: Label
var summary: Label
var scroll: ScrollContainer
var content: VBoxContainer
var clock: Label
var toggle: Button
var option_buttons: Array[Button] = []
var expanded := true
var preview_id := ""
var preview_choice := -1
var _key := ""
var _view_key := ""
var _seen := -1
var _owns_pause := false
var _previous_pause := false
var _stages: Array[Dictionary] = []
var _playback: Dictionary = {}
var _elapsed := 0.0
var _cursor := .12
var _sequence_end := 0.0
var _chat_width := 410.0
var _layout_width := 0.0
var _options_ready := false
var _restart_preview := false
var _settled_history_count := -1
var _follow_frames := 0

class BubbleShell extends PanelContainer:
	var own := false
	func _draw() -> void:
		var x := size.x if own else 0.0
		var tip := 6.0 if own else -6.0
		var points := PackedVector2Array([Vector2(x,11),Vector2(x+tip,16),Vector2(x,21)])
		draw_colored_polygon(points,Color("e5cbe5") if own else WarUISkin.CREAM)
		if not own: draw_polyline(points,WarUISkin.LINE,1,true)

func setup(owner: WarHUD) -> void:
	hud = owner
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A live reply pauses the simulation.  Keep the handset above the map and
	# ordinary HUD panels so that its choices, rather than the map below, receive
	# the pointer event.
	z_index = 20
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	phone = WarDeskPhone.new(); phone.name = "DeskPhone"; add_child(phone)
	# Layout-only content inside the phone's screen; only actual controls take input.
	panel = MarginContainer.new(); panel.name = "LifeConversation"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(panel)
	var column := VBoxContainer.new(); column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation",8); panel.add_child(column)
	summary = _label("",12,ON_DESK)
	column.add_child(summary)
	var header := HBoxContainer.new(); header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_constant_override("separation",6); column.add_child(header)
	var heading := _label("外部联系",13,ON_DESK)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL; header.add_child(heading)
	toggle = _small_button("收起",_toggle,header)
	event_button = _small_button("事件 · 40",func(): hud.show_life_events(),header)
	scroll = ScrollContainer.new(); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; column.add_child(scroll)
	scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inset := MarginContainer.new(); inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inset.add_theme_constant_override("margin_left",8); inset.add_theme_constant_override("margin_right",8)
	scroll.add_child(inset)
	content = VBoxContainer.new(); content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",9); inset.add_child(content)
	clock = _label("",11,ON_DESK); column.add_child(clock)
	folded_note = _label("消息已收起\n点击「展开」查看",12,MUTED)
	column.add_child(folded_note)
	hud.game.state_replaced.connect(reset_world)

func _label(text: String,font_size: int,color := INK) -> Label:
	var line := Label.new(); line.text = text
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_font_override("font",WarUISkin.BODY)
	line.add_theme_font_size_override("font_size",font_size)
	line.add_theme_color_override("font_color",color)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return line

static func _white_box(fill := Color.WHITE) -> StyleBoxTexture:
	var skin := WarUISkin.painted_panel(fill,12,12,"button")
	skin.content_margin_top = 9; skin.content_margin_bottom = 9
	return skin

func _small_button(text: String,callback: Callable,parent: Node) -> Button:
	var button := Button.new(); button.text = text; button.focus_mode = Control.FOCUS_NONE
	WarUISkin.apply_button(button)
	button.custom_minimum_size = Vector2(0,24)
	button.add_theme_font_override("font",WarUISkin.BODY); button.add_theme_font_size_override("font_size",12)
	for state in WarUISkin.STATES:
		var skin := WarUISkin.button_box(state,"",12,"compact")
		skin.content_margin_left = 4; skin.content_margin_right = 4
		skin.content_margin_top = 2; skin.content_margin_bottom = 2
		button.add_theme_stylebox_override(state,skin)
	button.pressed.connect(callback); parent.add_child(button)
	return button

func reset_world() -> void:
	_key = ""; _view_key = ""; _seen = -1; _owns_pause = false
	preview_id = ""; preview_choice = -1; expanded = true; _playback.clear(); _layout_width = 0
	_settled_history_count = -1; _restart_preview = false

func apply_desk_projection(projection: Transform2D) -> void:
	# The physical phone and its real controls share the desk's camera transform.
	# Screen HUD, the advisor and the return-to-overview icon remain accessible.
	position = projection.origin
	scale = projection.get_scale()

func _take_pause() -> void:
	if _owns_pause: return
	_previous_pause = hud.game.paused; _owns_pause = true; hud.game.paused = true

func _release_pause() -> void:
	if not _owns_pause: return
	if not hud.game.life.enabled() or hud.game.life.state().phase != "ended": hud.game.paused = _previous_pause
	_owns_pause = false

func _toggle() -> void:
	if not preview_id.is_empty():
		preview_id = ""; preview_choice = -1; _key = ""; expanded = true; _release_pause()
		if not hud.game.life.state().pending.is_empty(): _take_pause()
		return
	expanded = not expanded
	if expanded and not hud.game.life.state().pending.is_empty(): _take_pause()
	else: _release_pause()

func show_preview(id: String) -> void:
	if WarLifeRun.definition(id).is_empty(): return
	preview_id = id; preview_choice = -1; expanded = true; _key = ""; _take_pause()
	_restart_preview = true

func animation_finished() -> bool:
	return _elapsed >= _sequence_end

func submit_choice(token: int,index: int) -> bool:
	if not preview_id.is_empty():
		var preview := WarLifeRun.definition(preview_id)
		if index < 0 or index >= preview.get("options",[]).size(): return false
		preview_choice = index
		_key = ""
		hud.game.notify("事件预览：已展示结果；不会改写本局记录")
		return true
	if not hud.game.life.choose(token,index): return false
	_settled_history_count = int(hud.game.life.state().decisionCount)
	_release_pause(); _key = ""
	_save_progress()
	return true

func _entry(widget: Control,start: float,side: int,own := false,option := false) -> void:
	var slot := Control.new(); slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(slot); slot.add_child(widget)
	slot.custom_minimum_size.y = widget.custom_minimum_size.y
	widget.size = Vector2(_chat_width,widget.custom_minimum_size.y)
	slot.visible = false; widget.modulate.a = 0
	_stages.append({"slot":slot,"widget":widget,"start":start,"side":side,"own":own,"option":option})
	_sequence_end = maxf(_sequence_end,start+ENTER_SECONDS)

func _bubble(speaker: String,text: String,own: bool,start: float) -> void:
	var row := HBoxContainer.new(); row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var text_width := WarUISkin.BODY.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,15).x
	var width := minf(_chat_width*.82,maxf(66,ceilf(text_width)+26))
	var block := VBoxContainer.new(); block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.custom_minimum_size.x = width; block.add_theme_constant_override("separation",5)
	var spacer := Control.new(); spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if own: row.add_child(spacer)
	row.add_child(block)
	if not own: row.add_child(spacer)
	var height := ceilf(WarUISkin.BODY.get_height(15))+20
	if not speaker.is_empty():
		var name_label := _label(speaker,11,ON_DESK)
		if own: name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		block.add_child(name_label); height += ceilf(WarUISkin.BODY.get_height(11))+5
	var shell := BubbleShell.new(); shell.own = own; block.add_child(shell)
	var skin := _white_box(Color("ebd4ec") if own else Color.WHITE)
	shell.add_theme_stylebox_override("panel",skin)
	shell.add_child(_label(text,15,INK))
	row.custom_minimum_size.y = height
	_entry(row,start,1 if own else -1,own)

func _messages(speaker: String,text: String,own := false,already_shown := false) -> void:
	var limit := minf(18,(_chat_width*.82-28)/15)
	var chunks := WarAdvisorDialogue.split_text(text,limit)
	for i in chunks.size():
		_bubble(speaker if i == 0 else "",chunks[i],own,-10.0 if already_shown else _cursor)
		if not already_shown: _cursor += maxf(.72,WarAdvisorDialogue.text_weight(chunks[i])*.034+.4)

func _note(text: String) -> void:
	var line := _label(text,11,ON_DESK)
	line.custom_minimum_size.y = 18
	_entry(line,_cursor,0)
	_cursor += .2

func _option(item: Dictionary,index: int,token: int) -> void:
	var option: Dictionary = item.options[index]
	var button := Button.new(); button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	WarUISkin.apply_button(button)
	var body := VBoxContainer.new(); body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation",4); button.add_child(body)
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.offset_left = 12; body.offset_right = -12; body.offset_top = 9; body.offset_bottom = -9
	var affordable := hud.game.life.affordable(option)
	body.add_child(_label("%s  %s" % [char(65+index),option.label],14,INK if affordable else MUTED))
	var effects := WarLifeRun.effect_text(option)
	if not affordable: effects += "\n余额不足"
	body.add_child(_label(effects,11,MUTED))
	button.tooltip_text = option.label+"\n"+effects
	if not preview_id.is_empty(): button.tooltip_text += "\n\n事件预览：点击可查看回复，不会结算。"
	button.custom_minimum_size = Vector2(0,ceilf(WarUISkin.BODY.get_height(14))+ceilf(WarUISkin.BODY.get_height(11))*(effects.count("\n")+1)+24)
	# Hidden rows cannot receive clicks.  As soon as an option is on screen it
	# is actionable; waiting for the whole chat animation previously made a
	# paused live event look like a broken phone.
	button.disabled = not hud.game.life.affordable(option)
	button.pressed.connect(func(): submit_choice(token,index))
	option_buttons.append(button)
	_entry(button,_cursor,0,false,true)
	_cursor += .16

func _rebuild() -> void:
	var previous := _view_key
	if not _view_key.is_empty(): _playback[_view_key] = _elapsed
	for child in content.get_children(): content.remove_child(child); child.queue_free()
	option_buttons.clear(); _stages.clear(); _cursor = .12; _sequence_end = 0; _options_ready = false
	var s := hud.game.life.state()
	var item := WarLifeRun.definition(preview_id) if not preview_id.is_empty() else WarLifeRun.definition(str(s.pending.get("id","")))
	if s.phase == "ended":
		_view_key = "ended"
		_messages("小脑 · 生命历程","本局存活至 %.1f 岁。完成 %d 次生活选择，遭遇 %d 次外部感染。可从右侧菜单读取存档或重新开始。" % [float(s.finishedAge),int(s.decisionCount),int(s.outbreaks)])
	elif item.is_empty():
		if s.history.is_empty():
			_view_key = "intro"
			_messages("生活联系","首次联系会在游玩 3 分钟后到来。也可以先查看全部事件。")
			_messages("本人","新的生活开始了，工作、吃饭和休息，都在这里安排。",true)
		else:
			var last: Dictionary = s.history.back()
			_view_key = "history:"+str(s.decisionCount)
			var answered := previous.begins_with("offer:") or int(s.decisionCount) == _settled_history_count
			_messages(last.speaker,last.line,false,answered)
			_messages("本人",last.own,true,answered)
			_messages("",last.reply,true)
			_note(s.lastChange)
	else:
		_view_key = "preview:"+preview_id if not preview_id.is_empty() else "offer:"+str(s.pending.token)
		if not preview_id.is_empty():
			_note("事件预览 · 点击选项查看对应回复；不会结算金钱、机能或时间。点击「返回」回到实况。")
		_messages(item.speaker,item.line,item.speaker == "本人")
		_messages("本人",item.own,true)
		_cursor += .15
		for i in item.options.size(): _option(item,i,int(s.pending.get("token",-1)))
		if not preview_id.is_empty() and preview_choice >= 0:
			var chosen: Dictionary = item.options[preview_choice]
			_note("预览结果 · "+WarLifeRun.effect_text(chosen))
			_messages("本人",str(chosen.reply),true)
	_elapsed = 0.0 if _restart_preview else float(_playback.get(_view_key,0))
	_restart_preview = false; _follow_frames = 3
	if _playback.size() > 64: _playback.erase(_playback.keys()[0])
	scroll.scroll_vertical = 0

func _animate(delta: float) -> void:
	if not expanded: return
	_elapsed += minf(maxf(delta,0),.1)
	var follow_bottom := scroll.scroll_vertical >= scroll.get_v_scroll_bar().max_value-scroll.get_v_scroll_bar().page-24
	var appeared := false
	for stage in _stages:
		var age := _elapsed-float(stage.start)
		var slot: Control = stage.slot
		var widget: Control = stage.widget
		if age < 0:
			slot.hide(); continue
		if not slot.visible: slot.show(); appeared = true
		var t := clampf(age/ENTER_SECONDS,0,1)
		var ease := 1-pow(1-t,3)
		widget.modulate.a = t
		widget.position = Vector2(float(stage.side)*24*(1-ease),10*(1-ease) if stage.option else 0)
		widget.size = Vector2(slot.size.x,slot.custom_minimum_size.y)
	if appeared and follow_bottom: _follow_frames = 3
	if _follow_frames > 0:
		scroll.set_deferred("scroll_vertical",int(scroll.get_v_scroll_bar().max_value)); _follow_frames -= 1
	_options_ready = animation_finished() and preview_id.is_empty()
	var item := WarLifeRun.definition(str(hud.game.life.state().pending.get("id","")))
	for i in option_buttons.size():
		if not preview_id.is_empty():
			# The preview uses its own definition and remains interactive so that a
			# player gets visible feedback before a real contact arrives.
			var preview := WarLifeRun.definition(preview_id)
			option_buttons[i].disabled = preview.is_empty() or not hud.game.life.affordable(preview.options[i])
		else:
			option_buttons[i].disabled = item.is_empty() or not hud.game.life.affordable(item.options[i])
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP if content.size.y > scroll.size.y+1 else Control.MOUSE_FILTER_IGNORE

func layout() -> void:
	var size := get_viewport_rect().size
	var narrow := size.x < 720
	var frame := WarDeskPhone.rect_for(size,expanded)
	if narrow and expanded:
		# The native selection card can grow with its contents; keep the phone's
		# scrollable screen above it instead of covering either set of controls.
		frame.size.y = minf(frame.size.y,maxf(250,hud.panel.position.y-frame.position.y-12))
	phone.position = frame.position; phone.size = frame.size
	var screen := phone.content_rect()
	panel.position = phone.position+screen.position
	panel.size = screen.size
	_chat_width = screen.size.x
	summary.visible = expanded or not narrow
	event_button.visible = expanded or not narrow
	folded_note.visible = not expanded
	scroll.visible = expanded
	scroll.custom_minimum_size.y = 0
	toggle.text = "返回" if not preview_id.is_empty() else ("收起" if expanded else "展开")
	if not is_equal_approx(_layout_width,_chat_width): _layout_width = _chat_width; _key = ""
	hud.status.visible = not (narrow and expanded)

func _process(delta: float) -> void:
	if hud == null: return
	visible = hud.game.life.enabled() and not hud.home.visible and not hud.menu.visible
	if not visible: return
	var s := hud.game.life.state()
	var token := int(s.pending.get("token",-1))
	if token > 0 and token != _seen and preview_id.is_empty():
		_seen = token; expanded = true; _take_pause()
		incoming_message.emit()
		_save_progress()
	layout()
	var key := "%s:%s:%s" % [s.revision,preview_id,s.phase]
	if key != _key:
		_key = key; _rebuild()
		if s.phase == "ended": _save_progress()
	summary.text = "金钱 %d  ·  机能 %.1f  ·  %.1f岁" % [int(s.money),float(s.function),float(s.age)]
	var remaining := maxi(0,ceili(float(s.nextDecisionAt)-float(s.activeElapsed)))
	summary.tooltip_text = "身体机能 %.1f / 100 · 已完成 %d 次选择\n下次联系约 %d分%02d秒" % [float(s.function),int(s.decisionCount),remaining/60,remaining%60]
	clock.visible = expanded and (s.phase != "living" or not preview_id.is_empty() or not s.pending.is_empty())
	folded_note.text = "有一条待回复联系\n点击「展开」查看" if not s.pending.is_empty() else "消息已收起\n点击「展开」查看"
	if s.phase == "crisis": clock.text = "危急 · 剩余 %.0f 秒，恢复到 2 可脱险" % float(s.crisisRemaining)
	elif s.phase == "ended": clock.text = "生命历程已结束"
	elif not preview_id.is_empty(): clock.text = "事件预览 · 不结算"
	else: clock.text = "待回复 · 收起可继续战斗" if not expanded else ""
	_animate(delta)

func _save_progress() -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("save_progress"): scene.save_progress()
