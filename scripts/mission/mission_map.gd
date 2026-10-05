class_name MissionMap
extends Node2D
## Defense map "Bright Harbor", 160 x 160 m, built from a fixed seed.
## Layout (north = up):
##   - Evacuation site in the centre-south: 56 x 44 m walled compound with three gates
##     (west, north, east; the south wall backs onto cliffs). Inside: 3 generators,
##     the evac rocket pad, the Pelican pad with its console, ammo boxes, drop zone.
##   - Barricades and crates in front of every gate (cover and chokepoints).
##   - Roads from each gate out to the warp-ship landing zones (north, west, east,
##     north-west, north-east), rocks, ruins and groves on the approaches.
## Draws all static ground/rocks/walls in one canvas item; trees, crates and
## interactables are their own nodes. Keeps simple shapes for the map overlay.

const PX := Firearm.PX_PER_M
const HALF_M := 80.0
const HALF := HALF_M * PX

const GROUND := Color(0.24, 0.25, 0.2)
const DIRT := Color(0.36, 0.31, 0.22)
const CONCRETE := Color(0.42, 0.41, 0.38)
const WALL := Color(0.52, 0.5, 0.46)
const GATE_W_M := 7.0

## Base (px).
var base_rect := Rect2(Vector2(-28, -12) * PX, Vector2(56, 44) * PX)
var base_center := Vector2(0, 10) * PX
## {pos, normal (outward)}
var gates: Array[Dictionary] = []
var generator_spots: Array[Vector2] = []
var rocket_pad := Vector2(0, 6) * PX
var drop_zone := Vector2(-12, 22) * PX
var extraction := Vector2(14, 21) * PX
var console_spot := Vector2(23, 27) * PX
var ammo_spots: Array[Vector2] = []
## Warp-ship landing zones.
var spawn_points: Array[Vector2] = []
## Unused by this map (kept for the HUD/mission API).
var terminal_spots: Array[Vector2] = []
var nest_spots: Array[Vector2] = []

## Overlay/minimap data.
var roads: Array[PackedVector2Array] = []
var rocks: Array[Dictionary] = []
var walls: Array[Rect2] = []
var floors: Array[Rect2] = []
var forest_areas: Array[Dictionary] = []
var trees: Array[Vector2] = []

var _rng := RandomNumberGenerator.new()
var _clear: Array[Dictionary] = [] # {pos, r}: keep free of rocks/trees
var _patches: Array[Dictionary] = []


func _ready() -> void:
	_rng.seed = 20261005
	gates = [
		{"pos": Vector2(-28, 10) * PX, "normal": Vector2.LEFT, "name": "west"},
		{"pos": Vector2(0, -12) * PX, "normal": Vector2.UP, "name": "north"},
		{"pos": Vector2(28, 10) * PX, "normal": Vector2.RIGHT, "name": "east"},
	]
	generator_spots = [Vector2(-17, -3) * PX, Vector2(17, -3) * PX, Vector2(-1, 25) * PX]
	ammo_spots = [Vector2(-24, 28) * PX, Vector2(-23, -8) * PX, Vector2(23, -8) * PX, Vector2(6, 14) * PX]
	spawn_points = [Vector2(0, -66) * PX, Vector2(-66, 4) * PX, Vector2(66, 4) * PX,
		Vector2(-52, -52) * PX, Vector2(52, -52) * PX]

	_clear.append({"pos": base_center, "r": 40.0 * PX})
	for g in gates:
		_clear.append({"pos": g.pos + (g.normal as Vector2) * 10.0 * PX, "r": 9.0 * PX})
	for p in spawn_points:
		_clear.append({"pos": p, "r": 10.0 * PX})

	_build_roads()
	_build_base()
	_build_barricades()
	_build_ruins()
	_build_forests()
	_build_rock_fields()
	_build_border()
	_build_patches()
	queue_redraw()


## Free spot for spawning (no bodies within r).
func is_free(p: Vector2, r := 24.0) -> bool:
	if absf(p.x) > HALF - 100 or absf(p.y) > HALF - 100:
		return false
	var q := PhysicsShapeQueryParameters2D.new()
	var c := CircleShape2D.new()
	c.radius = r
	q.shape = c
	q.transform = Transform2D(0.0, p)
	return get_world_2d().direct_space_state.intersect_shape(q, 1).is_empty()


## Random free point between min_m and max_m from `around` (or Vector2.INF).
func random_point_near(around: Vector2, min_m: float, max_m: float, tries := 30) -> Vector2:
	for i in tries:
		var p := around + Vector2.from_angle(randf() * TAU) * randf_range(min_m, max_m) * PX
		if is_free(p, 30.0):
			return p
	return Vector2.INF


func is_inside_base(p: Vector2) -> bool:
	return base_rect.grow(-0.6 * PX).has_point(p)


## Next waypoint for a ground unit going from `from` to `to`: through a gate when one
## of them is inside the walls and the other is not.
func route(from: Vector2, to: Vector2) -> Vector2:
	var in_from := is_inside_base(from)
	var in_to := is_inside_base(to)
	if in_from == in_to:
		return to
	var best: Dictionary = gates[0]
	var best_cost := INF
	for g in gates:
		var cost := from.distance_to(g.pos) + (g.pos as Vector2).distance_to(to)
		if cost < best_cost:
			best_cost = cost
			best = g
	var n: Vector2 = best.normal
	var outer: Vector2 = best.pos + n * 4.0 * PX
	var inner: Vector2 = best.pos - n * 3.0 * PX
	var first := inner if in_from else outer
	var second := outer if in_from else inner
	# In the gate lane (lined up with the gap): go straight through.
	var rel := from - (best.pos as Vector2)
	var along := rel.dot(n)
	var across := absf(rel.cross(n))
	if across < GATE_W_M * 0.35 * PX and absf(along) < 5.0 * PX:
		return second
	return first


func _build_roads() -> void:
	for g in gates:
		var a: Vector2 = g.pos + (g.normal as Vector2) * 1.0 * PX
		var targets: Array[Vector2] = []
		for s in spawn_points:
			if (s - a).normalized().dot(g.normal) > 0.3:
				targets.append(s)
		for b in targets:
			var pts := PackedVector2Array()
			var n := 12
			var bend := Vector2(_rng.randf_range(-6, 6), _rng.randf_range(-6, 6)) * PX
			for i in n + 1:
				var t := float(i) / n
				pts.append(a.lerp(b, t) + bend * sin(t * PI))
			roads.append(pts)
			for p in pts:
				_clear.append({"pos": p, "r": 3.5 * PX})


func _build_base() -> void:
	var r := base_rect
	floors.append(r)
	var t := 0.8 * PX
	var gw := GATE_W_M * PX / 2.0
	var l := r.position.x
	var rt := r.end.x
	var top := r.position.y
	var bot := r.end.y
	var gy: float = (gates[0].pos as Vector2).y
	var segs := [
		[Vector2(l, top), Vector2(-gw, top)], [Vector2(gw, top), Vector2(rt, top)], # north
		[Vector2(l, bot), Vector2(rt, bot)], # south
		[Vector2(l, top), Vector2(l, gy - gw)], [Vector2(l, gy + gw), Vector2(l, bot)], # west
		[Vector2(rt, top), Vector2(rt, gy - gw)], [Vector2(rt, gy + gw), Vector2(rt, bot)], # east
		# Interior: low dividers around the rocket pad (cover inside the base)
		[Vector2(-9, 13) * PX, Vector2(-4, 13) * PX], [Vector2(4, 13) * PX, Vector2(9, 13) * PX],
	]
	for s in segs:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		_add_wall(Rect2(a, Vector2.ZERO).expand(b).grow(t / 2.0))
	# Watch towers at the corners
	for c in [r.position, Vector2(rt, top), Vector2(l, bot), r.end]:
		_add_wall(Rect2(c - Vector2(1.4, 1.4) * PX, Vector2(2.8, 2.8) * PX))


## Barricade walls and crates outside every gate.
func _build_barricades() -> void:
	for g in gates:
		var n: Vector2 = g.normal
		var side := n.orthogonal()
		var c: Vector2 = g.pos + n * 7.0 * PX
		for k in [-1.0, 1.0]:
			var p: Vector2 = c + side * k * 5.5 * PX
			var half := (side * 2.0 + n * 0.4) * PX
			_add_wall(Rect2(p - half.abs(), half.abs() * 2.0))
		for k in [-1.0, 1.0]:
			var cp: Vector2 = g.pos + n * 13.0 * PX + side * k * 3.0 * PX
			var crate := Destructible.make(Destructible.Kind.CRATE)
			crate.position = cp
			add_child(crate)


## Ruined buildings on the approaches (cover for both sides).
func _build_ruins() -> void:
	for spot in [Vector2(-38, -30), Vector2(36, -28), Vector2(-14, -40), Vector2(20, -46), Vector2(-46, 26), Vector2(48, 28)]:
		var o: Vector2 = spot * PX
		var w := _rng.randf_range(4.0, 6.0) * PX
		var h := _rng.randf_range(3.0, 5.0) * PX
		var t := 0.6 * PX
		floors.append(Rect2(o - Vector2(w, h), Vector2(w, h) * 2))
		var segs := [[Vector2(-w, -h), Vector2(w * 0.2, -h)], [Vector2(-w, -h), Vector2(-w, h * 0.3)],
			[Vector2(w, -h * 0.2), Vector2(w, h)], [Vector2(-w * 0.3, h), Vector2(w, h)]]
		for s in segs:
			var a: Vector2 = o + s[0]
			var b: Vector2 = o + s[1]
			_add_wall(Rect2(a, Vector2.ZERO).expand(b).grow(t / 2.0))
		_clear.append({"pos": o, "r": maxf(w, h) + 1.5 * PX})


func _build_forests() -> void:
	forest_areas.append({"pos": Vector2(-56, -26) * PX, "r": 14.0 * PX})
	forest_areas.append({"pos": Vector2(58, -24) * PX, "r": 13.0 * PX})
	forest_areas.append({"pos": Vector2(-30, 58) * PX, "r": 15.0 * PX})
	forest_areas.append({"pos": Vector2(36, 58) * PX, "r": 14.0 * PX})
	for f in forest_areas:
		var count := int(pow(f.r / PX, 2) * 0.08)
		for i in count:
			var p: Vector2 = f.pos + Vector2.from_angle(_rng.randf() * TAU) * sqrt(_rng.randf()) * f.r
			if _blocked(p, 2.0 * PX) or _near_tree(p, 2.6 * PX):
				continue
			trees.append(p)
	for i in 25:
		var p := Vector2(_rng.randf_range(-HALF + 300, HALF - 300), _rng.randf_range(-HALF + 300, HALF - 300))
		if not _blocked(p, 3.0 * PX) and not _near_tree(p, 4.0 * PX):
			trees.append(p)
	for p in trees:
		var tr := Destructible.make(Destructible.Kind.TREE)
		tr.position = p
		add_child(tr)


func _build_rock_fields() -> void:
	var fields := [Vector2(-28, -28), Vector2(26, -36), Vector2(-62, -6), Vector2(62, 18), Vector2(0, -52),
		Vector2(-60, 50), Vector2(60, 50)]
	for c in fields:
		var center: Vector2 = c * PX
		for i in _rng.randi_range(3, 6):
			var p := center + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0, 8) * PX
			if not _blocked(p, 3.0 * PX):
				_add_rock(p, _rng.randf_range(0.8, 2.4) * PX)
	for i in 30:
		var p := Vector2(_rng.randf_range(-HALF + 200, HALF - 200), _rng.randf_range(-HALF + 200, HALF - 200))
		if not _blocked(p, 3.0 * PX):
			_add_rock(p, _rng.randf_range(0.5, 1.4) * PX)
	# Cliffs south of the base: a band of big rocks.
	for i in 14:
		var p := Vector2(-40 + i * 6.2, _rng.randf_range(38, 42)) * PX
		_add_rock(p, _rng.randf_range(2.6, 3.6) * PX)


func _build_border() -> void:
	var t := 60.0
	for r in [Rect2(-HALF - t, -HALF - t, HALF * 2 + t * 2, t), Rect2(-HALF - t, HALF, HALF * 2 + t * 2, t),
			Rect2(-HALF - t, -HALF, t, HALF * 2), Rect2(HALF, -HALF, t, HALF * 2)]:
		_add_wall(r, false)


func _build_patches() -> void:
	for i in 70:
		_patches.append({
			"pos": Vector2(_rng.randf_range(-HALF, HALF), _rng.randf_range(-HALF, HALF)),
			"r": _rng.randf_range(4, 14) * PX,
			"col": GROUND.lightened(_rng.randf_range(-0.1, 0.08)),
		})


func _add_wall(r: Rect2, visible_wall := true) -> void:
	var body := StaticBody2D.new()
	body.position = r.get_center()
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = r.size
	col.shape = shape
	body.add_child(col)
	add_child(body)
	if visible_wall:
		walls.append(r)
		Vision.add_occluder(body, Vision.rect_points(r.size))


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


func _blocked(p: Vector2, margin: float) -> bool:
	if absf(p.x) > HALF - 150 or absf(p.y) > HALF - 150:
		return true
	for c in _clear:
		if p.distance_to(c.pos) < c.r + margin:
			return true
	for r in walls:
		if r.grow(margin).has_point(p):
			return true
	return false


func _near_tree(p: Vector2, d: float) -> bool:
	for t in trees:
		if t.distance_squared_to(p) < d * d:
			return true
	return false


func _draw() -> void:
	draw_rect(Rect2(-HALF, -HALF, HALF * 2, HALF * 2), GROUND)
	for p in _patches:
		draw_circle(p.pos, p.r, p.col)
	for f in forest_areas:
		draw_circle(f.pos, f.r, Color(0.17, 0.21, 0.14))
	for road in roads:
		draw_polyline(road, DIRT.darkened(0.15), 4.6 * PX)
		draw_polyline(road, DIRT, 3.8 * PX)
	for r in floors:
		draw_rect(r, CONCRETE.darkened(0.25))
	# Base markings: gate lanes, rocket pad, Pelican pad, drop zone
	for g in gates:
		var n: Vector2 = g.normal
		var a: Vector2 = g.pos
		draw_line(a - n * 2.0 * PX, a + n * 2.0 * PX, UiStyle.YELLOW.darkened(0.45), GATE_W_M * PX)
		draw_line(a - n * 2.0 * PX, a + n * 2.0 * PX, CONCRETE.darkened(0.15), GATE_W_M * PX - 16.0)
	draw_circle(rocket_pad, 5.5 * PX, CONCRETE.darkened(0.05))
	draw_arc(rocket_pad, 5.5 * PX, 0, TAU, 48, UiStyle.YELLOW.darkened(0.3), 8.0)
	for i in 8:
		var a := TAU * i / 8.0
		draw_line(rocket_pad + Vector2.from_angle(a) * 3.0 * PX, rocket_pad + Vector2.from_angle(a) * 5.0 * PX, Color(0.1, 0.1, 0.1, 0.6), 6.0)
	draw_circle(extraction, 6.0 * PX, CONCRETE.darkened(0.1))
	draw_arc(extraction, 6.0 * PX, 0, TAU, 64, UiStyle.YELLOW.darkened(0.3), 8.0)
	draw_line(extraction + Vector2(-2.5, 0) * PX, extraction + Vector2(2.5, 0) * PX, Color(1, 1, 1, 0.3), 8.0)
	draw_line(extraction + Vector2(0, -2.5) * PX, extraction + Vector2(0, 2.5) * PX, Color(1, 1, 1, 0.3), 8.0)
	draw_arc(drop_zone, 4.0 * PX, 0, TAU, 48, Color(1, 1, 1, 0.15), 6.0)
	# Warp zones: purple scorch where the ships land
	for p in spawn_points:
		draw_circle(p, 7.0 * PX, Color(0.3, 0.2, 0.35, 0.35))
		draw_arc(p, 7.0 * PX, 0, TAU, 40, Color(0.7, 0.4, 1.0, 0.3), 5.0)
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
	draw_rect(Rect2(-HALF, -HALF, HALF * 2, HALF * 2), Color(0.6, 0.15, 0.1), false, 14.0)
