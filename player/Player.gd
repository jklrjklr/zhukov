class_name Player
extends CharacterBody2D

@export var move_speed: float = 180.0
@export var ergonomics: float = 0.5
@export_range(-3.1416, 3.1416, 0.1) var facing_offset: float = 0.0
@export_range(5.0, 90.0, 1.0) var ease_start_deg: float = 30.0
@export_range(0.0, 0.5, 0.01) var ease_min_factor: float = 0.5

@onready var _camera: Camera2D = $Camera2D
@onready var _sprite: Node2D   = $Sprite2D
@onready var inventory: InventorySystem = $InventorySystem

var _facing_angle: float = 0.0
var _initialized: bool = false
var _turn_speed_rad: float = 0.0
var _reaction_delay: float = 0.0

var max_health: int = 100
var health: int = 100

signal health_changed(new_hp: int)
signal player_died
signal headshot_received

func _ready() -> void:
	_update_ergonomics_stats()
	# temp test setup — remove later
	await get_tree().process_frame
	$WeaponSystem.equip(0, "micro_uzi")
	add_to_group("player")

func _physics_process(delta: float) -> void:
	if not _initialized:
		_facing_angle = _get_target_angle()
		_sprite.rotation = _facing_angle
		_initialized = true
		return
	_apply_movement(delta)
	_update_facing(delta)

func _get_target_angle() -> float:
	return _camera.rotation + facing_offset

func _apply_movement(delta: float) -> void:
	var raw_dir: Vector2 = TouchInputHandler.get_move_vector()
	if raw_dir.length_squared() < 0.01:
		velocity = velocity.move_toward(Vector2.ZERO, move_speed * 8.0 * delta)
	else:
		velocity = raw_dir.rotated(_camera.rotation) * move_speed
	move_and_slide()

func _update_facing(delta: float) -> void:
	var target_angle: float = _get_target_angle()
	var gap: float = absf(angle_difference(_facing_angle, target_angle))

	if gap <= deg_to_rad(0.1):
		_facing_angle = target_angle
		_sprite.rotation = _facing_angle
		return

	var ease_start_rad: float = deg_to_rad(ease_start_deg)
	var speed: float
	if gap >= ease_start_rad:
		speed = _turn_speed_rad
	else:
		var t: float = gap / ease_start_rad
		speed = _turn_speed_rad * lerpf(ease_min_factor, 1.0, smoothstep(0.0, 1.0, t))

	_facing_angle = rotate_toward(_facing_angle, target_angle, speed * delta)
	_sprite.rotation = _facing_angle

func _update_ergonomics_stats() -> void:
	_turn_speed_rad = deg_to_rad(lerpf(90.0, 480.0, ergonomics))
	_reaction_delay = lerpf(0.5, 0.05, ergonomics)

func set_ergonomics(value: float) -> void:
	ergonomics = clampf(value, 0.0, 1.0)
	_update_ergonomics_stats()

func take_damage(amount: int, is_headshot: bool = false) -> void:
	health = max(0, health - amount)
	health_changed.emit(health)
	if is_headshot:
		headshot_received.emit()
	if health == 0:
		player_died.emit()

func heal(amount: int) -> void:
	health = min(max_health, health + amount)
	health_changed.emit(health)

func angle_difference(from: float, to: float) -> float:
	return fposmod(to - from + PI, TAU) - PI

func rotate_toward(current: float, target: float, step: float) -> float:
	var diff := angle_difference(current, target)
	if absf(diff) <= step:
		return target
	return current + sign(diff) * step
