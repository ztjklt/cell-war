extends SceneTree
var main: Node2D
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("FAIL ",message)

func frames(count := 6) -> void:
	for i in count: await process_frame

func capture(name: String) -> void:
	await frames()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test-output/purification/"+name+".png")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Use a native rendering window for purification_capture.gd"); quit(1); return
	root.size = Vector2i(1440,900)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main); current_scene = main
	main.set_process(false); main.set_process_unhandled_input(false)
	main.start("fullbody"); main.game.paused = true
	main.game.state.influenzaColonies = {"version":1,"groups":{}}
	var group: Dictionary = main.game.influenza.start_outbreak("lung_r",0,10)
	group.pending = 0
	var center := WarData.point(group.center)
	for item in [["worker",Vector2(-2,0)],["spear",Vector2(2,0)]]:
		var unit: Dictionary = main.game.spawn(item[0],1,center+item[1])
		unit.vesselLane = 0
		main.game.order(unit,{"kind":"hold"})
	main.focus(center,32)
	main.world.assisted = true
	main.game.influenza.after_step(10)
	var surface: WarInfectionSurface = main.world.infection_surface
	var began := Time.get_ticks_msec()
	while Time.get_ticks_msec()-began < 12000:
		await process_frame
		if surface.live_surfaces.has(group.id) and surface.live_surfaces[group.id].visible and main.world.visible_tiles.all(func(tile): return main.world.textures.get_texture(tile.spec.resource) != null): break
	check(not main.world.infections.enabled and main.game.paused,"runtime paving does not activate the paused art-preview model")
	check(surface.live_surfaces.has(group.id) and surface.visible,"native runtime infection patch is visible")
	if not surface.live_surfaces.has(group.id):
		finish(); return
	var node: MeshInstance2D = surface.live_surfaces[group.id]
	check(node.get_parent() == surface and surface.get_parent() == main.world.infection_canvas,"runtime patch stays on the retained independent infection canvas")
	check(node.mesh != null and node.material is ShaderMaterial,"native live patch uses approved textured shader")
	check(node.texture == main.world.textures.get_texture(WarData.read("infection_zones").texture),"native live patch reuses approved color tile")
	check(is_equal_approx(node.modulate.a,1),"active infection ground has full configured visibility")
	DirAccess.make_dir_recursive_absolute("res://test-output/purification")
	await capture("active-50-percent")
	main.world.assisted = false
	await frames()
	check(node.is_visible_in_tree(),"normal unassisted view retains the actual infection ground")
	await capture("active-pure-view")
	main.world.assisted = true
	main.world.infection_canvas.hide()
	check(not node.is_visible_in_tree(),"infection canvas can be hidden independently")
	main.world.infection_canvas.show()
	main.game.influenza.after_step(10)
	main.game.influenza.after_step(1.5)
	await frames()
	check(group.cleared and is_equal_approx(node.modulate.a,.5),"native ground follows saved half-fade progress")
	await capture("fading-half")
	main.game.influenza.after_step(1.5)
	await frames()
	check(not surface.visible and not surface.live_surfaces.has(group.id),"native purified patch is removed while organ layer remains")
	await capture("purified")
	# Two source decals coexist; preview and normal view remain distinct.
	main.game.influenza.start_outbreak("lung_r",0,10)
	var second: Dictionary = main.game.influenza.start_outbreak("lung_r",1,10)
	main.focus((center+WarData.point(second.center))*.5,2)
	await frames(30)
	check(surface.live_surfaces.size() == 2,"two live patches have separate meshes and material instances")
	if surface.live_surfaces.size() == 2:
		var nodes := surface.live_surfaces.values()
		check(nodes[0].material != nodes[1].material,"independent fade uniforms for different colonies")
	await capture("multiple-infections")
	main.world.infections.select("lung_r")
	main.world.infections.enabled = true
	await frames()
	check(surface.mesh != null and surface.visible and surface.live_surfaces.values().all(func(child): return not child.visible),"explicit art preview keeps its original single footprint")
	main.world.infections.enabled = false
	main.start("systemic")
	await frames()
	check(not surface.visible and surface.live_surfaces.is_empty(),"legacy encounter has no live infection floor")
	finish()

func finish() -> void:
	DirAccess.make_dir_recursive_absolute("res://test-output/purification")
	var file := FileAccess.open("res://test-output/purification/native-checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"native":true},"  "))
	print("PURIFICATION NATIVE ",checks-failures.size(),"/",checks)
	main.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
