class_name Firearm
extends Node2D
## Held firearm: fire control, ammo, reload, jams, recoil and camera kick.
## Child of Player, origin at the pistol grip, muzzle toward -Y.

const PX_PER_M := 60.0
## px the camera is pushed back at full vertical recoil stack.
const CAM_PUSH := 70.0
## Extra zoom at full vertical recoil stack.
const CAM_ZOOM := 0.08
## Max px the weapon is pulled back when the muzzle is inside a wall.
const MAX_PULL := 25.0

enum State { DRAWING, READY, RELOADING, CLEARING }

@export var stats: FirearmStats

## Held by TouchControls (Space on desktop).
var trigger := false
var fire_mode_index := 0
var mag := 0
var chambered := false
## Spare mags in pouch, rounds each. Partial mags are kept on tactical reload.
var mags: Array[int] = []
var state := State.DRAWING
var jammed := false
## px the muzzle is inside geometry (0 = clear).
var blocked := 0.0
## Vertical recoil stack, 0..1.
var recoil_stack := 0.0
## >0 shows "EMPTY" after a dry trigger pull.
var dry_flash := 0.0

var _state_left := 0.0
var _state_total := 1.0
var _cooldown := 0.0
var _trigger_was := false
var _burst_left := 0
var _since_shot := 99.0
var _roll_back := 0.0
var _kick := 0.0
var _tilt := 0.0
var _flash := 0.0
var _shake := Vector2.ZERO
var _player: CharacterBody2D
var _camera: Camera2D
var _cam_base := Vector2.ZERO
var _projectiles: Node


func _ready() -> void:
	_player = get_parent()
	_camera = _player.get_node_or_null("Camera2D")
	if _camera:
		_cam_base = _camera.position
	_projectiles = get_tree().get_first_node_in_group("projectiles")
	if stats.closed_bolt:
		mag = stats.mag_size - 1
		chambered = true
	else:
		mag = stats.mag_size
	for i in stats.spare_mags:
		mags.append(stats.mag_size)
	fire_mode_index = stats.fire_modes.size() - 1 # start on the most automatic mode
	_set_state(State.DRAWING, stats.swap_time())


func fire_mode() -> int:
	return stats.fire_modes[fire_mode_index]


func fire_mode_name() -> String:
	return ["SEMI", "BURST", "AUTO"][fire_mode()]


func cycle_fire_mode() -> void:
	fire_mode_index = (fire_mode_index + 1) % stats.fire_modes.size()


func rounds_loaded() -> int:
	return mag + int(chambered)


func state_progress() -> float:
	return 1.0 - _state_left / _state_total


func reload() -> void:
	if state != State.READY:
		return
	if jammed:
		_set_state(State.CLEARING, stats.jam_clear_time)
		return
	if mags.is_empty():
		return
	if mag >= stats.mag_size:
		return
	var empty := not _has_round()
	_set_state(State.RELOADING, stats.reload_time_empty if empty else stats.reload_time_tactical)


func current_spread_deg() -> float:
	var move := clampf(_player.get_real_velocity().length() / _player.move_speed, 0.0, 1.0)
	return stats.bullet_spread + stats.moving_spread * move + stats.recoil_spread * recoil_stack


func muzzle_local() -> Vector2:
	return Vector2(0, stats.stock_length - stats.weapon_length * PX_PER_M)


## Hand positions in Player space (hands sit under the weapon).
func hand_points() -> Array[Vector2]:
	var t := transform * _hold_transform()
	var support := stats.support_hand
	if state == State.RELOADING or state == State.CLEARING:
		# Support hand goes to the mag well and back.
		support = Vector2(-7, -9 + sin(state_progress() * TAU * 2.0) * 4.0)
	return [t * stats.grip_hand, t * support]


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k.pressed and not k.echo:
		match k.physical_keycode:
			KEY_R:
				reload()
			KEY_B:
				cycle_fire_mode()


func _physics_process(delta: float) -> void:
	_since_shot += delta
	dry_flash = maxf(dry_flash - delta, 0.0)
	_flash = maxf(_flash - delta, 0.0)
	_kick = move_toward(_kick, 0.0, delta * 40.0)
	var reloading := state == State.RELOADING or state == State.CLEARING
	_tilt = move_toward(_tilt, -0.45 if reloading else 0.0, delta * 4.0)
	_update_state(delta)
	_update_block()
	_update_trigger(delta)
	_update_recoil(delta)
	queue_redraw()


func _update_trigger(delta: float) -> void:
	var held := trigger or Input.is_physical_key_pressed(KEY_SPACE)
	var pressed := held and not _trigger_was
	_trigger_was = held
	var mode := fire_mode()
	if pressed and mode != FirearmStats.FireMode.AUTO:
		_burst_left = stats.burst_count if mode == FirearmStats.FireMode.BURST else 1
	if pressed and state == State.READY and not jammed and not _has_round():
		dry_flash = 0.8

	_cooldown -= delta
	while _cooldown <= 0.0 and ((mode == FirearmStats.FireMode.AUTO and held) or _burst_left > 0):
		if not _try_fire():
			_burst_left = 0
			break
		_cooldown += stats.shot_interval()
		_burst_left = maxi(_burst_left - 1, 0)
	_cooldown = maxf(_cooldown, 0.0)


func _try_fire() -> bool:
	if state != State.READY or jammed or blocked > 0.0 or not _has_round():
		return false
	if stats.closed_bolt:
		chambered = mag > 0
		if chambered:
			mag -= 1
	else:
		mag -= 1
	if randf() < stats.jam_chance:
		jammed = true

	var spread := current_spread_deg()
	var muzzle := to_global(muzzle_local())
	for i in stats.bullet_count:
		var off := clampf(randfn(0.0, spread / 4.0), -spread / 2.0, spread / 2.0)
		var dir := Vector2.UP.rotated(global_rotation + deg_to_rad(off))
		_projectiles.spawn_bullet(muzzle, dir * stats.muzzle_velocity * PX_PER_M, stats, _player)
	_projectiles.spawn_casing(to_global(Vector2(3, -12)), global_rotation)

	# Vertical: eased stacking, each shot adds less the closer the stack is to 1.
	recoil_stack = minf(1.0, recoil_stack + stats.vertical_recoil * pow(1.0 - recoil_stack, 1.5))
	# Horizontal: bounce left/right, part of it rolls back by itself.
	var dir_sign := 1.0 if randf() < stats.horizontal_recoil_right else -1.0
	var bounce := deg_to_rad(stats.horizontal_recoil * randf_range(0.6, 1.0)) * dir_sign
	_player.turn(bounce)
	_roll_back -= bounce * stats.recoil_recovery
	_kick = 3.0
	_flash = 0.045
	_shake = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 2.5
	_since_shot = 0.0
	return true


func _update_recoil(delta: float) -> void:
	if _since_shot > stats.shot_interval() + 0.06:
		# Ease out of the stack: slow near 0, faster when high.
		recoil_stack = move_toward(recoil_stack, 0.0, stats.vertical_recovery_rate() * delta * (0.3 + recoil_stack))
	if _since_shot > 0.04 and _roll_back != 0.0:
		var step := _roll_back * minf(1.0, stats.roll_back_rate() * delta)
		_player.turn(step)
		_roll_back -= step
	_shake = _shake.lerp(Vector2.ZERO, minf(1.0, delta * 25.0))
	if _camera:
		var eased := recoil_stack * recoil_stack * (3.0 - 2.0 * recoil_stack)
		_camera.position = _cam_base + Vector2(0, eased * CAM_PUSH) + _shake
		_camera.zoom = Vector2.ONE * (1.0 + eased * CAM_ZOOM)


func _update_state(delta: float) -> void:
	if state == State.READY:
		return
	_state_left -= delta
	if _state_left > 0.0:
		return
	match state:
		State.RELOADING:
			_finish_reload()
		State.CLEARING:
			jammed = false
			# The stuck round is thrown out; chamber the next one.
			if stats.closed_bolt:
				chambered = mag > 0
				if chambered:
					mag -= 1
			else:
				mag = maxi(mag - 1, 0)
	state = State.READY


func _finish_reload() -> void:
	var best := 0
	for i in mags.size():
		if mags[i] > mags[best]:
			best = i
	var new_mag := mags[best]
	mags.remove_at(best)
	if mag > 0:
		mags.append(mag) # keep partial mag
	mag = new_mag
	if stats.closed_bolt and not chambered and mag > 0:
		mag -= 1
		chambered = true


func _has_round() -> bool:
	return chambered if stats.closed_bolt else mag > 0


func _set_state(s: State, time: float) -> void:
	state = s
	_state_left = time
	_state_total = maxf(time, 0.001)


## Weapon length check: is the muzzle inside something?
func _update_block() -> void:
	var from := _player.global_position
	var to := to_global(muzzle_local())
	var q := PhysicsRayQueryParameters2D.create(from, to)
	q.exclude = [_player.get_rid()]
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	blocked = 0.0 if hit.is_empty() else from.distance_to(to) - from.distance_to(hit.position)


func _hold_transform() -> Transform2D:
	return Transform2D(_tilt, Vector2(0, minf(blocked, MAX_PULL) + _kick))


func _draw() -> void:
	# Spread cone from the muzzle
	if state == State.READY and blocked <= 0.0:
		var half := deg_to_rad(current_spread_deg() / 2.0)
		var m := muzzle_local()
		for s in [-1.0, 1.0]:
			var d := Vector2.UP.rotated(half * s)
			draw_line(m + d * 20.0, m + d * 420.0, Color(1, 0.9, 0.3, 0.18), 1.5)

	draw_set_transform_matrix(_hold_transform())
	WeaponArt.draw(self, stats.model)
	if _flash > 0.0:
		var m := muzzle_local()
		var pts := PackedVector2Array()
		for i in 10:
			var r := 10.0 if i % 2 == 0 else 4.0
			var a := TAU * i / 10.0
			pts.append(m + Vector2(0, -7) + Vector2(cos(a) * r * 0.7, sin(a) * r))
		draw_colored_polygon(pts, Color(1, 0.85, 0.4, 0.9))
		draw_circle(m + Vector2(0, -5), 3.0, Color(1, 1, 0.85))
	draw_set_transform_matrix(Transform2D.IDENTITY)
