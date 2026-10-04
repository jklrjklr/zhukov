extends Control
## Helldivers-style HUD (info only; controls are TouchControls).
## - Top-left: operation name + objectives (count, done/optional)
## - Top-centre: compass strip with objective markers and distances
## - Top-right: MAP and PAUSE buttons, mission clock, reinforcements
## - Centre: message feed, extraction countdown, interact prompt
## - Bottom-centre: player panel (health, stims, grenades, weapon, ammo, status)
## - Overlays: map, pause menu, death/reinforcing, mission complete/failed with stats
## Works without a Mission (firing range): objectives/clock hidden, death -> restart.
## Must come after TouchControls in the tree so it sees touches first.

@export var player_path: NodePath

var _player: CharacterBody2D
var _weapon: Firearm
var _mission: Mission
var _map_open := false
var _paused := false
var _buttons := {} # name -> Rect2 of the current frame
var _strat: Stratagems


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player = get_node(player_path)
	_weapon = _player.get_node("Firearm")
	_mission = get_tree().get_first_node_in_group("mission") as Mission


func _process(_delta: float) -> void:
	if _strat == null:
		_strat = get_tree().get_first_node_in_group("stratagems") as Stratagems
	queue_redraw()


func _input(event: InputEvent) -> void:
	var t := event as InputEventScreenTouch
	if t == null:
		if (_map_open or _paused or _overlay_blocking()) and event is InputEventScreenDrag:
			get_viewport().set_input_as_handled()
		return
	if not t.pressed:
		if _map_open or _paused or _overlay_blocking():
			get_viewport().set_input_as_handled()
		return
	var hit := _button_at(t.position)
	if hit != "":
		Sfx.play_ui("ui_click", -4.0)
	var consumed := true
	if _paused:
		match hit:
			"resume":
				_set_paused(false)
			"restart":
				_restart()
			"menu":
				Game.goto_menu()
	elif _mission and _mission.is_over():
		match hit:
			"retry":
				Game.start_mission()
			"menu":
				Game.goto_menu()
	elif _map_open:
		_map_open = false
	elif _player.dead and not _mission:
		_restart()
	else:
		match hit:
			"map":
				_map_open = true
			"pause":
				_set_paused(true)
			_:
				consumed = false
	if consumed:
		get_viewport().set_input_as_handled()


func _overlay_blocking() -> bool:
	return (_mission != null and _mission.is_over()) or (_player.dead and not _mission)


func _set_paused(p: bool) -> void:
	_paused = p
	get_tree().paused = p


func _restart() -> void:
	if _mission:
		Game.start_mission()
	else:
		Game.start_range()


func _button_at(p: Vector2) -> String:
	for k in _buttons:
		if (_buttons[k] as Rect2).has_point(p):
			return k
	return ""


func _draw() -> void:
	_buttons.clear()
	var vp := get_viewport_rect().size
	_draw_hurt(vp)
	if _mission:
		_draw_objectives()
		_draw_compass(vp)
		_draw_clock(vp)
		_draw_extraction(vp)
	else:
		UiStyle.panel(self, Rect2(16, 16, 240, 40))
		UiStyle.accent(self, Rect2(16, 16, 240, 40))
		UiStyle.text(self, Vector2(30, 43), "firing range", 20, UiStyle.YELLOW)
	_draw_top_buttons(vp)
	_draw_messages(vp)
	_draw_interact_prompt(vp)
	_draw_stratagems(vp)
	_draw_player_panel(vp)
	_draw_perf(vp)
	if _player.dead:
		_draw_death(vp)
	if _map_open:
		_draw_map(vp)
	if _mission and _mission.is_over():
		_draw_end(vp)
	if _paused:
		_draw_pause(vp)


func _draw_hurt(vp: Vector2) -> void:
	if _player.hurt <= 0.0:
		return
	var a: float = _player.hurt * 0.35
	var e := 60.0
	for r in [Rect2(0, 0, vp.x, e), Rect2(0, vp.y - e, vp.x, e), Rect2(0, 0, e, vp.y), Rect2(vp.x - e, 0, e, vp.y)]:
		draw_rect(r, Color(0.8, 0, 0, a))


func _draw_objectives() -> void:
	var x := 16.0
	var y := 16.0
	var w := 400.0
	var rows := _mission.objectives.filter(func(o): return o.active)
	var h := 44.0 + rows.size() * 30.0
	UiStyle.panel(self, Rect2(x, y, w, h))
	UiStyle.accent(self, Rect2(x, y, w, h))
	UiStyle.text(self, Vector2(x + 16, y + 28), Mission.NAME, 18, UiStyle.YELLOW)
	var yy := y + 58.0
	for o in rows:
		var done: bool = o.done
		var col := UiStyle.TEXT_DIM if done else (UiStyle.TEXT_DIM.lerp(UiStyle.TEXT, 0.6) if o.optional else UiStyle.TEXT)
		var box := Rect2(x + 16, yy - 13, 14, 14)
		if done:
			draw_rect(box, UiStyle.YELLOW)
		else:
			draw_rect(box, UiStyle.YELLOW, false, 2.0)
		var label: String = ("(optional) " if o.optional else "") + o.text
		if o.total > 1:
			label += "  %d/%d" % [o.count, o.total]
		UiStyle.text(self, Vector2(x + 40, yy), label, 15, col)
		if done:
			draw_line(Vector2(x + 40, yy - 5), Vector2(x + 40 + UiStyle.font().get_string_size(label.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x, yy - 5), col, 1.5)
		yy += 30.0


## Heading strip: 140 deg wide, objective diamonds with distance.
func _draw_compass(vp: Vector2) -> void:
	var w := 560.0
	var cx := vp.x * 0.5
	var y := 14.0
	var span := 140.0
	var ppd := w / span
	UiStyle.panel(self, Rect2(cx - w / 2, y, w, 44), Color(0, 0, 0, 0.45), 8.0)
	var heading := fposmod(rad_to_deg(_player.look_angle), 360.0)
	var names := {0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SW", 270: "W", 315: "NW"}
	for b in range(0, 360, 15):
		var d := wrapf(b - heading, -180.0, 180.0)
		if absf(d) > span / 2:
			continue
		var x := cx + d * ppd
		if names.has(b):
			UiStyle.text(self, Vector2(x - 20, y + 22), names[b], 16, UiStyle.YELLOW if b == 0 else UiStyle.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 40)
		else:
			draw_line(Vector2(x, y + 8), Vector2(x, y + 16), UiStyle.TEXT_DIM, 2.0)
	draw_colored_polygon(PackedVector2Array([Vector2(cx - 6, y + 44), Vector2(cx + 6, y + 44), Vector2(cx, y + 36)]), UiStyle.YELLOW)
	# Objective markers
	# Objective markers: a diamond per target, distance only for the nearest one.
	for o in _mission.objectives:
		if o.done or not o.active or o.targets.is_empty():
			continue
		var col := UiStyle.YELLOW if not o.optional else UiStyle.TEXT_DIM
		var nearest := INF
		var nearest_x := 0.0
		for t in o.targets:
			var to: Vector2 = (t as Vector2) - _player.global_position
			var bearing := rad_to_deg(Vector2.UP.angle_to(to))
			var d := clampf(wrapf(bearing - heading, -180.0, 180.0), -span / 2, span / 2)
			var x := cx + d * ppd
			UiStyle.diamond(self, Vector2(x, y + 33), 6.0, col)
			if to.length() < nearest:
				nearest = to.length()
				nearest_x = x
		UiStyle.text(self, Vector2(nearest_x - 30, y + 62), "%dm" % roundi(nearest / Firearm.PX_PER_M), 13, col, HORIZONTAL_ALIGNMENT_CENTER, 60)


func _draw_clock(vp: Vector2) -> void:
	var r := Rect2(vp.x - 276, 72, 260, 62)
	UiStyle.panel(self, r)
	var t := maxf(_mission.time_left, 0.0)
	var low := t < 120.0
	UiStyle.text(self, r.position + Vector2(14, 24), "mission time", 13, UiStyle.TEXT_DIM)
	UiStyle.text(self, r.position + Vector2(14, 50), "%02d:%02d" % [int(t) / 60, int(t) % 60], 24, UiStyle.RED if low else UiStyle.TEXT)
	UiStyle.text(self, r.position + Vector2(140, 24), "reinforce", 13, UiStyle.TEXT_DIM)
	UiStyle.text(self, r.position + Vector2(140, 50), "x %d" % _mission.reinforcements, 24, UiStyle.YELLOW)


func _draw_top_buttons(vp: Vector2) -> void:
	var right := vp.x - (100.0 if OS.has_feature("web") else 16.0)
	_buttons["pause"] = UiStyle.button(self, Rect2(right - 70, 12, 70, 50), "II", false, 20)
	if _mission:
		_buttons["map"] = UiStyle.button(self, Rect2(right - 160, 12, 80, 50), "MAP", false, 18)


func _draw_messages(vp: Vector2) -> void:
	var y := 120.0
	if _mission == null:
		return
	for m in _mission.messages:
		var a := clampf(5.0 - m.t, 0.0, 1.0)
		UiStyle.text(self, Vector2(0, y), m.text, 18, Color(UiStyle.YELLOW, a), HORIZONTAL_ALIGNMENT_CENTER, vp.x)
		y += 26.0


func _draw_extraction(vp: Vector2) -> void:
	if _mission.phase == Mission.Phase.EXTRACTING:
		var t := maxf(_mission.extract_left, 0.0)
		var r := Rect2(vp.x * 0.5 - 150, 84, 300, 30)
		UiStyle.panel(self, r, UiStyle.PANEL_SOLID, 6.0)
		UiStyle.text(self, Vector2(r.position.x, r.position.y + 22), "extraction  %d:%02d" % [int(t) / 60, int(t) % 60], 18, UiStyle.YELLOW, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	elif _mission.phase == Mission.Phase.SHUTTLE and _mission.board_progress() > 0.0:
		var r := Rect2(vp.x * 0.5 - 150, vp.y * 0.6, 300, 14)
		UiStyle.bar(self, r, _mission.board_progress(), UiStyle.YELLOW)


## Stratagem list while entering a code: name, arrows (matched part lit), cooldown.
func _draw_stratagems(_vp: Vector2) -> void:
	if _strat == null or not _strat.entering:
		return
	var x := 150.0
	var y := 200.0
	var row := 46.0
	var r := Rect2(x, y, 400, 20 + row * _strat.equipped.size())
	UiStyle.panel(self, r, UiStyle.PANEL_SOLID)
	UiStyle.accent(self, r, UiStyle.RED if _strat.error_t > 0.0 else UiStyle.YELLOW)
	var yy := y + 18.0
	for id in _strat.equipped:
		var def: Dictionary = Stratagems.DEFS[id]
		var ok := _strat.available(id)
		var lit := ok and _strat.matches_prefix(id)
		var col: Color = def.color if ok else Color(0.5, 0.5, 0.5)
		draw_rect(Rect2(x + 14, yy, 30, 30), Color(col, 0.85))
		UiStyle.text(self, Vector2(x + 54, yy + 12), def.name, 14, UiStyle.TEXT if ok else UiStyle.TEXT_DIM)
		if ok:
			var code: Array = def.code
			for i in code.size():
				var on := lit and i < _strat.input.size()
				var c := Vector2(x + 62 + i * 22, yy + 24)
				_code_arrow(c, int(code[i]), UiStyle.YELLOW if on else (UiStyle.TEXT if lit else UiStyle.TEXT_DIM))
			var st: Dictionary = _strat.status[id]
			if st.uses > 0:
				UiStyle.text(self, Vector2(x + 300, yy + 24), "x%d" % st.uses, 13, UiStyle.TEXT_DIM)
		else:
			var w := _strat.wait_time(id)
			var what := "rearming" if (_strat.status[id] as Dictionary).uses == 0 else "cooldown"
			UiStyle.text(self, Vector2(x + 54, yy + 30), "%s %d:%02d" % [what, int(w) / 60, int(w) % 60], 13, UiStyle.TEXT_DIM)
		yy += row


func _code_arrow(c: Vector2, d: int, col: Color) -> void:
	var v: Vector2 = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT][d]
	var side := v.orthogonal()
	draw_colored_polygon(PackedVector2Array([c + v * 7.0, c - v * 5.0 + side * 6.0, c - v * 5.0 - side * 6.0]), col)


func _draw_interact_prompt(vp: Vector2) -> void:
	var it: Interactable = _player.interact_target
	if it == null or _player.dead:
		return
	var r := Rect2(vp.x * 0.5 - 170, vp.y - 160, 340, 46)
	UiStyle.panel(self, r, UiStyle.PANEL_SOLID)
	UiStyle.accent(self, r)
	UiStyle.text(self, r.position + Vector2(16, 22), "hold  " + it.label, 16, UiStyle.YELLOW)
	UiStyle.bar(self, Rect2(r.position + Vector2(16, 30), Vector2(r.size.x - 32, 8)), it.progress / it.hold_time, UiStyle.YELLOW)


## Health, stims, grenades | weapon, ammo, mags, fire mode, status.
func _draw_player_panel(vp: Vector2) -> void:
	var r := Rect2(vp.x * 0.5 - 250, vp.y - 100, 500, 86)
	UiStyle.panel(self, r)
	UiStyle.accent(self, r)
	var x := r.position.x + 18
	var y := r.position.y
	var hp_frac: float = _player.hp / _player.max_hp
	var hp_col := UiStyle.RED if hp_frac < 0.3 else (UiStyle.YELLOW if hp_frac < 0.6 else UiStyle.TEXT)
	UiStyle.text(self, Vector2(x, y + 24), "health", 13, UiStyle.TEXT_DIM)
	UiStyle.bar(self, Rect2(x, y + 32, 200, 16), hp_frac, hp_col, 10)
	if _player.stamina < 1.0:
		draw_rect(Rect2(x, y + 50, 200 * _player.stamina, 3), UiStyle.BLUE)
	if _player.is_healing():
		UiStyle.text(self, Vector2(x + 120, y + 24), "stimmed", 13, UiStyle.GREEN)
	# Stims / grenades pips
	UiStyle.text(self, Vector2(x, y + 72), "stim", 13, UiStyle.TEXT_DIM)
	for i in _player.max_stims:
		draw_rect(Rect2(x + 42 + i * 13, y + 60, 9, 14), UiStyle.GREEN if i < _player.stims else Color(1, 1, 1, 0.15))
	UiStyle.text(self, Vector2(x + 110, y + 72), "nade", 13, UiStyle.TEXT_DIM)
	for i in _player.max_grenades:
		draw_circle(Vector2(x + 158 + i * 14, y + 67), 5.0, UiStyle.YELLOW if i < _player.grenades else Color(1, 1, 1, 0.15))

	# Weapon block
	var wx := r.position.x + 250
	draw_line(Vector2(wx - 14, y + 12), Vector2(wx - 14, y + 74), Color(1, 1, 1, 0.15), 2.0)
	var w := _weapon
	UiStyle.text(self, Vector2(wx, y + 24), "%s  %s" % [w.stats.display_name, w.fire_mode_name()], 15, UiStyle.YELLOW)
	if w.has_support():
		var other: FirearmStats = w.slots[1 - w.slot].stats
		UiStyle.text(self, Vector2(wx + 150, y + 78), "swap: " + other.display_name, 12, UiStyle.GREEN)
	var total := w.rounds_loaded()
	# "+1" only when a tactical reload put a full mag behind a chambered round.
	var rounds := "%d+1" % w.stats.mag_size if total > w.stats.mag_size else "%d" % total
	var low := total <= w.stats.mag_size / 4
	UiStyle.text(self, Vector2(wx, y + 62), rounds, 34, UiStyle.RED if low else UiStyle.TEXT)
	for i in w.mags.size():
		var mx := wx + 90 + i * 12
		var h := 30.0
		var fill := h * w.mags[i] / float(w.stats.mag_size)
		draw_rect(Rect2(mx, y + 34, 8, h), Color(1, 1, 1, 0.15))
		draw_rect(Rect2(mx, y + 34 + h - fill, 8, fill), UiStyle.TEXT)
	var status := ""
	var col := UiStyle.YELLOW
	if w.jammed:
		status = "jammed - clear"
		col = UiStyle.RED
	elif w.state == Firearm.State.RELOADING:
		status = "reloading"
	elif w.state == Firearm.State.CLEARING:
		status = "clearing"
	elif w.state == Firearm.State.DRAWING:
		status = "readying"
	elif w.blocked > 0.0:
		status = "blocked"
	elif w.dry_flash > 0.0:
		status = "empty - reload" if not w.mags.is_empty() else "out of ammo"
		col = UiStyle.RED
	if status != "":
		UiStyle.text(self, Vector2(wx + 150, y + 62), status, 14, col)


func _draw_perf(vp: Vector2) -> void:
	var proc_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	UiStyle.text(self, Vector2(16, vp.y - 8), "%d fps  proc %.1f  phys %.1f" % [Engine.get_frames_per_second(), proc_ms, phys_ms], 12, UiStyle.TEXT_DIM)


func _draw_death(vp: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.5))
	UiStyle.text(self, Vector2(0, vp.y * 0.42), "you died", 52, UiStyle.RED, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
	var sub := "tap to restart"
	if _mission:
		if _mission.respawn_in >= 0.0:
			sub = "reinforcing in %d" % ceili(_mission.respawn_in)
		else:
			sub = ""
	UiStyle.text(self, Vector2(0, vp.y * 0.42 + 46), sub, 22, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_CENTER, vp.x)


func _draw_map(vp: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.75))
	var m := _mission.map
	var size := minf(vp.y - 70, vp.x - 70)
	var origin := vp * 0.5 - Vector2(size, size) * 0.5
	var s := size / (MissionMap.HALF * 2.0)
	var to_screen := func(p: Vector2) -> Vector2: return origin + (p + Vector2(MissionMap.HALF, MissionMap.HALF)) * s
	draw_rect(Rect2(origin, Vector2(size, size)), MissionMap.GROUND.darkened(0.2))
	for f in m.forest_areas:
		draw_circle(to_screen.call(f.pos), f.r * s, Color(0.12, 0.2, 0.1))
	for road in m.roads:
		var pts := PackedVector2Array()
		for p in road:
			pts.append(to_screen.call(p))
		draw_polyline(pts, MissionMap.DIRT, 3.0)
	for rk in m.rocks:
		draw_circle(to_screen.call(rk.pos), maxf((rk.r as float) * s, 1.5), Color(0.45, 0.43, 0.4))
	for w in m.walls:
		draw_rect(Rect2(to_screen.call(w.position), w.size * s), Color(0.75, 0.72, 0.65))
	draw_rect(Rect2(origin, Vector2(size, size)), UiStyle.YELLOW_DIM, false, 2.0)
	# Objectives
	for o in _mission.objectives:
		if o.done or not o.active:
			continue
		for t in o.targets:
			UiStyle.diamond(self, to_screen.call(t), 8.0, UiStyle.YELLOW if not o.optional else UiStyle.TEXT_DIM)
	var ex: Vector2 = to_screen.call(m.extraction)
	draw_arc(ex, 10.0, 0, TAU, 24, UiStyle.BLUE, 3.0)
	UiStyle.text(self, ex + Vector2(-40, 26), "extract", 13, UiStyle.BLUE, HORIZONTAL_ALIGNMENT_CENTER, 80)
	# Player arrow (points where the camera looks)
	var pp: Vector2 = to_screen.call(_player.global_position)
	var f := Vector2.UP.rotated(_player.look_angle)
	draw_colored_polygon(PackedVector2Array([pp + f * 12.0, pp + f.rotated(2.5) * 9.0, pp + f.rotated(-2.5) * 9.0]), UiStyle.GREEN)
	UiStyle.text(self, Vector2(0, origin.y + size + 26), "tap to close", 16, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, vp.x)


func _draw_pause(vp: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.65))
	var w := 360.0
	var x := vp.x * 0.5 - w * 0.5
	UiStyle.text(self, Vector2(0, vp.y * 0.28), "paused", 40, UiStyle.YELLOW, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
	_buttons["resume"] = UiStyle.button(self, Rect2(x, vp.y * 0.36, w, 64), "RESUME", true)
	_buttons["restart"] = UiStyle.button(self, Rect2(x, vp.y * 0.36 + 80, w, 64), "RESTART")
	_buttons["menu"] = UiStyle.button(self, Rect2(x, vp.y * 0.36 + 160, w, 64), "ABANDON MISSION" if _mission else "MAIN MENU")


func _draw_end(vp: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.7))
	var ok := _mission.phase == Mission.Phase.COMPLETE
	var r := Rect2(vp.x * 0.5 - 330, vp.y * 0.5 - 250, 660, 500)
	UiStyle.panel(self, r, UiStyle.PANEL_SOLID, 16.0)
	UiStyle.panel_outline(self, r, UiStyle.YELLOW if ok else UiStyle.RED, 16.0)
	UiStyle.text(self, Vector2(r.position.x, r.position.y + 62), "mission complete" if ok else "mission failed", 42,
		UiStyle.YELLOW if ok else UiStyle.RED, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	UiStyle.text(self, Vector2(r.position.x, r.position.y + 92), Mission.NAME if ok else _mission.fail_reason, 16,
		UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	var s := Game.stats
	var t := int(_mission.elapsed)
	var main_done := _mission.objectives.filter(func(o): return o.done and not o.optional).size()
	var main_total := _mission.objectives.filter(func(o): return not o.optional).size()
	var rows := [
		["mission time", "%02d:%02d" % [t / 60, t % 60]],
		["objectives", "%d / %d" % [main_done, main_total]],
		["optional", "done" if _mission.objective("hulk").done else "-"],
		["kills", str(s.kills)],
		["accuracy", "%d%%" % roundi(Game.accuracy())],
		["shots fired", str(s.shots)],
		["deaths", str(s.deaths)],
		["grenades / stims", "%d / %d" % [s.grenades, s.stims]],
	]
	var y := r.position.y + 140
	for row in rows:
		UiStyle.text(self, Vector2(r.position.x + 70, y), row[0], 18, UiStyle.TEXT_DIM)
		UiStyle.text(self, Vector2(r.position.x + 70, y), row[1], 18, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 140)
		y += 32
	var bw := 250.0
	_buttons["retry"] = UiStyle.button(self, Rect2(r.get_center().x - bw - 10, r.end.y - 84, bw, 60), "PLAY AGAIN", true)
	_buttons["menu"] = UiStyle.button(self, Rect2(r.get_center().x + 10, r.end.y - 84, bw, 60), "MAIN MENU")
