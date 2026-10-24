class_name WarWorldView
extends Node2D

var game: WarSimulation
var camera: Camera2D
var textures := WarTextures.new()
var art: Dictionary
var campaign_art: Dictionary = {}
var campaign_tiles: Array = []
var visible_tiles: Array = []
var _layer := 0
var layer: int:
	get: return _layer
	set(value):
		_blend_from = layer_weights.duplicate()
		_blend_started = _time
		_layer = clampi(value,0,6)
var _blend_from := [1.0,1.0,1.0,1.0,0.0]
var _blend_started := -100.0
var assisted := true
var presentation: Dictionary
var friendly_buildings: Dictionary
var heart := WarHeartDisplay.new()
var layer_weights := [1.0,1.0,1.0,1.0,0.0]
const MODES := [[1,1,1,1,0],[1,1,1,.18,0],[.18,0,1,0,0],[.14,0,0,1,0],[.18,1,0,0,0],[1,0,0,0,0],[1,1,1,1,1]]
const MODE_NAMES := ["全图","虚化","器官","血管","衬底","骨骼","原图"]
var show_paths := true
var show_labels := true
var _time := 0.0
var marker := Vector2(INF,INF)
var marker_time := -100.0
var marker_kind := "move"
const COMMAND_MARKERS := {
	"move": preload("res://assets/command_markers/move_3d.png"),
	"attack": preload("res://assets/command_markers/attack_3d.png"),
	"guard": preload("res://assets/command_markers/guard_3d.png")
}
var _font: Font
var legacy := WarLegacyArt.new()
var legacy_surface: WarLegacySurface
const LAYER_NODES := ["BodyBase","ConnectionUnderlay","Organs","BloodVessels","GameObjects","Orders","OriginalReference"]
var layer_nodes: Array[WarWorldLayer] = []
var _canvas: CanvasItem
## Opt-in evidence for native compositor tests; no recording in normal play.
var record_draws := false
var drawn_specs: Dictionary = {}
var _drawing_channel := 0
var infections := WarInfectionZones.new()
var infection_canvas: WarWorldLayer
var infection_surface: WarInfectionSurface

func setup(sim: WarSimulation,view_camera: Camera2D) -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	game = sim
	camera = view_camera
	for i in LAYER_NODES.size():
		var node: WarWorldLayer = get_node(LAYER_NODES[i])
		node.world = self
		layer_nodes.append(node)
	infection_canvas = get_node("InfectionGround")
	infection_canvas.world = self
	infection_surface = get_node("InfectionGround/StainPaving")
	infection_surface.world = self
	art = WarData.read("art")
	presentation = WarData.read("presentation")
	friendly_buildings = WarData.read("friendly_buildings").get("buildings",{})
	for spec in WarData.read("campaign_art"): campaign_art[spec.mode] = spec
	_font = load("res://assets/fonts/MiSans-Regular.ttf")
	game.state_replaced.connect(func(): marker = Vector2(INF,INF); marker_kind = "move"; infections.enabled = false)

func show_command_marker(point: Vector2,order_kind: String) -> void:
	if order_kind in ["stop","retreat","build"] or order_kind.begins_with("place:"):
		marker = Vector2(INF,INF)
		return
	marker = point
	marker_kind = "attack" if order_kind in ["attack","attackmove"] else ("guard" if order_kind in ["guard","hold"] else "move")
	marker_time = _time

func _process(delta: float) -> void:
	if game == null or game.state.is_empty(): return
	_time += delta
	var blend := WarHeartDisplay.smooth((_time-_blend_started)/.75)
	for i in 5:
		layer_weights[i] = lerpf(float(_blend_from[i]),float(MODES[layer][i]),blend)
	heart.sample(flow_time())
	textures.update()
	visible_tiles.clear()
	var zoom := camera.zoom.x
	var display_bounds := visible_world_rect()
	var bounds := display_bounds.grow(8.0/zoom)
	var stretch := get_viewport().get_stretch_transform().get_scale().x
	var density := zoom*2.0*stretch*DisplayServer.screen_get_scale()
	var legacy_from := (display_bounds.position-Vector2.ONE*4).floor().max(Vector2.ONE)
	var legacy_to := (display_bounds.end+Vector2.ONE*4).ceil().min(Vector2(game.state.get("mapWidth",2048),game.state.get("mapHeight",4096)))
	legacy.prepare(game,textures,Rect2(legacy_from,legacy_to-legacy_from),zoom/32)
	if legacy.enabled(game) and DisplayServer.get_name() != "headless":
		if legacy_surface == null:
			legacy_surface = WarLegacySurface.new(); add_child(legacy_surface); legacy_surface.setup(self)
		legacy_surface.sync(true)
	elif legacy_surface != null: legacy_surface.sync(false)
	for key in ["foundation","organs","blood"]:
		if game.is_campaign() or legacy.enabled(game) or game.mode == "cell_test": break
		var level := 4
		for candidate in [4,8,16,32]:
			level = candidate
			if candidate >= density: break
		while level > 4:
			var decoded := 0
			for tile in art[key]:
				var box: Array = tile.sourceBox
				var tile_rect := Rect2(WarData.source_to_world([box[0],box[1]]),Vector2(box[2]-box[0],box[3]-box[1])*2)
				if tile_rect.intersects(bounds):
					var pixels: Array = tile.levels[str(level)].pixelSize
					decoded += int(pixels[0])*int(pixels[1])*4
			if decoded <= int(presentation.budgets[key]): break
			level /= 2
		for tile in art[key]:
			var box: Array = tile.sourceBox
			var p := WarData.source_to_world([box[0],box[1]])
			var rect := Rect2(p,Vector2(box[2]-box[0],box[3]-box[1])*2)
			if not rect.intersects(bounds): continue
			var spec: Dictionary = tile.levels[str(level)]
			var base: Dictionary = tile.levels["4"]
			textures.request(base.resource)
			textures.request(spec.resource)
			var use: Dictionary = spec if textures.get_texture(spec.resource) else base
			visible_tiles.append({"spec":use,"group":key,"kind":tile.get("kind","")})
	if layer_weights[4] > .001: textures.request(art.reference.resource)
	for key in WarData.config().CellFrames.assets:
		textures.request(WarData.config().CellFrames.assets[key].path,true)
	textures.request(WarData.config().CellAnimationData.granule.path,true)
	textures.request(presentation.checkpoint,true)
	textures.request(presentation.buildings.resource,true)
	for spec in friendly_buildings.values(): textures.request(spec.texture,true)
	if game.state.get("influenzaColonies") is Dictionary:
		textures.request(WarInfluenzaColonies.data().texture)
	textures.request(presentation.resources.resource,true)
	if game.organ_resources.enabled():
		for spec in WarOrganResources.data().art.values(): textures.request(spec.texture,true)
	if infections.enabled:
		textures.request(infections.data.texture,true)
		textures.request(infections.data.edgeTexture,true)
	if game.medicine_helpers.enabled() and (not game.medicine_helpers.bubbles.projectiles().is_empty() or not game.medicine_helpers.impacts.is_empty()):
		textures.request(WarMedicineHelpers.data().clips.projectile.path)
	for e in game.units():
		if bounds.has_point(WarData.point(e)):
			var pose := animation(e,false)
			if pose.has("clip"): textures.request(pose.clip.path)
	for e in game.corpses:
		var pose := animation(e,true)
		if pose.has("clip"): textures.request(pose.clip.path)
	campaign_tiles.clear()
	if game.is_campaign() and campaign_art.has(game.mode):
		for tile in campaign_art[game.mode].tiles:
			var b: Array = tile.worldBox
			var rect := Rect2(Vector2(b[0],b[1]),Vector2(b[2]-b[0],b[3]-b[1]))
			if not rect.intersects(bounds): continue
			var high: String = tile.levels["8"] if zoom*DisplayServer.screen_get_scale() > 4 else tile.levels["4"]
			var base: String = tile.levels["4"]
			textures.request(base)
			textures.request(high)
			campaign_tiles.append({"rect":rect,"path":high if textures.get_texture(high) else base})
	for node in layer_nodes: node.queue_redraw()
	infection_canvas.queue_redraw()

func visible_world_rect() -> Rect2:
	var field := (get_parent() as WarDeskMapFrame).screen_rect()
	var inverse := get_viewport().get_canvas_transform().affine_inverse()
	return Rect2(inverse*field.position,field.size/camera.zoom)

func tile_channel(entry: Dictionary) -> int:
	return 3 if entry.group == "blood" else (2 if entry.group == "organs" else (0 if entry.kind == "base" else 1))

func tiles_for_layer(channel: int) -> Array:
	return visible_tiles.filter(func(entry): return tile_channel(entry) == channel)

func draw_layer(canvas: CanvasItem,channel: int) -> void:
	if game == null or game.state.is_empty(): return
	_canvas = canvas
	_drawing_channel = channel
	if record_draws: drawn_specs[channel] = []
	if channel == 7:
		infections.draw(canvas,self)
		return
	if channel == 6:
		_draw_spec(art.reference,float(layer_weights[4]))
		return
	if layer_weights[4] >= 1: return
	if channel < 4:
		_draw_terrain_layer(channel)
	elif channel == 4:
		_draw_game_objects()
	elif channel == 5:
		_draw_orders()

func _draw_terrain_layer(channel: int) -> void:
	if game.is_campaign():
		if channel == 0: _draw_campaign()
	elif legacy.enabled(game):
		if channel == 0:
			if legacy_surface != null: legacy_surface.draw(_canvas)
			else: legacy.draw_base_layer(_canvas,self)
		elif channel == 2: legacy.draw_overlays(_canvas,self)
	elif game.mode == "cell_test":
		if channel != 0: return
		_canvas.draw_rect(Rect2(Vector2(75,75),Vector2(70,70)),Color("735866"))
		for x in range(75,145,2):
			_canvas.draw_line(Vector2(x,75),Vector2(x,145),Color(.8,.7,.8,.05),.03,true)
		for y in range(75,145,2):
			_canvas.draw_line(Vector2(75,y),Vector2(145,y),Color(.8,.7,.8,.05),.03,true)
	else:
		for entry in tiles_for_layer(channel):
			_draw_spec(entry.spec,float(layer_weights[channel]))

func _draw_game_objects() -> void:
	_draw_resources()
	_draw_systemic_markers()
	var render_units := game.entities()
	render_units.sort_custom(func(a,b):
		if a.category != b.category: return a.category == "building"
		return int(a.id) < int(b.id))
	for e in render_units:
		if e.hp <= 0 or not game.visible(e): continue
		if e.category == "unit": _draw_unit(e,false)
		else: _draw_building(e)
	for e in game.corpses: _draw_unit(e,true)
	_draw_t_projectiles()
	for projectile in game.state.combatProjectiles:
		var q := WarData.point(projectile)
		if obscured(projectile,q): continue
		var p := display_point(q)
		if projectile.get("style","") == "granule":
			var clip: Dictionary = WarData.config().CellAnimationData.granule
			var texture := textures.get_texture(clip.path)
			if texture:
				var frame := atlas_frame(clip,flow_time()-float(projectile.get("born",0)),true)
				var angle := (display_point(q+Vector2(projectile.dx,projectile.dy))-p).angle()-PI
				_canvas.draw_set_transform(p,angle)
				var side := 22.0/32.0
				_canvas.draw_texture_rect_region(texture,Rect2(Vector2(-clip.anchorX,-clip.anchorY)*side/clip.frameSize,Vector2.ONE*side),Rect2(Vector2(frame%int(clip.columns),frame/int(clip.columns))*clip.frameSize,Vector2.ONE*clip.frameSize))
				_canvas.draw_set_transform(Vector2.ZERO)
		else: _canvas.draw_circle(p,maxf(1.0/camera.zoom.x,3.0/32),Color("df6aa5"))
	_draw_medicine_projectiles()

func _draw_medicine_projectiles() -> void:
	if not game.medicine_helpers.enabled(): return
	var clip: Dictionary = WarMedicineHelpers.data().clips.projectile
	var texture := textures.get_texture(clip.path)
	if texture == null: return
	var side := float(WarMedicineHelpers.data().projectileVisual.spriteSide)
	for bullet in game.medicine_helpers.bubbles.projectiles():
		var q := WarData.point(bullet)
		if obscured({"vesselLane":int(bullet.source.vesselLane)},q): continue
		var elapsed := game.medicine_helpers.bubbles.clock()-float(bullet.born)
		var index := int(floorf(maxf(0,elapsed)/.085))%4
		_canvas.draw_texture_rect_region(texture,Rect2(display_point(q)-Vector2.ONE*side*.5,Vector2.ONE*side),Rect2(Vector2(index%4,index/4)*512,Vector2.ONE*512))
		if record_draws: drawn_specs[4].append({"path":clip.path,"medicine":"flight"})
	for effect in game.medicine_helpers.impacts:
		var q := WarData.point(effect)
		if obscured(effect,q): continue
		var ratio := clampf((flow_time()-float(effect.born))/float(WarMedicineHelpers.data().projectileVisual.impactSeconds),0,.999)
		var index := 4+int(floorf(ratio*12))
		_canvas.draw_texture_rect_region(texture,Rect2(display_point(q)-Vector2.ONE*side*.5,Vector2.ONE*side),Rect2(Vector2(index%4,index/4)*512,Vector2.ONE*512))
		if record_draws: drawn_specs[4].append({"path":clip.path,"medicine":"impact"})
func _draw_orders() -> void:
	infections.draw_orders(_canvas,self)
	if show_paths and assisted:
		for id in game.selected:
			var e := game.entity(id)
			if e.is_empty(): continue
			var previous := WarData.point(e)
			for i in range(int(e.get("pathIndex",0)),e.path.size()):
				var next: Vector2 = e.path[i].p
				_canvas.draw_line(previous,next,Color(.45,.88,.77,.55),1.0/camera.zoom.x,true)
				previous = next
	if is_finite(marker.x) and _time-marker_time < 2.4:
		var age := _time-marker_time
		var enter := clampf(age/.15,0,1)
		var fade := clampf((2.4-age)/.48,0,1)
		var side := (82.0+sin(age*8.0)*3.0)/camera.zoom.x*lerpf(.82,1.0,enter)
		var texture: Texture2D = COMMAND_MARKERS.get(marker_kind,COMMAND_MARKERS.move)
		var p := display_point(marker)
		_canvas.draw_texture_rect(texture,Rect2(p-Vector2(side*.5,side*.78),Vector2.ONE*side),false,Color(1,1,1,fade))

func _draw_spec(spec: Dictionary,alpha: float) -> void:
	if alpha <= .001: return
	var texture := textures.get_texture(spec.resource)
	if texture == null: return
	if record_draws: drawn_specs[_drawing_channel].append({"path":spec.resource,"alpha":alpha})
	if not spec.resource == art.reference.resource and _heart_enabled() and heart.draw_spec(_canvas,spec,texture,alpha): return
	var box: Array = spec.sourceBox
	var pos := WarData.source_to_world([box[0],box[1]])
	_canvas.draw_texture_rect(texture,Rect2(pos,Vector2(box[2]-box[0],box[3]-box[1])*2),false,Color(1,1,1,alpha))

func animation(e: Dictionary,dead: bool) -> Dictionary:
	if e.kind == WarTCellRuntime.KIND: return game.t_cells.sample(e,flow_time())
	if e.kind == WarMedicineHelpers.KIND: return WarMedicineHelpers.sample(e,flow_time(),activity(e),dead)
	if e.kind == "dendritic_cell": return WarDendriticCells.sample(e,flow_time(),activity(e),dead)
	if e.kind == "b_cell": return WarBCells.sample(e,flow_time(),activity(e),dead)
	if e.kind == "scout": return WarPlatelets.sample(e,flow_time(),activity(e),dead)
	if e.kind == "virus": return WarInfluenzaAnimation.sample(e,flow_time(),activity(e),dead)
	var family := "red" if e.kind == "worker" else ("white" if e.kind in ["spear","neutrophil"] else "")
	if family.is_empty(): return {}
	var clips: Dictionary = WarData.config().CellAnimationData
	var time := flow_time()
	var key: String
	var elapsed := 0.0
	var loop := false
	if dead or e.has("deathTime"):
		key = family+"Death"
		elapsed = maxf(0,time-float(e.get("deathTime",e.get("died",time))))
		if not (elapsed < 1.3 or (elapsed >= 1.42 and elapsed < 1.56) or (elapsed >= 1.68 and elapsed < 1.82)): return {"hidden":true,"key":key,"frame":atlas_frame(clips[key],elapsed,false)}
	else:
		var hit := family+"Hit"
		var hit_started := float(e.get("cellHitStarted",e.get("hitTime",-100)))
		if time >= hit_started and time-hit_started < float(clips[hit].duration):
			key = hit; elapsed = time-hit_started
		elif family == "white" and e.has("shotTime") and time >= float(e.shotTime) and time-float(e.shotTime) < float(clips.whiteShoot.duration)/maxf(.01,float(e.get("shotSpeed",1))):
			key = "whiteShoot"; elapsed = (time-float(e.shotTime))*maxf(.01,float(e.get("shotSpeed",1)))
		elif family == "red" and e.has("cellWorkTime") and float(game.state.time)-float(e.cellWorkTime) < .15:
			key = "redBuild"; elapsed = time; loop = true
		else:
			key = "whiteMove" if family == "white" else ("redOxygen" if float(e.get("cargo",{}).get("oxygen",0)) > 0 else ("redGlucose" if float(e.get("cargo",{}).get("food",0)) > 0 else "redWalk"))
			loop = true
			elapsed = time+int(e.id)*.071 if activity(e) > .02 else 0.0
	var clip: Dictionary = clips[key]
	return {"key":key,"clip":clip,"frame":atlas_frame(clip,elapsed,loop),"family":family}

func _draw_unit(e: Dictionary,dead: bool) -> void:
	var p := WarData.point(e) if dead else unit_position(e)
	var physical := p
	p = display_point(p)
	if obscured(e,physical):
		if not dead:
			_draw_hidden(e,p)
			_draw_scan_mark(e,p,display_radius(e,physical),WarDendriticCells.concealed(e))
		return
	var radius := display_radius(e,physical)
	if not dead and e.faction != 1 and WarDendriticCells.concealed(e):
		_draw_scan_mark(e,p,radius,true)
		return
	if camera.zoom.x/32.0 < .14:
		if not dead:
			if e.kind != "worker" and game.selected.has(int(e.id)): _canvas.draw_circle(p,4.0/camera.zoom.x,Color("eaebb8"))
			_canvas.draw_circle(p,2.0/camera.zoom.x,faction_color(int(e.faction)))
			_draw_scan_mark(e,p,radius)
		return
	var rotation := cell_rotation(e)
	var angle: float = rotation.angle
	var mirror: bool = rotation.mirror
	var pose := animation(e,dead)
	if e.kind == WarTCellRuntime.KIND:
		_draw_t_cell(e,p,radius,mirror,pose,dead)
		return
	if pose.get("hidden",false): return
	if not pose.is_empty():
		var clip: Dictionary = pose.clip
		var texture := textures.get_texture(clip.path)
		if texture:
			var frame := int(pose.frame)
			var side := radius*2.0/float(clip.occupancy)
			var scale := side/float(clip.frameSize)
			_canvas.draw_set_transform(p,angle,Vector2(-1 if mirror else 1,1))
			var source := Rect2(Vector2(frame % int(clip.columns),frame / int(clip.columns))*float(clip.frameSize),Vector2.ONE*float(clip.frameSize))
			var rect := Rect2(-Vector2(float(clip.anchorX),float(clip.anchorY))*scale,Vector2.ONE*side)
			_canvas.draw_texture_rect_region(texture,rect,source,Color.WHITE)
			if record_draws and e.kind == WarMedicineHelpers.KIND: drawn_specs[4].append({"path":clip.path,"medicine":pose.key})
			_canvas.draw_set_transform(Vector2.ZERO)
			if game.selected.has(int(e.id)) and not dead: _draw_selection(e,p,radius,pose)
			_draw_health(e,p,radius,dead)
			if not dead: _draw_scan_mark(e,p,radius)
			return
	if e.kind == "virus":
		var asset: Dictionary = WarData.config().CellFrames.assets.influenza
		var texture := textures.get_texture(asset.path)
		if texture:
			var side := radius*2.0/float(asset.occupancy)
			_canvas.draw_set_transform(p,0,Vector2(-1 if mirror else 1,1))
			_canvas.draw_texture_rect(texture,Rect2(Vector2.ONE*-side*.5,Vector2.ONE*side),false)
			_canvas.draw_set_transform(Vector2.ZERO)
	else:
		var data: Dictionary = WarData.config().CellFrames
		var asset: Dictionary = data.assets[data.kinds.get(e.kind,"red")]
		var texture := textures.get_texture(asset.path)
		if texture:
			var side := radius*2.0/float(asset.occupancy)
			_canvas.draw_set_transform(p,angle,Vector2(-1 if mirror else 1,1)*float(rotation.pulse))
			_canvas.draw_texture_rect(texture,Rect2(Vector2.ONE*-side*.5,Vector2.ONE*side),false)
			_canvas.draw_set_transform(Vector2.ZERO)
		else:
			_canvas.draw_circle(p,radius,Color("de7487"),true,-1,true)
	if game.selected.has(int(e.id)) and not dead: _draw_selection(e,p,radius,pose)
	_draw_health(e,p,radius,dead)
	if not dead: _draw_scan_mark(e,p,radius)

func _draw_t_pose(p: Vector2,radius: float,mirror: bool,clip: Dictionary,frame: int,body: Dictionary,alpha := 1.0) -> void:
	var texture := textures.get_texture(clip.path)
	if texture == null: return
	var scale := radius*2/float(clip.occupancy)/float(clip.frameSize)
	var origin := Vector2(frame%int(clip.columns),frame/int(clip.columns))*float(clip.frameSize)
	var local := Rect2(Vector2.ZERO,Vector2.ONE*float(clip.frameSize)) if body.is_empty() else Rect2(body.x,body.y,body.w,body.h)
	_canvas.draw_set_transform(p,0,Vector2(-1 if mirror else 1,1))
	_canvas.draw_texture_rect_region(texture,Rect2((local.position-Vector2(clip.anchorX,clip.anchorY))*scale,local.size*scale),Rect2(origin+local.position,local.size),Color(1,1,1,alpha))
	_canvas.draw_set_transform(Vector2.ZERO)

func _draw_t_cell(e: Dictionary,p: Vector2,radius: float,mirror: bool,pose: Dictionary,dead: bool) -> void:
	var blink: Dictionary = WarTCells.data().clips.tBlink
	for ghost in pose.get("afterimages",[]):
		var age := maxf(0,flow_time()-float(ghost.time))
		var alpha := .45*clampf(1-age/float(WarTCells.data().blink.trailSeconds),0,1)
		_draw_t_pose(display_point(Vector2(ghost.x,ghost.y)),radius,mirror,blink,int(ghost.frame),{},alpha)
	if not pose.get("hidden",false): _draw_t_pose(p,radius,mirror,pose.clip,int(pose.frame),pose.get("bodyRect",{}))
	if not dead:
		if game.selected.has(int(e.id)): _draw_selection(e,p,radius,pose)
		_draw_health(e,p,radius,false); _draw_scan_mark(e,p,radius)
	if record_draws: drawn_specs[4].append({"path":pose.clip.path,"tCell":pose.key,"frame":pose.frame,"hidden":pose.get("hidden",false),"ghosts":pose.get("afterimages",[]).size(),"bodyCrop":not pose.get("bodyRect",{}).is_empty()})

func _draw_t_projectiles() -> void:
	var projectiles := game.t_cells.cells.projectiles()
	if projectiles.is_empty(): return
	var art: Dictionary = WarTCells.data().projectileArt
	var texture := textures.get_texture(art.path)
	if texture == null: return
	for b in projectiles:
		if obscured(b,WarData.point(b)): continue
		var r: Dictionary = art.atlasRect
		var width := float(WarTCells.data().radius)*2*float(art.widthInBodies)
		var height := width*float(r.h)/float(r.w)
		_canvas.draw_set_transform(display_point(WarData.point(b)),Vector2(b.dx,b.dy).angle()+PI)
		_canvas.draw_texture_rect_region(texture,Rect2(Vector2(-width,-height)*.5,Vector2(width,height)),Rect2(r.x,r.y,r.w,r.h))
		_canvas.draw_set_transform(Vector2.ZERO)
		if record_draws: drawn_specs[4].append({"path":art.path,"tKnife":b.id})

func _draw_scan_mark(e: Dictionary,p: Vector2,radius: float,underground := false) -> void:
	if not game.dendritic.marked(e,1): return
	var r := maxf(radius*1.35,8.0/camera.zoom.x)
	var length := r*.45
	var width := maxf(.025,1.4/camera.zoom.x)
	var color := Color("f5c87a")
	for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
		var q: Vector2 = p+corner*r
		_canvas.draw_line(q,q-Vector2(corner.x*length,0),color,width,true)
		_canvas.draw_line(q,q-Vector2(0,corner.y*length),color,width,true)
	if underground:
		_canvas.draw_circle(p,maxf(.055,2.0/camera.zoom.x),color,true,-1,true)
		_draw_label(p+Vector2(0,r+.25),"地下 · 已标记",Color("f5c87a"),10)

func _draw_health(e: Dictionary,p: Vector2,radius: float,dead: bool) -> void:
	if dead or not assisted or (not game.selected.has(int(e.id)) and e.hp >= e.maxHp): return
	var width := maxf(30.0/32.0,12.0/camera.zoom.x)
	var height := maxf(3.0/32.0,1.8/camera.zoom.x)
	var rect := Rect2(p+Vector2(-width*.5,-radius-maxf(9.0/32.0,6.2/camera.zoom.x)),Vector2(width,height))
	_canvas.draw_rect(rect,Color(.03,.04,.05,.8))
	_canvas.draw_rect(Rect2(rect.position,Vector2(width*float(e.hp)/float(e.maxHp),height)),Color("85d9b5") if e.faction == 1 else Color("e17d8d"))

func _draw_building(e: Dictionary) -> void:
	var p := WarData.point(e)
	var radius := float(WarData.spec(e.kind).get("size",2))*.5
	p = display_point(p)
	if e.kind == "flu_fortress":
		var spec := WarInfluenzaColonies.data()
		var texture := textures.get_texture(spec.texture)
		if texture:
			var side := radius*2/float(spec.occupancy)
			var anchor := Vector2(spec.anchor[0],spec.anchor[1])
			_canvas.draw_texture_rect(texture,Rect2(p-anchor*side,Vector2.ONE*side),false,Color(1,1,1,1 if e.get("complete",false) else .45+.4*float(e.progress)))
		if assisted and camera.zoom.x >= 4.0:
			var text := "流感要塞" if e.get("complete",false) else "施工 %d%%" % roundi(float(e.progress)*100)
			_draw_label(p+Vector2(0,radius*.65),text,Color("35475b"),12)
		_draw_health(e,p,radius,false)
		return
	if e.has("checkpointId"):
		var port: Dictionary = presentation.ports.get(e.checkpointId,{})
		if port.is_empty(): return
		p = display_point(WarData.source_to_world(port.a))
		var color := Color("e4a040") if e.get("isolated",false) else (Color("b25bcf") if e.get("breached",false) else Color("63aeb6"))
		if camera.zoom.x < .035*32:
			_canvas.draw_circle(p,2.4/camera.zoom.x,color)
			return
		var texture := textures.get_texture(presentation.checkpoint)
		if texture:
			var tangent := Vector2(port.tangent[0],port.tangent[1]) if port.has("tangent") else Vector2(port.a[0]-port.b[0],port.a[1]-port.b[1])
			var angle := (display_point(WarData.source_to_world([port.a[0]+tangent.x,port.a[1]+tangent.y]))-p).angle()+PI*.5
			var tint := Color("ffc06e") if e.get("isolated",false) else (Color("cc99eb") if e.get("breached",false) else Color.WHITE)
			_canvas.draw_set_transform(p,angle)
			_canvas.draw_texture_rect(texture,Rect2(-6.6,-6.6,13.2,13.2),false,tint)
			_canvas.draw_set_transform(Vector2.ZERO)
		if camera.zoom.x >= .12*32 and assisted:
			var width := maxf(24/camera.zoom.x,13.2*.6)
			var rect := Rect2(p+Vector2(-width*.5,-13.2*.6),Vector2(width,3/camera.zoom.x))
			_canvas.draw_rect(rect,Color("4b3748"))
			_canvas.draw_rect(Rect2(rect.position,Vector2(rect.size.x*e.hp/e.maxHp,rect.size.y)),color)
		return
	if friendly_buildings.has(e.kind):
		var spec: Dictionary = friendly_buildings[e.kind]
		var texture := textures.get_texture(spec.texture)
		if texture:
			var side := radius*2/float(spec.occupancy)
			var anchor := Vector2(spec.anchor[0],spec.anchor[1])*side
			_canvas.draw_texture_rect(texture,Rect2(p-anchor,Vector2.ONE*side),false,Color(1,1,1,1 if e.get("complete",false) else .45+.4*float(e.progress)))
	else:
		var texture := textures.get_texture(presentation.buildings.resource)
		var index := int(presentation.buildings.indices.get(e.kind,0))-1
		if texture and index >= 0:
			var side := building_radius(str(e.kind))*2.5/32*(1+sin(flow_time()*.9+int(e.id))*.014)
			var source_size := Vector2(texture.get_width(),texture.get_height())/4
			_canvas.draw_texture_rect_region(texture,Rect2(p-Vector2.ONE*side*.5,Vector2.ONE*side),Rect2(Vector2(index%4,index/4)*source_size,source_size),Color(1,1,1,1 if e.get("complete",true) else 145.0/255))
	_draw_health(e,p,radius,false)

func _draw_resources() -> void:
	var z := camera.zoom.x/32.0
	for resource in game.state.resources.values():
		var station: bool = resource.get("organSource",false)
		if (resource.amount <= 0 and not station) or not resource.get("resourcePoint",false): continue
		var p := display_point(WarData.point(resource))
		var color := Color("48bbcc") if resource.kind == "oxygen" else (Color("e1ae51") if resource.kind == "food" else Color("7599ca"))
		if z < .22:
			_canvas.draw_circle(p,2.5/camera.zoom.x,color)
			continue
		var radius := maxf(8/camera.zoom.x,float(resource.get("radius",2.2))*20/32)
		if station:
			var spec: Dictionary = WarOrganResources.data().art[resource.kind]
			var texture := textures.get_texture(spec.texture)
			if texture:
				var width := float(resource.get("radius",2.2))*2/float(spec.occupancy)
				var size := Vector2(width,width*texture.get_height()/float(texture.get_width()))
				var anchor := Vector2(spec.anchor[0],spec.anchor[1])*size
				_canvas.draw_texture_rect(texture,Rect2(p-anchor,size),false,Color("c6b7b7") if resource.get("contested",false) else Color.WHITE)
			var label: String = "敌军占用 · 停工" if resource.get("contested",false) else ("补充中 +%.1f/秒" % float(resource.regen) if resource.amount < resource.max else "库存充足")
			_draw_label(p+Vector2(0,radius*.65+11/camera.zoom.x),spec.name,Color("35475b"),11)
			_draw_label(p+Vector2(0,radius*.65+25/camera.zoom.x),"%d/%d · %s" % [int(resource.amount),int(resource.max),label],Color("54677b"),10)
			continue
		var polygon := PackedVector2Array()
		for i in 6: polygon.append(p+Vector2(cos((i+1)*PI/3)*radius,sin((i+1)*PI/3)*radius*.65))
		_canvas.draw_colored_polygon(polygon,Color(color,210.0/255))
		_draw_label(p+Vector2(0,4/camera.zoom.x),{"oxygen":"O₂","food":"G","wood":"P"}.get(resource.kind,""),Color.WHITE,int(clampf(14*z,10,18)))
		_draw_label(p+Vector2(0,radius*.65+11/camera.zoom.x),{"oxygen":"氧气采集点","food":"葡萄糖采集点","wood":"蛋白质采集点"}.get(resource.kind,""),Color("35475b"),11)
		_draw_label(p+Vector2(0,radius*.65+25/camera.zoom.x),"剩余 %d" % int(resource.amount),Color("54677b"),10)

func _draw_label(p: Vector2,text: String,color: Color,size: int) -> void:
	var scale := 1.0/camera.zoom.x
	_canvas.draw_set_transform(p,0,Vector2.ONE*scale)
	var width := _font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
	_canvas.draw_string(_font,Vector2(-width*.5,0),text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)
	_canvas.draw_set_transform(Vector2.ZERO)

func _draw_systemic_markers() -> void:
	var q := game.scenarios.systemic()
	if q.is_empty(): return
	var entries := [[q.front,Color("29c1c9"),"肺部补给 · O₂ / 葡萄糖"],[q.heart,Color("f4b74b"),"心脏储备 · 运氧换粮"]]
	var nest := game.entity(int(q.nest))
	if not nest.is_empty() and nest.hp > 0: entries.append([nest,Color("ec4c79"),"感染灶 · 消耗营养繁殖"])
	for entry in entries:
		var p := display_point(WarData.point(entry[0]))
		var radius := maxf(7/camera.zoom.x,3)
		_canvas.draw_arc(p,radius,0,TAU,48,Color(entry[1],230.0/255),2/camera.zoom.x,true)
		if camera.zoom.x >= .055*32: _draw_label(p-Vector2(0,radius+12/camera.zoom.x),entry[2],entry[1],12)

func _draw_campaign() -> void:
	# Source artwork is a separate input from the certified navigation mask.
	for tile in campaign_tiles:
		var texture := textures.get_texture(tile.path)
		if texture: _canvas.draw_texture_rect(texture,tile.rect,false)
	var spec: Dictionary = game.navigation.campaign
	for i in spec.zones.size():
		var zone: Dictionary = spec.zones[i]
		var status: Dictionary = game.state.campaign.event.zones[i]
		var color := Color("269b97") if status.owner != 2 else Color("ce4c4e")
		if game.mode == "nasal_01": color = Color("1e8485") if status.owner == 1 else (Color("bd405b") if status.owner == 2 else Color("b1a2c3"))
		if status.get("contested",false): color = Color("d7a549")
		var polygon := PackedVector2Array()
		for j in range(0,zone.polygon.size(),2): polygon.append(Vector2(zone.polygon[j],zone.polygon[j+1]))
		_canvas.draw_colored_polygon(polygon,Color(color,(62.0 if status.get("contested",false) else 36.0)/255 if game.mode == "lungs_01" else (34.0 if status.get("contested",false) else 22.0)/255))
		if game.mode == "trachea_01":
			if camera.zoom.x >= .065*32:
				_canvas.draw_line(polygon[0],Vector2(polygon[2].x,polygon[0].y),Color(color,155.0/255),maxf(1/camera.zoom.x,.08),true)
				_draw_label(Vector2(polygon[2].x+10/camera.zoom.x,(polygon[0].y+polygon[2].y)*.5),str(zone.name),color,11)
		elif game.mode == "lungs_01":
			var outline := polygon.duplicate(); outline.append(polygon[0])
			_canvas.draw_polyline(outline,Color(color,190.0/255),maxf(1.2/camera.zoom.x,.9),true)
			if camera.zoom.x >= .105*32:
				_draw_label(WarData.point(zone)-Vector2(0,18),str(zone.name),color,maxi(10,int(12*camera.zoom.x/32)))
				_draw_label(WarData.point(zone)-Vector2(0,18-16/camera.zoom.x),_territory_status(status),color,maxi(9,int(10*camera.zoom.x/32)))
		elif camera.zoom.x >= .1*32:
			var p := Vector2(zone.x,spec.bounds.y+spec.bounds.h+5)
			_draw_label(p,str(zone.name),color,12)
			_draw_label(p+Vector2(0,16/camera.zoom.x),_territory_status(status),color,10)
	if game.mode == "nasal_01": _draw_nasal_flow()
	if game.mode == "lungs_01": _draw_lung_landmarks()

func _territory_status(status: Dictionary) -> String:
	if status.get("contested",false): return "争夺中"
	return ("免疫 " if status.owner == 1 else "病毒 " if status.owner == 2 else "中立 ")+str(int(absf(float(status.control))))+"%"

func _draw_nasal_flow() -> void:
	var spec: Dictionary = campaign_art.get(game.mode,{})
	if spec.is_empty(): return
	if camera.zoom.x >= .12*32:
		for edge in spec.network.edges:
			var distance := fposmod(flow_time()*7+int(edge.id)*11,23)
			var count := 0
			for i in range(1,edge.points.size()):
				var a := WarData.point(edge.points[i-1])
				var b := WarData.point(edge.points[i])
				var length := a.distance_to(b)
				while distance < length and count < 12:
					var p := a.lerp(b,distance/length)
					_canvas.draw_set_transform(p,(b-a).angle())
					_canvas.draw_ellipse(Vector2.ZERO,1,.65,Color(224.0/255,110.0/255,138.0/255,190.0/255))
					_canvas.draw_ellipse(Vector2.ZERO,.47,.31,Color(127.0/255,47.0/255,80.0/255,220.0/255))
					_canvas.draw_set_transform(Vector2.ZERO)
					distance += 23; count += 1
				distance -= length
	if camera.zoom.x >= .14*32:
		for obstacle in spec.nasal.obstacles:
			if obstacle.kind == "concha": _draw_label(WarData.point(obstacle),str(obstacle.name),Color("6f4b6e"),10)
	if camera.zoom.x >= .1*32:
		for p in spec.nasal.landmarks: _draw_label(WarData.point(p),str(p.name),Color("6c577f"),10)
		_draw_label(Vector2(spec.nasal.bounds.x+93,spec.nasal.bounds.y+80),"鼻中隔",Color("6e4e7a"),11)
	if camera.zoom.x >= .23*32:
		for gate in spec.network.gates: _draw_label(WarData.point(gate)-Vector2(0,7),"膜口",Color("906328"),9)

func _draw_lung_landmarks() -> void:
	var color := Color(113.0/255,165.0/255,178.0/255,210.0/255)
	for line in [[Vector2(940,540),Vector2(940,700),8.0],[Vector2(940,700),Vector2(700,820),6.0],[Vector2(940,700),Vector2(1180,820),6.0]]:
		_canvas.draw_line(line[0],line[1],color,maxf(2/camera.zoom.x,line[2]),true)
	for line in [[Vector2(690,820),Vector2(610,760)],[Vector2(690,820),Vector2(620,920)],[Vector2(1190,820),Vector2(1270,760)],[Vector2(1190,820),Vector2(1260,920)]]:
		_canvas.draw_line(line[0],line[1],Color(135.0/255,178.0/255,188.0/255,210.0/255),maxf(1.2/camera.zoom.x,3),true)
	if camera.zoom.x >= .12*32:
		for center in [Vector2(650,900),Vector2(1230,900)]:
			for row in 4:
				for col in 5:
					var p: Vector2 = center+Vector2((col-2)*38+(row%2)*16,(row-1.5)*42)
					_canvas.draw_ellipse(p,maxf(2/camera.zoom.x,7),maxf(2/camera.zoom.x,5),Color(246.0/255,229.0/255,238.0/255,55.0/255))
					_canvas.draw_ellipse(p,maxf(1/camera.zoom.x,3),maxf(1/camera.zoom.x,2),Color(183.0/255,119.0/255,157.0/255,80.0/255))

func _heart_enabled() -> bool:
	return game.state.get("anatomyVersion",0) == 4 and game.state.get("heartDisplayEnabled",true) and (game.is_fullbody() or (game.state.get("organBattlefieldVersion",0) == 1 and WarData.array(game.state.get("organBattlefieldIds",[])).has("heart")))

func _exit_tree() -> void:
	textures.close()

func activity(e: Dictionary) -> float:
	return clampf(WarData.point(e).distance_to(Vector2(e.get("previousX",e.x),e.get("previousY",e.y)))/WarSimulation.STEP/3.6,0,1)

func display_point(p: Vector2) -> Vector2:
	return heart.forward(p) if _heart_enabled() else p

func command_point(p: Vector2) -> Vector2:
	return heart.inverse(p) if _heart_enabled() else p

static func faction_color(faction: int) -> Color:
	if faction <= 0: return Color("ca7c58")
	var c: Array = WarData.config().Data.factions[faction-1].color
	return Color(float(c[0])/255,float(c[1])/255,float(c[2])/255)

static func building_radius(kind: String) -> float:
	return 43 if kind == "core" else float(WarData.spec(kind).get("size",1))*13+2

func display_radius(e: Dictionary,p: Vector2) -> float:
	var radius := WarData.radius(e.kind)
	# A linked wall uses physical spacing; independent minimum-size enlargement
	# would make adjacent hands overlap at distant full-body zoom levels.
	if e.kind == "scout" and not e.get("plateletLinks",[]).is_empty(): return radius
	var zoom := camera.zoom.x/32.0
	if not game.is_fullbody() or zoom <= .14: return radius
	var distance := INF
	for b in presentation.protected:
		var rect := Rect2(WarData.source_to_world([b[0],b[1]]),Vector2(b[2]-b[0],b[3]-b[1])*2)
		var dx := maxf(maxf(rect.position.x-p.x,0),p.x-rect.end.x)
		var dy := maxf(maxf(rect.position.y-p.y,0),p.y-rect.end.y)
		distance = minf(distance,Vector2(dx,dy).length())
	return radius+maxf(0,4.5/camera.zoom.x-radius)*WarHeartDisplay.smooth((zoom-.14)/.01)*WarHeartDisplay.smooth(distance/24)

func obscured(e: Dictionary,p: Vector2) -> bool:
	if layer_weights[3] < .99 or not game.is_fullbody(): return false
	var lane := str(int(e.get("vesselLane",0)))
	var crossing: Dictionary = presentation.crossings.get(lane,{})
	if crossing.is_empty(): return false
	var q := Vector2(p.x*.5,(p.y-512)*.5)
	for ring in crossing.rings:
		if _inside(q,ring.outer):
			var hole := false
			for points in WarData.array(ring.holes):
				if _inside(q,points): hole = true; break
			if not hole: return true
	return false

static func _inside(p: Vector2,points: Array) -> bool:
	var hit := false
	var j := points.size()-1
	for i in points.size():
		var a: Array = points[i]
		var b: Array = points[j]
		if (a[1] > p.y) != (b[1] > p.y) and p.x < (b[0]-a[0])*(p.y-a[1])/(b[1]-a[1])+a[0]: hit = not hit
		j = i
	return hit

func _draw_hidden(e: Dictionary,p: Vector2) -> void:
	var radius := maxf(3.2/camera.zoom.x,WarData.radius(e.kind))
	var color := Color(105.0/255,235.0/255,203.0/255,210.0/255) if game.selected.has(int(e.id)) and e.kind != "worker" else Color(83.0/255,102.0/255,116.0/255,140.0/255)
	for i in 6:
		var a := i*PI/3
		var b := a+PI/6
		_canvas.draw_line(p+Vector2.from_angle(a)*radius,p+Vector2.from_angle(b)*radius,color,1.0/camera.zoom.x,true)

func flow_time() -> float:
	return maxf(0,float(game.state.time)-WarSimulation.STEP+minf(game.accumulator,WarSimulation.STEP))

static func atlas_frame(clip: Dictionary,elapsed: float,loop: bool) -> int:
	var t := maxf(0,elapsed)
	if loop: t = fmod(t,float(clip.duration))
	var end := 0.0
	var durations := WarData.array(clip.durations)
	for i in durations.size():
		end += float(durations[i])
		if t < end-.000001: return i
	return durations.size()-1

func pick(e: Dictionary,p: Vector2) -> bool:
	if float(e.get("hp",0)) <= 0: return false
	var center := display_point(unit_position(e))
	if e.faction != 1 and WarDendriticCells.concealed(e):
		return game.dendritic.marked(e,1) and p.distance_to(center) <= display_radius(e,unit_position(e))*1.8
	if e.has("checkpointId"): return p.distance_to(center) < 6.6
	if e.category != "unit": return p.distance_to(center) < building_radius(e.kind)/32
	if camera.zoom.x < .14*32: return p.distance_to(center) < 6/camera.zoom.x
	var pose := animation(e,false)
	var key: String = pose.get("key","")
	var frame := int(pose.get("frame",0))
	var rotation := cell_rotation(e)
	var local := (p-center).rotated(-rotation.angle)/display_radius(e,unit_position(e))/float(rotation.pulse)
	if rotation.mirror: local.x = -local.x
	return Geometry2D.is_point_in_polygon(local,WarCellShape.normalized(e,key,frame,"outline"))

func _draw_selection(e: Dictionary,p: Vector2,radius: float,pose: Dictionary) -> void:
	var points := WarCellShape.normalized(e,pose.get("key",""),int(pose.get("frame",0)),"outline")
	var rotation := cell_rotation(e)
	var outline := PackedVector2Array()
	for point in points:
		if rotation.mirror: point.x = -point.x
		outline.append(p+point.rotated(rotation.angle)*radius*float(rotation.pulse))
	outline.append(outline[0])
	if e.kind == "worker":
		_canvas.draw_polyline(outline,Color(41.0/255,64.0/255,69.0/255,210.0/255),1.5/camera.zoom.x,true)
	else:
		_canvas.draw_polyline(outline,Color(41.0/255,64.0/255,69.0/255,210.0/255),3/camera.zoom.x,true)
		_canvas.draw_polyline(outline,Color("69ebcb"),1.5/camera.zoom.x,true)

func unit_position(e: Dictionary) -> Vector2:
	var p := WarData.point(e)
	if e.get("category","") != "unit": return p
	var previous := Vector2(e.get("previousX",e.x),e.get("previousY",e.y))
	if previous.distance_squared_to(p) > 9: return p
	var alpha := clampf(game.accumulator/WarSimulation.STEP,0,1)
	var trail: Array = e.get("renderTrail",[])
	if trail.size() > 1:
		var points := trail.duplicate()
		if (points[-1] as Vector2).distance_to(p) > .00001: points.append(p)
		var length := 0.0
		for i in range(1,points.size()): length += (points[i-1] as Vector2).distance_to(points[i])
		var remaining := length*alpha
		for i in range(1,points.size()):
			var from: Vector2 = points[i-1]
			var to: Vector2 = points[i]
			var distance := from.distance_to(to)
			if distance > 0 and remaining <= distance: return from.lerp(to,remaining/distance)
			remaining -= distance
		return p
	return previous.lerp(p,alpha)

func cell_rotation(e: Dictionary) -> Dictionary:
	if e.kind == WarMedicineHelpers.KIND:
		return {"angle":0.0,"mirror":cos(float(e.get("weaponHeading",e.get("moveHeading",PI))))>0,"pulse":1.0}
	var pose := WarCellShape.pose(e,flow_time(),false)
	if e.kind in ["spear","neutrophil"]:
		var heading := float(e.get("moveHeading",PI)) if activity(e) > .001 else float(e.get("weaponHeading",e.get("moveHeading",PI)))
		var target := game.entity(int(e.get("weaponTarget",0)))
		if not target.is_empty() and float(game.state.time)-float(e.get("weaponTargetTime",-100)) <= WarSimulation.STEP*2 and game.visible(target):
			heading = (display_point(unit_position(target))-display_point(unit_position(e))).angle()
		pose.mirror = cos(heading) > 0
		pose.angle = heading if pose.mirror else heading-PI
	return pose
