extends CharacterBody2D
## Top-down player. The camera is a child that rotates with the player, so
## "forward" (local -Y) is always screen-up, like an FPS seen from above.

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
const GUN := Color(0.18, 0.18, 0.2)
const OUTLINE := Color(0.08, 0.08, 0.08)
const STRIDE := 34.0 # px travelled per full step cycle

var _walk_phase := 0.0 # radians, advances with distance moved
var _walk_amount := 0.0 # 0 idle .. 1 full stride, eased


func _physics_process(delta: float) -> void:
	var input := move_input
	var kb := _keyboard_move()
	if kb != Vector2.ZERO:
		input = kb
	velocity = input.limit_length(1.0).rotated(rotation) * move_speed
	move_and_slide()
	_animate(delta)

	var kb_turn := float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q))
	if kb_turn != 0.0:
		turn(kb_turn * keyboard_turn_speed * delta)


## Positive = clockwise (turn right).
func turn(radians: float) -> void:
	rotation = wrapf(rotation + radians, -PI, PI)


func _keyboard_move() -> Vector2:
	var v := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	return v.normalized()


func _animate(delta: float) -> void:
	var speed := get_real_velocity().length()
	_walk_phase = fmod(_walk_phase + speed * delta / STRIDE * TAU, TAU)
	_walk_amount = move_toward(_walk_amount, clampf(speed / move_speed, 0.0, 1.0), delta * 6.0)
	queue_redraw()


func _draw() -> void:
	# Aim line
	for i in 12:
		var a := Vector2(0, -50 - i * 40)
		draw_line(a, a + Vector2(0, -20), Color(1, 0.9, 0.3, 0.35 - i * 0.025), 2.0)

	var swing := sin(_walk_phase) * _walk_amount
	var bob := absf(cos(_walk_phase)) * _walk_amount

	# Feet (alternate forward/back while walking)
	_shape_ellipse(Vector2(-9, -6 - swing * 9), Vector2(4.5, 6.5), BOOT)
	_shape_ellipse(Vector2(9, -6 + swing * 9), Vector2(4.5, 6.5), BOOT)

	# Torso (wide shoulders, sways slightly opposite to feet)
	var torso_rot := -swing * 0.12
	draw_set_transform(Vector2.ZERO, torso_rot)
	_shape_ellipse(Vector2(0, 1), Vector2(16, 10), ARMOR)
	draw_set_transform(Vector2.ZERO)

	# Gun held forward along the aim line
	draw_rect(Rect2(-3, -44, 6, 30), OUTLINE)
	draw_rect(Rect2(-2, -43, 4, 28), GUN)

	# Hands: right on grip, left on handguard
	var hand_bob := Vector2(0, bob * 1.5)
	_shape_circle(Vector2(4, -17) + hand_bob, 4.0, SKIN)
	_shape_circle(Vector2(-3, -31) + hand_bob, 4.0, SKIN)

	# Head (helmet with visor facing forward)
	_shape_circle(Vector2(0, 0), 7.0, HELMET)
	draw_arc(Vector2(0, 0), 4.5, -PI * 0.8, -PI * 0.2, 10, Color(0.55, 0.85, 1.0), 2.5)


func _shape_circle(c: Vector2, r: float, col: Color) -> void:
	draw_circle(c, r + 1.5, OUTLINE)
	draw_circle(c, r, col)


func _shape_ellipse(c: Vector2, radii: Vector2, col: Color) -> void:
	draw_colored_polygon(_ellipse_points(c, radii + Vector2(1.5, 1.5)), OUTLINE)
	draw_colored_polygon(_ellipse_points(c, radii), col)


func _ellipse_points(c: Vector2, radii: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		pts.append(c + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	return pts
