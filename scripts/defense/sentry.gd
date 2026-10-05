class_name Sentry
extends StaticBody2D
## A/MG-43 Machine Gun Sentry (stratagem). Turns toward the nearest enemy it can see
## within range and fires full-auto bursts until its ammo runs out, then self-destructs.
## Enemies close by go for it (group "sentries").

const PX := Firearm.PX_PER_M
const RANGE_M := 40.0
const TURN_DEG := 220.0
const AMMO := 300
const RPM := 650.0

var hp := 400.0
var ammo := AMMO
var hit_radius := 18.0
var _stats: FirearmStats
var _aim := 0.0
var _target: Node2D
var _cd := 0.0
var _tick := 0
var _flash := 0.0
var _hurt := 0.0
var _done_t := -1.0


func _ready() -> void:
	add_to_group("sentries")
	collision_layer = 1
	collision_mask = 0
	var col := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = 16.0
	col.shape = c
	add_child(col)
	_stats = FirearmStats.new()
	_stats.display_name = "MG-43 Sentry"
	_stats.damage = 70.0
	_stats.armor_penetration = 3
	_stats.armor_damage = 20.0
	_stats.stagger = 25.0
	_stats.range_min = 30.0
	_stats.range_max = RANGE_M + 10.0
	_stats.muzzle_velocity = 700.0
	_aim = randf() * TAU


func take_damage(amount: float, _from: Vector2, _knock := true) -> void:
	hp -= amount
	_hurt = 0.08
	if hp <= 0.0 and _done_t < 0.0:
		_destroy()


func _destroy() -> void:
	_done_t = 0.0
	remove_from_group("sentries")
	var proj := get_tree().get_first_node_in_group("projectiles")
	if proj:
		proj.add_puff(global_position, 2.0)
	Sfx.play("explosion", global_position)
	queue_free()


func _physics_process(delta: float) -> void:
	_flash = maxf(_flash - delta, 0.0)
	_hurt = maxf(_hurt - delta, 0.0)
	_tick += 1
	if _tick % 6 == 0:
		_target = _find_target()
	_cd -= delta
	if _target and is_instance_valid(_target) and not (_target.has_method("is_dead") and _target.is_dead()):
		var want := (_target.global_position - global_position).angle()
		var step := deg_to_rad(TURN_DEG) * delta
		var diff := wrapf(want - _aim, -PI, PI)
		_aim += clampf(diff, -step, step)
		if absf(diff) < deg_to_rad(4.0) and _cd <= 0.0 and ammo > 0:
			_fire()
	if ammo <= 0:
		_done_t = maxf(_done_t, 0.0) + delta
		if _done_t > 1.5:
			_destroy()
	queue_redraw()


func _fire() -> void:
	_cd = 60.0 / RPM
	ammo -= 1
	var dir := Vector2.from_angle(_aim + deg_to_rad(randf_range(-1.5, 1.5)))
	var muzzle := global_position + Vector2.from_angle(_aim) * 26.0
	var proj := get_tree().get_first_node_in_group("projectiles")
	proj.spawn_bullet(muzzle, dir * _stats.muzzle_velocity * PX, _stats, self)
	Sfx.play("sentry_shot", muzzle, -6.0, 0.05)
	_flash = 0.04
	if ammo % 10 == 0:
		Enemies.broadcast_sound(global_position, 90.0, 10.0)


func _find_target() -> Node2D:
	var space := get_world_2d().direct_space_state
	var best: Node2D = null
	var best_d := RANGE_M * PX
	for n in Enemies.list:
		var d := global_position.distance_to(n.global_position)
		if d >= best_d:
			continue
		var q := PhysicsRayQueryParameters2D.create(global_position, n.global_position, 1)
		q.exclude = [get_rid()]
		if not space.intersect_ray(q).is_empty():
			continue
		best = n
		best_d = d
	return best


func _draw() -> void:
	var outline := Color(0.06, 0.06, 0.06)
	for i in 3:
		var a := TAU * i / 3.0 + PI / 2.0
		draw_line(Vector2.ZERO, Vector2.from_angle(a) * 20.0, outline, 5.0)
		draw_line(Vector2.ZERO, Vector2.from_angle(a) * 19.0, Color(0.3, 0.32, 0.28), 3.0)
	draw_circle(Vector2.ZERO, 11.0, outline)
	draw_circle(Vector2.ZERO, 9.5, Color(0.35, 0.4, 0.32) if _hurt <= 0.0 else Color(0.9, 0.5, 0.4))
	var f := Vector2.from_angle(_aim)
	draw_line(Vector2.ZERO, f * 28.0, outline, 6.0)
	draw_line(Vector2.ZERO, f * 27.0, Color(0.18, 0.18, 0.18), 3.5)
	draw_rect(Rect2(-5, -5, 10, 10), UiStyle.YELLOW.darkened(0.2))
	if _flash > 0.0:
		draw_circle(f * 30.0, 6.0, Color(1, 0.85, 0.4, 0.9))
	# Ammo bar
	draw_rect(Rect2(-16, 22, 32, 4), outline)
	draw_rect(Rect2(-15, 23, 30.0 * ammo / AMMO, 2), UiStyle.YELLOW)
