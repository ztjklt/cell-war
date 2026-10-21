class_name WarAdvisorDialogue
extends Control
## Native adaptation of the teammate's short-strip UI, checked against BrainUI.lua.
var hud: WarHUD
var feed: Control
var controls: HBoxContainer
var skip: Button
var hit: Button
var strips: Array[Dictionary] = []
var history: Array[Dictionary] = []
var elapsed := 0.0
var duration := 0.0
var chatting := false
var active := false
var topic := ""
var memory: Dictionary = {}
var intro := 0.0
var bubble := ""
var bubble_remaining := 0.0

static func text_weight(text: String) -> float:
	var total := 0.0
	for i in text.length(): total += .6 if text.unicode_at(i) < 128 else 1.0
	return total

static func split_text(text: String,limit := 20.0) -> Array[String]:
	var result: Array[String] = []
	var chunk := ""
	var used := 0.0
	limit = maxf(6,limit)
	for i in text.length():
		var c := text[i]
		var weight := .6 if text.unicode_at(i) < 128 else 1.0
		if c == "\n":
			if not chunk.is_empty(): result.append(chunk)
			chunk = ""; used = 0
			continue
		if used+weight > limit:
			if not chunk.is_empty(): result.append(chunk)
			chunk = ""; used = 0
		chunk += c; used += weight
		if c in ["。","！","？","；","，"] and used >= 4:
			result.append(chunk); chunk = ""; used = 0
	if not chunk.is_empty(): result.append(chunk)
	return result

func feed_width() -> float:
	if hud.game.life.enabled() and get_viewport_rect().size.x < 720: return minf(200,get_viewport_rect().size.x-156)
	if hud.game.life.enabled(): return minf(270,WarDeskMapFrame.rect_for(get_viewport_rect().size).position.x-90)
	return minf(356,get_viewport_rect().size.x-24)

func setup(owner: WarHUD) -> void:
	hud = owner
	z_index = 9
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hit = Button.new()
	hit.flat = true; hit.focus_mode = Control.FOCUS_NONE
	for key in ["normal","hover","pressed","focus"]: hit.add_theme_stylebox_override(key,StyleBoxEmpty.new())
	hit.tooltip_text = "小脑 · 你的战术参谋，点击听取汇报"
	hit.pressed.connect(func(): close_chat() if chatting else answer("body"))
	add_child(hit)
	feed = Control.new(); feed.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(feed)
	controls = HBoxContainer.new(); controls.add_theme_constant_override("separation",5); add_child(controls)
	for item in [["人体情况","body"],["守卫建议","defense"],["援军补给","supply"]]:
		var key: String = item[1]
		_chat_button(item[0],func(): answer(key))
	skip = _chat_button("»",func(): elapsed = duration)
	_chat_button("×",close_chat)
	controls.hide()
	hud.game.state_replaced.connect(reset_world)

func _chat_button(text: String,callback: Callable) -> Button:
	var btn := hud.button(text,callback,controls)
	btn.custom_minimum_size.y = 28
	btn.add_theme_font_size_override("font_size",13)
	btn.add_theme_color_override("font_color",Color("e2e6ea"))
	btn.add_theme_color_override("font_hover_color",Color("e2e6ea"))
	for key in ["normal","hover","pressed","focus"]:
		var skin := WarHUD.style(Color(30.0/255,32.0/255,37.0/255,245.0/255),12)
		skin.content_margin_left = 4; skin.content_margin_right = 4
		skin.content_margin_top = 0; skin.content_margin_bottom = 0
		btn.add_theme_stylebox_override(key,skin)
	return btn

func close_chat() -> void:
	chatting = false; active = false; topic = ""; bubble = ""; bubble_remaining = 0
	feed.hide(); controls.hide(); hud.advisor.speaking = false

func reset_world() -> void:
	close_chat(); history.clear(); memory.clear(); intro = 0
	for child in feed.get_children(): child.queue_free()
	strips.clear()

func answer(value: String) -> void:
	chatting = true; topic = value
	var question := "现在应该怎样守卫？" if value == "defense" else ("援军和补给准备好了吗？" if value == "supply" else "人体现在怎么样？")
	history.append({"sender":"you","text":question})
	say(WarAdvisorRules.reply(hud.game,value).text,question)

func say(text: String,question := "") -> void:
	for child in feed.get_children(): feed.remove_child(child); child.queue_free()
	strips.clear(); elapsed = 0; duration = 0; active = true
	if not question.is_empty(): _append_strip(question,true)
	var width := feed_width()
	for chunk in split_text(text,minf(20,(width-26)/15)): _append_strip(chunk,false)
	history.append({"sender":"brain","text":text})
	while history.size() > 6: history.pop_front()
	if not chatting: bubble_remaining = maxf(bubble_remaining,duration+3.5)

func _append_strip(text: String,user: bool) -> void:
	var chip := PanelContainer.new(); chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var skin := WarHUD.style(Color(43.0/255,52.0/255,69.0/255,244.0/255) if user else Color(16.0/255,18.0/255,23.0/255,244.0/255),12)
	skin.content_margin_left = 12; skin.content_margin_right = 12
	skin.content_margin_top = 0; skin.content_margin_bottom = 0
	chip.add_theme_stylebox_override("panel",skin)
	chip.size = Vector2(minf(feed_width(),ceilf(text_weight(text)*15+26)),32)
	feed.add_child(chip)
	var line := hud.label(text,11,Color("ebeef5")); line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.clip_text = true; chip.add_child(line)
	var seconds := .65 if user else maxf(1.65,text_weight(text)*.09+.65)
	strips.append({"widget":chip,"start":duration,"duration":seconds,"user":user,"y":0.0})
	duration += seconds; chip.hide()

func _poll(delta: float,blocked: bool) -> void:
	if hud.game.paused or blocked: return
	bubble_remaining = maxf(0,bubble_remaining-delta)
	if bubble_remaining == 0: bubble = ""
	var state := hud.game.state
	var message := ""
	if hud.game.is_campaign():
		var ev: Dictionary = state.campaign.event
		var spec := hud.game.navigation.campaign
		var urgent := WarAdvisorRules.danger(state,spec)
		if urgent and not memory.get("danger",false) and ev.status == "active": message = "后鼻屏障告急！先回防，再调援。"
		elif ev.wave != memory.get("wave",-1) and ev.wave > 0 and ev.status == "active": message = "第 %d 波病毒已入侵。点我查看防线建议。" % int(ev.wave)
		elif ev.secure > 0 and not memory.get("secure",false): message = "鼻腔已净化！继续稳守 %d 秒。" % int(spec.secureSeconds)
		else:
			for i in ev.zones.size():
				if ev.zones[i].control == 100 and memory.has("zones") and memory.zones[i] < 100: message = str(spec.zones[i].name)+"已完全夺回！"; break
		memory.danger = urgent; memory.wave = ev.wave; memory.secure = ev.secure > 0; memory.zones = []
		for z in ev.zones: memory.zones.append(z.control)
	intro += delta
	if not memory.get("introduced",false) and intro >= 1:
		memory.introduced = true
		if message.is_empty(): message = "指挥官，我是你的参谋小脑。人体情况由我汇报，行动由你决定。点击我，听取情况和建议。"
	if not message.is_empty():
		bubble = WarAdvisorRules.map_text(state,message); bubble_remaining = 8
		if not chatting: topic = ""; say(bubble)

func _process(delta: float) -> void:
	if hud == null: return
	var blocked := hud.menu.visible or hud.home.visible
	visible = not blocked
	hud.advisor.visible = not hud.home.visible
	hit.position = hud.advisor.position; hit.size = hud.advisor.size
	var anchor := hud.advisor.position+Vector2(0,hud.advisor.size.y+10)
	if hud.systemic_panel.visible and not hud.game.life.enabled(): anchor.x = hud.systemic_panel.get_rect().end.x+12
	anchor.x = minf(anchor.x,get_viewport_rect().size.x-minf(356,get_viewport_rect().size.x-24)-12)
	feed.position = anchor
	_poll(delta,blocked)
	hud.advisor.mood = "happy" if hud.game.is_campaign() and hud.game.state.campaign.event.status == "completed" else ("alert" if WarAdvisorRules.danger(hud.game.state,hud.game.navigation.campaign) else ("thinking" if topic == "defense" else "idle"))
	hud.advisor.speaking = false
	if blocked or not active: return
	# Original BrainUI reading advances in real time even when tactical time is paused.
	elapsed += maxf(0,delta)
	var latest := -1
	for i in strips.size():
		var strip := strips[i]
		if elapsed >= strip.start:
			latest = i
			if not strip.user and elapsed < strip.start+strip.duration-.25: hud.advisor.speaking = true
	var bottom := hud.battle.chip.position.y if hud.game.is_campaign() else hud.panel.position.y
	if hud.game.life.enabled():
		bottom = hud.life_dialogue.phone.position.y if get_viewport_rect().size.x < 720 else hud.zoom_tools.position.y-12
	var short_topics := hud.game.life.enabled() and get_viewport_rect().size.x < 720
	for i in 3: controls.get_child(i).text = ["人体","守卫","补给"][i] if short_topics else ["人体情况","守卫建议","援军补给"][i]
	var capacity := clampi(int((bottom-anchor.y-24-(38 if chatting else 0))/40),1,3)
	var first := maxi(0,latest-capacity+1)
	for i in strips.size():
		var strip := strips[i]
		var chip: Control = strip.widget
		var fade := 1.0 if chatting else clampf((duration+3.1+(i-first)*.16-elapsed)/.45,0,1)
		if i == first and latest >= capacity-1 and latest+1 < strips.size(): fade *= clampf((strips[latest+1].start-elapsed)/.22,0,1)
		chip.visible = i >= first and i <= latest and fade > 0
		if chip.visible:
			var age: float = elapsed-strip.start
			var enter := clampf(age/.32,0,1)
			strip.y = float((i-first)*40) if age <= delta else lerpf(strip.y,float((i-first)*40),1-exp(-14*delta))
			chip.position = Vector2(-24*pow(1-enter,3),strip.y); chip.modulate.a = minf(1,age/.22)*fade
	feed.show(); controls.visible = chatting
	controls.position = anchor+Vector2(0,mini(capacity,latest+1)*40+4)
	skip.visible = elapsed < duration
	if not chatting and elapsed > duration+3.5: active = false; feed.hide(); hud.advisor.speaking = false
