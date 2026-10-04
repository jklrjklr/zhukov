extends Node2D
## Placeholder test arena: gridded ground (1 cell = 100 px), random rocks, border walls,
## a firing lane of target dummies straight ahead (north) and a wall to test weapon length.

const HALF_SIZE := 3000.0
const GRID := 100.0
const ROCK_COUNT := 110
const DUMMY_METERS := [5, 10, 20, 35, 50]
const TEST_WALL := Rect2(160, -40, 40, 200)
## Armored dummies at 8 m, right of the lane: armor class each.
const ARMORED_CLASSES := [1, 2, 3, 4, 6]
const CRATES := [Vector2(-220, -60), Vector2(-265, -60), Vector2(-220, -105), Vector2(-320, 120)]
const TREES := [Vector2(-330, -300), Vector2(380, 260)]
const RANDOM_TREES := 30

var _dummy_script := preload("res://scripts/target_dummy.gd")

var _rocks: Array[Dictionary] = []


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	while _rocks.size() < ROCK_COUNT:
		var pos := Vector2(
			rng.randf_range(-HALF_SIZE + 100, HALF_SIZE - 100),
			rng.randf_range(-HALF_SIZE + 100, HALF_SIZE - 100))
		if pos.length() < 300.0:
			continue # keep spawn clear
		if absf(pos.x) < 250.0 and pos.y < 0.0:
			continue # keep firing lane clear
		var radius := rng.randf_range(25.0, 80.0)
		var poly := _blunt_blob(rng, radius)
		var body := StaticBody2D.new()
		body.position = pos
		var col := CollisionPolygon2D.new()
		col.polygon = poly
		body.add_child(col)
		body.add_child(Vision.make_occluder(poly))
		add_child(body)
		var world_poly := PackedVector2Array()
		for v in poly:
			world_poly.append(v + pos)
		_rocks.append({"poly": world_poly, "pos": pos, "radius": radius, "shade": rng.randf_range(0.3, 0.45)})

	for i in DUMMY_METERS.size():
		var dummy := StaticBody2D.new()
		dummy.set_script(_dummy_script)
		dummy.position = Vector2((i % 2 * 2 - 1) * 8.0, -DUMMY_METERS[i] * Firearm.PX_PER_M)
		add_child(dummy)

	for i in ARMORED_CLASSES.size():
		var armored := StaticBody2D.new()
		armored.set_script(_dummy_script)
		armored.set("armor_class", ARMORED_CLASSES[i])
		armored.position = Vector2(300 + i * 80, -8 * Firearm.PX_PER_M)
		add_child(armored)

	for p in CRATES:
		var crate := Destructible.make(Destructible.Kind.CRATE)
		crate.position = p
		add_child(crate)
	var tree_spots: Array = TREES.duplicate()
	while tree_spots.size() < TREES.size() + RANDOM_TREES:
		var p := Vector2(rng.randf_range(-HALF_SIZE + 100, HALF_SIZE - 100), rng.randf_range(-HALF_SIZE + 100, HALF_SIZE - 100))
		if p.length() > 500.0 and absf(p.x) > 250.0:
			tree_spots.append(p)
	for p in tree_spots:
		var tree := Destructible.make(Destructible.Kind.TREE)
		tree.position = p
		add_child(tree)

	var test_wall := RectangleShape2D.new()
	test_wall.size = TEST_WALL.size
	var wall_body := _add_static_body(TEST_WALL.get_center(), test_wall)
	var h := TEST_WALL.size / 2.0
	wall_body.add_child(Vision.make_occluder(PackedVector2Array([
		Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)])))

	var t := 50.0
	var s := HALF_SIZE * 2 + t * 2
	for wall in [
		[Vector2(0, -HALF_SIZE - t / 2), Vector2(s, t)],
		[Vector2(0, HALF_SIZE + t / 2), Vector2(s, t)],
		[Vector2(-HALF_SIZE - t / 2, 0), Vector2(t, s)],
		[Vector2(HALF_SIZE + t / 2, 0), Vector2(t, s)],
	]:
		var rect := RectangleShape2D.new()
		rect.size = wall[1]
		_add_static_body(wall[0], rect)
	queue_redraw()


func _add_static_body(pos: Vector2, shape: Shape2D) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = pos
	var col := CollisionShape2D.new()
	col.shape = shape
	body.add_child(col)
	add_child(body)
	return body


## Lumpy rounded rock outline: random radii smoothed twice so bumps stay blunt.
func _blunt_blob(rng: RandomNumberGenerator, radius: float) -> PackedVector2Array:
	var n := 14
	var radii: Array[float] = []
	for i in n:
		radii.append(radius * rng.randf_range(0.75, 1.0))
	for pass_i in 2:
		var smooth: Array[float] = []
		for i in n:
			smooth.append((radii[i - 1] + radii[i] * 2.0 + radii[(i + 1) % n]) / 4.0)
		radii = smooth
	var start := rng.randf() * TAU
	var pts := PackedVector2Array()
	for i in n:
		var a := start + TAU * i / n
		pts.append(Vector2(cos(a), sin(a)) * radii[i])
	return pts


func _draw() -> void:
	draw_rect(Rect2(-HALF_SIZE, -HALF_SIZE, HALF_SIZE * 2, HALF_SIZE * 2), Color(0.2, 0.26, 0.18))
	var x := -HALF_SIZE
	while x <= HALF_SIZE:
		var c := Color(1, 1, 1, 0.12 if int(x) % 500 == 0 else 0.05)
		draw_line(Vector2(x, -HALF_SIZE), Vector2(x, HALF_SIZE), c, 2.0)
		draw_line(Vector2(-HALF_SIZE, x), Vector2(HALF_SIZE, x), c, 2.0)
		x += GRID
	for r in _rocks:
		var shade: float = r.shade
		var poly: PackedVector2Array = r.poly
		var center: Vector2 = r.pos
		for o in Geometry2D.offset_polygon(poly, 2.0):
			draw_colored_polygon(o, Color(0.08, 0.08, 0.08))
		draw_colored_polygon(poly, Color(shade, shade * 0.95, shade * 0.85))
		var top := PackedVector2Array()
		for v in poly:
			top.append(center + (v - center) * 0.55 + Vector2(-0.18, -0.18) * r.radius)
		draw_colored_polygon(top, Color(shade + 0.08, shade + 0.08, shade + 0.04))
	draw_rect(TEST_WALL.grow(2.0), Color(0.1, 0.1, 0.1))
	draw_rect(TEST_WALL, Color(0.45, 0.42, 0.38))
	draw_rect(Rect2(-HALF_SIZE, -HALF_SIZE, HALF_SIZE * 2, HALF_SIZE * 2), Color(0.6, 0.15, 0.1), false, 12.0)
