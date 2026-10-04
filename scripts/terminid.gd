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
	for n in _numbers:
		n.t += delta
	_numbers = _numbers.filter(func(n): return n.t < 0.9)
	if state == State.DEAD:
		_dead_t += delta
		if _dead_t > 40.0:
			queue_free()
		queue_redraw()
		return

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
	remove_from_group("terminids")
	remove_from_group("enemies")
	_col.set_deferred("disabled", true)
	z_index = -1
	velocity = Vector2.ZERO
	rotation = (dir as Vector2).angle() + PI / 2.0 + randf_range(-0.6, 0.6)


# --- Drawing ---------------------------------------------------------------

func _draw() -> void:
	var s := radius / 15.0
	var body: Color = _cfg.color
	var dark: Color = _cfg.dark
	if state == State.DEAD:
		var fade := clampf(40.0 - _dead_t, 0.0, 1.0)
		draw_circle(Vector2(0, 4), radius * 1.6, Color(0.55, 0.45, 0.1, 0.45 * fade)) # ichor
		body = body.darkened(0.45)
		dark = dark.darkened(0.45)
	elif _flash > 0.0:
		body = body.lerp(Color.WHITE, 0.5)
	var moving := clampf(velocity.length() / (run_speed * PX), 0.0, 1.0) if state != State.DEAD else 0.0
	var gait := sin(_walk_phase) * moving
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))

	# Six legs (two tripods alternate)
	for i in 3:
		var y := -6.0 + i * 7.0
		var phase := gait if i % 2 == 0 else -gait
		for side in [-1.0, 1.0]:
			var p: float = phase * side
			var root := Vector2(side * 6.0, y)
			var tip := Vector2(side * 17.0, y + (i - 1) * 6.0 + p * 5.0)
			draw_line(root, tip, OUTLINE, 3.5)
			draw_line(root, tip, dark, 2.0)

	match kind:
		Kind.BILE_SPITTER:
			# Huge glowing bile sac behind
			var pulse := 1.0 + 0.06 * sin(Time.get_ticks_msec() * 0.008)
			_ellipse(Vector2(0, 14), Vector2(12, 14) * pulse, Color(0.75, 0.85, 0.2) if state != State.DEAD else dark)
			_ellipse(Vector2(0, 16), Vector2(7, 8) * pulse, Color(0.9, 1.0, 0.4, 0.8) if state != State.DEAD else dark)
		Kind.HUNTER:
			_ellipse(Vector2(0, 11), Vector2(6, 9), dark)
		_:
			_ellipse(Vector2(0, 11), Vector2(8, 10), dark) # abdomen
	# Thorax with plates
	_ellipse(Vector2(0, -1), Vector2(9, 9), body)
	draw_line(Vector2(-7, -1), Vector2(7, -1), dark, 1.5)
	# Head + mandibles / claws
	var head_c := Vector2(0, -11)
	var reach := 0.0
	if state == State.ATTACK:
		reach = clampf(_attack_t / _cfg.windup, 0.0, 1.0)
	elif state == State.LEAP:
		reach = 1.0
	if kind == Kind.HUNTER:
		# Long scythe claws
		for side in [-1.0, 1.0]:
			var base := Vector2(side * 5.0, -8.0)
			var tip := Vector2(side * (9.0 - reach * 5.0), -22.0 - reach * 6.0)
			draw_line(base, tip, OUTLINE, 3.5)
			draw_line(base, tip, body.lightened(0.2), 2.0)
	_ellipse(head_c, Vector2(6, 5.5), body.darkened(0.15))
	for side in [-1.0, 1.0]:
		var open := 0.5 + reach * 0.6
		draw_line(head_c + Vector2(side * 3.0, -3.0), head_c + Vector2(side * (3.0 + 4.0 * open), -9.0), OUTLINE, 2.5)
	if kind == Kind.BILE_SPITTER and state == State.SPIT:
		draw_circle(head_c + Vector2(0, -6), 2.0 + _special_t * 4.0, Color(0.8, 1.0, 0.3, 0.8))
	if is_stunned():
		var a := Time.get_ticks_msec() * 0.006
		for i in 3:
			draw_circle(head_c + Vector2.from_angle(a + i * TAU / 3.0) * 9.0, 1.6, UiStyle.YELLOW)
	draw_set_transform(Vector2.ZERO)
	_draw_numbers()


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


func _ellipse(c: Vector2, radii: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	var out := PackedVector2Array()
	for i in 14:
		var a := TAU * i / 14.0
		var v := Vector2(cos(a), sin(a))
		pts.append(c + v * radii)
		out.append(c + v * (radii + Vector2(1.4, 1.4)))
	draw_colored_polygon(out, OUTLINE)
	draw_colored_polygon(pts, col)
