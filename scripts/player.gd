extends CharacterBody2D
## Top-down player. The camera is a child that rotates with the player, so
## "forward" (local -Y) is always screen-up, like an FPS seen from above.

@export var move_speed := 260.0
@export var keyboard_turn_speed := 2.8 # rad/s, desktop testing only

## Movement input in screen/local space, set by TouchControls.
## Length 0..1, (0, -1) = forward.
var move_input := Vector2.ZERO


func _physics_process(delta: float) -> void:
	var input := move_input
	var kb := _keyboard_move()
	if kb != Vector2.ZERO:
		input = kb
	velocity = input.limit_length(1.0).rotated(rotation) * move_speed
	move_and_slide()

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


func _draw() -> void:
	# Aim line
	for i in 12:
		var a := Vector2(0, -40 - i * 40)
		draw_line(a, a + Vector2(0, -20), Color(1, 0.9, 0.3, 0.35 - i * 0.025), 2.0)
	# Barrel
	draw_rect(Rect2(-4, -34, 8, 22), Color(0.25, 0.25, 0.25))
	# Body
	draw_circle(Vector2.ZERO, 16.0, Color(0.95, 0.75, 0.15))
	draw_circle(Vector2(0, -6), 6.0, Color(0.2, 0.2, 0.2))
