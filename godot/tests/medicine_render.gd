extends "res://tests/opening_flow.gd"
## Real purchase/deployment plus existing medicine art through the native world renderer.
const MED := "fever_pain_relief"
const MED_OUT := "res://test-output/medicines/"
var explicit_staging := not OS.get_cmdline_user_args().has("--released")

func drawn(key: String) -> bool:
	return main.world.drawn_specs.get(4,[]).any(func(item): return item.get("medicine","")==key)

func capture_medicine(name: String,key: String) -> void:
	await frames(12)
	check(drawn(key),"native renderer draws approved medicine atlas for "+key)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(MED_OUT+"native-"+name+".png")

func legal_point(actor: Dictionary,distance: float) -> Vector2:
	var g: WarSimulation=main.game
	for index in 48:
		var point:=WarData.point(actor)+Vector2.from_angle(index*TAU/48.0)*distance
		if not g.navigation.point_allowed(point,0,MED): continue
		if g.navigation.clear_segment(WarData.point(actor),point,0,MED) and g.navigation.movement_clear(WarData.point(actor),point,MED,1): return point
	return Vector2.INF

func finish_render() -> void:
	var report: Dictionary={"passed":checks-failures.size(),"total":checks,"failures":failures,"explicitServiceStaging":explicit_staging,"engine":Engine.get_version_info().string,"renderer":DisplayServer.get_name()}
	FileAccess.open(MED_OUT+"render.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("MEDICINE NATIVE RENDER ",checks-failures.size(),"/",checks," ",failures)
	main.queue_free(); await frames(3)
	quit(0 if failures.is_empty() else 1)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(MED_OUT)
	if DisplayServer.get_name()=="headless":
		check(false,"native rendering requires an actual display server"); await finish_render(); return
	root.size=Vector2i(1440,900)
	main=load("res://scenes/main.tscn").instantiate()
	root.add_child(main); current_scene=main; main.set_process(false)
	main.start("life")
	var g: WarSimulation=main.game
	g.medicine_supply.staging=explicit_staging
	g.paused=true
	var red: Dictionary=g.units().filter(func(e): return e.kind=="worker" and e.faction==1)[0]
	g.selected.assign([int(red.id)]); g.order(red,{"kind":"hold"})
	check(g.medicine_supply.queue_purchase().ok,"native fixture queues actual purchase")
	g.paused=false; g.update(.1)
	check(g.medicine_supply.queue_deployment(int(red.id)).ok,"native fixture queues actual nearby deployment")
	g.update(.1)
	var helpers:=g.units().filter(func(e): return e.kind==MED)
	if not check(helpers.size()==1,"native purchase deploys one actual helper"):
		await finish_render(); return
	var helper: Dictionary=helpers[0]
	main.world.record_draws=true
	main.focus(main.world.display_point(WarData.point(helper)),64)
	for clip in WarMedicineHelpers.data().clips.values(): main.world.textures.request(clip.path)
	await frames(120)
	g.selected.clear(); g.paused=true
	await click(screen(WarData.point(helper)))
	check(g.selected==[int(helper.id)],"physical mouse click selects the real tablet silhouette")
	check(main.world.cell_rotation(helper).angle==0,"native medicine sprite stays upright")
	var point:=legal_point(helper,2.0)
	check(point!=Vector2.INF,"native helper has a legal movement segment")
	if point!=Vector2.INF:
		g.issue("move",point); g.paused=false
		for i in 6: g.update(.05)
		await capture_medicine("move","move")
	g.issue("hold"); g.update(.1)
	point=legal_point(helper,4.0)
	check(point!=Vector2.INF,"native helper has a legal firing segment")
	if point==Vector2.INF: await finish_render(); return
	var target:=g.spawn("virus",2,point)
	target.vesselLane=0; g.order(target,{"kind":"hold"})
	for i in 12:
		g.update(.05)
		if helper.has("medicineAttack"): break
	check(helper.has("medicineAttack"),"native helper reaches actual windup state")
	await capture_medicine("attack","attack")
	for i in 20:
		g.update(.05)
		if not g.medicine_helpers.bubbles.projectiles().is_empty(): break
	check(not g.medicine_helpers.bubbles.projectiles().is_empty(),"native render observes actual travelling projectile")
	await capture_medicine("flight","flight")
	var hp:=float(target.hp)
	for i in 12:
		g.update(.05)
		if target.hp<hp: break
	check(target.hp<hp,"native rendered bubble reaches actual damage")
	await capture_medicine("impact","impact")
	g.combat.damage(target,helper,1,true,"native_hit_fixture"); g.update(.2)
	await capture_medicine("hit","hit")
	g.combat.damage({},helper,helper.hp,true,"native_death_fixture"); g.update(.2)
	await capture_medicine("death","death")
	for i in 30: g.update(.05)
	await capture_medicine("death-end","death")
	for i in 25: g.update(.05)
	check(g.corpses.all(func(e): return e.kind!=MED),"native medicine death finishes and retires")
	await finish_render()
