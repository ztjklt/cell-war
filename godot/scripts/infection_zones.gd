class_name WarInfectionZones
extends RefCounted
## Authored patch geometry for both the opt-in art preview and live colonies.
## Presentation reads saved colony state; it never advances simulation timers.
var enabled := false
var data: Dictionary = {}
var zone: Dictionary = {}
var placement_index := 0
var paving_variation := 0
var ground_visible := true
var last_ground_drawn := false
var last_range_drawn := false
var _triangles: Array[PackedVector2Array] = []
var _outlines: Array[PackedVector2Array] = []

static func live_patches(game: WarSimulation) -> Array:
	var result: Array = []
	if game.mode != "fullbody" or not game.is_fullbody(): return result
	for group in game.state.get("influenzaColonies",{}).get("groups",{}).values():
		var alpha := WarInfectionPurification.ground_opacity(group)
		if alpha <= .0001: continue
		var rect := WarInfectionPurification.footprint(group)
		if rect.size.is_zero_approx(): continue
		result.append({"group":group,"rect":rect,"opacity":alpha,
			"seed":float(posmod(hash(group.id),100000))*.01})
	return result

func select(organ: String,index := 0) -> bool:
	if data.is_empty(): data = WarData.read("infection_zones")
	for entry in data.zones:
		if entry.organ != organ: continue
		zone = entry
		placement_index = posmod(index,zone.placements.size())
		paving_variation = 0
		_triangles.clear(); _outlines.clear()
		for triangle in zone.triangles: _triangles.append(points(triangle))
		for ring in zone.rings:
			_outlines.append(points(ring.outer))
		return true
	return false

func placement() -> Dictionary:
	return zone.placements[placement_index] if not zone.is_empty() else {}

static func points(raw: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in raw: result.append(WarData.point(point))
	return result

func footprint() -> Rect2:
	var patch := placement()
	if patch.is_empty(): return Rect2()
	return Rect2(WarData.point(patch.center)-Vector2.ONE*float(patch.side)*.5,Vector2.ONE*float(patch.side))

func paving_seed() -> float:
	return float(posmod(hash(placement().get("id","")),100000))*.01+float(paving_variation)*19.37

func overview_bounds() -> Rect2:
	var bounds := footprint()
	for line in _outlines:
		for point in line: bounds = bounds.expand(point)
	return bounds

func _project(raw: PackedVector2Array,view: WarWorldView) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in raw: out.append(view.display_point(point))
	return out

func draw(canvas: CanvasItem,view: WarWorldView) -> void:
	last_ground_drawn = false; last_range_drawn = false
	if not enabled or zone.is_empty() or not view.game.is_fullbody(): return
	var alpha := float(view.layer_weights[2])*(1-float(view.layer_weights[4]))
	if alpha < .001: return
	if view.assisted:
		for triangle in _triangles:
			canvas.draw_primitive(_project(triangle,view),PackedColorArray([Color(.25,.65,.64,.105*alpha)]),PackedVector2Array())
		for line in _outlines:
			canvas.draw_polyline(_project(line,view),Color(.16,.58,.58,.72*alpha),1.3/view.camera.zoom.x,true)
		last_range_drawn = true
	last_ground_drawn = view.infection_surface.visible and view.infection_surface.mesh != null

func draw_orders(canvas: CanvasItem,view: WarWorldView) -> void:
	if not enabled:
		_draw_live_status(canvas,view)
		return
	if not enabled or not view.assisted or zone.is_empty() or not view.game.is_fullbody(): return
	if view.layer_weights[4] > .99 or view.layer_weights[2] < .01: return
	var route := _project(points(placement().route),view)
	if route.size() > 1:
		canvas.draw_polyline(route,Color(.2,.53,.51,.7),1.4/view.camera.zoom.x,true)
	var position := view.display_point(WarData.point(placement().center))
	canvas.draw_set_transform(position,0,Vector2.ONE/view.camera.zoom.x)
	canvas.draw_string(view._font,Vector2(12,-18),"本次感染",HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("704257"))
	canvas.draw_set_transform(Vector2.ZERO)

func _draw_live_status(canvas: CanvasItem,view: WarWorldView) -> void:
	if not view.assisted or view.layer_weights[4] > .99 or view.layer_weights[2] < .01: return
	for item in live_patches(view.game):
		var group: Dictionary = item.group
		var status: Dictionary = group.get("purification",{})
		var red := int(status.get("red",0)); var white := int(status.get("white",0))
		# Only show the readout when defenders have actually reached this patch.
		if red+white == 0: continue
		var text := "净化 %d%% · 红 %d/%d 白 %d/%d" % [roundi(WarInfectionPurification.progress(group)*100),red,WarInfectionPurification.RED_REQUIRED,white,WarInfectionPurification.WHITE_REQUIRED]
		match status.get("status",""):
			"contested": text = "敌军干扰 · 净化已中断"
			"fortified": text = "先摧毁流感要塞"
			"pending_births": text = "感染仍在涌出 · 先清理敌军"
			"purified": text = "感染已净化 · 停止增殖"
		canvas.draw_set_transform(view.display_point(WarData.point(group.center)),0,Vector2.ONE/view.camera.zoom.x)
		canvas.draw_string(view._font,Vector2(12,-18),text,HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("704257"))
		canvas.draw_set_transform(Vector2.ZERO)
