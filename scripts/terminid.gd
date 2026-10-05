class_name Terminid
extends CharacterBody2D
## Bug enemy (Helldivers 2 Terminids). One script, four kinds:
##   SCAVENGER    small, fast, fragile; swarms
##   WARRIOR      the line bug; armored body, head is the weak spot
##   HUNTER       fast flanker; LEAPS at the player from a few meters and slows them
##   BILE_SPITTER keeps its distance and lobs acid that pools on the ground
## Shared behaviour:
## - Wanders after a pack leader. Sees the player in a cone with line of sight;
##   hears sounds whose loudness here >= (100 - hearing) (loud ones deafen it).
## - Chases with context steering around obstacles (commits to a side at walls).
## - Melee: wind-up, strike if still in reach, then recover (window to act).
## - Awareness (see Awareness): UNAWARE -> SUSPICIOUS (sounds / partial sightings raise a meter; it
##   investigates, "?" fills) -> ALERT (player identified: LOS in the sight cone for a dwell time, or
##   shot). ALERT is per bug and never broadcast; suspicion spreads to bugs within 15 m. Only an
##   ALERT bug can call a breach, and it must stand and perform a visible ~2 s call first.
## - Stagger: impact = weapon stagger (x1.5 crit) / weight -> knockback, slowdown,
##   wind-up interrupt, stun meter.
## - Performance: perception (LOS ray) and steering (ray fan) run every THINK_NEAR s within
##   NEAR_M of the player, every THINK_FAR s beyond, staggered by a per-enemy phase. Physics
##   runs every frame in between: the heading turns toward the last steering direction with a
##   capped turn rate, velocity accelerates, move_and_slide every frame, separation from
##   neighbours comes from the Enemies registry (no raycasts).
## - The body is a cutout rig (BugRig, baked part textures, transforms only); the only
##   real-time drawing is on two small overlays (telegraphs, HP bar / icons / numbers).

enum Kind { SCAVENGER, WARRIOR, HUNTER, BILE_SPITTER }
enum State { WANDER, CHASE, SEARCH, ATTACK, RECOVER, LEAP, SPIT, DEAD, CALL }

const NEAR_M := 20.0
const THINK_NEAR := 0.1
const THINK_FAR := 0.2
const RIG_RANGE_M := 45.0
const RIG_RANGE_PX2 := (RIG_RANGE_M * 60.0) * (RIG_RANGE_M * 60.0)
const RIG_LOD1_PX2 := (14.0 * 60.0) * (14.0 * 60.0)
const RIG_LOD2_PX2 := (28.0 * 60.0) * (28.0 * 60.0)
const SLEEP_M := 55.0
const SLEEP_EVERY := 4
const KNOCKBACK := 450.0
const SLOW_PER_IMPACT := 1.2
const INTERRUPT_IMPACT := 0.25
const STUN_DECAY := 0.5
const STUN_TIME := 0.9
const CRIT_STAGGER_MULT := 1.5
const PX := Firearm.PX_PER_M
const RAYS := 16
const FEELER := 60.0
const ACCEL := 1100.0
const SEP_SPEED := 0.7
const OUTLINE := Color(0.07, 0.05, 0.04)
const BLOOD := {Kind.SCAVENGER: Color(0.9, 0.5, 0.12), Kind.WARRIOR: Color(0.5, 0.66, 0.14),
	Kind.HUNTER: Color(0.62, 0.7, 0.18), Kind.BILE_SPITTER: Color(0.66, 0.9, 0.16)}
const DEAFEN_LEVEL := 80.0
const DEAFEN_RATE := 0.5
const MIN_HEARING := 10.0

## Per-kind stats. Speeds are fractions of the player's base walk speed.
const KINDS := {
	Kind.SCAVENGER: {"name": "Scavenger", "hp": 60.0, "weight": 25.0, "radius": 11.0, "run": 1.35, "wander": 0.3,
		"sight": 6.0, "fov": 90.0, "reach": 0.5, "damage": 8.0, "windup": 0.25, "cooldown": 0.5, "recover": 0.5,
		"armor": 0, "head": 5.0, "crit": 2.0, "turn": 360.0,
		"color": Color(0.85, 0.55, 0.25), "dark": Color(0.55, 0.32, 0.15)},
	Kind.WARRIOR: {"name": "Warrior", "hp": 220.0, "weight": 120.0, "radius": 17.0, "run": 1.05, "wander": 0.25,
		"sight": 6.0, "fov": 70.0, "reach": 0.8, "damage": 20.0, "windup": 0.45, "cooldown": 0.9, "recover": 1.2,
		"armor": 1, "head": 8.0, "crit": 2.5, "turn": 220.0,
		"color": Color(0.62, 0.36, 0.2), "dark": Color(0.36, 0.2, 0.12)},
	Kind.HUNTER: {"name": "Hunter", "hp": 120.0, "weight": 50.0, "radius": 13.0, "run": 1.25, "wander": 0.3,
		"sight": 7.0, "fov": 90.0, "reach": 0.6, "damage": 12.0, "windup": 0.3, "cooldown": 0.7, "recover": 0.7,
		"armor": 0, "head": 6.0, "crit": 2.0, "turn": 320.0,
		"color": Color(0.5, 0.52, 0.3), "dark": Color(0.3, 0.32, 0.17)},
	Kind.BILE_SPITTER: {"name": "Bile Spitter", "hp": 280.0, "weight": 150.0, "radius": 19.0, "run": 0.8, "wander": 0.2,
		"sight": 8.0, "fov": 80.0, "reach": 0.8, "damage": 18.0, "windup": 0.5, "cooldown": 1.0, "recover": 1.0,
		"armor": 1, "head": 8.0, "crit": 2.0, "turn": 180.0,
		"color": Color(0.58, 0.45, 0.25), "dark": Color(0.35, 0.26, 0.14)},
}

## Hunter leap.
const LEAP_MIN_M := 3.0
const LEAP_MAX_M := 7.0
const LEAP_SPEED := 14.0
const LEAP_TIME := 0.35
const LEAP_COOLDOWN := 4.0
const LEAP_DAMAGE := 15.0
## Bile spitter.
const SPIT_MIN_M := 7.0
const SPIT_MAX_M := 16.0
const SPIT_WINDUP := 0.8
const SPIT_COOLDOWN := 4.0

@export var kind := Kind.WARRIOR
## 0..100 hearing sensitivity: hears sounds of at least (100 - hearing) loudness.
@export var hearing := 90.0
@export var hearing_recovery := 4.0

var hp := 100.0
var max_hp := 100.0
var weight := 100.0
var radius := 15.0
var state := State.WANDER
var pack_id := -1
var leader: Terminid = null
var hearing_now := 90.0
var wander_speed := 1.0
var run_speed := 4.0
## Absolute heading change of the last physics step (rad), for tests.
var last_turn := 0.0

var _cfg: Dictionary
var _pack_offset := Vector2.ZERO
var _recover_t := 0.0
var _stun_meter := 0.0
var _stun_t := 0.0
var _goal := Vector2.ZERO
var _wander_time := 0.0
var _attack_t := 0.0
var _struck := false
var _cooldown := 0.0
var _special_cd := 2.0
var _special_t := 0.0
var _leap_dir := Vector2.UP
var _stagger := 0.0
var _steer := Vector2.UP
var _steer_to := Vector2.UP
var _detour := 0
var _detour_time := 0.0
var _tick := 0
var _dead_t := 0.0
var _flash := 0.0
var _numbers: Array[Dictionary] = []
## Graphics: seconds since the last hit, ricochet icon timer, seconds spent engaged.
var _dmg_t := 99.0
var _bounce_t := 0.0
var _aware_t := 0.0
## Awareness: level, suspicion meter 0..1, where the last cue was, seconds without cues, LOS dwell.
var level := Awareness.Level.UNAWARE
var suspicion := 0.0
var _cue_pos := Vector2.ZERO
var _quiet_t := 0.0
var _dwell := 0.0
var _call_t := 0.0
var _think_acc := 0.0
var _mission: Node
var _idle_t := 4.0
var _hurt_snd := 0.0
var _player: CharacterBody2D
var _col: CollisionShape2D
## Cadence: perception + steering rays run when _think_t runs out (phase differs per enemy).
var _think_t := 0.0
var _los := false
var _sep := Vector2.ZERO
var _sleep_acc := 0.0
var _turn := 0.0
var _rig: BugRig
var _tele: Node2D
var _bb: Node2D
var _tele_on := false
var _bb_sig := 0
var _lod_acc := 0.0
var _lod_phase := 0


func _ready() -> void:
	_cfg = KINDS[kind]
	max_hp = _cfg.hp
	hp = max_hp
	weight = _cfg.weight
	radius = _cfg.radius * Game.VISUAL_SCALE # drawn (and colliding) bigger; ranges unchanged
	hearing_now = hearing
	add_to_group("terminids")
	add_to_group("enemies")
	add_to_group("concealable")
	Enemies.add(self)
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 2 # actors: block bullets and movement, not sight
	collision_mask = 3
	_col = CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = radius
	_col.shape = shape
	add_child(_col)
	_tick = randi() % 6
	_think_t = randf() * THINK_FAR
	_lod_phase = randi() % 4
	_idle_t = randf_range(2.0, 9.0)
	rotation = randf() * TAU
	_player = get_tree().get_first_node_in_group("player")
	var walk: float = (_player.move_speed if _player else 180.0) / PX
	wander_speed = walk * _cfg.wander
	run_speed = walk * _cfg.run
	_rig = BugRig.make(kind, radius / 15.0)
	add_child(_rig)
	_tele = Enemies.make_overlay(self, _draw_tele)
	_bb = Enemies.make_overlay(self, _draw_bb)
	_bb.scale = Vector2.ONE * Game.BILLBOARD_SCALE
	_new_wander()


static func make(k: Kind) -> Terminid:
	var t := Terminid.new()
	t.kind = k
	return t


## Weighted random kind for a pack (mostly scavengers and warriors).
static func random_kind(spitters := true) -> Kind:
	var r := randf()
	if r < 0.35:
		return Kind.SCAVENGER
	if r < 0.75:
		return Kind.WARRIOR
	if r < 0.9 or not spitters:
		return Kind.HUNTER
	return Kind.BILE_SPITTER


## Spawn a pack around `center` under `parent`. `kinds` (optional) picks kinds per bug.
static func spawn_pack(parent: Node, center: Vector2, size: int, pack: int, is_free: Callable, kinds: Array = []) -> Array[Terminid]:
	var out: Array[Terminid] = []
	var lead: Terminid = null
	for attempt in size * 6:
		if out.size() >= size:
			break
		var p := center if out.is_empty() else center + Vector2.from_angle(randf() * TAU) * randf_range(40.0, 140.0) * Vis.VISUAL_SCALE
		if not is_free.call(p):
			continue
		var k: Kind = kinds[out.size() % kinds.size()] if not kinds.is_empty() else random_kind()
		var t := Terminid.make(k)
		t.position = p
		parent.add_child(t)
		if lead == null:
			lead = t
		t.join_pack(pack, lead)
		out.append(t)
	return out


func is_dead() -> bool:
	return state == State.DEAD


## Chasing / attacking (used for the combat music and the HUD).
func is_alerted() -> bool:
	return state != State.DEAD and level == Awareness.Level.ALERT


func kind_name() -> String:
	var cfg: Dictionary = _cfg if not _cfg.is_empty() else KINDS[kind]
	return cfg.get("name", "Bug")


## Max heading change per second (rad) from the kind's turn rate.
func turn_cap() -> float:
	return deg_to_rad(_cfg.turn)


## Scripted nudge (spawned patrols / packs): chase=true makes this bug ALERT at once (no call),
## else it only becomes suspicious of `pos` and investigates it.
func alert_to(pos: Vector2, chase := false) -> void:
	if state == State.DEAD or level == Awareness.Level.ALERT:
		return
	if chase and _player:
		_become_alert(false)
	else:
		add_suspicion(0.5, pos)


func hear(pos: Vector2, loudness: float, falloff_pct: float) -> void:
	hear_sound(pos, loudness, falloff_pct, Awareness.Sound.GUNFIRE)


## A sound: suspicion by distance (Awareness.sound_gain, hard caps per kind); never alert by itself.
func hear_sound(pos: Vector2, loudness: float, falloff_pct: float, kind: int) -> void:
	if state == State.DEAD or level == Awareness.Level.ALERT:
		return
	var meters := global_position.distance_to(pos) / PX
	var gain := Awareness.sound_gain(kind, loudness, meters)
	if gain <= 0.0:
		return
	var heard := FirearmStats.loudness_at(loudness, falloff_pct, meters)
	if heard > DEAFEN_LEVEL:
		hearing_now = maxf(hearing_now - (heard - DEAFEN_LEVEL) * DEAFEN_RATE, MIN_HEARING)
	gain *= hearing_now / maxf(hearing, 1.0)
	var vague := lerpf(6.0, 1.0, clampf(gain / 0.6, 0.0, 1.0))
	add_suspicion(gain, pos + Vector2(randf_range(-vague, vague), randf_range(-vague, vague)) * PX)


## Raise the meter (absolute = set to at least `amount`, used by spreading and sightings). A
## suspicious bug turns and walks to investigate `pos`.
func add_suspicion(amount: float, pos: Vector2, absolute := false) -> void:
	if state == State.DEAD or level == Awareness.Level.ALERT:
		return
	suspicion = maxf(suspicion, amount) if absolute else clampf(suspicion + amount, 0.0, 1.0)
	_quiet_t = 0.0
	_cue_pos = pos
	_update_level()
	if suspicion >= Awareness.SUSPICIOUS_AT and (state == State.WANDER or state == State.SEARCH):
		state = State.SEARCH
		_goal = pos


func _update_level() -> void:
	if level == Awareness.Level.ALERT:
		return
	if suspicion >= Awareness.SUSPICIOUS_AT or (level == Awareness.Level.SUSPICIOUS and suspicion >= Awareness.UNAWARE_BELOW):
		level = Awareness.Level.SUSPICIOUS
	else:
		level = Awareness.Level.UNAWARE


## Player identified (LOS dwell) or hit by the player: this bug alone is alert. Then it may call
## reinforcements (a visible ~2 s action, see _start_call).
func _become_alert(can_call: bool) -> void:
	if state == State.DEAD or level == Awareness.Level.ALERT:
		return
	level = Awareness.Level.ALERT
	suspicion = 1.0
	_dwell = 0.0
	_aware_t = 0.0
	Sfx.play("bug_alert", global_position, -2.0)
	if state in [State.WANDER, State.SEARCH]:
		state = State.CHASE
	if _player:
		_goal = _player.global_position
	if can_call and state == State.CHASE and _mission_node() != null and _mission_node().request_call(self):
		_start_call()


func _mission_node() -> Node:
	if _mission == null or not is_instance_valid(_mission):
		_mission = get_tree().get_first_node_in_group("mission")
	return _mission


func _start_call() -> void:
	state = State.CALL
	_call_t = 0.0
	Sfx.play("bug_alert", global_position, 3.0)


func _finish_call() -> void:
	state = State.CHASE
	if _mission_node() != null:
		_mission_node().finish_call(self)


## The caller was killed or staggered: no breach.
func _cancel_call() -> void:
	if state == State.CALL:
		state = State.CHASE
	if _mission_node() != null:
		_mission_node().cancel_call(self)


func take_hit(hit: Dictionary) -> void:
	if state == State.DEAD:
		return
	var crit := Combat.is_crit(hit, global_position + Vector2.UP.rotated(rotation) * radius * 0.6, _cfg.head, 30.0)
	var armor: int = 0 if crit else _cfg.armor
	var dmg: float = hit.damage * FirearmStats.armor_factor(hit.armor_penetration, armor) * (_cfg.crit if crit else 1.0)
	hp -= dmg
	_flash = 0.1
	_dmg_t = 0.0
	var armored: bool = armor > 0 and dmg < hit.damage * 0.5
	var hit_pos: Vector2 = hit.get("pos", global_position)
	if armored:
		_bounce_t = 0.7
		Fx.spark(self, hit_pos, hit.dir)
	else:
		Fx.splat(self, hit_pos, hit.dir, BLOOD[kind], crit or hit.get("explosive", false))
	if _hurt_snd <= 0.0:
		_hurt_snd = 0.15
		Sfx.play("hit_armor" if armored else "hit_flesh", global_position, -6.0)
		if hp > 0.0:
			Sfx.play("bug_hurt", global_position, -4.0)
	_apply_stagger(hit, crit)
	_numbers.append({"text": ("CRIT %d" if crit else "%d") % roundi(dmg), "t": 0.0, "crit": crit, "x": randf_range(-10, 10)})
	if hp <= 0.0:
		_die(hit.dir)
		return
	if level != Awareness.Level.ALERT and _player:
		_become_alert(true)


func _apply_stagger(hit: Dictionary, crit: bool) -> void:
	var impact: float = hit.get("stagger", 0.0) * (CRIT_STAGGER_MULT if crit else 1.0) / weight
	velocity += (hit.dir as Vector2) * impact * KNOCKBACK
	_stagger = maxf(_stagger, impact * SLOW_PER_IMPACT)
	if (state == State.ATTACK and not _struck or state == State.SPIT) and impact >= INTERRUPT_IMPACT:
		state = State.CHASE
		_cooldown = _cfg.cooldown
	if state == State.CALL and impact >= INTERRUPT_IMPACT:
		_cancel_call()
	_stun_meter += impact
	if _stun_meter >= 1.0:
		_stun_meter = 0.0
		_stun_t = STUN_TIME
		if state == State.CALL:
			_cancel_call()
		if state in [State.ATTACK, State.SPIT, State.LEAP]:
			state = State.CHASE


func is_stunned() -> bool:
	return _stun_t > 0.0


# --- Frame loop ---------------------------------------------------------------------

## Rig animation + overlays: once per rendered frame, only for enemies that are visible
## (not concealed by the sight cone) and near the player; dead ones play the death curl, freeze
## into one static corpse sprite and stop processing.
func _process(delta: float) -> void:
	if not _numbers.is_empty():
		for n in _numbers:
			n.t += delta
		_numbers = _numbers.filter(func(n): return n.t < 0.9)
	if state == State.DEAD:
		_process_dead(delta)
		return
	_update_overlays()
	if not visible or _rig == null:
		return
	# Rig LOD: full rate near the player, every 2nd / 4th frame further out, none beyond RIG_RANGE_M.
	var every := 1
	if _player != null:
		var d2 := global_position.distance_squared_to(_player.global_position)
		if d2 > RIG_RANGE_PX2:
			return
		every = 1 if d2 < RIG_LOD1_PX2 else (2 if d2 < RIG_LOD2_PX2 else 4)
	_lod_acc += delta
	if every > 1 and (Engine.get_process_frames() + _lod_phase) % every != 0:
		return
	delta = _lod_acc
	_lod_acc = 0.0
	var mode := BugRig.M.IDLE
	var k := 0.0
	match state:
		State.ATTACK:
			mode = BugRig.M.ATTACK
			k = clampf(_attack_t / _cfg.windup, 0.0, 1.0)
		State.LEAP:
			mode = BugRig.M.LEAP
		State.SPIT:
			mode = BugRig.M.SPIT
			k = clampf(_special_t / SPIT_WINDUP, 0.0, 1.0)
		State.CALL:
			mode = BugRig.M.CALL
			k = clampf(_call_t / Awareness.CALL_TIME, 0.0, 1.0)
	if _stun_t > 0.0:
		mode = BugRig.M.STUN
	var move := clampf(velocity.length() / (run_speed * PX), 0.0, 1.0)
	_rig.animate(delta, move, _turn, mode, k, level == Awareness.Level.ALERT, _flash, hp < max_hp * 0.5)


func _process_dead(delta: float) -> void:
	if _rig != null and _rig.corpse_sprite == null:
		_rig.animate(delta, 0.0, 0.0, BugRig.M.DEAD, 0.0, false, 0.0, false)
		if _rig.settled():
			_rig.become_corpse()
			Enemies.add_corpse(self)
	_update_overlays()
	if _numbers.is_empty() and _rig != null and _rig.corpse_sprite != null:
		set_process(false)


func _physics_process(delta: float) -> void:
	_flash = maxf(_flash - delta, 0.0)
	_dmg_t += delta
	_bounce_t = maxf(_bounce_t - delta, 0.0)
	_aware_t = _aware_t + delta if _engaged() else 0.0
	_hurt_snd = maxf(_hurt_snd - delta, 0.0)
	_idle_t -= delta
	if _idle_t <= 0.0:
		_idle_t = randf_range(5.0, 12.0)
		if _player and global_position.distance_to(_player.global_position) < 22.0 * PX and state in [State.WANDER, State.SEARCH]:
			Sfx.play("bug_chitter", global_position, -8.0)
	_cooldown = maxf(_cooldown - delta, 0.0)
	_special_cd = maxf(_special_cd - delta, 0.0)
	_stagger = maxf(_stagger - delta, 0.0)
	_stun_meter = maxf(_stun_meter - STUN_DECAY * delta, 0.0)
	if _stun_t > 0.0:
		_stun_t -= delta
		velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
		move_and_slide()
		return
	hearing_now = minf(hearing_now + hearing_recovery * delta, hearing)
	var d2 := global_position.distance_squared_to(_player.global_position) if _player != null else 0.0
	var near := d2 < pow(NEAR_M * PX, 2)
	# Far, idle bugs only simulate every SLEEP_EVERY-th tick (with the accumulated delta).
	if state == State.WANDER and _player != null and d2 > pow(SLEEP_M * PX, 2):
		_sleep_acc += delta
		_tick += 1
		if _tick % SLEEP_EVERY != 0:
			return
		delta = _sleep_acc
		_sleep_acc = 0.0
	_think_acc += delta
	_think_t -= delta
	if _think_t <= 0.0:
		_think_t = maxf(_think_t + (THINK_NEAR if near else THINK_FAR), 0.0)
		var dt := _think_acc
		_think_acc = 0.0
		_think(near, dt)

	if state == State.LEAP:
		_update_leap(delta)
		return

	var speed := 0.0
	var face := _steer
	var to_player := (_player.global_position - global_position) if _player else Vector2.ZERO
	var dist_m := to_player.length() / PX
	var forward := Vector2.UP.rotated(rotation)
	match state:
		State.WANDER:
			_wander_time -= delta
			if _wander_time <= 0.0 or global_position.distance_to(_goal) < 20.0:
				_new_wander()
			speed = wander_speed
			if _is_follower() and global_position.distance_to(_goal) > 3.0 * PX:
				speed *= 1.6
		State.CHASE:
			speed = run_speed
			if _player and _can_reach_player():
				_start_attack()
			elif kind == Kind.HUNTER and _special_cd <= 0.0 and dist_m >= LEAP_MIN_M and dist_m <= LEAP_MAX_M \
					and absf(forward.angle_to(to_player)) < 0.45 and _los:
				_start_leap(to_player)
			elif kind == Kind.BILE_SPITTER and _special_cd <= 0.0 and dist_m >= SPIT_MIN_M and dist_m <= SPIT_MAX_M \
					and _los:
				state = State.SPIT
				_special_t = 0.0
			elif kind == Kind.BILE_SPITTER and dist_m < SPIT_MIN_M * 0.8 and dist_m > 2.0:
				# Too close: back off to spitting range.
				_goal = global_position - to_player.normalized() * 4.0 * PX
		State.SEARCH:
			speed = run_speed * (0.8 if level == Awareness.Level.ALERT else 0.5) # investigating is a walk
			if global_position.distance_to(_goal) < 30.0:
				_new_wander()
		State.ATTACK:
			speed = 0.6
			_update_attack(delta)
			if _player:
				face = to_player.normalized()
		State.SPIT:
			speed = 0.0
			face = to_player.normalized()
			_special_t += delta
			if _special_t >= SPIT_WINDUP:
				_spit()
		State.RECOVER:
			speed = 0.0
			_recover_t -= delta
			if _recover_t <= 0.0:
				state = State.CHASE
		State.CALL:
			# Stands, rears up and calls for reinforcements; killed / staggered = cancelled.
			speed = 0.0
			face = to_player.normalized()
			_call_t += delta
			if _call_t >= Awareness.CALL_TIME:
				_finish_call()

	if state in [State.WANDER, State.CHASE, State.SEARCH]:
		# Follow the last steering direction smoothly (the ray fan only runs every think).
		_steer = _steer.slerp(_steer_to, minf(delta * 12.0, 1.0))
		face = _steer

	var before := rotation
	var want := face.angle() + PI / 2.0
	var max_step := deg_to_rad(_cfg.turn) * delta
	rotation += clampf(wrapf(want - rotation, -PI, PI), -max_step, max_step)
	var dr := wrapf(rotation - before, -PI, PI)
	last_turn = absf(dr)
	_turn = lerpf(_turn, dr / maxf(delta, 0.0001), minf(delta * 10.0, 1.0))
	forward = Vector2.UP.rotated(rotation)
	var along := clampf(forward.dot(_steer), 0.2, 1.0) if state != State.ATTACK else 1.0
	if _stagger > 0.0:
		speed *= 0.25
	if state == State.WANDER and not _is_follower() and fmod(_wander_time, 4.0) < 1.2:
		speed = 0.0
	var target := forward * speed * PX * along
	if near and state != State.ATTACK:
		target += _sep * SEP_SPEED * PX
	velocity = velocity.move_toward(target, ACCEL * delta)
	move_and_slide()


## Perception (one LOS ray), the pack leader and steering (the ray fan): the expensive part,
## run at THINK_NEAR / THINK_FAR instead of every frame.
func _think(near: bool, dt: float) -> void:
	_awareness_tick(dt)
	_perceive(dt)
	_follow_leader()
	if state in [State.WANDER, State.CHASE, State.SEARCH]:
		_steer_to = _steer_dir((_goal - global_position).normalized())
	_sep = Enemies.separation(self, radius) if near else Vector2.ZERO


func _start_leap(to_player: Vector2) -> void:
	Sfx.play("bug_attack", global_position, -4.0)
	state = State.LEAP
	_special_t = 0.0
	_leap_dir = to_player.normalized()
	_struck = false


func _update_leap(delta: float) -> void:
	_special_t += delta
	velocity = _leap_dir * LEAP_SPEED * PX
	move_and_slide()
	if not _struck and _player and global_position.distance_to(_player.global_position) < radius + 24.0:
		_struck = true
		_player.take_damage(LEAP_DAMAGE, global_position)
		if _player.has_method("apply_slow"):
			_player.apply_slow(1.5)
	if _special_t >= LEAP_TIME or get_slide_collision_count() > 0:
		_special_cd = LEAP_COOLDOWN
		velocity *= 0.3
		_recover_t = 0.5
		state = State.RECOVER


func _spit() -> void:
	Sfx.play("bile_spit", global_position, -4.0)
	_special_cd = SPIT_COOLDOWN
	state = State.CHASE
	var proj := get_tree().get_first_node_in_group("projectiles")
	if proj and _player:
		var miss := Vector2.from_angle(randf() * TAU) * randf_range(0.0, 1.2) * PX
		proj.spawn_bile(global_position + Vector2.UP.rotated(rotation) * radius, _player.global_position + miss)


## Decay without cues, and spreading suspicion to bugs nearby (never the alert itself).
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


## Sees the player? Only identification (LOS in the sight cone for a dwell time that grows with
## distance) makes this bug ALERT; peripheral / half sightings just raise suspicion.
func _perceive(dt: float) -> void:
	if not _player or _player.get("dead"):
		_los = false
		if level == Awareness.Level.ALERT:
			_lose_player()
			_new_wander()
		return
	var to := _player.global_position - global_position
	var dist := to.length()
	var forward := Vector2.UP.rotated(rotation)
	var in_range: bool = dist <= _cfg.sight * PX
	var in_cone: bool = in_range and absf(forward.angle_to(to)) <= deg_to_rad(_cfg.fov / 2.0)
	var touching := dist <= 1.5 * PX
	var peripheral: bool = not in_cone and not touching and dist <= _cfg.sight * 1.4 * PX
	var alert := level == Awareness.Level.ALERT
	var want_los: bool = in_cone or touching or peripheral or (alert and (kind == Kind.HUNTER or kind == Kind.BILE_SPITTER))
	_los = want_los and _line_of_sight(_player)
	var seen := (in_cone or touching) and _los
	if alert:
		if seen:
			if state == State.CHASE:
				_goal = _player.global_position
		elif state == State.CHASE:
			_lose_player()
		return
	if seen:
		var need := Awareness.dwell_time(dist / PX)
		_dwell += dt
		var frac := clampf(_dwell / need, 0.0, 1.0)
		add_suspicion(Awareness.SUSPICIOUS_AT + (0.9 - Awareness.SUSPICIOUS_AT) * frac, _player.global_position, true)
		if _dwell >= need:
			_become_alert(true)
	else:
		_dwell = maxf(_dwell - dt * 2.0, 0.0)
		if peripheral and _los:
			add_suspicion(0.5 * dt, _player.global_position)


## Lost the player: still suspicious for a while (meter decays over ~8 s), searching.
func _lose_player() -> void:
	level = Awareness.Level.SUSPICIOUS
	suspicion = 1.0
	_quiet_t = 0.0
	_dwell = 0.0
	if state == State.CHASE:
		state = State.SEARCH


func _line_of_sight(target: CollisionObject2D) -> bool:
	var q := PhysicsRayQueryParameters2D.create(global_position, target.global_position, 1)
	q.exclude = [get_rid()]
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and hit.collider == target

func _steer_dir(desired: Vector2) -> Vector2:
	var space := get_world_2d().direct_space_state
	var exclude := [get_rid()]
	if state == State.CHASE and _player:
		exclude.append(_player.get_rid())
	var dirs: Array[Vector2] = []
	var dangers: Array[float] = []
	for i in RAYS:
		var d := Vector2.from_angle(TAU * i / RAYS)
		var q := PhysicsRayQueryParameters2D.create(global_position, global_position + d * (radius + FEELER))
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		var danger := 0.0
		if not hit.is_empty():
			var free_px := global_position.distance_to(hit.position) - radius
			danger = 1.0 - clampf(free_px / FEELER, 0.0, 1.0)
		dirs.append(d)
		dangers.append(danger)
	var ahead := _danger_toward(desired, dirs, dangers)
	_detour_time -= THINK_NEAR
	if ahead > 0.4:
		if _detour == 0:
			var left := _danger_toward(desired.rotated(-PI / 2.0), dirs, dangers)
			var right := _danger_toward(desired.rotated(PI / 2.0), dirs, dangers)
			_detour = -1 if left < right or (left == right and randf() < 0.5) else 1
			_detour_time = 3.0
	elif _detour_time < 2.5:
		_detour = 0
	if _detour_time <= 0.0:
		_detour = 0
	var side := desired.rotated(_detour * PI / 2.0)
	var best := desired
	var best_score := -INF
	for i in RAYS:
		var d := dirs[i]
		var score := d.dot(desired) + 0.25 * d.dot(_steer) - dangers[i] * 2.0
		if _detour != 0:
			score += 0.7 * d.dot(side)
		if score > best_score:
			best_score = score
			best = d
	return best


func _danger_toward(d: Vector2, dirs: Array[Vector2], dangers: Array[float]) -> float:
	var best_i := 0
	var best_dot := -2.0
	for i in dirs.size():
		var dd := dirs[i].dot(d)
		if dd > best_dot:
			best_dot = dd
			best_i = i
	return dangers[best_i]


func _new_wander() -> void:
	state = State.WANDER
	_wander_time = randf_range(4.0, 9.0)
	if _is_follower():
		_goal = leader.global_position + _pack_offset
	else:
		_goal = global_position + Vector2.from_angle(randf() * TAU) * randf_range(3.0, 10.0) * PX


func join_pack(id: int, lead: Terminid) -> void:
	pack_id = id
	leader = lead if lead != self else null
	_pack_offset = Vector2.from_angle(randf() * TAU) * randf_range(1.0, 2.5) * PX


func _is_follower() -> bool:
	return leader != null and is_instance_valid(leader) and not leader.is_dead()


func _follow_leader() -> void:
	if state == State.WANDER and _is_follower():
		_goal = leader.global_position + _pack_offset


func _engaged() -> bool:
	return state in [State.CHASE, State.ATTACK, State.RECOVER, State.LEAP, State.SPIT, State.CALL]


func _edge_distance_to_player() -> float:
	return global_position.distance_to(_player.global_position) - radius - 16.0 * Game.VISUAL_SCALE


func _can_reach_player() -> bool:
	return _cooldown <= 0.0 and _edge_distance_to_player() <= _cfg.reach * PX


func _start_attack() -> void:
	Sfx.play("bug_attack", global_position, -4.0)
	state = State.ATTACK
	_attack_t = 0.0
	_struck = false


func _update_attack(delta: float) -> void:
	_attack_t += delta
	if not _struck and _attack_t >= _cfg.windup:
		_struck = true
		var to := _player.global_position - global_position
		var forward := Vector2.UP.rotated(rotation)
		var in_arc := absf(forward.angle_to(to)) <= deg_to_rad(70.0)
		if in_arc and _edge_distance_to_player() <= (_cfg.reach + 0.25) * PX:
			_player.take_damage(_cfg.damage, global_position)
	if _attack_t >= _cfg.windup + 0.25:
		_cooldown = _cfg.cooldown
		_recover_t = _cfg.recover
		state = State.RECOVER


func _die(dir: Vector2) -> void:
	if state == State.CALL:
		_cancel_call()
	state = State.DEAD
	Game.add_stat("kills")
	Fx.death(self, global_position, BLOOD[kind], radius * 1.25)
	Sfx.play("bug_death", global_position, -2.0)
	get_tree().call_group("mission", "on_kill", self)
	remove_from_group("terminids")
	remove_from_group("enemies")
	Enemies.remove(self)
	_col.set_deferred("disabled", true)
	z_index = -1
	velocity = Vector2.ZERO
	rotation = (dir as Vector2).angle() + PI / 2.0 + randf_range(-0.6, 0.6)
	set_physics_process(false)
	_tele.visible = false
	get_tree().create_timer(40.0, false).timeout.connect(queue_free)


# --- Overlays (the body itself is a rig; nothing here re-records per frame) ----------------

func _update_overlays() -> void:
	var dead := state == State.DEAD
	_tele_on = not dead and ((state == State.ATTACK and not _struck) or state == State.SPIT or state == State.CALL or is_stunned())
	if _tele_on:
		_tele.visible = true
		_tele.queue_redraw()
	elif _tele.visible:
		_tele.visible = false
	var heavy: bool = kind == Kind.BILE_SPITTER
	var icon := _icon_kind()
	var bar_a := _bar_alpha(heavy)
	if not dead and (bar_a > 0.0 or icon != EnemyUi.Icon.NONE or _bounce_t > 0.0) or not _numbers.is_empty():
		_bb.visible = true
		_bb.global_rotation = -Enemies.cam_rot(self)
		var sig := int(clampf(hp / max_hp, 0.0, 1.0) * 48.0) | (int(bar_a * 8.0) << 8) | (icon << 12) | (int(_icon_pop() * 8.0) << 14) \
			| (int(_bounce_t * 30.0) << 22) | (int(suspicion * 16.0) << 27)
		if not _numbers.is_empty():
			sig = randi()
		if sig != _bb_sig:
			_bb_sig = sig
			_bb.queue_redraw()
	elif _bb.visible:
		_bb.visible = false
		_bb_sig = -1


func _bar_alpha(heavy: bool) -> float:
	if state == State.DEAD:
		return 0.0
	if heavy and (_engaged() or hp < max_hp):
		return 1.0
	return clampf((3.5 - _dmg_t) / 0.8, 0.0, 1.0)


func _icon_kind() -> int:
	if state == State.DEAD:
		return EnemyUi.Icon.NONE
	if level == Awareness.Level.ALERT or state == State.CALL:
		return EnemyUi.Icon.ALERT if (_aware_t < 2.5 or kind == Kind.BILE_SPITTER or state == State.CALL) else EnemyUi.Icon.NONE
	if level == Awareness.Level.SUSPICIOUS:
		return EnemyUi.Icon.SUSPICIOUS
	return EnemyUi.Icon.NONE


func _icon_pop() -> float:
	return 1.0 + 0.5 * clampf(1.0 - _aware_t / 0.35, 0.0, 1.0) if level == Awareness.Level.ALERT else 1.0


## Melee wind-up arc, bile target circle, stun stars (enemy-local frame).
func _draw_tele() -> void:
	var s := radius / 15.0
	if state == State.ATTACK and not _struck:
		var k := clampf(_attack_t / _cfg.windup, 0.0, 1.0)
		var reach_px: float = radius + (_cfg.reach + 0.25) * PX
		var a0 := -PI / 2.0 - deg_to_rad(70.0)
		var a1 := -PI / 2.0 + deg_to_rad(70.0)
		_tele.draw_arc(Vector2.ZERO, reach_px, a0, a1, 14, Color(1, 0.25, 0.1, 0.25 + 0.5 * k), 3.0)
		_tele.draw_arc(Vector2.ZERO, reach_px * k, a0, a1, 14, Color(1, 0.3, 0.1, 0.35), 2.0)
	if state == State.SPIT and _player != null:
		var tp := to_local(_player.global_position)
		var k := clampf(_special_t / SPIT_WINDUP, 0.0, 1.0)
		var rr := 1.8 * PX
		_tele.draw_circle(tp, rr, Color(0.6, 0.85, 0.15, 0.1 + 0.18 * k))
		_tele.draw_arc(tp, rr, 0.0, TAU, 32, Color(0.75, 1.0, 0.25, 0.8), 2.5)
		_tele.draw_arc(tp, rr * (1.0 - k * 0.85), 0.0, TAU, 28, Color(1.0, 0.95, 0.3, 0.9), 3.0)
		var from := Vector2(0, -radius)
		var steps := 10
		for i in steps:
			if i % 2 == 0:
				var a := from.lerp(tp, float(i) / steps)
				var b := from.lerp(tp, float(i + 1) / steps)
				_tele.draw_line(a, b, Color(0.8, 1.0, 0.3, 0.45), 2.0)
	if state == State.CALL:
		# Pulsing orange pheromone ring + call progress.
		var kk := clampf(_call_t / Awareness.CALL_TIME, 0.0, 1.0)
		var ph := fmod(_call_t * 1.6, 1.0)
		var base := radius * 1.3
		_tele.draw_circle(Vector2.ZERO, base * (1.0 + 2.2 * ph), Color(1.0, 0.55, 0.1, 0.16 * (1.0 - ph)))
		_tele.draw_arc(Vector2.ZERO, base * (1.0 + 2.2 * ph), 0.0, TAU, 40, Color(1.0, 0.6, 0.15, 0.85 * (1.0 - ph)), 3.0 * Vis.VISUAL_SCALE)
		_tele.draw_arc(Vector2.ZERO, base, 0.0, TAU, 40, Color(1.0, 0.55, 0.1, 0.35), 2.0 * Vis.VISUAL_SCALE)
		_tele.draw_arc(Vector2.ZERO, base * 1.12, -PI / 2.0, -PI / 2.0 + TAU * kk, 40, Color(1.0, 0.85, 0.3, 0.9), 3.5 * Vis.VISUAL_SCALE)
	if is_stunned():
		var a := Time.get_ticks_msec() * 0.006
		for i in 3:
			_tele.draw_circle(Vector2(0, -11.0 * s) + Vector2.from_angle(a + i * TAU / 3.0) * 9.0 * s, 1.6 * s, UiStyle.YELLOW)


## Screen-aligned: HP bar, awareness icon, ricochet shield, damage numbers.
func _draw_bb() -> void:
	var rb := radius / Game.BILLBOARD_SCALE
	var top := -rb - 14.0
	var heavy: bool = kind == Kind.BILE_SPITTER
	var a := _bar_alpha(heavy)
	if a > 0.0:
		EnemyUi.hp_bar(_bb, top - 4.0, 40.0 if heavy else 28.0, 6.0, hp / max_hp, a, heavy)
		top -= 10.0
	var icon := _icon_kind()
	if icon != EnemyUi.Icon.NONE:
		EnemyUi.icon(_bb, icon, Vector2(0, top - 8.0), 9.0, suspicion, _icon_pop())
	if _bounce_t > 0.0:
		var ba := clampf(_bounce_t / 0.3, 0.0, 1.0)
		EnemyUi.shield(_bb, Vector2(rb * 0.9 + 6.0, -rb * 0.5 - (0.7 - _bounce_t) * 22.0), ba)
	if not _numbers.is_empty():
		EnemyUi.numbers(_bb, _numbers, -rb - 12.0, Color(1, 0.35, 0.2), 16)
