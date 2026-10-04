class_name Automaton
extends CharacterBody2D
## Automaton enemy (Helldivers 2 bots). One script, four kinds:
##   TROOPER     light infantry; keeps 9-14 m, strafes, fires blaster bursts; weak head
##   BERSERKER   chainsaw arms; walks straight at you and never stops; weak head
##   DEVASTATOR  armored heavy (body AC3) with a heavy blaster; weak head
##   HULK        walking tank: front AC5 / sides AC4 / rear vents AC2 (weak spot x2),
##               glowing eye (AC3, crit); flamethrower at short range
## Shared behaviour:
## - Patrols after a squad leader. Sees the player in a cone with line of sight; hears
##   sounds (loudness here >= 100 - hearing).
## - Engaged: ranged bots hold their preferred distance (closing in when they lose
##   sight), turn to face you and shoot laser bolts that cover and walls stop.
## - Spotting the player / being shot alerts its squad and reports to the mission,
##   which may call a bot drop.
## - Stagger: impact = weapon stagger / weight (bots are heavy; Hulks shrug most off).
## - Far from the player it thinks/steers less often (performance).

enum Kind { TROOPER, BERSERKER, DEVASTATOR, HULK }
enum State { PATROL, ENGAGE, SEARCH, STUNNED, DEAD }

const PX := Firearm.PX_PER_M
const LOD_FAR_M := 30.0
const SLEEP_M := 55.0
const SLEEP_EVERY := 4
const KNOCKBACK := 300.0
const STUN_DECAY := 0.5
const STUN_TIME := 0.8
const SQUAD_ALERT_M := 22.0
const RAYS := 16
const FEELER := 60.0
const OUTLINE := Color(0.06, 0.06, 0.07)
const METAL := Color(0.24, 0.24, 0.26)
const METAL_DARK := Color(0.15, 0.15, 0.17)
const RED := Color(1.0, 0.18, 0.12)

## Per-kind stats. Speeds are fractions of the player's base walk speed.
## weapon: "blaster" (bursts of bolts), "chainsaw" (melee), "flamer" (short cone).
const KINDS := {
	Kind.TROOPER: {"name": "Trooper", "hp": 90.0, "weight": 80.0, "radius": 13.0, "speed": 0.95, "patrol": 0.3,
		"sight": 8.0, "fov": 80.0, "armor": [1, 1, 1], "head": 5.0, "crit": 2.5, "turn": 260.0,
		"weapon": "blaster", "range": 16.0, "keep": Vector2(9.0, 14.0), "burst": 3, "burst_gap": 0.12,
		"burst_cd": 1.7, "bolt_damage": 8.0, "spread": 3.0, "bolt_speed": 28.0},
	Kind.BERSERKER: {"name": "Berserker", "hp": 350.0, "weight": 260.0, "radius": 17.0, "speed": 0.8, "patrol": 0.3,
		"sight": 7.0, "fov": 80.0, "armor": [2, 2, 2], "head": 6.0, "crit": 2.0, "turn": 200.0,
		"weapon": "chainsaw", "reach": 0.9, "dps": 45.0},
	Kind.DEVASTATOR: {"name": "Devastator", "hp": 650.0, "weight": 420.0, "radius": 21.0, "speed": 0.6, "patrol": 0.25,
		"sight": 9.0, "fov": 80.0, "armor": [3, 3, 3], "head": 6.0, "crit": 2.5, "turn": 160.0,
		"weapon": "blaster", "range": 16.0, "keep": Vector2(7.0, 12.0), "burst": 5, "burst_gap": 0.1,
		"burst_cd": 2.3, "bolt_damage": 10.0, "spread": 4.0, "bolt_speed": 26.0},
	Kind.HULK: {"name": "Hulk", "hp": 1600.0, "weight": 1600.0, "radius": 32.0, "speed": 0.55, "patrol": 0.2,
		"sight": 9.0, "fov": 90.0, "armor": [5, 4, 2], "head": 7.0, "crit": 2.0, "turn": 110.0,
		"weapon": "flamer", "range": 6.0, "dps": 35.0, "cone": 25.0, "rear_mult": 2.0, "eye_armor": 3},
}

@export var kind := Kind.TROOPER
@export var hearing := 85.0

var hp := 100.0
var max_hp := 100.0
var weight := 100.0
var radius := 15.0
var state := State.PATROL
var squad_id := -1
var leader: Automaton = null
## Hulk flamer currently spewing (drawn).
var flaming := false

var _cfg: Dictionary
var _player: CharacterBody2D
var _col: CollisionShape2D
var _goal := Vector2.ZERO
var _patrol_t := 0.0
var _offset := Vector2.ZERO
var _steer := Vector2.UP
var _detour := 0
var _detour_time := 0.0
var _tick := 0
var _walk_phase := 0.0
var _flash := 0.0
var _dead_t := 0.0
var _stun_meter := 0.0
var _stun_t := 0.0
var _numbers: Array[Dictionary] = []
var _burst_left := 0
var _burst_t := 0.0
var _fire_cd := 1.0
var _strafe := 1.0
var _strafe_t := 0.0
var _seen_t := 0.0
var _muzzle_flash := 0.0


func _ready() -> void:
	_cfg = KINDS[kind]
	max_hp = _cfg.hp
	hp = max_hp
	weight = _cfg.weight
	radius = _cfg.radius
	add_to_group("automatons")
	add_to_group("enemies")
	add_to_group("concealable")
	if kind == Kind.HULK:
		add_to_group("hulks")
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 2
	collision_mask = 3
	_col = CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = radius
	_col.shape = shape
	add_child(_col)
	_tick = randi() % 6
	rotation = randf() * TAU
	_strafe = 1.0 if randf() < 0.5 else -1.0
	_player = get_tree().get_first_node_in_group("player")
	_new_patrol()


static func make(k: Kind) -> Automaton:
	var a := Automaton.new()
	a.kind = k
	return a


## Squad mix: mostly troopers, some berserkers/devastators.
static func random_kind(heavies := true) -> Kind:
	var r := randf()
	if r < 0.6 or not heavies:
		return Kind.TROOPER
	if r < 0.82:
		return Kind.BERSERKER
	return Kind.DEVASTATOR


static func spawn_squad(parent: Node, center: Vector2, size: int, id: int, is_free: Callable, kinds: Array = []) -> Array[Automaton]:
	var out: Array[Automaton] = []
	var lead: Automaton = null
	for attempt in size * 6:
		if out.size() >= size:
			break
		var p := center if out.is_empty() else center + Vector2.from_angle(randf() * TAU) * randf_range(50.0, 150.0)
		if not is_free.call(p):
			continue
		var k: Kind = kinds[out.size() % kinds.size()] if not kinds.is_empty() else random_kind()
		var a := Automaton.make(k)
		a.position = p
		parent.add_child(a)
		if lead == null:
			lead = a
		a.join_squad(id, lead)
		out.append(a)
	return out


func join_squad(id: int, lead: Automaton) -> void:
	squad_id = id
	leader = lead if lead != self else null
	_offset = Vector2.from_angle(randf() * TAU) * randf_range(1.5, 3.0) * PX


func is_dead() -> bool:
	return state == State.DEAD


func kind_name() -> String:
	return _cfg.name


func alert_to(pos: Vector2, engage := false) -> void:
	if state == State.DEAD or state == State.ENGAGE:
		return
	if engage:
		_engage()
	else:
		state = State.SEARCH
		_goal = pos


func hear(pos: Vector2, loudness: float, falloff_pct: float) -> void:
	if state != State.PATROL and state != State.SEARCH:
		return
	var level := FirearmStats.loudness_at(loudness, falloff_pct, global_position.distance_to(pos) / PX)
	if level >= 100.0 - hearing:
		state = State.SEARCH
		var vague := lerpf(6.0, 1.0, clampf(level / 60.0, 0.0, 1.0))
		_goal = pos + Vector2(randf_range(-vague, vague), randf_range(-vague, vague)) * PX


## Armor class met by a hit travelling in `dir` (front, side, rear).
func _zone(dir: Vector2) -> int:
	var d := dir.normalized().dot(Vector2.UP.rotated(rotation))
	if d < -0.5:
		return 0 # front: bullet flies against our facing
	if d > 0.5:
		return 2 # rear
	return 1


func take_hit(hit: Dictionary) -> void:
	if state == State.DEAD:
		return
	var zone := _zone(hit.dir)
	var armor: int = _cfg.armor[zone]
	var head_c := global_position + Vector2.UP.rotated(rotation) * radius * 0.45
	var crit := zone == 0 and Combat.is_crit(hit, head_c, _cfg.head, 30.0)
	var mult := 1.0
	if crit:
		armor = _cfg.get("eye_armor", 0)
		mult = _cfg.crit
	elif zone == 2 and _cfg.has("rear_mult"):
		mult = _cfg.rear_mult
		crit = true
	if hit.get("explosive", false):
		armor = mini(armor, 3)
	var dmg: float = hit.damage * FirearmStats.armor_factor(hit.armor_penetration, armor) * mult
	hp -= dmg
	_flash = 0.08
	if not hit.get("explosive", false):
		Sfx.play("hit_armor" if dmg <= 0.0 else "hit_metal", global_position, -6.0, 0.1)
	var text := "BLOCK" if dmg <= 0.0 else ("CRIT %d" if crit else "%d") % roundi(dmg)
	_numbers.append({"text": text, "t": 0.0, "crit": crit, "x": randf_range(-10, 10)})
	var impact: float = hit.get("stagger", 0.0) / weight
	velocity += (hit.dir as Vector2) * impact * KNOCKBACK
	_stun_meter += impact
	if _stun_meter >= 1.0:
		_stun_meter = 0.0
		_stun_t = STUN_TIME
	if hp <= 0.0:
		_die(hit.dir)
		return
	if state != State.ENGAGE:
		_engage()


func _physics_process(delta: float) -> void:
	_flash = maxf(_flash - delta, 0.0)
	_muzzle_flash = maxf(_muzzle_flash - delta, 0.0)
	for n in _numbers:
		n.t += delta
	_numbers = _numbers.filter(func(n): return n.t < 0.9)
	if state == State.DEAD:
		_dead_t += delta
		if _dead_t > 45.0:
			queue_free()
		queue_redraw()
		return
	_stun_meter = maxf(_stun_meter - STUN_DECAY * delta, 0.0)
	flaming = false
	if _stun_t > 0.0:
		_stun_t -= delta
		velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
		move_and_slide()
		queue_redraw()
		return
	_tick += 1
	var dist2 := global_position.distance_squared_to(_player.global_position) if _player else INF
	var far := dist2 > pow(LOD_FAR_M * PX, 2)
	if state == State.PATROL and dist2 > pow(SLEEP_M * PX, 2) and _tick % SLEEP_EVERY != 0:
		return
	if _tick % (15 if far else 5) == 0:
		_perceive()

	var walk: float = (_player.move_speed if _player else 180.0)
	var speed := 0.0
	var face := _steer
	var to_player := (_player.global_position - global_position) if _player else Vector2.ZERO
	var dist_m := to_player.length() / PX
	var player_ok: bool = _player != null and not _player.dead and not _player.deploying
	match state:
		State.PATROL:
			_patrol_t -= delta
			if leader != null and is_instance_valid(leader) and not leader.is_dead():
				_goal = leader.global_position + _offset
				speed = walk * _cfg.patrol * (1.6 if global_position.distance_to(_goal) > 3.0 * PX else 0.0)
			else:
				if _patrol_t <= 0.0 or global_position.distance_to(_goal) < 30.0:
					_new_patrol()
				speed = walk * _cfg.patrol
		State.SEARCH:
			speed = walk * _cfg.speed * 0.8
			if global_position.distance_to(_goal) < 40.0:
				_new_patrol()
		State.ENGAGE:
			if not player_ok:
				_new_patrol()
			else:
				if _tick % 3 == 0:
					if _line_of_sight(_player):
						_seen_t = 0.0
						_goal = _player.global_position
					else:
						_seen_t += delta * 3.0
				face = to_player.normalized()
				speed = walk * _cfg.speed
				match _cfg.weapon:
					"blaster":
						var keep: Vector2 = _cfg.keep
						if _seen_t > 0.5 or dist_m > keep.y:
							_goal = _player.global_position # close in / regain sight
						elif dist_m < keep.x:
							_goal = global_position - to_player.normalized() * 3.0 * PX
						else:
							_strafe_t -= delta
							if _strafe_t <= 0.0:
								_strafe_t = randf_range(1.5, 3.0)
								_strafe = -_strafe
							_goal = global_position + to_player.normalized().orthogonal() * _strafe * 2.0 * PX
							speed *= 0.5
						_update_blaster(delta, dist_m, to_player)
					"chainsaw":
						_goal = _player.global_position
						if dist_m * PX < radius + 16.0 + _cfg.reach * PX:
							speed *= 0.3
							_player.take_damage(_cfg.dps * delta, global_position, false)
					"flamer":
						_goal = _player.global_position
						if dist_m <= _cfg.range and absf(Vector2.UP.rotated(rotation).angle_to(to_player)) < deg_to_rad(_cfg.cone) \
								and _seen_t < 0.3:
							flaming = true
							speed *= 0.4
							_player.take_damage(_cfg.dps * delta, global_position, false)

	if _cfg.weapon != "blaster":
		var sawing: bool = state == State.ENGAGE and _cfg.weapon == "chainsaw" and dist_m < 4.0
		Sfx.hold(str(get_instance_id()), _cfg.weapon, global_position, flaming or sawing, -2.0)
	if _tick % (9 if far else 3) == 0 and speed > 0.0:
		_steer = _steer.lerp(_steer_dir((_goal - global_position).normalized()), 0.5).normalized()
	var move_dir := _steer
	if state != State.ENGAGE:
		face = _steer
	var want := face.angle() + PI / 2.0
	var max_step := deg_to_rad(_cfg.turn) * delta
	rotation += clampf(wrapf(want - rotation, -PI, PI), -max_step, max_step)
	velocity = velocity.move_toward(move_dir * speed, 900.0 * delta)
	move_and_slide()
	_walk_phase = fmod(_walk_phase + clampf(velocity.length() / maxf(walk, 1.0), 0.0, 1.5) * 1.6 * TAU * delta, TAU)
	queue_redraw()


func _update_blaster(delta: float, dist_m: float, to_player: Vector2) -> void:
	_fire_cd -= delta
	var aimed := absf(Vector2.UP.rotated(rotation).angle_to(to_player)) < deg_to_rad(15.0)
	if _burst_left <= 0:
		if _fire_cd <= 0.0 and aimed and dist_m <= _cfg.range and _seen_t < 0.3:
			_burst_left = _cfg.burst
			_burst_t = 0.0
		return
	_burst_t -= delta
	if _burst_t <= 0.0:
		_burst_t = _cfg.burst_gap
		_burst_left -= 1
		var dir := to_player.normalized().rotated(deg_to_rad(randf_range(-1.0, 1.0) * _cfg.spread))
		var muzzle := global_position + Vector2.UP.rotated(rotation) * (radius + 6.0) + Vector2.RIGHT.rotated(rotation) * radius * 0.5
		var proj := get_tree().get_first_node_in_group("projectiles")
		proj.spawn_bolt(muzzle, dir * _cfg.bolt_speed * PX, _cfg.bolt_damage, self)
		Sfx.play("bot_heavy_blaster" if kind == Kind.DEVASTATOR else "bot_blaster", muzzle, -4.0, 0.08)
		_muzzle_flash = 0.06
		if _burst_left <= 0:
			_fire_cd = _cfg.burst_cd * randf_range(0.8, 1.2)


func _perceive() -> void:
	if not _player or _player.dead or _player.deploying:
		return
	if state == State.ENGAGE:
		return
	var to := _player.global_position - global_position
	var dist := to.length()
	var in_cone: bool = dist <= _cfg.sight * PX and absf(Vector2.UP.rotated(rotation).angle_to(to)) <= deg_to_rad(_cfg.fov / 2.0)
	if (in_cone or dist <= 1.5 * PX) and _line_of_sight(_player):
		_engage()


func _engage() -> void:
	state = State.ENGAGE
	_fire_cd = randf_range(0.4, 1.0) # reaction time
	_seen_t = 0.0
	if _player:
		_goal = _player.global_position
	for n in get_tree().get_nodes_in_group("automatons"):
		var o := n as Automaton
		if o != self and o.squad_id == squad_id and squad_id >= 0 and o.state != State.ENGAGE and o.state != State.DEAD \
				and o.global_position.distance_to(global_position) <= SQUAD_ALERT_M * PX:
			o.state = State.ENGAGE
			o._fire_cd = randf_range(0.6, 1.4)
	get_tree().call_group("mission", "on_enemy_alert", self)


func _new_patrol() -> void:
	state = State.PATROL
	_patrol_t = randf_range(5.0, 10.0)
	_goal = global_position + Vector2.from_angle(randf() * TAU) * randf_range(3.0, 10.0) * PX


func _line_of_sight(target: CollisionObject2D) -> bool:
	var q := PhysicsRayQueryParameters2D.create(global_position, target.global_position, 1)
	q.exclude = [get_rid()]
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and hit.collider == target


func _steer_dir(desired: Vector2) -> Vector2:
	var space := get_world_2d().direct_space_state
	var exclude := [get_rid()]
	if _player:
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
	remove_from_group("automatons")
	remove_from_group("enemies")
	remove_from_group("hulks")
	_col.set_deferred("disabled", true)
	Sfx.play("bot_death", global_position, 0.0, 0.1)
	Sfx.hold(str(get_instance_id()), "", global_position, false)
	z_index = -1
	velocity = Vector2.ZERO
	rotation = (dir as Vector2).angle() + PI / 2.0 + randf_range(-0.5, 0.5)
	var proj := get_tree().get_first_node_in_group("projectiles")
	if proj and kind != Kind.TROOPER:
		proj.add_puff(global_position, 2.0)


# --- Drawing ---------------------------------------------------------------

func _draw() -> void:
	var dead := state == State.DEAD
	var metal := METAL.darkened(0.45) if dead else (METAL.lerp(Color.WHITE, 0.5) if _flash > 0.0 else METAL)
	var dark := METAL_DARK.darkened(0.4) if dead else METAL_DARK
	var eye := Color(0.25, 0.08, 0.06) if dead else RED
	if dead:
		draw_circle(Vector2.ZERO, radius * 1.4, Color(0.05, 0.05, 0.05, 0.4 * clampf(45.0 - _dead_t, 0.0, 1.0)))
	var stride := sin(_walk_phase) * (0.0 if dead else 1.0)
	var s := radius / 15.0
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
	# Feet (mechanical)
	for side in [-1.0, 1.0]:
		var fp := Vector2(side * 8.0, -3.0 + stride * side * 6.0)
		draw_rect(Rect2(fp - Vector2(4.5, 6), Vector2(9, 12)), OUTLINE)
		draw_rect(Rect2(fp - Vector2(3.2, 4.8), Vector2(6.4, 9.6)), dark)
	match kind:
		Kind.HULK:
			# Rear heat vents (weak spot)
			for side in [-1.0, 1.0]:
				draw_rect(Rect2(Vector2(side * 9.0 - 4.0, 9.0), Vector2(8, 6)), OUTLINE)
				draw_rect(Rect2(Vector2(side * 9.0 - 3.0, 10.0), Vector2(6, 4)), Color(1, 0.45, 0.1) if not dead else dark)
			_box(Rect2(-17, -12, 34, 22), metal)
			_box(Rect2(-12, -16, 24, 8), dark)
			# Flamer arm (right) and claw (left)
			_box(Rect2(10, -24, 7, 16), dark)
			_box(Rect2(-17, -20, 7, 12), dark)
			draw_circle(Vector2(0, -12), 4.0, OUTLINE)
			draw_circle(Vector2(0, -12), 3.0, eye)
			if flaming:
				var pts := PackedVector2Array([Vector2(13.5, -24)])
				var reach: float = _cfg.range * PX / s
				var w := tan(deg_to_rad(_cfg.cone)) * reach
				pts.append(Vector2(13.5 - w, -24 - reach))
				pts.append(Vector2(13.5 + w * 0.3, -24 - reach * 1.05))
				draw_colored_polygon(pts, Color(1, 0.55, 0.15, 0.55))
				draw_colored_polygon(PackedVector2Array([Vector2(13.5, -24), Vector2(13.5 - w * 0.4, -24 - reach * 0.6),
					Vector2(13.5 + w * 0.2, -24 - reach * 0.6)]), Color(1, 0.9, 0.4, 0.7))
		Kind.BERSERKER:
			_box(Rect2(-12, -6, 24, 14), metal)
			# Chainsaw arms
			for side in [-1.0, 1.0]:
				var x: float = side * 13.0
				_box(Rect2(x - 3.0, -22, 6, 18), dark)
				draw_line(Vector2(x, -22), Vector2(x, -4), Color(0.7, 0.7, 0.7, 0.8) if not dead else dark, 1.5)
			_box(Rect2(-5, -12, 10, 8), dark)
			draw_rect(Rect2(-4, -11, 8, 2), eye)
		Kind.DEVASTATOR:
			_box(Rect2(-15, -7, 30, 16), metal)
			_box(Rect2(-18, -9, 7, 9), dark) # shoulder plates
			_box(Rect2(11, -9, 7, 9), dark)
			_box(Rect2(11, -24, 6, 16), dark) # arm cannon
			_box(Rect2(-5, -13, 10, 8), dark)
			draw_rect(Rect2(-4, -12, 8, 2), eye)
		_:
			_box(Rect2(-10, -5, 20, 11), metal)
			_box(Rect2(7, -20, 3, 14), dark) # rifle
			_box(Rect2(-4, -11, 8, 7), dark)
			draw_rect(Rect2(-3, -10, 6, 2), eye)
	if _muzzle_flash > 0.0:
		var mx := 13.5 if kind == Kind.DEVASTATOR else 8.5
		draw_circle(Vector2(mx, -26), 4.0, Color(1, 0.4, 0.3, 0.9))
	if _stun_t > 0.0:
		var a := Time.get_ticks_msec() * 0.006
		for i in 3:
			draw_circle(Vector2(0, -8) + Vector2.from_angle(a + i * TAU / 3.0) * 10.0, 1.6, UiStyle.YELLOW)
	draw_set_transform(Vector2.ZERO)
	if not _numbers.is_empty():
		var font := ThemeDB.fallback_font
		draw_set_transform(Vector2.ZERO, -get_viewport().get_canvas_transform().get_rotation() - global_rotation)
		for n in _numbers:
			var al: float = 1.0 - n.t / 0.9
			var col := Color(1, 0.35, 0.2, al) if n.crit else Color(1, 0.95, 0.5, al)
			draw_string(font, Vector2(n.x - 50, -radius - 14 - n.t * 40.0), n.text, HORIZONTAL_ALIGNMENT_CENTER, 100, 20 if n.crit else 16, col)
		draw_set_transform(Vector2.ZERO)


func _box(r: Rect2, col: Color) -> void:
	draw_rect(r.grow(1.3), OUTLINE)
	draw_rect(r, col)


func _exit_tree() -> void:
	Sfx.hold(str(get_instance_id()), "", Vector2.ZERO, false)
