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
	s.open_menu() # keyboard path (Q)
	check("Q opens the menu", s.ui == s.Ui.MENU)
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

	# Stratagem cards are the touch buttons: tap = aim mode, press + swipe out = quick throw.
	await fresh()
	p.global_position = m.zones[0].rect.get_center()
	p.rotation = 0.0
	p.look_angle = 0.0
	await wait(0.2)
	var tc: Node = _scene.get_node("HUD/TouchControls")
	tc.set_process(false)
	var real: Vector2 = tc.get_viewport_rect().size
	var n: int = s.equipped.size()
	var ci: int = s.equipped.find("eat17")
	check("loadout has the EAT-17 card", ci >= 0)
	var cr: Rect2 = load("res://scripts/ui/strat_menu.gd").card_rect(real, n, ci)
	var c0 := cr.get_center()
	tc._on_touch(_touch(true, c0, 5))
	check("press on a card does nothing yet", s.ui == s.Ui.NONE and s.typing_id == "")
	tc._on_touch(_touch(false, c0, 5))
	check("tap on a card enters aim mode for that stratagem", s.ui == s.Ui.AIM and s.aim_id == "eat17")
	tc._on_touch(_touch(true, c0, 5))
	tc._on_touch(_touch(false, c0, 5))
	check("tap on the aimed card cancels", s.ui == s.Ui.NONE and s.aim_id == "")
	var before: int = s.charges("eat17")
	var up_end := c0 + Vector2(110, -20) # swipe right-and-slightly-up, out of the card
	tc._on_touch(_touch(true, c0, 6))
	tc._on_drag(_drag(up_end, 6))
	tc._on_touch(_touch(false, up_end, 6))
	check("swipe out of a card starts a quick throw (typing, no aim mode)", s.typing_id == "eat17" and s.ui == s.Ui.NONE and s.throw_queued)
	await wait(0.7)
	check("swipe quick throw thrown after the code", s.charges("eat17") == before - 1 and s.last_called == "eat17")
	b = s._beacons[0]
	var want: Vector2 = tc.get_viewport().get_canvas_transform().affine_inverse().basis_xform(up_end - c0).normalized()
	check("swipe throw goes 12 m in the swipe direction", (b.to - b.from).normalized().dot(want) > 0.98 and (b.to - b.from).length() / PX <= 12.01, str(b.to - b.from))
	# An empty card gives strat_error + a reason on press.
	await wait(1.0)
	s.status.eat17.charges = 0
	s.error_t = 0.0
	tc._on_touch(_touch(true, c0, 7))
	check("pressing an empty card refuses (error flash, no aim mode)", s.error_t > 0.0 and s.ui == s.Ui.NONE and s.typing_id == "")
	tc._on_touch(_touch(false, c0, 7))
	check("releasing an empty card does nothing", s.ui == s.Ui.NONE and s.typing_id == "")
	# Keyboard path still works: number key -> aim mode.
	s.status.eat17.charges = 1
	check("key 1-5 enters aim mode", s.select_index(ci) and s.ui == s.Ui.AIM)
	s.cancel(false)

	# Fire vs sprint: holding FIRE always fires and cancels sprint; sprint resumes after release.
	await fresh()
	p.global_position = m.zones[0].start_pos
	p.stamina = 1.0
	await wait(0.2)
	var mag0: int = p.weapon.mag
	p.move_input = Vector2(0, -1)
	await wait(0.5)
	check("sprinting with the stick at the edge", p.sprinting)
	p.weapon.trigger = true
	await wait(0.3)
	check("holding FIRE cancels sprint and the weapon fires", not p.sprinting and p.weapon.mag < mag0, "%s %d/%d" % [p.sprinting, p.weapon.mag, mag0])
	p.weapon.trigger = false
	await wait(0.2)
	check("sprint resumes after FIRE is released", p.sprinting)
	p.move_input = Vector2.ZERO

	# --- H: performance structure (registry, turn cap, cadence, rig, perf overlay) --------------
	await fresh()
	p.global_position = m.zones[0].rect.get_center()
	await wait(0.2)
	var actors: Node = m.get_node("Actors")
	var T = load("res://scripts/terminid.gd")
	var got: Array = T.spawn_pack(actors, p.global_position + Vector2(0, -10 * PX), 4, 777, func(_q): return true,
		[T.Kind.SCAVENGER, T.Kind.WARRIOR, T.Kind.HUNTER, T.Kind.BILE_SPITTER])
	check("Enemies registry tracks every enemy in the group", root.get_tree().get_nodes_in_group("enemies").size() == Enemies.count())
	var worst := 0.0
	var over := 0
	for t in got:
		t.alert_to(p.global_position, true)
	for f in 120:
		await physics_frame
		for t in got:
			if is_instance_valid(t) and not t.is_dead():
				var cap: float = t.turn_cap() / 60.0
				worst = maxf(worst, t.last_turn / cap)
				if t.last_turn > cap * 1.02 + 1e-4:
					over += 1
	check("per-frame heading change never exceeds the turn-rate cap", over == 0, "worst %.2f of cap" % worst)
	var bug1 = got[1]
	check("bug has a cutout rig with parts", bug1._rig != null and bug1._rig.nodes.size() > 20)
	check("bug think cadence is 0.1 s near / 0.2 s far", T.THINK_NEAR == 0.1 and T.THINK_FAR == 0.2 and T.NEAR_M == 20.0)
	check("mission checks combat music every 0.5 s, minimap every 0.2 s", m.MUSIC_CHECK_S == 0.5 and m.MINIMAP_S == 0.2)
	bug1.take_hit({"damage": 9999.0, "base_damage": 9999.0, "armor_penetration": 5, "armor_damage": 0.0, "destruction_level": 0,
		"stagger": 0.0, "dir": Vector2.UP, "meters": 0.0, "aim_point": null})
	check("dead bug leaves the registry and stops physics", bug1.is_dead() and not Enemies.list.has(bug1) and not bug1.is_physics_processing())
	await wait(1.5)
	check("dead bug is baked into the decal layer (no node left, or an idle one about to be reaped)",
		not is_instance_valid(bug1) or (bug1._rig.corpse_sprite != null and not bug1.is_processing()))
	check("the corpse decal exists", (load("res://scripts/fx/fx.gd") as GDScript).call("corpse_count") >= 1)
	check("perf overlay is off by default", not root.get_node("Game").perf_overlay)
	var hud := _scene.get_node("HUD/Hud")
	check("HUD has a camera overlay layer and a redraw signature", hud._overlay != null and hud._signature() != 0)

	# --- I: scale (VISUAL_SCALE 1.6, camera 0.5) and zone layouts ------------------------------
	await fresh()
	var VS: float = root.get_node("Game").VISUAL_SCALE
	check("VISUAL_SCALE is 1.6 and the base camera zoom is 0.5", is_equal_approx(VS, 1.6) and is_equal_approx(root.get_node("Game").CAM_ZOOM, 0.5))
	check("player drawn 1.6x with matching collision", is_equal_approx(p.scale.x, VS) and p.get_node("CollisionShape2D").shape.radius * p.scale.x > 24.0)
	var cam: Camera2D = p.get_node("CameraRig/Camera2D")
	await wait(0.5)
	check("camera zoomed out 2x", absf(cam.zoom.x - 0.5) < 0.05, str(cam.zoom))
	check("player speed unchanged (3 m/s walk)", is_equal_approx(p.move_speed, 180.0))
	for zi in 3:
		var z = m.zones[zi]
		var pts: Array = [z.start_pos]
		for k in z.slots:
			pts.append_array(z.slots[k])
		for q in [z.terminal_pos, z.pad_pos]:
			if q != Vector2.INF:
				pts.append(q)
		var bad := 0
		var bad_at := ""
		for q in pts:
			var lp: Vector2 = q - z.position
			for r in z.walls:
				if r.grow(40.0).has_point(lp):
					bad += 1
					bad_at += " %s" % (lp / PX).snapped(Vector2(0.1, 0.1))
					break
		check("zone %d: spots, objectives and start are clear of the grown walls" % zi, bad == 0, "%d inside walls:%s" % [bad, bad_at])
		# Flood fill (30 px cells) for the player's grown body: entrance -> exit and every spot reachable.
		var cell := 30.0
		var half: float = z.HALF
		var gn := int(half * 2.0 / cell)
		var blocked := PackedByteArray()
		blocked.resize(gn * gn)
		for gy in gn:
			for gx in gn:
				var c := Vector2(-half + (gx + 0.5) * cell, -half + (gy + 0.5) * cell)
				var hit := false
				for r in z.walls:
					if r.grow(26.0).has_point(c):
						hit = true
						break
				if not hit:
					for rk in z.rocks:
						if c.distance_to(rk.pos) < rk.r + 26.0:
							hit = true
							break
				blocked[gy * gn + gx] = 1 if hit else 0
		var start := Vector2i(int((z.entrance_pt - z.position).x + half) / int(cell), int((z.entrance_pt - z.position).y + half - 120.0) / int(cell))
		var seen := PackedByteArray()
		seen.resize(gn * gn)
		var stack: Array[Vector2i] = [start]
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			if c.x < 0 or c.y < 0 or c.x >= gn or c.y >= gn or seen[c.y * gn + c.x] == 1 or blocked[c.y * gn + c.x] == 1:
				continue
			seen[c.y * gn + c.x] = 1
			stack.append_array([c + Vector2i(1, 0), c + Vector2i(-1, 0), c + Vector2i(0, 1), c + Vector2i(0, -1)])
		var unreachable := 0
		var targets: Array = [z.exit_pt - Vector2(0, 120)]
		for q in pts:
			targets.append(q)
		for q in targets:
			var lp: Vector2 = q - z.position
			var gc := Vector2i(clampi(int((lp.x + half) / cell), 0, gn - 1), clampi(int((lp.y + half) / cell), 0, gn - 1))
			if seen[gc.y * gn + gc.x] == 0 and blocked[gc.y * gn + gc.x] == 0:
				unreachable += 1
		check("zone %d: entrance reaches the exit and every spot with the grown body" % zi, unreachable == 0, "%d unreachable" % unreachable)

	# --- J: awareness (unaware -> suspicious -> alert), hearing caps, calls --------------------
	await fresh()
	p.global_position = m.zones[0].start_pos
	await wait(0.2)
	var T2 = load("res://scripts/terminid.gd")
	var AW_ALERT := 2
	var AW_SUSP := 1
	m.call_chance = 0.0
	var mk := func(rel_m: Vector2, kind_: int, physics := false):
		var got2: Array = T2.spawn_pack(m.get_node("Actors"), p.global_position + rel_m * PX, 1, 880 + randi() % 90, func(_q): return true, [kind_])
		var b2 = got2[0]
		b2.set_physics_process(physics)
		return b2
	var far_b = mk.call(Vector2(0, -60), T2.Kind.HUNTER)
	var mid_b = mk.call(Vector2(30, 0), T2.Kind.HUNTER)
	var enemies_before: int = Enemies.count()
	Enemies.broadcast_sound(p.global_position, 100.0, 13.0, 0)
	check("gunfire at 60 m: no change (hard cap 50 m)", far_b.suspicion == 0.0 and far_b.level == 0 and far_b.state == far_b.State.WANDER)
	check("gunfire at 30 m: suspicious, investigating, not alert", mid_b.level == AW_SUSP and mid_b.suspicion >= 0.2 and mid_b.state == mid_b.State.SEARCH, "%d %.2f" % [mid_b.level, mid_b.suspicion])
	check("gunfire at 30 m: no reinforcement call or breach", not m.is_calling() and m._breach_t < 0.0 and Enemies.count() == enemies_before)
	var near_b = mk.call(Vector2(3, 0), T2.Kind.SCAVENGER)
	Enemies.broadcast_sound(p.global_position + Vector2(0, 79 * PX), 100.0, 13.0, 1)
	var exp_far = mk.call(Vector2(0, 70), T2.Kind.HUNTER)
	Enemies.broadcast_sound(p.global_position, 100.0, 13.0, 1)
	check("explosions carry further than gunfire (70 m: suspicious)", exp_far.level == AW_SUSP, "%.2f" % exp_far.suspicion)
	var foot_b = mk.call(Vector2(0, 9), T2.Kind.SCAVENGER)
	Enemies.broadcast_sound(p.global_position, 50.0, 0.0, 2)
	check("footsteps are only heard within a few metres", foot_b.suspicion == 0.0 and near_b.suspicion > 0.0)
	for b3 in [far_b, mid_b, near_b, exp_far, foot_b]:
		b3.queue_free()
	await wait(0.1)

	# Alert needs LOS dwell in the sight cone (0.4 s at <= 10 m); it is never broadcast, suspicion is.
	var seer = mk.call(Vector2(0, -4), T2.Kind.WARRIOR)
	seer.rotation = PI # facing the player
	for i in 3:
		seer._think(true, 0.1)
	check("LOS dwell: not alert after 0.3 s at 4 m", seer.level != AW_ALERT and seer.level == AW_SUSP, "level %d susp %.2f" % [seer.level, seer.suspicion])
	for i in 2:
		seer._think(true, 0.1)
	check("LOS dwell: alert after >= 0.4 s", seer.level == AW_ALERT)
	var buddy = mk.call(Vector2(8, -6), T2.Kind.SCAVENGER)
	var stranger = mk.call(Vector2(40, -30), T2.Kind.SCAVENGER)
	seer._awareness_tick(0.1)
	check("alert does not propagate: neighbour only suspicious, no player position", buddy.level == AW_SUSP and buddy.state == buddy.State.SEARCH and not buddy.is_alerted() \
		and buddy._goal.distance_to(p.global_position) > 2.0 * PX, "%d %s" % [buddy.level, buddy.state])
	check("suspicion spreads only within ~15 m", stranger.level == 0 and stranger.suspicion == 0.0)
	var walled = mk.call(Vector2(-6, 5), T2.Kind.HUNTER)
	walled.rotation = PI
	var hit_b = mk.call(Vector2(6, 6), T2.Kind.WARRIOR)
	hit_b.rotation = 0.0 # facing away
	hit_b.take_hit({"damage": 1.0, "base_damage": 1.0, "armor_penetration": 5, "armor_damage": 0.0, "destruction_level": 0,
		"stagger": 0.0, "dir": Vector2.UP, "meters": 0.0, "aim_point": null})
	check("being hit alerts instantly", hit_b.level == AW_ALERT)
	for b4 in [seer, buddy, stranger, walled, hit_b]:
		b4.queue_free()
	await wait(0.1)
	# Suspicion decays over ~8 s without cues.
	var decay_b = mk.call(Vector2(0, -20), T2.Kind.SCAVENGER)
	decay_b.add_suspicion(1.0, decay_b.global_position)
	for i in 40:
		decay_b._awareness_tick(0.2)
	check("suspicion decays within ~8 s without cues", decay_b.level == 0 and decay_b.suspicion < 0.1, "%.2f" % decay_b.suspicion)
	decay_b.queue_free()

	# Reinforcement call: needs ~2 s; killing the caller cancels the breach.
	m.call_chance = 1.0
	m._breach_cd = 0.0
	m._call_roll_cd = 0.0
	p.max_hp = 1.0e6
	var caller = mk.call(Vector2(0, -14), T2.Kind.WARRIOR, true)
	caller.rotation = PI
	caller._become_alert(true)
	check("alert caller stops and starts a call", caller.state == caller.State.CALL and m.is_calling())
	await wait(1.0)
	check("call takes time: no breach after 1 s", caller.state == caller.State.CALL and m._breach_t < 0.0 and m._breach_cd == 0.0)
	caller.take_hit({"damage": 9999.0, "base_damage": 9999.0, "armor_penetration": 5, "armor_damage": 0.0, "destruction_level": 0,
		"stagger": 0.0, "dir": Vector2.UP, "meters": 0.0, "aim_point": null})
	await wait(3.5)
	check("killing the caller cancels the breach", not m.is_calling() and m._breach_t < 0.0 and m._breach_cd == 0.0 and m._breach_pos == Vector2.INF)
	m._call_roll_cd = 0.0
	var caller2 = mk.call(Vector2(0, -14), T2.Kind.HUNTER, true)
	caller2.rotation = PI
	caller2._become_alert(true)
	await wait(1.2)
	check("caller is still calling at 1.2 s", caller2.state == caller2.State.CALL)
	await wait(1.1)
	check("after ~2 s the call completes and the breach starts", caller2.state != caller2.State.CALL and m._breach_cd > 5.0, "cd %.1f state %d" % [m._breach_cd, caller2.state])


func _touch(pressed: bool, pos: Vector2, index: int) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.pressed = pressed
	e.position = pos
	e.index = index
	return e


func _drag(pos: Vector2, index: int) -> InputEventScreenDrag:
	var e := InputEventScreenDrag.new()
	e.position = pos
	e.index = index
	return e
