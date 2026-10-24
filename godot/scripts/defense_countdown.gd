class_name WarDefenseCountdown
extends Control
## GPT-painted card and cell illustration; all information remains native/live UI.
const CARD = preload("res://assets/ui/left-lung/task-card.png")
const DUO = preload("res://assets/ui/left-lung/cell-duo.png")
const INK := Color("57334f")
const LILAC := Color("aa7bcb")
const ALERT := Color("b94f54")
const CLEAN := Color("689a82")
var hud: WarHUD
var artwork: TextureRect
var characters: TextureRect
var caption: Label
var digits: Label
var detail: Label
var note: Label
var progress: ProgressBar
var previous := -1
var bounce: Tween
var _view_size := Vector2.ZERO
var _phase := ""
var _fill: StyleBoxFlat
var _stage := ""
var _cell_origin := Vector2.ZERO
var _motion_clock := 0.0
var _celebration_lift := 0.0
var _arrival: Tween
var _celebration: Tween
var _meter_tween: Tween
var _meter_target := -1.0

func setup(owner: WarHUD) -> void:
	hud = owner
	name = "DefenseCountdown"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 40
	# Atlas regions exclude only the generated PNGs' near-transparent outer padding.
	# The originals and their alpha channels are preserved byte-for-byte.
	artwork = _art("TaskCard",CARD,Rect2(78,90,2040,582))
	characters = _art("CellTeam",DUO,Rect2(34,246,1220,825))
	characters.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	caption = _label("Stage",WarUISkin.BODY)
	digits = _label("Objective",WarUISkin.DISPLAY)
	detail = _label("Requirements",WarUISkin.BODY)
	note = _label("Guidance",WarUISkin.BODY)
	note.add_theme_color_override("font_color",Color("876576"))
	progress = ProgressBar.new(); progress.name = "LiveProgress"
	progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress.min_value = 0; progress.max_value = 1; progress.step = .001
	progress.show_percentage = false
	var rail := WarUISkin.panel(Color("ebdce8"),4,0); rail.set_border_width_all(0)
	_fill = WarUISkin.panel(LILAC,4,0); _fill.set_border_width_all(0)
	progress.add_theme_stylebox_override("background",rail)
	progress.add_theme_stylebox_override("fill",_fill)
	add_child(progress)
	hide()

func _art(title: String,source: Texture2D,region: Rect2) -> TextureRect:
	var texture := AtlasTexture.new(); texture.atlas = source; texture.region = region
	var node := TextureRect.new(); node.name = title; node.texture = texture
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(node)
	return node

func _label(title: String,font: Font) -> Label:
	var node := Label.new(); node.name = title
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_theme_font_override("font",font)
	node.add_theme_color_override("font_color",INK)
	add_child(node)
	return node

func _layout(view: Vector2) -> void:
	# Toolbar height changes after its flow container has laid out the buttons.
	# Read its live bounds even when the viewport itself has not changed.
	var top := maxf(150,hud.toolbar.get_global_rect().end.y+8)
	position = Vector2((view.x-minf(448,view.x-24))*.5,top)
	if view == _view_size: return
	_view_size = view
	var narrow := view.x < 720
	size = Vector2(minf(448,view.x-24),144 if narrow else 148)
	pivot_offset = size*.5
	artwork.position = Vector2.ZERO; artwork.size = size
	characters.position = Vector2(2,28) if narrow else Vector2(6,14)
	characters.size = Vector2.ONE*(92 if narrow else 122)
	_cell_origin = characters.position
	characters.pivot_offset = characters.size*.5
	var left := 96.0 if narrow else 134.0
	var width := size.x-left-26
	caption.position = Vector2(left,14); caption.size = Vector2(width,18)
	digits.position = Vector2(left,30); digits.size = Vector2(width,34)
	detail.position = Vector2(left,65); detail.size = Vector2(width,18)
	progress.position = Vector2(left,87); progress.size = Vector2(width,5)
	note.position = Vector2(left,94); note.size = Vector2(width,18)
	caption.add_theme_font_size_override("font_size",11 if narrow else 12)
	detail.add_theme_font_size_override("font_size",12 if narrow else 13)
	note.add_theme_font_size_override("font_size",11)

func _process(delta: float) -> void:
	if hud == null: return
	var defense: Dictionary = hud.game.state.get("lungDefense",{})
	var phase: String = defense.get("phase","")
	visible = phase in ["preparing","infected","defended"] and not hud.home.visible
	if not visible:
		previous = -1
		_stage = ""
		return
	_layout(get_viewport_rect().size)
	var narrow := _view_size.x < 720
	if phase != _phase:
		_phase = phase; previous = -1
		if bounce != null: bounce.kill()
		digits.scale = Vector2.ONE
	_animate_cells(delta)
	digits.add_theme_font_size_override("font_size",(30 if narrow else 36) if phase == "preparing" else (18 if narrow else 24))
	# The large animated clock needs a taller row than the battle headlines.
	# Shrink the Label again after changing phases; Godot retains its old size.
	digits.size.y = digits.get_minimum_size().y
	detail.position.y = 83 if phase == "preparing" else 65
	progress.position.y = 107 if phase == "preparing" else 87
	note.visible = phase != "preparing"
	digits.add_theme_color_override("font_color",INK)
	progress.visible = true
	_fill.bg_color = LILAC
	var pause := " · 暂停" if hud.game.paused else ""
	var organ := hud.game.scenarios.defense_name()
	if phase == "preparing":
		_present("preparing")
		caption.text = organ+"防线 · 准备"+pause
		detail.text = "建造分裂兵巢，训练白细胞"
		note.text = "准备结束后，病毒将进入左肺" if organ == "左肺" else "准备结束后，病毒将进入右肺"
		var total := maxf(1,float(defense.preparationSeconds))
		var remaining := maxi(0,ceili(total-float(defense.elapsed)))
		_meter(clampf((total-float(defense.elapsed))/total,0,1))
		var color := ALERT if remaining <= 10 else INK
		digits.add_theme_color_override("font_color",color)
		_fill.bg_color = ALERT if remaining <= 10 else LILAC
		if remaining != previous:
			previous = remaining
			digits.text = "%02d:%02d" % [remaining/60,remaining%60]
			_bounce()
		return
	if phase == "defended":
		_present("defended")
		caption.text = organ+"防线 · 守卫成功"
		digits.text = organ+"已夺回"
		detail.text = "本场战斗胜利"
		if defense.has("finishedAt"):
			var finished := int(defense.finishedAt)
			detail.text += " · %02d:%02d" % [finished/60,finished%60]
		note.text = "感染已净化，进度随存档保留"
		_meter(1); _fill.bg_color = CLEAN
		return
	var group: Dictionary = hud.game.state.get("influenzaColonies",{}).get("groups",{}).get(defense.get("colony",""),{})
	var cleanup: Dictionary = group.get("purification",{})
	var status: String = cleanup.get("status","")
	var enemies := 0 if group.is_empty() else hud.game.influenza.members(group).size()+int(group.get("pending",0))
	var forts := 0 if group.is_empty() else hud.game.influenza.forts(group).size()
	# Surviving colony viruses outside the infection floor do not block occupation.
	# Pending births/forts still prevent a fresh outbreak's initial waiting state
	# from briefly displaying a purification instruction before its first update.
	if status == "purifying" or (int(group.get("pending",0)) == 0 and forts == 0 and status in ["waiting_red","waiting_white"]):
		_present(status)
		caption.text = organ+"防线 · 协同净化"+pause
		var red := int(cleanup.get("red",0)); var white := int(cleanup.get("white",0))
		detail.text = "红细胞 %d/%d · 白细胞 %d/%d" % [red,WarInfectionPurification.RED_REQUIRED,white,WarInfectionPurification.WHITE_REQUIRED]
		if status == "purifying":
			digits.text = "净化 %d / %d 秒" % [int(cleanup.elapsed),int(WarInfectionPurification.HOLD_SECONDS)]
			_meter(WarInfectionPurification.progress(group))
			_fill.bg_color = CLEAN
			note.text = "保持红白细胞在感染地板内"
		else:
			_meter(0)
			var missing := "红细胞" if status == "waiting_red" else "白细胞"
			digits.text = "还需要"+missing
			note.text = "带"+missing+"进入感染地板"
		return
	_present("combat")
	_meter(0)
	caption.text = organ+"防线 · 清除感染"+pause
	digits.text = "清除病毒和要塞"
	detail.text = "病毒 %d · 要塞 %d" % [enemies,forts]
	note.text = "摧毁要塞，阻止病毒继续增殖"
	progress.visible = false

func _animate_cells(delta: float) -> void:
	# Presentation clock only: never feed decorative time into the simulation.
	_motion_clock += minf(maxf(delta,0),.1)
	var breath := sin(_motion_clock*TAU/3.6)
	characters.position = _cell_origin+Vector2(0,sin(_motion_clock*1.65)*2.2-_celebration_lift)
	characters.scale = Vector2(1+breath*.015,1-breath*.01)
	characters.rotation = sin(_motion_clock*.8)*.018

func _present(stage: String) -> void:
	if stage == _stage: return
	_stage = stage
	if _arrival != null: _arrival.kill()
	if _celebration != null: _celebration.kill()
	if _meter_tween != null: _meter_tween.kill()
	_meter_target = -1; _celebration_lift = 0
	modulate.a = 0; scale = Vector2.ONE*.975
	_arrival = create_tween().set_parallel(true)
	_arrival.tween_property(self,"modulate:a",1.0,.18)
	_arrival.tween_property(self,"scale",Vector2.ONE,.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if stage == "defended":
		_celebration = create_tween()
		_celebration.tween_property(self,"_celebration_lift",9.0,.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_celebration.tween_property(self,"_celebration_lift",0.0,.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

func _meter(value: float) -> void:
	if is_equal_approx(value,_meter_target): return
	if _meter_tween != null: _meter_tween.kill()
	# Phase changes, interruptions and victory are exact immediately. Small
	# fixed-step updates ease between samples without altering the real timer.
	if _meter_target < 0 or value <= 0 or value >= 1:
		progress.value = value
	else:
		_meter_tween = create_tween()
		_meter_tween.tween_property(progress,"value",value,.14)
	_meter_target = value

func _bounce() -> void:
	if bounce != null: bounce.kill()
	digits.pivot_offset = Vector2(digits.size.x*.25,digits.size.y*.5)
	digits.scale = Vector2(1.08,.9)
	bounce = create_tween()
	bounce.tween_property(digits,"scale",Vector2(.98,1.06),.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	bounce.tween_property(digits,"scale",Vector2.ONE,.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
