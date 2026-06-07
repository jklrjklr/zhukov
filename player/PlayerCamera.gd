class_name PlayerCamera
extends Camera2D

@export var view_offset: float = 250.0
@export var base_zoom: float = 1.0
@export var recoil_zoom_step: float = 0.02
@export var recoil_zoom_max: float = 0.35
@export var recoil_zoom_return_speed: float = 0.5

var _recoil_zoom: float = 0.0
var _ads_scope_mult: float = 1.0

func _ready() -> void:
	TouchInputHandler.camera_rotated.connect(_on_camera_rotated)
	_refresh_camera()

func _physics_process(delta: float) -> void:
	var zoom_sq := _ads_scope_mult * _ads_scope_mult
	_recoil_zoom = move_toward(_recoil_zoom, 0.0, recoil_zoom_return_speed * zoom_sq * delta)
	_refresh_camera()

func _on_camera_rotated(delta_angle: float) -> void:
	rotation += delta_angle
	_refresh_camera()

func add_muzzle_rise_kick(amount: float) -> void:
	var current_zoom_in: float = max(0.0, zoom.x - base_zoom)
	var scaled_amount: float = amount / pow((1.0 + current_zoom_in),2.0)
	_recoil_zoom += scaled_amount * recoil_zoom_step
	_refresh_camera()

func add_lateral_recoil(radians: float) -> void:
	rotation += radians
	_refresh_camera()

func set_ads_scope(mult: float) -> void:
	_ads_scope_mult = maxf(mult, 1.0)
	_refresh_camera()

func clear_ads_scope() -> void:
	_ads_scope_mult = 1.0
	_refresh_camera()

func _refresh_camera() -> void:
	position = Vector2.UP.rotated(rotation) * view_offset * _ads_scope_mult

	var z: float = max(0.1, base_zoom + _recoil_zoom)
	zoom = Vector2(z, z)

func set_muzzle_rise_recovery(value: float) -> void:
	recoil_zoom_return_speed = value

func get_scope_mult() -> float:
	return _ads_scope_mult
