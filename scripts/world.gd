extends Node2D
## Placeholder test ground: grid (1 cell = 100 px), a few rocks and border walls,
## so movement and camera turning can be judged. Replace with the new game's world.

const HALF_SIZE := 3000.0
const GRID := 100.0
const ROCK_COUNT := 60

var _rocks: Array[PackedVector2Array] = []


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	while _rocks.size() < ROCK_COUNT:
		var pos := Vector2(
			rng.randf_range(-HALF_SIZE + 100, HALF_SIZE - 100),
			rng.randf_range(-HALF_SIZE + 100, HALF_SIZE - 100))
		if pos.length() < 300.0:
			continue # keep spawn clear
		var poly := _blob(rng, rng.randf_range(25.0, 80.0))
		_add_wall(pos, poly)
		var world_poly := PackedVector2Array()
		for v in poly:
			world_poly.append(v + pos)
		_rocks.append(world_poly)
	var h := HALF_SIZE
	for r in [Rect2(-h, -h - 50, 2 * h, 50), Rect2(-h, h, 2 * h, 50), Rect2(-h - 50, -h, 50, 2 * h), Rect2(h, -h, 50, 2 * h)]:
		_add_wall(Vector2.ZERO, PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]))


func _add_wall(pos: Vector2, poly: PackedVector2Array) -> void:
	var body := StaticBody2D.new()
	body.position = pos
	var col := CollisionPolygon2D.new()
	col.polygon = poly
	body.add_child(col)
	add_child(body)


func _blob(rng: RandomNumberGenerator, radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 9
	for i in n:
		var a := TAU * i / n + rng.randf_range(-0.2, 0.2)
		pts.append(Vector2.from_angle(a) * radius * rng.randf_range(0.75, 1.1))
	return pts


func _draw() -> void:
	var h := HALF_SIZE
	draw_rect(Rect2(-h, -h, 2 * h, 2 * h), Color(0.2, 0.24, 0.18))
	var line := Color(1, 1, 1, 0.06)
	var x := -h
	while x <= h:
		draw_line(Vector2(x, -h), Vector2(x, h), line, 2.0)
		draw_line(Vector2(-h, x), Vector2(h, x), line, 2.0)
		x += GRID
	draw_circle(Vector2.ZERO, 12.0, Color(1, 1, 1, 0.2))
	for poly in _rocks:
		draw_colored_polygon(poly, Color(0.38, 0.37, 0.34))
		var outline := poly.duplicate()
		outline.append(poly[0])
		draw_polyline(outline, Color(0.1, 0.1, 0.1), 3.0)
