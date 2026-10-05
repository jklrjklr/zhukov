extends Control
## Mobile controls, multi-touch:
## - Left half: floating joystick (appears where the finger lands) -> move.
## - Right half: horizontal swipe -> turn (camera rotates with the player).
## - FIRE (hold; dragging it also turns), RELOAD, fire MODE, GRENADE, STIM.
## - ADS: tap toggles aim down sights; press and swipe up/down sets aim distance.
##   While aiming, any right-side swipe (and dragging FIRE) also moves aim distance
##   with its vertical motion.
## - INTERACT (hold) appears next to terminals, consoles, ammo boxes and pods.
## - STRATAGEM CARDS (bottom centre, drawn by the HUD, hit-tested here): tap a card = aim mode
##   (drag on the right half to move the landing point, camera follows, release or THROW
##   throws, CANCEL exits); press a card and swipe out of it = quick throw 12 m in the swipe
##   direction (the code is auto-typed first). Locked / empty cards give the strat_error
##   sound and the reason banner. The aim overlay is drawn by StratMenu (scripts/ui/strat_menu.gd).
## - DIVE: lunge and drop prone. SWAP: primary <-> support weapon (when carrying one).
## On web, the top-right corner toggles fullscreen.
## Info (health, ammo, objectives...) is drawn by the HUD; this node only draws the
## controls and the aim overlay.
## Desktop: mouse is emulated as touch index 0 (plus WASD / Left,Right turn, Space, R, B, F,
## Z/X, G grenade, H stim, hold V interact, C dive, T swap). Stratagems: hold Q (or middle
## mouse) = radial quick throw, swipe the mouse toward one and release; tap Q = menu, then
## click one (or keys 1-5 directly; the cards also work with the mouse) = aim mode with the mouse as landing point, left click
## throws, right click / Q cancels.

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
## Press on a stratagem card held this long (ms) opens the radial (keyboard Q / mouse only).
const RADIAL_HOLD_MS := 150
## A radial released in the dead-zone within this many ms (without moving) counts as a tap.
const RADIAL_TAP_MS := 350
## A card press released this far (px) from where it started, or outside the card, is a swipe.
const SWIPE_PX := 36.0
## Landing point px per finger px while dragging in aim mode.
const AIM_DRAG_GAIN := 1.3

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
var _menu: StratMenu
## Stratagem card press (touch index, -1 none) before it is a tap or a swipe.
var _card_index := -1
var _card_i := -1
var _card_pos := Vector2.ZERO
var _card_cur := Vector2.ZERO
## Radial source: -1 none, -2 keyboard / mouse, otherwise the touch index; pointer origin.
var _radial_src := -1
var _radial_origin := Vector2.ZERO
var _radial_ms := 0
var _radial_moved := false
var _radial_btn := ""
var _q_down := false
var _q_ms := 0
var _q_consumed := false
var _menu_by_key := false
var _aim_index := -1
var _aim_last := Vector2.ZERO
var _aim_moved := 0.0


func _ready() -> void:
	_player = get_node(player_path)
	_weapon = _player.get_node("Firearm")
	_menu = StratMenu.new()
	_menu.name = "StratMenu"
	get_parent().add_child.call_deferred(_menu)


func _process(_delta: float) -> void:
	if _strat == null:
		_strat = get_tree().get_first_node_in_group("stratagems") as Stratagems
	_player.interacting = _interact_index != -1 or Input.is_physical_key_pressed(KEY_V)
	_update_stratagem_input()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_release_all()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k.physical_keycode == KEY_Q:
		_q_key(k)
		return
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
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				if _strat:
					_strat.select_index(int(k.physical_keycode - KEY_1), true)


func _input(event: InputEvent) -> void:
	if _player.dead:
		_release_all()
		return
	if event is InputEventMouseButton and _strat:
		_on_mouse_button(event)
	elif event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_drag(event)


func _on_touch(e: InputEventScreenTouch) -> void:
	var vp := get_viewport_rect().size
	if e.pressed:
		if OS.has_feature("web") and _fullscreen_rect().has_point(e.position):
			_toggle_fullscreen()
		elif _strat and _card_press(e):
			pass
		elif e.position.distance_to(_dive_center()) < SMALL_RADIUS:
			_player.dive()
		elif _strat and _strat.ui == Stratagems.Ui.AIM and _aim_touch(e):
			pass
		elif _strat and _strat.ui == Stratagems.Ui.MENU and _menu_touch(e):
			pass
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
		elif e.index == _card_index:
			_card_release(e.position)
		elif e.index == _aim_index:
			_aim_index = -1
			if _aim_moved > 8.0 and _strat and _strat.ui == Stratagems.Ui.AIM:
				_strat.aim_throw()
		elif e.index == _ads_index:
			_ads_index = -1
			var tap := Time.get_ticks_msec() - _ads_press_ms < TAP_MS and e.position.distance_to(_ads_start) < TAP_PX
			if tap and _ads_was_on:
				_weapon.ads = false


func _on_drag(e: InputEventScreenDrag) -> void:
	if e.index == _card_index:
		_card_cur = e.position
	elif e.index == _aim_index:
		if _strat and _strat.ui == Stratagems.Ui.AIM:
			var d := e.position - _aim_last
			_aim_moved += d.length()
			var w := get_viewport().get_canvas_transform().affine_inverse().basis_xform(d)
			_strat.aim_move(w * AIM_DRAG_GAIN)
		_aim_last = e.position
	elif e.index == _joy_index:
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


## Touch in aim mode. Consumes THROW / CANCEL, the mouse click (keyboard aim) and the
## right half of the screen (drag = move the landing point).
func _aim_touch(e: InputEventScreenTouch) -> bool:
	var vp := get_viewport_rect().size
	if _strat.aim_mouse:
		if e.index == 0:
			_strat.aim_throw()
			return true
		return false
	if e.position.distance_to(StratMenu.throw_center(vp)) < StratMenu.THROW_R:
		_strat.aim_throw()
		return true
	if e.position.distance_to(StratMenu.cancel_center(vp)) < StratMenu.CANCEL_R:
		_strat.cancel()
		return true
	if e.position.x >= vp.x * 0.5:
		if _aim_index == -1:
			_aim_index = e.index
			_aim_last = e.position
			_aim_moved = 0.0
		return true
	return false


## Touch on the list menu: a row starts aim mode, outside (right half) closes it.
func _menu_touch(e: InputEventScreenTouch) -> bool:
	var vp := get_viewport_rect().size
	var n := _strat.equipped.size()
	var i := StratMenu.row_at(vp, n, e.position)
	if i >= 0:
		_strat.select_aim(_strat.equipped[i], _menu_by_key)
		return true
	if StratMenu.close_rect(vp, n).has_point(e.position):
		_strat.cancel()
		return true
	if StratMenu.list_rect(vp, n).has_point(e.position):
		return true
	if e.position.x >= vp.x * 0.5:
		_strat.cancel()
		return true
	return false


## Press on a stratagem card. Unusable ones refuse right away (sound + reason banner).
func _card_press(e: InputEventScreenTouch) -> bool:
	var i := StratMenu.card_at(get_viewport_rect().size, _strat.equipped.size(), e.position)
	if i < 0:
		return false
	_release_fire()
	_weapon.ads = false
	var id: String = _strat.equipped[i]
	if _strat.locked:
		_strat.select_aim(id) # refuses with the reason
		return true
	if _card_index == -1:
		_card_index = e.index
		_card_i = i
		_card_pos = e.position
		_card_cur = e.position
		var why := _strat.pick_error(id)
		if why != "":
			_strat.select_aim(id) # refuses: strat_error + reason banner
			_card_index = -1
	return true


## Released: outside the card / far from the press = quick throw in the swipe direction,
## otherwise a tap = aim mode (tap the card of the stratagem being aimed = cancel).
func _card_release(pos: Vector2) -> void:
	var i := _card_i
	_card_index = -1
	_card_i = -1
	if _strat == null or i < 0 or i >= _strat.equipped.size():
		return
	var id: String = _strat.equipped[i]
	var real := get_viewport_rect().size
	var swipe := pos - _card_pos
	var out := not StratMenu.card_rect(real, _strat.equipped.size(), i).has_point(pos)
	if swipe.length() >= SWIPE_PX or (out and swipe.length() > TAP_PX):
		var dir := get_viewport().get_canvas_transform().affine_inverse().basis_xform(swipe).normalized()
		_strat.select_quick(id, dir)
	elif _strat.ui == Stratagems.Ui.AIM and _strat.aim_id == id:
		_strat.cancel()
	else:
		_strat.select_aim(id)


func _begin_radial(src: int, pos: Vector2) -> void:
	if _strat == null:
		return
	var c := StratMenu.clamp_center(pos, get_viewport_rect().size)
	_strat.open_radial(c, c)
	if _strat.ui != Stratagems.Ui.RADIAL:
		return
	_radial_src = src
	_radial_origin = pos
	_radial_ms = Time.get_ticks_msec()
	_radial_moved = false


func _update_radial(pos: Vector2) -> void:
	if pos.distance_to(_radial_origin) > TAP_PX:
		_radial_moved = true
	_strat.radial_pointer = _strat.radial_center + (pos - _radial_origin)


## Keyboard / mouse radial released: toward a stratagem = quick throw; centre = cancel.
func _end_radial() -> void:
	var src := _radial_src
	_radial_src = -1
	_radial_btn = ""
	if _strat.ui != Stratagems.Ui.RADIAL:
		return
	var hover := StratMenu.radial_hover(_strat.radial_center, _strat.radial_pointer, _strat.equipped.size())
	if hover >= 0:
		_strat.select_quick(_strat.equipped[hover])
	elif src >= 0 and not _radial_moved and Time.get_ticks_msec() - _radial_ms < RADIAL_TAP_MS:
		_strat.open_menu()
		_menu_by_key = false
	else:
		_strat.cancel()


## Per frame: the keyboard / mouse radial follows the mouse.
func _update_stratagem_input() -> void:
	if _strat == null:
		return
	if _player.dead and _strat.ui != Stratagems.Ui.NONE:
		_strat.cancel(false)
	var now := Time.get_ticks_msec()
	if _q_down and _radial_src == -1 and not _q_consumed and now - _q_ms >= RADIAL_HOLD_MS \
			and _strat.ui == Stratagems.Ui.NONE:
		_begin_radial(-2, get_viewport().get_mouse_position())
		_radial_btn = "q"
	if _radial_src == -2:
		_update_radial(get_viewport().get_mouse_position())


## Q: hold = radial toward the mouse, tap = menu (Q again closes the menu / aim mode).
func _q_key(k: InputEventKey) -> void:
	if _strat == null:
		return
	if k.pressed and not k.echo:
		_q_down = true
		_q_ms = Time.get_ticks_msec()
		_q_consumed = false
		if _strat.ui == Stratagems.Ui.MENU or _strat.ui == Stratagems.Ui.AIM:
			_strat.cancel()
			_q_consumed = true
	elif not k.pressed:
		_q_down = false
		if _radial_btn == "q" and _radial_src == -2:
			_end_radial()
		elif not _q_consumed:
			_strat.open_menu()
			_menu_by_key = true
		_q_consumed = false


## Desktop: middle mouse = radial (like Q), right click cancels any stratagem UI.
func _on_mouse_button(e: InputEventMouseButton) -> void:
	if e.button_index == MOUSE_BUTTON_RIGHT and e.pressed:
		if _strat.ui != Stratagems.Ui.NONE:
			_strat.cancel()
			_radial_src = -1
	elif e.button_index == MOUSE_BUTTON_MIDDLE:
		if e.pressed and _strat.ui == Stratagems.Ui.NONE:
			_begin_radial(-2, e.position)
			_radial_btn = "mid"
		elif not e.pressed and _radial_btn == "mid":
			_end_radial()


func _release_all() -> void:
	if _strat and _strat.ui != Stratagems.Ui.NONE:
		_strat.cancel(false)
	_radial_src = -1
	_card_index = -1
	_aim_index = -1
	_q_down = false
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


func _dive_center() -> Vector2:
	var vp := get_viewport_rect().size
	return Vector2(vp.x - 52, vp.y - 52)


func _swap_center() -> Vector2:
	var vp := get_viewport_rect().size
	return Vector2(vp.x - 60, vp.y - 440)


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

	_draw_card_press()
	if _strat != null and _strat.ui == Stratagems.Ui.AIM: # THROW / CANCEL are drawn by StratMenu
		_button(_dive_center(), SMALL_RADIUS - 4, "DIVE", _player.is_diving(), 14)
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


## Pressed stratagem card: highlight and, once the finger leaves it, the swipe direction.
func _draw_card_press() -> void:
	if _strat == null or _card_index == -1 or _card_i < 0 or _card_i >= _strat.equipped.size():
		return
	var id: String = _strat.equipped[_card_i]
	var col: Color = Stratagems.DEFS[id].color
	var r := StratMenu.card_rect(get_viewport_rect().size, _strat.equipped.size(), _card_i)
	draw_rect(r, Color(col, 0.3))
	var d := _card_cur - _card_pos
	if d.length() > TAP_PX:
		draw_line(_card_pos, _card_cur, Color(col, 0.8), 4.0)
		UiIcons.arrow(self, _card_cur + d.normalized() * 14.0, d.normalized(), 14.0, col)


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
	if not o.show or (_strat != null and _strat.ui == Stratagems.Ui.AIM):
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
