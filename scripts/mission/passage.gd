class_name Passage
extends Node2D
## 20 m roofed corridor between two zones (north-bound). No spawns, no sky: Eagle and
## orbital beacons inside are refused (see Stratagems). Crossing the midline seals it
## behind the player (rockslide + collision wall); Mission fails the zone's uncleared
## objectives and the next zone begins. Node origin = passage centre (= midline).

signal sealed(p: Passage)

const PX := Firearm.PX_PER_M
const LEN_M := 20.0
const HALF_W_M := 4.0
const SEAL_BEHIND_M := 3.0
## Corridor wall thickness (px): drawn VISUAL_SCALE bigger, growing outward (the opening stays 8 m).
const WT := 2.0 * Vis.VISUAL_SCALE * PX
const K := Vis.VISUAL_SCALE

var index := 0
var is_sealed := false
## World rectangles.
var roof_rect := Rect2()
var seal_rect := Rect2()
var _seal_t := -1.0
var _dust: Array[Dictionary] = []
var _rocks: Array[Dictionary] = []
var _roof: Node2D


func build(world_center: Vector2) -> void:
	position = world_center
	z_index = -9
	var half_len := LEN_M * 0.5 * PX
	var hw := HALF_W_M * PX
	roof_rect = Rect2(world_center - Vector2(hw + WT, half_len), Vector2(hw + WT, half_len) * 2.0)
	roof_rect.size.x = (hw + WT) * 2.0
	seal_rect = Rect2(world_center + Vector2(-hw, SEAL_BEHIND_M * PX - 0.5 * PX), Vector2(hw * 2.0, 1.0 * PX))
	for side in [-1.0, 1.0]:
		var r := Rect2(Vector2((hw if side > 0.0 else -hw - WT), -half_len), Vector2(WT, half_len * 2.0))
		var body := StaticBody2D.new()
		body.position = r.get_center()
		var col := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = r.size
		col.shape = shape
		body.add_child(col)
		add_child(body)
		Vision.add_occluder(body, Vision.rect_points(r.size))
	_roof = Node2D.new()
	_roof.z_index = 14
	_roof.z_as_relative = false
	_roof.draw.connect(_draw_roof)
	add_child(_roof)
	queue_redraw()


## Past the midline going north (and still inside the corridor).
func crossed(p: Vector2) -> bool:
	return not is_sealed and absf(p.x - position.x) < HALF_W_M * PX and p.y < position.y and p.y > position.y - LEN_M * 0.5 * PX


func inside(p: Vector2) -> bool:
	return absf(p.x - position.x) < HALF_W_M * PX and absf(p.y - position.y) < LEN_M * 0.5 * PX


## In the corridor, before the midline (HUD warns about leaving the zone).
func approaching(p: Vector2) -> bool:
	return not is_sealed and inside(p) and p.y > position.y


func is_roofed(p: Vector2) -> bool:
	return roof_rect.has_point(p)


func seal() -> void:
	if is_sealed:
		return
	is_sealed = true
	_seal_t = 0.0
	var body := StaticBody2D.new()
	body.name = "Seal"
	body.position = seal_rect.get_center() - position
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = seal_rect.size
	col.shape = shape
	body.add_child(col)
	add_child(body)
	Vision.add_occluder(body, Vision.rect_points(seal_rect.size))
	for i in 14:
		_rocks.append({"pos": Vector2(randf_range(-4.0, 4.0) * PX, seal_rect.get_center().y - position.y + randf_range(-0.4, 0.4) * PX),
			"r": randf_range(0.6, 1.3) * PX * K, "delay": randf() * 0.5, "shade": randf_range(0.3, 0.45)})
	Sfx.play("passage_seal", seal_rect.get_center(), 4.0, 0.03)
	Fx.shake(self, 8.0)
	Fx.dust_puff(self, seal_rect.get_center(), 3.0)
	sealed.emit(self)


func _process(delta: float) -> void:
	if _seal_t >= 0.0:
		_seal_t += delta
		if _seal_t < 1.2 and randf() < 0.5:
			_dust.append({"pos": Vector2(randf_range(-4.0, 4.0) * PX, seal_rect.get_center().y - position.y), "t": 0.0})
		for d in _dust:
			d.t += delta
		_dust = _dust.filter(func(d): return d.t < 1.0)
		queue_redraw()
		_roof.queue_redraw()


func _draw() -> void:
	var half_len := LEN_M * 0.5 * PX
	var hw := HALF_W_M * PX
	var wall_col := Zone.WALL
	draw_rect(Rect2(-hw - WT, -half_len, (hw + WT) * 2.0, half_len * 2.0), Color(0.3, 0.29, 0.27))
	draw_rect(Rect2(-hw, -half_len, hw * 2.0, half_len * 2.0), Color(0.36, 0.34, 0.31))
	# Floor: plate seams, scuffs, guiding chevrons toward the next zone, cable runs.
	var y := -half_len
	while y < half_len:
		draw_line(Vector2(-hw, y), Vector2(hw, y), Color(0, 0, 0, 0.18), 2.0)
		y += 1.5 * PX
	for x in [-hw * 0.5, hw * 0.5]:
		draw_line(Vector2(x, -half_len), Vector2(x, half_len), Color(0.1, 0.1, 0.1, 0.35), 3.0)
	var prng := RandomNumberGenerator.new()
	prng.seed = 1000 + index
	for i in 22:
		draw_circle(Vector2(prng.randf_range(-hw, hw), prng.randf_range(-half_len, half_len)), prng.randf_range(8, 24), Color(0.05, 0.05, 0.04, 0.12))
	for i in 5:
		var cy := -half_len + (i + 0.5) * half_len * 2.0 / 5.0
		draw_polyline(PackedVector2Array([Vector2(-26, cy + 16) * K, Vector2(0, cy - 8) * K, Vector2(26, cy + 16) * K]), Color(UiStyle.YELLOW, 0.4), 6.0 * K)
	for side in [-1.0, 1.0]:
		var r := Rect2(Vector2((hw if side > 0.0 else -hw - WT), -half_len), Vector2(WT, half_len * 2.0))
		if Game.shadows_enabled: draw_rect(Rect2(r.position + Vector2(7, 9), r.size), Color(0, 0, 0, 0.3))
		draw_rect(r.grow(2.0 * K), Color(0.08, 0.08, 0.08))
		draw_rect(r, wall_col.darkened(0.3))
		var top := Rect2(r.position, r.size - Vector2(6, 0) * K)
		draw_rect(top, wall_col)
		draw_rect(Rect2(top.position, Vector2(3, top.size.y)), wall_col.lightened(0.2))
		var t := 2.0 * PX
		while t < r.size.y:
			draw_line(Vector2(top.position.x + 3, r.position.y + t), Vector2(top.end.x, r.position.y + t), wall_col.darkened(0.3), 1.5)
			t += 2.0 * PX
		# Warning lamps along the inner edge.
		var lx := (hw - 5.0 * K) if side > 0.0 else (-hw + 5.0 * K)
		var ly := -half_len + 40.0
		while ly < half_len:
			draw_circle(Vector2(lx, ly), 5.0 * K, Color(0.1, 0.1, 0.1))
			draw_circle(Vector2(lx, ly), 3.4 * K, Color(1.0, 0.65, 0.15) if not is_sealed else Color(0.4, 0.15, 0.1))
			ly += 4.0 * PX
	# Hazard line at the midline.
	for i in 8:
		draw_rect(Rect2(-hw + i * hw * 0.25, -3 * K, hw * 0.125, 6 * K), UiStyle.YELLOW.darkened(0.4))
	draw_rect(Rect2(-hw, -6 * K, hw * 2.0, 12 * K), Color(0, 0, 0, 0.15))
	for r in _rocks:
		var k := clampf((_seal_t - r.delay) / 0.4, 0.0, 1.0)
		if k <= 0.0:
			continue
		var p: Vector2 = r.pos + Vector2(0, -(1.0 - k) * 240.0)
		var shade: float = r.shade
		draw_circle(p, r.r + 2.0, Color(0.08, 0.08, 0.08))
		draw_circle(p, r.r, Color(shade, shade * 0.95, shade * 0.85))
		draw_circle(p + Vector2(-0.2, -0.2) * r.r, r.r * 0.55, Color(shade + 0.08, shade + 0.08, shade + 0.04))
	for d in _dust:
		var k: float = d.t
		draw_circle(d.pos, (16.0 + k * 40.0) * K, Color(0.6, 0.55, 0.45, 0.3 * (1.0 - k)))


func _draw_roof() -> void:
	var half_len := LEN_M * 0.5 * PX
	var hw := HALF_W_M * PX + WT
	# Slatted roof: you can still see the floor through it.
	var n := 10
	for i in n:
		var y := -half_len + (i + 0.5) * half_len * 2.0 / n
		_roof.draw_rect(Rect2(-hw, y - 10.0 * K, hw * 2.0, 20.0 * K), Color(0.12, 0.12, 0.13, 0.55))
		_roof.draw_rect(Rect2(-hw, y - 10.0 * K, hw * 2.0, 3.0 * K), Color(0.3, 0.3, 0.32, 0.6))
	_roof.draw_rect(Rect2(-hw, -half_len, hw * 2.0, half_len * 2.0), Color(0, 0, 0, 0.12))
