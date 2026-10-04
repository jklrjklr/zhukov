extends CharacterBody2D
## Top-down player. The camera is a child that rotates with the player, so
## "forward" (local -Y) is always screen-up, like an FPS seen from above.
## Draw order: feet, torso, hands (this node) -> Firearm -> Head (children).

@export var move_speed := 260.0
@export var keyboard_turn_speed := 2.8 # rad/s, desktop testing only

## Movement input in screen/local space, set by TouchControls.
## Length 0..1, (0, -1) = forward.
var move_input := Vector2.ZERO

## Body look: floating head, torso, hands and feet (no arms/legs), top-down.
const SKIN := Color(0.96, 0.78, 0.6)
const ARMOR := Color(0.95, 0.75, 0.15)
const HELMET := Color(0.3, 0.32, 0.3)
const BOOT := Color(0.22, 0.2, 0.18)
const OUTLINE := Color(0.08, 0.08, 0.08)
## Full step cycles (left+right foot) per second at full speed. Decoupled from
## distance on purpose: feet may "skip" ground, the pace just reads calmer.
const STEP_CYCLES_PER_SEC := 1.5
## Speed multipliers by direction (relative to facing).
const FORWARD_SPEED := 1.0
const STRAFE_SPEED := 0.6
const BACK_SPEED := 0.7

var _walk_phase := 0.0 # radians, advances with distance moved
var _walk_amount := 0.0 # 0 idle .. 1 full stride, eased

@onready var weapon: Firearm = $Firearm
@onready var _head: Node2D = $Head


func _ready() -> void:
	_head.draw.connect(_draw_head)


func _physics_process(delta: float) -> void:
	var input := move_input
	var kb := _keyboard_move()
	if kb != Vector2.ZERO:
		input = kb
	input = input.limit_length(1.0)
	velocity = input.rotated(rotation) * move_speed * _direction_multiplier(input) * weapon.stats.move_multiplier()
	move_and_slide()
	_animate(delta)

	var kb_turn := float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q))
	if kb_turn != 0.0:
		turn(kb_turn * keyboard_turn_speed * weapon.stats.turn_multiplier() * delta)


## Positive = clockwise (turn right).
func turn(radians: float) -> void:
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
	# Walking swings the weapon left/right (aim only, camera stays).
	weapon.sway = sin(_walk_phase) * _walk_amount
	queue_redraw()


func _draw() -> void:
	var swing := sin(_walk_phase) * _walk_amount
	var bob := absf(cos(_walk_phase)) * _walk_amount

	# Feet (alternate forward/back while walking)
	_shape_ellipse(Vector2(-9, -6 - swing * 9), Vector2(4.5, 6.5), BOOT)
	_shape_ellipse(Vector2(9, -6 + swing * 9), Vector2(4.5, 6.5), BOOT)

	# Torso (wide shoulders, sways slightly opposite to feet)
	draw_set_transform(Vector2.ZERO, -swing * 0.12)
	_shape_ellipse(Vector2(0, 1), Vector2(16, 10), ARMOR)
	draw_set_transform(Vector2.ZERO)

	# Hands, under the weapon
	for p in weapon.hand_points():
		_shape_circle(self, p + Vector2(0, bob * 1.5), 4.0, SKIN)


func _draw_head() -> void:
	_shape_circle(_head, Vector2.ZERO, 7.0, HELMET)
	_head.draw_arc(Vector2.ZERO, 4.5, -PI * 0.8, -PI * 0.2, 10, Color(0.55, 0.85, 1.0), 2.5)


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
