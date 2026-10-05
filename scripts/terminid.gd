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
## - Getting shot / spotting the player alerts its pack and reports to the mission
##   (which may call a bug breach).
## - Stagger: impact = weapon stagger (x1.5 crit) / weight -> knockback, slowdown,
##   wind-up interrupt, stun meter.
## - Far from the player it thinks/steers less often (performance).

enum Kind { SCAVENGER, WARRIOR, HUNTER, BILE_SPITTER }
enum State { WANDER, CHASE, SEARCH, ATTACK, RECOVER, LEAP, SPIT, DEAD }

const LOD_FAR_M := 30.0
const SLEEP_M := 55.0
const SLEEP_EVERY := 4
const KNOCKBACK := 450.0
const SLOW_PER_IMPACT := 1.2
const INTERRUPT_IMPACT := 0.25
const STUN_DECAY := 0.5
const STUN_TIME := 0.9
const CRIT_STAGGER_MULT := 1.5
const PACK_ALERT_M := 20.0
const PX := Firearm.PX_PER_M
const RAYS := 16
const FEELER := 60.0
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
var _detour := 0
var _detour_time := 0.0
var _tick := 0
var _walk_phase := 0.0
var _dead_t := 0.0
var _flash := 0.0
var _numbers: Array[Dictionary] = []
## Graphics: seconds since the last hit, ricochet icon timer, seconds spent engaged, draw scale.
var _dmg_t := 99.0
var _bounce_t := 0.0
var _aware_t := 0.0
var _base := Transform2D.IDENTITY
var _idle_t := 4.0
var _hurt_snd := 0.0
var _player: CharacterBody2D
var _col: CollisionShape2D


func _ready() -> void:
	_cfg = KINDS[kind]
	max_hp = _cfg.hp
	hp = max_hp
	weight = _cfg.weight
	radius = _cfg.radius
	hearing_now = hearing
	add_to_group("terminids")
	add_to_group("enemies")
	add_to_group("concealable")
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 2 # actors: block bullets and movement, not sight
	collision_mask = 3
	_col = CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = radius
	_col.shape = shape
	add_child(_col)
	_tick = randi() % 6
	_idle_t = randf_range(2.0, 9.0)
	_walk_phase = randf() * TAU
	rotation = randf() * TAU
	_player = get_tree().get_first_node_in_group("player")
	var walk: float = (_player.move_speed if _player else 180.0) / PX
	wander_speed = walk * _cfg.wander
	run_speed = walk * _cfg.run
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
		var p := center if out.is_empty() else center + Vector2.from_angle(randf() * TAU) * randf_range(40.0, 140.0)
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
	return _engaged()


func kind_name() -> String:
	return _cfg.name


## Send it somewhere: chase=true runs straight at the player, else it investigates pos.
func alert_to(pos: Vector2, chase := false) -> void:
	if state == State.DEAD or _engaged():
		return
	if chase and _player:
		_engage(_player.global_position)
	else:
		state = State.SEARCH
		_goal = pos


func hear(pos: Vector2, loudness: float, falloff_pct: float) -> void:
	if state == State.DEAD:
		return
	var level := FirearmStats.loudness_at(loudness, falloff_pct, global_position.distance_to(pos) / PX)
	var heard := level >= 100.0 - hearing_now
	if level > DEAFEN_LEVEL:
		hearing_now = maxf(hearing_now - (level - DEAFEN_LEVEL) * DEAFEN_RATE, MIN_HEARING)
	if not heard or _engaged():
		return
	state = State.SEARCH
	var vague := lerpf(6.0, 1.0, clampf(level / 60.0, 0.0, 1.0))
	_goal = pos + Vector2(randf_range(-vague, vague), randf_range(-vague, vague)) * PX


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
	if not _engaged() and _player:
		_engage(_player.global_position)


func _apply_stagger(hit: Dictionary, crit: bool) -> void:
	var impact: float = hit.get("stagger", 0.0) * (CRIT_STAGGER_MULT if crit else 1.0) / weight
	velocity += (hit.dir as Vector2) * impact * KNOCKBACK
	_stagger = maxf(_stagger, impact * SLOW_PER_IMPACT)
	if (state == State.ATTACK and not _struck or state == State.SPIT) and impact >= INTERRUPT_IMPACT:
		state = State.CHASE
		_cooldown = _cfg.cooldown
	_stun_meter += impact
	if _stun_meter >= 1.0:
		_stun_meter = 0.0
		_stun_t = STUN_TIME
		if state in [State.ATTACK, State.SPIT, State.LEAP]:
			state = State.CHASE


func is_stunned() -> bool:
	return _stun_t > 0.0


func _physics_process(delta: float) -> void:
	_flash = maxf(_flash - delta, 0.0)
	_dmg_t += delta
	_bounce_t = maxf(_bounce_t - delta, 0.0)
	_aware_t = _aware_t + delta if _engaged() else 0.0
	_hurt_snd = maxf(_hurt_snd - delta, 0.0)
	for n in _numbers:
		n.t += delta
	_numbers = _numbers.filter(func(n): return n.t < 0.9)
	if state == State.DEAD:
		_dead_t += delta
		if _dead_t > 40.0:
			queue_free()
		queue_redraw()
		return

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
		queue_redraw()
		return
	hearing_now = minf(hearing_now + hearing_recovery * delta, hearing)
	_tick += 1
	var far := _player != null and global_position.distance_squared_to(_player.global_position) > pow(LOD_FAR_M * PX, 2)
	if state == State.WANDER and _player != null \
			and global_position.distance_squared_to(_player.global_position) > pow(SLEEP_M * PX, 2) \
			and _tick % SLEEP_EVERY != 0:
		return
	if _tick % (15 if far else 5) == 0:
		_perceive()
		_follow_leader()

	if state == State.LEAP:
		_update_leap(delta)
		queue_redraw()
		return

	var speed := 0.0
	var face := _steer
	var to_player := (_player.global_position - global_position) if _player else Vector2.ZERO
	var dist_m := to_player.length() / PX
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
					and _line_of_sight(_player):
				_start_leap(to_player)
			elif kind == Kind.BILE_SPITTER and _special_cd <= 0.0 and dist_m >= SPIT_MIN_M and dist_m <= SPIT_MAX_M \
					and _line_of_sight(_player):
				state = State.SPIT
				_special_t = 0.0
			elif kind == Kind.BILE_SPITTER and dist_m < SPIT_MIN_M * 0.8 and dist_m > 2.0:
				# Too close: back off to spitting range.
				_goal = global_position - to_player.normalized() * 4.0 * PX
		State.SEARCH:
			speed = run_speed * 0.8
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

	if state in [State.WANDER, State.CHASE, State.SEARCH] and _tick % (9 if far else 3) == 0:
		var desired := (_goal - global_position).normalized()
		_steer = _steer.lerp(_steer_dir(desired), 0.5).normalized()
		face = _steer

	var want := face.angle() + PI / 2.0
	var max_step := deg_to_rad(_cfg.turn) * delta
	rotation += clampf(wrapf(want - rotation, -PI, PI), -max_step, max_step)
	var forward := Vector2.UP.rotated(rotation)
	var along := clampf(forward.dot(_steer), 0.2, 1.0) if state != State.ATTACK else 1.0
	if _stagger > 0.0:
		speed *= 0.25
	if state == State.WANDER and not _is_follower() and fmod(_wander_time, 4.0) < 1.2:
		speed = 0.0
	velocity = velocity.move_toward(forward * speed * PX * along, 1100.0 * delta)
	move_and_slide()
	_walk_phase = fmod(_walk_phase + clampf(velocity.length() / (run_speed * PX), 0.0, 1.0) * 2.4 * TAU * delta, TAU)
	queue_redraw()


func _start_leap(to_player: Vector2) -> void:
	Sfx.play("bug_attack", global_position, -4.0)
	state = State.LEAP
	_special_t = 0.0
	_leap_dir = to_player.normalized()
	rotation = _leap_dir.angle() + PI / 2.0
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


func _perceive() -> void:
	if not _player or _player.get("dead"):
		if _engaged():
			_new_wander()
		return
	var to := _player.global_position - global_position
	var dist := to.length()
	var forward := Vector2.UP.rotated(rotation)
	var in_cone: bool = dist <= _cfg.sight * PX and absf(forward.angle_to(to)) <= deg_to_rad(_cfg.fov / 2.0)
	var touching := dist <= 1.5 * PX
	var seen := (in_cone or touching) and _line_of_sight(_player)
	if seen:
		if not _engaged():
			_engage(_player.global_position)
		elif state == State.CHASE:
			_goal = _player.global_position
	elif state == State.CHASE:
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
	_detour_time -= 0.05
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
	return state in [State.CHASE, State.ATTACK, State.RECOVER, State.LEAP, State.SPIT]


func _engage(pos: Vector2) -> void:
	Sfx.play("bug_alert", global_position, -2.0)
	state = State.CHASE
	_goal = pos
	_alert_pack(pos)
	get_tree().call_group("mission", "on_bug_alert", self)


func _alert_pack(pos: Vector2) -> void:
	if pack_id < 0:
		return
	for n in get_tree().get_nodes_in_group("terminids"):
		var other := n as Terminid
		if other == self or other.pack_id != pack_id or other._engaged():
			continue
		if other.global_position.distance_to(global_position) <= PACK_ALERT_M * PX:
			other.state = State.CHASE
			other._goal = pos


func _edge_distance_to_player() -> float:
	return global_position.distance_to(_player.global_position) - radius - 16.0


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
	state = State.DEAD
	Game.add_stat("kills")
	Fx.death(self, global_position, BLOOD[kind], radius * 1.25)
	Sfx.play("bug_death", global_position, -2.0)
	get_tree().call_group("mission", "on_kill", self)
	remove_from_group("terminids")
	remove_from_group("enemies")
	_col.set_deferred("disabled", true)
	z_index = -1
	velocity = Vector2.ZERO
	rotation = (dir as Vector2).angle() + PI / 2.0 + randf_range(-0.6, 0.6)


# --- Drawing ---------------------------------------------------------------

## Ellipse as a scaled unit circle (no triangulation), with a dark outline.
func _ell(c: Vector2, r: Vector2, col: Color, outline := true) -> void:
	if outline:
		draw_set_transform_matrix(_base * Transform2D(Vector2(r.x + 1.4, 0), Vector2(0, r.y + 1.4), c))
		draw_circle(Vector2.ZERO, 1.0, OUTLINE)
	draw_set_transform_matrix(_base * Transform2D(Vector2(r.x, 0), Vector2(0, r.y), c))
	draw_circle(Vector2.ZERO, 1.0, col)
	draw_set_transform_matrix(_base)


func _draw() -> void:
	var s := radius / 15.0
	var body: Color = _cfg.color
	var dark: Color = _cfg.dark
	var dead := state == State.DEAD
	var aware := _engaged()
	if dead:
		var fade := clampf(40.0 - _dead_t, 0.0, 1.0)
		body = body.darkened(0.45)
		dark = dark.darkened(0.45)
		draw_circle(Vector2(0, 4), radius * 1.3, Color(BLOOD[kind], 0.18 * fade))
	elif _flash > 0.0:
		body = body.lerp(Color.WHITE, 0.55)
		dark = dark.lerp(Color.WHITE, 0.35)
	_base = Transform2D(Vector2(s, 0), Vector2(0, s), Vector2.ZERO)
	if not dead:
		# Drop shadow (light is fixed in the world, not on the screen).
		var so := Vector2(5, 7).rotated(-global_rotation)
		draw_set_transform_matrix(Transform2D(Vector2(radius * 0.95, 0), Vector2(0, radius * 1.35), so))
		draw_circle(Vector2.ZERO, 1.0, Color(0, 0, 0, 0.28))
	draw_set_transform_matrix(_base)
	if state == State.ATTACK and not _struck:
		_draw_melee_telegraph()
	var moving := clampf(velocity.length() / (run_speed * PX), 0.0, 1.0) if not dead else 0.0
	var gait := sin(_walk_phase) * moving
	var plate := body.lightened(0.18)
	var armored: bool = _cfg.armor > 0

	# Six legs: two segments with a knee (two tripods alternate).
	for i in 3:
		var y := -6.0 + i * 7.0
		var phase := gait if i % 2 == 0 else -gait
		for side in [-1.0, 1.0]:
			var p: float = phase * side
			var root := Vector2(side * 6.0, y)
			var knee := Vector2(side * 14.0, y + (i - 1) * 3.0 - 3.0 + p * 3.0)
			var tip := Vector2(side * 18.0, y + (i - 1) * 6.0 + 2.0 + p * 5.0)
			draw_polyline(PackedVector2Array([root, knee, tip]), OUTLINE, 3.8)
			draw_polyline(PackedVector2Array([root, knee, tip]), dark, 2.1)
			draw_circle(knee, 1.5, body.darkened(0.1))
			draw_line(tip, tip + Vector2(side * 2.5, 1.5), OUTLINE, 1.6)

	match kind:
		Kind.BILE_SPITTER:
			# Huge glowing bile sac behind, with veins.
			var pulse := 1.0 + 0.06 * sin(Time.get_ticks_msec() * 0.008)
			var sac := Color(0.75, 0.85, 0.2) if not dead else dark
			_ell(Vector2(0, 14), Vector2(12, 14) * pulse, sac)
			_ell(Vector2(0, 16), Vector2(7, 8) * pulse, Color(0.9, 1.0, 0.4, 0.8) if not dead else dark, false)
			if not dead:
				for a in [-0.8, 0.0, 0.8]:
					draw_line(Vector2(0, 16), Vector2(sin(a) * 10.0, 16.0 + cos(a) * 8.0), Color(0.45, 0.6, 0.1, 0.8), 1.0)
			_ell(Vector2(0, 5), Vector2(8, 5), dark)
		Kind.HUNTER:
			_ell(Vector2(0, 11), Vector2(6, 9), dark)
			draw_line(Vector2(-4, 10), Vector2(4, 10), OUTLINE, 1.0)
			draw_line(Vector2(-4, 14), Vector2(4, 14), OUTLINE, 1.0)
		_:
			_ell(Vector2(0, 11), Vector2(8, 10), dark) # abdomen
			for yy in [8.0, 12.0, 16.0]:
				draw_line(Vector2(-6, yy), Vector2(6, yy), OUTLINE, 1.0)
	# Thorax with plates.
	_ell(Vector2(0, -1), Vector2(9, 9), body)
	draw_line(Vector2(-7, -1), Vector2(7, -1), dark, 1.5)
	if armored:
		# Overlapping carapace plates with highlights and rivets.
		var pl := plate
		for k in 3:
			var yy := -5.0 + k * 4.5
			var w := 8.5 - absf(k - 1) * 1.5
			_ell(Vector2(0, yy), Vector2(w, 3.2), pl.darkened(k * 0.08), true)
			draw_line(Vector2(-w * 0.7, yy - 1.6), Vector2(w * 0.7, yy - 1.6), pl.lightened(0.35), 1.0)
		for side in [-1.0, 1.0]:
			_ell(Vector2(side * 9.0, -3.0), Vector2(3.4, 5.0), pl.darkened(0.12)) # shoulder plates
			draw_circle(Vector2(side * 9.0, -4.0), 0.9, pl.lightened(0.4))
		if kind == Kind.WARRIOR:
			for side in [-1.0, 1.0]:
				draw_colored_polygon(PackedVector2Array([Vector2(side * 4, 4), Vector2(side * 7, 9), Vector2(side * 2, 7)]), pl.darkened(0.3))
	else:
		draw_circle(Vector2(-2.5, -4.0), 2.2, body.lightened(0.3))
	# Head + mandibles / claws.
	var head_c := Vector2(0, -11)
	var reach := 0.0
	if state == State.ATTACK:
		reach = clampf(_attack_t / _cfg.windup, 0.0, 1.0)
	elif state == State.LEAP:
		reach = 1.0
	if kind == Kind.HUNTER:
		for side in [-1.0, 1.0]:
			var base := Vector2(side * 5.0, -8.0)
			var mid := Vector2(side * (11.0 - reach * 3.0), -17.0 - reach * 3.0)
			var tip := Vector2(side * (7.0 - reach * 4.0), -25.0 - reach * 7.0)
			draw_polyline(PackedVector2Array([base, mid, tip]), OUTLINE, 3.8)
			draw_polyline(PackedVector2Array([base, mid, tip]), body.lightened(0.25), 2.0)
	_ell(head_c, Vector2(6, 5.5), body.darkened(0.15))
	if armored:
		draw_arc(head_c, 4.5, PI * 1.15, PI * 1.85, 8, plate.lightened(0.3), 1.2)
	for side in [-1.0, 1.0]:
		var open := 0.5 + reach * 0.6
		var m0 := head_c + Vector2(side * 3.0, -3.0)
		var m1 := head_c + Vector2(side * (3.0 + 4.0 * open), -9.0)
		draw_line(m0, m1, OUTLINE, 3.0)
		draw_line(m0, m1, Color(0.8, 0.72, 0.55) if not dead else dark, 1.4)
		var eye := Color(1.0, 0.18, 0.1) if (aware and not dead) else Color(0.1, 0.05, 0.04)
		draw_circle(head_c + Vector2(side * 2.6, -1.0), 1.3, eye)
	if kind == Kind.BILE_SPITTER and state == State.SPIT:
		draw_circle(head_c + Vector2(0, -6), 2.0 + _special_t * 4.0, Color(0.8, 1.0, 0.3, 0.8))
	if is_stunned():
		var a := Time.get_ticks_msec() * 0.006
		for i in 3:
			draw_circle(head_c + Vector2.from_angle(a + i * TAU / 3.0) * 9.0, 1.6, UiStyle.YELLOW)
	if not dead and hp < max_hp * 0.5:
		# Wounds: goo blots on the thorax.
		var gc: Color = BLOOD[kind]
		draw_circle(Vector2(3.5, 0.5), 2.0, Color(gc, 0.8))
		draw_circle(Vector2(-4.0, 6.0), 1.5, Color(gc, 0.8))
	draw_set_transform(Vector2.ZERO)
	if state == State.SPIT:
		_draw_spit_telegraph()
	if not dead:
		_draw_billboards()
	_draw_numbers()


## Melee wind-up: red arc in front that fills toward the strike.
func _draw_melee_telegraph() -> void:
	var k := clampf(_attack_t / _cfg.windup, 0.0, 1.0)
	var reach_px: float = radius + (_cfg.reach + 0.25) * PX
	var a0 := -PI / 2.0 - deg_to_rad(70.0)
	var a1 := -PI / 2.0 + deg_to_rad(70.0)
	draw_set_transform(Vector2.ZERO)
	draw_arc(Vector2.ZERO, reach_px, a0, a1, 14, Color(1, 0.25, 0.1, 0.25 + 0.5 * k), 3.0)
	draw_arc(Vector2.ZERO, reach_px * k, a0, a1, 14, Color(1, 0.3, 0.1, 0.35), 2.0)
	draw_set_transform_matrix(_base)


## Bile spitter: target circle at the player with a shrinking ring and a lobbed-arc hint.
func _draw_spit_telegraph() -> void:
	if _player == null:
		return
	var tp := to_local(_player.global_position)
	var k := clampf(_special_t / SPIT_WINDUP, 0.0, 1.0)
	var rr := 1.8 * PX
	draw_circle(tp, rr, Color(0.6, 0.85, 0.15, 0.1 + 0.18 * k))
	draw_arc(tp, rr, 0.0, TAU, 32, Color(0.75, 1.0, 0.25, 0.8), 2.5)
	draw_arc(tp, rr * (1.0 - k * 0.85), 0.0, TAU, 28, Color(1.0, 0.95, 0.3, 0.9), 3.0)
	var from := Vector2(0, -radius)
	var steps := 10
	for i in steps:
		if i % 2 == 0:
			var a := from.lerp(tp, float(i) / steps)
			var b := from.lerp(tp, float(i + 1) / steps)
			draw_line(a, b, Color(0.8, 1.0, 0.3, 0.45), 2.0)


## Screen-aligned icons: awareness (?/!), ricochet shield, HP bar.
func _draw_billboards() -> void:
	draw_set_transform(Vector2.ZERO, -get_viewport().get_canvas_transform().get_rotation() - global_rotation)
	var font := ThemeDB.fallback_font
	var top := -radius - 14.0
	var heavy: bool = kind == Kind.BILE_SPITTER
	if _dmg_t < 3.5 or (heavy and _engaged()) or (hp < max_hp and heavy):
		var w := 40.0 if heavy else 28.0
		var a := 1.0 if heavy else clampf((3.5 - _dmg_t) / 0.8, 0.0, 1.0)
		var r := Rect2(-w * 0.5, top - 4.0, w, 6.0)
		draw_rect(r.grow(1.5), Color(0, 0, 0, 0.7 * a))
		var f := clampf(hp / max_hp, 0.0, 1.0)
		var col := Color(0.4, 0.9, 0.3, a) if f > 0.5 else (Color(1, 0.8, 0.1, a) if f > 0.25 else Color(0.95, 0.2, 0.15, a))
		draw_rect(Rect2(r.position, Vector2(r.size.x * f, r.size.y)), col)
		if heavy:
			draw_rect(r, Color(1, 1, 1, 0.3), false, 1.0)
		top -= 10.0
	# Awareness icon.
	var icon := ""
	var icol := UiStyle.YELLOW
	var pop := 1.0
	if _engaged():
		icon = "!"
		icol = Color(1.0, 0.25, 0.15)
		pop = 1.0 + 0.5 * clampf(1.0 - _aware_t / 0.35, 0.0, 1.0)
	elif state == State.SEARCH:
		icon = "?"
	if icon != "" and (not _engaged() or _aware_t < 2.5 or heavy):
		var ic := Vector2(0, top - 8.0)
		var rr := 9.0 * pop
		draw_circle(ic, rr + 1.5, Color(0.05, 0.04, 0.04, 0.9))
		draw_circle(ic, rr, Color(icol, 0.9))
		draw_string(font, ic + Vector2(-rr, 6.0 * pop), icon, HORIZONTAL_ALIGNMENT_CENTER, rr * 2.0, int(17 * pop), Color(0.08, 0.05, 0.03))
	# Ricochet shield.
	if _bounce_t > 0.0:
		var a := clampf(_bounce_t / 0.3, 0.0, 1.0)
		var c := Vector2(radius * 0.9 + 6.0, -radius * 0.5 - (0.7 - _bounce_t) * 22.0)
		var shield := PackedVector2Array([c + Vector2(-6, -7), c + Vector2(6, -7), c + Vector2(6, 1), c + Vector2(0, 8), c + Vector2(-6, 1)])
		var sh_o := PackedVector2Array()
		for v in shield:
			sh_o.append(c + (v - c) * 1.3)
		draw_colored_polygon(sh_o, Color(0.05, 0.05, 0.05, 0.9 * a))
		draw_colored_polygon(shield, Color(1.0, 0.88, 0.2, a))
		draw_line(c + Vector2(-4, 4), c + Vector2(4, -4), Color(0.1, 0.08, 0.04, a), 2.0)
	draw_set_transform(Vector2.ZERO)


func _draw_numbers() -> void:
	if _numbers.is_empty():
		return
	var font := ThemeDB.fallback_font
	draw_set_transform(Vector2.ZERO, -get_viewport().get_canvas_transform().get_rotation() - global_rotation)
	for n in _numbers:
		var a: float = 1.0 - n.t / 0.9
		var col := Color(1, 0.35, 0.2, a) if n.crit else Color(1, 0.95, 0.5, a)
		draw_string(font, Vector2(n.x - 50, -radius - 12 - n.t * 40.0), n.text, HORIZONTAL_ALIGNMENT_CENTER, 100, 20 if n.crit else 16, col)
	draw_set_transform(Vector2.ZERO)
