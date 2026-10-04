class_name Mission
extends Node2D
## Sample bug mission "Operation: Swift Liberty" (Helldivers 2 style).
## 0. Hellpod drop at the landing zone.
## 1. Upload data at 2 terminals (each draws a horde).
## 2. Close 3 bug holes (explosives: grenades, Eagle, Orbital, EAT); they spawn bugs
##    while you are near.
## 3. (Optional) Kill the Charger guarding the holes.
## 4. Call Pelican-1 at the extraction pad, hold until it lands, board it.
## Bug breaches: when bugs keep fighting you for a while they call reinforcements out
## of the ground nearby (cooldown between breaches).
## 25 min mission clock, 5 reinforcements (each arrives by hellpod).
## Also draws hellpods, breaches and Pelican-1 (world space, above everything).

enum Phase { ACTIVE, EXTRACTING, SHUTTLE, COMPLETE, FAILED }

@export var mission_time := 25.0 * 60.0
@export var reinforcements := 5
@export var extract_time := 90.0
## Ambient bugs kept on the map.
@export var ambient_target := 22
## Hard cap on live bugs (performance).
@export var bug_cap := 50
## s of continued fighting before bugs call a breach, and cooldown between breaches.
@export var breach_call_time := 9.0
@export var breach_cooldown := 60.0

const PX := Firearm.PX_PER_M
const NAME := "OPERATION: SWIFT LIBERTY"
const HELLPOD_FALL := 2.0
const HELLPOD_BLAST := {"radius_m": 2.5, "damage": 600.0, "ap": 5, "armor_damage": 200.0, "destruction": 30,
	"stagger": 800.0, "sound": 130.0, "sound_falloff": 8.0, "self_mult": 0.0}

var phase := Phase.ACTIVE
var time_left := 0.0
var elapsed := 0.0
var extract_left := 0.0
## Seconds until the dead player is reinforced (-1 = not pending).
var respawn_in := -1.0
var fail_reason := ""
## {id, text, done, optional, count, total, targets: Array[Vector2], active}
var objectives: Array[Dictionary] = []
## {text, t}
var messages: Array[Dictionary] = []

var map: MissionMap
var player: CharacterBody2D
var _terminals: Array[Interactable] = []
var _console: Interactable
var _nests: Array[Destructible] = []
var _guard: Charger
var _breaches: Array[Dictionary] = []
var _breach_cd := 30.0
var _breach_call := -1.0
var _deploy_t := HELLPOD_FALL
var _setup_ticks := 0
var _pack_id := 1000
var _ambient_t := 0.0
var _nest_t := 0.0
var _wave_t := 0.0
var _extract_charger := false
var _board_t := 0.0
var _shuttle_t := 0.0
var _death_pos := Vector2.ZERO
var _pod_pos := Vector2.INF
var _pod_t := 0.0
var _end_t := 0.0


func _ready() -> void:
	add_to_group("mission")
	z_index = 20
	z_as_relative = false
	process_mode = Node.PROCESS_MODE_PAUSABLE
	map = get_node("../Map")
	player = get_node("../Player")
	time_left = mission_time
	player.global_position = map.drop_zone
	player.look_angle = 0.0
	player.rotation = 0.0
	# Hellpod insertion: hidden until the pod lands.
	player.deploying = true
	player.visible = false
	_pod_pos = map.drop_zone
	_pod_t = HELLPOD_FALL

	for p in map.terminal_spots:
		var t := Interactable.make(Interactable.Kind.TERMINAL)
		t.position = p
		t.activated.connect(_on_terminal)
		map.add_child(t)
		_terminals.append(t)
	_console = Interactable.make(Interactable.Kind.EXTRACT_CONSOLE)
	_console.position = map.console_spot
	_console.activated.connect(_on_extract_called)
	map.add_child(_console)
	for p in map.ammo_spots:
		var a := Interactable.make(Interactable.Kind.AMMO)
		a.position = p
		a.activated.connect(_on_ammo)
		map.add_child(a)
	for n in get_tree().get_nodes_in_group("nests"):
		var nest := n as Destructible
		nest.destroyed.connect(_on_nest_destroyed)
		_nests.append(nest)

	objectives = [
		{"id": "terminals", "text": "UPLOAD DATA AT TERMINALS", "done": false, "optional": false,
			"count": 0, "total": _terminals.size(), "targets": map.terminal_spots.duplicate(), "active": true},
		{"id": "nests", "text": "CLOSE BUG HOLES (EXPLOSIVES)", "done": false, "optional": false,
			"count": 0, "total": _nests.size(), "targets": map.nest_spots.duplicate(), "active": true},
		{"id": "charger", "text": "KILL THE CHARGER", "done": false, "optional": true,
			"count": 0, "total": 1, "targets": [map.nest_clearing], "active": true},
		{"id": "extract", "text": "CALL PELICAN-1", "done": false, "optional": false,
			"count": 0, "total": 0, "targets": [map.extraction], "active": false},
	]
	msg(NAME)
	msg("HELLPOD INBOUND")


func objective(id: String) -> Dictionary:
	for o in objectives:
		if o.id == id:
			return o
	return {}


func msg(text: String) -> void:
	messages.append({"text": text, "t": 0.0})
	if messages.size() > 4:
		messages.pop_front()


func is_over() -> bool:
	return phase == Phase.COMPLETE or phase == Phase.FAILED


func _physics_process(delta: float) -> void:
	for m in messages:
		m.t += delta
	messages = messages.filter(func(m): return m.t < 5.0)
	if _pod_t > 0.0:
		_pod_t = maxf(_pod_t - delta, 0.0)
	if player.deploying and _setup_ticks > 3:
		_deploy_t -= delta
		if _deploy_t <= 0.0:
			_land_pod(map.drop_zone)
			player.deploying = false
			player.visible = true
			_pod_pos = Vector2.INF
			msg("FOR SUPER EARTH!")
	queue_redraw()

	# Wait a couple of ticks so the map's bodies are in the physics space.
	_setup_ticks += 1
	if _setup_ticks == 3:
		_initial_spawns()
	if _setup_ticks < 3 or is_over():
		if is_over():
			_end_t += delta
		return

	elapsed += delta
	time_left -= delta
	if time_left <= 0.0:
		_fail("MISSION TIME EXPIRED")
		return
	_update_death(delta)
	_update_breaches(delta)
	_update_ambient(delta)
	_update_nests(delta)
	_check_charger()
	match phase:
		Phase.EXTRACTING:
			_update_extraction(delta)
		Phase.SHUTTLE:
			_update_boarding(delta)


func _initial_spawns() -> void:
	for i in 7:
		_spawn_pack_far(map.drop_zone, 45.0, 140.0, randi_range(3, 5))
	var gp := map.random_point_near(map.nest_clearing, 12.0, 18.0)
	if gp != Vector2.INF:
		_guard = _spawn_charger(gp)


# --- Spawning --------------------------------------------------------------

func _bug_count() -> int:
	return get_tree().get_nodes_in_group("terminids").size()


func _spawn_pack_at(center: Vector2, size: int, kinds: Array = []) -> Array[Terminid]:
	if _bug_count() + size > bug_cap:
		size = maxi(bug_cap - _bug_count(), 0)
	if size <= 0:
		return []
	_pack_id += 1
	return Terminid.spawn_pack(map, center, size, _pack_id, func(p): return map.is_free(p), kinds)


func _spawn_pack_far(away: Vector2, min_m: float, max_m: float, size: int) -> Array[Terminid]:
	var p := map.random_point_near(away, min_m, max_m)
	if p == Vector2.INF:
		return []
	return _spawn_pack_at(p, size)


func _spawn_charger(p: Vector2) -> Charger:
	var g := Charger.new()
	g.position = p
	map.add_child(g)
	return g


## Horde converging on `target` from 30-40 m away.
func _horde(target: Vector2, packs: int, chase := false) -> void:
	for i in packs:
		for z in _spawn_pack_far(target, 30.0, 40.0, randi_range(4, 6)):
			z.alert_to(target, chase)


func _update_ambient(delta: float) -> void:
	_ambient_t -= delta
	if _ambient_t > 0.0:
		return
	_ambient_t = 20.0
	if _bug_count() < ambient_target:
		_spawn_pack_far(player.global_position, 45.0, 80.0, randi_range(3, 5))


func _update_nests(delta: float) -> void:
	_nest_t -= delta
	if _nest_t > 0.0:
		return
	_nest_t = 14.0
	for nest in _nests:
		if nest.is_destroyed():
			continue
		var d := nest.global_position.distance_to(player.global_position) / PX
		if d > 45.0 or _bug_count() >= bug_cap:
			continue
		var p := map.random_point_near(nest.global_position, 2.5, 4.0, 8)
		if p == Vector2.INF:
			continue
		_pack_id += 1
		var kinds := [Terminid.Kind.SCAVENGER, Terminid.Kind.SCAVENGER, Terminid.Kind.WARRIOR]
		for z in Terminid.spawn_pack(map, p, 2, _pack_id, func(q): return map.is_free(q), [kinds.pick_random()]):
			z.alert_to(player.global_position, d < 20.0)


# --- Objectives --------------------------------------------------------------

func _on_ammo(_it: Interactable) -> void:
	player.resupply()
	msg("RESUPPLIED")


func _on_terminal(_it: Interactable) -> void:
	var o := objective("terminals")
	o.count += 1
	msg("DATA UPLOADED %d/%d" % [o.count, o.total])
	_horde(_it.global_position, 2 + o.count)
	_remove_target(o, _it.global_position)
	if o.count >= o.total:
		o.done = true
		msg("OBJECTIVE COMPLETE: DATA UPLOADED")
	_check_main_done()


func _on_nest_destroyed(nest: Destructible) -> void:
	var o := objective("nests")
	o.count += 1
	msg("BUG HOLE CLOSED %d/%d" % [o.count, o.total])
	_remove_target(o, nest.global_position)
	if o.count >= o.total:
		o.done = true
		msg("OBJECTIVE COMPLETE: BUG HOLES")
	_check_main_done()


func _check_charger() -> void:
	var o := objective("charger")
	if not o.done and _guard and _guard.is_dead():
		o.done = true
		o.count = 1
		o.targets = []
		msg("CHARGER KILLED")
	elif not o.done and _guard and is_instance_valid(_guard):
		o.targets = [_guard.global_position]


func _remove_target(o: Dictionary, pos: Vector2) -> void:
	var keep: Array = []
	for t in o.targets:
		if (t as Vector2).distance_to(pos) > 60.0:
			keep.append(t)
	o.targets = keep


func _check_main_done() -> void:
	if objective("terminals").done and objective("nests").done and not _console.enabled:
		_console.enabled = true
		objective("extract").active = true
		msg("EXTRACTION AVAILABLE - CALL PELICAN-1")


func _on_extract_called(_it: Interactable) -> void:
	phase = Phase.EXTRACTING
	extract_left = extract_time
	_wave_t = 3.0
	var o := objective("extract")
	o.text = "DEFEND THE LANDING ZONE"
	msg("PELICAN-1 INBOUND")


func _update_extraction(delta: float) -> void:
	extract_left -= delta
	_wave_t -= delta
	if _wave_t <= 0.0:
		_wave_t = 14.0
		_horde(map.extraction, 1, true)
	if not _extract_charger and extract_left <= extract_time * 0.5:
		_extract_charger = true
		var p := map.random_point_near(map.extraction, 28.0, 36.0)
		if p != Vector2.INF:
			_spawn_charger(p).alert_to(map.extraction)
		msg("CHARGER INCOMING")
	if extract_left <= 0.0:
		phase = Phase.SHUTTLE
		_shuttle_t = 0.0
		objective("extract").text = "BOARD PELICAN-1"
		msg("PELICAN-1 HAS LANDED - GET ON BOARD")


func _update_boarding(delta: float) -> void:
	_shuttle_t += delta
	var on_pad: bool = not player.dead and player.global_position.distance_to(map.extraction) < 6.0 * PX
	if _shuttle_t > 3.0 and on_pad:
		_board_t += delta
		if _board_t >= 2.0:
			_complete()
	else:
		_board_t = 0.0


func board_progress() -> float:
	return _board_t / 2.0


func _complete() -> void:
	phase = Phase.COMPLETE
	objective("extract").done = true
	msg("MISSION COMPLETE")


func _fail(reason: String) -> void:
	phase = Phase.FAILED
	fail_reason = reason
	msg("MISSION FAILED")


# --- Death / reinforcement ------------------------------------------------------

func _update_death(delta: float) -> void:
	if not player.dead:
		return
	if respawn_in < 0.0:
		_death_pos = player.global_position
		if reinforcements <= 0:
			_fail("NO REINFORCEMENTS LEFT")
			return
		respawn_in = 4.0
		msg("REINFORCING - HELLPOD INBOUND")
		return
	respawn_in -= delta
	if respawn_in <= 1.0 and _pod_pos == Vector2.INF:
		_pod_pos = _safe_respawn_point()
		_pod_t = 1.0
		player.visible = false
	if respawn_in <= 0.0:
		reinforcements -= 1
		_land_pod(_pod_pos)
		player.revive(_pod_pos)
		msg("REINFORCED")
		player.look_angle = player.rotation
		respawn_in = -1.0
		_pod_pos = Vector2.INF


## Hellpod impact: kills bugs under it, leaves a scorch.
func _land_pod(at: Vector2) -> void:
	var proj := get_tree().get_first_node_in_group("projectiles")
	proj.explode(at, HELLPOD_BLAST)
	player.visible = true


## Bugs report fighting the player; sustained fighting calls a breach.
func on_bug_alert(_bug: Node) -> void:
	if _breach_cd <= 0.0 and _breach_call < 0.0 and not is_over():
		_breach_call = breach_call_time


func _update_breaches(delta: float) -> void:
	_breach_cd = maxf(_breach_cd - delta, 0.0)
	if _breach_call >= 0.0:
		_breach_call -= delta
		if _breach_call < 0.0:
			var fighting := false
			for n in get_tree().get_nodes_in_group("terminids"):
				if (n as Terminid)._engaged():
					fighting = true
					break
			if fighting:
				_start_breach()
	for b in _breaches:
		b.t += delta
		if b.t >= 2.5 and not b.done:
			b.done = true
			var kinds := []
			for i in randi_range(8, 12):
				kinds.append(Terminid.random_kind())
			for z in _spawn_pack_at(b.pos, kinds.size(), kinds):
				z.alert_to(player.global_position, true)
			if elapsed > 180.0 and randf() < 0.35:
				_spawn_charger(b.pos + Vector2(60, 0)).alert_to(player.global_position)
	_breaches = _breaches.filter(func(b): return b.t < 4.0)


func _start_breach() -> void:
	var p := map.random_point_near(player.global_position, 14.0, 22.0)
	if p == Vector2.INF:
		return
	_breach_cd = breach_cooldown
	_breaches.append({"pos": p, "t": 0.0, "done": false})
	msg("BUG BREACH!")


func _safe_respawn_point() -> Vector2:
	for i in 20:
		var p := map.random_point_near(_death_pos, 12.0, 25.0, 4)
		if p == Vector2.INF:
			continue
		var clear := true
		for e in get_tree().get_nodes_in_group("enemies"):
			if (e as Node2D).global_position.distance_to(p) < 10.0 * PX:
				clear = false
				break
		if clear:
			return p
	return map.drop_zone


# --- Drawing (shuttle, drop pod) ------------------------------------------------

func _draw() -> void:
	if _pod_t > 0.0 and _pod_pos != Vector2.INF:
		# Incoming hellpod: growing shadow, fiery streak from the sky.
		var total := HELLPOD_FALL if player.deploying else 1.0
		var k := clampf(1.0 - _pod_t / total, 0.0, 1.0)
		draw_circle(_pod_pos, 40.0 * (0.4 + k * 0.6), Color(0, 0, 0, 0.35 * k))
		var top := _pod_pos + Vector2(0, -900.0 * (1.0 - k))
		draw_line(top + Vector2(0, -220), top, Color(1, 0.6, 0.2, 0.7), 10.0)
		draw_circle(top, 16.0, Color(0.25, 0.26, 0.28))
		draw_circle(top, 9.0, UiStyle.YELLOW)
	for b in _breaches:
		var k: float = clampf(b.t / 2.5, 0.0, 1.0)
		var shake := Vector2(randf_range(-3, 3), randf_range(-3, 3)) * (1.0 - k)
		draw_circle(b.pos + shake, 40.0 + k * 90.0, Color(0.3, 0.2, 0.12, 0.6))
		for i in 7:
			var a := TAU * i / 7.0 + 0.3
			draw_line(b.pos, b.pos + Vector2.from_angle(a) * (40.0 + k * 120.0), Color(0.1, 0.07, 0.05, 0.8), 4.0)
		if b.t >= 2.5:
			draw_circle(b.pos, 60.0, Color(0.55, 0.45, 0.1, 0.4 * (4.0 - b.t)))
	if phase == Phase.SHUTTLE or (phase == Phase.COMPLETE and _shuttle_t > 0.0):
		var k := clampf(_shuttle_t / 3.0, 0.0, 1.0)
		var c := map.extraction + Vector2(0, -(1.0 - k) * 900.0)
		draw_circle(map.extraction, 160.0 * (0.4 + k * 0.6), Color(0, 0, 0, 0.35 * k))
		_draw_shuttle(c, 1.0 + (1.0 - k) * 0.5)


func _draw_shuttle(c: Vector2, s: float) -> void:
	var outline := Color(0.06, 0.06, 0.06)
	var hull := Color(0.33, 0.36, 0.34)
	var body := PackedVector2Array([Vector2(0, -150), Vector2(55, -90), Vector2(60, 120), Vector2(0, 150),
		Vector2(-60, 120), Vector2(-55, -90)])
	var wings := PackedVector2Array([Vector2(-170, 10), Vector2(170, 10), Vector2(150, 60), Vector2(-150, 60)])
	var t := Transform2D(0.0, Vector2(s, s), 0.0, c)
	draw_colored_polygon(t * wings, outline)
	draw_colored_polygon(t * body, outline)
	draw_colored_polygon(t * Geometry2D.offset_polygon(wings, -4.0)[0], hull.darkened(0.15))
	draw_colored_polygon(t * Geometry2D.offset_polygon(body, -4.0)[0], hull)
	for x in [-130.0, 130.0]:
		draw_circle(t * Vector2(x, 35), 28.0 * s, outline)
		draw_circle(t * Vector2(x, 35), 22.0 * s, Color(0.2, 0.2, 0.2))
	draw_rect(Rect2(t * Vector2(-30, 60), Vector2(60, 70) * s), UiStyle.YELLOW.darkened(0.2))
	draw_circle(t * Vector2(0, -120), 12.0 * s, Color(0.4, 0.7, 1.0, 0.8))
