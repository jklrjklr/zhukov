class_name UiIcons
## Icons drawn in code (no image assets): stratagem glyphs, HUD symbols. Every function draws
## centred on `c` with half-size `s` (px) on any CanvasItem; shapes get a dark outline so they
## read on top of the game as well as on panels.

const DARK := Color(0.05, 0.05, 0.05, 0.95)


static func _poly(ci: CanvasItem, c: Vector2, s: float, pts: Array, col: Color) -> void:
	var p := PackedVector2Array()
	for v in pts:
		p.append(c + (v as Vector2) * s)
	var o := p.duplicate()
	o.append(p[0])
	ci.draw_colored_polygon(p, col)
	ci.draw_polyline(o, DARK, maxf(s * 0.12, 1.2))


## Stratagem glyph by id, in the category colour.
static func strat(ci: CanvasItem, id: String, c: Vector2, s: float, col: Color) -> void:
	match id:
		"eagle_airstrike":
			_poly(ci, c + Vector2(0, -s * 0.15), s, [Vector2(0, -0.95), Vector2(0.18, -0.4), Vector2(0.95, 0.25),
				Vector2(0.9, 0.5), Vector2(0.2, 0.3), Vector2(0.12, 0.62), Vector2(0.36, 0.78), Vector2(0.3, 0.9),
				Vector2(0, 0.8), Vector2(-0.3, 0.9), Vector2(-0.36, 0.78), Vector2(-0.12, 0.62), Vector2(-0.2, 0.3),
				Vector2(-0.9, 0.5), Vector2(-0.95, 0.25), Vector2(-0.18, -0.4)], col)
			for i in 3:
				ci.draw_circle(c + Vector2((i - 1) * s * 0.42, s * 0.95), s * 0.12, col)
		"eagle_500kg":
			_poly(ci, c + Vector2(0, -s * 0.05), s, [Vector2(0, -1.0), Vector2(0.38, -0.55), Vector2(0.4, 0.35),
				Vector2(0.18, 0.6), Vector2(0.5, 0.95), Vector2(-0.5, 0.95), Vector2(-0.18, 0.6), Vector2(-0.4, 0.35),
				Vector2(-0.38, -0.55)], col)
			ci.draw_line(c + Vector2(-s * 0.3, -s * 0.2), c + Vector2(s * 0.3, -s * 0.2), DARK, maxf(s * 0.12, 1.2))
			ci.draw_line(c + Vector2(-s * 0.3, s * 0.05), c + Vector2(s * 0.3, s * 0.05), DARK, maxf(s * 0.12, 1.2))
		"orbital_precision":
			ci.draw_arc(c, s * 0.62, 0.0, TAU, 20, DARK, s * 0.34)
			ci.draw_arc(c, s * 0.62, 0.0, TAU, 20, col, s * 0.2)
			for i in 4:
				var d := Vector2.from_angle(i * PI / 2.0)
				ci.draw_line(c + d * s * 0.4, c + d * s * 1.0, DARK, s * 0.3)
				ci.draw_line(c + d * s * 0.4, c + d * s * 1.0, col, s * 0.16)
			ci.draw_circle(c, s * 0.16, col)
		"orbital_120":
			ci.draw_arc(c, s * 0.95, 0.0, TAU, 24, Color(col, 0.55), maxf(s * 0.1, 1.0))
			for off in [Vector2(-0.4, 0.15), Vector2(0.35, -0.2), Vector2(0.05, 0.5)]:
				var p: Vector2 = c + (off as Vector2) * s
				ci.draw_line(p + Vector2(0, -s * 0.5), p + Vector2(0, s * 0.1), DARK, s * 0.34)
				ci.draw_line(p + Vector2(0, -s * 0.5), p + Vector2(0, s * 0.1), col, s * 0.2)
				ci.draw_circle(p + Vector2(0, s * 0.14), s * 0.14, col)
		"resupply":
			_poly(ci, c, s, [Vector2(-0.8, -0.55), Vector2(0.8, -0.55), Vector2(0.8, 0.75), Vector2(-0.8, 0.75)], col)
			ci.draw_line(c + Vector2(0, -s * 0.55), c + Vector2(0, s * 0.75), DARK, maxf(s * 0.14, 1.2))
			ci.draw_line(c + Vector2(-s * 0.8, s * 0.05), c + Vector2(s * 0.8, s * 0.05), DARK, maxf(s * 0.14, 1.2))
			_poly(ci, c + Vector2(0, -s * 0.8), s * 0.45, [Vector2(-0.8, -0.3), Vector2(0.8, -0.3), Vector2(0, 0.7)], col.lightened(0.3))
		"eat17":
			_poly(ci, c, s, [Vector2(-0.18, -0.55), Vector2(0.18, -0.55), Vector2(0.18, 0.85), Vector2(-0.18, 0.85)], col)
			_poly(ci, c, s, [Vector2(-0.18, -0.55), Vector2(0, -1.0), Vector2(0.18, -0.55)], col.lightened(0.25))
			_poly(ci, c, s, [Vector2(-0.18, 0.55), Vector2(-0.5, 0.95), Vector2(-0.18, 0.85)], col)
			_poly(ci, c, s, [Vector2(0.18, 0.55), Vector2(0.5, 0.95), Vector2(0.18, 0.85)], col)
		"sentry_mg":
			for a in [-0.9, 0.0, 0.9]:
				var tip := c + Vector2(sin(a) * s * 0.95, s * (0.95 if a != 0.0 else 0.4) * 0.9)
				ci.draw_line(c + Vector2(0, s * 0.15), tip, DARK, maxf(s * 0.3, 2.0))
				ci.draw_line(c + Vector2(0, s * 0.15), tip, col, maxf(s * 0.16, 1.2))
			ci.draw_circle(c + Vector2(0, s * 0.1), s * 0.4, DARK)
			ci.draw_circle(c + Vector2(0, s * 0.1), s * 0.3, col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.1, -s * 0.95), Vector2(s * 0.2, s * 0.9)), DARK)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.06, -s * 0.9), Vector2(s * 0.12, s * 0.8)), col)
		_:
			ci.draw_circle(c, s * 0.7, col)


static func shield(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	_poly(ci, c, s, [Vector2(-0.8, -0.8), Vector2(0.8, -0.8), Vector2(0.8, 0.1), Vector2(0, 1.0), Vector2(-0.8, 0.1)], col)


static func skull(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	ci.draw_circle(c + Vector2(0, -s * 0.15), s * 0.8, DARK)
	ci.draw_circle(c + Vector2(0, -s * 0.15), s * 0.68, col)
	ci.draw_rect(Rect2(c + Vector2(-s * 0.4, s * 0.3), Vector2(s * 0.8, s * 0.55)), col)
	for x in [-1.0, 1.0]:
		ci.draw_circle(c + Vector2(x * s * 0.28, -s * 0.15), s * 0.2, DARK)


## Helldiver helmet (reinforcements).
static func helmet(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	ci.draw_circle(c, s, DARK)
	ci.draw_circle(c, s * 0.82, col)
	ci.draw_rect(Rect2(c + Vector2(-s * 0.55, -s * 0.05), Vector2(s * 1.1, s * 0.34)), DARK)
	ci.draw_line(c + Vector2(-s * 0.3, -s * 0.7), c + Vector2(s * 0.3, -s * 0.7), Color(1, 1, 1, 0.5), maxf(s * 0.15, 1.0))


## Sample vial (blue glow droplet).
static func sample(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	_poly(ci, c, s, [Vector2(0, -1.0), Vector2(0.7, 0.2), Vector2(0.45, 0.85), Vector2(-0.45, 0.85), Vector2(-0.7, 0.2)], col)
	ci.draw_circle(c + Vector2(-s * 0.2, 0.0), s * 0.18, Color(1, 1, 1, 0.7))


static func syringe(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	ci.draw_line(c + Vector2(0, -s), c + Vector2(0, -s * 0.5), DARK, s * 0.3)
	ci.draw_rect(Rect2(c + Vector2(-s * 0.3, -s * 0.5), Vector2(s * 0.6, s * 1.3)), DARK)
	ci.draw_rect(Rect2(c + Vector2(-s * 0.2, -s * 0.4), Vector2(s * 0.4, s * 1.1)), col)
	ci.draw_line(c + Vector2(-s * 0.55, -s * 0.5), c + Vector2(s * 0.55, -s * 0.5), DARK, s * 0.2)


static func grenade(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	ci.draw_circle(c + Vector2(0, s * 0.15), s * 0.8, DARK)
	ci.draw_circle(c + Vector2(0, s * 0.15), s * 0.66, col)
	ci.draw_rect(Rect2(c + Vector2(-s * 0.2, -s * 0.8), Vector2(s * 0.4, s * 0.35)), DARK)
	ci.draw_line(c + Vector2(s * 0.1, -s * 0.8), c + Vector2(s * 0.7, -s * 0.5), DARK, maxf(s * 0.15, 1.0))
	ci.draw_line(c + Vector2(-s * 0.6, s * 0.15), c + Vector2(s * 0.6, s * 0.15), Color(0, 0, 0, 0.35), maxf(s * 0.12, 1.0))


## Spare magazine.
static func magazine(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	ci.draw_rect(Rect2(c + Vector2(-s * 0.55, -s), Vector2(s * 1.1, s * 2.0)), DARK)
	ci.draw_rect(Rect2(c + Vector2(-s * 0.38, -s * 0.85), Vector2(s * 0.76, s * 1.7)), col)
	ci.draw_line(c + Vector2(-s * 0.38, -s * 0.2), c + Vector2(s * 0.38, -s * 0.2), Color(0, 0, 0, 0.35), maxf(s * 0.12, 1.0))
	ci.draw_line(c + Vector2(-s * 0.38, s * 0.3), c + Vector2(s * 0.38, s * 0.3), Color(0, 0, 0, 0.35), maxf(s * 0.12, 1.0))


static func heart(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	ci.draw_circle(c + Vector2(-s * 0.4, -s * 0.2), s * 0.52, DARK)
	ci.draw_circle(c + Vector2(s * 0.4, -s * 0.2), s * 0.52, DARK)
	_poly(ci, c, s, [Vector2(-0.95, -0.1), Vector2(0.95, -0.1), Vector2(0, 0.95)], DARK)
	ci.draw_circle(c + Vector2(-s * 0.4, -s * 0.2), s * 0.42, col)
	ci.draw_circle(c + Vector2(s * 0.4, -s * 0.2), s * 0.42, col)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.8, -s * 0.05), c + Vector2(s * 0.8, -s * 0.05), c + Vector2(0, s * 0.82)]), col)


static func check(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array([c + Vector2(-s * 0.6, 0), c + Vector2(-s * 0.15, s * 0.5), c + Vector2(s * 0.7, -s * 0.5)])
	ci.draw_polyline(pts, DARK, s * 0.5)
	ci.draw_polyline(pts, col, s * 0.3)


static func cross(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	for d in [Vector2(1, 1), Vector2(1, -1)]:
		ci.draw_line(c - (d as Vector2) * s * 0.6, c + (d as Vector2) * s * 0.6, DARK, s * 0.5)
	for d in [Vector2(1, 1), Vector2(1, -1)]:
		ci.draw_line(c - (d as Vector2) * s * 0.6, c + (d as Vector2) * s * 0.6, col, s * 0.3)


static func star(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var pts: Array = []
	for i in 10:
		var r := 1.0 if i % 2 == 0 else 0.45
		pts.append(Vector2.from_angle(-PI / 2.0 + TAU * i / 10.0) * r)
	_poly(ci, c, s, pts, col)


## Speaker with waves (radio banners).
static func radio(ci: CanvasItem, c: Vector2, s: float, col: Color, t := 0.0) -> void:
	_poly(ci, c + Vector2(-s * 0.3, 0), s, [Vector2(-0.6, -0.3), Vector2(-0.2, -0.3), Vector2(0.3, -0.8), Vector2(0.3, 0.8), Vector2(-0.2, 0.3), Vector2(-0.6, 0.3)], col)
	for i in 3:
		var a := clampf(0.9 - fmod(t * 1.5 + i * 0.3, 0.9), 0.15, 0.9)
		ci.draw_arc(c + Vector2(s * 0.1, 0), s * (0.5 + i * 0.35), -0.8, 0.8, 8, Color(col, a), maxf(s * 0.14, 1.2))


## Triangle arrow pointing along `dir`.
static func arrow(ci: CanvasItem, c: Vector2, dir: Vector2, s: float, col: Color) -> void:
	var side := dir.orthogonal()
	var p := PackedVector2Array([c + dir * s, c - dir * s * 0.7 + side * s * 0.8, c - dir * s * 0.3, c - dir * s * 0.7 - side * s * 0.8])
	var o := p.duplicate()
	o.append(p[0])
	ci.draw_colored_polygon(p, col)
	ci.draw_polyline(o, DARK, maxf(s * 0.18, 1.2))


## Exit / passage marker: chevron stack.
static func exit_marker(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	for i in 2:
		var o := Vector2(0, (i - 0.5) * s * 0.8)
		var pts := PackedVector2Array([c + o + Vector2(-s * 0.7, s * 0.3), c + o + Vector2(0, -s * 0.4), c + o + Vector2(s * 0.7, s * 0.3)])
		ci.draw_polyline(pts, DARK, maxf(s * 0.5, 2.0))
		ci.draw_polyline(pts, col, maxf(s * 0.3, 1.4))


## Hex nest-hole marker.
static func hole(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var pts: Array = []
	for i in 6:
		pts.append(Vector2.from_angle(TAU * i / 6.0))
	_poly(ci, c, s, pts, col)
	ci.draw_circle(c, s * 0.38, DARK)
