class_name Zombie
extends CharacterBody2D
## Placeholder enemy: wanders, and shambles toward the player once within sight range.
## Body = pre-rendered sprite (CharSprite).

@export var skin := "zombieA"
@export var speed := 100.0 # px/s while chasing
@export var sight := 520.0 # px
@export var turn_speed := 3.0 # rad/s

var dead := false
var _sprite: CharSprite
var _wander := Vector2.ZERO
var _wander_t := 0.0


func _ready() -> void:
	add_to_group("enemies")
	scale = Vector2.ONE * Vis.VISUAL_SCALE
	collision_layer = 2
	collision_mask = 3
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	z_index = 10
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 14.0
	shape.shape = circle
	add_child(shape)
	_sprite = CharSprite.new()
	_sprite.skin = skin
	add_child(_sprite)
	_sprite.phase = randf()


## Killed by a hit travelling along `push` (world): falls that way and stays as a corpse
## (no collision, drawn under the living).
func die(push: Vector2) -> void:
	if dead:
		return
	dead = true
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0
	z_index = 4
	remove_from_group("enemies")
	_sprite.play_death(push.rotated(-rotation), randf_range(0.6, 0.85))


func _physics_process(delta: float) -> void:
	var target := Vector2.ZERO
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player and global_position.distance_to(player.global_position) < sight:
		target = (player.global_position - global_position).normalized() * speed
	else:
		_wander_t -= delta
		if _wander_t <= 0.0:
			_wander_t = randf_range(1.5, 4.0)
			_wander = Vector2.from_angle(randf() * TAU) * speed * 0.35 if randf() < 0.6 else Vector2.ZERO
		target = _wander
	velocity = velocity.move_toward(target, 600.0 * delta)
	if velocity.length() > 5.0:
		# Sprites face -Y: rotation 0 = up.
		var want := velocity.angle() + PI / 2.0
		rotation = rotate_toward(rotation, want, turn_speed * delta)
	move_and_slide()
	_sprite.advance(delta, get_real_velocity().length())
