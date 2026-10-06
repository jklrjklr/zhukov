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

enum State { WANDER, STALK, WINDUP, CHARGE, SKID, STUNNED, SWIPE, DEAD, CALL }

const PX := Firearm.PX_PER_M
## Drawing scale (art is authored at 1x) and matching collision radius.
const ART_SCALE := 1.6 * Vis.VISUAL_SCALE
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
const BLOOD := Color(0.9, 0.5, 0.1)
## Cadence: LOS rays at THINK_NEAR (<= NEAR_M from the player) / THINK_FAR, random phase.
const NEAR_M := 20.0
const THINK_NEAR := 0.1
const THINK_FAR := 0.2
const RIG_RANGE_M := 45.0
const RIG_RANGE_PX2 := (RIG_RANGE_M * 60.0) * (RIG_RANGE_M * 60.0)
const ACCEL := 600.0
const SEP_SPEED := 0.5
var radius := RADIUS
var last_turn := 0.0
var _think_t := 0.0
var _think_hit := false
var _los := false
var _sep := Vector2.ZERO
var _turn := 0.0
var _rig: ChargerRig
var _tele: Node2D
## Awareness (see Awareness): level, suspicion meter, last cue, quiet seconds, LOS dwell, call timer.
var level := Awareness.Level.UNAWARE
var suspicion := 0.0
var _cue_pos := Vector2.ZERO
var _quiet_t := 0.0
var _dwell := 0.0
var _call_t := 0.0
var _think_acc := 0.0
var _think_dt := 0.1
var _mission: Node


func _ready() -> void:
	hp = max_hp
	add_to_group("enemies")
	add_to_group("chargers")
	add_to_group("concealable")
	Enemies.add(self)
	_think_t = randf() * THINK_FAR
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
	_rig = ChargerRig.make(ART_SCALE)
	add_child(_rig)
	_tele = Enemies.make_overlay(self, _draw_tele)
	_new_wander()


func is_dead() -> bool:
	return state == State.DEAD


func is_alerted() -> bool:
	return state != State.DEAD and level == Awareness.Level.ALERT


func _mission_node() -> Node:
	if _mission == null or not is_instance_valid(_mission):
		_mission = get_tree().get_first_node_in_group("mission")
	return _mission


func hear(pos: Vector2, loudness: float, falloff_pct: float) -> void:
	hear_sound(pos, loudness, falloff_pct, Awareness.Sound.GUNFIRE)


## A sound raises suspicion by distance (hard caps per kind); never alert by itself.
func hear_sound(pos: Vector2, loudness: float, _falloff_pct: float, kind: int) -> void:
	if state == State.DEAD or level == Awareness.Level.ALERT:
		return
	var gain := Awareness.sound_gain(kind, loudness, global_position.distance_to(pos) / PX) * hearing / 100.0 / 0.85
	if gain > 0.0:
		add_suspicion(minf(gain, 1.0), pos)


func add_suspicion(amount: float, pos: Vector2, absolute := false) -> void:
	if state == State.DEAD or level == Awareness.Level.ALERT:
		return
	suspicion = maxf(suspicion, amount) if absolute else clampf(suspicion + amount, 0.0, 1.0)
	_quiet_t = 0.0
	_cue_pos = pos
	_update_level()
	if suspicion >= Awareness.SUSPICIOUS_AT and state == State.WANDER:
		_goal = pos # investigate: walk to the cue
		_t = 8.0


func _update_level() -> void:
	if level == Awareness.Level.ALERT:
		return
	if suspicion >= Awareness.SUSPICIOUS_AT or (level == Awareness.Level.SUSPICIOUS and suspicion >= Awareness.UNAWARE_BELOW):
		level = Awareness.Level.SUSPICIOUS
	else:
		level = Awareness.Level.UNAWARE


func alert_to(pos: Vector2, chase := false) -> void:
	if state == State.DEAD or level == Awareness.Level.ALERT:
		return
	if chase and _player:
		_become_alert(false)
	else:
		add_suspicion(0.5, pos)


## Player identified (LOS dwell) or hit by the player: this charger alone is alert; it may call.
func _become_alert(can_call: bool) -> void:
	if state == State.DEAD or level == Awareness.Level.ALERT:
		return
	level = Awareness.Level.ALERT
	suspicion = 1.0
	_dwell = 0.0
	_aware_t = 0.0
	Sfx.play("charger_roar", global_position, 0.0)
	if state == State.WANDER:
		state = State.STALK
	if _player:
		_goal = _player.global_position
	if can_call and state == State.STALK and _mission_node() != null and _mission_node().request_call(self):
		state = State.CALL
		_call_t = 0.0
		Sfx.play("bug_alert", global_position, 3.0)


func _cancel_call() -> void:
	if state == State.CALL:
		state = State.STALK
	if _mission_node() != null:
		_mission_node().cancel_call(self)


func _lose_player() -> void:
	level = Awareness.Level.SUSPICIOUS
	suspicion = 1.0
	_quiet_t = 0.0
	_dwell = 0.0


## Decay without cues and spreading suspicion (never the alert) to bugs within 15 m.
func _awareness_tick(dt: float) -> void:
	if state == State.DEAD:
		return
	if level != Awareness.Level.ALERT:
		_quiet_t += dt
		if suspicion > 0.0 and _quiet_t > Awareness.QUIET_GRACE_S:
			suspicion = maxf(suspicion - dt / Awareness.DECAY_S, 0.0)
		_update_level()
	if level != Awareness.Level.UNAWARE:
		var src := 1.0 if level == Awareness.Level.ALERT else suspicion
		var cue := global_position if level == Awareness.Level.ALERT else _goal
		var lim := pow(Awareness.SPREAD_M * PX, 2)
		for o in Enemies.list:
			if o != self and o.has_method("add_suspicion") and o.global_position.distance_squared_to(global_position) <= lim:
				o.add_suspicion(src * Awareness.SPREAD_FACTOR, cue, true)


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
		if state == State.CALL:
			_cancel_call()
		_go(State.STUNNED, 1.2)
	if hp <= 0.0:
		_die()
		return
	if level != Awareness.Level.ALERT and _player:
		_become_alert(true)


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
	if not _dust.is_empty():
		for d in _dust:
			d.t += delta
		_dust = _dust.filter(func(d): return d.t < 0.6)
	_tick += 1
	var near := _player != null and global_position.distance_squared_to(_player.global_position) < pow(NEAR_M * PX, 2)
	_think_hit = false
	_think_acc += delta
	_think_t -= delta
	if _think_t <= 0.0:
		_think_t = maxf(_think_t + (THINK_NEAR if near else THINK_FAR), 0.0)
		_think_hit = true
		_think_dt = _think_acc
		_think_acc = 0.0
		_think(near)
		_awareness_tick(_think_dt)
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
			if _think_hit and player_ok:
				if _sees_player(to_player):
					var need := Awareness.dwell_time(to_player.length() / PX)
					_dwell += _think_dt
					add_suspicion(Awareness.SUSPICIOUS_AT + (0.9 - Awareness.SUSPICIOUS_AT) * clampf(_dwell / need, 0.0, 1.0), _player.global_position, true)
					if _dwell >= need:
						_become_alert(true)
				else:
					_dwell = maxf(_dwell - _think_dt * 2.0, 0.0)
		State.STALK:
			speed = stalk_speed
			if player_ok and _think_hit and _los:
				_goal = _player.global_position
			face = (_goal - global_position).normalized()
			var dist := to_player.length() / PX
			if player_ok and dist < 2.2:
				_go(State.SWIPE, 0.0)
			elif player_ok and _cooldown <= 0.0 and dist >= 4.0 and dist <= 20.0 \
					and absf(Vector2.UP.rotated(rotation).angle_to(to_player)) < 0.35 \
					and _los:
				Sfx.play("charger_roar", global_position, 2.0)
				_go(State.WINDUP, windup_time)
			elif not player_ok or global_position.distance_to(_goal) < 40.0:
				if not player_ok or not _los:
					_lose_player()
					_new_wander()
		State.CALL:
			# Stands, rears up and roars for reinforcements; stunned / killed = cancelled.
			if player_ok:
				face = to_player.normalized()
			_call_t += delta
			if _call_t >= Awareness.CALL_TIME:
				state = State.STALK
				if _mission_node() != null:
					_mission_node().finish_call(self)
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
			return
		State.SKID:
			_t -= delta
			velocity = velocity.move_toward(Vector2.ZERO, 1400.0 * delta)
			move_and_slide()
			if _t <= 0.0:
				_cooldown = charge_cooldown
				state = State.STALK
			return
		State.STUNNED:
			_t -= delta
			velocity = velocity.move_toward(Vector2.ZERO, 1400.0 * delta)
			move_and_slide()
			if _t <= 0.0:
				_cooldown = 0.8
				state = State.STALK
			return
		State.SWIPE:
			_t += delta
			if player_ok:
				face = to_player.normalized()
			if _t >= 0.6 and _t - delta < 0.6 and player_ok:
				if to_player.length() < RADIUS + 16.0 * Game.VISUAL_SCALE + 1.6 * PX \
						and absf(Vector2.UP.rotated(rotation).angle_to(to_player)) < 1.2:
					_player.take_damage(swipe_damage, global_position)
			if _t >= 1.1:
				state = State.STALK

	var before := rotation
	var want := face.angle() + PI / 2.0
	var max_step := deg_to_rad(turn_speed_deg) * delta * (2.0 if state == State.WINDUP else 1.0)
	rotation += clampf(wrapf(want - rotation, -PI, PI), -max_step, max_step)
	var dr := wrapf(rotation - before, -PI, PI)
	last_turn = absf(dr)
	_turn = lerpf(_turn, dr / maxf(delta, 0.0001), minf(delta * 10.0, 1.0))
	var forward := Vector2.UP.rotated(rotation)
	var target := forward * speed * PX * clampf(forward.dot(face), 0.0, 1.0)
	if near:
		target += _sep * SEP_SPEED * PX
	velocity = velocity.move_toward(target, ACCEL * delta)
	move_and_slide()
	# Walking into a rock: pick a new direction after a moment.
	if speed > 0.0 and get_real_velocity().length() < speed * PX * 0.25:
		_stuck += delta
		if _stuck > 1.0:
			_stuck = 0.0
			_goal = global_position + Vector2.from_angle(randf() * TAU) * 5.0 * PX
	else:
		_stuck = 0.0


func _update_charge(delta: float) -> void:
	velocity = _charge_dir * charge_speed * PX
	var step := velocity * delta
	_charge_dist += step.length()
	if _tick % 2 == 0:
		_dust.append({"pos": global_position - _charge_dir * RADIUS, "t": 0.0})
	# Player in the path?
	if _player and not _player.dead and not _hit_player:
		var to := _player.global_position - global_position
		if to.length() < RADIUS + 22.0 * Game.VISUAL_SCALE and to.dot(_charge_dir) > 0.0:
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
	return _los


## Perception ray (cached in _los) and separation vector: run at THINK_NEAR / THINK_FAR.
func _think(near: bool) -> void:
	_sep = Enemies.separation(self, RADIUS) if near else Vector2.ZERO
	if _player == null or _player.dead or state in [State.CHARGE, State.SKID, State.STUNNED, State.SWIPE, State.DEAD]:
		_los = false if (_player == null or _player.dead) else _los
		return
	_los = global_position.distance_squared_to(_player.global_position) < pow(40.0 * PX, 2) and _has_los(_player.global_position)


func _has_los(pos: Vector2) -> bool:
	var q := PhysicsRayQueryParameters2D.create(global_position, pos, 1)
	q.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_ray(q).is_empty()


func _die() -> void:
	if state == State.CALL:
		_cancel_call()
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
	Enemies.remove(self)
	_col.set_deferred("disabled", true)
	z_index = -1
	velocity = Vector2.ZERO
	set_physics_process(false)
	_tele.visible = false
	get_tree().create_timer(60.0, false).timeout.connect(queue_free)


## Rig animation + overlays, once per rendered frame (see Terminid._process).
func _process(delta: float) -> void:
	if not _numbers.is_empty():
		for n in _numbers:
			n.t += delta
		_numbers = _numbers.filter(func(n): return n.t < 0.9)
	if state == State.DEAD:
		if _rig.corpse_sprite == null:
			_rig.animate(delta, 0.0, false, 0.0, false, false, false, 0.0, true)
			_rig.flush()
			if _rig.settled():
				_rig.become_corpse()
		_update_overlays()
		if _numbers.is_empty() and _rig.corpse_sprite != null:
			set_process(false)
			Enemies.add_corpse(self)
		return
	_update_overlays()
	if not visible or (_player != null and global_position.distance_squared_to(_player.global_position) > RIG_RANGE_PX2):
		return
	var charging := state == State.CHARGE
	var move := clampf(velocity.length() / (stalk_speed * PX), 0.0, 3.0)
	var windup := state == State.WINDUP
	var calling := state == State.CALL
	_rig.animate(delta, move, charging, 1.0 if (windup or calling) else 0.0, windup and int(_t * 10.0) % 2 == 0, state == State.STUNNED,
		is_alerted(), _flash, false)
	_rig.flush()


func _update_overlays() -> void:
	var dead := state == State.DEAD
	var lane := not dead and (state == State.WINDUP or (state == State.CHARGE and _charge_dist < 3.0 * PX))
	var tele := lane or not _dust.is_empty() or (state == State.STUNNED and not dead) or (state == State.CALL and not dead)
	if tele:
		_tele.visible = true
		_tele.queue_redraw()
	elif _tele.visible:
		_tele.visible = false
	EnemyOverlay.set_active(self, not dead or not _numbers.is_empty())


func _icon_kind() -> int:
	if state == State.DEAD:
		return EnemyUi.Icon.NONE
	if is_alerted() or state == State.CALL:
		return EnemyUi.Icon.ALERT
	return EnemyUi.Icon.SUSPICIOUS if level == Awareness.Level.SUSPICIOUS else EnemyUi.Icon.NONE


func _icon_pop() -> float:
	if state == State.WINDUP or state == State.CHARGE:
		return 1.3
	return 1.0 + 0.5 * clampf(1.0 - _aware_t / 0.35, 0.0, 1.0) if is_alerted() else 1.0


## Charge dust trail, wind-up lane, stun stars (enemy-local frame).
func _draw_tele() -> void:
	for d in _dust:
		var k: float = d.t / 0.6
		_tele.draw_circle(to_local(d.pos), 8.0 + k * 14.0, Color(0.55, 0.48, 0.38, 0.4 * (1.0 - k)))
	if state == State.WINDUP or (state == State.CHARGE and _charge_dist < 3.0 * PX):
		_draw_charge_lane()
	if state == State.CALL:
		var kk := clampf(_call_t / Awareness.CALL_TIME, 0.0, 1.0)
		var ph := fmod(_call_t * 1.6, 1.0)
		var base := RADIUS * 1.25
		_tele.draw_circle(Vector2.ZERO, base * (1.0 + 1.6 * ph), Color(1.0, 0.55, 0.1, 0.16 * (1.0 - ph)))
		_tele.draw_arc(Vector2.ZERO, base * (1.0 + 1.6 * ph), 0.0, TAU, 48, Color(1.0, 0.6, 0.15, 0.85 * (1.0 - ph)), 4.0 * Vis.VISUAL_SCALE)
		_tele.draw_arc(Vector2.ZERO, base, 0.0, TAU, 48, Color(1.0, 0.55, 0.1, 0.35), 3.0 * Vis.VISUAL_SCALE)
		_tele.draw_arc(Vector2.ZERO, base * 1.1, -PI / 2.0, -PI / 2.0 + TAU * kk, 48, Color(1.0, 0.85, 0.3, 0.9), 4.5 * Vis.VISUAL_SCALE)
	if state == State.STUNNED:
		for i in 3:
			var a := Time.get_ticks_msec() * 0.005 + i * TAU / 3.0
			_tele.draw_circle(Vector2(0, -30.0 * ART_SCALE) + Vector2.from_angle(a) * 16.0 * ART_SCALE, 3.0 * ART_SCALE, UiStyle.YELLOW)


## Charge wind-up: red lane straight ahead (where the charge will go) with moving chevrons.
func _draw_charge_lane() -> void:
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
	_tele.draw_polygon(pts, cols)
	var edge := Color(1, 0.3, 0.15, 0.35 + 0.4 * k * (0.6 + 0.4 * pulse))
	_tele.draw_line(Vector2(-hw, -RADIUS), Vector2(-hw, -len * 0.7), edge, 2.5)
	_tele.draw_line(Vector2(hw, -RADIUS), Vector2(hw, -len * 0.7), edge, 2.5)
	var off := fmod(Time.get_ticks_msec() * 0.25, 90.0)
	var y := -RADIUS - 30.0 - off
	for i in 8:
		var yy := y - i * 90.0
		if yy < -len:
			break
		var a := (0.7 - float(i) * 0.08) * k
		_tele.draw_polyline(PackedVector2Array([Vector2(-hw * 0.6, yy + 18), Vector2(0, yy), Vector2(hw * 0.6, yy + 18)]),
			Color(1, 0.35, 0.2, maxf(a, 0.05)), 4.0)


func overlay_has_numbers() -> bool:
	return not _numbers.is_empty()


func overlay_numbers(o: EnemyOverlay) -> void:
	EnemyUi.numbers(o, _numbers, -RADIUS / Game.BILLBOARD_SCALE - 40.0, Color(1, 0.55, 0.15), 18)


## Screen-aligned on the shared overlay: HP bar (always on the heavy), awareness badge, ricochet shield.
func overlay_draw(o: EnemyOverlay) -> void:
	if state == State.DEAD:
		return
	var rb := RADIUS / Game.BILLBOARD_SCALE
	var top := -rb - 34.0
	var w := 64.0
	o.hp_bar(self, top, w, 8.0, hp / max_hp, 1.0, true, Color(0.9, 0.3, 0.15))
	for i in range(1, 4):
		o.bar_tick(self, -w * 0.5 + w * i / 4.0, top, 8.0, Color(0, 0, 0, 0.6))
	o.icon(self, _icon_kind(), Vector2(0, top - 16.0), 11.0, suspicion, _icon_pop())
	if _bounce_t > 0.0:
		var a := clampf(_bounce_t / 0.3, 0.0, 1.0)
		o.shield(self, Vector2(rb * 0.8 + 10.0, -rb * 0.3 - (0.7 - _bounce_t) * 24.0), a, 1.15)
