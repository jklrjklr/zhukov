class_name Mission
extends Node2D
## Defense mission "Operation: Bright Harbor" (Helldivers 2 style, Illuminate).
## Hold the evacuation site while colonists are launched to safety:
## 0. Hellpod drop inside the base.
## 1. Waves: Illuminate warp ships land at the edges of the map and unload squads that
##    march on the base through its gates and go for the generators (and anyone in the
##    way). Each wave is bigger; Harvesters join from wave 3.
## 2. When a wave is beaten an evac rocket launches (rockets 1..waves).
## 3. Keep at least one generator running: when all are down the site is lost.
## 4. After the last rocket, call Pelican-1 at the console, hold the pad while the final
##    assault comes in, board.
## Watchers that keep a Helldiver in sight call an extra warp ship on them.
## 30 min mission clock, 6 reinforcements (each arrives by hellpod).
## Also draws hellpods, warp ships, the evac rocket and Pelican-1 (world space, on top).

enum Phase { ACTIVE, EXTRACTING, SHUTTLE, COMPLETE, FAILED }

@export var mission_time := 30.0 * 60.0
@export var reinforcements := 6
@export var extract_time := 90.0
@export var waves := 5
## s before the first wave and between waves.
@export var first_break := 30.0
@export var wave_break := 20.0
## A wave ends when this few of its units are left (or after max_wave_time).
@export var wave_leftover := 3
@export var max_wave_time := 170.0
## Hard cap on live enemies (performance); ships wait to unload the rest.
@export var enemy_cap := 60

const PX := Firearm.PX_PER_M
const NAME := "OPERATION: BRIGHT HARBOR"
const HELLPOD_FALL := 2.0
const HELLPOD_BLAST := {"radius_m": 2.5, "damage": 600.0, "ap": 5, "armor_damage": 200.0, "destruction": 30,
	"stagger": 800.0, "sound": 130.0, "sound_falloff": 8.0, "self_mult": 0.0}
const SHIP_ARRIVE := 2.5
const UNLOAD_GAP := 0.3
const ROCKET_TIME := 5.0
const V := Illuminate.Kind.VOTELESS
const O := Illuminate.Kind.OVERSEER
const E := Illuminate.Kind.ELEVATED
const W := Illuminate.Kind.WATCHER
const F := Illuminate.Kind.FLESHMOB
const H := Illuminate.Kind.HARVESTER
## Units per wave: [voteless, overseers, elevated, watchers, fleshmobs, harvesters] and ships.
const WAVES := [
	{"mix": [12, 2, 0, 1, 0, 0], "ships": 1},
	{"mix": [16, 4, 2, 1, 0, 0], "ships": 2},
	{"mix": [18, 5, 3, 1, 1, 1], "ships": 2},
	{"mix": [20, 6, 4, 2, 2, 1], "ships": 3},
	{"mix": [24, 7, 5, 2, 2, 2], "ships": 3},
]

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
## Current wave (0 before the first), whether it is under way, and the break timer.
var wave := 0
var wave_active := false
var break_left := 0.0
var rockets := 0
var generators: Array[Generator] = []

var map: MissionMap
var player: CharacterBody2D
var _console: Interactable
var _wave_units: Array[Illuminate] = []
var _wave_t := 0.0
## Warp ships: {pos, t, queue: Array[int], next, done, dir, wave}
var _ships: Array[Dictionary] = []
var _rocket_t := -1.0
var _watcher_cd := 20.0
var _assault_t := 0.0
var _deploy_t := HELLPOD_FALL
var _setup_ticks := 0
var _board_t := 0.0
var _shuttle_t := 0.0
var _death_pos := Vector2.ZERO
var _pod_pos := Vector2.INF
var _pod_t := 0.0
var _end_t := 0.0
var _lost_generator := false


func _ready() -> void:
	add_to_group("mission")
	z_index = 20
	z_as_relative = false
	process_mode = Node.PROCESS_MODE_PAUSABLE
	map = get_node("../Map")
	player = get_node("../Player")
	time_left = mission_time
	break_left = first_break
	player.global_position = map.drop_zone
	player.look_angle = 0.0
	player.rotation = 0.0
	# Hellpod insertion: hidden until the pod lands.
	player.deploying = true
	player.visible = false
	_pod_pos = map.drop_zone
	_pod_t = HELLPOD_FALL

	var labels := ["A", "B", "C"]
	for i in map.generator_spots.size():
		var g := Generator.new()
		g.position = map.generator_spots[i]
		g.label = labels[i % labels.size()]
		g.destroyed.connect(_on_generator_destroyed)
		map.add_child(g)
		generators.append(g)
	_console = Interactable.make(Interactable.Kind.EXTRACT_CONSOLE)
	_console.position = map.console_spot
	_console.activated.connect(_on_extract_called)
	map.add_child(_console)
	for p in map.ammo_spots:
		var a := Interactable.make(Interactable.Kind.AMMO)
		a.position = p
		a.activated.connect(_on_ammo)
		map.add_child(a)

	objectives = [
		{"id": "evac", "text": "EVACUATE COLONISTS (ROCKETS)", "done": false, "optional": false,
			"count": 0, "total": waves, "targets": [map.rocket_pad], "active": true},
		{"id": "generators", "text": "KEEP THE GENERATORS RUNNING", "done": false, "optional": false,
			"count": generators.size(), "total": generators.size(), "targets": [], "active": true},
		{"id": "perfect", "text": "LOSE NO GENERATOR", "done": false, "optional": true,
			"count": 0, "total": 0, "targets": [], "active": true},
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
	Sfx.play_ui("objective", -6.0)
	if messages.size() > 4:
		messages.pop_front()


func is_over() -> bool:
	return phase == Phase.COMPLETE or phase == Phase.FAILED


## One line for the HUD wave panel.
func wave_status() -> String:
	if phase == Phase.EXTRACTING or phase == Phase.SHUTTLE:
		return "final assault  -  %d hostiles" % enemy_count()
	if wave_active:
		return "wave %d/%d  -  %d hostiles" % [wave, waves, enemy_count()]
	if _rocket_t >= 0.0:
		return "evac rocket %d launching" % rockets
	if wave >= waves:
		return "all colonists evacuated"
	return "wave %d/%d in %d s" % [wave + 1, waves, ceili(break_left)]


func enemy_count() -> int:
	return get_tree().get_nodes_in_group("illuminate").size()


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
			msg("DEFEND THE EVACUATION SITE")
	queue_redraw()

	_setup_ticks += 1
	if _setup_ticks < 3 or is_over():
		if is_over():
			_end_t += delta
		return

	elapsed += delta
	time_left -= delta
	if time_left <= 0.0:
		_fail("MISSION TIME EXPIRED")
		return
	_watcher_cd = maxf(_watcher_cd - delta, 0.0)
	_update_death(delta)
	_update_ships(delta)
	_update_rocket(delta)
	match phase:
		Phase.ACTIVE:
			_update_waves(delta)
		Phase.EXTRACTING:
			_update_extraction(delta)
		Phase.SHUTTLE:
			_update_boarding(delta)


# --- Waves ------------------------------------------------------------------

func _update_waves(delta: float) -> void:
	if wave_active:
		_wave_t += delta
		_wave_units = _wave_units.filter(func(u): return is_instance_valid(u) and not u.is_dead())
		var unloading := _ships.any(func(s): return s.wave == wave and not (s.queue as Array).is_empty())
		if (not unloading and _wave_units.size() <= wave_leftover) or _wave_t > max_wave_time:
			_end_wave()
		return
	if _rocket_t >= 0.0 or wave >= waves:
		return
	break_left -= delta
	if break_left <= 0.0:
		_start_wave()


func _start_wave() -> void:
	wave += 1
	wave_active = true
	_wave_t = 0.0
	var def: Dictionary = WAVES[mini(wave - 1, WAVES.size() - 1)]
	var units := _mix_list(def.mix)
	var count: int = def.ships
	var spots := map.spawn_points.duplicate()
	spots.shuffle()
	for i in count:
		var part: Array[int] = []
		for j in range(i, units.size(), count):
			part.append(units[j])
		_launch_ship(spots[i % spots.size()], part, wave)
	msg("WAVE %d - WARP SHIPS INBOUND" % wave)


## Unit list from a mix array, heavies spread through the list.
func _mix_list(mix: Array) -> Array[int]:
	var kinds := [V, O, E, W, F, H]
	var out: Array[int] = []
	for i in kinds.size():
		for n in int(mix[i]):
			out.append(kinds[i])
	out.shuffle()
	return out


func _end_wave() -> void:
	wave_active = false
	rockets += 1
	_rocket_t = 0.0
	var o := objective("evac")
	o.count = rockets
	msg("WAVE %d REPELLED - LAUNCHING EVAC ROCKET" % wave)
	break_left = wave_break


func _update_rocket(delta: float) -> void:
	if _rocket_t < 0.0:
		return
	_rocket_t += delta
	if _rocket_t >= ROCKET_TIME:
		_rocket_t = -1.0
		Sfx.play("evac_rocket", map.rocket_pad, 2.0)
		var o := objective("evac")
		msg("EVAC ROCKET %d/%d LAUNCHED" % [rockets, waves])
		if rockets >= waves and not o.done:
			o.done = true
			objective("generators").done = true
			if not _lost_generator:
				objective("perfect").done = true
			_console.enabled = true
			objective("extract").active = true
			msg("ALL COLONISTS EVACUATED - CALL PELICAN-1")


# --- Warp ships ---------------------------------------------------------------

func _launch_ship(at: Vector2, units: Array[int], wave_id: int) -> void:
	var p := at
	if not map.is_free(p, 40.0):
		var q := map.random_point_near(at, 2.0, 8.0)
		if q != Vector2.INF:
			p = q
	_ships.append({"pos": p, "t": 0.0, "queue": units, "next": 0.0, "dir": Vector2.from_angle(randf() * TAU),
		"wave": wave_id, "leave": -1.0})
	Sfx.play("warp_ship", p, 4.0)


func _update_ships(delta: float) -> void:
	for s in _ships:
		s.t += delta
		if s.t < SHIP_ARRIVE:
			continue
		var queue: Array = s.queue
		if queue.is_empty():
			if s.leave < 0.0:
				s.leave = s.t
			continue
		s.next -= delta
		if s.next > 0.0 or enemy_count() >= enemy_cap:
			continue
		s.next = UNLOAD_GAP
		var k: int = queue.pop_front()
		var got := Illuminate.spawn_group(map, s.pos, [k], func(q): return map.is_free(q, 20.0))
		for u in got:
			if s.wave > 0:
				_wave_units.append(u)
			else:
				u.alert_to(player.global_position, true)
	_ships = _ships.filter(func(s): return s.leave < 0.0 or s.t - s.leave < 3.0)


## A Watcher kept a Helldiver in sight: a warp ship lands near them.
func on_watcher_call(at: Vector2) -> void:
	if _watcher_cd > 0.0 or is_over():
		return
	var p := map.random_point_near(at, 18.0, 26.0)
	if p == Vector2.INF:
		return
	_watcher_cd = 45.0
	var units: Array[int] = [V, V, V, V, V, V, O, O]
	if elapsed > 300.0:
		units.append(E)
	_launch_ship(p, units, 0)
	msg("WATCHER CALLED REINFORCEMENTS!")


func on_enemy_alert(_e: Node) -> void:
	pass


# --- Objectives ------------------------------------------------------------

func _on_ammo(_it: Interactable) -> void:
	player.resupply()
	msg("RESUPPLIED")


func _on_generator_destroyed(g: Generator) -> void:
	_lost_generator = true
	var alive := generators.filter(func(x): return not x.is_destroyed()).size()
	var o := objective("generators")
	o.count = alive
	msg("GENERATOR %s DESTROYED - %d LEFT" % [g.label, alive])
	if alive == 0:
		_fail("EVACUATION SITE LOST")


func _on_extract_called(_it: Interactable) -> void:
	phase = Phase.EXTRACTING
	extract_left = extract_time
	_assault_t = 2.0
	var o := objective("extract")
	o.text = "DEFEND THE LANDING ZONE"
	msg("PELICAN-1 INBOUND")


func _update_extraction(delta: float) -> void:
	extract_left -= delta
	_assault_t -= delta
	if _assault_t <= 0.0:
		_assault_t = 18.0
		var spot: Vector2 = map.spawn_points[randi() % map.spawn_points.size()]
		var units: Array[int] = []
		for i in 8:
			units.append(V)
		units.append_array([O, O, E])
		if extract_left < extract_time * 0.6:
			units.append(F)
		_launch_ship(spot, units, 0)
	if extract_left <= 0.0:
		phase = Phase.SHUTTLE
		_shuttle_t = 0.0
		objective("extract").text = "BOARD PELICAN-1"
		msg("PELICAN-1 HAS LANDED - GET ON BOARD")


func _update_boarding(delta: float) -> void:
	_shuttle_t += delta
	Sfx.hold("pelican", "pelican", map.extraction, _shuttle_t < 12.0, -2.0)
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
	Sfx.hold("pelican", "", Vector2.ZERO, false)


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


## Hellpod impact: crushes enemies under it.
func _land_pod(at: Vector2) -> void:
	var proj := get_tree().get_first_node_in_group("projectiles")
	proj.explode(at, HELLPOD_BLAST)
	Sfx.play("hellpod_impact", at)
	player.visible = true


## Inside the base, away from enemies if possible.
func _safe_respawn_point() -> Vector2:
	for i in 20:
		var p := map.random_point_near(map.base_center, 2.0, 16.0, 4)
		if p == Vector2.INF or not map.is_inside_base(p):
			continue
		var clear := true
		for e in get_tree().get_nodes_in_group("enemies"):
			if (e as Node2D).global_position.distance_to(p) < 8.0 * PX:
				clear = false
				break
		if clear:
			return p
	return map.drop_zone


# --- Drawing --------------------------------------------------------------------

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
	for s in _ships:
		_draw_ship(s)
	_draw_rocket()
	if phase == Phase.SHUTTLE or (phase == Phase.COMPLETE and _shuttle_t > 0.0):
		var k := clampf(_shuttle_t / 3.0, 0.0, 1.0)
		var c := map.extraction + Vector2(0, -(1.0 - k) * 900.0)
		draw_circle(map.extraction, 160.0 * (0.4 + k * 0.6), Color(0, 0, 0, 0.35 * k))
		_draw_shuttle(c, 1.0 + (1.0 - k) * 0.5)


## Illuminate warp ship: glides in, hovers with a warp beam while unloading, leaves.
func _draw_ship(s: Dictionary) -> void:
	var t: float = s.t
	var dir: Vector2 = s.dir
	var off := 0.0
	if t < SHIP_ARRIVE:
		off = (SHIP_ARRIVE - t) * 700.0
	elif s.leave >= 0.0:
		off = -(t - s.leave) * 700.0
	var p: Vector2 = s.pos
	var c := p - dir * off
	var hover := t >= SHIP_ARRIVE and s.leave < 0.0
	draw_circle(p, 150.0, Color(0, 0, 0, 0.22 * clampf(t / SHIP_ARRIVE, 0.0, 1.0)))
	if hover:
		var pulse := 0.6 + 0.4 * sin(t * 6.0)
		draw_circle(p, 90.0, Color(0.6, 0.4, 1.0, 0.18 * pulse))
		draw_arc(p, 90.0, 0, TAU, 40, Color(0.75, 0.55, 1.0, 0.5 * pulse), 4.0)
	var tr := Transform2D(dir.angle() + PI / 2.0, c)
	var hull := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		hull.append(Vector2(cos(a) * 150.0, sin(a) * 70.0))
	var outline := Color(0.05, 0.05, 0.07)
	draw_colored_polygon(tr * Geometry2D.offset_polygon(hull, 5.0)[0], outline)
	draw_colored_polygon(tr * hull, Color(0.62, 0.62, 0.68))
	var ring := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		ring.append(Vector2(cos(a) * 70.0, sin(a) * 34.0))
	draw_colored_polygon(tr * ring, Color(0.45, 0.45, 0.52))
	draw_circle(tr * Vector2.ZERO, 22.0, Color(0.45, 0.95, 1.0, 0.9))
	for x in [-120.0, 120.0]:
		draw_circle(tr * Vector2(x, 0), 10.0, Color(0.7, 0.45, 1.0, 0.9))


## Evac rocket on its pad: fuelled while waves run, lifts off when one is beaten.
func _draw_rocket() -> void:
	var p := map.rocket_pad
	var lift := 0.0
	var a := 1.0
	if _rocket_t >= 0.0:
		var k := clampf((_rocket_t - 1.5) / (ROCKET_TIME - 1.5), 0.0, 1.0)
		lift = k * k * 1400.0
		a = 1.0 - k
		if _rocket_t > 1.0:
			draw_circle(p, 110.0 + 40.0 * sin(_rocket_t * 20.0), Color(0.9, 0.85, 0.75, 0.25))
	elif wave >= waves:
		return
	var c := p + Vector2(0, -lift)
	var outline := Color(0.06, 0.06, 0.06, a)
	if lift > 0.0:
		draw_line(c + Vector2(0, 60), c + Vector2(0, 60 + minf(lift, 500.0)), Color(1, 0.75, 0.3, 0.7 * a), 26.0)
	var body := PackedVector2Array([Vector2(0, -95), Vector2(22, -55), Vector2(22, 55), Vector2(-22, 55), Vector2(-22, -55)])
	var t := Transform2D(0.0, c)
	draw_colored_polygon(t * Geometry2D.offset_polygon(body, 4.0)[0], outline)
	draw_colored_polygon(t * body, Color(0.85, 0.85, 0.82, a))
	for x in [-30.0, 30.0]:
		draw_colored_polygon(t * PackedVector2Array([Vector2(x * 0.7, 25), Vector2(x * 1.4, 65), Vector2(x * 0.7, 55)]), Color(0.75, 0.15, 0.1, a))
	draw_rect(Rect2(t * Vector2(-22, -10), Vector2(44, 10)), Color(UiStyle.YELLOW, a))


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
