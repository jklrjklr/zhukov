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
var _barrel: Node2D
var _hurt_n: Node2D
var _flash_n: Node2D
var _bar: Node2D
var _bar_w := -1
var _shots := 0
var _done_t := -1.0


func _ready() -> void:
	scale = Vector2.ONE * Vis.VISUAL_SCALE # drawn (and colliding) bigger
	z_index = 2 # above the shared enemy rig layers (z 1): bugs swarm around it, not over it
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
	_build_art()


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
	_barrel.rotation = _aim
	_flash_n.visible = _flash > 0.0
	if _flash_n.visible:
		_flash_n.rotation = _aim
	_hurt_n.visible = _hurt > 0.0
	var bw := int(30.0 * ammo / AMMO)
	if bw != _bar_w:
		_bar_w = bw
		_bar.queue_redraw()


func _fire() -> void:
	_cd = 60.0 / RPM
	ammo -= 1
	var dir := Vector2.from_angle(_aim + deg_to_rad(randf_range(-1.5, 1.5)))
	var muzzle := global_position + Vector2.from_angle(_aim) * 26.0 * Vis.VISUAL_SCALE
	var proj := get_tree().get_first_node_in_group("projectiles")
	proj.spawn_bullet(muzzle, dir * _stats.muzzle_velocity * PX, _stats, self)
	# Every other round gets its report (starting a voice is the expensive part of a shot).
	_shots += 1
	if _shots % 2 == 1:
		Sfx.play("sentry_shot", muzzle, -3.0, 0.05)
	_flash = 0.04
	if ammo % 10 == 0:
		Enemies.broadcast_sound(global_position, 90.0, 10.0)


## Nearest visible enemy within range. The registry (Enemies.list) is the only source (no group
## scans); squared distances reject most candidates, and a ray is only cast for a candidate that
## would beat the best so far. Called every 6th tick, not every tick.
func _find_target() -> Node2D:
	var best: Node2D = null
	var best_d2 := RANGE_M * PX * RANGE_M * PX
	var me := global_position
	var space := get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(me, me, 1)
	q.exclude = [get_rid()]
	for n in Enemies.list:
		var d2 := me.distance_squared_to(n.global_position)
		if d2 >= best_d2:
			continue
		q.to = n.global_position
		if not space.intersect_ray(q).is_empty():
			continue
		best = n
		best_d2 = d2
	return best


## Static art on child nodes: nothing is re-recorded per tick, the barrel only rotates (a transform),
## the muzzle flash toggles, the ammo bar redraws when its width changes (every ~10 rounds).
func _build_art() -> void:
	var outline := Color(0.06, 0.06, 0.06)
	_art(func(n: Node2D) -> void:
		for i in 3:
			var a := TAU * i / 3.0 + PI / 2.0
			n.draw_line(Vector2.ZERO, Vector2.from_angle(a) * 20.0, outline, 5.0)
			n.draw_line(Vector2.ZERO, Vector2.from_angle(a) * 19.0, Color(0.3, 0.32, 0.28), 3.0)
		n.draw_circle(Vector2.ZERO, 11.0, outline)
		n.draw_circle(Vector2.ZERO, 9.5, Color(0.35, 0.4, 0.32)))
	_hurt_n = _art(func(n: Node2D) -> void: n.draw_circle(Vector2.ZERO, 9.5, Color(0.9, 0.5, 0.4)))
	_hurt_n.visible = false
	_barrel = _art(func(n: Node2D) -> void:
		n.draw_line(Vector2.ZERO, Vector2(28.0, 0), outline, 6.0)
		n.draw_line(Vector2.ZERO, Vector2(27.0, 0), Color(0.18, 0.18, 0.18), 3.5))
	_art(func(n: Node2D) -> void: n.draw_rect(Rect2(-5, -5, 10, 10), UiStyle.YELLOW.darkened(0.2)))
	_flash_n = _art(func(n: Node2D) -> void: n.draw_circle(Vector2(30.0, 0), 6.0, Color(1, 0.85, 0.4, 0.9)))
	_flash_n.visible = false
	_bar = _art(func(n: Node2D) -> void:
		n.draw_rect(Rect2(-16, 22, 32, 4), outline)
		n.draw_rect(Rect2(-15, 23, 30.0 * ammo / AMMO, 2), UiStyle.YELLOW))
	_bar.rotation = 0.0


func _art(fn: Callable) -> Node2D:
	var n := Node2D.new()
	n.draw.connect(fn.bind(n))
	add_child(n)
	return n
