class_name WarInfectionSurface
extends MeshInstance2D
## Flat paving from generated color/edge assets. Geometry stays inside the
## already certified footprint; the displayed contour is a merged decal mask.
var world: WarWorldView
var paving := ShaderMaterial.new()
var _rect := Rect2()
var _flow := INF
var live_surfaces: Dictionary = {}

func _ready() -> void:
	paving.shader = load("res://shaders/infection_paving.gdshader")
	material = paving
	visible = false

func _process(_delta: float) -> void:
	visible = false
	if world == null: return
	for surface in live_surfaces.values(): surface.visible = false
	var model := world.infections
	if not world.game.is_fullbody():
		_clear_live()
		return
	if not model.enabled:
		_process_live()
		return
	if not model.ground_visible or model.zone.is_empty(): return
	var alpha := float(world.layer_weights[2])*(1-float(world.layer_weights[4]))
	if alpha < .001: return
	var base := world.textures.get_texture(model.data.texture)
	var edge := world.textures.get_texture(model.data.edgeTexture)
	if base == null or edge == null: return
	var rect := model.footprint()
	var flow := world.flow_time()
	if rect != _rect or flow != _flow:
		_rect = rect; _flow = flow
		_rebuild(rect)
	texture = base
	paving.set_shader_parameter("ground_pattern",base)
	paving.set_shader_parameter("edge_brush",edge)
	paving.set_shader_parameter("region_origin",rect.position)
	paving.set_shader_parameter("region_size",rect.size)
	paving.set_shader_parameter("tile_world_size",float(model.data.pavingWorldSize))
	paving.set_shader_parameter("amount",float(model.data.pavingOpacity))
	paving.set_shader_parameter("layout_seed",model.paving_seed())
	paving.set_shader_parameter("detail_midpoint",float(model.data.get("pavingDetailMidpoint",.4)))
	paving.set_shader_parameter("detail_strength",float(model.data.get("pavingDetailStrength",.75)))
	modulate = Color(1,1,1,alpha)
	visible = mesh != null

func _clear_live(keep: Dictionary = {}) -> void:
	for id in live_surfaces.keys():
		if keep.has(id): continue
		live_surfaces[id].queue_free()
		live_surfaces.erase(id)

func _process_live() -> void:
	# Keep the retained InfectionGround canvas; each active certified patch gets
	# its own mesh/material so multiple outbreaks can fade independently.
	mesh = null; _rect = Rect2(); _flow = INF
	modulate = Color.WHITE
	var items := WarInfectionZones.live_patches(world.game)
	var keep: Dictionary = {}
	for item in items: keep[item.group.id] = true
	_clear_live(keep)
	var alpha := float(world.layer_weights[2])*(1-float(world.layer_weights[4]))
	if items.is_empty() or alpha < .001: return
	var data: Dictionary = WarData.read("infection_zones")
	# Runtime infection textures are requested here, without enabling the paused
	# layout-preview model or requiring changes in the main world process.
	world.textures.request(data.texture,true)
	world.textures.request(data.edgeTexture,true)
	var base := world.textures.get_texture(data.texture)
	var edge := world.textures.get_texture(data.edgeTexture)
	if base == null or edge == null: return
	var flow := world.flow_time()
	for item in items:
		var rect: Rect2 = item.rect
		if not rect.intersects(world.visible_world_rect().grow(12)): continue
		var id: String = item.group.id
		var surface: MeshInstance2D = live_surfaces.get(id)
		if surface == null:
			surface = MeshInstance2D.new()
			surface.name = "Live_"+id.replace(".","_")
			var shader_material := ShaderMaterial.new()
			shader_material.shader = paving.shader
			surface.material = shader_material
			add_child(surface)
			live_surfaces[id] = surface
		if surface.get_meta("flow",INF) != flow or surface.get_meta("rect",Rect2()) != rect:
			surface.mesh = _make_mesh(rect)
			surface.set_meta("flow",flow); surface.set_meta("rect",rect)
		var shader_material: ShaderMaterial = surface.material
		surface.texture = base
		shader_material.set_shader_parameter("ground_pattern",base)
		shader_material.set_shader_parameter("edge_brush",edge)
		shader_material.set_shader_parameter("region_origin",rect.position)
		shader_material.set_shader_parameter("region_size",rect.size)
		shader_material.set_shader_parameter("tile_world_size",float(data.pavingWorldSize))
		shader_material.set_shader_parameter("amount",float(data.pavingOpacity))
		shader_material.set_shader_parameter("layout_seed",float(item.seed))
		shader_material.set_shader_parameter("detail_midpoint",float(data.get("pavingDetailMidpoint",.4)))
		shader_material.set_shader_parameter("detail_strength",float(data.get("pavingDetailStrength",.75)))
		surface.modulate = Color(1,1,1,alpha*float(item.opacity))
		surface.visible = true
		visible = true

func _rebuild(rect: Rect2) -> void:
	mesh = _make_mesh(rect)

func _make_mesh(rect: Rect2) -> ArrayMesh:
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	const DIVISIONS := 8
	for y in DIVISIONS+1:
		for x in DIVISIONS+1:
			var uv := Vector2(x,y)/float(DIVISIONS)
			vertices.append(world.display_point(rect.position+uv*rect.size))
			uvs.append(uv)
	for y in DIVISIONS:
		for x in DIVISIONS:
			var at := y*(DIVISIONS+1)+x
			indices.append_array(PackedInt32Array([at,at+1,at+DIVISIONS+2,at,at+DIVISIONS+2,at+DIVISIONS+1]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return result
