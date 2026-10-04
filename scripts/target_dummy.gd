extends StaticBody2D
## Practice target: floating damage numbers, distance label, heals after a pause.

@export var max_hp := 100.0

var hp := 100.0
var _numbers: Array[Dictionary] = []
var _since_hit := 99.0


func _ready() -> void:
	hp = max_hp
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 16.0
	col.shape = shape
	add_child(col)


func take_hit(damage: float, _dir: Vector2, meters: float) -> void:
	if hp <= 0.0:
		return
	hp = maxf(hp - damage, 0.0)
	_since_hit = 0.0
	_numbers.append({"text": "%d" % roundi(damage), "t": 0.0, "x": randf_range(-10, 10), "m": meters})


func _process(delta: float) -> void:
	_since_hit += delta
	if _since_hit > 2.5:
		hp = max_hp
	for n in _numbers:
		n.t += delta
	_numbers = _numbers.filter(func(n): return n.t < 0.9)
	queue_redraw()


func _draw() -> void:
	var down := hp <= 0.0
	draw_circle(Vector2.ZERO, 17.5, Color(0.08, 0.08, 0.08))
	draw_circle(Vector2.ZERO, 16.0, Color(0.5, 0.5, 0.5) if down else Color(0.85, 0.2, 0.15))
	draw_circle(Vector2.ZERO, 10.0, Color(0.95, 0.92, 0.85))
	draw_circle(Vector2.ZERO, 4.5, Color(0.85, 0.2, 0.15))

	# Text stays upright on screen while the camera rotates.
	var font := ThemeDB.fallback_font
	var up := -get_viewport().get_canvas_transform().get_rotation()
	draw_set_transform(Vector2.ZERO, up)
	var label := "DOWN" if down else "%d m" % roundi(global_position.length() / Firearm.PX_PER_M)
	draw_string(font, Vector2(-40, 38), label, HORIZONTAL_ALIGNMENT_CENTER, 80, 16, Color(1, 1, 1, 0.7))
	draw_rect(Rect2(-20, 44, 40, 4), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(-20, 44, 40 * hp / max_hp, 4), Color(0.4, 0.9, 0.4))
	for n in _numbers:
		var a: float = 1.0 - n.t / 0.9
		var p := Vector2(n.x - 30, -26 - n.t * 40.0)
		draw_string(font, p, n.text, HORIZONTAL_ALIGNMENT_CENTER, 60, 20, Color(1, 0.95, 0.5, a))
	draw_set_transform(Vector2.ZERO)
