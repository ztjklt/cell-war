class_name WarMinimap
extends Control
var game: WarSimulation
var camera: Camera2D
var world: WarWorldView
var map_scale := 1.0
var origin := Vector2.ZERO
var overview := false
signal moved(point: Vector2)

func _ready() -> void:
	custom_minimum_size = Vector2.ZERO
	clip_contents = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if game == null or game.state.is_empty() or world == null: return
	var aperture := world.visible_world_rect()
	var view := aperture.size
	map_scale = clampf(minf(size.x/view.x,size.y/view.y)/2.4,maxf(size.x,size.y)/900,minf(size.x,size.y)/160)
	var projected_center := aperture.get_center()
	var center := projected_center
	var half := size/(2*map_scale)
	var dimensions := Vector2(game.state.get("mapWidth",2048),game.state.get("mapHeight",4096))
	if overview:
		map_scale = minf(size.x/dimensions.x,size.y/dimensions.y)
		half = dimensions*.5
		center = half
	center.x = dimensions.x*.5 if half.x*2 >= dimensions.x else clampf(center.x,half.x,dimensions.x-half.x)
	center.y = dimensions.y*.5 if half.y*2 >= dimensions.y else clampf(center.y,half.y,dimensions.y-half.y)
	origin = size*.5-center*map_scale
	draw_rect(Rect2(Vector2.ZERO,size),Color.WHITE)
	draw_set_transform(origin,0,Vector2.ONE*map_scale)
	if game.is_fullbody():
		if world.layer_weights[4] < 1:
			for key in ["foundation","organs","blood"]:
				for tile in world.art[key]:
					var spec: Dictionary = tile.levels["4"]
					var box: Array = spec.sourceBox
					var rect := Rect2(WarData.source_to_world([box[0],box[1]]),Vector2(box[2]-box[0],box[3]-box[1])*2)
					if not Rect2((Vector2.ZERO-origin)/map_scale,size/map_scale).intersects(rect): continue
					world.textures.request(spec.resource)
					var texture := world.textures.get_texture(spec.resource)
					var channel := 3 if key == "blood" else (2 if key == "organs" else (0 if tile.kind == "base" else 1))
					if texture: draw_texture_rect(texture,rect,false,Color(1,1,1,world.layer_weights[channel]))
		if world.layer_weights[4] > 0:
			var texture := world.textures.get_texture(world.art.reference.resource)
			if texture: draw_texture_rect(texture,Rect2(0,512,2048,3072),false,Color(1,1,1,world.layer_weights[4]))
	if world.legacy.enabled(game) and not world.legacy.data.is_empty():
		var amount := WarLegacyArt.blend(map_scale/32)
		if amount < 1:
			world.textures.request(world.art.reference.resource)
			var reference := world.textures.get_texture(world.art.reference.resource)
			if reference: draw_texture_rect(reference,Rect2(0,512,2048,3072),false)
		var bounds := Rect2((Vector2.ZERO-origin)/map_scale,size/map_scale)
		world.legacy.draw_base(self,bounds,amount)
		for spec in world.legacy.data.overlays.get(game.mode,[]):
			var box: Array = spec.sourceBox
			var rect := Rect2(WarData.source_to_world([box[0],box[1]]),Vector2(box[2]-box[0],box[3]-box[1])*2)
			if not rect.intersects(bounds): continue
			world.textures.request(spec.resource)
			var texture := world.textures.get_texture(spec.resource)
			if texture: draw_texture_rect(texture,rect,false,Color(1,1,1,amount))
	if game.is_campaign() and world.campaign_art.has(game.mode):
		for tile in world.campaign_art[game.mode].tiles:
			var b: Array = tile.worldBox
			var rect := Rect2(Vector2(b[0],b[1]),Vector2(b[2]-b[0],b[3]-b[1]))
			if not Rect2((Vector2.ZERO-origin)/map_scale,size/map_scale).intersects(rect): continue
			var path: String = tile.levels["4"]
			world.textures.request(path)
			var texture := world.textures.get_texture(path)
			if texture: draw_texture_rect(texture,rect,false)
	if world.layer != 6:
		for e in game.units():
			if game.visible(e): draw_circle(world.display_point(WarData.point(e)),2.0/map_scale,WarWorldView.faction_color(int(e.faction)))
	draw_set_transform(Vector2.ZERO)
	var rect := Rect2(origin+(projected_center-view*.5)*map_scale,view*map_scale)
	draw_rect(rect.intersection(Rect2(Vector2.ZERO,size)),Color("3c8885"),false,1)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		moved.emit((event.position-origin)/map_scale)
		accept_event()
