class_name Bullet
extends Area2D

var speed: float = 1200.0
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
	area_entered.connect(_on_area_entered)

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
	BulletSpawner.return_bullet(self)
