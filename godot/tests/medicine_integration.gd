extends SceneTree
const MED := "fever_pain_relief"
var checks := 0
var failures: Array[String] = []
var staging := not OS.get_cmdline_user_args().has("--released")

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("FAIL ", message)

func near(a: float, b: float, message: String, epsilon := .0001) -> void:
	check(absf(a-b) <= epsilon, message)

func fixture() -> WarSimulation:
	var g := WarSimulation.new(); g.start("life"); g.paused = true
	g.medicine_supply.staging = staging
	var red: Dictionary = g.units().filter(func(e): return e.kind == "worker" and e.faction == 1)[0]
	g.selected.assign([int(red.id)]); g.order(red, {"kind":"hold"})
	return g

func worker(g: WarSimulation) -> Dictionary: return g.entity(g.selected[0])

func ticks(g: WarSimulation, count: int) -> void:
	for i in count: g.update(.1)

func buy(g: WarSimulation, quantity := 1) -> Dictionary:
	var result := g.medicine_supply.queue_purchase(MED, quantity)
	check(result.ok, "real medicine purchase can queue")
	g.paused = false; g.update(.1)
	return result

func deploy(g: WarSimulation) -> Dictionary:
	var result := g.medicine_supply.queue_deployment(int(worker(g).id))
	check(result.ok, "selected natural red cell has a legal local deployment")
	if not result.ok: return {}
	g.paused = false; g.update(.1)
	var units := g.units().filter(func(e): return e.kind == MED)
	return units[-1] if not units.is_empty() else {}

func enemy_near(g: WarSimulation, source: Dictionary, distance := 3.0) -> Dictionary:
	for index in 24:
		var p := WarData.point(source)+Vector2.from_angle(float(index)*TAU/24.0)*distance
		if not g.navigation.clear_segment(WarData.point(source),p,0,MED): continue
		if not g.navigation.movement_clear(WarData.point(source),p,MED,1): continue
		var e := g.spawn("virus",2,p)
		if e.is_empty(): continue
		e.vesselLane = 0; g.order(e,{"kind":"hold"}); return e
	return {}

func accessible(g: WarSimulation, actor: Dictionary, distance := 2.0) -> Vector2:
	var origin := WarData.point(actor)
	for index in 48:
		var point := origin + Vector2.from_angle(float(index)*TAU/48.0)*distance
		if not g.navigation.point_allowed(point,int(actor.vesselLane),actor.kind): continue
		if not g.navigation.clear_segment(origin,point,int(actor.vesselLane),actor.kind): continue
		if not g.navigation.movement_clear(origin,point,actor.kind,int(actor.faction)): continue
		if g.entities().any(func(e): return e.hp>0 and e.id!=actor.id and WarData.point(e).distance_to(point)<WarData.radius(e.kind)+WarData.radius(actor.kind)+.1): continue
		return point
	return Vector2.INF

func test_external_income() -> void:
	var g := fixture()
	var life := g.life.state()
	# Controlled event fixture; settlement still uses the actual life choice API.
	life.serial+=1; life.pending={"id":"late_work","token":life.serial,"offeredAt":life.activeElapsed}
	var money := int(life.money); var earned := int(life.earned)
	check(g.life.choose(int(life.serial),1),"actual external character event choice settles")
	check(int(life.money)==money+60 and int(life.earned)==earned+60,"external event income enters the existing life wallet")
	buy(g)
	check(int(life.money)==money+60-80 and g.medicine_supply.count()==1,"medicine spends external-event wallet money through the same account")
	g.dispose()

func test_purchase_deploy() -> void:
	var g := fixture(); var s := g.medicine_supply
	check(g.life.enabled() and s.count()==0 and s.state().runId.length()==24,"new life run has empty persisted inventory and world namespace")
	var initial_money := int(g.life.state().money); var initial_spent := int(g.life.state().spent)
	var before := g.snapshot()
	var quote := s.quote_purchase()
	check(quote.ok and quote.unitPrice==80 and g.snapshot()==before,"purchase quote is read-only and uses first-pass price80")
	check(not s.quote_purchase("vaccine").ok and not s.quote_purchase("antibiotic").ok,"other medicines remain unavailable")
	var request := s.queue_purchase()
	check(request.ok,"purchase request uses official simulation command queue")
	g.state.commands.append(g.state.commands[-1].duplicate(true))
	g.update(.2)
	check(s.count()==0 and int(g.life.state().money)==initial_money,"pause defers duplicate queued purchases without deduction")
	g.paused = false; g.update(.1)
	check(s.count()==1 and int(g.life.state().money)==initial_money-80,"resume settles duplicated request exactly once")
	check(int(g.life.state().spent)==initial_spent+80,"purchase updates existing life spending ledger")
	var placement := s.quote_deployment(int(worker(g).id))
	check(placement.ok,"natural unchanged starter tissue can provide a certified nearby point")
	if not placement.ok: g.dispose(); return
	var pending := s.queue_deployment(int(worker(g).id))
	check(pending.ok,"deployment can queue without consuming inventory")
	check(s.cancel_queued(pending.request).get("cancelled",false) and s.count()==1,"cancel pending deployment leaves inventory intact")
	g.update(.1)
	check(g.units().filter(func(e): return e.kind==MED).is_empty(),"cancelled request cannot create helper on resume")
	g.paused = true
	pending = s.queue_deployment(int(worker(g).id)); g.state.commands.append(g.state.commands[-1].duplicate(true))
	var cached := int(g.life.state().money); g.update(.2)
	check(s.count()==1,"paused deployment is not consumed early")
	g.paused = false; g.update(.1)
	var actors := g.units().filter(func(e): return e.kind==MED)
	check(actors.size()==1 and s.count()==0,"duplicate deployment request consumes one item and creates one helper")
	check(int(g.life.state().money)==cached,"deployment does not charge money a second time")
	if actors.is_empty(): g.dispose(); return
	var helper: Dictionary = actors[0]; var red := worker(g)
	check(helper.medicineOrgan==g.navigation.organ_at(WarData.point(red),"worker") and helper.vesselLane==0,"helper enters the selected red cell's real tissue organ")
	check(WarData.point(helper).distance_to(WarData.point(red))<=3.001 and g.navigation.clear_segment(WarData.point(red),WarData.point(helper),0,MED) and g.navigation.movement_clear(WarData.point(red),WarData.point(helper),MED,1),"deployment is local and has a certified tissue segment")
	check(WarData.point(helper).distance_to(WarData.point(red))>WarData.radius(MED)+WarData.radius("worker"),"helper does not overlap deployment worker")
	near(helper.hp,60,"real helper health60")
	near(WarData.spec(MED).speed,2.3,"real helper movement config2.3")
	check(float(helper.medicineRemaining)>89.8 and float(helper.medicineRemaining)<=90,"real helper starts with90 simulation seconds")
	check(WarSave.validate(g.snapshot()).is_empty(),"live purchased/deployed world passes actual save validation")
	g.dispose()

func test_failure_paths() -> void:
	var g := fixture(); var s := g.medicine_supply
	g.life.state().money = 79
	check(not s.queue_purchase().ok and s.count()==0 and g.life.state().money==79,"insufficient money cannot queue or become negative")
	g.life.state().money = 80
	var first := s.queue_purchase(); var second := s.queue_purchase()
	g.paused=false; g.update(.1)
	check(first.ok and second.ok and s.count()==1 and g.life.state().money==0,"two distinct queued requests revalidate funds; only affordable one executes")
	check(not s.quote_purchase(MED,0).ok and not s.quote_purchase(MED,-1).ok,"zero and negative quantities rejected")
	var invalid := s.reserve_request()
	g.submit_player({"action":"medicine_buy","medicine":MED,"quantity":1.5,"unitPrice":80,"request":invalid})
	g.update(.1)
	check(s.count()==1 and g.life.state().money==0,"fractional raw queued purchase is not truncated into a charge")
	var red := worker(g); g.selected.clear()
	check(not s.quote_deployment(int(red.id)).ok,"unselected red cell cannot deploy")
	g.selected.assign([int(red.id)]); red.vesselLane=1
	check(not s.quote_deployment(int(red.id)).ok,"projected vessel red cell cannot deploy into underlying organ")
	red.vesselLane=0; red.faction=2
	check(not s.quote_deployment(int(red.id)).ok,"enemy red cell cannot consume player inventory")
	red.faction=1
	var pending := s.queue_deployment(int(red.id)); red.hp=0
	g.update(.1)
	check(pending.ok and s.count()==1 and g.units().filter(func(e): return e.kind==MED).is_empty(),"red cell death before execution fails without inventory consumption")
	g.dispose()
	g=fixture(); s=g.medicine_supply; buy(g)
	red=worker(g)
	var blockers := 0
	for index in 120:
		var point := g.medicine_helpers.find_placement(red)
		if not point.ok: break
		var blocker := g.spawn("b_cell",1,WarData.point(point))
		if blocker.is_empty(): break
		blocker.vesselLane=0; g.order(blocker,{"kind":"hold"}); blockers+=1
	check(blockers>0 and not s.quote_deployment(int(red.id)).ok,"legal nearby sites can be filled by existing live units")
	var token := s.reserve_request(); var result := s.deploy(token,int(red.id),[int(red.id)])
	check(not result.ok and s.count()==1,"full landing region fails atomically")
	g.dispose()

func test_real_attack_and_movement() -> void:
	var g := fixture(); buy(g); var helper := deploy(g)
	if helper.is_empty(): g.dispose(); return
	var target := enemy_near(g,helper)
	check(not target.is_empty(),"real virus fixture fits the same certified organ")
	if target.is_empty(): g.dispose(); return
	var shots: Array = []
	var receive := func(event):
		if event.kind=="medicine_shot": shots.append(event.duplicate(true))
	g.combat_event.connect(receive)
	var initial_hp := float(target.hp)
	g.update(.1)
	check(helper.has("medicineAttack") and shots.is_empty() and target.hp==initial_hp,"automatic AI starts a real windup without instant damage")
	var release_at := float(helper.medicineAttack.releaseAt)
	while float(g.state.time)+.100001<release_at: g.update(.1)
	check(shots.is_empty(),"attack has not emitted before approved frame7 timing")
	for i in 8:
		g.update(.1)
		if not shots.is_empty(): break
	check(shots.size()==1 and float(shots[0].time)>=release_at-.0001 and float(shots[0].time)<release_at+.101,"first eligible simulation tick emits exactly once at release time")
	check(not g.medicine_helpers.bubbles.projectiles().is_empty(),"real helper creates an independent travelling bubble")
	for i in 10:
		g.update(.1)
		if target.hp<initial_hp: break
	near(target.hp,initial_hp-4,"actual native combat takes first-pass4 damage once")
	near(g.combat.multiplier(target,"moveMultiplier"),.7,"formal movement multiplier consumes medicine slow once")
	check(not g.effects.is_empty(),"medicine impact uses native damage feedback")
	var origin := WarData.point(target)
	var destination := accessible(g,target,1.8)
	check(destination != Vector2.INF,"real slowed virus has a certified test segment")
	if destination != Vector2.INF:
		# Separate otherwise identical world avoids the live target blocking its control.
		var control_game := WarSimulation.new()
		var control_state := g.snapshot(); control_state.medicineRuntime.bubbles.slows.clear()
		control_game.restore(control_state)
		var control := control_game.entity(int(target.id))
		for e in [target,control]:
			e.path=[{"p":origin,"lane":0},{"p":destination,"lane":0}]; e.pathIndex=1; e.pathGoal=destination
			e.pathPending=false; e.pathFailed=false; e.movementSpeed=0.0; e.lastTravel=g.state.time
		g.go(target,destination,.1); control_game.go(control,destination,.1)
		var slow_distance := WarData.point(target).distance_to(origin)
		var normal_distance := WarData.point(control).distance_to(origin)
		check(normal_distance>0 and absf(slow_distance/normal_distance-.7)<.02,"actual go displacement is slowed relative to same-speed control")
		control_game.dispose()
		target.x=origin.x; target.y=origin.y; target.path=[]; target.pathGoal=Vector2(INF,INF); target.pathPending=false
	for i in 25:
		g.update(.1)
		if shots.size()>=2 and target.hp<=initial_hp-8: break
	check(shots.size()>=2 and target.hp<=initial_hp-8,"automatic repeat cast produces further real damage")
	near(g.combat.multiplier(target,"moveMultiplier"),.7,"repeated formal hits refresh rather than multiply slow")
	g.combat.damage({},helper,helper.hp,true,"test_death")
	ticks(g,25)
	near(g.combat.multiplier(target,"moveMultiplier"),1,"slow expires in main simulation after attacks stop")
	check(g.medicine_supply.count()==0,"death does not refund consumed inventory")
	g.combat_event.disconnect(receive); g.dispose()

func test_orders_and_interruption() -> void:
	var g := fixture(); buy(g); var helper := deploy(g)
	if helper.is_empty(): g.dispose(); return
	g.selected.assign([int(helper.id)])
	var origin := WarData.point(helper)
	var point := accessible(g,helper)
	check(point!=Vector2.INF,"natural deployed helper has a legal player-command destination")
	if point==Vector2.INF: g.dispose(); return
	g.issue("attackmove",point)
	g.update(.1)
	var destination := WarData.point(helper.orders[0]) if not helper.orders.is_empty() else point
	for i in 100:
		g.update(.1)
		if helper.orders.is_empty(): break
	check(helper.orders.is_empty() and WarData.point(helper).distance_to(destination)<.15 and WarData.point(helper).distance_to(origin)>.5,"actual issued attackmove reaches and finishes its specified waypoint without an enemy")
	point=accessible(g,helper,1.5)
	check(point!=Vector2.INF,"guard fixture has a legal destination")
	if point==Vector2.INF: g.dispose(); return
	g.issue("guard",point); ticks(g,25)
	check(not helper.orders.is_empty() and helper.orders[0].kind=="guard" and WarData.point(helper).distance_to(point)<.15,"actual guard reaches and retains its post")
	var target := enemy_near(g,helper)
	check(not target.is_empty(),"guard fixture has an actual same-layer enemy")
	if target.is_empty(): g.dispose(); return
	var hp:=float(target.hp); var shots: Array=[]
	var receive:=func(event):
		if event.kind=="medicine_shot": shots.append(event.duplicate(true))
	g.combat_event.connect(receive)
	for i in 35:
		g.update(.1)
		if shots.size()>=2 and target.hp<=hp-8: break
	check(shots.size()>=2 and target.hp<=hp-8,"guard at its post actually fires and damages a real enemy")
	if shots.size()>=2: near(float(shots[1].time)-float(shots[0].time),1.2,"guard keeps fixed1.2-second shot cadence",.101)
	# A fresh move order must cancel windup, then suppress shooting during travel.
	g.issue("hold"); g.update(.1)
	for i in 20:
		g.update(.1)
		if helper.has("medicineAttack") and not helper.medicineAttack.released: break
	check(helper.has("medicineAttack") and not helper.medicineAttack.released,"interruption fixture reaches an actual pre-release windup")
	var count:=shots.size()
	point=accessible(g,helper,2.0)
	if point!=Vector2.INF:
		g.issue("move",point); ticks(g,12)
		check(shots.size()==count,"actual move cancels pending shot and suppresses fire during travel")
	else: check(false,"interruption fixture has a legal travel segment")
	g.issue("hold"); g.update(.1)
	for i in 25:
		g.update(.1)
		if helper.has("medicineAttack") and not helper.medicineAttack.released: break
	count=shots.size()
	g.combat.damage(target,helper,1,true,"test_hit_interrupt"); ticks(g,5)
	check(shots.size()==count,"native hit interrupts the pre-release cast without extra bubble")
	g.combat_event.disconnect(receive); g.dispose()
	# Fresh actual combat fixture: emitted projectile survives its source's death.
	g=fixture(); buy(g); helper=deploy(g)
	if helper.is_empty(): g.dispose(); return
	target=enemy_near(g,helper,4.0)
	check(not target.is_empty(),"source-death fixture has a legal live target")
	if target.is_empty(): g.dispose(); return
	shots.clear(); g.combat_event.connect(receive)
	for i in 30:
		g.update(.1)
		if not g.medicine_helpers.bubbles.projectiles().is_empty(): break
	check(not g.medicine_helpers.bubbles.projectiles().is_empty(),"death fixture has a genuinely emitted bubble")
	hp=float(target.hp); count=shots.size()
	g.combat.damage({},helper,helper.hp,true,"test_death"); ticks(g,10)
	check(target.hp<hp and shots.size()==count,"emitted bubble completes native hit after source death with no further shots")
	g.combat_event.disconnect(receive); g.dispose()

func test_shapes_and_animation() -> void:
	var g := fixture(); buy(g); var helper := deploy(g)
	if helper.is_empty(): g.dispose(); return
	var radius:=WarData.radius(MED)
	var hull:=WarCellShape.normalized(helper,"",0,"hull")
	check(hull.size()>=8 and hull!=WarCellShape.normalized(worker(g),"",0,"hull"),"medicine owns a static tablet hull distinct from the worker")
	check(Array(hull).all(func(p): return p.length()<=1.001),"tablet contact hull fits the configured physical radius")
	for heading in [-2.1,-.4,0.0,1.2,PI]:
		helper.moveHeading=heading; helper.weaponHeading=heading
		near(WarCellShape.pose(helper,12.0,true).angle,0,"contact stays upright at heading "+str(heading))
	var clips: Dictionary=WarMedicineHelpers.data().clips
	for key in ["move","attack","hit","death"]:
		check(clips[key].durations.size()==16 and WarCellShape.normalized(helper,key,15,"outline").size()>=3,"approved16-frame clip and real selection outline available for "+key)
	helper.hitTime=g.state.time
	check(WarMedicineHelpers.sample(helper,g.state.time,0,false).key=="hit","native hit state chooses actual approved hit clip")
	helper.hp=0; helper.died=g.state.time
	check(WarMedicineHelpers.sample(helper,g.state.time+.2,0,true).key=="death","native death chooses actual approved death clip")
	check(WarMedicineHelpers.sample(helper,g.state.time+3,0,true).get("hidden",false),"completed death animation retires its visual")
	g.dispose()

func test_save_world_and_lifetime() -> void:
	var g := fixture(); var s := g.medicine_supply
	var queued := s.queue_purchase(); var run_id := str(s.state().runId)
	check(WarSave.write(g,1)==OK,"paused pending medicine command saves through actual file API")
	g.paused=false; g.update(.1)
	check(s.count()==1,"pending command executes after first save")
	check(WarSave.read_slot(g,1)==OK,"pending purchase reloads from actual file")
	g.medicine_supply.staging=staging; g.paused=true
	check(s.count()==0 and str(s.state().runId)==run_id and g.state.commands.size()==1,"file restore retains pre-payment inventory and pending identity")
	g.paused=false; g.update(.1)
	check(s.count()==1 and int(g.life.state().money)==220,"restored pending request pays once")
	var restored_red: Dictionary = g.units().filter(func(e): return e.kind=="worker" and e.faction==1)[0]
	g.selected.assign([int(restored_red.id)])
	var helper := deploy(g)
	if helper.is_empty(): g.dispose(); return
	var target := enemy_near(g,helper,4.0)
	if target.is_empty(): g.dispose(); return
	for i in 12:
		g.update(.1)
		if not g.medicine_helpers.bubbles.projectiles().is_empty(): break
	check(not g.medicine_helpers.bubbles.projectiles().is_empty(),"save fixture contains genuinely in-flight bubble")
	var helper_id := int(helper.id); var target_id := int(target.id)
	check(WarSave.write(g,2)==OK,"helper cast flight and inventory save together")
	var snapshot := g.snapshot()
	var loaded := WarSave.read_slot(g,2)
	var restored := g.snapshot()
	check(loaded==OK and restored.medicineSupply==snapshot.medicineSupply and restored.medicineRuntime==snapshot.medicineRuntime,"whole-world file roundtrip preserves medicine inventory requests and flight")
	var old_actor: Dictionary = snapshot.entities[str(helper_id)]
	var new_actor: Dictionary = restored.entities[str(helper_id)]
	check(new_actor.medicineAttack==old_actor.medicineAttack and new_actor.medicineRemaining==old_actor.medicineRemaining and new_actor.hp==old_actor.hp and new_actor.x==old_actor.x and new_actor.y==old_actor.y,"file restore preserves pending cast lifetime health and actual helper location")
	g.medicine_supply.staging=staging; target=g.entity(target_id); helper=g.entity(helper_id)
	var hp := float(target.hp); ticks(g,4)
	check(target.hp<hp,"restored flight resumes to a native hit")
	var before_money := int(g.life.state().money)
	var duplicate := s.purchase(queued.request,MED,1,80)
	check(duplicate.ok and s.count()==0 and int(g.life.state().money)==before_money,"paid pre-save request cannot replay money or inventory gain")
	var bad := g.snapshot(); bad.medicineSupply.inventory[MED] = -1
	check(not WarSave.validate(bad).is_empty(),"negative inventory rejected")
	bad=g.snapshot(); bad.medicineSupply.purchased+=1
	check(not WarSave.validate(bad).is_empty(),"inventory conservation mismatch rejected")
	bad=g.snapshot(); bad.entities[str(helper_id)].medicineRemaining=INF
	check(not WarSave.validate(bad).is_empty(),"nonfinite remaining helper time rejected")
	bad=g.snapshot(); bad.medicineSupply.receipts["999999"]={}
	check(not WarSave.validate(bad).is_empty(),"corrupt transaction history rejected")
	bad=g.snapshot(); bad.medicineSupply.inventory[MED]=-1
	var live := g.snapshot()
	FileAccess.open(WarSave.path(3),FileAccess.WRITE).store_string(JSON.stringify({"schema":WarSave.SCHEMA,"mode":g.mode,"snapshot":bad},"",true,true))
	check(WarSave.read_slot(g,3)==ERR_FILE_CORRUPT and g.snapshot()==live,"corrupt real save leaves live world intact")
	var stale := s.reserve_request(); g.start("life"); g.medicine_supply.staging=staging
	check(s.count()==0 and str(s.state().runId)!=run_id and g.medicine_helpers.bubbles.projectiles().is_empty(),"new life world clears inventory and old flights")
	check(not s.purchase(stale,MED,1,80).ok and int(g.life.state().money)==300,"previous-world request cannot spend in new world")
	g.start("cell_test")
	check(not s.enabled() and not s.queue_purchase().ok and not g.state.has("medicineSupply"),"legacy nonlife modes do not acquire medicine economy")
	g.dispose()
	g=fixture(); buy(g); helper=deploy(g)
	if helper.is_empty(): g.dispose(); return
	helper_id=int(helper.id); var remaining:=float(helper.medicineRemaining)
	g.paused=true; g.speed=2; ticks(g,10)
	near(helper.medicineRemaining,remaining,"pause freezes actual helper lifetime")
	g.paused=false; ticks(g,5)
	near(helper.medicineRemaining,remaining-1,"2x main simulation consumes one second over five0.1s updates")
	g.speed=1
	for i in 920:
		g.update(.1)
		if g.entity(helper_id).is_empty(): break
	check(g.entity(helper_id).is_empty() and g.medicine_supply.count()==0,"real90-second helper expires without refund")
	g.dispose()

func run() -> void:
	WarSave.directory="user://test-saves/medicine-integration"
	test_external_income()
	test_purchase_deploy()
	test_failure_paths()
	test_real_attack_and_movement()
	test_orders_and_interruption()
	test_shapes_and_animation()
	test_save_world_and_lifetime()
	var report: Dictionary={"passed":checks-failures.size(),"total":checks,"failures":failures,"staging":staging,"engine":Engine.get_version_info().string}
	DirAccess.make_dir_recursive_absolute("res://test-output/medicines")
	FileAccess.open("res://test-output/medicines/integration.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("MEDICINE INTEGRATION ",checks-failures.size(),"/",checks," ",failures)
	quit(0 if failures.is_empty() else 1)
