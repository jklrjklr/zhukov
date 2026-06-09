class_name Bullet
extends Area2D

var speed: float = 3600.0
var damage: int = 10
var headshot_multiplier: float = 3.0
var direction: Vector2 = Vector2.ZERO
var max_range: float = 1000.0
var traveled: float = 0.0

var _head_target: Node = null
var _body_target: Node = null
var _hit_queued: bool = false

@onready var _cast: ShapeCast2D = $ShapeCast2D

func _ready() -> void:
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

func init(pos: Vector2, dir: Vector2, dmg: int, spd: float = 3600.0, hs_mult: float = 3.0) -> void:
	global_position = pos
	direction = dir.normalized()
	rotation = dir.angle()
	damage = dmg
	speed = spd
	headshot_multiplier = hs_mult
	traveled = 0.0
	z_index = 10
	_head_target = null
	_body_target = null
	_hit_queued = false

func _physics_process(delta: float) -> void:
	var step_len := speed * delta

	# Sweep the bullet's collision shape along the travel direction before moving.
	# The bullet's local +X is aligned with direction (set via rotation in init),
	# so the cast target is simply forward along local X.
	_cast.target_position = Vector2(step_len, 0)
	_cast.force_shapecast_update()

	if _cast.is_colliding():
		var frac := _cast.get_closest_collision_unsafe_fraction()
		global_position += direction * step_len * frac
		traveled += step_len * frac
		_resolve_cast_hit(_cast.get_collider(0))
		return

	global_position += direction * step_len
	traveled += step_len
	if traveled >= max_range:
		recycle()

func _resolve_cast_hit(col: Object) -> void:
	if col is HurtBox:
		var hb := col as HurtBox
		var char_node := hb.get_character()
		if hb.hit_type == HurtBox.HitType.HEAD:
			if char_node != null and char_node.has_method("take_damage"):
				char_node.take_damage(int(damage * headshot_multiplier), true)
		else:
			if char_node != null and char_node.has_method("take_damage"):
				char_node.take_damage(damage, false)
		recycle()
		return
	var node := col as Node
	if node != null and not (node.is_in_group("player") or node.is_in_group("character")):
		recycle()

# Fallback for targets that move INTO the bullet (ShapeCast only sweeps forward).
# Preserves head-beats-body priority via deferred resolution.
func _on_area_entered(area: Area2D) -> void:
	if not (area is HurtBox):
		return
	var hb := area as HurtBox
	var char := hb.get_character()
	match hb.hit_type:
		HurtBox.HitType.HEAD:
			_head_target = char
		HurtBox.HitType.BODY:
			if _body_target == null:
				_body_target = char
	if not _hit_queued:
		_hit_queued = true
		call_deferred("_resolve_hit")

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player") or body.is_in_group("character"):
		return
	recycle()

func _resolve_hit() -> void:
	_hit_queued = false
	if _head_target != null:
		var dmg := int(damage * headshot_multiplier)
		if _head_target.has_method("take_damage"):
			_head_target.take_damage(dmg, true)
		recycle()
	elif _body_target != null:
		if _body_target.has_method("take_damage"):
			_body_target.take_damage(damage, false)
		recycle()
	_head_target = null
	_body_target = null

func recycle() -> void:
	if not is_inside_tree():
		queue_free()
		return
	var spawner := get_node_or_null("/root/BulletSpawner")
	if spawner != null:
		spawner.return_bullet(self)
	else:
		queue_free()
