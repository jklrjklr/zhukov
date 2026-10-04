class_name MissionMap
extends Node2D
## Sample mission map, 200 x 200 m, built from a fixed seed.
## Layout (north = up):
##   - Drop zone (south), dirt roads joining every point of interest
##   - Ruined outpost (west-centre) with radio terminal A
##   - Rocky ridge (east) with radio terminal B
##   - Forest (north-east) around a clearing with 3 nests
##   - Extraction pad (north-west) with its console
##   - Ammo boxes at points of interest, crates, rock fields and scattered forests
## Draws all static ground/rocks/walls in one canvas item; trees, crates, nests and
## interactables are their own nodes. Keeps simple shapes for the map overlay.

const PX := Firearm.PX_PER_M
const HALF_M := 100.0
const HALF := HALF_M * PX

const GROUND := Color(0.21, 0.26, 0.17)
const DIRT := Color(0.36, 0.31, 0.22)
const CONCRETE := Color(0.42, 0.41, 0.38)
const WALL := Color(0.5, 0.48, 0.44)

## Points of interest (px).
var drop_zone := Vector2(0, 80) * PX
var outpost := Vector2(-50, 5) * PX
var ridge := Vector2(60, -12) * PX
var nest_clearing := Vector2(55, -70) * PX
var extraction := Vector2(-60, -78) * PX
var terminal_spots: Array[Vector2] = []
var nest_spots: Array[Vector2] = []
var console_spot := Vector2.ZERO
var ammo_spots: Array[Vector2] = []

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
	_rng.seed = 20261004
	terminal_spots = [outpost + Vector2(6, -3) * PX, ridge + Vector2(0, 2) * PX]
	for i in 3:
		nest_spots.append(nest_clearing + Vector2.from_angle(TAU * i / 3.0 + 0.4) * 7.0 * PX)
	console_spot = extraction + Vector2(9, 0) * PX
	ammo_spots = [drop_zone + Vector2(4, -3) * PX, outpost + Vector2(-8, 6) * PX,
		ridge + Vector2(-6, 6) * PX, extraction + Vector2(-8, 4) * PX, Vector2(10, -30) * PX]

	for p in [drop_zone, outpost, ridge, nest_clearing, extraction]:
		_clear.append({"pos": p, "r": 14.0 * PX})
	_clear[3].r = 11.0 * PX # nest clearing

	_build_roads()
	_build_outpost()
	_build_ridge()
	_build_forests()
	_build_rock_fields()
	_build_crates()
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


func _build_roads() -> void:
	var hub := Vector2(-5, -20) * PX
	for target in [drop_zone, outpost, ridge, nest_clearing + Vector2(-12, 10) * PX, extraction]:
		var pts := PackedVector2Array()
		var a: Vector2 = hub
		var b: Vector2 = target
		var n := 12
		var bend := Vector2(_rng.randf_range(-8, 8), _rng.randf_range(-8, 8)) * PX
		for i in n + 1:
			var t := float(i) / n
			pts.append(a.lerp(b, t) + bend * sin(t * PI))
		roads.append(pts)
		for p in pts:
			_clear.append({"pos": p, "r": 3.5 * PX})


## Ruined compound: 30 x 22 m, broken walls with gaps, concrete floor.
func _build_outpost() -> void:
	var o := outpost
	var w := 15.0 * PX
	var h := 11.0 * PX
	var t := 0.6 * PX
	floors.append(Rect2(o - Vector2(w, h), Vector2(w, h) * 2))
	# Outer walls as segments with gaps (doors and breaches).
	var segs := [
		[Vector2(-w, -h), Vector2(-4 * PX, -h)], [Vector2(3 * PX, -h), Vector2(w, -h)],
		[Vector2(-w, h), Vector2(-8 * PX, h)], [Vector2(-2 * PX, h), Vector2(w, h)],
		[Vector2(-w, -h), Vector2(-w, -2 * PX)], [Vector2(-w, 3 * PX), Vector2(-w, h)],
		[Vector2(w, -h), Vector2(w, 0)], [Vector2(w, 5 * PX), Vector2(w, h)],
		# Interior
		[Vector2(-3 * PX, -h), Vector2(-3 * PX, -2 * PX)], [Vector2(-3 * PX, 3 * PX), Vector2(-3 * PX, h)],
		[Vector2(-3 * PX, 0), Vector2(3 * PX, 0)],
	]
	for s in segs:
		var a: Vector2 = o + s[0]
		var b: Vector2 = o + s[1]
		var r := Rect2(a, Vector2.ZERO).expand(b).grow(t / 2.0)
		_add_wall(r)


func _build_ridge() -> void:
	# Arc of big rocks shielding terminal B from the east and north.
	for i in 9:
		var a := -PI * 0.9 + i * PI * 0.12
		var p := ridge + Vector2.from_angle(a) * _rng.randf_range(11, 14) * PX
		_add_rock(p, _rng.randf_range(2.0, 3.5) * PX)


func _build_forests() -> void:
	# Big forest around the nest clearing + scattered groves.
	forest_areas.append({"pos": nest_clearing, "r": 32.0 * PX})
	forest_areas.append({"pos": Vector2(-70, 40) * PX, "r": 18.0 * PX})
	forest_areas.append({"pos": Vector2(40, 45) * PX, "r": 16.0 * PX})
	forest_areas.append({"pos": Vector2(-25, -55) * PX, "r": 14.0 * PX})
	forest_areas.append({"pos": Vector2(80, 70) * PX, "r": 15.0 * PX})
	for f in forest_areas:
		var count := int(pow(f.r / PX, 2) * 0.09)
		for i in count:
			var p: Vector2 = f.pos + Vector2.from_angle(_rng.randf() * TAU) * sqrt(_rng.randf()) * f.r
			if _blocked(p, 2.0 * PX) or _near_tree(p, 2.6 * PX):
				continue
			trees.append(p)
	# Lone trees
	for i in 40:
		var p := Vector2(_rng.randf_range(-HALF + 300, HALF - 300), _rng.randf_range(-HALF + 300, HALF - 300))
		if not _blocked(p, 3.0 * PX) and not _near_tree(p, 4.0 * PX):
			trees.append(p)
	for p in trees:
		var tr := Destructible.make(Destructible.Kind.TREE)
		tr.position = p
		add_child(tr)
	for p in nest_spots:
		var nest := Destructible.make(Destructible.Kind.NEST)
		nest.position = p
		add_child(nest)


func _build_rock_fields() -> void:
	var fields := [Vector2(20, 30), Vector2(-80, -20), Vector2(75, 25), Vector2(-30, 55), Vector2(10, -60),
		Vector2(-80, 75), Vector2(85, -40)]
	for c in fields:
		var center: Vector2 = c * PX
		for i in _rng.randi_range(4, 8):
			var p := center + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0, 10) * PX
			if not _blocked(p, 3.0 * PX):
				_add_rock(p, _rng.randf_range(0.8, 2.6) * PX)
	for i in 50:
		var p := Vector2(_rng.randf_range(-HALF + 200, HALF - 200), _rng.randf_range(-HALF + 200, HALF - 200))
		if not _blocked(p, 3.0 * PX):
			_add_rock(p, _rng.randf_range(0.5, 1.4) * PX)


func _build_crates() -> void:
	var spots := [outpost + Vector2(-10, -7) * PX, outpost + Vector2(10, 7) * PX, drop_zone + Vector2(-7, 2) * PX,
		ridge + Vector2(4, 8) * PX, extraction + Vector2(-4, -9) * PX]
	for s in spots:
		for i in _rng.randi_range(2, 4):
			var p: Vector2 = s + Vector2(_rng.randi_range(-1, 1), _rng.randi_range(-1, 1)) * 45.0
			if not _hits_geometry(p, 26.0):
				var c := Destructible.make(Destructible.Kind.CRATE)
				c.position = p
				add_child(c)


func _build_border() -> void:
	var t := 60.0
	for r in [Rect2(-HALF - t, -HALF - t, HALF * 2 + t * 2, t), Rect2(-HALF - t, HALF, HALF * 2 + t * 2, t),
			Rect2(-HALF - t, -HALF, t, HALF * 2), Rect2(HALF, -HALF, t, HALF * 2)]:
		_add_wall(r, false)


func _build_patches() -> void:
	for i in 90:
		_patches.append({
			"pos": Vector2(_rng.randf_range(-HALF, HALF), _rng.randf_range(-HALF, HALF)),
			"r": _rng.randf_range(4, 14) * PX,
			"col": GROUND.lightened(_rng.randf_range(-0.12, 0.1)),
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


## Overlaps a rock or wall already placed (physics may not be updated yet in _ready).
func _hits_geometry(p: Vector2, r: float) -> bool:
	for w in walls:
		if w.grow(r).has_point(p):
			return true
	for rk in rocks:
		if p.distance_to(rk.pos) < (rk.r as float) + r:
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
		draw_circle(f.pos, f.r, Color(0.16, 0.22, 0.13))
	for road in roads:
		draw_polyline(road, DIRT.darkened(0.15), 4.6 * PX)
		draw_polyline(road, DIRT, 3.8 * PX)
	for r in floors:
		draw_rect(r, CONCRETE.darkened(0.25))
	# Drop zone and extraction pad markings
	draw_arc(drop_zone, 5.0 * PX, 0, TAU, 48, Color(1, 1, 1, 0.15), 6.0)
	draw_circle(extraction, 8.0 * PX, CONCRETE.darkened(0.1))
	draw_arc(extraction, 8.0 * PX, 0, TAU, 64, UiStyle.YELLOW.darkened(0.3), 10.0)
	draw_arc(extraction, 5.5 * PX, 0, TAU, 64, Color(1, 1, 1, 0.25), 4.0)
	draw_line(extraction + Vector2(-3, 0) * PX, extraction + Vector2(3, 0) * PX, Color(1, 1, 1, 0.3), 8.0)
	draw_line(extraction + Vector2(0, -3) * PX, extraction + Vector2(0, 3) * PX, Color(1, 1, 1, 0.3), 8.0)
	# Nest clearing: dark churned ground
	draw_circle(nest_clearing, 11.0 * PX, Color(0.24, 0.18, 0.15))
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
