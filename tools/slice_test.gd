extends SceneTree
## Headless gameplay test of the v0.5 slice. Run:
##   gd --headless -s res://tools/slice_test.gd
## Prints PASS/FAIL per check and exits 1 on any FAIL.
## Checks: passage seal + objective failure + roofed beacon refusal, zone-clear time refill
## (+1:30, cap 10:00, departure stage back to main), meter / barrage maths, departure
## locking stratagems, death after departure = run over, reinforcement respawn, extraction
## terminal -> Pelican lands in 3-5 s -> boarding -> mission complete.

const PX := 60.0

var fails := 0
var checks := 0
var _scene: Node
var m # Mission (untyped: -s scripts compile before the autoloads exist)
var p # Player
var s # Stratagems


func _initialize() -> void:
	_run.call_deferred()


func check(name: String, ok: bool, detail := "") -> void:
	checks += 1
	if ok:
		print("PASS  ", name)
	else:
		fails += 1
		print("FAIL  ", name, "  ", detail)


func wait(sec: float) -> void:
	await create_timer(sec).timeout


## Fresh mission scene with an unkillable player and the hellpod already landed.
func fresh() -> void:
	if _scene:
		_scene.queue_free()
		_scene = null
		await process_frame
		await process_frame
	root.get_node("Game").reset_stats()
	_scene = (load("res://scenes/mission.tscn") as PackedScene).instantiate()
	root.add_child(_scene)
	current_scene = _scene
	m = _scene.get_node("Mission")
	p = _scene.get_node("Player")
	s = _scene.get_node("Stratagems")
	m._pod_t = 0.01
	var guard := 0
	while not m.play_started and guard < 600:
		await process_frame
		guard += 1
	p.max_hp = 1.0e6
	p.hp = 1.0e6


func to_passage(i: int, rel_m: float) -> void:
	var ps = m.passages[i]
	p.global_position = ps.position + Vector2(0, rel_m * PX)


func destroy_holes() -> void:
	for h in m._holes:
		if h.zone == 0 and is_instance_valid(h.node) and h.objective:
			h.node.take_hit({"damage": 999.0, "base_damage": 999.0, "armor_penetration": 5, "armor_damage": 0.0,
				"destruction_level": 100, "stagger": 0.0, "dir": Vector2.UP, "meters": 0.0, "aim_point": null})


func _run() -> void:
	# --- A: layout, passage seal, objective failure, roofed beacons ---------------------
	await fresh()
	check("three zones and two passages", m.zones.size() == 3 and m.passages.size() == 2)
	check("zones are 120 x 120 m", is_equal_approx(m.zones[0].rect.size.x, 120.0 * PX) and is_equal_approx(m.zones[1].rect.size.y, 120.0 * PX))
	check("insertion main objective has 3 holes", m.main_objective(0).total == 3 and m.main_objective(0).text == "DESTROY BUG NEST")
	check("middle main objective is upload data", m.main_objective(1).text == "UPLOAD DATA")
	check("each zone has an outpost, 2 POIs", m._holes.filter(func(h): return h.zone == 2).size() == 2 and m._pois.size() == 6)
	check("starts at 8:00 in the main stage", m.hud_state().stage == "main" and m.time_left > 478.0 and m.time_left <= 480.0)
	check("5 reinforcements", m.reinforcements == 5)
	check("guards spawned unaware", get_nodes_in_group("enemies").size() > 5 and not get_nodes_in_group("enemies").any(func(e): return e.is_alerted() and not e.is_in_group("chargers")))
	var hs: Dictionary = m.hud_state()
	check("hud_state has the fields the HUD reads", hs.has("minimap") and hs.has("objectives") and hs.has("banners") and hs.has("time_left") and hs.has("end"))

	to_passage(0, 5.0)
	await wait(0.2)
	check("passage warns about uncleared objectives before the midline", m.hud_state().passage_warning.size() >= 1 and not m.passages[0].is_sealed)
	check("passage is roofed", m.is_roofed(p.global_position))
	var eagle0: int = s.charges("eagle_airstrike")
	check("roofed passage: Eagle is not pickable (tooltip says why)", s.pick_error("eagle_airstrike").contains("NO SKY"))
	s.select_quick("eagle_airstrike")
	await wait(0.6)
	check("eagle beacon refused in the roofed passage (nothing spent)", s.charges("eagle_airstrike") == eagle0 and s.last_called == "")
	var banner_text := ""
	for b in m.banners:
		banner_text += b.text
	check("refusal is announced", banner_text.contains("NO SKY ACCESS"))

	var nest = m.main_objective(0)
	to_passage(0, -1.0)
	await wait(0.2)
	check("crossing the midline seals the passage", m.passages[0].is_sealed)
	check("seal has collision", m.passages[0].has_node("Seal"))
	var q := PhysicsPointQueryParameters2D.new()
	q.position = m.passages[0].seal_rect.get_center()
	check("seal blocks physics", not m.get_world_2d().direct_space_state.intersect_point(q, 1).is_empty())
	check("uncleared main objective failed", nest.status == "failed")
	check("zone advanced", m.current == 1)
	check("old zone enemies removed", get_nodes_in_group("enemies").all(func(e): return e.global_position.y < m.passages[0].seal_rect.position.y))
	check("next zone enemies start unaware", get_nodes_in_group("enemies").size() > 3 and not get_nodes_in_group("enemies").any(func(e): return e.is_alerted()))
	var up = m.main_objective(1)
	to_passage(1, -1.0)
	await wait(0.2)
	check("second passage seals and fails the upload", m.passages[1].is_sealed and up.status == "failed" and m.current == 2)

	# --- B: zone clear refill, departure stage back to main, cap --------------------------
	await fresh()
	m.time_left = 300.0
	destroy_holes()
	await wait(0.1)
	check("zone clear completes the nest objective", m.main_objective(0).status == "done")
	check("zone clear adds 1:30", absf(m.time_left - 390.0) < 1.0, str(m.time_left))
	to_passage(0, -1.0)
	await wait(0.2)
	check("cleared objective is not failed on leaving", m.main_objective(0).status == "done")
	m.time_left = 100.0
	await wait(0.2)
	check("departure stage at 2:00", m.hud_state().stage == "departure")
	check("departure stops meter fill", not s.fill_enabled and not s.locked)
	var eat_meter: float = s.status.eat17.meter
	await wait(0.3)
	check("meter does not fill in the departure stage", is_equal_approx(s.status.eat17.meter, eat_meter))
	m.complete_objective(m.main_objective(1))
	check("zone clear in departure adds time and returns to main", m.hud_state().stage == "main" and m.time_left > 188.0 and s.fill_enabled)

	await fresh()
	m.time_left = 580.0
	destroy_holes()
	check("refill is capped at 10:00", m.time_left <= 600.0 and m.time_left > 599.0, str(m.time_left))

	# --- C: meter system and barrage ----------------------------------------------------
	var eat_ch: int = s.charges("eat17")
	check("start with 1 EAT-17, 2 Eagle uses, 1 barrage", eat_ch == 1 and s.charges("eagle_airstrike") == 2 and s.charges("orbital_120") == 1)
	check("cost = HD2 cooldown x 10 (EAT-17 700)", is_equal_approx(s.cost("eat17"), 700.0))
	s.status.eat17.meter = 0.0
	s.add_points(699.0)
	check("meter just short of a charge", s.charges("eat17") == 1 and s.meter_frac("eat17") > 0.9)
	s.add_points(2.0)
	check("full meter gives +1 charge (cap 2)", s.charges("eat17") == 2)
	s.add_points(5000.0)
	check("charges stop at the cap", s.charges("eat17") == 2)
	check("resupply holds one box and meter does not exceed it", s.charges("resupply") == 1)
	s.status.resupply.charges = 0
	s.add_points(1700.0)
	check("resupply refills by meter once", s.charges("resupply") == 1)
	s.status.resupply.charges = 0
	s.add_points(1700.0)
	check("but not twice in the same zone", s.charges("resupply") == 0)
	s.new_zone()
	s.add_points(1700.0)
	check("a new zone allows it again", s.charges("resupply") == 1)
	s.status.eagle_airstrike.charges = 0
	s.add_points(1499.0)
	check("empty Eagle needs 1500 rearm points", s.charges("eagle_airstrike") == 0)
	s.add_points(2.0)
	check("rearm meter restores both uses", s.charges("eagle_airstrike") == 2)
	var inside := 0
	var within_sigma := 0
	var n := 3000
	for i in n:
		var v: Vector2 = s._barrage_point(Vector2.ZERO)
		if v.length() <= s.BARRAGE_R_M * PX + 0.01:
			inside += 1
		if v.length() <= 0.45 * s.BARRAGE_R_M * PX:
			within_sigma += 1
	check("barrage shells never land outside R = 27 m", inside == n)
	check("barrage is centre-weighted (sigma 0.45 R)", float(within_sigma) / n > 0.33, str(float(within_sigma) / n))
	var kills_before: float = s.status.eat17.meter
	s.status.eat17.charges = 1
	m.on_kill(load("res://scripts/terminid.gd").make(1))
	check("kills add meter points", s.status.eat17.meter > kills_before)

	# --- D: departure locks stratagems, death after departure ends the run ------------------
	await fresh()
	m.time_left = 0.4
	await wait(1.0)
	check("departed at 0:00", m.hud_state().stage == "departed" and m.time_left == 0.0)
	check("all stratagems lock", s.locked)
	s.open_menu()
	check("menu refuses to open when locked", not s.ui_open())
	check("none available", not s.available("eat17") and not s.available("eagle_airstrike"))
	var meter_before: float = s.status.eat17.meter
	s.add_points(500.0)
	check("no meter fill after departure", is_equal_approx(s.status.eat17.meter, meter_before))
	check("not over yet while alive", m.hud_state().end == "" and m.reinforcements == 5)
	p.take_damage(9.9e9, p.global_position + Vector2.RIGHT)
	await wait(0.5)
	check("death after departure ends the run despite 5 reinforcements", m.hud_state().end == "lost" and m.reinforcements == 5, m.end_reason)

	# --- E: reinforcements before departure ---------------------------------------------
	await fresh()
	p.take_damage(9.9e9, p.global_position + Vector2.RIGHT)
	await wait(0.4)
	check("death starts a 3 s hellpod countdown", p.dead and m.respawn_in > 2.0 and m.respawn_in <= 3.0, str(m.respawn_in))
	await wait(3.2)
	check("hellpod brings the Helldiver back", not p.dead and m.reinforcements == 4 and m.hud_state().end == "")
	m.reinforcements = 0
	p.hp = 1.0e6
	p.take_damage(9.9e9, p.global_position + Vector2.RIGHT)
	await wait(0.4)
	check("dead with 0 reinforcements = run lost", m.hud_state().end == "lost")

	# --- F: extraction ------------------------------------------------------------------
	await fresh()
	var z2 = m.zones[2]
	p.global_position = z2.terminal_pos + Vector2(0, 40)
	_scene.get_node("HUD/TouchControls").set_process(false) # it would reset p.interacting every frame
	p.interacting = true
	var t0 := Time.get_ticks_msec()
	var guard := 0
	while m.hud_state().pelican == "none" and guard < 400:
		await process_frame
		guard += 1
	check("extraction terminal calls Pelican-1", m.hud_state().pelican == "called")
	p.interacting = false
	var called := Time.get_ticks_msec()
	guard = 0
	while m.hud_state().pelican == "called" and guard < 800:
		await process_frame
		guard += 1
	var land_s := (Time.get_ticks_msec() - called) / 1000.0
	check("Pelican lands 3-5 s after the call", m.hud_state().pelican == "landed" and land_s >= 2.8 and land_s <= 5.3, str(land_s))
	check("mission not complete until boarding", m.hud_state().end == "")
	p.global_position = z2.pad_pos + Vector2(40, 0)
	await wait(1.8)
	check("boarding completes the mission", m.hud_state().end == "won")
	await wait(1.8)
	var es: Dictionary = m.hud_state()
	check("end screen data: objectives failed, kills, samples, time", es.end == "won" and es.end_ready and es.has("kills") and es.has("samples") and es.elapsed > 0.0)
	check("uncleared objectives count as failed", m.objectives.filter(func(o): return o.type == "main" and o.zone < 2 and o.status == "failed").size() == 2)
	paused = false

	# --- G: soak: patrols, breaches, upload attack waves, hole spawns run without errors ----
	await fresh()
	m._patrol_t = 0.0
	for i in 40:
		m.on_bug_alert(null)
		m._breach_cd = 0.0
		await wait(0.1)
	check("patrols / breaches spawn bugs", get_nodes_in_group("enemies").size() > 10)
	var hole = m._holes[0].node
	p.global_position = hole.global_position + Vector2(0, 200)
	m._holes[0].t = 0.0
	var n0: int = get_nodes_in_group("enemies").size()
	await wait(0.6)
	check("bug holes spawn small bugs near the player", get_nodes_in_group("enemies").size() > n0)
	m.current = 1
	p.global_position = m.zones[1].terminal_pos + Vector2(0, 300)
	m._terminal.progress = 4.0
	m._upload_t = 0.0
	n0 = get_nodes_in_group("enemies").size()
	await wait(0.9)
	check("upload brings attack waves", get_nodes_in_group("enemies").size() > n0 and m.main_objective(1).progress > 0.0)

	await _stratagem_input_tests()

	print("")
	print("%d checks, %d failed" % [checks, fails])
	quit(1 if fails > 0 else 0)


## Stratagem input: auto-typed codes (0.1 s per arrow), quick throw, menu + aim mode, interruptions.
func _stratagem_input_tests() -> void:
	await fresh()
	var open: Vector2 = m.zones[0].rect.get_center()
	p.global_position = open
	p.rotation = 0.0
	p.look_angle = 0.0
	await wait(0.2)
	check("code time is 0.1 s per arrow", is_equal_approx(s.code_time("eat17"), 0.5) and is_equal_approx(s.code_time("orbital_120"), 0.6) and is_equal_approx(s.code_time("orbital_precision"), 0.3))

	# Quick throw: typed automatically, thrown after length x 0.1 s along the aim direction.
	var eat: int = s.charges("eat17")
	check("quick throw selects an available stratagem", s.select_quick("eat17"))
	await wait(0.25)
	check("typing in progress: helldiver in typing pose, not thrown yet", p.typing and s.is_typing() and s.charges("eat17") == eat and s.last_called == "")
	await wait(0.5)
	check("EAT-17 thrown right after its 5-arrow code (0.5 s)", s.charges("eat17") == eat - 1 and s.last_called == "eat17" and not p.typing)
	var b: Dictionary = s._beacons[0]
	var thrown_m: float = (b.to - b.from).length() / PX
	check("quick throw goes ~12 m forward (or shorter against a wall)", thrown_m <= 12.01 and (b.to - b.from).normalized().dot(Vector2.UP) > 0.99, str(thrown_m))
	check("quick throw closed the selection UI", not s.ui_open())

	# Menu + aim mode: throw waits for the code, lands at the aimed point clamped to 20 m.
	await fresh()
	p.global_position = m.zones[0].rect.get_center()
	p.rotation = 0.0
	p.look_angle = 0.0
	await wait(0.2)
	s.open_menu()
	check("tap opens the menu", s.ui == s.Ui.MENU)
	check("menu entry enters aim mode", s.select_aim("eagle_airstrike") and s.ui == s.Ui.AIM)
	s.aim_move(Vector2(0, -50.0 * PX))
	check("aim point is clamped to the max throw range (20 m)", is_equal_approx(s.aim_offset.length(), 20.0 * PX), str(s.aim_offset.length()))
	var ea: int = s.charges("eagle_airstrike")
	await wait(0.1)
	s.aim_throw() # asked before the 4-arrow code (0.4 s) is done
	await wait(0.1)
	check("throw waits until typing has finished", s.charges("eagle_airstrike") == ea and s.ui == s.Ui.AIM)
	await wait(0.45)
	check("then throws at the aim point", s.charges("eagle_airstrike") == ea - 1 and s.last_called == "eagle_airstrike" and not s.ui_open())
	b = s._beacons[0]
	var d: Vector2 = b.to - b.from
	check("Eagle: line is perpendicular to the throw direction", absf(d.normalized().dot(b.dir)) > 0.99 and d.length() / PX <= 20.01, str(d.length() / PX))

	# Aim mode, aim moved sideways, typing again after an interruption.
	await fresh()
	p.global_position = m.zones[0].rect.get_center()
	await wait(0.2)
	s.select_aim("eat17")
	await wait(0.2)
	p.dive()
	await wait(0.1)
	check("diving interrupts typing (it must restart)", s.typing_t < 0.15 and s.ui == s.Ui.AIM and not p.typing)
	s.aim_throw()
	await wait(0.8)
	check("no throw while diving / prone", s.last_called == "")
	await wait(1.0)
	check("typing restarts after the dive and the queued throw happens", s.last_called == "eat17")

	# Quick throw dropped by a dive; also by a stagger.
	await fresh()
	p.global_position = m.zones[0].rect.get_center()
	await wait(0.2)
	var op: int = s.charges("orbital_120")
	s.select_quick("orbital_120")
	await wait(0.2)
	p.dive()
	await wait(0.2)
	check("quick throw is cancelled by a dive", s.typing_id == "" and s.charges("orbital_120") == op and s.last_called == "")
	await wait(1.2)
	s.select_quick("resupply")
	await wait(0.1)
	p.take_damage(30.0, p.global_position + Vector2(40, 0))
	await wait(0.1)
	check("stagger / knock-down interrupts typing", s.typing_id == "" and s.last_called == "")

	# Walking is allowed while typing (no sprint).
	await wait(0.6)
	s.select_quick("sentry_mg")
	p.move_input = Vector2(0, -1)
	await wait(0.15)
	check("typing does not stop movement but blocks sprinting", p.typing and not p.sprinting and p.velocity.length() > 20.0, "%s %s %s id=%s st=%s" % [p.typing, p.sprinting, p.velocity.length(), s.typing_id, p.stagger_t])
	p.move_input = Vector2.ZERO
	await wait(0.6)

	# Locked / unavailable stratagems cannot be picked.
	await fresh()
	p.global_position = m.zones[0].rect.get_center()
	await wait(0.2)
	s.status.eat17.charges = 0
	check("no charges: not pickable, reason names the meter", s.pick_error("eat17").begins_with("NO CHARGES"))
	check("selecting it is refused", not s.select_quick("eat17") and not s.select_aim("eat17") and s.typing_id == "" and s.error_t > 0.0)
	s.locked = true
	check("departed: not pickable, reason says offline", s.pick_error("resupply").contains("OFFLINE") and not s.select_quick("resupply"))
	s.locked = false
