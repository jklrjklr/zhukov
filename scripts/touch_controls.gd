extends Control
## Mobile controls, multi-touch:
## - Left half: floating joystick (appears where the finger lands) -> move.
## - Right half: horizontal swipe -> turn (camera rotates with the player).
## - FIRE (hold; dragging it also turns), RELOAD, fire MODE, GRENADE, STIM.
## - ADS: tap toggles aim down sights; press and swipe up/down sets aim distance.
##   While aiming, any right-side swipe (and dragging FIRE) also moves aim distance
##   with its vertical motion.
## - INTERACT (hold) appears next to terminals, consoles, ammo boxes and pods.
## - STRATAGEM (left): opens the stratagem menu; enter the code with the D-pad or by
##   swiping on the right half (one swipe = one arrow). Tap again to cancel.
## - DIVE: lunge and drop prone. SWAP: primary <-> support weapon (when carrying one).
## On web, the top-right corner toggles fullscreen.
## Info (health, ammo, objectives...) is drawn by the HUD; this node only draws the
## controls and the aim overlay.
## Desktop: mouse is emulated as touch index 0 (plus WASD / Q,E, Space, R, B, F, Z/X,
## G grenade, H stim, hold V interact, Ctrl stratagems + arrow keys, C dive, T swap).

@export var player_path: NodePath
@export var joystick_radius := 110.0
@export var dead_zone := 0.12
## Radians turned when swiping across the full screen width.
@export var turn_per_screen_width := 4.5

const FULLSCREEN_SIZE := Vector2(90, 90)
const FIRE_RADIUS := 80.0
const SMALL_RADIUS := 42.0
const ADS_RADIUS := 50.0
const INTERACT_RADIUS := 52.0
## Meters of aim distance per full-screen-height vertical swipe.
const AIM_M_PER_SCREEN := 16.0
## Turn sensitivity while fully aimed.
const ADS_TURN_MULT := 0.5
## A press on ADS shorter/smaller than this is a tap (toggle).
const TAP_MS := 300
const TAP_PX := 14.0
const STRAT_RADIUS := 46.0
const DPAD_RADIUS := 50.0
const DPAD_GAP := 105.0
## Minimum swipe length for a stratagem arrow (px).
const SWIPE_MIN := 40.0

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
var _ads_index := -1
var _ads_last := Vector2.ZERO
var _ads_start := Vector2.ZERO
var _ads_press_ms := 0
var _ads_was_on := false
var _interact_index := -1
var _strat: Stratagems
var _swipe_index := -1
var _swipe_start := Vector2.ZERO


func _ready() -> void:
	_player = get_node(player_path)
	_weapon = _player.get_node("Firearm")


func _process(_delta: float) -> void:
	if _strat == null:
		_strat = get_tree().get_first_node_in_group("stratagems") as Stratagems
	_player.interacting = _interact_index != -1 or Input.is_physical_key_pressed(KEY_V)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_release_all()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k.pressed and not k.echo:
		match k.physical_keycode:
			KEY_G:
				_player.throw_grenade()
			KEY_H:
				_player.use_stim()
			KEY_C:
				_player.dive()
			KEY_T:
				_weapon.switch_weapon()
			KEY_CTRL:
				if _strat:
					_strat.toggle_menu()
			KEY_UP:
				if _strat: _strat.push(Stratagems.Dir.UP)
			KEY_DOWN:
				if _strat: _strat.push(Stratagems.Dir.DOWN)
			KEY_LEFT:
				if _strat: _strat.push(Stratagems.Dir.LEFT)
			KEY_RIGHT:
				if _strat: _strat.push(Stratagems.Dir.RIGHT)


func _input(event: InputEvent) -> void:
	if _player.dead:
		_release_all()
		return
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_drag(event)


func _on_touch(e: InputEventScreenTouch) -> void:
	var vp := get_viewport_rect().size
	var entering := _strat != null and _strat.entering
	if e.pressed:
		if OS.has_feature("web") and _fullscreen_rect().has_point(e.position):
			_toggle_fullscreen()
		elif _strat and e.position.distance_to(_strat_center()) < STRAT_RADIUS:
			_release_fire()
			_weapon.ads = false
			_strat.toggle_menu()
		elif entering and e.position.x >= vp.x * 0.5:
			var d := _dpad_at(e.position)
			if d >= 0:
				_strat.push(d)
			elif _swipe_index == -1:
				_swipe_index = e.index
				_swipe_start = e.position
		elif e.position.distance_to(_dive_center()) < SMALL_RADIUS:
			_player.dive()
		elif _weapon.has_support() and e.position.distance_to(_swap_center()) < SMALL_RADIUS:
			_weapon.switch_weapon()
		elif e.position.distance_to(_fire_center()) < FIRE_RADIUS and _fire_index == -1:
			_fire_index = e.index
			_fire_last = e.position
			_weapon.trigger = true
		elif e.position.distance_to(_ads_center()) < ADS_RADIUS and _ads_index == -1:
			_ads_index = e.index
			_ads_last = e.position
			_ads_start = e.position
			_ads_press_ms = Time.get_ticks_msec()
			_ads_was_on = _weapon.ads
			_weapon.ads = true
		elif _interact_visible() and e.position.distance_to(_interact_center()) < INTERACT_RADIUS:
			_interact_index = e.index
		elif e.position.distance_to(_reload_center()) < SMALL_RADIUS:
			_weapon.reload()
		elif e.position.distance_to(_mode_center()) < SMALL_RADIUS:
			_weapon.cycle_fire_mode()
		elif e.position.distance_to(_grenade_center()) < SMALL_RADIUS:
			_player.throw_grenade()
		elif e.position.distance_to(_stim_center()) < SMALL_RADIUS:
			_player.use_stim()
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
		elif e.index == _interact_index:
			_interact_index = -1
		elif e.index == _swipe_index:
			_swipe_index = -1
			var d := e.position - _swipe_start
			if _strat and d.length() >= SWIPE_MIN:
				if absf(d.x) > absf(d.y):
					_strat.push(Stratagems.Dir.RIGHT if d.x > 0 else Stratagems.Dir.LEFT)
				else:
					_strat.push(Stratagems.Dir.DOWN if d.y > 0 else Stratagems.Dir.UP)
		elif e.index == _ads_index:
			_ads_index = -1
			var tap := Time.get_ticks_msec() - _ads_press_ms < TAP_MS and e.position.distance_to(_ads_start) < TAP_PX
			if tap and _ads_was_on:
				_weapon.ads = false


func _on_drag(e: InputEventScreenDrag) -> void:
	if e.index == _joy_index:
		var offset := (e.position - _joy_origin).limit_length(joystick_radius)
		_joy_knob = _joy_origin + offset
		var v := offset / joystick_radius
		var strength := inverse_lerp(dead_zone, 1.0, v.length())
		_player.move_input = v.normalized() * clampf(strength, 0.0, 1.0)
	elif e.index == _look_index:
		_aim_drag(e.position - _look_last, _weapon.ads)
		_look_last = e.position
	elif e.index == _fire_index:
		_aim_drag(e.position - _fire_last, _weapon.ads)
		_fire_last = e.position
	elif e.index == _ads_index:
		_aim_drag(e.position - _ads_last, true)
		_ads_last = e.position


## Horizontal turns; vertical moves the aim circle (up = farther) when adjusting.
func _aim_drag(d: Vector2, adjust_distance: bool) -> void:
	var vp := get_viewport_rect().size
	var sens := lerpf(1.0, ADS_TURN_MULT, _weapon.ads_amount())
	_player.turn_look(d.x / vp.x * turn_per_screen_width * sens)
	if adjust_distance:
		_weapon.adjust_aim(-d.y / vp.y * AIM_M_PER_SCREEN)


func _release_all() -> void:
	_release_joystick()
	_release_fire()
	_look_index = -1
	_interact_index = -1
	_ads_index = -1


func _release_joystick() -> void:
	_joy_index = -1
	if _player:
		_player.move_input = Vector2.ZERO


func _release_fire() -> void:
	_fire_index = -1
	if _weapon:
		_weapon.trigger = false


func _interact_visible() -> bool:
	return _player.interact_target != null


func _strat_center() -> Vector2:
	return Vector2(90, 260)


func _dive_center() -> Vector2:
	var vp := get_viewport_rect().size
	return Vector2(vp.x - 52, vp.y - 52)


func _swap_center() -> Vector2:
	var vp := get_viewport_rect().size
	return Vector2(vp.x - 60, vp.y - 440)


func _dpad_center() -> Vector2:
	var vp := get_viewport_rect().size
	return Vector2(vp.x - 230, vp.y * 0.55)


## Which D-pad arrow is at p (-1 = none).
func _dpad_at(p: Vector2) -> int:
	var c := _dpad_center()
	var dirs := {Stratagems.Dir.UP: Vector2.UP, Stratagems.Dir.DOWN: Vector2.DOWN,
		Stratagems.Dir.LEFT: Vector2.LEFT, Stratagems.Dir.RIGHT: Vector2.RIGHT}
	for d in dirs:
		if p.distance_to(c + (dirs[d] as Vector2) * DPAD_GAP) < DPAD_RADIUS:
			return d
	return -1


func _fire_center() -> Vector2:
	var vp := get_viewport_rect().size
	return Vector2(vp.x - 170, vp.y - 170)


func _reload_center() -> Vector2:
	var vp := get_viewport_rect().size
	return Vector2(vp.x - 320, vp.y - 90)


func _ads_center() -> Vector2:
	var vp := get_viewport_rect().size
	return Vector2(vp.x - 330, vp.y - 250)


func _mode_center() -> Vector2:
	var vp := get_viewport_rect().size
	return Vector2(vp.x - 60, vp.y - 330)


func _grenade_center() -> Vector2:
	var vp := get_viewport_rect().size
	return Vector2(vp.x - 175, vp.y - 335)


func _stim_center() -> Vector2:
	var vp := get_viewport_rect().size
	return Vector2(vp.x - 460, vp.y - 90)


func _interact_center() -> Vector2:
	var vp := get_viewport_rect().size
	return Vector2(vp.x - 490, vp.y - 250)


func _fullscreen_rect() -> Rect2:
	var vp := get_viewport_rect().size
	return Rect2(Vector2(vp.x - FULLSCREEN_SIZE.x, 0), FULLSCREEN_SIZE)


func _toggle_fullscreen() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _draw() -> void:
	if _player.dead:
		return
	var vp := get_viewport_rect().size
	_draw_aim_overlay()

	# Joystick
	if _joy_index != -1:
		draw_circle(_joy_origin, joystick_radius, Color(0, 0, 0, 0.25))
		draw_arc(_joy_origin, joystick_radius, 0, TAU, 48, UiStyle.YELLOW_DIM, 3.0)
		draw_circle(_joy_knob, 40.0, Color(1, 0.9, 0.06, 0.4))
	else:
		var hint := Vector2(180, vp.y - 180)
		draw_arc(hint, joystick_radius, 0, TAU, 48, Color(1, 1, 1, 0.12), 3.0)
		UiStyle.text(self, hint + Vector2(-60, 6), "move", 18, Color(1, 1, 1, 0.25), HORIZONTAL_ALIGNMENT_CENTER, 120)

	# Stratagem menu toggle + D-pad while entering a code
	var entering := _strat != null and _strat.entering
	if _strat:
		_button(_strat_center(), STRAT_RADIUS, "STRAT", entering, 15)
	if entering:
		var c := _dpad_center()
		var dirs := [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
		for v in dirs:
			var bc: Vector2 = c + v * DPAD_GAP
			draw_circle(bc, DPAD_RADIUS, Color(0, 0, 0, 0.5))
			draw_arc(bc, DPAD_RADIUS, 0, TAU, 32, UiStyle.YELLOW, 2.5)
			_arrow(bc, v, 20.0, UiStyle.YELLOW)
		UiStyle.text(self, c + Vector2(-100, 8), "swipe or tap", 14, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, 200)
		return

	_button(_fire_center(), FIRE_RADIUS, "FIRE", _fire_index != -1, 24, UiStyle.RED)
	_button(_dive_center(), SMALL_RADIUS - 4, "DIVE", _player.is_diving(), 14)
	if _weapon.has_support():
		_button(_swap_center(), SMALL_RADIUS, "SWAP", _weapon.slot == 1, 14, UiStyle.GREEN)
	var w := _weapon
	var busy := w.state == Firearm.State.RELOADING or w.state == Firearm.State.CLEARING
	_button(_reload_center(), SMALL_RADIUS, "CLEAR" if w.jammed else "RELOAD", false, 14)
	if busy:
		draw_arc(_reload_center(), SMALL_RADIUS - 5, -PI / 2, -PI / 2 + TAU * w.state_progress(), 32, UiStyle.BLUE, 5.0)
	_button(_mode_center(), SMALL_RADIUS, w.fire_mode_name(), false, 14)
	_button(_grenade_center(), SMALL_RADIUS, "NADE %d" % _player.grenades, false, 14, Color.WHITE, _player.grenades == 0)
	_button(_stim_center(), SMALL_RADIUS, "STIM %d" % _player.stims, _player.is_healing(), 14, UiStyle.GREEN, _player.stims == 0)

	var ac := _ads_center()
	_button(ac, ADS_RADIUS, "ADS", w.ads, 18)
	if w.ads:
		UiStyle.text(self, ac + Vector2(-50, 22), "%d m" % roundi(w.aim_distance), 14, Color(0.05, 0.05, 0.05), HORIZONTAL_ALIGNMENT_CENTER, 100)
		UiStyle.text(self, ac + Vector2(-50, -ADS_RADIUS - 6), "^", 14, UiStyle.YELLOW_DIM, HORIZONTAL_ALIGNMENT_CENTER, 100)
		UiStyle.text(self, ac + Vector2(-50, ADS_RADIUS + 18), "v", 14, UiStyle.YELLOW_DIM, HORIZONTAL_ALIGNMENT_CENTER, 100)

	if _interact_visible():
		var ic := _interact_center()
		var it: Interactable = _player.interact_target
		_button(ic, INTERACT_RADIUS, "HOLD", _interact_index != -1, 18)
		draw_arc(ic, INTERACT_RADIUS + 6, -PI / 2, -PI / 2 + TAU * it.progress / it.hold_time, 40, UiStyle.YELLOW, 6.0)

	if OS.has_feature("web"):
		var r := _fullscreen_rect().grow(-30)
		var l := 10.0
		for c in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			var sx := 1.0 if c.x == r.position.x else -1.0
			var sy := 1.0 if c.y == r.position.y else -1.0
			draw_line(c, c + Vector2(l * sx, 0), UiStyle.TEXT_DIM, 3.0)
			draw_line(c, c + Vector2(0, l * sy), UiStyle.TEXT_DIM, 3.0)


## Filled arrow triangle pointing along v.
func _arrow(c: Vector2, v: Vector2, size: float, col: Color) -> void:
	var side := v.orthogonal()
	draw_colored_polygon(PackedVector2Array([c + v * size, c - v * size * 0.6 + side * size * 0.8,
		c - v * size * 0.6 - side * size * 0.8]), col)


## Round control: dark glass, accent ring, label; filled with the accent when active.
func _button(c: Vector2, r: float, label: String, active: bool, size: int, accent := UiStyle.YELLOW, empty := false) -> void:
	var ring := accent if not empty else Color(0.5, 0.5, 0.5)
	draw_circle(c, r, Color(ring.r, ring.g, ring.b, 0.55) if active else Color(0, 0, 0, 0.45))
	draw_arc(c, r, 0, TAU, 40, Color(ring.r, ring.g, ring.b, 0.8), 2.5)
	var tc := Color(0.05, 0.05, 0.05) if active else (Color(0.6, 0.6, 0.6) if empty else UiStyle.TEXT)
	UiStyle.text(self, c + Vector2(-r, size * 0.35), label, size, tc, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0)


## Hip: spread cone lines from the muzzle. ADS: aim circle + reticle where bullets land.
func _draw_aim_overlay() -> void:
	var o := _weapon.aim_overlay()
	if not o.show:
		return
	var xf := get_viewport().get_canvas_transform()
	var scale := xf.get_scale().x
	var muzzle: Vector2 = xf * (o.muzzle as Vector2)
	var fwd: Vector2 = xf.basis_xform(o.forward).normalized()
	var ads: float = o.ads
	var hip := 1.0 - ads
	if hip > 0.0:
		for s in [-1.0, 1.0]:
			var d := fwd.rotated(o.half_spread * s)
			draw_line(muzzle + d * 20.0 * scale, muzzle + d * 420.0 * scale, Color(1, 0.9, 0.3, 0.25 * hip), 1.5)
	if ads > 0.0:
		var c: Vector2 = xf * (o.center as Vector2)
		var r := maxf((o.radius as float) * scale, 2.0)
		var col := Color(1, 0.9, 0.3, 0.9 * ads)
		draw_line(muzzle + fwd * 20.0 * scale, c - fwd * (r + 4.0), Color(1, 0.9, 0.3, 0.15 * ads), 1.5)
		draw_arc(c, r, 0.0, TAU, 40, col, 2.0)
		draw_circle(c, 1.5, col)
		for i in 4:
			var t := fwd.rotated(i * PI / 2.0)
			draw_line(c + t * (r + 4.0), c + t * (r + 12.0), col, 2.0)
