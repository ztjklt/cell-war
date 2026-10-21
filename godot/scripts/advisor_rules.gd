class_name WarAdvisorRules
extends RefCounted
## BrainAdvisor.lua, including its authored wording and map-name substitutions.

static func danger(state: Dictionary,spec: Dictionary) -> bool:
	if not state.get("campaign") is Dictionary: return false
	var zones: Array = state.campaign.event.zones
	for index in WarData.array(spec.get("failureZones",[zones.size()])):
		var zone: Dictionary = zones[int(index)-1]
		if zone.control < 60 or zone.hostile > 0: return true
	return false

static func territory_status(z: Dictionary) -> String:
	if z.get("contested",false): return "争夺中"
	if z.control >= 100: return "免疫控制"
	if z.control <= -100: return "病毒控制"
	if z.friendly > 0: return "解除感染" if z.owner == 2 else "夺回中"
	if z.hostile > 0: return "正在失守" if z.owner == 1 else "感染中"
	return "免疫控制 · 部分受损" if z.owner == 1 else ("病毒控制 · 部分清除" if z.owner == 2 else "中立")

static func map_text(state: Dictionary,text: String) -> String:
	if not state.get("campaign") is Dictionary or state.campaign.map_id != "trachea_01": return text
	return text.replace("后鼻屏障","下段屏障").replace("鼻腔","气管").replace("咽喉、双肺","双肺").replace("可沿上下鼻道绕开鼻甲，也可从黄色膜口走血管侧路。","沿气管纵向通道移动，先稳住下段屏障，再向上段入口反攻。")

static func reply(game: WarSimulation,topic: String) -> Dictionary:
	if game.life.enabled():
		var s := game.life.state()
		if topic == "supply": return {"title":"生活与补给","text":"生活金钱 %d，和体内葡萄糖、氧气分别管理。每个生活周期正常收入 80，基本支出 60。药品助手尚未开放，现可用金钱改善饮食和休整。" % int(s.money)}
		if topic == "defense": return {"title":"守卫建议","text":"身体机能 %.1f。控制已出现的感染能减少机能损耗；休息和生活调整能逐步恢复。病毒仍需由细胞实际清除，机能回升不会让敌人自动消失。" % float(s.function)}
		return {"title":"人体情况","text":"现在 %.1f 岁，金钱 %d，身体机能 %.1f / 100。%s。生活联系每隔 2–3 分钟出现一次，在桌上的手机里和外部人员对话。" % [float(s.age),int(s.money),float(s.function),str(s.lastChange)]}
	return reply_data(game.state,game.entities(),game.economy.stock(1,"food"),game.navigation.campaign,topic)

static func reply_data(state: Dictionary,entities: Array,food: float,spec: Dictionary,topic: String) -> Dictionary:
	var count := 0
	var hurt := 0
	for e in entities:
		if float(e.get("hp",0)) > 0 and e.faction == 1 and e.category == "unit":
			count += 1
			if e.hp < e.maxHp*.4: hurt += 1
	if not state.get("campaign") is Dictionary:
		if topic == "supply": return {"title":"胞群补给","text":"当前可用葡萄糖 %d。让工细胞采集并运回胞巢，安排培养床生产，远征前检查补给。旧记录的沙盒没有鼻腔调援功能。" % floori(food)}
		if topic == "defense": return {"title":"稳态建议","text":"胞群目前有 %d 名细胞，其中 %d 名生命低于 40%%。受伤单位适合回营休整。保留工细胞和生产建筑，逐步发展，再组织进攻。" % [count,hurt]}
		var day := floori(float(state.time)/float(WarData.config().Data.DAY))+1
		var fraction := fposmod(float(state.time),float(WarData.config().Data.DAY))/float(WarData.config().Data.DAY)
		var season := (day-1)/8%4
		var phase := "活跃" if fraction < .6 else ("过渡" if fraction < .75 else "休息")
		return {"title":"人体内域情况","text":"我是小脑，你的脑细胞联络员。这份记录处于沙盒，第 %d 天，当前是「%s」的%s期。你有 %d 名细胞。温度、饱食与精神会影响它们的状态；这是游戏中的胞群稳态。" % [day,WarData.config().Data.seasons[season],phase,count]}
	var c: Dictionary = state.campaign
	var ev: Dictionary = c.event
	var r: Dictionary = c.reinforcements
	var text := ""
	var title := ""
	if topic == "supply":
		var waiting := 0
		for q in WarData.array(r.queue): waiting += int(q.remaining)
		text = "补给现有 %d / %d。" % [int(r.supply),int(spec.supply.max)]
		if ev.status != "active": text += "这次战斗已经结束，调援暂停。"
		else:
			text += "每 %d 秒回复 1 点；每次消耗 %d 点调来 %d 个白细胞，%d 秒后抵达，冷却 %d 秒。" % [int(spec.supply.period),int(spec.supply.cost),int(spec.supply.count),int(spec.supply.arrival),int(spec.supply.cooldown)]
			text += "当前还需冷却 %d 秒。" % ceili(r.cooldown) if r.cooldown > 0 else ("现在补给不足，先守住防线等待回复。" if r.supply < spec.supply.cost else "现在可以点击底部「调援 +2」。")
		if waiting > 0: text += "已有 %d 名援军调入中。" % waiting
		title = "援军补给"
	elif topic == "defense":
		if ev.status == "failed": text = "后鼻屏障已完全失守。这次防守失败了。关闭对话后可重试事件，恢复事件开始时的部队与补给。"
		elif ev.status == "completed": text = "鼻腔已经夺回，部队和已完成记录会保留。咽喉、双肺、肠道与血流的后续事件尚未开放。"
		elif danger(state,spec): text = "优先回防关键区域！那里有病毒进入或控制正在下降。让白细胞清除敌军、留在区域内夺回控制，补给充足时调援。完全失守会结束本次事件。"
		elif ev.secure > 0: text = "全部区域已净化，正在稳固：%d / %d 秒。维持区域完全控制，防止病毒重新进入。" % [floori(ev.secure),int(spec.secureSeconds)]
		elif ev.phase == "counterattack": text = "三波入侵都已启动。守住后方，逐步清除病毒并夺回三块区域。全部控制后还需稳定 %d 秒；双方同在区域时争夺进度会暂停。" % int(spec.secureSeconds)
		else: text = "先守住后鼻屏障，再反攻入口黏膜。选择白细胞，点击进攻目标；可沿上下鼻道绕开鼻甲，也可从黄色膜口走血管侧路。"
		text += "当前有 %d 名免疫细胞，%d 名生命低于 40%%。" % [count,hurt]
		title = "防线建议"
	else:
		text = "好消息，鼻腔已夺回！" if ev.status == "completed" else ("鼻腔防线失守了。" if ev.status == "failed" else "人体的鼻腔正在遭遇病毒入侵。")
		text += "入侵已启动 %d / %d 波。" % [int(ev.wave),spec.waves.size()]
		for i in ev.zones.size(): text += str(spec.zones[i].name)+"："+territory_status(ev.zones[i])+"。"
		if ev.status == "active" and ev.wave < spec.waves.size(): text += "下一波约 %d 秒后开始。" % maxi(0,ceili(spec.waves[int(ev.wave)].at-ev.elapsed))
		text += "其余器官的事件尚未开放；当前没有它们的感染监测数据。"
		title = "人体当前情况"
	return {"title":title,"text":map_text(state,text)}
