extends CharacterBody2D
## Top-down player. Swipes turn the camera (look_angle); the body follows at a
## limited turn rate, so fast flicks lag behind. The camera rig counter-rotates
## so the view stays on look_angle: screen-up is always where you are looking.
## Movement has light inertia (accel/decel), direction-dependent speed and a
## stamina-limited sprint. Dodge = dive: committed lunge in the stick direction with
## invulnerability while airborne, then a short prone slide and getting up (vulnerable,
## no control): mistimed dives are punished.

@export var move_speed := 180.0 # px/s base walk (3 m/s)
@export var keyboard_turn_speed := 2.8 # rad/s, desktop testing only
## Body turn rate (deg/s).
@export var body_turn_speed := 300.0
## px/s^2
@export var acceleration := 1100.0
@export var deceleration := 1400.0
## Sprint: joystick pushed to the edge (or Shift). Speed multiplier and seconds of stamina.
@export var sprint_mult := 1.5
@export var stamina_seconds := 6.0
@export var stamina_regen_delay := 1.0

## Dive: total time (s, matches the baked clip: airborne, prone slide, getting up), airborne
## distance (m), and the clip fractions where flight ends / the slide ends.
@export var dive_time := 0.8
@export var dive_distance := 3.2
const DIVE_AIR_END := 0.55
const DIVE_SLIDE_END := 0.72
## Invulnerable from take-off until landing (fractions of dive_time).
const DIVE_IFRAMES := Vector2(0.05, 0.55)

const PX_PER_M := 60.0

## Where the camera looks (radians). Body rotation chases it.
var look_angle := 0.0
## 0..1
var stamina := 1.0
var sprinting := false
var _stamina_idle := 0.0
var _edge_t := 0.0
## Dive progress 0..1 (-1 = not diving) and its world direction.
var _dive_t := -1.0
var _dive_dir := Vector2.UP

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
	# The body is drawn VISUAL_SCALE bigger (the whole node, so the collision circle too); the
	# camera rig cancels it so the camera maths stays in world pixels.
	scale = Vector2.ONE * Vis.VISUAL_SCALE
	_rig.scale = Vector2.ONE / Vis.VISUAL_SCALE
	_ov = Node2D.new()
	_ov.name = "Overlay"
	_ov.draw.connect(_draw_overlay)
	add_child(_ov)
	look_angle = rotation


## Dodge. Direction: the stick (or WASD), else straight ahead.
func dive() -> void:
	if is_diving():
		return
	var input := _keyboard_move()
	if input == Vector2.ZERO:
		input = move_input
	_dive_dir = input.rotated(look_angle).normalized() if input.length() > 0.2 else Vector2.UP.rotated(rotation)
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


func _physics_process(delta: float) -> void:
	if is_diving():
		_update_dive(delta)
		return
	var input := move_input
	var kb := _keyboard_move()
	if kb != Vector2.ZERO:
		input = kb
	input = input.limit_length(1.0)

	var kb_turn := float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT))
	if kb_turn != 0.0:
		turn_look(kb_turn * keyboard_turn_speed * delta)

	# Body chases the camera at a limited rate.
	var max_step := deg_to_rad(body_turn_speed) * delta
	var diff := wrapf(look_angle - rotation, -PI, PI)
	rotation = wrapf(rotation + clampf(diff, -max_step, max_step), -PI, PI)
	_rig.rotation = wrapf(look_angle - rotation, -PI, PI)

	# Sprint: stick held at the edge (or Shift), with stamina left.
	_edge_t = _edge_t + delta if input.length() >= 0.97 else 0.0
	var want_sprint := (_edge_t > 0.12 or Input.is_physical_key_pressed(KEY_SHIFT)) and input.length() > 0.5
	sprinting = want_sprint and stamina > 0.0
	if sprinting:
		stamina = maxf(stamina - delta / stamina_seconds, 0.0)
		_stamina_idle = 0.0
	else:
		_stamina_idle += delta
		if _stamina_idle > stamina_regen_delay:
			stamina = minf(stamina + delta / (stamina_seconds * 0.6), 1.0)

	# Joystick is screen-relative (camera); speed penalties are body-relative.
	var dir_world := input.rotated(look_angle)
	var target := dir_world * move_speed * _direction_multiplier(dir_world.rotated(-rotation))
	if sprinting:
		target *= sprint_mult
	var rate := acceleration if target.length() > velocity.length() else deceleration
	velocity = velocity.move_toward(target, rate * delta)
	move_and_slide()
	_animate(delta)


## Airborne: constant fast lunge; prone: slide to a stop; getting up: no movement.
## The camera can still be turned; the body keeps its facing, the sprite faces the dive.
func _update_dive(delta: float) -> void:
	_dive_t += delta / dive_time
	var kb_turn := float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT))
	if kb_turn != 0.0:
		turn_look(kb_turn * keyboard_turn_speed * delta)
	_rig.rotation = wrapf(look_angle - rotation, -PI, PI)
	var air_speed := dive_distance * PX_PER_M / (DIVE_AIR_END * dive_time)
	if _dive_t < DIVE_AIR_END:
		velocity = _dive_dir * air_speed
	elif _dive_t < DIVE_SLIDE_END:
		velocity = _dive_dir * air_speed * 0.35 * (1.0 - inverse_lerp(DIVE_AIR_END, DIVE_SLIDE_END, _dive_t))
	else:
		velocity = Vector2.ZERO
	move_and_slide()
	sprite.rotation = wrapf(_dive_dir.angle() + PI / 2.0 - rotation, -PI, PI)
	sprite.lift = sin(PI * clampf(_dive_t / DIVE_AIR_END, 0.0, 1.0))
	sprite.show_clip("dive", _dive_t)
	if _dive_t >= 1.0:
		_dive_t = -1.0
		sprite.rotation = 0.0
		sprite.lift = 0.0
		sprite.anim = "idle"
	_ov.queue_redraw()


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
	sprite.advance(delta, get_real_velocity().length())
	_ov.queue_redraw()


## Stamina arc around the player.
func _draw_overlay() -> void:
	if stamina >= 0.995:
		return
	var col := Pal.STAMINA if stamina > 0.25 else Pal.STAMINA_LOW
	_ov.draw_arc(Vector2.ZERO, 26.0, PI * 0.15, PI * 0.85, 12, Color(0, 0, 0, 0.35), 2.5)
	_ov.draw_arc(Vector2.ZERO, 26.0, PI * 0.15, PI * 0.15 + PI * 0.7 * stamina, 12, col, 1.5)
