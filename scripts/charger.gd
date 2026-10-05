class_name Charger
extends CharacterBody2D
## Charger: heavy armored Terminid (Helldivers 2 Charger).
## - Armor by facing: front plates AC5, sides AC3, rear sac AC1 (and the rear sac is a
##   weak spot: hits from behind always count as critical). Flank it.
## - Very heavy: light weapons barely stagger it; explosives can.
## - Sees the player (90 deg / 10 m) or hears noise; stalks toward them.
## - At 4-20 m with a clear line it rears up (wind-up), then CHARGES in a straight line
##   at high speed, unable to turn. Hitting the player does heavy damage and throws
##   them; ramming a wall/rock stuns it; it smashes through crates and trees.
## - Close up it swipes with its claws instead.

enum State { WANDER, STALK, WINDUP, CHARGE, SKID, STUNNED, SWIPE, DEAD }

const PX := Firearm.PX_PER_M
## Drawing scale (art is authored at 1x) and matching collision radius.
const ART_SCALE := 1.6
const RADIUS := 28.0 * ART_SCALE
const FRONT_AC := 5
const SIDE_AC := 3
const REAR_AC := 1
const REAR_CRIT_MULT := 2.0
## Stagger thresholds (same idea as Terminids, much heavier).
const STUN_DECAY := 0.4

@export var max_hp := 1000.0
@export var weight := 900.0
@export var wander_speed := 0.8
@export var stalk_speed := 2.2
@export var charge_speed := 10.0
@export var charge_max_m := 24.0
@export var windup_time := 1.0
@export var charge_cooldown := 2.5
@export var charge_damage := 65.0
@export var swipe_damage := 35.0
@export var sight_m := 10.0
@export var fov_deg := 90.0
@export var hearing := 85.0
@export var turn_speed_deg := 120.0

var hp := 1000.0
var state := State.WANDER

var _player: CharacterBody2D
var _goal := Vector2.ZERO
var _t := 0.0
var _cooldown := 1.0
var _charge_dir := Vector2.UP
var _charge_dist := 0.0
var _hit_player := false
var _tick := 0
var _walk_phase := 0.0
var _flash := 0.0
var _stun_meter := 0.0
var _dead_t := 0.0
var _numbers: Array[Dictionary] = []
var _dust: Array[Dictionary] = []
var _col: CollisionShape2D
var _stuck := 0.0
var _step_t := 0.0
var _hurt_snd := 0.0
## Graphics.
var _dmg_t := 99.0
var _bounce_t := 0.0
var _aware_t := 0.0
var _base := Transform2D.IDENTITY
const BLOOD := Color(0.9, 0.5, 0.1)


func _ready() -> void:
	hp = max_hp
	add_to_group("enemies")
	add_to_group("chargers")
	add_to_group("concealable")
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 2
	collision_mask = 3
	_col = CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = RADIUS
	_col.shape = shape
	add_child(_col)
	_player = get_tree().get_first_node_in_group("player")
	rotation = randf() * TAU
	_new_wander()


func is_dead() -> bool:
	return state == State.DEAD


func is_alerted() -> bool:
	return state in [State.STALK, State.WINDUP, State.CHARGE, State.SWIPE, State.SKID, State.STUNNED]


func _notice() -> void:
	Sfx.play("charger_roar", global_position, 0.0)
	get_tree().call_group("mission", "on_bug_alert", self)


func hear(pos: Vector2, loudness: float, falloff_pct: float) -> void:
	if state != State.WANDER:
		return
	var level := FirearmStats.loudness_at(loudness, falloff_pct, global_position.distance_to(pos) / PX)
	if level >= 100.0 - hearing:
		state = State.STALK
		_goal = pos
		_notice()


func alert_to(pos: Vector2, _chase := false) -> void:
	if state == State.WANDER:
		state = State.STALK
		_goal = pos
		_notice()


## Which armor a bullet travelling in `dir` meets: front, side or rear.
func facing_zone(dir: Vector2) -> String:
	var forward := Vector2.UP.rotated(rotation)
	var d := dir.normalized().dot(forward)
	if d < -0.5:
		return "front" # bullet travels against our facing: hits the face
	if d > 0.5:
		return "rear"
	return "side"


func take_hit(hit: Dictionary) -> void:
	if state == State.DEAD:
		return
	var zone := facing_zone(hit.dir)
	var ac := FRONT_AC if zone == "front" else (REAR_AC if zone == "rear" else SIDE_AC)
	if hit.get("explosive", false):
		ac = SIDE_AC # blasts wrap around the plates
	var f := FirearmStats.armor_factor(hit.armor_penetration, ac)
	var crit: bool = zone == "rear" and not hit.get("explosive", false)
	var dmg: float = hit.damage * f * (REAR_CRIT_MULT if crit else 1.0)
	hp -= dmg
	_flash = 0.08
	_dmg_t = 0.0
	var hit_pos: Vector2 = hit.get("pos", global_position)
	if f <= 0.3:
		Fx.spark(self, hit_pos, hit.dir, 9 if f <= 0.0 else 5)
		_bounce_t = 0.7
	else:
		Fx.splat(self, hit_pos, hit.dir, BLOOD, crit)
	if _hurt_snd <= 0.0:
		_hurt_snd = 0.15
		Sfx.play("hit_armor" if f <= 0.3 else "hit_flesh", global_position, -4.0)
		if hp > 0.0 and f > 0.3:
			Sfx.play("bug_hurt", global_position, -2.0)
	var text := "BLOCK" if f <= 0.0 else ("WEAK %d" if crit else "%d") % roundi(dmg)
	_numbers.append({"text": text, "t": 0.0, "crit": crit, "x": randf_range(-14, 14)})
	# Stagger: impact / weight; only big hits matter.
	var impact: float = hit.get("stagger", 0.0) / weight
	_stun_meter += impact
	if _stun_meter >= 1.0 and state != State.CHARGE:
		_stun_meter = 0.0
		_go(State.STUNNED, 1.2)
	if hp <= 0.0:
		_die()
		return
	if state == State.WANDER and _player:
		state = State.STALK
		_goal = _player.global_position
		_notice()


func _go(s: State, t := 0.0) -> void:
	state = s
	_t = t


func _new_wander() -> void:
	state = State.WANDER
	_goal = global_position + Vector2.from_angle(randf() * TAU) * randf_range(4.0, 10.0) * PX
	_t = randf_range(5.0, 10.0)


func _physics_process(delta: float) -> void:
	_flash = maxf(_flash - delta, 0.0)
	_dmg_t += delta
	_bounce_t = maxf(_bounce_t - delta, 0.0)
	_aware_t = _aware_t + delta if is_alerted() else 0.0
	_hurt_snd = maxf(_hurt_snd - delta, 0.0)
	for n in _numbers:
		n.t += delta
	_numbers = _numbers.filter(func(n): return n.t < 0.9)
	for d in _dust:
		d.t += delta
	_dust = _dust.filter(func(d): return d.t < 0.6)
	if state == State.DEAD:
		_dead_t += delta
		if _dead_t > 60.0:
			queue_free()
		queue_redraw()
		return

	_tick += 1
	_step_t -= delta
	if _step_t <= 0.0 and velocity.length() > 40.0 and _player and global_position.distance_to(_player.global_position) < 30.0 * PX:
		_step_t = 0.55 if state != State.CHARGE else 0.25
		Sfx.play("bug_big_step", global_position, -2.0)
	_cooldown = maxf(_cooldown - delta, 0.0)
	_stun_meter = maxf(_stun_meter - STUN_DECAY * delta, 0.0)
	var speed := 0.0
	var face := Vector2.UP.rotated(rotation)
	var to_player := (_player.global_position - global_position) if _player else Vector2.ZERO
	var player_ok: bool = _player != null and not _player.dead

	match state:
		State.WANDER:
			_t -= delta
			speed = wander_speed
			if _t <= 0.0 or global_position.distance_to(_goal) < 30.0:
				_new_wander()
			face = (_goal - global_position).normalized()
			if _tick % 6 == 0 and player_ok and _sees_player(to_player):
				state = State.STALK
				_notice()
		State.STALK:
			speed = stalk_speed
			if player_ok and _tick % 6 == 0 and _has_los(_player.global_position):
				_goal = _player.global_position
			face = (_goal - global_position).normalized()
			var dist := to_player.length() / PX
			if player_ok and dist < 2.2:
				_go(State.SWIPE, 0.0)
			elif player_ok and _cooldown <= 0.0 and dist >= 4.0 and dist <= 20.0 \
					and absf(Vector2.UP.rotated(rotation).angle_to(to_player)) < 0.35 \
					and _has_los(_player.global_position):
				Sfx.play("charger_roar", global_position, 2.0)
				_go(State.WINDUP, windup_time)
			elif not player_ok or global_position.distance_to(_goal) < 40.0:
				if not player_ok or not _has_los(_player.global_position):
					_new_wander()
		State.WINDUP:
			_t -= delta
			if player_ok:
				face = to_player.normalized() # can still aim during the wind-up
			if _t <= 0.0:
				Sfx.play("charger_charge", global_position, 2.0)
				_charge_dir = Vector2.UP.rotated(rotation)
				_charge_dist = 0.0
				_hit_player = false
				# Plough through actors; only world geometry stops a charge.
				collision_mask = 1
				if _player:
					add_collision_exception_with(_player)
				_go(State.CHARGE)
		State.CHARGE:
			_update_charge(delta)
			queue_redraw()
			return
		State.SKID:
			_t -= delta
			velocity = velocity.move_toward(Vector2.ZERO, 1400.0 * delta)
			move_and_slide()
			if _t <= 0.0:
				_cooldown = charge_cooldown
				state = State.STALK
			queue_redraw()
			return
		State.STUNNED:
			_t -= delta
			velocity = velocity.move_toward(Vector2.ZERO, 1400.0 * delta)
			move_and_slide()
			if _t <= 0.0:
				_cooldown = 0.8
				state = State.STALK
			queue_redraw()
			return
		State.SWIPE:
			_t += delta
			if player_ok:
				face = to_player.normalized()
			if _t >= 0.6 and _t - delta < 0.6 and player_ok:
				if to_player.length() < RADIUS + 16.0 + 1.6 * PX \
						and absf(Vector2.UP.rotated(rotation).angle_to(to_player)) < 1.2:
					_player.take_damage(swipe_damage, global_position)
			if _t >= 1.1:
				state = State.STALK

	var want := face.angle() + PI / 2.0
	var max_step := deg_to_rad(turn_speed_deg) * delta * (2.0 if state == State.WINDUP else 1.0)
	rotation += clampf(wrapf(want - rotation, -PI, PI), -max_step, max_step)
	var forward := Vector2.UP.rotated(rotation)
	var target := forward * speed * PX * clampf(forward.dot(face), 0.0, 1.0)
	velocity = velocity.move_toward(target, 600.0 * delta)
	move_and_slide()
	# Walking into a rock: pick a new direction after a moment.
	if speed > 0.0 and get_real_velocity().length() < speed * PX * 0.25:
		_stuck += delta
		if _stuck > 1.0:
			_stuck = 0.0
			_goal = global_position + Vector2.from_angle(randf() * TAU) * 5.0 * PX
	else:
		_stuck = 0.0
	_walk_phase = fmod(_walk_phase + velocity.length() / (stalk_speed * PX) * 1.2 * TAU * delta, TAU)
	queue_redraw()


func _update_charge(delta: float) -> void:
	velocity = _charge_dir * charge_speed * PX
	var step := velocity * delta
	_charge_dist += step.length()
	_walk_phase = fmod(_walk_phase + 3.0 * TAU * delta, TAU)
	if _tick % 2 == 0:
		_dust.append({"pos": global_position - _charge_dir * RADIUS, "t": 0.0})
	# Player in the path?
	if _player and not _player.dead and not _hit_player:
		var to := _player.global_position - global_position
		if to.length() < RADIUS + 22.0 and to.dot(_charge_dir) > 0.0:
			_hit_player = true
			Fx.shake(self, 9.0)
			_player.take_damage(charge_damage, global_position - _charge_dir * 40.0)
			_player.velocity += _charge_dir * 500.0
	var col := move_and_collide(step)
	if col:
		var other := col.get_collider()
		if other is Destructible and (other as Destructible).kind != Destructible.Kind.NEST:
			# Smash through crates and trees.
			other.take_hit({"damage": 9999.0, "base_damage": 9999.0, "armor_penetration": 10,
				"armor_damage": 0.0, "destruction_level": 100, "stagger": 0.0,
				"dir": _charge_dir, "meters": 0.0, "aim_point": null})
		else:
			_end_charge()
			Sfx.play("hit_metal", global_position, 0.0)
			Fx.landing(self, global_position + _charge_dir * RADIUS, 70.0)
			Fx.shake_at(self, global_position, 8.0)
			_go(State.STUNNED, 2.5) # rammed something solid
			velocity = -_charge_dir * 120.0
			return
	if _charge_dist >= charge_max_m * PX:
		_end_charge()
		_go(State.SKID, 0.8)


func _end_charge() -> void:
	collision_mask = 3
	if _player:
		remove_collision_exception_with(_player)


func _sees_player(to: Vector2) -> bool:
	var forward := Vector2.UP.rotated(rotation)
	var dist := to.length()
	if dist > sight_m * PX:
		return false
	if dist > 2.0 * PX and absf(forward.angle_to(to)) > deg_to_rad(fov_deg / 2.0):
		return false
	return _has_los(_player.global_position)


func _has_los(pos: Vector2) -> bool:
	var q := PhysicsRayQueryParameters2D.create(global_position, pos, 1)
	q.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_ray(q).is_empty()


func _die() -> void:
	if state == State.CHARGE:
		_end_charge()
	state = State.DEAD
	Game.add_stat("kills")
	Fx.death(self, global_position, BLOOD, RADIUS * 1.5)
	Fx.shake_at(self, global_position, 5.0)
	Fx.hit_stop(self, 0.07)
	Sfx.play("bug_death", global_position, 2.0)
	get_tree().call_group("mission", "on_kill", self)
	remove_from_group("enemies")
	remove_from_group("chargers")
	_col.set_deferred("disabled", true)
	z_index = -1
	velocity = Vector2.ZERO


## Ellipse as a scaled unit circle in art space (ART_SCALE applied), with a dark outline.
func _ell(c: Vector2, r: Vector2, col: Color, outline := true) -> void:
	if outline:
		draw_set_transform_matrix(_base * Transform2D(Vector2(r.x + 1.6, 0), Vector2(0, r.y + 1.6), c))
		draw_circle(Vector2.ZERO, 1.0, Color(0.07, 0.06, 0.06))
	draw_set_transform_matrix(_base * Transform2D(Vector2(r.x, 0), Vector2(0, r.y), c))
	draw_circle(Vector2.ZERO, 1.0, col)
	draw_set_transform_matrix(_base)


func _draw() -> void:
	var outline := Color(0.07, 0.06, 0.06)
	var plate := Color(0.45, 0.32, 0.22)
	var dark := Color(0.28, 0.2, 0.15)
	var sac := Color(1.0, 0.55, 0.15)
	var dead := state == State.DEAD
	_base = Transform2D(Vector2(ART_SCALE, 0), Vector2(0, ART_SCALE), Vector2.ZERO)
	if dead:
		plate = plate.darkened(0.5)
		dark = dark.darkened(0.5)
		sac = Color(0.35, 0.15, 0.08)
	elif _flash > 0.0:
		plate = plate.lerp(Color.WHITE, 0.5)
		dark = dark.lerp(Color.WHITE, 0.25)
	for d in _dust:
		var k: float = d.t / 0.6
		var p: Vector2 = to_local(d.pos)
		draw_circle(p, 8.0 + k * 14.0, Color(0.55, 0.48, 0.38, 0.4 * (1.0 - k)))
	if state == State.WINDUP or (state == State.CHARGE and _charge_dist < 3.0 * PX):
		_draw_charge_lane()
	if not dead:
		var so := Vector2(7, 10).rotated(-global_rotation)
		draw_set_transform_matrix(Transform2D(Vector2(RADIUS * 1.0, 0), Vector2(0, RADIUS * 1.3), so))
		draw_circle(Vector2.ZERO, 1.0, Color(0, 0, 0, 0.3))
	draw_set_transform_matrix(_base)
	var charging := state == State.CHARGE
	var rear := state == State.WINDUP
	var stride := sin(_walk_phase)
	# Legs: 4 jointed claws.
	for side in [-1.0, 1.0]:
		var front_leg := Vector2(side * 28.0, -16.0 + stride * side * (9.0 if charging else 5.0))
		var back_leg := Vector2(side * 26.0, 18.0 - stride * side * (9.0 if charging else 5.0))
		for leg in [front_leg, back_leg]:
			var root := Vector2(side * 18.0, leg.y * 0.7)
			draw_line(root, leg, outline, 7.0)
			draw_line(root, leg, dark, 4.5)
			draw_circle(leg, 8.5, outline)
			draw_circle(leg, 7.0, dark)
			for c in 3:
				draw_line(leg, leg + Vector2(side * 6.0, (c - 1) * 5.0), outline, 2.2)
			draw_circle(leg + Vector2(-1.5, -1.5), 2.5, dark.lightened(0.25))
	# Rear sac (weak spot), pulsing, with veins and a faint target ring.
	var pulse := 1.0 + 0.08 * sin(Time.get_ticks_msec() * 0.006)
	_ell(Vector2(0, 31), Vector2(16, 15) * pulse, sac.darkened(0.25))
	_ell(Vector2(0, 33), Vector2(9, 9) * pulse, sac, false)
	if not dead:
		for a in [-0.7, 0.0, 0.7]:
			draw_line(Vector2(0, 33), Vector2(sin(a) * 13.0, 33.0 + cos(a) * 10.0), Color(0.6, 0.2, 0.05, 0.7), 1.2)
		draw_arc(Vector2(0, 33), 12.0 * pulse, 0.0, TAU, 20, Color(1, 0.85, 0.3, 0.3), 1.0)
	# Body carapace with segment ridges.
	_ell(Vector2(0, 4), Vector2(24, 29), dark)
	for k in 4:
		var y := -2.0 + k * 7.0
		draw_arc(Vector2(0, y + 6.0), 22.0 - k * 1.5, PI * 1.12, PI * 1.88, 12, outline, 1.6)
	# Side plates (AC3): lighter armour slabs with rivets.
	for side in [-1.0, 1.0]:
		_ell(Vector2(side * 21.0, 2.0), Vector2(7.5, 18.0), plate.darkened(0.12))
		draw_line(Vector2(side * 19.0, -12.0), Vector2(side * 19.0, 14.0), plate.lightened(0.25), 1.2)
		for y in [-8.0, 0.0, 8.0]:
			draw_circle(Vector2(side * 22.0, y), 1.3, plate.lightened(0.4))
	# Front armour plates (AC5): overlapping, wide, edge-lit.
	var lift := -6.0 if rear else 0.0
	for i in 3:
		var y := -18.0 + i * 9.0 + lift
		var pc := plate.darkened(i * 0.1)
		_ell(Vector2(0, y), Vector2(27 - i * 3, 9), pc)
		draw_arc(Vector2(0, y), 24.0 - i * 3.0, PI * 1.1, PI * 1.9, 14, pc.lightened(0.35), 1.6)
		for x in [-14.0 + i * 3.0, 14.0 - i * 3.0]:
			draw_circle(Vector2(x, y + 1.0), 1.4, pc.lightened(0.45))
	# Head with horns, mandibles and eyes.
	var hc := Vector2(0, -30 + lift)
	for side in [-1.0, 1.0]:
		var h0 := hc + Vector2(side * 7.0, -3.0)
		var h1 := hc + Vector2(side * 14.0, -10.0)
		draw_line(h0, h1, outline, 5.0)
		draw_line(h0, h1, plate.lightened(0.15), 2.8)
	_ell(hc, Vector2(10, 9.5), plate.darkened(0.15))
	for side in [-1.0, 1.0]:
		draw_line(hc + Vector2(side * 6, -6), hc + Vector2(side * 11, -16), outline, 4.0)
		draw_line(hc + Vector2(side * 6, -6), hc + Vector2(side * 11, -16), Color(0.8, 0.72, 0.55) if not dead else dark, 1.8)
		var ec := Color(1, 0.2, 0.1) if (is_alerted() and not dead) else Color(0.1, 0.05, 0.04)
		draw_circle(hc + Vector2(side * 4.0, -1.0), 2.0, ec)
	if state == State.WINDUP and int(_t * 10.0) % 2 == 0:
		draw_circle(hc, 4.0, Color(1, 0.25, 0.1))
	if state == State.STUNNED:
		for i in 3:
			var a := Time.get_ticks_msec() * 0.005 + i * TAU / 3.0
			draw_circle(Vector2(0, -30) + Vector2.from_angle(a) * 16.0, 3.0, UiStyle.YELLOW)
	draw_set_transform(Vector2.ZERO)
	if not dead:
		_draw_billboards()
	if not _numbers.is_empty():
		var font := ThemeDB.fallback_font
		draw_set_transform(Vector2.ZERO, -get_viewport().get_canvas_transform().get_rotation() - global_rotation)
		for n in _numbers:
			var a: float = 1.0 - n.t / 0.9
			var col := Color(1, 0.55, 0.15, a) if n.crit else Color(1, 0.95, 0.5, a)
			draw_string(font, Vector2(n.x - 50, -80 - n.t * 40.0), n.text, HORIZONTAL_ALIGNMENT_CENTER, 100, 22 if n.crit else 18, col)
		draw_set_transform(Vector2.ZERO)


## Charge wind-up: red lane straight ahead (where the charge will go) with moving chevrons.
func _draw_charge_lane() -> void:
	draw_set_transform(Vector2.ZERO)
	var k := 1.0
	if state == State.WINDUP:
		k = clampf(1.0 - _t / windup_time, 0.0, 1.0)
	else:
		k = 1.0 - _charge_dist / (3.0 * PX)
	var len := charge_max_m * PX
	var hw := RADIUS * 0.95
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.02)
	var pts := PackedVector2Array([Vector2(-hw, -RADIUS), Vector2(hw, -RADIUS), Vector2(hw, -len), Vector2(-hw, -len)])
	var cols := PackedColorArray([Color(1, 0.2, 0.1, 0.1 + 0.25 * k), Color(1, 0.2, 0.1, 0.1 + 0.25 * k),
		Color(1, 0.2, 0.1, 0.0), Color(1, 0.2, 0.1, 0.0)])
	draw_polygon(pts, cols)
	var edge := Color(1, 0.3, 0.15, 0.35 + 0.4 * k * (0.6 + 0.4 * pulse))
	draw_line(Vector2(-hw, -RADIUS), Vector2(-hw, -len * 0.7), edge, 2.5)
	draw_line(Vector2(hw, -RADIUS), Vector2(hw, -len * 0.7), edge, 2.5)
	var off := fmod(Time.get_ticks_msec() * 0.25, 90.0)
	var y := -RADIUS - 30.0 - off
	for i in 8:
		var yy := y - i * 90.0
		if yy < -len:
			break
		var a := (0.7 - float(i) * 0.08) * k
		draw_polyline(PackedVector2Array([Vector2(-hw * 0.6, yy + 18), Vector2(0, yy), Vector2(hw * 0.6, yy + 18)]),
			Color(1, 0.35, 0.2, maxf(a, 0.05)), 4.0)


## Screen-aligned icons: HP bar (always on the heavy), awareness, ricochet shield.
func _draw_billboards() -> void:
	draw_set_transform(Vector2.ZERO, -get_viewport().get_canvas_transform().get_rotation() - global_rotation)
	var font := ThemeDB.fallback_font
	var top := -RADIUS - 34.0
	var w := 64.0
	var r := Rect2(-w * 0.5, top, w, 8.0)
	draw_rect(r.grow(2.0), Color(0, 0, 0, 0.75))
	var f := clampf(hp / max_hp, 0.0, 1.0)
	var col := Color(0.9, 0.3, 0.15) if f > 0.3 else Color(1.0, 0.15, 0.1)
	draw_rect(Rect2(r.position, Vector2(r.size.x * f, r.size.y)), col)
	draw_rect(r, Color(1, 1, 1, 0.3), false, 1.0)
	for i in range(1, 4):
		draw_line(Vector2(r.position.x + w * i / 4.0, r.position.y), Vector2(r.position.x + w * i / 4.0, r.end.y), Color(0, 0, 0, 0.6), 1.0)
	var ic := Vector2(0, top - 16.0)
	var icon := ""
	var icol := UiStyle.YELLOW
	var pop := 1.0
	if state == State.WINDUP or state == State.CHARGE:
		icon = "!"
		icol = Color(1.0, 0.2, 0.1)
		pop = 1.3
	elif is_alerted():
		icon = "!"
		icol = Color(1.0, 0.45, 0.15)
		pop = 1.0 + 0.5 * clampf(1.0 - _aware_t / 0.35, 0.0, 1.0)
	if icon != "":
		var rr := 11.0 * pop
		draw_circle(ic, rr + 1.5, Color(0.05, 0.04, 0.04, 0.9))
		draw_circle(ic, rr, Color(icol, 0.92))
		draw_string(font, ic + Vector2(-rr, 7.0 * pop), icon, HORIZONTAL_ALIGNMENT_CENTER, rr * 2.0, int(20 * pop), Color(0.08, 0.05, 0.03))
	if _bounce_t > 0.0:
		var a := clampf(_bounce_t / 0.3, 0.0, 1.0)
		var c := Vector2(RADIUS * 0.8 + 10.0, -RADIUS * 0.3 - (0.7 - _bounce_t) * 24.0)
		var shield := PackedVector2Array([c + Vector2(-7, -8), c + Vector2(7, -8), c + Vector2(7, 2), c + Vector2(0, 9), c + Vector2(-7, 2)])
		var sh_o := PackedVector2Array()
		for v in shield:
			sh_o.append(c + (v - c) * 1.3)
		draw_colored_polygon(sh_o, Color(0.05, 0.05, 0.05, 0.9 * a))
		draw_colored_polygon(shield, Color(1.0, 0.88, 0.2, a))
		draw_line(c + Vector2(-5, 5), c + Vector2(5, -5), Color(0.1, 0.08, 0.04, a), 2.2)
	draw_set_transform(Vector2.ZERO)
