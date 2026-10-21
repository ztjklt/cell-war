extends SceneTree
var failures: Array[String] = []
var checks := 0
var main

func check(value: bool,message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("FAIL ",message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1440,900)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main); current_scene = main
	main.set_process(false); main.set_process_unhandled_input(false)
	main.open_infection_preview()
	var model: WarInfectionZones = main.world.infections
	check(model.data.zones.size() == 12,"all twelve organs have certified footprints and routes")
	check(model.data.deferredOrgans.is_empty(),"no organ admitted without certified placements")
	check(model.data.surfaceStyle == "flat-modular","ground is a reusable flat material")
	check(FileAccess.get_sha256("res://assets/image/infection-ground-20261020/v2-flat/ground-tile.png") == "eb197be6b60a5e77c690ce35a8ebf57c9a440de3a6c8ab4a8e72d9fdbb218de6","approved upper color tile remains unchanged")
	var ports: Array = WarData.read("checkpoints").ports
	var placement_count := 0
	for zone in model.data.zones:
		check(FileAccess.get_sha256("res://data/navigation/"+zone.organ+"_siege.json") == zone.geometrySha256,"geometry unchanged: "+zone.organ)
		var side := float(zone.placements[0].side)
		check(float(zone.area) > 3*side*side,"large range exceeds small footprint: "+zone.organ)
		for i in zone.placements.size():
			placement_count += 1
			model.select(zone.organ,i)
			var patch := model.placement()
			var rect := model.footprint()
			var corners := [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]
			for j in 4:
				check(main.game.navigation.organ_at(corners[j],"siege") == zone.organ,"footprint organ: "+patch.id)
				check(main.game.navigation.clear_segment(corners[j],corners[(j+1)%4],0,"siege"),"footprint edge: "+patch.id)
			for port in ports:
				for key in ["a","b"]:
					var at := WarData.source_to_world(port[key])
					var closest := Vector2(clampf(at.x,rect.position.x,rect.end.x),clampf(at.y,rect.position.y,rect.end.y))
					check(at.distance_to(closest)+.001 >= float(model.data.gateGap),"whole patch avoids gate: "+patch.id)
			var length := 0.0
			for j in range(1,patch.route.size()):
				var a := WarData.point(patch.route[j-1]); var b := WarData.point(patch.route[j])
				length += a.distance_to(b)
				if not main.game.navigation.clear_segment(a,b,0,"siege"): printerr("SEGMENT ",patch.id," ",a," -> ",b)
				check(main.game.navigation.clear_segment(a,b,0,"siege"),"attack route segment: "+patch.id)
			check(length+.05 >= float(model.data.minimumRoute),"advance distance: "+patch.id)
	check(placement_count >= 24,"multiple approved positions per organ")
	var snapshot: Dictionary = main.game.snapshot()
	main.infection_preview.show_organ("lung_r")
	main.infection_preview.next_placement()
	check(model.placement_index == 1,"switch legal position")
	main.infection_preview.toggle_range()
	check(not main.world.assisted and model.ground_visible,"pure view retains infection ground")
	main.infection_preview.toggle_ground()
	check(not model.ground_visible,"healthy-ground comparison")
	check(main.game.snapshot() == snapshot,"preview does not alter simulation/save state")
	check(main.game.paused,"preview paused")
	var footprint := model.footprint()
	var seed := model.paving_seed()
	model.paving_variation += 1
	check(model.paving_seed() != seed and model.footprint() == footprint,"different paving layouts preserve certified ground footprint")
	if DisplayServer.get_name() != "headless":
		main.infection_preview.show_organ("lung_r")
		await settle(); await capture("lung-r-range")
		check(model.last_ground_drawn and model.last_range_drawn,"native assisted range and GPT texture")
		main.infection_preview.toggle_range(); await capture("lung-r-pure")
		check(model.last_ground_drawn and not model.last_range_drawn,"native pure view retains only ground")
		main.infection_preview.closeup(); await settle(); await capture("lung-r-ground")
		model.paving_variation += 1; await capture("lung-r-paving-alternate")
		main.infection_preview.toggle_ground(); await capture("lung-r-healthy")
		check(not model.last_ground_drawn,"native healthy ground restored")
		for zone in model.data.zones:
			if zone.organ == "lung_r": continue
			main.infection_preview.show_organ(zone.organ)
			await settle(); await capture(zone.organ+"-range")
			check(model.last_ground_drawn and model.last_range_drawn,"native floor and candidate range: "+zone.organ)
	DirAccess.make_dir_recursive_absolute("res://test-output/infection-preview")
	var out := FileAccess.open("res://test-output/infection-preview/checks.json",FileAccess.WRITE)
	out.store_string(JSON.stringify({"checks":checks,"failures":failures,"placements":placement_count,"native":DisplayServer.get_name() != "headless","previewOnly":true,"gateGap":model.data.gateGap},"  "))
	print("INFECTION PREVIEW ",checks-failures.size(),"/",checks,"; failures ",failures)
	main.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)

func settle() -> void:
	var began := Time.get_ticks_msec()
	var stable := 0
	while Time.get_ticks_msec()-began < 12000:
		await process_frame
		var loaded: bool = main.world.textures.get_texture(main.world.infections.data.texture) != null
		loaded = loaded and main.world.textures.get_texture(main.world.infections.data.edgeTexture) != null
		for entry in main.world.visible_tiles:
			if main.world.textures.get_texture(entry.spec.resource) == null: loaded = false
		stable = stable+1 if loaded else 0
		if stable >= 16: return
	check(false,"native textures finish loading")

func capture(name: String) -> void:
	main.camera.force_update_scroll()
	await process_frame; await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://test-output/infection-preview")
	root.get_texture().get_image().save_png("res://test-output/infection-preview/"+name+".png")
