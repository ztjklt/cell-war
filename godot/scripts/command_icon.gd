class_name WarCommandIcon
extends WarSmoothIcon
## Filled low-poly symbols: consistent light face, cocoa side and warm inset face.
var kind := "move"
var color := WarUISkin.INK
var emphasis := 0.0

func _poly(canvas: CanvasItem,raw: Array,tint: Color) -> void:
	var points := PackedVector2Array()
	for p in raw: points.append(Vector2(p[0],p[1])*size)
	canvas.draw_colored_polygon(points,tint)

func _solid(canvas: CanvasItem,raw: Array,tint := Color("b89a76")) -> void:
	var points := PackedVector2Array()
	for p in raw: points.append(Vector2(p[0],p[1])*size)
	var side := points.duplicate()
	for i in side.size(): side[i] += Vector2(1.3,2.3-emphasis*.4)
	canvas.draw_colored_polygon(side,color.darkened(.13))
	canvas.draw_colored_polygon(points,tint)
	var contour := points.duplicate(); contour.append(points[0])
	canvas.draw_polyline(contour,Color(color,.8),.9,true)

func _paint_icon(canvas: CanvasItem) -> void:
	var cream := Color("fff5df")
	var gold := Color("d4b58a")
	var sage := Color("9cbaa3")
	match kind:
		"move","rally":
			_solid(canvas,[[.13,.64],[.47,.3],[.3,.13],[.89,.12],[.88,.71],[.7,.52],[.36,.87]],gold)
			_poly(canvas,[[.47,.3],[.89,.12],[.53,.48],[.13,.64]],cream)
			_poly(canvas,[[.53,.48],[.89,.12],[.88,.71],[.7,.52]],Color("bb946d"))
		"attack","attackmove":
			_solid(canvas,[[.17,.12],[.37,.18],[.81,.7],[.69,.82],[.18,.32]],Color("c0c8bf"))
			_poly(canvas,[[.17,.12],[.37,.18],[.75,.74],[.69,.82]],cream)
			_solid(canvas,[[.83,.12],[.79,.33],[.33,.84],[.17,.7],[.63,.2]],gold)
			_poly(canvas,[[.83,.12],[.53,.57],[.17,.7],[.63,.2]],cream)
			_solid(canvas,[[.08,.64],[.2,.52],[.44,.76],[.33,.88]],Color("b6936c"))
			_solid(canvas,[[.56,.75],[.8,.52],[.92,.64],[.68,.88]],Color("b6936c"))
		"guard","hold":
			_solid(canvas,[[.5,.08],[.85,.22],[.79,.66],[.5,.93],[.21,.66],[.15,.22]],sage)
			_poly(canvas,[[.5,.08],[.5,.78],[.29,.59],[.23,.27]],Color("dce8cd"))
			_poly(canvas,[[.5,.08],[.85,.22],[.79,.66],[.5,.93],[.5,.78],[.7,.59],[.77,.27]],Color("7b9b84"))
		"retreat","back":
			_solid(canvas,[[.11,.47],[.49,.1],[.49,.32],[.81,.32],[.89,.42],[.89,.79],[.69,.79],[.69,.54],[.49,.54],[.49,.8]],gold)
			_poly(canvas,[[.11,.47],[.49,.1],[.49,.32],[.81,.32],[.89,.42],[.4,.42],[.4,.29]],cream)
		"stop":
			_solid(canvas,[[.25,.13],[.71,.13],[.85,.27],[.85,.73],[.71,.87],[.25,.87],[.12,.73],[.12,.27]],Color("c7b09a"))
			_poly(canvas,[[.25,.13],[.71,.13],[.85,.27],[.12,.27]],cream)
			_poly(canvas,[[.71,.13],[.85,.27],[.85,.73],[.71,.87],[.68,.7],[.68,.31]],Color("a88b72"))
			_poly(canvas,[[.32,.34],[.65,.34],[.65,.67],[.32,.67]],Color("f5e7d1"))
		"build","build_menu","repair","production":
			_solid(canvas,[[.18,.8],[.58,.35],[.72,.49],[.32,.94]],Color("b6936c"))
			_poly(canvas,[[.18,.8],[.58,.35],[.63,.4],[.23,.85]],cream)
			_solid(canvas,[[.38,.25],[.61,.04],[.93,.36],[.72,.59]],Color("ccbda2"))
			_poly(canvas,[[.38,.25],[.61,.04],[.69,.12],[.46,.33]],cream)
			_poly(canvas,[[.69,.12],[.93,.36],[.72,.59],[.65,.51],[.83,.34]],Color("a48d70"))
		"harvest","farm":
			_solid(canvas,[[.48,.07],[.71,.38],[.69,.59],[.5,.7],[.3,.59],[.29,.39]],WarUISkin.HONEY)
			_poly(canvas,[[.48,.07],[.5,.55],[.3,.59],[.29,.39]],cream)
			_solid(canvas,[[.17,.61],[.29,.86],[.72,.86],[.85,.61],[.73,.69],[.29,.69]],gold)
		"extinguish":
			_solid(canvas,[[.5,.04],[.7,.29],[.67,.43],[.51,.51],[.34,.44],[.31,.3]],Color("91c4cc"))
			_poly(canvas,[[.5,.04],[.49,.38],[.34,.44],[.31,.3]],cream)
			_solid(canvas,[[.17,.5],[.83,.5],[.72,.92],[.28,.92]],sage)
			_poly(canvas,[[.25,.59],[.75,.59],[.69,.83],[.31,.83]],Color("b6dde0"))
			_poly(canvas,[[.17,.5],[.83,.5],[.8,.58],[.2,.58]],cream)
		"next":
			_solid(canvas,[[.24,.14],[.76,.5],[.24,.86],[.24,.64],[.47,.5],[.24,.36]],gold)
		_:
			_solid(canvas,[[.15,.42],[.5,.13],[.85,.42],[.85,.85],[.15,.85]],gold)
			_poly(canvas,[[.15,.42],[.5,.13],[.85,.42],[.5,.32]],cream)
			_poly(canvas,[[.41,.59],[.61,.59],[.61,.85],[.41,.85]],color)
