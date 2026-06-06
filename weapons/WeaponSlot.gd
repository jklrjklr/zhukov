class_name WeaponSlot
extends Node2D

var data: WeaponData = null

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _muzzle: Node2D   = $Muzzle

func _ready() -> void:
	visible = false

func load_weapon(weapon_data: WeaponData) -> void:
	data = weapon_data
	if data == null:
		visible = false
		return
	visible = true
	if data.sprite_path != "" and ResourceLoader.exists(data.sprite_path):
		_sprite.texture = load(data.sprite_path)
	else:
		_sprite.texture = null

func clear() -> void:
	data = null
	visible = false

func get_muzzle_global_position() -> Vector2:
	return _muzzle.global_position

func get_muzzle_global_rotation() -> float:
	return _muzzle.global_rotation
