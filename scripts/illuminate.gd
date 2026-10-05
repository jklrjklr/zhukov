class_name Illuminate
extends CharacterBody2D
## Illuminate enemy (Helldivers 2 squids). One script, six kinds:
##   VOTELESS   converted colonists: fast shamble, claws, come in hordes; no armor, weak head
##   OVERSEER   armored (AC2) staff warrior: plasma shots at range, staff swings up close
##   ELEVATED   Elevated Overseer: jetpack flyer (crosses walls), plasma bursts; the jetpack
##              on its back is the weak spot (x2)
##   WATCHER    flying scout drone, no weapon: keeps the Helldiver in its eye and after a
##              few seconds calls a warp ship on them unless it is shot down first
##   FLESHMOB   mass of fused bodies: slow, very tough, crushing contact damage, barely staggers
##   HARVESTER  tripod walker that steps over walls. Energy shield (blocks everything,
##              regenerates 5 s after the last hit), hull AC4, red eye AC3 (crit).
##              Charges, then sweeps a beam that cuts through anything not behind cover.
## Targets: the Helldiver while it sees them (and a few s after losing sight), a sentry
## close by, otherwise the nearest generator. Ground units go through the base gates
## (MissionMap.route). Flyers ignore walls.

enum Kind { VOTELESS, OVERSEER, ELEVATED, WATCHER, FLESHMOB, HARVESTER }
enum State { ADVANCE, ENGAGE, DEAD }

const PX := Firearm.PX_PER_M
const KNOCKBACK := 300.0
const STUN_DECAY := 0.5
const STUN_TIME := 0.7
const RAYS := 12
## Beyond this distance from the Helldiver units think and steer less often.
const LOD_FAR_M := 30.0
const FEELER := 60.0
const CHASE_TIME := 4.0
const OUTLINE := Color(0.05, 0.05, 0.07)
const ROBE := Color(0.78, 0.78, 0.82)
const ROBE_DARK := Color(0.45, 0.45, 0.52)
const GLOW := Color(0.45, 0.95, 1.0)
const PURPLE := Color(0.7, 0.35, 1.0)
const SKIN := Color(0.42, 0.36, 0.38)
const FLESH := Color(0.62, 0.36, 0.38)

## Per-kind stats. Speeds are fractions of the player's base walk speed.
## weapon: "claw" (melee), "plasma" (bursts of plasma bolts), "watch" (calls ships),
## "crush" (contact), "beam" (charged sweeping beam).
const KINDS := {
	Kind.VOTELESS: {"name": "Voteless", "hp": 125.0, "weight": 70.0, "radius": 12.0, "speed": 1.05,
		"sight": 11.0, "fov": 140.0, "armor": [0, 0, 0], "head": 5.0, "crit": 2.0, "turn": 320.0,
		"weapon": "claw", "reach": 0.5, "dps": 28.0, "fly": false},
	Kind.OVERSEER: {"name": "Overseer", "hp": 450.0, "weight": 220.0, "radius": 15.0, "speed": 0.8,
		"sight": 15.0, "fov": 110.0, "armor": [2, 2, 2], "head": 5.0, "crit": 2.0, "turn": 220.0,
		"weapon": "plasma", "range": 18.0, "keep": Vector2(6.0, 13.0), "burst": 2, "burst_gap": 0.25,
		"burst_cd": 2.2, "bolt_damage": 14.0, "spread": 3.0, "bolt_speed": 20.0, "reach": 0.8, "dps": 40.0,
		"fly": false},
	Kind.ELEVATED: {"name": "Elevated Overseer", "hp": 300.0, "weight": 150.0, "radius": 14.0, "speed": 1.1,
		"sight": 17.0, "fov": 130.0, "armor": [1, 1, 1], "head": 5.0, "crit": 2.0, "turn": 260.0,
		"weapon": "plasma", "range": 22.0, "keep": Vector2(10.0, 18.0), "burst": 3, "burst_gap": 0.2,
		"burst_cd": 2.6, "bolt_damage": 10.0, "spread": 5.0, "bolt_speed": 20.0, "rear_mult": 2.0, "fly": true},
	Kind.WATCHER: {"name": "Watcher", "hp": 150.0, "weight": 60.0, "radius": 13.0, "speed": 1.0,
		"sight": 22.0, "fov": 160.0, "armor": [1, 1, 1], "head": 7.0, "crit": 2.0, "turn": 200.0,
		"weapon": "watch", "keep": Vector2(12.0, 18.0), "call_time": 4.0, "fly": true},
	Kind.FLESHMOB: {"name": "Fleshmob", "hp": 1400.0, "weight": 2500.0, "radius": 30.0, "speed": 0.75,
		"sight": 12.0, "fov": 160.0, "armor": [1, 1, 1], "head": 0.0, "crit": 1.0, "turn": 120.0,
		"weapon": "crush", "reach": 0.4, "dps": 70.0, "fly": false},
	Kind.HARVESTER: {"name": "Harvester", "hp": 2400.0, "weight": 6000.0, "radius": 36.0, "speed": 0.35,
		"sight": 30.0, "fov": 200.0, "armor": [4, 4, 4], "head": 9.0, "crit": 2.0, "eye_armor": 3, "turn": 60.0,
		"weapon": "beam", "range": 30.0, "keep": Vector2(12.0, 24.0), "beam_dps": 45.0, "charge": 1.2,
		"fire": 2.2, "beam_cd": 3.0, "sweep": 22.0, "shield": 900.0, "shield_delay": 5.0, "shield_regen": 300.0,
		"shield_r": 70.0, "fly": true},
}

@export var kind := Kind.VOTELESS
@export var hearing := 80.0

var hp := 100.0
var max_hp := 100.0
var weight := 100.0
var radius := 15.0
var shield := 0.0
var max_shield := 0.0
var state := State.ADVANCE
var flying := false
## Current target (player, sentry or generator) and its position this tick.
var target: Node2D

var _cfg: Dictionary
var _player: CharacterBody2D
var _map: Node
var _col: CollisionShape2D
var _shape: CircleShape2D
var _goal := Vector2.ZERO
var _steer := Vector2.UP
var _detour := 0
var _detour_time := 0.0
var _tick := 0
var _walk_phase := 0.0
var _flash := 0.0
var _shield_flash := 0.0
var _shield_wait := 0.0
var _dead_t := 0.0
var _stun_meter := 0.0
var _stun_t := 0.0
var _numbers: Array[Dictionary] = []
var _burst_left := 0
var _burst_t := 0.0
var _fire_cd := 1.0
var _strafe := 1.0
var _strafe_t := 0.0
var _chase_t := 0.0
var _seen := false
var _muzzle_flash := 0.0
var _call_t := 0.0
## Harvester beam: 0 idle, 1 charging, 2 firing.
var _beam_phase := 0
var _beam_t := 0.0
var _beam_aim := Vector2.ZERO
var _beam_end := Vector2.ZERO
var _bob := 0.0
var _lof_cache := false


func _ready() -> void:
	_cfg = KINDS[kind]
	max_hp = _cfg.hp
	hp = max_hp
	weight = _cfg.weight
	radius = _cfg.radius
	flying = _cfg.fly
	max_shield = _cfg.get("shield", 0.0)
	shield = max_shield
	add_to_group("illuminate")
	add_to_group("enemies")
	add_to_group("concealable")
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 2
	collision_mask = 0 if flying else 3
	z_index = 6 if flying else 0
	_col = CollisionShape2D.new()
	_shape = CircleShape2D.new()
	_shape.radius = _cfg.shield_r if shield > 0.0 else radius
	_col.shape = _shape
	add_child(_col)
	_tick = randi() % 6
	_bob = randf() * TAU
	_strafe = 1.0 if randf() < 0.5 else -1.0
	_fire_cd = randf_range(0.5, 1.5)
	_player = get_tree().get_first_node_in_group("player")
	var mission := get_tree().get_first_node_in_group("mission")
	if mission:
		_map = mission.get("map")
	_goal = global_position


static func make(k: Kind) -> Illuminate:
	var a := Illuminate.new()
	a.kind = k
	return a


## A group of `kinds` around center (free spots only). Returns the spawned units.
static func spawn_group(parent: Node, center: Vector2, kinds: Array, is_free: Callable) -> Array[Illuminate]:
	var out: Array[Illuminate] = []
	for k in kinds:
		for attempt in 8:
			var p := center + Vector2.from_angle(randf() * TAU) * randf_range(0.0, 4.0) * PX
			if not is_free.call(p):
				continue
			var a := Illuminate.make(k)
			a.position = p
			a.rotation = randf() * TAU
			parent.add_child(a)
			out.append(a)
			break
	return out


func is_dead() -> bool:
	return state == State.DEAD


func kind_name() -> String:
	return _cfg.name


## Point the Helldiver out (e.g. a horde told where they are).
func alert_to(_pos: Vector2, engage := false) -> void:
	if engage and state != State.DEAD:
		_chase_t = CHASE_TIME * 2.0


func hear(pos: Vector2, loudness: float, falloff_pct: float) -> void:
	if state == State.DEAD or _player == null or kind == Kind.WATCHER:
		return
	var level := FirearmStats.loudness_at(loudness, falloff_pct, global_position.distance_to(pos) / PX)
	if level >= 100.0 - hearing and pos.distance_to(_player.global_position) < 3.0 * PX:
		_chase_t = maxf(_chase_t, 2.0)


## Armor class met by a hit travelling in `dir` (front, side, rear).
func _zone(dir: Vector2) -> int:
	var d := dir.normalized().dot(Vector2.UP.rotated(rotation))
	if d < -0.5:
		return 0
	if d > 0.5:
		return 2
	return 1


func take_hit(hit: Dictionary) -> void:
	if state == State.DEAD:
		return
	var explosive: bool = hit.get("explosive", false)
	if shield > 0.0:
		# The shield takes everything until it collapses; explosives hit it harder.
		shield -= hit.damage * (1.5 if explosive else 1.0)
		_shield_wait = _cfg.shield_delay
		_shield_flash = 0.1
		_numbers.append({"text": "SHIELD", "t": 0.0, "crit": false, "x": randf_range(-10, 10)})
		if shield <= 0.0:
			shield = 0.0
			Sfx.play("shield_break", global_position, 2.0)
			var proj := get_tree().get_first_node_in_group("projectiles")
			if proj:
				proj.add_puff(global_position, 3.0)
		else:
			Sfx.play("shield_hit", global_position, -6.0, 0.1)
		_chase_t = CHASE_TIME
		return
	var zone := _zone(hit.dir)
	var armor: int = _cfg.armor[zone]
	var mult := 1.0
	var crit := false
	if _cfg.head > 0.0 and zone != 2:
		var head_c := global_position + Vector2.UP.rotated(rotation) * radius * 0.5
		crit = Combat.is_crit(hit, head_c, _cfg.head, 30.0)
	if crit:
		armor = _cfg.get("eye_armor", 0)
		mult = _cfg.crit
	elif zone == 2 and _cfg.has("rear_mult"):
		mult = _cfg.rear_mult
		crit = true
	if explosive:
		armor = mini(armor, 3)
	var dmg: float = hit.damage * FirearmStats.armor_factor(hit.armor_penetration, armor) * mult
	hp -= dmg
	_flash = 0.08
	if not explosive:
		Sfx.play("hit_armor" if dmg <= 0.0 else "hit_flesh", global_position, -6.0, 0.1)
	var text := "BLOCK" if dmg <= 0.0 else ("CRIT %d" if crit else "%d") % roundi(dmg)
	_numbers.append({"text": text, "t": 0.0, "crit": crit, "x": randf_range(-10, 10)})
	var impact: float = hit.get("stagger", 0.0) / weight
	velocity += (hit.dir as Vector2) * impact * KNOCKBACK
	_stun_meter += impact
	if _stun_meter >= 1.0:
		_stun_meter = 0.0
		_stun_t = STUN_TIME
		_beam_phase = 0
	if hp <= 0.0:
		_die(hit.dir)
		return
	_chase_t = CHASE_TIME


func _physics_process(delta: float) -> void:
	_flash = maxf(_flash - delta, 0.0)
	_shield_flash = maxf(_shield_flash - delta, 0.0)
	_muzzle_flash = maxf(_muzzle_flash - delta, 0.0)
	_bob += delta * 3.0
	for n in _numbers:
		n.t += delta
	_numbers = _numbers.filter(func(n): return n.t < 0.9)
	if state == State.DEAD:
		_dead_t += delta
		if _dead_t > 30.0:
			queue_free()
		queue_redraw()
		return
	_update_shield(delta)
	_stun_meter = maxf(_stun_meter - STUN_DECAY * delta, 0.0)
	if _stun_t > 0.0:
		_stun_t -= delta
		velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
		move_and_slide()
		queue_redraw()
		return
	_tick += 1
	_chase_t = maxf(_chase_t - delta, 0.0)
	var far: bool = _player == null or global_position.distance_squared_to(_player.global_position) > pow(LOD_FAR_M * PX, 2)
	if _tick % (12 if far else 5) == 0 or target == null or not is_instance_valid(target):
		_pick_target()

	var walk: float = (_player.move_speed if _player else 180.0)
	var speed: float = walk * _cfg.speed
	var face := _steer
	if target == null:
		velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
		move_and_slide()
		queue_redraw()
		return
	var tpos := target.global_position
	var to_t := tpos - global_position
	var dist_m := to_t.length() / PX
	var reach_px: float = radius + _target_radius() + _cfg.get("reach", 0.0) * PX
	_goal = _route(tpos)
	match _cfg.weapon:
		"claw", "crush":
			face = to_t.normalized()
			if to_t.length() <= reach_px:
				speed *= 0.25
				# Claws do less to machines than to Helldivers.
				var mult := 1.0 if target == _player else 0.5
				target.take_damage(_cfg.dps * mult * delta, global_position, false)
				if kind == Kind.VOTELESS and _tick % 30 == 0:
					Sfx.play("claw", global_position, -8.0, 0.15)
			if kind == Kind.FLESHMOB and _player and target != _player \
					and global_position.distance_to(_player.global_position) <= radius + 16.0 + 0.4 * PX:
				_player.take_damage(_cfg.dps * delta, global_position, false)
		"plasma":
			face = to_t.normalized()
			var keep: Vector2 = _cfg.keep
			var sees := _line_of_fire(target)
			if not sees or dist_m > keep.y:
				pass # keep routing in
			elif dist_m < keep.x and target == _player:
				_goal = global_position - to_t.normalized() * 3.0 * PX
			else:
				_strafe_t -= delta
				if _strafe_t <= 0.0:
					_strafe_t = randf_range(1.5, 3.0)
					_strafe = -_strafe
				_goal = global_position + to_t.normalized().orthogonal() * _strafe * 2.0 * PX
				speed *= 0.5
			if kind == Kind.OVERSEER and to_t.length() <= reach_px:
				target.take_damage(_cfg.dps * delta, global_position, false)
				speed *= 0.3
			else:
				_update_plasma(delta, dist_m, to_t, sees)
		"watch":
			face = to_t.normalized()
			var keep: Vector2 = _cfg.keep
			if target == _player:
				if dist_m < keep.x:
					_goal = global_position - to_t.normalized() * 3.0 * PX
				elif dist_m < keep.y:
					_goal = global_position + to_t.normalized().orthogonal() * _strafe * 2.0 * PX
					speed *= 0.4
				if _seen:
					_call_t += delta
					if _call_t >= _cfg.call_time:
						_call_t = -12.0
						Sfx.play("watcher_call", global_position, 2.0)
						get_tree().call_group("mission", "on_watcher_call", _player.global_position)
				else:
					_call_t = maxf(_call_t - delta, minf(_call_t, 0.0))
			else:
				_call_t = minf(_call_t, 0.0)
				if dist_m < 20.0:
					speed *= 0.3 # hover near the base, looking for Helldivers
		"beam":
			face = to_t.normalized()
			var keep: Vector2 = _cfg.keep
			if dist_m < keep.y and _line_of_fire(target):
				speed *= 0.25 if dist_m > keep.x else 0.0
			_update_beam(delta, dist_m, tpos)

	if flying:
		_steer = (_goal - global_position).normalized() if global_position.distance_to(_goal) > 8.0 else _steer
	elif _tick % (8 if far else (4 if kind == Kind.VOTELESS else 3)) == 0 and speed > 0.0:
		_steer = _steer.lerp(_steer_dir((_goal - global_position).normalized()), 0.5).normalized()
	if global_position.distance_to(_goal) < 8.0:
		speed = 0.0
	var want := face.angle() + PI / 2.0
	var max_step := deg_to_rad(_cfg.turn) * delta
	rotation += clampf(wrapf(want - rotation, -PI, PI), -max_step, max_step)
	velocity = velocity.move_toward(_steer * speed, 900.0 * delta)
	move_and_slide()
	_walk_phase = fmod(_walk_phase + clampf(velocity.length() / maxf(walk, 1.0), 0.0, 1.5) * 1.6 * TAU * delta, TAU)
	if kind == Kind.HARVESTER:
		Sfx.hold(str(get_instance_id()), "harvester_beam", global_position, _beam_phase == 2, 0.0)
	queue_redraw()


func _update_shield(delta: float) -> void:
	if max_shield <= 0.0:
		return
	if shield < max_shield:
		_shield_wait -= delta
		if _shield_wait <= 0.0:
			shield = minf(shield + _cfg.shield_regen * delta, max_shield)
	var want: float = _cfg.shield_r if shield > 0.0 else radius
	if _shape.radius != want:
		_shape.radius = want


## Who to go for: the Helldiver while seen / recently seen, a sentry close by, else the
## nearest generator (falls back to the Helldiver).
func _pick_target() -> void:
	var player_ok: bool = _player != null and not _player.dead and not _player.deploying
	_seen = false
	if player_ok:
		var to := _player.global_position - global_position
		var dist := to.length()
		var in_cone: bool = dist <= _cfg.sight * PX and absf(Vector2.UP.rotated(rotation).angle_to(to)) <= deg_to_rad(_cfg.fov / 2.0)
		if (in_cone or dist <= 2.0 * PX) and _line_of_sight(_player):
			_seen = true
			_chase_t = CHASE_TIME
	if player_ok and _chase_t > 0.0:
		_set_target(_player)
		return
	if kind != Kind.WATCHER:
		var best: Node2D = null
		var best_d := 14.0 * PX
		for s in get_tree().get_nodes_in_group("sentries"):
			var d := global_position.distance_to((s as Node2D).global_position)
			if d < best_d:
				best_d = d
				best = s
		if best:
			_set_target(best)
			return
	var gen: Node2D = null
	var gd := INF
	for g in get_tree().get_nodes_in_group("generators"):
		if g.is_destroyed():
			continue
		var d := global_position.distance_to((g as Node2D).global_position)
		if d < gd:
			gd = d
			gen = g
	if gen:
		_set_target(gen)
	elif player_ok:
		_set_target(_player)
	else:
		target = null


func _set_target(t: Node2D) -> void:
	if t != target:
		state = State.ENGAGE if t == _player else State.ADVANCE
		_beam_phase = 0 if _beam_phase == 1 else _beam_phase
	target = t


func _target_radius() -> float:
	var r = target.get("hit_radius")
	return r if r != null else 14.0


## Waypoint toward `to`: ground units walk through the base gates.
func _route(to: Vector2) -> Vector2:
	if flying or _map == null or not _map.has_method("route"):
		return to
	return _map.route(global_position, to)


func _update_plasma(delta: float, dist_m: float, to_t: Vector2, sees: bool) -> void:
	_fire_cd -= delta
	var aimed := absf(Vector2.UP.rotated(rotation).angle_to(to_t)) < deg_to_rad(20.0)
	if _burst_left <= 0:
		if _fire_cd <= 0.0 and aimed and dist_m <= _cfg.range and sees:
			_burst_left = _cfg.burst
			_burst_t = 0.0
		return
	_burst_t -= delta
	if _burst_t <= 0.0:
		_burst_t = _cfg.burst_gap
		_burst_left -= 1
		var dir := to_t.normalized().rotated(deg_to_rad(randf_range(-1.0, 1.0) * _cfg.spread))
		var muzzle := global_position + Vector2.UP.rotated(rotation) * (radius + 8.0)
		var proj := get_tree().get_first_node_in_group("projectiles")
		proj.spawn_bolt(muzzle, dir * _cfg.bolt_speed * PX, _cfg.bolt_damage, self, "plasma")
		Sfx.play("plasma_shot", muzzle, -4.0, 0.1)
		_muzzle_flash = 0.08
		if _burst_left <= 0:
			_fire_cd = _cfg.burst_cd * randf_range(0.8, 1.2)


## Harvester: lock on and charge, then fire a beam that sweeps toward the target.
func _update_beam(delta: float, dist_m: float, tpos: Vector2) -> void:
	var eye := global_position + Vector2.UP.rotated(rotation) * radius * 0.5
	match _beam_phase:
		0:
			_fire_cd -= delta
			if _fire_cd <= 0.0 and dist_m <= _cfg.range and _line_of_fire(target):
				_beam_phase = 1
				_beam_t = _cfg.charge
				_beam_aim = tpos + (tpos - eye).normalized().orthogonal() * randf_range(-3.0, 3.0) * PX
				Sfx.play("beam_charge", global_position, 0.0)
		1:
			_beam_t -= delta
			_beam_end = _cast(eye, _beam_aim)
			if _beam_t <= 0.0:
				_beam_phase = 2
				_beam_t = _cfg.fire
		2:
			_beam_t -= delta
			# Sweep toward the target's current position.
			var cur := (_beam_aim - eye).angle()
			var want := (tpos - eye).angle()
			var step := deg_to_rad(_cfg.sweep) * delta
			cur += clampf(wrapf(want - cur, -PI, PI), -step, step)
			_beam_aim = eye + Vector2.from_angle(cur) * _cfg.range * PX
			_beam_end = _cast(eye, _beam_aim, _cfg.beam_dps * delta)
			if _beam_t <= 0.0:
				_beam_phase = 0
				_fire_cd = _cfg.beam_cd


## Ray from `from` toward `to` (range-limited); damages the first thing hit that can
## take damage. Returns the end point.
func _cast(from: Vector2, to: Vector2, damage := 0.0) -> Vector2:
	var end: Vector2 = from + (to - from).normalized() * _cfg.range * PX
	var q := PhysicsRayQueryParameters2D.create(from, end, 1)
	q.exclude = [get_rid()]
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return end
	if damage > 0.0 and hit.collider.has_method("take_damage"):
		hit.collider.take_damage(damage, from, false)
	return hit.position


func _line_of_sight(t: CollisionObject2D) -> bool:
	var q := PhysicsRayQueryParameters2D.create(global_position, t.global_position, 1)
	q.exclude = [get_rid()]
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and hit.collider == t


## Line of fire on the target (only every 3rd tick; cached in between).
func _line_of_fire(t: Node2D) -> bool:
	if _tick % 3 == 0:
		_lof_cache = t is CollisionObject2D and _line_of_sight(t as CollisionObject2D)
	return _lof_cache


func _steer_dir(desired: Vector2) -> Vector2:
	var space := get_world_2d().direct_space_state
	var exclude := [get_rid()]
	if _player:
		exclude.append(_player.get_rid())
	if target is CollisionObject2D:
		exclude.append((target as CollisionObject2D).get_rid())
	var dirs: Array[Vector2] = []
	var dangers: Array[float] = []
	for i in RAYS:
		var d := Vector2.from_angle(TAU * i / RAYS)
		var q := PhysicsRayQueryParameters2D.create(global_position, global_position + d * (radius + FEELER), 1)
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		var danger := 0.0
		if not hit.is_empty():
			danger = 1.0 - clampf((global_position.distance_to(hit.position) - radius) / FEELER, 0.0, 1.0)
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


func _die(dir: Vector2) -> void:
	state = State.DEAD
	Game.add_stat("kills")
	remove_from_group("illuminate")
	remove_from_group("enemies")
	_col.set_deferred("disabled", true)
	Sfx.play("voteless_death" if kind == Kind.VOTELESS else "illuminate_death", global_position, 0.0, 0.1)
	Sfx.hold(str(get_instance_id()), "", global_position, false)
	z_index = -1
	velocity = Vector2.ZERO
	_beam_phase = 0
	rotation = (dir as Vector2).angle() + PI / 2.0 + randf_range(-0.5, 0.5)
	var proj := get_tree().get_first_node_in_group("projectiles")
	if proj and kind != Kind.VOTELESS:
		proj.add_puff(global_position, 3.0 if kind == Kind.HARVESTER else 1.5)
	if kind == Kind.WATCHER or kind == Kind.ELEVATED:
		_dead_t = 25.0 # wrecks of flyers fade sooner


# --- Drawing ---------------------------------------------------------------

func _draw() -> void:
	var dead := state == State.DEAD
	var fade := clampf(30.0 - _dead_t, 0.0, 1.0)
	var lift := 0.0
	if flying and not dead:
		lift = 3.0 * sin(_bob)
		# Shadow on the ground (flyers hover).
		draw_set_transform(Vector2(10, 14).rotated(-rotation), 0.0)
		draw_circle(Vector2.ZERO, radius * 1.1, Color(0, 0, 0, 0.3))
		draw_set_transform(Vector2.ZERO)
	if kind == Kind.HARVESTER and not dead:
		_draw_beam()
	var s := radius / 15.0
	draw_set_transform(Vector2(0, -lift), 0.0, Vector2(s, s))
	var hit_tint := _flash > 0.0
	match kind:
		Kind.VOTELESS:
			_draw_voteless(dead, hit_tint)
		Kind.OVERSEER, Kind.ELEVATED:
			_draw_overseer(dead, hit_tint)
		Kind.WATCHER:
			_draw_watcher(dead, hit_tint)
		Kind.FLESHMOB:
			_draw_fleshmob(dead, hit_tint, fade)
		Kind.HARVESTER:
			_draw_harvester(dead, hit_tint)
	if _stun_t > 0.0:
		var a := Time.get_ticks_msec() * 0.006
		for i in 3:
			draw_circle(Vector2(0, -8) + Vector2.from_angle(a + i * TAU / 3.0) * 10.0, 1.6, UiStyle.YELLOW)
	draw_set_transform(Vector2.ZERO)
	if shield > 0.0 and not dead:
		var sr: float = _cfg.shield_r
		var al := 0.12 + 0.25 * (shield / max_shield) + (0.35 if _shield_flash > 0.0 else 0.0)
		draw_circle(Vector2.ZERO, sr, Color(GLOW, al * 0.35))
		draw_arc(Vector2.ZERO, sr, 0, TAU, 40, Color(GLOW, al + 0.2), 3.0)
	if not _numbers.is_empty():
		var font := ThemeDB.fallback_font
		draw_set_transform(Vector2.ZERO, -get_viewport().get_canvas_transform().get_rotation() - global_rotation)
		for n in _numbers:
			var al: float = 1.0 - n.t / 0.9
			var col := Color(1, 0.35, 0.2, al) if n.crit else Color(1, 0.95, 0.5, al)
			if n.text == "SHIELD":
				col = Color(GLOW, al)
			draw_string(font, Vector2(n.x - 50, -radius - 14 - n.t * 40.0), n.text, HORIZONTAL_ALIGNMENT_CENTER, 100, 20 if n.crit else 16, col)
		draw_set_transform(Vector2.ZERO)


func _draw_voteless(dead: bool, hit: bool) -> void:
	var skin := SKIN.darkened(0.4) if dead else (SKIN.lerp(Color.WHITE, 0.5) if hit else SKIN)
	var stride := sin(_walk_phase) * (0.0 if dead else 1.0)
	if dead:
		draw_circle(Vector2.ZERO, 16.0, Color(0.15, 0.05, 0.1, 0.35))
	for side in [-1.0, 1.0]:
		var hand := Vector2(side * 9.0, -12.0 + stride * side * 5.0)
		draw_line(Vector2(side * 7.0, -2), hand, OUTLINE, 5.0)
		draw_line(Vector2(side * 7.0, -2), hand, skin.darkened(0.15), 3.0)
	draw_circle(Vector2(0, 1), 10.0, OUTLINE)
	draw_circle(Vector2(0, 1), 8.8, Color(0.3, 0.27, 0.3) if not dead else Color(0.18, 0.16, 0.18)) # rags
	draw_circle(Vector2(0, -5), 5.6, OUTLINE)
	draw_circle(Vector2(0, -5), 4.6, skin.lightened(0.15))
	if not dead:
		draw_circle(Vector2(-1.8, -7), 1.2, PURPLE)
		draw_circle(Vector2(1.8, -7), 1.2, PURPLE)


func _draw_overseer(dead: bool, hit: bool) -> void:
	var robe := ROBE.darkened(0.5) if dead else (Color.WHITE if hit else ROBE)
	var glow := Color(0.2, 0.2, 0.25) if dead else GLOW
	if dead:
		draw_circle(Vector2.ZERO, 18.0, Color(0.1, 0.1, 0.15, 0.35))
	if kind == Kind.ELEVATED:
		# Jetpack on the back (weak spot).
		for side in [-1.0, 1.0]:
			draw_rect(Rect2(side * 7.0 - 4.0, 6, 8, 10), OUTLINE)
			draw_rect(Rect2(side * 7.0 - 3.0, 7, 6, 8), ROBE_DARK)
			if not dead:
				draw_circle(Vector2(side * 7.0, 17), 3.5 + sin(_bob * 4.0), Color(glow, 0.8))
	# Shoulders / robe
	var body := PackedVector2Array([Vector2(-13, 2), Vector2(-9, -6), Vector2(9, -6), Vector2(13, 2), Vector2(8, 10), Vector2(-8, 10)])
	draw_colored_polygon(Geometry2D.offset_polygon(body, 1.4)[0], OUTLINE)
	draw_colored_polygon(body, robe)
	draw_line(Vector2(0, -5), Vector2(0, 9), ROBE_DARK, 2.0)
	# Elongated head
	draw_set_transform(Vector2(0, -9) * (radius / 15.0), 0.0, Vector2(0.8, 1.25) * (radius / 15.0))
	draw_circle(Vector2.ZERO, 5.5, OUTLINE)
	draw_circle(Vector2.ZERO, 4.5, Color(0.55, 0.5, 0.6) if not dead else Color(0.3, 0.28, 0.32))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(radius / 15.0, radius / 15.0))
	draw_circle(Vector2(0, -12), 1.6, glow)
	# Staff (right hand) with glowing tip
	draw_line(Vector2(11, 6), Vector2(11, -24), OUTLINE, 4.0)
	draw_line(Vector2(11, 6), Vector2(11, -24), ROBE_DARK, 2.0)
	draw_circle(Vector2(11, -25), 3.0 + (2.0 if _muzzle_flash > 0.0 else 0.0), glow)


func _draw_watcher(dead: bool, hit: bool) -> void:
	var shell := ROBE_DARK.darkened(0.5) if dead else (Color.WHITE if hit else ROBE_DARK)
	for side in [-1.0, 1.0]:
		draw_colored_polygon(PackedVector2Array([Vector2(side * 8, -2), Vector2(side * 20, 4), Vector2(side * 8, 8)]), OUTLINE)
	draw_circle(Vector2.ZERO, 11.0, OUTLINE)
	draw_circle(Vector2.ZERO, 9.6, shell)
	draw_circle(Vector2(0, -3), 5.5, OUTLINE)
	var eye := Color(0.25, 0.25, 0.3) if dead else (Color(1, 0.3, 0.3) if _call_t > 0.0 else GLOW)
	draw_circle(Vector2(0, -3), 4.4, eye)
	if not dead and _call_t > 0.0:
		var k: float = clampf(_call_t / _cfg.call_time, 0.0, 1.0)
		draw_arc(Vector2.ZERO, 18.0, -PI / 2.0, -PI / 2.0 + TAU * k, 24, Color(1, 0.3, 0.3, 0.9), 2.5)


func _draw_fleshmob(dead: bool, hit: bool, fade: float) -> void:
	var flesh := FLESH.darkened(0.5) if dead else (FLESH.lerp(Color.WHITE, 0.4) if hit else FLESH)
	var lumps := [Vector2(0, 0), Vector2(-8, -5), Vector2(8, -6), Vector2(-6, 7), Vector2(7, 6), Vector2(0, -10)]
	var wob := 0.0 if dead else sin(_walk_phase) * 1.2
	for l in lumps:
		draw_circle(l * (1.0 + wob * 0.03), 8.5, OUTLINE)
	for i in lumps.size():
		draw_circle(lumps[i] * (1.0 + wob * 0.03), 7.3, flesh.darkened(0.08 * (i % 3)))
	if not dead:
		for h in [Vector2(-6, -12), Vector2(4, -13), Vector2(11, -3), Vector2(-11, 2)]:
			draw_circle(h, 2.8, OUTLINE)
			draw_circle(h, 2.0, SKIN.lightened(0.2))
	else:
		draw_circle(Vector2.ZERO, 20.0, Color(0.3, 0.05, 0.08, 0.35 * fade))


func _draw_harvester(dead: bool, hit: bool) -> void:
	var hull := ROBE_DARK.darkened(0.6) if dead else (Color.WHITE if hit else ROBE_DARK)
	var stride := _walk_phase
	# Three long legs reaching out to the ground.
	for i in 3:
		var a := TAU * i / 3.0 + PI / 2.0
		var swing := 0.0 if dead else sin(stride + i * TAU / 3.0) * 0.25
		var knee := Vector2.from_angle(a + swing) * 16.0
		var foot := Vector2.from_angle(a + swing * 1.5) * 34.0
		draw_line(Vector2.ZERO, knee, OUTLINE, 6.0)
		draw_line(knee, foot, OUTLINE, 5.0)
		draw_line(Vector2.ZERO, knee, hull, 3.5)
		draw_line(knee, foot, hull.lightened(0.1), 3.0)
		draw_circle(foot, 3.0, OUTLINE)
	draw_circle(Vector2.ZERO, 12.0, OUTLINE)
	draw_circle(Vector2.ZERO, 10.5, hull)
	draw_circle(Vector2(0, 2), 6.0, ROBE.darkened(0.3) if not dead else hull)
	draw_circle(Vector2(0, -7.5), 4.2, OUTLINE)
	var eye := Color(0.3, 0.1, 0.1) if dead else Color(1, 0.2 + (0.5 if _beam_phase > 0 else 0.0), 0.2)
	draw_circle(Vector2(0, -7.5), 3.2, eye)


## Beam in local space (drawn before the body).
func _draw_beam() -> void:
	if _beam_phase == 0:
		return
	var eye := Vector2(0, -radius * 0.5)
	var end := to_local(_beam_end)
	if _beam_phase == 1:
		var k: float = 1.0 - _beam_t / _cfg.charge
		draw_line(eye, end, Color(1, 0.3, 0.3, 0.25 + 0.4 * k), 1.5 + 2.0 * k)
	else:
		draw_line(eye, end, Color(1, 0.35, 0.3, 0.35), 14.0)
		draw_line(eye, end, Color(1, 0.75, 0.6, 0.95), 4.0)
		draw_circle(end, 9.0, Color(1, 0.6, 0.4, 0.7))


func _exit_tree() -> void:
	Sfx.hold(str(get_instance_id()), "", Vector2.ZERO, false)
