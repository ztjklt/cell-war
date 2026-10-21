class_name WarDeskMapFrame
extends Control
## The paper and its anatomy occupy fixed positions in the same desk world.
signal desk_projection_changed(projection: Transform2D)
var world: WarWorldView
var camera: Camera2D

static func rect_for(view: Vector2) -> Rect2:
	if view.x < 720:
		return Rect2(Vector2(view.x*.055,view.y*.235),Vector2(view.x*.89,view.y*.50))
	# Center the figure between the paper's study columns and above its charts.
	return Rect2(view*Vector2(.248,.17),view*Vector2(.40,.645))

static func contains(view: Vector2,point: Vector2) -> bool:
	return rect_for(view).has_point(point)

static func overview_zoom(view: Vector2,dimensions: Vector2) -> float:
	var field := rect_for(view)
	return minf(field.size.x/dimensions.x,field.size.y*1.26/dimensions.y)

static func overview_projection(view: Vector2,dimensions: Vector2) -> Transform2D:
	var zoom := overview_zoom(view,dimensions)
	return Transform2D(Vector2(zoom,0),Vector2(0,zoom),rect_for(view).get_center()-dimensions*.5*zoom)

func desk_projection() -> Transform2D:
	if world == null or not world.game.is_fullbody(): return Transform2D.IDENTITY
	var dimensions := Vector2(world.game.state.get("mapWidth",2048),world.game.state.get("mapHeight",4096))
	if is_equal_approx(camera.zoom.x,overview_zoom(get_viewport_rect().size,dimensions)) and camera.position.distance_to(dimensions*.5) < .001:
		return Transform2D.IDENTITY
	return get_viewport().get_canvas_transform()*overview_projection(get_viewport_rect().size,dimensions).affine_inverse()

func screen_rect() -> Rect2:
	var view := get_viewport_rect().size
	return (desk_projection()*rect_for(view)).intersection(Rect2(Vector2.ZERO,view))

func contains_screen_point(point: Vector2) -> bool:
	return screen_rect().has_point(point)

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(sync_size)

func bind_world(value: WarWorldView,view_camera: Camera2D) -> void:
	world = value; camera = view_camera
	sync_size()

func sync_size() -> void:
	if world == null or camera == null: return
	camera.force_update_scroll()
	var canvas := get_viewport().get_canvas_transform()
	var field := rect_for(get_viewport_rect().size)
	if world.game.is_fullbody():
		var dimensions := Vector2(world.game.state.get("mapWidth",2048),world.game.state.get("mapHeight",4096))
		var paper := overview_projection(get_viewport_rect().size,dimensions).affine_inverse()*field
		# This rectangle never counter-scales against the camera. Its edges move
		# with the printed paper and eventually leave the screen during approach.
		position = paper.position
		scale = Vector2.ONE
		size = paper.size
	else:
		position = canvas.affine_inverse()*field.position
		scale = Vector2.ONE/canvas.get_scale()
		size = field.size
	world.transform = get_global_transform().affine_inverse()
	desk_projection_changed.emit(desk_projection())

func _process(_delta: float) -> void:
	sync_size()
