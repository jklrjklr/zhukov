class_name Firearm
extends Node2D
## Held firearm: fire control, ammo, reload, jams, recoil and camera kick.
## Child of Player, origin at the pistol grip, muzzle toward -Y.

const PX_PER_M := 60.0
## px the camera is pushed back at full vertical recoil stack.
const CAM_PUSH := 70.0
## Extra zoom at full vertical recoil stack.
const CAM_ZOOM := 0.08
## ADS: nearest aim distance (m).
const ADS_MIN := 2.0
## ADS muzzle rise: at full vertical recoil stack the aim circle (and where bullets
## land) is pushed this fraction of the aim distance farther away.
const ADS_RECOIL_DEPTH := 0.5
## ADS: the camera is pushed forward by this fraction of the circle's push, so the
## circle visibly climbs past the view like real muzzle rise.
const ADS_CAM_FOLLOW := 0.5

## Top-down size of a loose magazine.
const MAG_SIZE_PX := Vector2(4.5, 10)
## Max px the weapon is pulled back when the muzzle is inside a wall.
const MAX_PULL := 25.0
## Player space: chest mag pouch.
const POUCH := Vector2(-12, -3)
## px the cocking lever travels back.
const BOLT_TRAVEL := 6.0

## Support hand keyframes: [progress, point]. Points: support, well, pouch, lever, lever_back.
## Tactical: old mag out -> stowed in pouch -> fresh mag in.
const TACTICAL_KEYS := [
	[0.0, "support"], [0.12, "well"], [0.18, "well"], [0.38, "pouch"], [0.52, "pouch"],
	[0.74, "well"], [0.84, "well"], [1.0, "support"]]
const TACTICAL_MAG_IN_HAND := Vector2(0.15, 0.8)
## Empty: empty mag dropped -> fresh mag from pouch -> in -> pull and slap the bolt.
const EMPTY_KEYS := [
	[0.0, "support"], [0.08, "well"], [0.12, "well"], [0.32, "pouch"], [0.4, "pouch"],
	[0.6, "well"], [0.66, "well"], [0.74, "lever"], [0.82, "lever_back"], [0.86, "lever"],
	[1.0, "support"]]
const EMPTY_MAG_IN_HAND := Vector2(0.36, 0.64)
const EMPTY_MAG_DROP := 0.12
## Clearing a jam: rack the bolt.
const CLEAR_KEYS := [
	[0.0, "support"], [0.3, "lever"], [0.55, "lever_back"], [0.65, "lever"], [1.0, "support"]]

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
## -1..1 walk swing, set by Player. Rotates the weapon (and its shots) around the grip.
var sway := 0.0
## Aim down sights wanted (toggled by controls). Blends in over stats.ads_time().
var ads := false
## m from the muzzle to the centre of the aim circle.
var aim_distance := 10.0

var _state_left := 0.0
var _state_total := 1.0
var _cooldown := 0.0
var _trigger_was := false
var _burst_left := 0
var _since_shot := 99.0
var _roll_back := 0.0
var _kick := 0.0
var _tilt := 0.0
var _ads := 0.0
var _cam_zoom := 1.0
var _cam_offset := Vector2.ZERO
var _reload_empty := false
var _mag_dropped := false
var _flash := 0.0
var _shake := Vector2.ZERO
var _player: CharacterBody2D
var _camera: Camera2D
var _cam_base := Vector2.ZERO
var _projectiles: Node


func _ready() -> void:
	_player = get_parent()
	_camera = _player.get_node_or_null("CameraRig/Camera2D")
	if _camera:
		_cam_base = _camera.position
		_cam_offset = _cam_base
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
	_reload_empty = not _has_round()
	_mag_dropped = false
	_set_state(State.RELOADING, stats.reload_time_empty if _reload_empty else stats.reload_time_tactical)


func current_spread_deg() -> float:
	var move := clampf(_player.get_real_velocity().length() / _player.move_speed, 0.0, 1.0)
	var spread := stats.bullet_spread + stats.moving_spread * move + stats.recoil_spread * recoil_stack
	return spread * lerpf(1.0, stats.ads_spread_mult, _ads)


## 0 = hip, 1 = fully aimed.
func ads_amount() -> float:
	return _ads


func toggle_ads() -> void:
	ads = not ads


func adjust_aim(meters: float) -> void:
	aim_distance = clampf(aim_distance + meters, ADS_MIN, stats.ads_range)


## What the HUD needs to draw the aim overlay (global space). Drawn on the HUD
## layer so world lighting does not dim it.
func aim_overlay() -> Dictionary:
	return {
		"show": state == State.READY and blocked <= 0.0,
		"muzzle": to_global(muzzle_local()),
		"forward": Vector2.UP.rotated(global_rotation),
		"half_spread": deg_to_rad(current_spread_deg() / 2.0),
		"ads": _ads,
		"center": to_global(aim_center_local()),
		"radius": aim_radius_px(),
	}


## Centre of the aim circle (weapon space), including vertical recoil push.
func aim_center_local() -> Vector2:
	return muzzle_local() + Vector2(0, -aim_distance * PX_PER_M - ads_recoil_push())


## px the aim circle is currently pushed out by vertical recoil.
func ads_recoil_push() -> float:
	return _eased_stack() * ADS_RECOIL_DEPTH * aim_distance * PX_PER_M


func _eased_stack() -> float:
	return recoil_stack * recoil_stack * (3.0 - 2.0 * recoil_stack)


## Aim circle radius in px at the current aim distance.
func aim_radius_px() -> float:
	return aim_distance * PX_PER_M * tan(deg_to_rad(current_spread_deg() / 2.0))


func muzzle_local() -> Vector2:
	return Vector2(0, stats.stock_length - stats.weapon_length * PX_PER_M)


## Hand positions in Player space (hands sit under the weapon).
func hand_points() -> Array[Vector2]:
	var t := transform * _hold_transform()
	var keys := _anim_keys()
	var support := t * stats.support_hand if keys.is_empty() else _anim_hand(keys)
	return [t * stats.grip_hand, support]


## Player-space position of the mag carried by the support hand, or null.
func held_mag() -> Variant:
	if state != State.RELOADING:
		return null
	var p := state_progress()
	var span := EMPTY_MAG_IN_HAND if _reload_empty else TACTICAL_MAG_IN_HAND
	if p < span.x or p >= span.y:
		return null
	return _anim_hand(_anim_keys())


## Rotation of the weapon in Player space (for drawing a held mag).
func hold_rotation() -> float:
	return rotation + _tilt


func _anim_keys() -> Array:
	match state:
		State.RELOADING:
			return EMPTY_KEYS if _reload_empty else TACTICAL_KEYS
		State.CLEARING:
			return CLEAR_KEYS
	return []


func _anim_point(name: String) -> Vector2:
	var t := transform * _hold_transform()
	match name:
		"well":
			return t * stats.mag_well
		"pouch":
			return POUCH
		"lever":
			return t * stats.bolt_handle
		"lever_back":
			return t * (stats.bolt_handle + Vector2(0, BOLT_TRAVEL))
	return t * stats.support_hand


## Eased support hand position along the keyframes at the current progress.
func _anim_hand(keys: Array) -> Vector2:
	var p := state_progress()
	for i in keys.size() - 1:
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if p <= b[0]:
			var k := smoothstep(0.0, 1.0, (p - a[0]) / maxf(b[0] - a[0], 0.0001))
			return _anim_point(a[1]).lerp(_anim_point(b[1]), k)
	return _anim_point(keys[-1][1])


## 0..1 how far the cocking lever is pulled back (hand drags it).
func _bolt_pull() -> float:
	var keys := _anim_keys()
	if keys.is_empty():
		return 0.0
	var p := state_progress()
	for i in keys.size() - 1:
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if p <= b[0]:
			var on_lever := String(a[1]).begins_with("lever") and String(b[1]).begins_with("lever")
			if not on_lever:
				return 0.0
			var lever := _anim_point("lever")
			return clampf(_anim_hand(keys).distance_to(lever) / BOLT_TRAVEL, 0.0, 1.0)
	return 0.0


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k.pressed and not k.echo:
		match k.physical_keycode:
			KEY_R:
				reload()
			KEY_B:
				cycle_fire_mode()
			KEY_F:
				toggle_ads()
			KEY_Z:
				adjust_aim(-1.0)
			KEY_X:
				adjust_aim(1.0)


func _physics_process(delta: float) -> void:
	_since_shot += delta
	dry_flash = maxf(dry_flash - delta, 0.0)
	_flash = maxf(_flash - delta, 0.0)
	_kick = move_toward(_kick, 0.0, delta * 40.0)
	var aim_target := 1.0 if ads and state == State.READY else 0.0
	_ads = move_toward(_ads, aim_target, delta / stats.ads_time())
	var reloading := state == State.RELOADING or state == State.CLEARING
	_tilt = move_toward(_tilt, -0.45 if reloading else 0.0, delta * 4.0)
	rotation = deg_to_rad(stats.move_sway_deg()) * sway * lerpf(1.0, 0.4, _ads)
	_update_state(delta)
	_drop_empty_mag()
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
	if held and state == State.READY and not jammed and not _has_round():
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
	var speed := stats.muzzle_velocity * PX_PER_M
	for i in stats.bullet_count:
		if _ads >= 0.5:
			# Aimed: each bullet lands somewhere inside the aim circle, which vertical
			# recoil has pushed farther out (muzzle rise).
			var center := to_global(aim_center_local())
			var scatter := Vector2.from_angle(randf() * TAU) * aim_radius_px() * sqrt(randf())
			var land := center + scatter
			_projectiles.spawn_bullet(muzzle, (land - muzzle).normalized() * speed, stats, _player, land)
		else:
			var off := clampf(randfn(0.0, spread / 4.0), -spread / 2.0, spread / 2.0)
			var dir := Vector2.UP.rotated(global_rotation + deg_to_rad(off))
			_projectiles.spawn_bullet(muzzle, dir * speed, stats, _player)
	_projectiles.spawn_casing(to_global(Vector2(3, -12)), global_rotation)

	# Vertical: eased stacking, each shot adds less the closer the stack is to 1.
	recoil_stack = minf(1.0, recoil_stack + stats.vertical_recoil * pow(1.0 - recoil_stack, 1.5))
	# Horizontal: bounce left/right, part of it rolls back by itself.
	var dir_sign := 1.0 if randf() < stats.horizontal_recoil_right else -1.0
	var bounce := deg_to_rad(stats.horizontal_recoil * randf_range(0.6, 1.0)) * dir_sign
	_player.kick(bounce)
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
		_player.kick(step)
		_roll_back -= step
	_shake = _shake.lerp(Vector2.ZERO, minf(1.0, delta * 25.0))
	if _camera:
		var eased := _eased_stack()
		# ADS: zoom out / shift forward so both the player and the aim circle fit.
		var aim_px := aim_distance * PX_PER_M
		var ads_zoom := clampf(720.0 / (aim_px + 220.0), 0.5, 1.0)
		var half := 360.0 / ads_zoom
		var ads_cam := Vector2(0, -clampf(aim_px - (half - 90.0), -_cam_base.y, half - 90.0))
		var a := smoothstep(0.0, 1.0, _ads)
		var k := minf(1.0, delta * 8.0)
		_cam_zoom = lerpf(_cam_zoom, lerpf(1.0, ads_zoom, a), k)
		_cam_offset = _cam_offset.lerp(_cam_base.lerp(ads_cam, a), k)
		# Vertical recoil: hip pushes the view back toward the player; ADS pushes it
		# forward (less than the aim circle moves).
		var push := lerpf(eased * CAM_PUSH, -ads_recoil_push() * ADS_CAM_FOLLOW, a)
		_camera.position = _cam_offset + Vector2(0, push) + _shake
		_camera.zoom = Vector2.ONE * _cam_zoom * (1.0 + eased * CAM_ZOOM)


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


## Empty reload: the empty mag falls to the ground.
func _drop_empty_mag() -> void:
	if state != State.RELOADING or not _reload_empty or _mag_dropped:
		return
	if state_progress() < EMPTY_MAG_DROP:
		return
	_mag_dropped = true
	var at := _player.to_global(_anim_point("well"))
	var fall := Vector2(randf_range(-40, -10), randf_range(20, 50)).rotated(global_rotation)
	_projectiles.spawn_debris(at, fall, global_rotation + randf_range(-0.5, 0.5), MAG_SIZE_PX, Color(0.12, 0.12, 0.13), 20.0)


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
	draw_set_transform_matrix(_hold_transform())
	WeaponArt.draw(self, stats.model, _bolt_pull() * BOLT_TRAVEL)
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
