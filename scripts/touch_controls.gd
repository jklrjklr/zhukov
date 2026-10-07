extends Control
## Mobile controls, multi-touch:
## - Left half: floating joystick (appears where the finger lands) -> move.
## - Right half: horizontal swipe -> turn (camera rotates with the player).
## - DIVE button (bottom right): dodge in the stick direction.
## On web, the top-right corner toggles fullscreen.
## Desktop: mouse is emulated as touch index 0, plus WASD move, Left/Right turn, Shift sprint,
## Space / C dive.

@export var player_path: NodePath
@export var joystick_radius := 110.0
@export var dead_zone := 0.12
## Radians turned when swiping across the full screen width.
@export var turn_per_screen_width := 4.5

const FULLSCREEN_SIZE := Vector2(90, 90)
const DIVE_RADIUS := 64.0
const HINT_COL := Color(1, 1, 1, 0.12)
const RING_COL := Color(1.0, 0.9, 0.06, 0.35)
const KNOB_COL := Color(1, 0.9, 0.06, 0.4)

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
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_release_all()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_drag(event)


func _on_touch(e: InputEventScreenTouch) -> void:
	var vp := get_viewport_rect().size
	if e.pressed:
		if OS.has_feature("web") and _fullscreen_rect().has_point(e.position):
			_toggle_fullscreen()
		elif e.position.distance_to(_dive_center()) < DIVE_RADIUS:
			_player.dive()
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
		var d := e.position - _look_last
		_player.turn_look(d.x / get_viewport_rect().size.x * turn_per_screen_width)
		_look_last = e.position


func _release_all() -> void:
	_release_joystick()
	_look_index = -1


func _release_joystick() -> void:
	_joy_index = -1
	if _player:
		_player.move_input = Vector2.ZERO


func _dive_center() -> Vector2:
	var vp := get_viewport_rect().size
	return Vector2(vp.x - 150, vp.y - 140)


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
	if _joy_index != -1:
		draw_circle(_joy_origin, joystick_radius, Color(0, 0, 0, 0.25))
		draw_arc(_joy_origin, joystick_radius, 0, TAU, 48, RING_COL, 3.0)
		draw_circle(_joy_knob, 40.0, KNOB_COL)
	else:
		var hint := Vector2(180, vp.y - 180)
		draw_arc(hint, joystick_radius, 0, TAU, 48, HINT_COL, 3.0)
		draw_string(ThemeDB.fallback_font, hint + Vector2(-60, 6), "MOVE", HORIZONTAL_ALIGNMENT_CENTER, 120, 18, Color(1, 1, 1, 0.25))

	var dc := _dive_center()
	var busy: bool = _player.is_diving()
	draw_circle(dc, DIVE_RADIUS, Color(1, 0.9, 0.06, 0.45) if busy else Color(0, 0, 0, 0.35))
	draw_arc(dc, DIVE_RADIUS, 0, TAU, 48, RING_COL, 3.0)
	draw_string(ThemeDB.fallback_font, dc + Vector2(-DIVE_RADIUS, 7), "DIVE", HORIZONTAL_ALIGNMENT_CENTER, DIVE_RADIUS * 2.0, 20, Color(1, 1, 1, 0.7))

	if OS.has_feature("web"):
		var r := _fullscreen_rect().grow(-30)
		var l := 10.0
		for c in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			var sx := 1.0 if c.x == r.position.x else -1.0
			var sy := 1.0 if c.y == r.position.y else -1.0
			draw_line(c, c + Vector2(l * sx, 0), Color(1, 1, 1, 0.5), 3.0)
			draw_line(c, c + Vector2(0, l * sy), Color(1, 1, 1, 0.5), 3.0)
