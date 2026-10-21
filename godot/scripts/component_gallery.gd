extends Control
## Standalone interactive specimen of the same controls used during gameplay.
var notice: Label

func _ready() -> void:
	get_window().title = "细胞战争 · 多面体组件试用"
	theme = WarUISkin.theme()
	var background := ColorRect.new()
	background.color = Color("fffbf4")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,32)
	scroll.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation",20)
	margin.add_child(body)
	body.add_child(_label("细胞指挥 · 组件试用",34,true))
	body.add_child(_label("奶油米色 / 可可棕 / 杏珊瑚 · 多面体切面与动态交互",16))
	var columns := HFlowContainer.new()
	columns.add_theme_constant_override("h_separation",24)
	columns.add_theme_constant_override("v_separation",24)
	body.add_child(columns)
	var left := _section("01  指令按钮",columns)
	var row := HBoxContainer.new(); left.add_child(row)
	for item in [["移动","move",""],["进攻","attackmove","primary"],["驻守","guard","sage"]]:
		var btn := WarCommandButton.new(); row.add_child(btn)
		btn.configure(item[0],item[1],item[2])
		var title: String = item[0]
		btn.pressed.connect(func(): notice.text = "已选择："+title)
	row = HBoxContainer.new(); left.add_child(row)
	for item in [["建造","build"],["撤退","retreat"],["不可用","stop"]]:
		var btn := WarCommandButton.new(); row.add_child(btn)
		btn.configure(item[0],item[1]); btn.disabled = item[0] == "不可用"
		var title: String = item[0]
		btn.pressed.connect(func(): notice.text = "已选择："+title)
	left.add_child(_label("悬停、按下、禁用、键盘焦点",14))
	var resources := _section("02  资源与状态",columns)
	for item in [["氧气量",320,WarUISkin.SAGE],["葡萄糖量",640,WarUISkin.HONEY],["蛋白质量",280,WarUISkin.LILAC]]:
		var card := PanelContainer.new(); resources.add_child(card)
		card.add_theme_stylebox_override("panel",WarUISkin.panel(WarUISkin.CREAM,14,10))
		var content := HBoxContainer.new(); card.add_child(content)
		var title := _label(item[0],17); title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; content.add_child(title)
		var value := _label(str(item[1]),24)
		value.add_theme_font_override("font",WarUISkin.BUTTON); content.add_child(value)
		var rail := ProgressBar.new(); rail.value = 76; rail.show_percentage = false
		rail.custom_minimum_size = Vector2(70,5); rail.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fill := WarUISkin.panel(item[2],4,0); fill.set_border_width_all(0)
		rail.add_theme_stylebox_override("fill",fill); content.add_child(rail)
	var state := _section("03  信息卡与操作",columns)
	state.add_child(_label("白细胞 · 已选择 3 个",23,true))
	state.add_child(_label("生命值  320 / 320",16))
	var hp := ProgressBar.new(); hp.value = 86; hp.show_percentage = false; hp.custom_minimum_size.y = 7; state.add_child(hp)
	state.add_child(_label("框选细胞 → 点击目标 → 选择指令",15))
	var resume := Button.new(); resume.text = "继续游戏"; resume.custom_minimum_size.y = 48
	WarUISkin.apply_button(resume,"primary"); state.add_child(resume)
	resume.pressed.connect(func(): notice.text = "继续按钮已响应")
	var toggle := CheckButton.new(); toggle.text = "追加命令"; state.add_child(toggle)
	toggle.toggled.connect(func(value): notice.text = "追加命令："+("开启" if value else "关闭"))
	var bottom := HFlowContainer.new(); bottom.add_theme_constant_override("h_separation",24); body.add_child(bottom)
	var typography := _section("04  字体与提示",bottom)
	typography.custom_minimum_size.x = 420
	typography.add_child(_label("守住生命的防线",28,true))
	var sample := _label("进攻  建造  撤退  320 / 640",24)
	sample.add_theme_font_override("font",WarUISkin.BUTTON); typography.add_child(sample)
	typography.add_child(_label("标题：站酷快乐体\n按钮与数字：站酷庆科黄油体\n说明：MiSans，保留小字号辨识度",15))
	var preview := Button.new(); preview.text = "进入真实战场试用环形指令"; preview.custom_minimum_size.y = 48
	WarUISkin.apply_button(preview); typography.add_child(preview)
	preview.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main.tscn"))
	var ring := _section("05  点击式环形组件",bottom)
	ring.custom_minimum_size = Vector2(450,330)
	var space := Control.new(); space.custom_minimum_size = Vector2(420,310); ring.add_child(space)
	for i in 6:
		var action: Array = [["移动","move"],["进攻","attackmove"],["驻守","guard"],["撤退","retreat"],["停止","stop"],["建造","build"]][i]
		var btn := WarCommandButton.new(); space.add_child(btn)
		btn.configure(action[0],action[1],"primary" if i == 1 else "")
		var destination := Vector2(210,150)+Vector2.from_angle(-PI*.5+i*TAU/6)*108-btn.size*.5
		btn.reveal(Vector2(210,150)-btn.size*.5,destination,.12+i*.025)
		var title: String = action[0]
		btn.pressed.connect(func(): _demo_confirm(space,btn,title))
	var cancel := Button.new(); cancel.text = "×"; WarUISkin.apply_button(cancel)
	cancel.position = Vector2(188,128); cancel.size = Vector2(44,44); space.add_child(cancel)
	cancel.pressed.connect(func(): notice.text = "已取消")
	notice = _label("点击上面的组件试用",16)
	body.add_child(notice)
	_facet_all(self)

func _demo_confirm(space: Control,chosen: WarCommandButton,title: String) -> void:
	if space.get_meta("busy",false): return
	space.set_meta("busy",true)
	notice.text = "指令确认："+title
	var center := Vector2(210,150)
	var buttons: Array[WarCommandButton] = []
	var destinations: Array[Vector2] = []
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for child in space.get_children():
		if not child is WarCommandButton: continue
		var btn := child as WarCommandButton
		buttons.append(btn); destinations.append(btn.position)
		btn.settle(btn.position); btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if btn == chosen:
			tween.tween_property(btn,"scale",Vector2.ONE*1.08,.07)
			tween.tween_property(btn,"position",center-btn.size*.5,.23).set_delay(.07).set_ease(Tween.EASE_IN_OUT)
			tween.tween_property(btn,"scale",Vector2.ONE*.24,.23).from(Vector2.ONE*1.08).set_delay(.07)
			tween.tween_property(btn,"modulate:a",0.0,.08).set_delay(.25)
		else:
			tween.tween_property(btn,"position",btn.position.lerp(center-btn.size*.5,.45),.16)
			tween.tween_property(btn,"modulate:a",0.0,.13)
	tween.tween_callback(func():
		var ack := WarOrderPulse.new(); space.add_child(ack); ack.configure(center,chosen.action)).set_delay(.33)
	tween.tween_callback(func():
		for i in buttons.size():
			buttons[i].mouse_filter = Control.MOUSE_FILTER_STOP
			buttons[i].reveal(center-buttons[i].size*.5,destinations[i],i*.018)
		space.set_meta("busy",false)).set_delay(1.15)

func _section(title: String,parent: Node) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(320,0)
	panel.add_theme_stylebox_override("panel",WarUISkin.panel(WarUISkin.CREAM,18,18))
	parent.add_child(panel)
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation",14); panel.add_child(column)
	column.add_child(_label(title,20,true))
	return column

func _label(text: String,font_size: int,display := false) -> Label:
	var label := Label.new(); label.text = text
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_font_override("font",WarUISkin.DISPLAY if display else WarUISkin.BODY)
	label.add_theme_color_override("font_color",WarUISkin.INK)
	return label

func _facet_all(node: Node) -> void:
	for child in node.get_children():
		if child is PanelContainer: WarUISkin.facet_panel(child)
		_facet_all(child)
