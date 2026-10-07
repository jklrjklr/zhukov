extends CharacterBody2D
## Top-down player. Swipes turn the camera (look_angle); the body follows at a
## limited turn rate, so fast flicks lag behind. The camera rig counter-rotates
## so the view stays on look_angle: screen-up is always where you are looking.
## Movement has light inertia (accel/decel), direction-dependent speed and a
## stamina-limited sprint.

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

const PX_PER_M := 60.0

## Where the camera looks (radians). Body rotation chases it.
var look_angle := 0.0
## 0..1
var stamina := 1.0
var sprinting := false
var _stamina_idle := 0.0
var _edge_t := 0.0

## Movement input in screen/local space, set by TouchControls.
## Length 0..1, (0, -1) = forward.
var move_input := Vector2.ZERO

## Body look: floating head, torso, hands and feet (no arms/legs), top-down.
const SKIN := Color(0.96, 0.78, 0.6)
const BODY := Color(0.55, 0.6, 0.65)
const HAIR := Color(0.3, 0.25, 0.2)
const BOOT := Color(0.22, 0.2, 0.18)
const OUTLINE := Color(0.08, 0.08, 0.08)
## Full step cycles (left+right foot) per second at full speed.
const STEP_CYCLES_PER_SEC := 1.5
## Speed multipliers by direction (relative to facing).
const FORWARD_SPEED := 1.0
const STRAFE_SPEED := 0.6
const BACK_SPEED := 0.7

var _ov: Node2D
var _walk_phase := 0.0 # radians
var _walk_amount := 0.0 # 0 idle .. 1 full stride, eased

@onready var _head: Node2D = $Head
@onready var _rig: Node2D = $CameraRig
@onready var camera: PlayerCamera = $CameraRig/ViewCamera


func _ready() -> void:
	add_to_group("player")
	# The body is drawn VISUAL_SCALE bigger (the whole node, so the collision circle too); the
	# camera rig cancels it so the camera maths stays in world pixels.
	scale = Vector2.ONE * Vis.VISUAL_SCALE
	_rig.scale = Vector2.ONE / Vis.VISUAL_SCALE
	_head.draw.connect(_draw_head)
	_ov = Node2D.new()
	_ov.name = "Overlay"
	_ov.draw.connect(_draw_overlay)
	add_child(_ov)
	look_angle = rotation


func _physics_process(delta: float) -> void:
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
	var speed := get_real_velocity().length()
	_walk_phase = fmod(_walk_phase + clampf(speed / move_speed, 0.0, 1.0) * STEP_CYCLES_PER_SEC * TAU * delta, TAU)
	_walk_amount = move_toward(_walk_amount, clampf(speed / move_speed, 0.0, 1.0), delta * 6.0)
	queue_redraw()
	_ov.queue_redraw()


func _draw() -> void:
	var swing := sin(_walk_phase) * _walk_amount
	var bob := absf(cos(_walk_phase)) * _walk_amount

	# Feet (alternate forward/back while walking)
	_shape_ellipse(Vector2(-9, -6 - swing * 9), Vector2(4.5, 6.5), BOOT)
	_shape_ellipse(Vector2(9, -6 + swing * 9), Vector2(4.5, 6.5), BOOT)

	# Torso (sways slightly opposite to feet)
	draw_set_transform(Vector2.ZERO, -swing * 0.12)
	_shape_ellipse(Vector2(0, 1), Vector2(16, 10), BODY)
	for sx in [-1.0, 1.0]:
		_shape_circle(self, Vector2(sx * 14.0, 0.5), 5.0, BODY.darkened(0.15))
	draw_set_transform(Vector2.ZERO)

	# Hands, swinging opposite to the feet
	_shape_circle(self, Vector2(-15, -8 + swing * 6 + bob), 4.0, SKIN)
	_shape_circle(self, Vector2(15, -8 - swing * 6 + bob), 4.0, SKIN)


func _draw_head() -> void:
	_shape_circle(_head, Vector2.ZERO, 7.0, HAIR)
	_head.draw_circle(Vector2(0, -3), 4.0, SKIN)


func _shape_circle(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	ci.draw_circle(c, r + 1.5, OUTLINE)
	ci.draw_circle(c, r, col)


func _shape_ellipse(c: Vector2, radii: Vector2, col: Color) -> void:
	draw_colored_polygon(_ellipse_points(c, radii + Vector2(1.5, 1.5)), OUTLINE)
	draw_colored_polygon(_ellipse_points(c, radii), col)


func _ellipse_points(c: Vector2, radii: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		pts.append(c + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	return pts


## Stamina arc around the player.
func _draw_overlay() -> void:
	if stamina >= 0.995:
		return
	var col := Color(0.4, 0.8, 1.0, 0.85) if stamina > 0.25 else Color(1.0, 0.55, 0.2, 0.9)
	_ov.draw_arc(Vector2.ZERO, 26.0, PI * 0.15, PI * 0.85, 12, Color(0, 0, 0, 0.35), 4.0)
	_ov.draw_arc(Vector2.ZERO, 26.0, PI * 0.15, PI * 0.15 + PI * 0.7 * stamina, 12, col, 3.0)
