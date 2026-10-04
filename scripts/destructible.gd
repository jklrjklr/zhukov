class_name Destructible
extends StaticBody2D
## Destructible prop. Takes damage only from weapons whose destruction_level is at or
## above this prop's level, and then always the weapon's flat base damage.
## Destroyed props lose collision and leave debris.
## NEST: enemy burrow; FABRICATOR: Automaton factory. Mission objectives; both need
## explosives (level 20).

signal destroyed(d: Destructible)

enum Kind { CRATE, TREE, NEST, FABRICATOR }

@export var kind := Kind.CRATE
@export_range(0, 100) var destruction_level := 3
@export var max_hp := 150.0

var hp := 150.0
var _flash := 0.0
var _debris: Array[Dictionary] = []
var _col: CollisionShape2D
var _occluder: LightOccluder2D
## Spiky canopy outline (trees), built once.
var _canopy := PackedVector2Array()
var _canopy_inner := PackedVector2Array()


static func make(k: Kind) -> StaticBody2D:
	# Untyped so script properties can be set before _ready.
	var d = StaticBody2D.new()
	d.set_script(load("res://scripts/destructible.gd"))
	d.kind = k
	match k:
		Kind.CRATE:
			d.destruction_level = 3
			d.max_hp = 150.0
		Kind.NEST:
			d.destruction_level = 20
			d.max_hp = 250.0
		Kind.FABRICATOR:
			d.destruction_level = 20
			d.max_hp = 400.0
		Kind.TREE:
			d.destruction_level = 30
			d.max_hp = 400.0
	return d


func _ready() -> void:
	hp = max_hp
	_col = CollisionShape2D.new()
	match kind:
		Kind.CRATE:
			var r := RectangleShape2D.new()
			r.size = Vector2(40, 40)
			_col.shape = r
			_occluder = Vision.add_occluder(self, Vision.rect_points(r.size))
		Kind.FABRICATOR:
			var fr := RectangleShape2D.new()
			fr.size = Vector2(80, 56)
			_col.shape = fr
			_occluder = Vision.add_occluder(self, Vision.rect_points(fr.size))
			add_to_group("fabricators")
		Kind.NEST:
			var nc := CircleShape2D.new()
			nc.radius = 30.0
			_col.shape = nc
			add_to_group("nests")
		Kind.TREE:
			var c := CircleShape2D.new()
			c.radius = 12.0 # trunk; bullets fly under the canopy
			_col.shape = c
			_occluder = Vision.add_occluder(self, Vision.circle_points(12.0))
			z_index = 2 # canopy over player
			var spin := fmod(position.x * 0.013 + position.y * 0.007, TAU)
			_canopy = _star(18, 60.0, 40.0, spin)
			_canopy_inner = _star(12, 38.0, 24.0, spin + 0.2)
	add_child(_col)


func _star(spikes: int, outer: float, inner: float, spin: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in spikes * 2:
		var r := outer if i % 2 == 0 else inner
		pts.append(Vector2.from_angle(spin + PI * i / spikes) * r)
	return pts


func take_hit(hit: Dictionary) -> void:
	if hp <= 0.0:
		return
	if hit.destruction_level < destruction_level:
		return
	hp -= hit.base_damage
	_flash = 0.08
	if hp <= 0.0:
		_destroy(hit.dir)


func is_destroyed() -> bool:
	return hp <= 0.0


func _destroy(dir: Vector2) -> void:
	destroyed.emit(self)
	if _occluder:
		_occluder.queue_free()
	remove_from_group("nests")
	remove_from_group("fabricators")
	_col.set_deferred("disabled", true)
	z_index = 0
	for i in 10:
		_debris.append({
			"pos": Vector2(randf_range(-12, 12), randf_range(-12, 12)),
			"vel": (dir * randf_range(40, 140)).rotated(randf_range(-0.8, 0.8)),
			"rot": randf() * TAU, "size": Vector2(randf_range(6, 16), randf_range(3, 6)),
		})


func _process(delta: float) -> void:
	_flash = maxf(_flash - delta, 0.0)
	for d in _debris:
		var damp := exp(-6.0 * delta)
		d.vel *= damp
		d.pos += d.vel * delta
	if _flash > 0.0 or not _debris.is_empty():
		queue_redraw()


func _draw() -> void:
	var outline := Color(0.08, 0.08, 0.08)
	if hp <= 0.0:
		var wood := Color(0.45, 0.3, 0.15) if kind == Kind.CRATE else Color(0.35, 0.25, 0.15)
		if kind == Kind.TREE:
			draw_circle(Vector2.ZERO, 12.0, Color(0.3, 0.22, 0.12)) # stump
		for d in _debris:
			draw_set_transform(d.pos, d.rot)
			draw_rect(Rect2(-d.size / 2, d.size), wood)
		draw_set_transform(Vector2.ZERO)
		return
	var dmg := 1.0 - hp / max_hp
	var hit_tint := Color(1, 1, 1, 0.5) if _flash > 0.0 else Color(0, 0, 0, 0)
	match kind:
		Kind.CRATE:
			draw_rect(Rect2(-21.5, -21.5, 43, 43), outline)
			draw_rect(Rect2(-20, -20, 40, 40), Color(0.62, 0.45, 0.25))
			draw_rect(Rect2(-20, -20, 40, 40), Color(0.4, 0.27, 0.12), false, 3.0)
			draw_line(Vector2(-18, -18), Vector2(18, 18), Color(0.4, 0.27, 0.12), 3.0)
			if dmg > 0.3:
				draw_line(Vector2(-14, 6), Vector2(2, -3), outline, 1.5)
			if dmg > 0.6:
				draw_line(Vector2(4, 14), Vector2(12, -8), outline, 1.5)
			draw_rect(Rect2(-20, -20, 40, 40), hit_tint)
		Kind.FABRICATOR:
			# Dark bot factory: armored block, glowing vent, smokestacks.
			var glow := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.004)
			draw_rect(Rect2(-41.5, -29.5, 83, 59), outline)
			draw_rect(Rect2(-40, -28, 80, 56), Color(0.2, 0.2, 0.22))
			draw_rect(Rect2(-34, -22, 68, 44), Color(0.14, 0.14, 0.16))
			draw_rect(Rect2(-14, 18, 28, 10), Color(1.0, 0.25, 0.1, glow)) # vent/door (weak spot)
			for x in [-24.0, 24.0]:
				draw_circle(Vector2(x, -8), 9.0, outline)
				draw_circle(Vector2(x, -8), 7.5, Color(0.25, 0.25, 0.27))
				draw_circle(Vector2(x, -8), 3.5, Color(0.08, 0.08, 0.08))
			draw_rect(Rect2(-40, -28, 80, 56), hit_tint)
		Kind.NEST:
			# Fleshy mound with a dark burrow mouth.
			draw_circle(Vector2.ZERO, 34.0, outline)
			draw_circle(Vector2.ZERO, 32.0, Color(0.42, 0.3, 0.32))
			draw_circle(Vector2(-6, -4), 22.0, Color(0.5, 0.36, 0.38))
			draw_circle(Vector2(3, 2), 13.0, Color(0.12, 0.05, 0.06))
			draw_circle(Vector2(3, 2), 7.0, Color(0.05, 0.02, 0.02))
			for i in 6:
				var a := TAU * i / 6.0 + 0.3
				draw_circle(Vector2.from_angle(a) * 27.0, 4.0, Color(0.6, 0.45, 0.4))
			draw_circle(Vector2.ZERO, 32.0, hit_tint)
		Kind.TREE:
			draw_circle(Vector2.ZERO, 13.5, outline)
			draw_circle(Vector2.ZERO, 12.0, Color(0.4, 0.28, 0.15))
			draw_colored_polygon(_canopy, Color(0.1, 0.25, 0.1, 0.8))
			draw_set_transform(Vector2(-8, -8))
			draw_colored_polygon(_canopy_inner, Color(0.17, 0.38, 0.15, 0.75))
			draw_set_transform(Vector2.ZERO)
			draw_circle(Vector2.ZERO, 12.0, hit_tint)
