class_name WarLegacyArt
extends RefCounted
## Original trial/sandbox ReferenceArt branch; never overlays the fullbody renderer.
var data: Dictionary = {}
var meshes: Dictionary = {}
var active_specs: Array = []
var bounds := Rect2()

static func blend(zoom: float) -> float:
	return WarHeartDisplay.smooth((zoom-.085)/.065)

func enabled(game: WarSimulation) -> bool:
	return game.mode in ["gastric_trial","organ_trial","sandbox"]

func prepare(game: WarSimulation,textures: WarTextures,view_bounds: Rect2,zoom: float) -> void:
	bounds = view_bounds
	active_specs.clear()
	if not enabled(game): return
	if data.is_empty(): data = WarData.read("legacy_art")
	if blend(zoom) < 1: textures.request(WarData.read("art").reference.resource)
	for spec in data.overlays.get(game.mode,[]):
		var box: Array = spec.sourceBox
		if Rect2(WarData.source_to_world([box[0],box[1]]),Vector2(box[2]-box[0],box[3]-box[1])*2).intersects(bounds):
			textures.request(spec.resource)
			active_specs.append(spec)

func _mesh(index: int) -> ArrayMesh:
	if meshes.has(index): return meshes[index]
	var spec: Dictionary = data.base[index]
	var box: Array = spec.sourceBox
	var from := Vector2(box[0],box[1])
	var span := Vector2(box[2]-box[0],box[3]-box[1])
	var base := Color(float(spec.color[0])/255,float(spec.color[1])/255,float(spec.color[2])/255)
	var light := Color(minf(1,base.r+2.0/255),minf(1,base.g+2.0/255),minf(1,base.b+2.0/255)) if index > 0 else base
	var vertices := PackedVector2Array()
	var colors := PackedColorArray()
	var file := FileAccess.open("res://data/legacy_base.bin",FileAccess.READ)
	file.seek(int(spec.offset))
	var points := file.get_buffer(int(spec.vertexCount)*8).to_float32_array()
	for i in int(spec.vertexCount):
		var p := Vector2(points[i*2],points[i*2+1])
		vertices.append(p*2+Vector2(0,512))
		colors.append(light.lerp(base,clampf((p-from).dot(span)/maxf(.00001,span.length_squared()),0,1)))
	var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	meshes[index] = mesh
	return mesh

func draw_base(canvas: CanvasItem,view_bounds: Rect2,amount: float) -> void:
	var opacity := floorf(amount*255)/255
	if opacity > 0:
		for i in data.base.size():
			var box: Array = data.base[i].sourceBox
			if Rect2(WarData.source_to_world([box[0],box[1]]),Vector2(box[2]-box[0],box[3]-box[1])*2).intersects(view_bounds):
				canvas.draw_mesh(_mesh(i),null,Transform2D.IDENTITY,Color(1,1,1,opacity))

func draw_layers(canvas: CanvasItem,view: WarWorldView) -> void:
	draw_base_layer(canvas,view)
	draw_overlays(canvas,view)

func draw_base_layer(canvas: CanvasItem,view: WarWorldView) -> void:
	if data.is_empty(): data = WarData.read("legacy_art")
	var amount := blend(view.camera.zoom.x/32)
	if amount < 1: _draw_spec(canvas,view,view.art.reference,1)
	draw_base(canvas,bounds,amount)

func draw_overlays(canvas: CanvasItem,view: WarWorldView) -> void:
	var amount := blend(view.camera.zoom.x/32)
	for spec in active_specs: _draw_spec(canvas,view,spec,amount)

func _draw_spec(canvas: CanvasItem,view: WarWorldView,spec: Dictionary,alpha: float) -> void:
	if alpha <= .001: return
	var texture := view.textures.get_texture(spec.resource)
	if texture == null: return
	if spec.resource != view.art.reference.resource and view._heart_enabled() and view.heart.draw_spec(canvas,spec,texture,alpha): return
	var box: Array = spec.sourceBox
	canvas.draw_texture_rect(texture,Rect2(WarData.source_to_world([box[0],box[1]]),Vector2(box[2]-box[0],box[3]-box[1])*2),false,Color(1,1,1,alpha))
