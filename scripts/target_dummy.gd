extends StaticBody2D
## Practice target: floating damage numbers, distance label, optional armor, heals after a pause.
## Armor: hit factor = FirearmStats.armor_factor(ap, armor_class) scales both HP damage and
## armor damage. Armor at 0 durability is broken (class 0).

@export var max_hp := 100.0
@export_range(0, 10) var armor_class := 0
@export var max_armor := 80.0

var hp := 100.0
var armor := 0.0
var _numbers: Array[Dictionary] = []
var _since_hit := 99.0


func _ready() -> void:
	hp = max_hp
	armor = max_armor if armor_class > 0 else 0.0
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 16.0
	col.shape = shape
	add_child(col)


func current_armor_class() -> int:
	return armor_class if armor > 0.0 else 0


func take_hit(hit: Dictionary) -> void:
	if hp <= 0.0:
		return
	var ac := current_armor_class()
	var f := FirearmStats.armor_factor(hit.armor_penetration, ac)
	if ac > 0:
		armor = maxf(armor - hit.armor_damage * f, 0.0)
	var dmg: float = hit.damage * f
	hp = maxf(hp - dmg, 0.0)
	_since_hit = 0.0
	var text := "BLOCK" if f <= 0.0 else "%d" % roundi(dmg)
	_numbers.append({"text": text, "t": 0.0, "x": randf_range(-10, 10)})


func _process(delta: float) -> void:
	_since_hit += delta
	if _since_hit > 2.5:
		hp = max_hp
		armor = max_armor if armor_class > 0 else 0.0
	for n in _numbers:
		n.t += delta
	_numbers = _numbers.filter(func(n): return n.t < 0.9)
	queue_redraw()


func _draw() -> void:
	var down := hp <= 0.0
	if armor_class > 0:
		var ring := Color(0.35, 0.6, 0.95) if armor > 0.0 else Color(0.3, 0.3, 0.3)
		draw_circle(Vector2.ZERO, 21.0, Color(0.08, 0.08, 0.08))
		draw_circle(Vector2.ZERO, 19.5, ring)
	draw_circle(Vector2.ZERO, 17.5, Color(0.08, 0.08, 0.08))
	draw_circle(Vector2.ZERO, 16.0, Color(0.5, 0.5, 0.5) if down else Color(0.85, 0.2, 0.15))
	draw_circle(Vector2.ZERO, 10.0, Color(0.95, 0.92, 0.85))
	draw_circle(Vector2.ZERO, 4.5, Color(0.85, 0.2, 0.15))

	# Text stays upright on screen while the camera rotates.
	var font := ThemeDB.fallback_font
	var up := -get_viewport().get_canvas_transform().get_rotation()
	draw_set_transform(Vector2.ZERO, up)
	var label := "DOWN" if down else "%d m" % roundi(global_position.length() / Firearm.PX_PER_M)
	if armor_class > 0:
		label += "  AC%d" % armor_class
	draw_string(font, Vector2(-50, 40), label, HORIZONTAL_ALIGNMENT_CENTER, 100, 16, Color(1, 1, 1, 0.7))
	draw_rect(Rect2(-20, 46, 40, 4), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(-20, 46, 40 * hp / max_hp, 4), Color(0.4, 0.9, 0.4))
	if armor_class > 0:
		draw_rect(Rect2(-20, 52, 40, 4), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(-20, 52, 40 * armor / max_armor, 4), Color(0.35, 0.6, 0.95))
	for n in _numbers:
		var a: float = 1.0 - n.t / 0.9
		var p := Vector2(n.x - 30, -26 - n.t * 40.0)
		draw_string(font, p, n.text, HORIZONTAL_ALIGNMENT_CENTER, 60, 20, Color(1, 0.95, 0.5, a))
	draw_set_transform(Vector2.ZERO)
