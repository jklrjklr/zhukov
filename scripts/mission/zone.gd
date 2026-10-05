class_name Zone
extends Node2D
## One 120 x 120 m zone of the Terminid planet (v0.5 slice). The layout (walls, ruins,
## compounds, barricades) is hand-built per zone type; rocks, trees, crates and the
## objective / POI / enemy slots chosen on top of it are randomised each run.
## Zone-local layout is authored in metres (north = -y); the node sits at the zone's
## world centre. South and north walls have an 8 m opening where the passages join.
## Draws the static ground, walls and rocks in one canvas item (z below actors).
## Props with behaviour (crates, trees, nest holes, terminals) are created by Mission
## from the spot lists here.

enum Type { INSERTION, MIDDLE, EXTRACTION }

const PX := Firearm.PX_PER_M
const SIZE_M := 120.0
const HALF_M := SIZE_M * 0.5
const HALF := HALF_M * PX
const GAP_M := 8.0
const NAMES := ["INSERTION ZONE", "MIDDLE ZONE", "EXTRACTION ZONE"]
const GROUNDS := [Color(0.33, 0.29, 0.2), Color(0.3, 0.27, 0.21), Color(0.27, 0.29, 0.21)]
const WALL := Color(0.5, 0.47, 0.42)
const CONCRETE := Color(0.4, 0.39, 0.36)

var type := Type.INSERTION
var zone_name := ""
## World rectangle of the zone interior.
var rect := Rect2()
## World positions.
var start_pos := Vector2.ZERO
var terminal_pos := Vector2.INF
var pad_pos := Vector2.INF
var entrance_pt := Vector2.ZERO
var exit_pt := Vector2.ZERO
## name -> Array[Vector2] (world): nest, sample, ammo, pack, edge, elite.
var slots := {}
var trees: Array[Vector2] = []
var crates: Array[Vector2] = []
## Drawn layers (zone-local px).
var walls: Array[Rect2] = []
var floors: Array[Rect2] = []
var rocks: Array[Dictionary] = []

var _rng := RandomNumberGenerator.new()
var _clear: Array[Dictionary] = [] # {pos, r} px, local: keep free of rocks/trees/crates
var _patches: Array[Dictionary] = []
var _decals: Array[Dictionary] = []
var _forest: Array[Dictionary] = []


## Build the layout. Call after the node is in the tree and positioned.
func build(t: int, world_center: Vector2, seed_value: int) -> void:
	type = t as Type
	zone_name = NAMES[t]
	position = world_center
	rect = Rect2(world_center - Vector2(HALF, HALF), Vector2(HALF, HALF) * 2.0)
	z_index = -10
	_rng.seed = seed_value
	_border()
	var local_slots := {"nest": [], "sample": [], "ammo": [], "pack": [], "edge": [], "elite": []}
	match type:
		Type.INSERTION:
			_layout_insertion(local_slots)
		Type.MIDDLE:
			_layout_middle(local_slots)
		Type.EXTRACTION:
			_layout_extraction(local_slots)
	for k in local_slots:
		var list: Array = local_slots[k]
		var out: Array[Vector2] = []
		for p in list:
			out.append(position + (p as Vector2) * PX)
		out.shuffle()
		slots[k] = out
	entrance_pt = position + Vector2(0, HALF_M - 2.0) * PX
	exit_pt = position + Vector2(0, -HALF_M + 2.0) * PX
	_scatter()
	_make_decor()
	queue_redraw()


func contains(p: Vector2, margin := 0.0) -> bool:
	return rect.grow(margin).has_point(p)


func _m(x: float, y: float) -> Vector2:
	return Vector2(x, y) * PX


# --- Layouts (metres, zone-local) --------------------------------------------------

func _border() -> void:
	var t := 2.0
	var h := HALF_M
	var g := GAP_M * 0.5
	# North and south walls with the passage openings.
	for y in [-h - t, h]:
		_wall_rect(Rect2(-h - t, y, h - g + t, t))
		_wall_rect(Rect2(g, y, h - g + t, t))
	_wall_rect(Rect2(-h - t, -h, t, h * 2.0))
	_wall_rect(Rect2(h, -h, t, h * 2.0))
	_clear.append({"pos": _m(0, h - 6), "r": 12.0 * PX})
	_clear.append({"pos": _m(0, -h + 6), "r": 12.0 * PX})


func _layout_insertion(s: Dictionary) -> void:
	start_pos = position + _m(0, 44)
	_clear.append({"pos": _m(0, 44), "r": 9.0 * PX})
	_ruin(Vector2(-36, 14), 14, 10)
	_ruin(Vector2(36, 18), 12, 10)
	_ruin(Vector2(-6, -8), 10, 8)
	_ruin(Vector2(26, -24), 10, 8)
	_seg(Vector2(-12, 36), Vector2(-5, 36))
	_seg(Vector2(5, 36), Vector2(12, 36))
	_seg(Vector2(-22, -24), Vector2(-12, -24))
	_seg(Vector2(10, 4), Vector2(20, 4))
	_seg(Vector2(-26, 40), Vector2(-17, 40))
	s.nest = [Vector2(-34, -38), Vector2(32, -40), Vector2(2, -32), Vector2(-46, -10), Vector2(46, -12)]
	s.sample = [Vector2(-48, 42), Vector2(48, 40), Vector2(0, -50), Vector2(-24, -4)]
	s.ammo = [Vector2(-22, 38), Vector2(22, 38), Vector2(-46, 24), Vector2(46, 26)]
	s.pack = [Vector2(-30, -8), Vector2(30, -8), Vector2(12, -36), Vector2(-16, -32), Vector2(-42, 28),
		Vector2(40, 4), Vector2(0, 12)]
	s.edge = [Vector2(-56, -12), Vector2(56, -12), Vector2(-56, 20), Vector2(56, 20), Vector2(-30, -56),
		Vector2(30, -56)]
	s.elite = [Vector2(-20, -42), Vector2(22, -38), Vector2(-4, 20)]
	_keep_clear(s)


func _layout_middle(s: Dictionary) -> void:
	start_pos = position + _m(0, 54)
	terminal_pos = position + _m(0, -4)
	_compound(Vector2(0, -4), 28, 20, 6.0)
	_ruin(Vector2(-40, -34), 12, 10)
	_ruin(Vector2(40, -30), 12, 10)
	_ruin(Vector2(-42, 26), 12, 10)
	_ruin(Vector2(42, 30), 12, 10)
	_seg(Vector2(-14, 30), Vector2(-4, 30))
	_seg(Vector2(4, 30), Vector2(14, 30))
	_seg(Vector2(-20, -32), Vector2(-8, -32))
	_seg(Vector2(8, -32), Vector2(20, -32))
	s.sample = [Vector2(-24, 44), Vector2(26, 44), Vector2(-50, 0), Vector2(50, -2)]
	s.ammo = [Vector2(-16, 14), Vector2(16, 14), Vector2(-46, -16), Vector2(46, -14)]
	s.pack = [Vector2(-26, 8), Vector2(26, 8), Vector2(-28, -22), Vector2(28, -20), Vector2(0, -26),
		Vector2(-12, 24), Vector2(14, 22), Vector2(-48, 12), Vector2(48, 14)]
	s.edge = [Vector2(-56, -26), Vector2(56, -26), Vector2(-56, 4), Vector2(56, 4), Vector2(-30, -56),
		Vector2(30, -56)]
	s.elite = [Vector2(-24, -46), Vector2(26, -44), Vector2(0, 36)]
	s.nest = [Vector2(-30, -48), Vector2(32, -48), Vector2(-52, 36), Vector2(52, 36)]
	_keep_clear(s)


func _layout_extraction(s: Dictionary) -> void:
	start_pos = position + _m(0, 54)
	pad_pos = position + _m(0, -30)
	terminal_pos = position + _m(16, -16)
	_clear.append({"pos": _m(0, -30), "r": 11.0 * PX})
	floors.append(Rect2(_m(-9, -39), _m(18, 18)))
	_compound(Vector2(16, -16), 12, 10, 5.0)
	_ruin(Vector2(-38, -4), 14, 10)
	_ruin(Vector2(38, 10), 14, 10)
	_ruin(Vector2(-22, 26), 10, 8)
	_ruin(Vector2(24, 34), 10, 8)
	_seg(Vector2(-16, 6), Vector2(-6, 6))
	_seg(Vector2(6, 6), Vector2(16, 6))
	_seg(Vector2(-30, -26), Vector2(-20, -26))
	s.sample = [Vector2(-50, 40), Vector2(50, 44), Vector2(-46, -44), Vector2(44, -42)]
	s.ammo = [Vector2(-10, 20), Vector2(10, 20), Vector2(-48, 12), Vector2(48, 22)]
	s.pack = [Vector2(-28, -14), Vector2(30, -2), Vector2(-14, 12), Vector2(18, 22), Vector2(-46, -30),
		Vector2(46, -26), Vector2(0, -8), Vector2(-40, 30)]
	s.edge = [Vector2(-56, -20), Vector2(56, -20), Vector2(-56, 10), Vector2(56, 10), Vector2(-30, -56),
		Vector2(30, -56)]
	s.elite = [Vector2(-24, -40)]
	s.nest = [Vector2(-34, -44), Vector2(34, -46), Vector2(-52, 30), Vector2(52, 36)]
	_keep_clear(s)


## Slots, objectives and POIs keep rocks/trees away.
func _keep_clear(s: Dictionary) -> void:
	for k in s:
		for p in s[k]:
			_clear.append({"pos": (p as Vector2) * PX, "r": 3.5 * PX})


## Wall from a to b (metres), 1 m thick.
func _seg(a: Vector2, b: Vector2, thick := 1.0) -> void:
	_wall_rect(Rect2(a, Vector2.ZERO).expand(b).grow(thick * 0.5))


## Ruined building: broken walls with doorways (half-size w/2 x h/2 around c).
func _ruin(c: Vector2, w: float, h: float) -> void:
	var hw := w * 0.5
	var hh := h * 0.5
	floors.append(Rect2((c - Vector2(hw, hh)) * PX, Vector2(w, h) * PX))
	_seg(c + Vector2(-hw, -hh), c + Vector2(hw * 0.2, -hh), 0.8)
	_seg(c + Vector2(-hw, -hh), c + Vector2(-hw, hh * 0.3), 0.8)
	_seg(c + Vector2(hw, -hh * 0.2), c + Vector2(hw, hh), 0.8)
	_seg(c + Vector2(-hw * 0.3, hh), c + Vector2(hw, hh), 0.8)
	_clear.append({"pos": c * PX, "r": maxf(w, h) * 0.5 * PX + 2.0 * PX})


## Walled square with an opening of `gap` m in the middle of every side.
func _compound(c: Vector2, w: float, h: float, gap: float) -> void:
	var hw := w * 0.5
	var hh := h * 0.5
	var g := gap * 0.5
	floors.append(Rect2((c - Vector2(hw, hh)) * PX, Vector2(w, h) * PX))
	for y in [-hh, hh]:
		_seg(c + Vector2(-hw, y), c + Vector2(-g, y), 1.0)
		_seg(c + Vector2(g, y), c + Vector2(hw, y), 1.0)
	for x in [-hw, hw]:
		_seg(c + Vector2(x, -hh), c + Vector2(x, -g), 1.0)
		_seg(c + Vector2(x, g), c + Vector2(x, hh), 1.0)
	_clear.append({"pos": c * PX, "r": maxf(w, h) * 0.5 * PX + 3.0 * PX})


# --- Random props on top ------------------------------------------------------------

func _scatter() -> void:
	var fields := [Vector2(-30, -30), Vector2(30, -40), Vector2(-50, 10), Vector2(50, 0), Vector2(0, 30),
		Vector2(-20, 46), Vector2(24, -8), Vector2(-8, -48)]
	fields.shuffle()
	for c in fields.slice(0, 5):
		var center: Vector2 = (c as Vector2) * PX + Vector2(_rng.randf_range(-5, 5), _rng.randf_range(-5, 5)) * PX
		for i in _rng.randi_range(3, 6):
			var p := center + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0, 7) * PX
			if not _blocked(p, 2.5 * PX):
				_add_rock(p, _rng.randf_range(0.8, 2.4) * PX)
	for i in 28:
		var p := Vector2(_rng.randf_range(-HALF + 120, HALF - 120), _rng.randf_range(-HALF + 120, HALF - 120))
		if not _blocked(p, 2.5 * PX):
			_add_rock(p, _rng.randf_range(0.5, 1.4) * PX)
	for i in 3:
		var f := {"pos": Vector2(_rng.randf_range(-48, 48), _rng.randf_range(-48, 48)) * PX, "r": _rng.randf_range(8, 12) * PX}
		if _blocked(f.pos, 4.0 * PX):
			continue
		_forest.append(f)
		for j in int(pow(f.r / PX, 2) * 0.07):
			var p: Vector2 = f.pos + Vector2.from_angle(_rng.randf() * TAU) * sqrt(_rng.randf()) * f.r
			if not _blocked(p, 2.0 * PX) and not _near(trees, p, 2.6 * PX):
				trees.append(p + position)
	for i in 10:
		var p := Vector2(_rng.randf_range(-HALF + 150, HALF - 150), _rng.randf_range(-HALF + 150, HALF - 150))
		if not _blocked(p, 2.5 * PX):
			crates.append(p + position)
			_clear.append({"pos": p, "r": 1.0 * PX})


func _make_decor() -> void:
	var ground: Color = GROUNDS[type]
	for i in 60:
		_patches.append({"pos": Vector2(_rng.randf_range(-HALF, HALF), _rng.randf_range(-HALF, HALF)),
			"r": _rng.randf_range(3, 11) * PX, "col": ground.lightened(_rng.randf_range(-0.1, 0.08))})
	for i in 70:
		var p := Vector2(_rng.randf_range(-HALF, HALF), _rng.randf_range(-HALF, HALF))
		_decals.append({"pos": p, "a": _rng.randf() * TAU, "len": _rng.randf_range(10, 40), "kind": _rng.randi() % 3})


func _blocked(p: Vector2, margin: float) -> bool:
	if absf(p.x) > HALF - 100.0 or absf(p.y) > HALF - 100.0:
		return true
	for c in _clear:
		if p.distance_to(c.pos) < c.r + margin:
			return true
	for r in walls:
		if r.grow(margin).has_point(p):
			return true
	return false


func _near(list: Array[Vector2], p: Vector2, d: float) -> bool:
	for t in list:
		if (t - position).distance_squared_to(p) < d * d:
			return true
	return false


## Wall from a rectangle in metres.
func _wall_rect(r: Rect2, visible_wall := true) -> void:
	var rect_px := Rect2(r.position * PX, r.size * PX)
	var body := StaticBody2D.new()
	body.position = rect_px.get_center()
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect_px.size
	col.shape = shape
	body.add_child(col)
	add_child(body)
	if visible_wall:
		walls.append(rect_px)
		Vision.add_occluder(body, Vision.rect_points(rect_px.size))


func _add_rock(p: Vector2, radius: float) -> void:
	var poly := _blunt_blob(radius)
	var body := StaticBody2D.new()
	body.position = p
	var col := CollisionPolygon2D.new()
	col.polygon = poly
	body.add_child(col)
	Vision.add_occluder(body, poly)
	add_child(body)
	var world_poly := PackedVector2Array()
	for v in poly:
		world_poly.append(v + p)
	rocks.append({"poly": world_poly, "pos": p, "r": radius, "shade": _rng.randf_range(0.3, 0.45)})
	_clear.append({"pos": p, "r": radius + 30.0})


func _blunt_blob(radius: float) -> PackedVector2Array:
	var n := 14
	var radii: Array[float] = []
	for i in n:
		radii.append(radius * _rng.randf_range(0.75, 1.0))
	for pass_i in 2:
		var smooth: Array[float] = []
		for i in n:
			smooth.append((radii[i - 1] + radii[i] * 2.0 + radii[(i + 1) % n]) / 4.0)
		radii = smooth
	var start := _rng.randf() * TAU
	var pts := PackedVector2Array()
	for i in n:
		var a := start + TAU * i / n
		pts.append(Vector2(cos(a), sin(a)) * radii[i])
	return pts


func _draw() -> void:
	var ground: Color = GROUNDS[type]
	draw_rect(Rect2(-HALF - 120, -HALF - 120, HALF * 2 + 240, HALF * 2 + 240), Color(0.06, 0.06, 0.05))
	draw_rect(Rect2(-HALF, -HALF, HALF * 2, HALF * 2), ground)
	for p in _patches:
		draw_circle(p.pos, p.r, p.col)
	for f in _forest:
		draw_circle(f.pos, f.r, Color(0.2, 0.2, 0.12))
	for d in _decals:
		var p: Vector2 = d.pos
		var dir := Vector2.from_angle(d.a)
		match d.kind:
			0: # crack
				draw_polyline(PackedVector2Array([p, p + dir * d.len * 0.5 + dir.orthogonal() * 4.0, p + dir * d.len]),
					ground.darkened(0.3), 2.0)
			1: # pebbles
				draw_circle(p, 3.0, ground.darkened(0.2))
				draw_circle(p + dir * 6.0, 2.0, ground.lightened(0.1))
			_: # grass tuft
				for k in 3:
					draw_line(p, p + dir.rotated(-0.5 + k * 0.5) * 9.0, Color(0.3, 0.38, 0.18), 1.5)
	for r in floors:
		draw_rect(r, CONCRETE.darkened(0.25))
	if pad_pos != Vector2.INF:
		var lp := pad_pos - position
		draw_circle(lp, 8.0 * PX, CONCRETE.darkened(0.05))
		draw_arc(lp, 8.0 * PX, 0, TAU, 64, UiStyle.YELLOW.darkened(0.3), 8.0)
		draw_arc(lp, 5.0 * PX, 0, TAU, 48, UiStyle.YELLOW.darkened(0.5), 4.0)
		draw_line(lp + Vector2(-3, 0) * PX, lp + Vector2(3, 0) * PX, Color(1, 1, 1, 0.3), 8.0)
		draw_line(lp + Vector2(0, -3) * PX, lp + Vector2(0, 3) * PX, Color(1, 1, 1, 0.3), 8.0)
	if type == Type.INSERTION:
		draw_arc(start_pos - position, 4.0 * PX, 0, TAU, 48, Color(1, 1, 1, 0.15), 6.0)
	for r in rocks:
		var shade: float = r.shade
		var poly: PackedVector2Array = r.poly
		var center: Vector2 = r.pos
		for o in Geometry2D.offset_polygon(poly, 2.0):
			draw_colored_polygon(o, Color(0.08, 0.08, 0.08))
		draw_colored_polygon(poly, Color(shade, shade * 0.95, shade * 0.85))
		var top := PackedVector2Array()
		for v in poly:
			top.append(center + (v - center) * 0.55 + Vector2(-0.18, -0.18) * (r.r as float))
		draw_colored_polygon(top, Color(shade + 0.08, shade + 0.08, shade + 0.04))
	for r in walls:
		draw_rect(r.grow(2.0), Color(0.08, 0.08, 0.08))
		draw_rect(r, WALL)
		draw_rect(Rect2(r.position, Vector2(r.size.x, minf(r.size.y, 4.0))), WALL.lightened(0.15))
