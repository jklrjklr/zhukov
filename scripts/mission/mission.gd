class_name Mission
extends Node2D
## v0.5 vertical slice: one Terminid planet.
##   Insertion zone -> passage -> Middle zone -> passage -> Extraction zone.
## Zones are 120 x 120 m (Zone), joined by 20 m roofed passages (Passage) that seal
## behind the player at their midline; the zone's uncleared objectives then FAIL.
## - Insertion: "Destroy bug nest" (3 holes). Middle: "Upload data" (hold a terminal 8 s
##   while bugs attack). Optional: "Kill elite" (a Charger). Extraction: terminal ->
##   Pelican-1 lands 3-5 s later -> board.
## - Two-stage timer: starts 8:00, each zone clear +1:30 (cap 10:00). At 2:00 the
##   Super Destroyer prepares to leave (meters stop); at 0:00 it has left (stratagems
##   lock, reinforcements escalate, any death ends the run).
## - 5 reinforcements: death -> hellpod 3 s later near the last position.
## - Stratagem meter points: kills (light 10 / medium 30 / heavy 150), objectives
##   (main 300 / optional 150).
## The HUD (scripts/ui/hud.gd) only reads hud_state(), the player and the Stratagems node.
## Also draws hellpods and Pelican-1 (world space, on top, via the Overlay child).

signal ended(state: int)

enum Stage { MAIN, DEPARTURE, DEPARTED }
enum End { NONE, WON, LOST }
enum Pelican { NONE, CALLED, LANDED, TAKEOFF }

const PX := Firearm.PX_PER_M
const NAME := "OPERATION: HIVE BREAKER"
const START_TIME := 480.0
const MAX_TIME := 600.0
const CLEAR_BONUS := 90.0
const DEPARTURE_AT := 120.0
const REINFORCEMENTS := 5
const RESPAWN_TIME := 3.0
const HELLPOD_FALL := 2.0
const HELLPOD_BLAST := {"radius_m": 2.5, "damage": 600.0, "ap": 5, "armor_damage": 200.0, "destruction": 30,
	"stagger": 800.0, "sound": 130.0, "sound_falloff": 8.0, "self_mult": 0.0}
const ZONE_STEP_M := 140.0
const UPLOAD_TIME := 8.0
const ENEMY_CAP := 45
const PELICAN_MIN := 3.0
const PELICAN_MAX := 5.0
const BOARD_RANGE_M := 7.0
const BOARD_TIME := 1.2
const FOG_CELLS := 24
## Combat music state is re-evaluated this often (s); the minimap data every MINIMAP_S.
const MUSIC_CHECK_S := 0.5
const MINIMAP_S := 0.2
const K := Vis.VISUAL_SCALE
const KILL_POINTS_LIGHT := 10.0
const KILL_POINTS_MEDIUM := 30.0
const KILL_POINTS_HEAVY := 150.0
const POINTS_MAIN := 300.0
const POINTS_OPTIONAL := 150.0

var stage := Stage.MAIN
var end_state := End.NONE
var end_reason := ""
## True once the end screen should be shown (the world is paused behind it).
var end_ready := false
var time_left := START_TIME
## Seconds of play (starts when the hellpod lands).
var elapsed := 0.0
var reinforcements := REINFORCEMENTS
var samples := 0
var respawn_in := -1.0
var current := 0
var zones: Array[Zone] = []
var passages: Array[Passage] = []
var player: CharacterBody2D
## {id, zone, text, type ("main"/"optional"/"extract"), status ("active"/"done"/"failed"),
##  count, total, progress 0..1, targets: Array[Vector2]}
var objectives: Array[Dictionary] = []
## {text, t}
var banners: Array[Dictionary] = []
## Recent kills for the HUD feed: {text, pts, t}
var kill_feed: Array[Dictionary] = []
var pelican := Pelican.NONE
var pelican_delay := 4.0
## Reset in tests / debugging.
var play_started := false

var _strat: Stratagems
var _actors: Node2D
var _overlay: Node2D
var _setup_ticks := 0
var _pod_pos := Vector2.INF
var _pod_t := 0.0
var _pod_total := HELLPOD_FALL
var _intro := true
var _death_pos := Vector2.ZERO
var _pack_id := 0
## Per-hole spawn bookkeeping: {node, zone, objective, t}
var _holes: Array[Dictionary] = []
var _pois: Array[Interactable] = []
var _terminal: Interactable
var _console: Interactable
var _elites := {} # zone -> Charger
var _patrol_t := 40.0
var _breach_cd := 20.0
var _breach_t := -1.0
var _breach_pos := Vector2.INF
var _upload_t := 0.0
var _upload_started := false
var _upload_mark := 0
var _pel_t := 0.0
var _board_t := 0.0
var _takeoff_t := 0.0
var _combat_t := 0.0
var _music_state := ""
var _music_check := 0.0
var _warned := {300.0: false, 60.0: false}
var _stage_prev := Stage.MAIN
var _passage_warning: Array[String] = []
var _explored := PackedByteArray()
var _fog_t := 0.0
var _end_t := 0.0
var _extract_hint := false
var _minimap := {}
var _minimap_at := -1.0
var _minimap_zone := -1
var _minimap_rev := 0


func _ready() -> void:
	Fx.reset()
	Enemies.clear()
	add_to_group("mission")
	player = get_node("../Player")
	_strat = get_node_or_null("../Stratagems") as Stratagems
	_actors = Node2D.new()
	_actors.name = "Actors"
	add_child(_actors)
	_overlay = Node2D.new()
	_overlay.name = "Overlay"
	_overlay.z_index = 20
	_overlay.z_as_relative = false
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_overlay.material = mat
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)

	var seed_base := randi()
	for i in 3:
		var z := Zone.new()
		z.name = "Zone%d" % i
		add_child(z)
		z.build(i, Vector2(0, -ZONE_STEP_M * i * PX), seed_base + i * 7919)
		zones.append(z)
	for i in 2:
		var p := Passage.new()
		p.name = "Passage%d" % i
		p.index = i
		add_child(p)
		p.build(Vector2(0, -(ZONE_STEP_M * i + ZONE_STEP_M * 0.5) * PX))
		passages.append(p)
	for i in 3:
		_build_zone_content(i)

	# Hellpod insertion: hidden until the pod lands.
	player.global_position = zones[0].start_pos
	player.look_angle = 0.0
	player.rotation = 0.0
	player.deploying = true
	player.visible = false
	_pod_pos = zones[0].start_pos
	_pod_t = HELLPOD_FALL
	_pod_total = HELLPOD_FALL
	_reset_fog()
	_ambience()
	announce(NAME, false)
	announce("HELLPOD INBOUND", false)
	Sfx.play_ui("hellpod_streak", -2.0)
	Warmup.run(self) # compile shader variants / load fight sounds now, not in the first fight
	Sfx.warm(Warmup.SOUNDS)


# --- Public API --------------------------------------------------------------------

func announce(text: String, chirp := true) -> void:
	banners.append({"text": text, "t": 0.0})
	if banners.size() > 4:
		banners.pop_front()
	if chirp:
		Sfx.play_ui("radio_chirp", -4.0)


func is_roofed(p: Vector2) -> bool:
	for ps in passages:
		if ps.is_roofed(p):
			return true
	return false


func is_over() -> bool:
	return end_state != End.NONE


func zone_objectives(zi: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for o in objectives:
		if o.zone == zi:
			out.append(o)
	return out


func main_objective(zi: int) -> Dictionary:
	for o in objectives:
		if o.zone == zi and o.type != "optional":
			return o
	return {}


func current_zone() -> Zone:
	return zones[current]


## Everything the HUD needs, as plain data (no node references).
func hud_state() -> Dictionary:
	var z := zones[current]
	_refresh_minimap()
	return {
		"mission_name": NAME,
		"zone_index": current,
		"zone_name": z.zone_name,
		"objectives": zone_objectives(current),
		"all_objectives": objectives,
		"time_left": time_left,
		"stage": ["main", "departure", "departed"][stage],
		"reinforcements": reinforcements,
		"samples": samples,
		"kills": int(Game.stats.get("kills", 0)),
		"banners": banners,
		"kill_feed": kill_feed,
		"passage_warning": _passage_warning,
		"respawn_in": respawn_in,
		"end": ["", "won", "lost"][end_state],
		"end_reason": end_reason,
		"end_ready": end_ready,
		"elapsed": elapsed,
		"pelican": ["none", "called", "landed", "takeoff"][pelican],
		"board_progress": _board_t / BOARD_TIME,
		"minimap": _minimap,
	}


## Minimap data is rebuilt every MINIMAP_S seconds (and when the zone changes), not per frame.
func _refresh_minimap() -> void:
	var now := Time.get_ticks_msec() * 0.001
	if not _minimap.is_empty() and now - _minimap_at < MINIMAP_S and _minimap_zone == current:
		return
	_minimap_at = now
	_minimap_zone = current
	var z := zones[current]
	var enemies_pos: Array = []
	var pp := player.global_position
	for n in Enemies.list:
		if n.global_position.distance_to(pp) < 24.0 * PX:
			enemies_pos.append({"pos": n.global_position, "alert": n.has_method("is_alerted") and n.is_alerted()})
	var pois: Array = []
	for it in _pois:
		if is_instance_valid(it) and not it.used and zones[current].contains(it.global_position):
			pois.append({"pos": it.global_position, "kind": "sample" if it.kind == Interactable.Kind.SAMPLE else "ammo"})
	var exit_pos := Vector2.INF
	if current < 2:
		exit_pos = z.exit_pt
	elif z.pad_pos != Vector2.INF:
		exit_pos = z.pad_pos
	_minimap_rev += 1
	_minimap = {
		"rev": _minimap_rev,
		"rect": z.rect, "player": pp, "look": player.look_angle, "explored": _explored, "cells": FOG_CELLS,
		"exit": exit_pos, "pois": pois, "enemies": enemies_pos,
		"targets": _active_targets(),
		"walls": z.walls, "floors": z.floors, "zone_pos": z.position, "entrance": z.entrance_pt,
		"main_done": main_objective(current).get("status", "") == "done",
	}


# --- Content ---------------------------------------------------------------------

func _build_zone_content(zi: int) -> void:
	var z := zones[zi]
	for p in z.crates:
		var c := Destructible.make(Destructible.Kind.CRATE)
		c.position = p
		_actors.add_child(c)
	for p in z.trees:
		var t := Destructible.make(Destructible.Kind.TREE)
		t.position = p
		_actors.add_child(t)
	# Outpost: bug holes spawn small bugs while alive. Insertion: the 3 holes ARE the objective.
	var hole_count := 3 if zi == 0 else 2
	var nests: Array = z.slots.nest
	for i in hole_count:
		var d := Destructible.make(Destructible.Kind.NEST)
		d.position = nests[i]
		_actors.add_child(d)
		var is_obj := zi == 0
		d.destroyed.connect(_on_hole_destroyed.bind(zi, is_obj))
		_holes.append({"node": d, "zone": zi, "objective": is_obj, "t": randf_range(3.0, 6.0)})
	# POIs: a sample and an ammo crate.
	var sample := Interactable.make(Interactable.Kind.SAMPLE)
	sample.position = (z.slots.sample as Array)[0]
	sample.activated.connect(_on_sample)
	_actors.add_child(sample)
	_pois.append(sample)
	var ammo := Interactable.make(Interactable.Kind.AMMO)
	ammo.position = (z.slots.ammo as Array)[0]
	ammo.activated.connect(_on_ammo)
	_actors.add_child(ammo)
	_pois.append(ammo)
	# Objectives.
	match zi:
		0:
			_add_objective(zi, "nest", "DESTROY BUG NEST", "main", 3)
			if randf() < 0.5:
				_add_objective(zi, "elite", "KILL ELITE", "optional", 1)
		1:
			_add_objective(zi, "upload", "UPLOAD DATA", "main", 1)
			_add_objective(zi, "elite", "KILL ELITE", "optional", 1)
			_terminal = Interactable.make(Interactable.Kind.TERMINAL)
			_terminal.hold_time = UPLOAD_TIME
			_terminal.label = "UPLOAD DATA"
			_terminal.position = z.terminal_pos
			_terminal.activated.connect(_on_upload_done)
			_actors.add_child(_terminal)
		2:
			_add_objective(zi, "extract", "CALL PELICAN-1", "extract", 1)
			_console = Interactable.make(Interactable.Kind.EXTRACT_CONSOLE)
			_console.enabled = true
			_console.label = "CALL PELICAN-1"
			_console.position = z.terminal_pos
			_console.activated.connect(_on_extract_called)
			_actors.add_child(_console)


func _add_objective(zi: int, id: String, text: String, type: String, total: int) -> void:
	objectives.append({"id": id, "zone": zi, "text": text, "type": type, "status": "active",
		"count": 0, "total": total, "progress": 0.0, "targets": []})


func _active_targets() -> Array:
	var out: Array = []
	for o in zone_objectives(current):
		if o.status != "active":
			continue
		match o.id:
			"nest":
				for h in _holes:
					if h.zone == current and h.objective and is_instance_valid(h.node) and not h.node.is_destroyed():
						out.append({"pos": h.node.global_position, "optional": false, "id": "nest"})
			"upload":
				out.append({"pos": _terminal.global_position, "optional": false, "id": "upload"})
			"elite":
				var e = _elites.get(current)
				if is_instance_valid(e) and not e.is_dead():
					out.append({"pos": e.global_position, "optional": true, "id": "elite"})
			"extract":
				out.append({"pos": _console.global_position, "optional": false, "id": "extract"})
	return out


func _activate_zone(zi: int) -> void:
	current = zi
	var z := zones[zi]
	if _strat == null:
		_strat = get_tree().get_first_node_in_group("stratagems") as Stratagems
	if _strat:
		_strat.new_zone()
	_reset_fog()
	_patrol_t = randf_range(25.0, 40.0)
	_breach_cd = 20.0
	_music("calm")
	announce(z.zone_name)
	match zi:
		0:
			announce("DESTROY THE BUG NEST - 3 HOLES", false)
		1:
			announce("UPLOAD DATA AT THE TERMINAL", false)
		2:
			announce("ACTIVATE THE EXTRACTION TERMINAL", false)
	# Guards: unaware packs on random slots away from the player.
	var packs: int = [5, 6, 5][zi]
	var slots: Array = (z.slots.pack as Array).duplicate()
	slots.shuffle()
	for p in slots:
		if packs <= 0:
			break
		if (p as Vector2).distance_to(player.global_position) < 22.0 * PX:
			continue
		var size := randi_range(3, 4) + (1 if zi > 0 else 0)
		var got := Terminid.spawn_pack(_actors, p, size, _next_pack(), _free_in_zone, [])
		if not got.is_empty():
			packs -= 1
	# Elite.
	for o in zone_objectives(zi):
		if o.id == "elite":
			var elite_slots: Array = z.slots.elite
			var spot: Vector2 = elite_slots[0]
			for e in elite_slots:
				if (e as Vector2).distance_to(player.global_position) > 32.0 * PX:
					spot = e
					break
			var c := Charger.new()
			c.position = spot
			_actors.add_child(c)
			_elites[zi] = c


func _next_pack() -> int:
	_pack_id += 1
	return _pack_id


func _free_in_zone(p: Vector2) -> bool:
	return zones[current].contains(p, -3.0 * PX) and _is_free(p, 24.0 * K)


func _is_free(p: Vector2, r: float) -> bool:
	var q := PhysicsShapeQueryParameters2D.new()
	var c := CircleShape2D.new()
	c.radius = r
	q.shape = c
	q.transform = Transform2D(0.0, p)
	return get_world_2d().direct_space_state.intersect_shape(q, 1).is_empty()


func _point_near(around: Vector2, min_m: float, max_m: float, in_zone := true, tries := 30) -> Vector2:
	for i in tries:
		var p := around + Vector2.from_angle(randf() * TAU) * randf_range(min_m, max_m) * PX
		if in_zone and not zones[current].contains(p, -3.0 * PX):
			continue
		if _is_free(p, 28.0 * K):
			return p
	return Vector2.INF


func enemy_count() -> int:
	return Enemies.list.size()


# --- Frame loop ---------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	for b in banners:
		b.t += delta
	banners = banners.filter(func(b): return b.t < 5.5)
	for k in kill_feed:
		k.t += delta
	kill_feed = kill_feed.filter(func(k): return k.t < 5.0)
	_overlay.queue_redraw()
	_setup_ticks += 1
	if end_state != End.NONE:
		_update_end(delta)
		return
	if _setup_ticks == 4:
		_activate_zone(0)
	if _intro:
		_update_intro(delta)
		return
	elapsed += delta
	_update_timer(delta)
	if end_state != End.NONE:
		return
	_update_death(delta)
	if end_state != End.NONE:
		return
	_update_passages()
	_update_holes(delta)
	_update_patrols(delta)
	_update_breach(delta)
	_update_objectives(delta)
	_update_pelican(delta)
	_update_music(delta)
	_update_fog(delta)


func _update_intro(delta: float) -> void:
	if _setup_ticks <= 4:
		return
	_pod_t = maxf(_pod_t - delta, 0.0)
	if _pod_t <= 0.0:
		_land_pod(zones[0].start_pos)
		player.deploying = false
		player.visible = true
		_pod_pos = Vector2.INF
		_intro = false
		play_started = true


## Hellpod impact: crushes enemies under it.
func _land_pod(at: Vector2) -> void:
	var proj := get_tree().get_first_node_in_group("projectiles")
	if proj:
		proj.explode(at, HELLPOD_BLAST)
	Fx.landing(self, at, 130.0)
	Sfx.play("hellpod_impact", at, 2.0)
	player.visible = true


# --- Timer ---------------------------------------------------------------------------

func _update_timer(delta: float) -> void:
	if stage != Stage.DEPARTED:
		time_left = maxf(time_left - delta, 0.0)
	_update_stage()
	for t in _warned:
		if time_left > t:
			_warned[t] = false
		elif not _warned[t] and time_left > 0.0:
			_warned[t] = true
			Sfx.play_ui("timer_warning", 0.0)
			announce("%d:%02d REMAINING" % [int(t) / 60, int(t) % 60])


## Stage follows the clock; entering a stage announces it.
func _update_stage() -> void:
	var s := Stage.MAIN
	if stage == Stage.DEPARTED or time_left <= 0.0:
		s = Stage.DEPARTED
	elif time_left <= DEPARTURE_AT:
		s = Stage.DEPARTURE
	stage = s
	if _strat == null:
		_strat = get_tree().get_first_node_in_group("stratagems") as Stratagems
	if _strat:
		_strat.fill_enabled = stage == Stage.MAIN
		_strat.locked = stage == Stage.DEPARTED
		if stage == Stage.DEPARTED:
			_strat.cancel(false)
	if stage == _stage_prev:
		return
	match stage:
		Stage.DEPARTURE:
			Sfx.play_ui("departure_alarm", 0.0)
			announce("SUPER DESTROYER PREPARING TO LEAVE LOW ORBIT.")
		Stage.DEPARTED:
			Sfx.play_ui("departure_alarm", 2.0)
			announce("SUPER DESTROYER HAS LEFT ORBIT.")
			_patrol_t = minf(_patrol_t, 4.0)
			_breach_cd = 0.0
		Stage.MAIN:
			announce("SUPER DESTROYER HOLDING ORBIT")
	_stage_prev = stage


func _zone_clear(zi: int) -> void:
	var was_departure := stage == Stage.DEPARTURE
	if stage != Stage.DEPARTED:
		time_left = minf(time_left + CLEAR_BONUS, MAX_TIME)
		if was_departure:
			time_left = maxf(time_left, DEPARTURE_AT + 1.0)
		announce("ZONE CLEARED  +1:30")
	else:
		announce("ZONE CLEARED")
	_update_stage()


# --- Objectives ----------------------------------------------------------------------

func complete_objective(o: Dictionary) -> void:
	if o.is_empty() or o.status != "active":
		return
	o.status = "done"
	o.progress = 1.0
	o.count = o.total
	Sfx.play_ui("objective_complete", 0.0)
	announce("OBJECTIVE COMPLETE: " + o.text)
	if o.type == "main":
		_zone_clear(o.zone)
	if _strat:
		_strat.add_points(POINTS_MAIN if o.type == "main" else POINTS_OPTIONAL)


func fail_objective(o: Dictionary) -> void:
	if o.status != "active":
		return
	o.status = "failed"
	Sfx.play_ui("objective_failed", 0.0)
	announce("OBJECTIVE FAILED: " + o.text, false)


func _on_hole_destroyed(d: Destructible, zi: int, is_obj: bool) -> void:
	Sfx.play("nest_hole_destroyed", d.global_position, 2.0)
	Sfx.play("debris", d.global_position, -2.0)
	if not is_obj:
		announce("BUG HOLE DESTROYED", false)
		return
	var o := main_objective(zi)
	if o.is_empty() or o.status != "active":
		return
	o.count += 1
	o.progress = float(o.count) / o.total
	if o.count >= o.total:
		complete_objective(o)
	else:
		Sfx.play_ui("objective_progress", 0.0)
		announce("BUG HOLE DESTROYED  %d/%d" % [o.count, o.total], false)


func _on_sample(_it: Interactable) -> void:
	samples += 1
	Sfx.play_ui("pickup_sample", 0.0)
	announce("SAMPLE COLLECTED", false)


func _on_ammo(_it: Interactable) -> void:
	player.resupply()
	Sfx.play_ui("pickup_ammo", 0.0)
	announce("RESUPPLIED", false)


func _on_upload_done(_it: Interactable) -> void:
	Sfx.hold("upload", "", Vector2.ZERO, false)
	Sfx.play_ui("terminal_beep", 0.0)
	complete_objective(main_objective(1))


func _update_objectives(delta: float) -> void:
	for o in objectives:
		if o.status != "active":
			continue
		if o.id == "elite" and o.zone == current:
			var e = _elites.get(o.zone)
			if e != null and (not is_instance_valid(e) or e.is_dead()):
				complete_objective(o)
	# Upload: progress follows the held terminal; bugs attack while it is held.
	var up := main_objective(1)
	if current == 1 and not up.is_empty() and up.status == "active" and _terminal.progress > 0.0:
		var f := _terminal.progress / _terminal.hold_time
		up.progress = f
		if not _upload_started:
			_upload_started = true
			_upload_t = 0.5
			Sfx.play_ui("terminal_beep", 0.0)
			announce("UPLOADING - HOLD THE TERMINAL", false)
		var mark := int(f * 4.0)
		if mark > _upload_mark and mark < 4:
			_upload_mark = mark
			Sfx.play_ui("objective_progress", -4.0)
		Sfx.hold("upload", "upload_loop", _terminal.global_position, true, -4.0)
		_upload_t -= delta
		if _upload_t <= 0.0:
			_upload_t = 3.5 if stage == Stage.DEPARTED else 4.5
			_spawn_attack_pack(randi_range(4, 6))
	else:
		_upload_started = false
		_upload_mark = 0
		Sfx.hold("upload", "", Vector2.ZERO, false)
		if not up.is_empty() and up.status == "active":
			up.progress = 0.0


## Pack that bursts in around the player and goes for them.
func _spawn_attack_pack(size: int) -> void:
	if enemy_count() >= ENEMY_CAP:
		return
	var at := _point_near(player.global_position, 14.0, 22.0)
	if at == Vector2.INF:
		return
	var got := Terminid.spawn_pack(_actors, at, size, _next_pack(), _free_in_zone, _kinds(size))
	if not got.is_empty():
		Sfx.play("burrow", at, 0.0)
	for t in got:
		t.alert_to(player.global_position, true)


## Kind list for a pack; escalates after departure.
func _kinds(size: int) -> Array:
	var out: Array = []
	for i in size:
		var k := Terminid.random_kind(current > 0)
		if stage == Stage.DEPARTED and randf() < 0.3:
			k = Terminid.Kind.WARRIOR
		out.append(k)
	return out


# --- Bug holes, patrols, breaches -----------------------------------------------------

func _update_holes(delta: float) -> void:
	for h in _holes:
		var d = h.node
		if not is_instance_valid(d) or d.is_destroyed() or h.zone != current:
			continue
		if d.global_position.distance_to(player.global_position) > 38.0 * PX:
			continue
		h.t -= delta
		if h.t > 0.0 or enemy_count() >= ENEMY_CAP:
			continue
		h.t = randf_range(3.5, 5.0) if stage == Stage.DEPARTED else randf_range(7.0, 11.0)
		for i in randi_range(1, 2):
			var t := Terminid.make(Terminid.Kind.SCAVENGER)
			t.position = d.global_position + Vector2.from_angle(randf() * TAU) * 44.0 * K
			_actors.add_child(t)
			t.alert_to(player.global_position, false)
		Sfx.play("burrow", d.global_position, 0.0)


func _update_patrols(delta: float) -> void:
	_patrol_t -= delta
	if _patrol_t > 0.0 or passages_blocking():
		return
	_patrol_t = randf_range(14.0, 22.0) if stage == Stage.DEPARTED else randf_range(40.0, 60.0)
	if enemy_count() >= ENEMY_CAP - 6:
		return
	var z := zones[current]
	var edges: Array = (z.slots.edge as Array).duplicate()
	edges.shuffle()
	for e in edges:
		if (e as Vector2).distance_to(player.global_position) < 28.0 * PX:
			continue
		var size := randi_range(3, 5) + (2 if stage == Stage.DEPARTED else 0)
		var got := Terminid.spawn_pack(_actors, e, size, _next_pack(), _free_in_zone, _kinds(size))
		var target := z.rect.get_center() + Vector2(randf_range(-20, 20), randf_range(-20, 20)) * PX
		for t in got:
			t.alert_to(target, false)
		return


## Nothing spawns while the player stands in a passage.
func passages_blocking() -> bool:
	for p in passages:
		if p.inside(player.global_position):
			return true
	return false


## Reinforcement calls: only an ALERT bug can call, and it has to stand and perform a visible ~2 s
## call (Terminid / Charger CALL state). request_call() rolls the chance and reserves the single
## call slot; finish_call() starts the breach (existing countdown, cooldowns and cap stay);
## cancel_call() (caller killed or staggered) cancels it, no breach.
var call_chance := 0.4
var _call_by: Node = null
var _call_roll_cd := 0.0


func _breach_possible() -> bool:
	return not (end_state != End.NONE or _intro or _breach_t >= 0.0 or _breach_cd > 0.0 or passages_blocking() \
		or enemy_count() >= ENEMY_CAP - 6)


func request_call(by: Node) -> bool:
	if _call_by != null and is_instance_valid(_call_by):
		return false
	if _call_roll_cd > 0.0 or not _breach_possible():
		return false
	_call_roll_cd = 4.0
	if randf() > call_chance:
		return false
	_call_by = by
	return true


func finish_call(by: Node) -> void:
	if _call_by != by:
		return
	_call_by = null
	if _breach_possible():
		_start_breach()


func cancel_call(by: Node) -> void:
	if _call_by == by:
		_call_by = null
		_call_roll_cd = 8.0


func is_calling() -> bool:
	return _call_by != null and is_instance_valid(_call_by)


## Old direct trigger (tests, scripted): rolls the chance and starts a breach right away.
func on_bug_alert(_bug: Node) -> void:
	if not _breach_possible() or randf() > 0.4:
		return
	_start_breach()


func _start_breach() -> void:
	var at := _point_near(player.global_position, 12.0, 18.0)
	if at == Vector2.INF:
		return
	_breach_pos = at
	_breach_t = 1.8
	_breach_cd = 12.0 if stage == Stage.DEPARTED else 30.0
	Sfx.play("breach", at, 4.0)
	announce("BUG BREACH!", false)


func _update_breach(delta: float) -> void:
	_breach_cd = maxf(_breach_cd - delta, 0.0)
	_call_roll_cd = maxf(_call_roll_cd - delta, 0.0)
	if _breach_t < 0.0:
		return
	_breach_t -= delta
	if _breach_t > 0.0:
		return
	_breach_t = -1.0
	var size := randi_range(4, 6) + (3 if stage == Stage.DEPARTED else 0)
	var got := Terminid.spawn_pack(_actors, _breach_pos, size, _next_pack(), _free_in_zone, _kinds(size))
	Fx.landing(self, _breach_pos, 90.0)
	if not got.is_empty():
		Sfx.play("burrow", _breach_pos, 2.0)
	for t in got:
		t.alert_to(player.global_position, true)
	_breach_pos = Vector2.INF


## Kill rewards (called by Terminid / Charger).
func on_kill(bug: Node) -> void:
	var pts := KILL_POINTS_MEDIUM
	var nm := "Bug"
	if bug is Charger:
		pts = KILL_POINTS_HEAVY
		nm = "Charger"
	elif bug is Terminid:
		nm = (bug as Terminid).kind_name()
		if (bug as Terminid).kind == Terminid.Kind.SCAVENGER:
			pts = KILL_POINTS_LIGHT
	kill_feed.append({"text": nm, "pts": int(pts), "t": 0.0})
	if kill_feed.size() > 5:
		kill_feed.pop_front()
	if _strat:
		_strat.add_points(pts)


# --- Passages -------------------------------------------------------------------------

func _update_passages() -> void:
	_passage_warning = []
	if player.dead:
		return
	for p in passages:
		if p.index != current or p.is_sealed:
			continue
		var pos := player.global_position
		if p.crossed(pos):
			_cross(p)
		elif p.approaching(pos):
			for o in zone_objectives(current):
				if o.status == "active" and o.type != "extract":
					_passage_warning.append(o.text)


func _cross(p: Passage) -> void:
	var from_zone := current
	p.seal()
	# Bugs caught in the seal come along (moved to the player's side).
	for e in get_tree().get_nodes_in_group("enemies"):
		var n := e as Node2D
		if p.seal_rect.grow(1.5 * PX).has_point(n.global_position):
			n.global_position.y = p.seal_rect.position.y - 1.5 * PX
	# Uncleared objectives of the zone left behind fail.
	for o in zone_objectives(from_zone):
		if o.status == "active" and o.type != "extract":
			fail_objective(o)
	announce("PASSAGE SEALED")
	# Everything left behind goes away.
	for e in get_tree().get_nodes_in_group("enemies"):
		var n := e as Node2D
		if n.global_position.y > p.seal_rect.position.y + p.seal_rect.size.y:
			n.queue_free()
	_holes = _holes.filter(func(h): return h.zone > from_zone)
	Sfx.hold("upload", "", Vector2.ZERO, false)
	_activate_zone(from_zone + 1)


# --- Death / reinforcement --------------------------------------------------------------

func _update_death(delta: float) -> void:
	if not player.dead:
		return
	if respawn_in < 0.0:
		_death_pos = player.global_position
		if stage == Stage.DEPARTED:
			_end(End.LOST, "THE SUPER DESTROYER HAS LEFT - NO REINFORCEMENTS")
			return
		if reinforcements <= 0:
			_end(End.LOST, "NO REINFORCEMENTS LEFT")
			return
		respawn_in = RESPAWN_TIME
		announce("REINFORCING - HELLPOD INBOUND")
		return
	if stage == Stage.DEPARTED:
		_end(End.LOST, "THE SUPER DESTROYER HAS LEFT - NO REINFORCEMENTS")
		return
	respawn_in -= delta
	if respawn_in <= 1.0 and _pod_pos == Vector2.INF:
		_pod_pos = _safe_respawn_point()
		_pod_t = 1.0
		_pod_total = 1.0
		player.visible = false
		Sfx.play("hellpod_streak", _pod_pos, 0.0)
	if respawn_in <= 0.0:
		reinforcements -= 1
		_land_pod(_pod_pos)
		player.revive(_pod_pos)
		player.look_angle = player.rotation
		Sfx.play_ui("reinforce", 0.0)
		announce("REINFORCED", false)
		respawn_in = -1.0
		_pod_pos = Vector2.INF
	_pod_t = maxf(_pod_t - delta, 0.0)


func _safe_respawn_point() -> Vector2:
	for i in 24:
		var p := _death_pos + Vector2.from_angle(randf() * TAU) * randf_range(3.0, 9.0) * PX
		if not _is_free(p, 30.0 * K):
			continue
		var clear := true
		for e in Enemies.list:
			if e.global_position.distance_to(p) < 5.0 * PX:
				clear = false
				break
		if clear:
			return p
	return _death_pos


# --- Pelican -------------------------------------------------------------------------

func _on_extract_called(_it: Interactable) -> void:
	if pelican != Pelican.NONE:
		return
	pelican = Pelican.CALLED
	pelican_delay = randf_range(PELICAN_MIN, PELICAN_MAX)
	_pel_t = 0.0
	Sfx.play_ui("terminal_beep", 0.0)
	Sfx.play("pelican_approach", zones[2].pad_pos, 2.0)
	announce("PELICAN-1 INBOUND")


func _update_pelican(delta: float) -> void:
	match pelican:
		Pelican.CALLED:
			_pel_t += delta
			if _pel_t >= pelican_delay:
				pelican = Pelican.LANDED
				Sfx.play("pelican_land", zones[2].pad_pos, 4.0)
				_music("extract")
				_music_state = "extract"
				announce("PELICAN-1 HAS LANDED - GET ON BOARD")
		Pelican.LANDED:
			Sfx.hold("pelican", "pelican", zones[2].pad_pos, true, -2.0)
			var on_pad: bool = not player.dead and player.global_position.distance_to(zones[2].pad_pos) < BOARD_RANGE_M * PX
			if on_pad:
				_board_t += delta
				if _board_t >= BOARD_TIME:
					_board()
			else:
				_board_t = maxf(_board_t - delta, 0.0)


func _board() -> void:
	pelican = Pelican.TAKEOFF
	_takeoff_t = 0.0
	for o in objectives:
		if o.type == "extract":
			o.status = "done"
		elif o.status == "active":
			o.status = "failed"
	Sfx.play("pelican_takeoff", zones[2].pad_pos, 4.0)
	player.visible = false
	_end(End.WON, "MISSION COMPLETE")


# --- Ending ---------------------------------------------------------------------------

func _end(state: End, reason: String) -> void:
	if end_state != End.NONE:
		return
	end_state = state
	end_reason = reason
	_end_t = 0.0
	Sfx.hold("upload", "", Vector2.ZERO, false)
	Sfx.play_ui("mission_complete" if state == End.WON else "mission_failed", 0.0)
	if state == End.LOST:
		_music("off")
	if _strat:
		_strat.cancel(false)
	ended.emit(state)


func _update_end(delta: float) -> void:
	_end_t += delta
	if pelican == Pelican.TAKEOFF:
		_takeoff_t += delta
	if _end_t >= 1.6 and not end_ready:
		end_ready = true
		Sfx.hold("pelican", "", Vector2.ZERO, false)
		get_tree().paused = true


# --- Music, fog -----------------------------------------------------------------------

func _music(state: String) -> void:
	if Sfx.has_method("music"):
		Sfx.call("music", state)


func _ambience() -> void:
	if Sfx.has_method("ambience"):
		Sfx.call("ambience", ["amb_wind", "amb_insects"])


## Combat music while an alerted bug is near; back to calm 8 s after none.
func _update_music(delta: float) -> void:
	if pelican == Pelican.LANDED or pelican == Pelican.TAKEOFF:
		return
	_combat_t = maxf(_combat_t - delta, 0.0)
	_music_check -= delta
	if _music_check <= 0.0:
		_music_check = MUSIC_CHECK_S
		var pp := player.global_position
		for n in Enemies.list:
			if n.has_method("is_alerted") and n.is_alerted() and n.global_position.distance_to(pp) < 35.0 * PX:
				_combat_t = 8.0
				break
	var want := "combat" if _combat_t > 0.0 else "calm"
	if want != _music_state:
		_music_state = want
		_music(want)


func _reset_fog() -> void:
	_explored = PackedByteArray()
	_explored.resize(FOG_CELLS * FOG_CELLS)
	_explored.fill(0)


func _update_fog(delta: float) -> void:
	_fog_t -= delta
	if _fog_t > 0.0:
		return
	_fog_t = 0.2
	var r := zones[current].rect
	var cell := r.size / float(FOG_CELLS)
	var pp := player.global_position
	var reveal := 22.0 * PX
	for y in FOG_CELLS:
		for x in FOG_CELLS:
			var c := r.position + Vector2((x + 0.5) * cell.x, (y + 0.5) * cell.y)
			if c.distance_to(pp) < reveal:
				_explored[y * FOG_CELLS + x] = 1


# --- World-space overlay ---------------------------------------------------------------

func _draw_overlay() -> void:
	var up := Fx.screen_up(_overlay)
	if _pod_t > 0.0 and _pod_pos != Vector2.INF:
		var k := clampf(1.0 - _pod_t / _pod_total, 0.0, 1.0)
		_overlay.draw_circle(_pod_pos, 40.0 * K * (0.4 + k * 0.6), Color(0, 0, 0, 0.55 * k))
		_overlay.draw_arc(_pod_pos, 70.0 * K * (1.2 - k * 0.5), 0.0, TAU, 28, Color(1, 0.6, 0.2, 0.7 * k), 3.0 * K)
		Fx.draw_pod(_overlay, _pod_pos, up, k, 1000.0, 18.0 * K)
	if _breach_t >= 0.0 and _breach_pos != Vector2.INF:
		var k := 1.0 - _breach_t / 1.8
		_overlay.draw_circle(_breach_pos, (60.0 * k + 10.0) * K, Color(0.35, 0.25, 0.1, 0.35))
		_overlay.draw_arc(_breach_pos, (70.0 * k + 12.0) * K, 0, TAU, 28, Color(1, 0.6, 0.2, 0.6), 3.0 * K)
		for i in 6: # cracks radiating from the breach point
			var a := TAU * i / 6.0 + 0.4
			_overlay.draw_line(_breach_pos + Vector2.from_angle(a) * 14.0, _breach_pos + Vector2.from_angle(a) * (30.0 + 60.0 * k), Color(0.1, 0.06, 0.03, 0.8), 3.0 * K)
		if _breach_t > 0.0 and int(_breach_t * 14.0) % 2 == 0:
			Fx.dust_puff(self, _breach_pos + Vector2.from_angle(randf() * TAU) * 40.0 * k, 0.8)
	if pelican == Pelican.CALLED or pelican == Pelican.LANDED or pelican == Pelican.TAKEOFF:
		var pad := zones[2].pad_pos
		var k := 1.0
		if pelican == Pelican.CALLED:
			k = clampf(_pel_t / pelican_delay, 0.0, 1.0)
			k = 1.0 - pow(1.0 - k, 2.0)
		elif pelican == Pelican.TAKEOFF:
			k = clampf(1.0 - _takeoff_t / 1.6, 0.0, 1.0)
		var c := pad + up * ((1.0 - k) * 900.0)
		_overlay.draw_circle(pad, 160.0 * K * (0.4 + k * 0.6), Color(0, 0, 0, 0.35 * k))
		_draw_pelican(c, (1.0 + (1.0 - k) * 0.5) * K)
		if k > 0.5 and int(Time.get_ticks_msec() / 90) % 2 == 0: # rotor wash
			Fx.dust_puff(self, pad + Vector2.from_angle(randf() * TAU) * randf_range(60.0, 220.0), 1.4)
	# Objective beacons: pulsing rings, tick marks and a short light column on active targets.
	var now := Time.get_ticks_msec() * 0.001
	for t in _active_targets():
		var col := UiStyle.YELLOW if not t.optional else Color(1, 1, 1, 0.6)
		var pulse := 0.5 + 0.5 * sin(now * 4.0)
		_overlay.draw_arc(t.pos, (46.0 + 6.0 * pulse) * K, 0, TAU, 28, Color(col, 0.4), 2.0 * K)
		for i in 4:
			var a := now * 1.2 + i * TAU / 4.0
			_overlay.draw_arc(t.pos, 56.0 * K, a, a + 0.5, 6, Color(col, 0.7), 3.0 * K)
		var side := up.orthogonal()
		var pts := PackedVector2Array([t.pos + side * 6.0 * K, t.pos - side * 6.0 * K, t.pos - side * 2.0 * K + up * 220.0, t.pos + side * 2.0 * K + up * 220.0])
		var cols := PackedColorArray([Color(col, 0.28 * (0.6 + pulse * 0.4)), Color(col, 0.28 * (0.6 + pulse * 0.4)), Color(col, 0.0), Color(col, 0.0)])
		_overlay.draw_polygon(pts, cols)


func _draw_pelican(c: Vector2, s: float) -> void:
	var outline := Color(0.06, 0.06, 0.06)
	var hull := Color(0.33, 0.36, 0.34)
	var body := PackedVector2Array([Vector2(0, -150), Vector2(55, -90), Vector2(60, 120), Vector2(0, 150),
		Vector2(-60, 120), Vector2(-55, -90)])
	var wings := PackedVector2Array([Vector2(-170, 10), Vector2(170, 10), Vector2(150, 60), Vector2(-150, 60)])
	var t := Transform2D(0.0, Vector2(s, s), 0.0, c)
	_overlay.draw_colored_polygon(t * wings, outline)
	_overlay.draw_colored_polygon(t * body, outline)
	_overlay.draw_colored_polygon(t * Geometry2D.offset_polygon(wings, -4.0)[0], hull.darkened(0.15))
	_overlay.draw_colored_polygon(t * Geometry2D.offset_polygon(body, -4.0)[0], hull)
	for x in [-130.0, 130.0]:
		_overlay.draw_circle(t * Vector2(x, 35), 28.0 * s, outline)
		_overlay.draw_circle(t * Vector2(x, 35), 22.0 * s, Color(0.2, 0.2, 0.2))
	_overlay.draw_rect(Rect2(t * Vector2(-30, 60), Vector2(60, 70) * s), UiStyle.YELLOW.darkened(0.2))
	_overlay.draw_circle(t * Vector2(0, -120), 12.0 * s, Color(0.4, 0.7, 1.0, 0.8))
