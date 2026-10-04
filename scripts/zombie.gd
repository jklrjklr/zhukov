class_name Zombie
extends CharacterBody2D
## Basic enemy.
## - Wanders slowly. Sees the player inside a 70 deg / 20 m cone with line of sight.
## - Runs at the player when seen; goes to the last known spot when sight is lost.
## - Hearing: a sound is heard when its loudness at this distance is at least
##   (100 - hearing). Sounds louder than DEAFEN_LEVEL here knock hearing down
##   (ringing ears); it recovers over time.
## - Steers around anything in the way (rocks, props, other zombies) with context
##   steering: rays in RAYS directions score "towards goal" minus "blocked". When the
##   direct way is blocked it commits to one side for a while, so it walks around
##   walls instead of dithering in front of them.
## - In reach: winds up and swings an arm; damage lands if the player is still there.

enum State { WANDER, CHASE, SEARCH, ATTACK, DEAD }

const PX := Firearm.PX_PER_M
const RADIUS := 15.0
const HEAD_RADIUS := 7.0
const CRIT_DEPTH := 30.0
const CRIT_MULT := 2.0
const RAYS := 16
## px of look-ahead for steering rays (beyond the body).
const FEELER := 60.0
const SKIN := Color(0.5, 0.62, 0.4)
const CLOTH := Color(0.36, 0.31, 0.4)
const OUTLINE := Color(0.08, 0.08, 0.08)

@export var max_hp := 120.0
## m/s
@export var wander_speed := 0.7
@export var run_speed := 3.3
@export var fov_deg := 70.0
@export var sight_m := 20.0
## m from body edge to body edge.
@export var reach_m := 0.7
@export var attack_damage := 18.0
## s from starting the swing to the hit.
@export var windup := 0.45
@export var attack_cooldown := 0.9
@export var turn_speed_deg := 240.0
## 0..100 hearing sensitivity: hears sounds of at least (100 - hearing) loudness.
@export var hearing := 90.0
## Hearing points regained per second after being deafened.
@export var hearing_recovery := 4.0

## Loudness (at the ear) above which hearing gets damaged.
const DEAFEN_LEVEL := 80.0
## Hearing lost per loudness point above DEAFEN_LEVEL.
const DEAFEN_RATE := 0.5
const MIN_HEARING := 10.0

var hp := 120.0
var state := State.WANDER
## Current hearing (drops when deafened, recovers to `hearing`).
var hearing_now := 90.0

var _goal := Vector2.ZERO
var _wander_time := 0.0
var _attack_t := 0.0
var _struck := false
var _cooldown := 0.0
var _stagger := 0.0
var _steer := Vector2.UP
## -1/+1 while detouring around something (which side), 0 when not.
var _detour := 0
var _detour_time := 0.0
var _tick := 0
var _walk_phase := 0.0
var _dead_t := 0.0
var _flash := 0.0
var _numbers: Array[Dictionary] = []
var _player: CharacterBody2D
var _col: CollisionShape2D


func _ready() -> void:
	hp = max_hp
	hearing_now = hearing
	add_to_group("zombies")
	add_to_group("concealable")
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_col = CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = RADIUS
	_col.shape = shape
	add_child(_col)
	_tick = randi() % 6
	_walk_phase = randf() * TAU
	rotation = randf() * TAU
	_player = get_tree().get_first_node_in_group("player")
	_new_wander()


func is_dead() -> bool:
	return state == State.DEAD


## A sound at pos: loudness at the source, % lost per meter.
func hear(pos: Vector2, loudness: float, falloff_pct: float) -> void:
	if state == State.DEAD:
		return
	var level := FirearmStats.loudness_at(loudness, falloff_pct, global_position.distance_to(pos) / PX)
	var heard := level >= 100.0 - hearing_now
	if level > DEAFEN_LEVEL:
		hearing_now = maxf(hearing_now - (level - DEAFEN_LEVEL) * DEAFEN_RATE, MIN_HEARING)
	if not heard or state == State.CHASE or state == State.ATTACK:
		return
	state = State.SEARCH
	# Quieter = vaguer idea of where it came from.
	var vague := lerpf(6.0, 1.0, clampf(level / 60.0, 0.0, 1.0))
	_goal = pos + Vector2(randf_range(-vague, vague), randf_range(-vague, vague)) * PX


func take_hit(hit: Dictionary) -> void:
	if state == State.DEAD:
		return
	var crit := Combat.is_crit(hit, global_position, HEAD_RADIUS, CRIT_DEPTH)
	var dmg: float = hit.damage * FirearmStats.armor_factor(hit.armor_penetration, 0) * (CRIT_MULT if crit else 1.0)
	hp -= dmg
	_flash = 0.1
	_stagger = 0.3 if crit else 0.18
	velocity += (hit.dir as Vector2) * (90.0 if crit else 45.0)
	_numbers.append({"text": ("CRIT %d" if crit else "%d") % roundi(dmg), "t": 0.0, "crit": crit, "x": randf_range(-10, 10)})
	if hp <= 0.0:
		_die(hit.dir)
		return
	# Shot: turn on the shooter.
	if state != State.ATTACK and _player:
		state = State.CHASE
		_goal = _player.global_position


func _physics_process(delta: float) -> void:
	_flash = maxf(_flash - delta, 0.0)
	for n in _numbers:
		n.t += delta
	_numbers = _numbers.filter(func(n): return n.t < 0.9)
	if state == State.DEAD:
		_dead_t += delta
		if _dead_t > 40.0:
			queue_free()
		queue_redraw()
		return

	_cooldown = maxf(_cooldown - delta, 0.0)
	_stagger = maxf(_stagger - delta, 0.0)
	hearing_now = minf(hearing_now + hearing_recovery * delta, hearing)
	_tick += 1
	if _tick % 5 == 0:
		_perceive()

	var speed := 0.0
	var face := _steer
	match state:
		State.WANDER:
			_wander_time -= delta
			if _wander_time <= 0.0 or global_position.distance_to(_goal) < 20.0:
				_new_wander()
			speed = wander_speed
		State.CHASE:
			speed = run_speed
			if _player and _can_reach_player():
				_start_attack()
		State.SEARCH:
			speed = run_speed * 0.8
			if global_position.distance_to(_goal) < 30.0:
				_new_wander()
		State.ATTACK:
			speed = 0.6
			_update_attack(delta)
			if _player:
				face = (_player.global_position - global_position).normalized()

	if state != State.ATTACK and _tick % 3 == 0:
		var desired := (_goal - global_position).normalized()
		_steer = _steer.lerp(_steer_dir(desired), 0.5).normalized()
		face = _steer

	# Turn toward the facing direction at a limited rate; move along facing.
	var want := face.angle() + PI / 2.0
	var max_step := deg_to_rad(turn_speed_deg) * delta
	rotation += clampf(wrapf(want - rotation, -PI, PI), -max_step, max_step)
	var forward := Vector2.UP.rotated(rotation)
	var along := clampf(forward.dot(_steer), 0.2, 1.0) if state != State.ATTACK else 1.0
	if _stagger > 0.0:
		speed *= 0.25
	if state == State.WANDER and _wander_time > 0.0 and fmod(_wander_time, 4.0) < 1.2:
		speed = 0.0 # shuffle-pause
	var target := forward * speed * PX * along
	velocity = velocity.move_toward(target, 900.0 * delta)
	move_and_slide()
	_walk_phase = fmod(_walk_phase + clampf(velocity.length() / (run_speed * PX), 0.0, 1.0) * 1.8 * TAU * delta, TAU)
	queue_redraw()


func _perceive() -> void:
	if not _player or _player.get("dead"):
		if state == State.CHASE or state == State.ATTACK:
			_new_wander()
		return
	var to := _player.global_position - global_position
	var dist := to.length()
	var forward := Vector2.UP.rotated(rotation)
	var in_cone := dist <= sight_m * PX and absf(forward.angle_to(to)) <= deg_to_rad(fov_deg / 2.0)
	var touching := dist <= 1.5 * PX
	var seen := (in_cone or touching) and _line_of_sight(_player)
	if seen:
		if state != State.ATTACK:
			state = State.CHASE
		_goal = _player.global_position
	elif state == State.CHASE:
		state = State.SEARCH # head to last known position


func _line_of_sight(target: CollisionObject2D) -> bool:
	var q := PhysicsRayQueryParameters2D.create(global_position, target.global_position)
	q.exclude = [get_rid()]
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and hit.collider == target


## Context steering: best of RAYS directions = toward desired, away from blocked.
func _steer_dir(desired: Vector2) -> Vector2:
	var space := get_world_2d().direct_space_state
	var exclude := [get_rid()]
	if state == State.CHASE and _player:
		exclude.append(_player.get_rid())
	var dirs: Array[Vector2] = []
	var dangers: Array[float] = []
	for i in RAYS:
		var d := Vector2.from_angle(TAU * i / RAYS)
		var q := PhysicsRayQueryParameters2D.create(global_position, global_position + d * (RADIUS + FEELER))
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		var danger := 0.0
		if not hit.is_empty():
			var free_px := global_position.distance_to(hit.position) - RADIUS
			danger = 1.0 - clampf(free_px / FEELER, 0.0, 1.0)
		dirs.append(d)
		dangers.append(danger)

	# Direct way blocked? Commit to the freer side until clear (or timeout).
	var ahead := _danger_toward(desired, dirs, dangers)
	_detour_time -= 0.05
	if ahead > 0.4:
		if _detour == 0:
			var left := _danger_toward(desired.rotated(-PI / 2.0), dirs, dangers)
			var right := _danger_toward(desired.rotated(PI / 2.0), dirs, dangers)
			_detour = -1 if left < right or (left == right and randf() < 0.5) else 1
			_detour_time = 3.0
	elif _detour_time < 2.5:
		_detour = 0
	if _detour_time <= 0.0:
		_detour = 0
	var side := desired.rotated(_detour * PI / 2.0)

	var best := desired
	var best_score := -INF
	for i in RAYS:
		var d := dirs[i]
		# Slight preference to keep the current heading (less jitter).
		var score := d.dot(desired) + 0.25 * d.dot(_steer) - dangers[i] * 2.0
		if _detour != 0:
			score += 0.7 * d.dot(side)
		if score > best_score:
			best_score = score
			best = d
	return best


## Danger of the ray closest to direction d.
func _danger_toward(d: Vector2, dirs: Array[Vector2], dangers: Array[float]) -> float:
	var best_i := 0
	var best_dot := -2.0
	for i in dirs.size():
		var dd := dirs[i].dot(d)
		if dd > best_dot:
			best_dot = dd
			best_i = i
	return dangers[best_i]


func _new_wander() -> void:
	state = State.WANDER
	_wander_time = randf_range(4.0, 9.0)
	_goal = global_position + Vector2.from_angle(randf() * TAU) * randf_range(3.0, 10.0) * PX


func _edge_distance_to_player() -> float:
	return global_position.distance_to(_player.global_position) - RADIUS - 16.0


func _can_reach_player() -> bool:
	return _cooldown <= 0.0 and _edge_distance_to_player() <= reach_m * PX


func _start_attack() -> void:
	state = State.ATTACK
	_attack_t = 0.0
	_struck = false


func _update_attack(delta: float) -> void:
	_attack_t += delta
	if not _struck and _attack_t >= windup:
		_struck = true
		var to := _player.global_position - global_position
		var forward := Vector2.UP.rotated(rotation)
		var in_arc := absf(forward.angle_to(to)) <= deg_to_rad(70.0)
		if in_arc and _edge_distance_to_player() <= (reach_m + 0.25) * PX:
			_player.take_damage(attack_damage, global_position)
	if _attack_t >= windup + 0.3:
		_cooldown = attack_cooldown
		state = State.CHASE


func _die(dir: Vector2) -> void:
	state = State.DEAD
	remove_from_group("zombies")
	_col.set_deferred("disabled", true)
	z_index = -1
	velocity = Vector2.ZERO
	rotation = (dir as Vector2).angle() + PI / 2.0 + randf_range(-0.4, 0.4)


func _draw() -> void:
	if state == State.DEAD:
		_draw_corpse()
		return
	var moving := clampf(velocity.length() / (run_speed * PX), 0.0, 1.0)
	var swing := sin(_walk_phase) * moving

	# Feet
	_ellipse(Vector2(-8, -4 - swing * 8), Vector2(4.5, 6.0), OUTLINE, Color(0.25, 0.22, 0.2))
	_ellipse(Vector2(8, -4 + swing * 8), Vector2(4.5, 6.0), OUTLINE, Color(0.25, 0.22, 0.2))
	# Torso (hunched, ragged)
	draw_set_transform(Vector2.ZERO, -swing * 0.15)
	_ellipse(Vector2(0, 2), Vector2(15, 9.5), OUTLINE, CLOTH)
	draw_set_transform(Vector2.ZERO)

	# Hands: reach forward when chasing; attack = right hand winds back then swipes across.
	var reach := 1.0 if state == State.CHASE or state == State.ATTACK else 0.35
	var left := Vector2(-8, -10 - 10 * reach)
	var right := Vector2(8, -10 - 10 * reach)
	if state == State.ATTACK:
		if _attack_t < windup:
			var k := _attack_t / windup
			right = right.lerp(Vector2(17, 4), k)
		else:
			var k := clampf((_attack_t - windup) / 0.15, 0.0, 1.0)
			right = Vector2(17, 4).lerp(Vector2(-6, -26), k)
	left.y += swing * 3.0
	_circle(left, 4.0, SKIN)
	_circle(right, 4.0, SKIN)

	# Head with eyes
	var head := SKIN.lerp(Color.WHITE, 0.6) if _flash > 0.0 else SKIN
	_circle(Vector2.ZERO, 7.0, head)
	draw_circle(Vector2(-2.5, -4), 1.3, Color(0.85, 0.15, 0.1))
	draw_circle(Vector2(2.5, -4), 1.3, Color(0.85, 0.15, 0.1))

	_draw_numbers()


func _draw_corpse() -> void:
	var fade := clampf(40.0 - _dead_t, 0.0, 1.0)
	draw_circle(Vector2(0, 6), 20.0, Color(0.35, 0.05, 0.05, 0.5 * fade))
	_ellipse(Vector2(0, 8), Vector2(9, 16), OUTLINE, CLOTH.darkened(0.3))
	_circle(Vector2(0, -12), 7.0, SKIN.darkened(0.3))
	_circle(Vector2(-12, 2), 4.0, SKIN.darkened(0.3))
	_circle(Vector2(11, 12), 4.0, SKIN.darkened(0.3))
	_draw_numbers()


func _draw_numbers() -> void:
	if _numbers.is_empty():
		return
	var font := ThemeDB.fallback_font
	var up := -get_viewport().get_canvas_transform().get_rotation() - global_rotation
	draw_set_transform(Vector2.ZERO, up)
	for n in _numbers:
		var a: float = 1.0 - n.t / 0.9
		var col := Color(1, 0.35, 0.2, a) if n.crit else Color(1, 0.95, 0.5, a)
		draw_string(font, Vector2(n.x - 50, -24 - n.t * 40.0), n.text, HORIZONTAL_ALIGNMENT_CENTER, 100, 22 if n.crit else 18, col)
	draw_set_transform(Vector2.ZERO)


func _circle(c: Vector2, r: float, col: Color) -> void:
	draw_circle(c, r + 1.5, OUTLINE)
	draw_circle(c, r, col)


func _ellipse(c: Vector2, radii: Vector2, outline: Color, fill: Color) -> void:
	draw_colored_polygon(_ellipse_points(c, radii + Vector2(1.5, 1.5)), outline)
	draw_colored_polygon(_ellipse_points(c, radii), fill)


func _ellipse_points(c: Vector2, radii: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		pts.append(c + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	return pts
