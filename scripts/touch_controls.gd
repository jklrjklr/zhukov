extends Control
## Mobile controls, multi-touch:
## - Left half: floating joystick (appears where the finger lands) -> move.
## - Right half: horizontal swipe -> turn (camera rotates with the player).
## - FIRE button (hold; dragging it also turns), RELOAD and fire MODE buttons.
## Top-right corner toggles fullscreen.
## On desktop, mouse is emulated as touch index 0 (plus WASD / Q,E, Space, R, B).

@export var player_path: NodePath
@export var joystick_radius := 110.0
@export var dead_zone := 0.12
## Radians turned when swiping across the full screen width.
@export var turn_per_screen_width := 4.5

const FULLSCREEN_SIZE := Vector2(90, 90)
const FIRE_RADIUS := 80.0
const SMALL_RADIUS := 44.0

var _player: Node
var _weapon: Firearm
var _joy_index := -1
var _joy_origin := Vector2.ZERO
var _joy_knob := Vector2.ZERO
var _look_index := -1
## Tracked manually: on Web, InputEventScreenDrag.relative is measured from the
## last drag of *any* finger, so it jumps wildly with two fingers down.
var _look_last := Vector2.ZERO
var _fire_index := -1
var _fire_last := Vector2.ZERO


func _ready() -> void:
	_player = get_node(player_path)
	_weapon = _player.get_node("Firearm")


func _process(_delta: float) -> void:
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_release_joystick()
		_look_index = -1
		_release_fire()


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
		elif e.position.distance_to(_fire_center()) < FIRE_RADIUS and _fire_index == -1:
			_fire_index = e.index
			_fire_last = e.position
			_weapon.trigger = true
		elif e.position.distance_to(_reload_center()) < SMALL_RADIUS:
			_weapon.reload()
		elif e.position.distance_to(_mode_center()) < SMALL_RADIUS:
			_weapon.cycle_fire_mode()
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
		elif e.index == _fire_index:
			_release_fire()


func _on_drag(e: InputEventScreenDrag) -> void:
	if e.index == _joy_index:
		var offset := (e.position - _joy_origin).limit_length(joystick_radius)
		_joy_knob = _joy_origin + offset
		var v := offset / joystick_radius
		var strength := inverse_lerp(dead_zone, 1.0, v.length())
		_player.move_input = v.normalized() * clampf(strength, 0.0, 1.0)
	elif e.index == _look_index:
		_turn(e.position.x - _look_last.x)
		_look_last = e.position
	elif e.index == _fire_index:
		_turn(e.position.x - _fire_last.x)
		_fire_last = e.position


func _turn(dx: float) -> void:
	_player.turn(dx / get_viewport_rect().size.x * turn_per_screen_width * _weapon.stats.turn_multiplier())


func _release_joystick() -> void:
	_joy_index = -1
	if _player:
		_player.move_input = Vector2.ZERO


func _release_fire() -> void:
	_fire_index = -1
	if _weapon:
		_weapon.trigger = false


func _fire_center() -> Vector2:
	var vp := get_viewport_rect().size
	return Vector2(vp.x - 170, vp.y - 170)


func _reload_center() -> Vector2:
	var vp := get_viewport_rect().size
	return Vector2(vp.x - 320, vp.y - 90)


func _mode_center() -> Vector2:
	var vp := get_viewport_rect().size
	return Vector2(vp.x - 70, vp.y - 330)


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
	var faint := Color(1, 1, 1, 0.3)

	# Joystick
	if _joy_index != -1:
		draw_circle(_joy_origin, joystick_radius, Color(1, 1, 1, 0.08))
		draw_arc(_joy_origin, joystick_radius, 0, TAU, 48, Color(1, 1, 1, 0.35), 3.0)
		draw_circle(_joy_knob, 42.0, Color(1, 1, 1, 0.45))
	else:
		var hint := Vector2(180, vp.y - 180)
		draw_arc(hint, joystick_radius, 0, TAU, 48, Color(1, 1, 1, 0.15), 3.0)
		draw_string(font, hint + Vector2(-60, 6), "MOVE", HORIZONTAL_ALIGNMENT_CENTER, 120, 20, faint)

	# Look zone hint
	if _look_index == -1 and _fire_index == -1:
		draw_string(font, Vector2(vp.x * 0.75 - 160, vp.y * 0.35), "<  SWIPE TO TURN  >", HORIZONTAL_ALIGNMENT_CENTER, 240, 20, faint)

	# Fire button
	var fc := _fire_center()
	draw_circle(fc, FIRE_RADIUS, Color(1, 0.3, 0.2, 0.28 if _fire_index != -1 else 0.14))
	draw_arc(fc, FIRE_RADIUS, 0, TAU, 48, Color(1, 0.4, 0.3, 0.6), 3.0)
	draw_string(font, fc + Vector2(-60, 7), "FIRE", HORIZONTAL_ALIGNMENT_CENTER, 120, 22, white)

	# Reload button with progress ring
	var rc := _reload_center()
	draw_circle(rc, SMALL_RADIUS, Color(1, 1, 1, 0.1))
	draw_arc(rc, SMALL_RADIUS, 0, TAU, 32, faint, 2.0)
	var busy := _weapon.state == Firearm.State.RELOADING or _weapon.state == Firearm.State.CLEARING
	if busy:
		draw_arc(rc, SMALL_RADIUS - 4, -PI / 2, -PI / 2 + TAU * _weapon.state_progress(), 32, Color(0.5, 0.9, 1.0, 0.9), 5.0)
	draw_string(font, rc + Vector2(-40, 6), "CLEAR" if _weapon.jammed else "R", HORIZONTAL_ALIGNMENT_CENTER, 80, 18, white)

	# Fire mode button
	var mc := _mode_center()
	draw_circle(mc, SMALL_RADIUS, Color(1, 1, 1, 0.1))
	draw_arc(mc, SMALL_RADIUS, 0, TAU, 32, faint, 2.0)
	draw_string(font, mc + Vector2(-40, 6), _weapon.fire_mode_name(), HORIZONTAL_ALIGNMENT_CENTER, 80, 16, white)

	_draw_ammo(font, Vector2(vp.x - 330, vp.y - 290))

	# Fullscreen button (corner brackets)
	var r := _fullscreen_rect().grow(-28)
	var l := 12.0
	for c in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var sx := 1.0 if c.x == r.position.x else -1.0
		var sy := 1.0 if c.y == r.position.y else -1.0
		draw_line(c, c + Vector2(l * sx, 0), white, 3.0)
		draw_line(c, c + Vector2(0, l * sy), white, 3.0)

	draw_string(font, Vector2(16, 30), "%d FPS" % Engine.get_frames_per_second(), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, white)


## Weapon name, rounds (+1 = chambered), spare mags as fill bars, status line.
func _draw_ammo(font: Font, at: Vector2) -> void:
	var w := _weapon
	var white := Color(1, 1, 1, 0.85)
	draw_string(font, at, "%s  %s" % [w.stats.display_name, w.stats.caliber], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.6))
	var rounds := "%d" % w.mag + ("+1" if w.chambered else "")
	draw_string(font, at + Vector2(0, 30), rounds, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, white)
	for i in w.mags.size():
		var x := at.x + 90 + i * 12
		var h := 26.0
		var fill := h * w.mags[i] / float(w.stats.mag_size)
		draw_rect(Rect2(x, at.y + 6, 8, h), Color(1, 1, 1, 0.15))
		draw_rect(Rect2(x, at.y + 6 + h - fill, 8, fill), Color(1, 1, 1, 0.7))

	var status := ""
	var col := Color(1, 0.8, 0.3)
	if w.jammed:
		status = "JAMMED - CLEAR (R)"
		col = Color(1, 0.4, 0.3)
	elif w.state == Firearm.State.RELOADING:
		status = "RELOADING"
	elif w.state == Firearm.State.CLEARING:
		status = "CLEARING"
	elif w.state == Firearm.State.DRAWING:
		status = "READYING"
	elif w.blocked > 0.0:
		status = "BLOCKED"
	elif w.dry_flash > 0.0:
		status = "EMPTY - RELOAD" if not w.mags.is_empty() else "OUT OF AMMO"
		col = Color(1, 0.4, 0.3)
	if status != "":
		draw_string(font, at + Vector2(0, 56), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)
