extends Node

const JOYSTICK_RADIUS: float = 80.0
const SWIPE_SENSITIVITY: float = 0.02

signal camera_rotated(delta_angle: float)

var _joystick_touch_index: int = -1
var _joystick_origin: Vector2 = Vector2.ZERO
var _joystick_current: Vector2 = Vector2.ZERO

var _swipe_touch_index: int = -1
var _swipe_last_pos: Vector2 = Vector2.ZERO

var _fire_touch_index: int = -1
var _fire_swipe_last_pos: Vector2 = Vector2.ZERO
var fire_held: bool = false
var fire_just_pressed: bool = false

var _reload_touch_index: int = -1
var _reload_swipe_last_pos: Vector2 = Vector2.ZERO
var reload_just_pressed: bool = false

var _fire_mode_touch_index: int = -1
var fire_mode_just_pressed: bool = false

var _screen_mid_x: float = 0.0

var fire_button_rect: Rect2 = Rect2()
var reload_button_rect: Rect2 = Rect2()
var fire_mode_button_rect: Rect2 = Rect2()

func _ready() -> void:
	_screen_mid_x = DisplayServer.window_get_size().x * 0.5

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		_screen_mid_x = DisplayServer.window_get_size().x * 0.5

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)

func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		var is_left: bool = event.position.x < _screen_mid_x
		if is_left:
			if _joystick_touch_index == -1:
				_joystick_touch_index = event.index
				_joystick_origin = event.position
				_joystick_current = event.position
		else:
			if fire_button_rect.has_point(event.position) and _fire_touch_index == -1:
				_fire_touch_index = event.index
				fire_held = true
				fire_just_pressed = true
				_fire_swipe_last_pos = event.position
			elif reload_button_rect.has_point(event.position) and _reload_touch_index == -1:
				_reload_touch_index = event.index
				reload_just_pressed = true
				_reload_swipe_last_pos = event.position
			elif fire_mode_button_rect.has_point(event.position) and _fire_mode_touch_index == -1:
				_fire_mode_touch_index = event.index
				fire_mode_just_pressed = true
			elif _swipe_touch_index == -1:
				_swipe_touch_index = event.index
				_swipe_last_pos = event.position
	else:
		if event.index == _joystick_touch_index:
			_joystick_touch_index = -1
			_joystick_origin = Vector2.ZERO
			_joystick_current = Vector2.ZERO
		elif event.index == _fire_touch_index:
			_fire_touch_index = -1
			fire_held = false
		elif event.index == _reload_touch_index:
			_reload_touch_index = -1
		elif event.index == _fire_mode_touch_index:
			_fire_mode_touch_index = -1
		elif event.index == _swipe_touch_index:
			_swipe_touch_index = -1

func _handle_drag(event: InputEventScreenDrag) -> void:
	if event.index == _joystick_touch_index:
		_joystick_current = event.position
	elif event.index == _swipe_touch_index:
		_apply_cam_swipe(event, _swipe_last_pos)
		_swipe_last_pos = event.position
	elif event.index == _fire_touch_index:
		_apply_cam_swipe(event, _fire_swipe_last_pos)
		_fire_swipe_last_pos = event.position
	elif event.index == _reload_touch_index:
		_apply_cam_swipe(event, _reload_swipe_last_pos)
		_reload_swipe_last_pos = event.position

func _apply_cam_swipe(event: InputEventScreenDrag, last_pos: Vector2) -> void:
	var dx: float = event.position.x - last_pos.x
	var swipe_speed: float = absf(event.velocity.x)
	var accel_mult: float = clampf(swipe_speed / 500000.0, 0.001, 0.2)
	camera_rotated.emit(dx * SWIPE_SENSITIVITY * accel_mult * Engine.get_frames_per_second())

func _physics_process(_delta: float) -> void:
	pass

func get_move_vector() -> Vector2:
	if _joystick_touch_index == -1:
		return Vector2.ZERO
	var raw := _joystick_current - _joystick_origin
	return raw.limit_length(JOYSTICK_RADIUS) / JOYSTICK_RADIUS

func get_camera_angular_velocity() -> float:
	return 0.0

func add_camera_impulse(radians: float) -> void:
	camera_rotated.emit(radians)
