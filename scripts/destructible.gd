class_name Destructible
extends StaticBody2D
## Destructible prop. Takes damage only from weapons whose destruction_level is at or
## above this prop's level, and then always the weapon's flat base damage.
## Destroyed props lose collision and leave debris.

enum Kind { CRATE, TREE }

@export var kind := Kind.CRATE
@export_range(0, 100) var destruction_level := 3
@export var max_hp := 150.0

var hp := 150.0
var _flash := 0.0
var _debris: Array[Dictionary] = []
var _col: CollisionShape2D


static func make(k: Kind) -> StaticBody2D:
	# Untyped so script properties can be set before _ready.
	var d = StaticBody2D.new()
	d.set_script(load("res://scripts/destructible.gd"))
	d.kind = k
	match k:
		Kind.CRATE:
			d.destruction_level = 3
			d.max_hp = 150.0
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
		Kind.TREE:
			var c := CircleShape2D.new()
			c.radius = 12.0 # trunk; bullets fly under the canopy
			_col.shape = c
			z_index = 2 # canopy over player
	add_child(_col)


func take_hit(hit: Dictionary) -> void:
	if hp <= 0.0:
		return
	if hit.destruction_level < destruction_level:
		return
	hp -= hit.base_damage
	_flash = 0.08
	if hp <= 0.0:
		_destroy(hit.dir)


func _destroy(dir: Vector2) -> void:
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
		Kind.TREE:
			draw_circle(Vector2.ZERO, 13.5, outline)
			draw_circle(Vector2.ZERO, 12.0, Color(0.4, 0.28, 0.15))
			draw_circle(Vector2.ZERO, 56.0, Color(0.1, 0.25, 0.1, 0.75))
			draw_circle(Vector2(-12, -12), 34.0, Color(0.16, 0.36, 0.14, 0.7))
			draw_circle(Vector2.ZERO, 12.0, hit_tint)
