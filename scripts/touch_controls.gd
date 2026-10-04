extends Control
## Mobile controls, multi-touch:
## - Left half: floating joystick (appears where the finger lands) -> move.
## - Right half: horizontal swipe -> turn (camera rotates with the player).
## Top-right corner toggles fullscreen.
## On desktop, mouse is emulated as touch index 0 (plus WASD / Q,E in player.gd).

@export var player_path: NodePath
@export var joystick_radius := 110.0
@export var dead_zone := 0.12
## Radians turned when swiping across the full screen width.
@export var turn_per_screen_width := 4.5

const FULLSCREEN_SIZE := Vector2(90, 90)

var _player: Node
var _joy_index := -1
var _joy_origin := Vector2.ZERO
var _joy_knob := Vector2.ZERO
var _look_index := -1
## Tracked manually: on Web, InputEventScreenDrag.relative is measured from the
## last drag of *any* finger, so it jumps wildly with two fingers down.
var _look_last := Vector2.ZERO


func _ready() -> void:
	_player = get_node(player_path)


func _process(_delta: float) -> void:
	queue_redraw() # FPS counter


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_release_joystick()
		_look_index = -1


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_drag(event)


func _on_touch(e: InputEventScreenTouch) -> void:
	var vp := get_viewport_rect().size
	if e.pressed:
		if _fullscreen_rect().has_point(e.position):
			_toggle_fullscreen()
		elif e.position.x < vp.x * 0.5:
			if _joy_index == -1:
				_joy_index = e.index
				_joy_origin = e.position
				_joy_knob = e.position
		elif _look_index == -1:
			_look_index = e.index
			_look_last = e.position
	else:
		if e.index == _joy_index:
			_release_joystick()
		elif e.index == _look_index:
			_look_index = -1


func _on_drag(e: InputEventScreenDrag) -> void:
	if e.index == _joy_index:
		var offset := (e.position - _joy_origin).limit_length(joystick_radius)
		_joy_knob = _joy_origin + offset
		var v := offset / joystick_radius
		var strength := inverse_lerp(dead_zone, 1.0, v.length())
		_player.move_input = v.normalized() * clampf(strength, 0.0, 1.0)
	elif e.index == _look_index:
		var dx := e.position.x - _look_last.x
		_look_last = e.position
		_player.turn(dx / get_viewport_rect().size.x * turn_per_screen_width)


func _release_joystick() -> void:
	_joy_index = -1
	if _player:
		_player.move_input = Vector2.ZERO


func _fullscreen_rect() -> Rect2:
	var vp := get_viewport_rect().size
	return Rect2(Vector2(vp.x - FULLSCREEN_SIZE.x, 0), FULLSCREEN_SIZE)


func _toggle_fullscreen() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _draw() -> void:
	var vp := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	var white := Color(1, 1, 1, 0.8)

	# Joystick
	if _joy_index != -1:
		draw_circle(_joy_origin, joystick_radius, Color(1, 1, 1, 0.08))
		draw_arc(_joy_origin, joystick_radius, 0, TAU, 48, Color(1, 1, 1, 0.35), 3.0)
		draw_circle(_joy_knob, 42.0, Color(1, 1, 1, 0.45))
	else:
		var hint := Vector2(180, vp.y - 180)
		draw_arc(hint, joystick_radius, 0, TAU, 48, Color(1, 1, 1, 0.15), 3.0)
		draw_string(font, hint + Vector2(-60, 6), "MOVE", HORIZONTAL_ALIGNMENT_CENTER, 120, 20, Color(1, 1, 1, 0.3))

	# Look zone hint
	if _look_index == -1:
		draw_string(font, Vector2(vp.x * 0.75 - 120, vp.y - 170), "<  SWIPE TO TURN  >", HORIZONTAL_ALIGNMENT_CENTER, 240, 20, Color(1, 1, 1, 0.3))

	# Fullscreen button (corner brackets)
	var r := _fullscreen_rect().grow(-28)
	var l := 12.0
	for c in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var sx := 1.0 if c.x == r.position.x else -1.0
		var sy := 1.0 if c.y == r.position.y else -1.0
		draw_line(c, c + Vector2(l * sx, 0), white, 3.0)
		draw_line(c, c + Vector2(0, l * sy), white, 3.0)

	draw_string(font, Vector2(16, 30), "%d FPS" % Engine.get_frames_per_second(), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, white)
