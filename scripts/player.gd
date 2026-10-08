extends CharacterBody2D
## Top-down player. Swipes turn the camera (look_angle); the body and its sprite face the look
## direction at once (snappy: no turn lag), so screen-up is always where you are looking.
## Movement: the stick is quantised to 8 directions relative to the look direction, with light
## inertia, direction-dependent speed and a stamina-limited sprint that only exists toward the
## front three directions. Dodge = dive: committed lunge along the exact stick direction with
## invulnerability while airborne, then a short prone slide and getting up (vulnerable, no
## control): mistimed dives are punished. The body keeps facing the look direction during the
## dive; a firearm can be fired while airborne, melee cannot.

@export var move_speed := 180.0 # px/s base walk (3 m/s)
@export var keyboard_turn_speed := 2.8 # rad/s, desktop testing only
## px/s^2
@export var acceleration := 1100.0
@export var deceleration := 1400.0
## Sprint: joystick pushed to the edge (or Shift). Speed multiplier and seconds of stamina.
@export var sprint_mult := 1.5
@export var stamina_seconds := 6.0
@export var stamina_regen_delay := 1.0

## Dive: total time (s, matches the baked clip: airborne, prone slide, getting up), airborne
## distance (m), and the clip fractions where flight ends / the slide ends.
@export var dive_time := 1.6
@export var dive_distance := 3.2
const DIVE_AIR_END := 0.34
const DIVE_SLIDE_END := 0.5
## Invulnerable from take-off until landing (fractions of dive_time).
const DIVE_IFRAMES := Vector2(0.05, 0.34)

const PX_PER_M := 60.0

enum Weapon { FIREARM, MELEE }
## Firearm: shoots along the look direction, also during the airborne part of a dive. Melee:
## swings in front of the player, never during a dive.
@export var weapon_type := Weapon.FIREARM
@export var fire_interval := 0.11
@export var melee_interval := 0.4
@export var melee_range := 90.0
## Shoots by itself while an enemy is in the aim cone (design: toggleable); F fires by hand.
@export var auto_fire := true
const AIM_CONE := deg_to_rad(12.0)
const AUTO_RANGE := 700.0

## Where the camera looks (radians). The body faces it.
var look_angle := 0.0
## 0..1
var stamina := 1.0
var sprinting := false
var _stamina_idle := 0.0
var _edge_t := 0.0
## Dive progress 0..1 (-1 = not diving) and its world direction (exact stick direction).
var _dive_t := -1.0
var _dive_dir := Vector2.UP
## Dive animation: dive direction relative to the look direction snapped to 8, 0..7
## (CharSprite.TAGS: forward, forward-right, right, back-right, back, back-left, left, forward-left).
var dive_index := 0
## Walk / run direction relative to the look direction, 0..7, -1 while there is no stick input.
var move_index := -1
var _anim_index := 0

var shots_fired := 0
var melee_swings := 0
var _attack_cd := 0.0
var _flash := 0.0
var _swing := 0.0

## Movement input in screen/local space, set by TouchControls.
## Length 0..1, (0, -1) = forward.
var move_input := Vector2.ZERO

## Speed multipliers by direction (relative to facing).
const FORWARD_SPEED := 1.0
const STRAFE_SPEED := 0.6
const BACK_SPEED := 0.7

var _ov: Node2D

## Pre-rendered body (3D model baked to sprites, see tools/bake_sprites.gd).
@onready var sprite: CharSprite = $Sprite
@onready var _rig: Node2D = $CameraRig
@onready var camera: PlayerCamera = $CameraRig/ViewCamera


func _ready() -> void:
	add_to_group("player")
	sprite.armed = true
	# The body is drawn VISUAL_SCALE bigger (the whole node, so the collision circle too); the
	# camera rig cancels it so the camera maths stays in world pixels.
	scale = Vector2.ONE * Vis.VISUAL_SCALE
	_rig.scale = Vector2.ONE / Vis.VISUAL_SCALE
	_ov = Node2D.new()
	_ov.name = "Overlay"
	_ov.draw.connect(_draw_overlay)
	add_child(_ov)
	look_angle = rotation


## Dodge. Direction: the stick (or WASD) EXACTLY (not quantised), else straight ahead. The
## animation is the dive direction relative to the look direction snapped to 8.
func dive() -> void:
	if is_diving():
		return
	var input := _keyboard_move()
	if input == Vector2.ZERO:
		input = move_input
	var rel := input.normalized() if input.length() > 0.2 else Vector2.UP
	_dive_dir = rel.rotated(look_angle)
	dive_index = CharSprite.dir_index(rel)
	rotation = look_angle
	_dive_t = 0.0
	sprinting = false


func is_diving() -> bool:
	return _dive_t >= 0.0


## True while damage should be ignored (airborne part of the dive).
func is_invulnerable() -> bool:
	return _dive_t >= DIVE_IFRAMES.x and _dive_t < DIVE_IFRAMES.y


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k.pressed and not k.echo and (k.physical_keycode == KEY_SPACE or k.physical_keycode == KEY_C):
		dive()
	elif k.pressed and not k.echo and k.physical_keycode == KEY_K:
		debug_kill_nearby()


## Debug: kills enemies within 10 m as if shot from here.
func debug_kill_nearby() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		var z := e as Node2D
		if z.global_position.distance_to(global_position) < 600.0:
			z.die(z.global_position - global_position)


func _physics_process(delta: float) -> void:
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	_flash = maxf(_flash - delta, 0.0)
	_swing = maxf(_swing - delta, 0.0)
	if is_diving():
		_update_dive(delta)
		_update_attack()
		return
	var input := move_input
	var kb := _keyboard_move()
	if kb != Vector2.ZERO:
		input = kb
	input = input.limit_length(1.0)

	var kb_turn := float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT))
	if kb_turn != 0.0:
		turn_look(kb_turn * keyboard_turn_speed * delta)

	# The body (and its sprite) faces the look direction at once.
	rotation = look_angle
	_rig.rotation = 0.0

	# 8 directions relative to the look direction (screen space of the stick).
	move_index = _quantize_index(input)
	if move_index >= 0:
		_anim_index = move_index
		input = CharSprite.dir_vector(move_index) * input.length()
	else:
		input = Vector2.ZERO

	# Sprint: stick held at the edge (or Shift), stamina left, and only toward the front
	# (forward, forward-left, forward-right); the other directions always walk.
	_edge_t = _edge_t + delta if input.length() >= 0.97 else 0.0
	var want_sprint := (_edge_t > 0.12 or Input.is_physical_key_pressed(KEY_SHIFT)) and input.length() > 0.5
	sprinting = want_sprint and stamina > 0.0 and can_run()
	if sprinting:
		stamina = maxf(stamina - delta / stamina_seconds, 0.0)
		_stamina_idle = 0.0
	else:
		_stamina_idle += delta
		if _stamina_idle > stamina_regen_delay:
			stamina = minf(stamina + delta / (stamina_seconds * 0.6), 1.0)

	# The stick is screen-relative (camera = look direction); speed penalties by direction.
	var dir_world := input.rotated(look_angle)
	var target := dir_world * move_speed * _direction_multiplier(input)
	if sprinting:
		target *= sprint_mult
	var rate := acceleration if target.length() > velocity.length() else deceleration
	velocity = velocity.move_toward(target, rate * delta)
	move_and_slide()
	_animate(delta)
	_update_attack()


## Running exists only toward the front three directions (relative to the look direction).
func can_run() -> bool:
	return move_index in CharSprite.RUN_DIRS


## Stick direction -> index 0..7 (clockwise from forward), with a little hysteresis so a stick
## resting on a sector border doesn't flicker; -1 without input.
func _quantize_index(input: Vector2) -> int:
	if input.length() < 0.01:
		return -1
	var raw := rad_to_deg(atan2(input.x, -input.y))
	if move_index >= 0 and absf(wrapf(raw - move_index * 45.0, -180.0, 180.0)) < 22.5 + 4.0:
		return move_index
	return CharSprite.dir_index(input)


## Airborne: constant fast lunge; prone: slide to a stop; getting up: no movement. The body and
## sprite keep facing the look direction (the camera can still be turned) while the motion
## follows the exact dive direction; the animation is the one for that direction relative to look.
func _update_dive(delta: float) -> void:
	_dive_t += delta / dive_time
	var kb_turn := float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT))
	if kb_turn != 0.0:
		turn_look(kb_turn * keyboard_turn_speed * delta)
	rotation = look_angle
	_rig.rotation = 0.0
	var air_speed := dive_distance * PX_PER_M / (DIVE_AIR_END * dive_time)
	if _dive_t < DIVE_AIR_END:
		velocity = _dive_dir * air_speed
	elif _dive_t < DIVE_SLIDE_END:
		velocity = _dive_dir * air_speed * 0.35 * (1.0 - inverse_lerp(DIVE_AIR_END, DIVE_SLIDE_END, _dive_t))
	else:
		velocity = Vector2.ZERO
	move_and_slide()
	sprite.lift = sin(PI * clampf(_dive_t / DIVE_AIR_END, 0.0, 1.0))
	sprite.show_clip("dive_%d" % dive_index, _dive_t)
	if _dive_t >= 1.0:
		_dive_t = -1.0
		sprite.lift = 0.0
		sprite.anim = "idle_aim"
		sprite.phase = 0.0
	_ov.queue_redraw()


## Attacking is allowed on foot; in a dive only with a firearm and only while airborne.
func can_attack() -> bool:
	if is_diving():
		return weapon_type == Weapon.FIREARM and _dive_t < DIVE_AIR_END
	return true


## Attacks once if allowed and the weapon is ready: a bullet along the look direction from the
## gun's muzzle (firearm) or a swing in front (melee). Returns whether it happened.
func try_attack() -> bool:
	if _attack_cd > 0.0 or not can_attack():
		return false
	if weapon_type == Weapon.FIREARM:
		_attack_cd = fire_interval
		var b := Bullet.new()
		b.dir = Vector2.UP.rotated(look_angle)
		b.position = muzzle_position()
		get_parent().add_child(b)
		shots_fired += 1
		_flash = 0.07
		_ov.queue_redraw()
		return true
	_attack_cd = melee_interval
	melee_swings += 1
	_swing = 0.15
	var fwd := Vector2.UP.rotated(look_angle)
	for e in get_tree().get_nodes_in_group("enemies"):
		var d := (e as Node2D).global_position - global_position
		if d.length() < melee_range and absf(fwd.angle_to(d)) < deg_to_rad(60.0):
			e.die(d)
	_ov.queue_redraw()
	return true


## Muzzle of the gun in the world (from the sprite frame's weapon anchor).
func muzzle_position() -> Vector2:
	var m := sprite.muzzle_local()
	if m == Vector2.INF:
		return global_position + Vector2.UP.rotated(look_angle) * 30.0
	return sprite.global_position + (m / Vis.CAM_ZOOM * (1.0 + sprite.lift * 0.18)).rotated(sprite.global_rotation)


func _update_attack() -> void:
	var want := Input.is_physical_key_pressed(KEY_F)
	if not want and auto_fire:
		want = _enemy_in_cone()
	if want:
		try_attack()


func _enemy_in_cone() -> bool:
	var fwd := Vector2.UP.rotated(look_angle)
	var firearm := weapon_type == Weapon.FIREARM
	var reach := AUTO_RANGE if firearm else melee_range
	for e in get_tree().get_nodes_in_group("enemies"):
		var d := (e as Node2D).global_position - global_position
		if d.length() < reach and absf(fwd.angle_to(d)) < AIM_CONE + (0.0 if firearm else 0.5):
			return true
	return false


## Swipe / keyboard turning: moves the camera; the body follows.
## Positive = clockwise (turn right).
func turn_look(radians: float) -> void:
	look_angle = wrapf(look_angle + radians, -PI, PI)


## Moves camera and body together (e.g. a knock or recoil).
func kick(radians: float) -> void:
	look_angle = wrapf(look_angle + radians, -PI, PI)
	rotation = wrapf(rotation + radians, -PI, PI)


## Blend forward/strafe/back multipliers by direction (squared components sum to 1).
func _direction_multiplier(input: Vector2) -> float:
	if input == Vector2.ZERO:
		return 1.0
	var d := input.normalized()
	var fb := FORWARD_SPEED if d.y < 0.0 else BACK_SPEED
	return d.x * d.x * STRAFE_SPEED + d.y * d.y * fb


func _keyboard_move() -> Vector2:
	var v := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	return v.normalized()


func _animate(delta: float) -> void:
	sprite.advance_dir(delta, get_real_velocity().length(), _anim_index, sprinting)
	_ov.queue_redraw()


## Stamina arc around the player, muzzle flash, melee swing.
func _draw_overlay() -> void:
	if _flash > 0.0:
		_draw_muzzle_flash()
	if _swing > 0.0:
		var a := Vector2.UP.angle()
		_ov.draw_arc(Vector2.ZERO, melee_range / Vis.VISUAL_SCALE, a - 1.05, a + 1.05, 10, Color(1, 1, 1, 0.8), 2.0)
	if stamina >= 0.995:
		return
	var col := Pal.STAMINA if stamina > 0.25 else Pal.STAMINA_LOW
	_ov.draw_arc(Vector2.ZERO, 26.0, PI * 0.15, PI * 0.85, 12, Color(0, 0, 0, 0.35), 2.5)
	_ov.draw_arc(Vector2.ZERO, 26.0, PI * 0.15, PI * 0.15 + PI * 0.7 * stamina, 12, col, 1.5)


## Orange / yellow star at the muzzle for a few frames (orange = fire).
func _draw_muzzle_flash() -> void:
	var at := _ov.to_local(muzzle_position())
	var fwd := Vector2.UP
	var side := Vector2.RIGHT
	var u := 1.0 / Vis.VISUAL_SCALE
	_ov.draw_colored_polygon(PackedVector2Array([at + fwd * 16 * u, at + side * 5 * u, at - fwd * 3 * u, at - side * 5 * u]), Color(1.0, 0.62, 0.18))
	_ov.draw_colored_polygon(PackedVector2Array([at + fwd * 9 * u, at + side * 2.5 * u, at - fwd * 1 * u, at - side * 2.5 * u]), Color(1.0, 0.95, 0.7))
