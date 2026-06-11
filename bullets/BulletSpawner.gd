# res://bullets/BulletSpawner.gd
extends Node

const BULLET_SCENE := preload("res://bullets/Bullet.tscn")
const POOL_SIZE    := 64

var _pool: Array[Bullet] = []

func _ready() -> void:
	for i in POOL_SIZE:
		var b: Bullet = BULLET_SCENE.instantiate()
		add_child(b)
		b.top_level = true
		b.set_physics_process(false)
		b.monitoring = false
		b.visible    = false
		_pool.append(b)

func spawn(origin: Vector2, direction: Vector2, ammo_hitpower: float, weapon_data: WeaponData, speed: float = 3600.0) -> void:
	var b: Bullet = _acquire()
	b.init(origin, direction, ammo_hitpower, weapon_data, speed)
	b.set_physics_process(true)
	b.monitoring = true
	b.visible    = true

func return_bullet(b: Bullet) -> void:
	b.set_physics_process(false)
	b.set_deferred("monitoring", false)
	b.visible = false
	b.global_position = Vector2(-99999.0, -99999.0)
	_pool.append(b)

func _acquire() -> Bullet:
	if _pool.is_empty():
		var b: Bullet = BULLET_SCENE.instantiate()
		add_child(b)
		return b
	return _pool.pop_back()
