class_name PlayerCamera
extends Camera2D

@export var view_offset: float = 250.0
@export var base_zoom: float = 1.0
@export var recoil_zoom_step: float = 0.02
@export var recoil_zoom_return_speed: float = 0.5
# How aggressively accumulated zoom damps each new kick (soft cap mechanism 1)
@export var kick_falloff: float = 4.0
# How much recovery speed increases per unit of accumulated zoom (soft cap mechanism 2)
@export var recovery_scale: float = 3.0

var _recoil_zoom: float = 0.0
var _scope_mult:  float = 1.0

func _ready() -> void:
	var input := get_node_or_null("/root/TouchInputHandler")
	if input != null:
		input.camera_rotated.connect(_on_camera_rotated)
	_refresh_camera()

func _physics_process(delta: float) -> void:
	# Recovery speed increases with accumulated zoom — contributes to soft cap
	var boost := 1.0 + _recoil_zoom * recovery_scale
	_recoil_zoom = move_toward(_recoil_zoom, 0.0, recoil_zoom_return_speed * boost * delta)
	_refresh_camera()

func _on_camera_rotated(delta_angle: float) -> void:
	rotation += delta_angle
	_refresh_camera()

func add_muzzle_rise_kick(amount: float) -> void:
	# Each new kick is dampened by how much zoom has already accumulated
	var dampen := 1.0 / (1.0 + _recoil_zoom * kick_falloff)
	_recoil_zoom += amount * recoil_zoom_step * dampen
	_refresh_camera()

func add_lateral_recoil(radians: float) -> void:
	rotation += radians
	_refresh_camera()

func set_ads_scope(mult: float) -> void:
	_scope_mult = maxf(mult, 1.0)
	_refresh_camera()

func clear_ads_scope() -> void:
	_scope_mult = 1.0
	_refresh_camera()

func _refresh_camera() -> void:
	var z: float = max(0.1, base_zoom + _recoil_zoom) / _scope_mult
	zoom = Vector2(z, z)
	# Pull the camera toward the player as recoil zoom grows so the player stays
	# at the same pixel position on screen.
	# Proof: screen_offset = (view_offset * base_zoom / (base_zoom + _recoil_zoom))
	#                       * (base_zoom + _recoil_zoom) = view_offset * base_zoom (constant).
	# ADS scope zoom (_scope_mult) is excluded — it should not affect the offset.
	var offset_factor := base_zoom / maxf(base_zoom, base_zoom + _recoil_zoom)
	position = Vector2.UP.rotated(rotation) * view_offset * offset_factor

func set_muzzle_rise_recovery(value: float) -> void:
	recoil_zoom_return_speed = value
