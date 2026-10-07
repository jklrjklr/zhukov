class_name PlayerCamera
extends Camera2D
## Child of the player's CameraRig (which the player counter-rotates to look_angle).
## Sits ahead of the player so more is visible in the look direction; eases toward
## `target_offset` / `target_zoom` (relative to the base) and adds decaying shake.

## px ahead of the player (screen-up) at rest.
@export var look_ahead := 280.0
## Higher = snappier offset / zoom changes.
@export var ease_rate := 8.0

## Extra offset (rig frame, px) and zoom multiplier other systems can set.
var target_offset := Vector2.ZERO
var target_zoom := 1.0
var _offset := Vector2.ZERO
var _zoom := 1.0
var _shake := 0.0


func _ready() -> void:
	ignore_rotation = false
	_offset = Vector2(0, -look_ahead)
	_apply(Vector2.ZERO)


## Kick the view by `amount` px (decays quickly).
func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _process(delta: float) -> void:
	var k := minf(1.0, delta * ease_rate)
	_offset = _offset.lerp(Vector2(0, -look_ahead) + target_offset, k)
	_zoom = lerpf(_zoom, target_zoom, k)
	_shake = move_toward(_shake, 0.0, delta * maxf(_shake * 6.0, 4.0))
	var jitter := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake if _shake > 0.0 else Vector2.ZERO
	_apply(jitter)


func _apply(jitter: Vector2) -> void:
	position = _offset + jitter
	zoom = Vector2.ONE * Vis.CAM_ZOOM * _zoom
