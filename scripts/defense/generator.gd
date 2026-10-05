class_name Generator
extends StaticBody2D
## Power generator of the evacuation site. Illuminate attack it; when every generator is
## down the site is lost. Takes damage from enemies (take_damage) and from explosions
## (friendly fire), not from bullets.

signal destroyed(g: Generator)

@export var max_hp := 2500.0
@export var label := "A"

var hp := 2500.0
## px: how far from the centre attackers can reach it.
var hit_radius := 38.0
var _flash := 0.0
var _t := 0.0
var _dead := false


func _ready() -> void:
	hp = max_hp
	add_to_group("generators")
	collision_layer = 1
	collision_mask = 0
	var col := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(70, 56)
	col.shape = r
	add_child(col)
	Vision.add_occluder(self, Vision.rect_points(r.size))
	_t = randf() * TAU


func is_destroyed() -> bool:
	return _dead


func take_damage(amount: float, _from: Vector2, _knock := true) -> void:
	if _dead:
		return
	hp = maxf(hp - amount, 0.0)
	_flash = 0.08
	if hp <= 0.0:
		_dead = true
		Sfx.play("explosion_big", global_position, 4.0)
		var proj := get_tree().get_first_node_in_group("projectiles")
		if proj:
			proj.add_puff(global_position, 4.0)
		destroyed.emit(self)
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	_flash = maxf(_flash - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	var outline := Color(0.06, 0.06, 0.06)
	draw_rect(Rect2(-37, -30, 74, 60), outline)
	var body := Color(0.3, 0.32, 0.3) if not _dead else Color(0.14, 0.13, 0.12)
	if _flash > 0.0:
		body = body.lightened(0.4)
	draw_rect(Rect2(-35, -28, 70, 56), body)
	# Hazard stripes along the base
	for i in 7:
		var x := -35.0 + i * 10.0
		draw_line(Vector2(x, 28), Vector2(x + 6, 22), UiStyle.YELLOW.darkened(0.3 if not _dead else 0.8), 3.0)
	# Coils
	for x in [-18.0, 0.0, 18.0]:
		draw_circle(Vector2(x, -6), 9.0, outline)
		var glow := Color(0.35, 0.8, 1.0) if not _dead else Color(0.1, 0.1, 0.1)
		var pulse := 0.6 + 0.4 * sin(_t * 4.0 + x)
		draw_circle(Vector2(x, -6), 7.0, glow.darkened(0.5 - 0.5 * pulse) if not _dead else glow)
	if _dead:
		for i in 3:
			var k := fmod(_t * 0.5 + i / 3.0, 1.0)
			draw_circle(Vector2(-10 + i * 10, -10 - k * 50.0), 8.0 + k * 10.0, Color(0.1, 0.1, 0.1, 0.5 * (1.0 - k)))
	# Label and health bar (upright regardless of camera rotation).
	draw_set_transform(Vector2.ZERO, -get_viewport().get_canvas_transform().get_rotation() - global_rotation)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-40, 18), label, HORIZONTAL_ALIGNMENT_CENTER, 80, 22, Color(1, 1, 1, 0.8))
	if not _dead:
		var k := hp / max_hp
		draw_rect(Rect2(-36, -46, 72, 8), outline)
		draw_rect(Rect2(-35, -45, 70 * k, 6), Color(0.35, 0.85, 1.0) if k > 0.35 else UiStyle.RED)
	draw_set_transform(Vector2.ZERO)
