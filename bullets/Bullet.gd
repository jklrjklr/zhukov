class_name Bullet
extends Area2D

var speed: float = 3600.0
var damage: int = 10
var headshot_multiplier: float = 3.0
var direction: Vector2 = Vector2.ZERO
var max_range: float = 1000.0
var traveled: float = 0.0

# Deferred-hit state: collect both body and head contacts this frame,
# then resolve once so head always beats body regardless of callback order.
var _head_target: Node = null
var _body_target: Node = null
var _hit_queued: bool = false

func _ready() -> void:
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

func init(pos: Vector2, dir: Vector2, dmg: int, spd: float = 1200.0, hs_mult: float = 3.0) -> void:
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
	var step: Vector2 = direction * speed * delta

	# Raycast along the movement step so fast bullets never tunnel through thin
	# HurtBoxes. At 3600 px/s the step is ~60px — larger than a head hitbox.
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
			global_position, global_position + step)
	query.collide_with_areas  = true
	query.collide_with_bodies = true
	query.exclude = [self]

	var hit := space.intersect_ray(query)
	if hit:
		var col: Object = hit["collider"]
		if col is HurtBox:
			var hb := col as HurtBox
			var char_node := hb.get_character()
			if hb.hit_type == HurtBox.HitType.HEAD:
				if char_node != null and char_node.has_method("take_damage"):
					char_node.take_damage(int(damage * headshot_multiplier), true)
			else:
				if char_node != null and char_node.has_method("take_damage"):
					char_node.take_damage(damage, false)
			global_position = hit["position"]
			recycle()
			return
		# Wall / world geometry — groups used by the old signal handler
		var body := col as Node
		if not (body.is_in_group("player") or body.is_in_group("character")):
			global_position = hit["position"]
			recycle()
			return

	global_position += step
	traveled += step.length()
	if traveled >= max_range:
		recycle()

# HurtBox Area2D hits — collect this frame, resolve deferred so head wins.
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

# Physics body hits — only used for world geometry (walls/floors).
# Characters that use HurtBoxes are skipped here.
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
	# Look the pool up by path rather than the autoload identifier so this
	# script also compiles under the headless `--script` test runner (which
	# does not register autoloads). Falls back to freeing if the pool is gone.
	var spawner := get_node_or_null("/root/BulletSpawner")
	if spawner != null:
		spawner.return_bullet(self)
	else:
		queue_free()
