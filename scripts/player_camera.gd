class_name PlayerCamera
extends Node2D
## Child of the player's CameraRig (which the player counter-rotates to look_angle).
## Not a Camera2D: PixelView reads this node's global transform and `zoom` to build the
## low-res buffer's canvas transform itself (so it can snap to whole pixels and hand the
## sub-pixel remainder to the upscale). Sits ahead of the player so more is visible in the
## look direction; eases toward `target_offset` / `target_zoom` and adds decaying shake.

## px ahead of the player (screen-up) at rest.
@export var look_ahead := 175.0
## Higher = snappier offset / zoom changes.
@export var ease_rate := 8.0

## Extra offset (rig frame, px) and zoom multiplier other systems can set.
var target_offset := Vector2.ZERO
var target_zoom := 1.0
## Buffer pixels per world px (read by PixelView).
var zoom := Vis.CAM_ZOOM
var _offset := Vector2.ZERO
var _zoom := 1.0
var _shake := 0.0


func _ready() -> void:
	add_to_group("view_camera")
	_offset = Vector2(0, -look_ahead)
	_apply(Vector2.ZERO)


## Kick the view by `amount` world px (decays quickly).
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
	zoom = Vis.CAM_ZOOM * _zoom
