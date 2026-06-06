class_name Bullet
extends Area2D

var speed: float = 1200.0
var damage: int = 10
var direction: Vector2 = Vector2.ZERO
var max_range: float = 1000.0
var traveled: float = 0.0

func init(pos: Vector2, dir: Vector2, dmg: int, spd: float = 1200.0) -> void:
	global_position = pos
	direction = dir.normalized()
	rotation = dir.angle()
	damage = dmg
	speed = spd
	traveled = 0.0
	z_index = 10

func _physics_process(delta: float) -> void:
	var step: Vector2 = direction * speed * delta
	global_position += step
	traveled += step.length()
	if traveled >= max_range:
		recycle()

func _on_body_entered(body: Node) -> void:
	if body == get_tree().get_first_node_in_group("player"):
		return
	if body.has_method("take_damage"):
		body.take_damage(damage)
	recycle()

func recycle() -> void:
	BulletSpawner.return_bullet(self)
