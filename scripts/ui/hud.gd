extends Control
## Helldivers-style HUD (info only; controls are TouchControls). Functional layout, meant
## to be re-skinned: every number comes from DATA INPUTS, never from game internals:
##   - Mission.hud_state() (Dictionary, see mission.gd): objectives, timer + stage,
##     reinforcements, samples, kills, banners, passage warning, minimap data, end data.
##   - the Player node (hp, stims, grenades, stamina, hurt, interact_target, dead) and
##     its Firearm (ammo, mags, fire mode, state)
##   - the Stratagems node (equipped, charges(), cap(), meter_frac(), cost(), locked,
##     fill_enabled, entering, input, error_t, gained)
## Layout: top-left objectives (+ passage warning), top-centre timer / lives / samples,
## top-right pause + minimap, centre banners, bottom stratagem bar + player panel.
## Overlays: reinforcing, pause, run-lost / mission-complete (RESTART, MENU).
## Works without a Mission (firing range): mission widgets hidden, death -> restart.
## Must come after TouchControls in the tree so it sees touches first.

@export var player_path: NodePath

const MINIMAP_SIZE := 190.0
const ORANGE := Color(1.0, 0.6, 0.1)

var _player: CharacterBody2D
var _weapon: Firearm
var _mission: Mission
var _paused := false
var _buttons := {} # name -> Rect2 of the current frame
var _strat: Stratagems
var _s := {} # mission.hud_state() of this frame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player = get_node(player_path)
	_weapon = _player.get_node("Firearm")
	_mission = get_tree().get_first_node_in_group("mission") as Mission
	_s = _mission.hud_state() if _mission else {}


func _process(_delta: float) -> void:
	if _strat == null:
		_strat = get_tree().get_first_node_in_group("stratagems") as Stratagems
	_s = _mission.hud_state() if _mission else {}
	queue_redraw()


func _input(event: InputEvent) -> void:
	var t := event as InputEventScreenTouch
	if t == null:
		if (_paused or _overlay_blocking()) and event is InputEventScreenDrag:
			get_viewport().set_input_as_handled()
		return
	if not t.pressed:
		if _paused or _overlay_blocking():
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
	elif _mission and _mission.end_ready:
		match hit:
			"retry":
				Game.start_mission()
			"menu":
				Game.goto_menu()
	elif _player.dead and not _mission:
		_restart()
	else:
		match hit:
			"pause":
				_set_paused(true)
			_:
				consumed = false
	if consumed:
		get_viewport().set_input_as_handled()


func _overlay_blocking() -> bool:
	return (_mission != null and _mission.end_ready) or (_player.dead and not _mission)


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
		_draw_passage_warning()
		_draw_timer(vp)
		_draw_minimap(vp)
		_draw_banners(vp)
		_draw_board_progress(vp)
	else:
		UiStyle.panel(self, Rect2(16, 16, 240, 40))
		UiStyle.accent(self, Rect2(16, 16, 240, 40))
		UiStyle.text(self, Vector2(30, 43), "firing range", 20, UiStyle.YELLOW)
	_draw_top_buttons(vp)
	_draw_interact_prompt(vp)
	_draw_stratagem_code()
	_draw_stratagem_bar(vp)
	_draw_player_panel(vp)
	_draw_perf(vp)
	if _player.dead:
		_draw_death(vp)
	if _mission and _mission.end_ready:
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


# --- Mission widgets ----------------------------------------------------------------

## Top-left: zone name and its objectives (main / optional, status, count or progress).
func _draw_objectives() -> void:
	var x := 16.0
	var y := 16.0
	var w := 400.0
	var rows: Array = _s.objectives
	var h := 50.0 + rows.size() * 34.0
	UiStyle.panel(self, Rect2(x, y, w, h))
	UiStyle.accent(self, Rect2(x, y, w, h))
	UiStyle.text(self, Vector2(x + 16, y + 26), _s.zone_name, 18, UiStyle.YELLOW)
	var yy := y + 56.0
	for o in rows:
		var status: String = o.status
		var done := status == "done"
		var failed := status == "failed"
		var col := UiStyle.TEXT
		if done:
			col = UiStyle.TEXT_DIM
		elif failed:
			col = UiStyle.RED
		elif o.type == "optional":
			col = UiStyle.TEXT_DIM.lerp(UiStyle.TEXT, 0.6)
		var box := Rect2(x + 16, yy - 13, 14, 14)
		if done:
			draw_rect(box, UiStyle.YELLOW)
		elif failed:
			draw_rect(box, UiStyle.RED, false, 2.0)
			draw_line(box.position, box.end, UiStyle.RED, 2.0)
			draw_line(Vector2(box.end.x, box.position.y), Vector2(box.position.x, box.end.y), UiStyle.RED, 2.0)
		else:
			draw_rect(box, UiStyle.YELLOW, false, 2.0)
		var label: String = ("(optional) " if o.type == "optional" else "") + o.text
		if o.total > 1:
			label += "  %d/%d" % [o.count, o.total]
		if failed:
			label += "  - failed"
		UiStyle.text(self, Vector2(x + 40, yy), label, 15, col)
		if done:
			var tw := UiStyle.font().get_string_size(label.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			draw_line(Vector2(x + 40, yy - 5), Vector2(x + 40 + tw, yy - 5), col, 1.5)
		if status == "active" and o.progress > 0.0 and o.total == 1:
			UiStyle.bar(self, Rect2(x + 40, yy + 5, w - 60, 6), o.progress, UiStyle.YELLOW)
		yy += 34.0


## Under the objectives while standing in a passage before its midline.
func _draw_passage_warning() -> void:
	var list: Array = _s.passage_warning
	if list.is_empty():
		return
	var rows: Array = _s.objectives
	var y := 16.0 + 50.0 + rows.size() * 34.0 + 10.0
	var r := Rect2(16, y, 400, 40.0 + list.size() * 24.0)
	UiStyle.panel(self, r, Color(0.35, 0.04, 0.02, 0.8))
	UiStyle.accent(self, r, UiStyle.RED)
	UiStyle.text(self, r.position + Vector2(16, 26), "passage seals ahead - will fail:", 15, UiStyle.RED)
	var yy := r.position.y + 50.0
	for t in list:
		UiStyle.text(self, Vector2(r.position.x + 24, yy), "- " + str(t), 15, UiStyle.TEXT)
		yy += 24.0


## Top-centre: mission timer (colour by stage), reinforcements, samples, kills.
func _draw_timer(vp: Vector2) -> void:
	var r := Rect2(vp.x * 0.5 - 170, 12, 340, 92)
	UiStyle.panel(self, r)
	var t: float = maxf(_s.time_left, 0.0)
	var stage: String = _s.stage
	var col := UiStyle.TEXT
	var label := "mission time"
	if stage == "departure":
		col = ORANGE if int(Time.get_ticks_msec() / 400) % 2 == 0 else UiStyle.YELLOW
		label = "destroyer leaving"
	elif stage == "departed":
		col = UiStyle.RED
		label = "destroyer departed"
	UiStyle.text(self, Vector2(r.position.x, r.position.y + 20), label, 13, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	UiStyle.text(self, Vector2(r.position.x, r.position.y + 58), "%d:%02d" % [int(t) / 60, int(t) % 60], 40, col, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	var y := r.position.y + 82.0
	UiStyle.text(self, Vector2(r.position.x + 16, y), "reinforce %d" % _s.reinforcements, 14,
		UiStyle.RED if _s.reinforcements <= 1 else UiStyle.YELLOW)
	UiStyle.text(self, Vector2(r.position.x, y), "samples %d" % _s.samples, 14, UiStyle.BLUE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	UiStyle.text(self, Vector2(r.position.x, y), "kills %d" % _s.kills, 14, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 16)


## Announcement banners (newest at the bottom), fading out.
func _draw_banners(vp: Vector2) -> void:
	var y := 150.0
	for b in _s.banners:
		var a := clampf(5.5 - b.t, 0.0, 1.0)
		var w := UiStyle.font().get_string_size(str(b.text).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 40.0
		UiStyle.panel(self, Rect2(vp.x * 0.5 - w * 0.5, y - 24, w, 36), Color(0, 0, 0, 0.5 * a), 8.0)
		UiStyle.text(self, Vector2(0, y), b.text, 22, Color(UiStyle.YELLOW, a), HORIZONTAL_ALIGNMENT_CENTER, vp.x)
		y += 42.0


func _draw_board_progress(vp: Vector2) -> void:
	if _s.pelican == "landed" and _s.board_progress > 0.0:
		UiStyle.bar(self, Rect2(vp.x * 0.5 - 150, vp.y * 0.6, 300, 14), _s.board_progress, UiStyle.YELLOW)
	elif _s.pelican == "landed":
		UiStyle.text(self, Vector2(0, vp.y * 0.6), "board pelican-1", 18, UiStyle.YELLOW, HORIZONTAL_ALIGNMENT_CENTER, vp.x)


## Top-right minimap of the current zone: fog, objectives, POIs, exit, bugs, player.
func _draw_minimap(vp: Vector2) -> void:
	var m: Dictionary = _s.minimap
	var rect: Rect2 = m.rect
	var size := MINIMAP_SIZE
	var origin := Vector2(vp.x - 16.0 - size, 100.0)
	var to_map := func(p: Vector2) -> Vector2: return origin + (p - rect.position) / rect.size * size
	draw_rect(Rect2(origin, Vector2(size, size)), Color(0.12, 0.11, 0.08, 0.85))
	# Fog of war: unexplored cells darkened (runs merged per row).
	var cells: int = m.cells
	var explored: PackedByteArray = m.explored
	var cs := size / cells
	for yy in cells:
		var x := 0
		while x < cells:
			if explored[yy * cells + x] == 0:
				var x0 := x
				while x < cells and explored[yy * cells + x] == 0:
					x += 1
				draw_rect(Rect2(origin + Vector2(x0 * cs, yy * cs), Vector2((x - x0) * cs, cs)), Color(0, 0, 0, 0.75))
			else:
				x += 1
	draw_rect(Rect2(origin, Vector2(size, size)), UiStyle.YELLOW_DIM, false, 2.0)
	for t in m.targets:
		UiStyle.diamond(self, to_map.call(t.pos), 6.0, UiStyle.YELLOW if not t.optional else UiStyle.TEXT)
	for p in m.pois:
		var c: Vector2 = to_map.call(p.pos)
		if p.kind == "sample":
			draw_circle(c, 3.5, UiStyle.BLUE)
		else:
			draw_rect(Rect2(c - Vector2(3, 3), Vector2(6, 6)), UiStyle.GREEN)
	var exit_pos: Vector2 = m.exit
	if exit_pos != Vector2.INF:
		var ec: Vector2 = to_map.call(exit_pos)
		draw_arc(ec, 7.0, 0, TAU, 16, UiStyle.BLUE, 2.5)
	for e in m.enemies:
		draw_circle(to_map.call(e.pos), 2.5, UiStyle.RED if e.alert else Color(1, 0.5, 0.3, 0.7))
	var pc: Vector2 = to_map.call(m.player)
	var f := Vector2.UP.rotated(m.look)
	draw_colored_polygon(PackedVector2Array([pc + f * 8.0, pc + f.rotated(2.5) * 6.0, pc + f.rotated(-2.5) * 6.0]), UiStyle.GREEN)


func _draw_top_buttons(vp: Vector2) -> void:
	var right := vp.x - (100.0 if OS.has_feature("web") else 16.0)
	_buttons["pause"] = UiStyle.button(self, Rect2(right - 70, 12, 70, 50), "II", false, 20)


# --- Stratagems ---------------------------------------------------------------------

## Bottom bar: icon colour, short name, charges (/cap), meter fill toward the next charge.
func _draw_stratagem_bar(vp: Vector2) -> void:
	if _strat == null or _strat.equipped.is_empty():
		return
	var n := _strat.equipped.size()
	var cw := 104.0
	var gap := 8.0
	var h := 64.0
	var x0 := vp.x * 0.5 - (n * cw + (n - 1) * gap) * 0.5
	var y := vp.y - 100.0 - 14.0 - h - 6.0
	for i in n:
		var id: String = _strat.equipped[i]
		var def: Dictionary = Stratagems.DEFS[id]
		var r := Rect2(x0 + i * (cw + gap), y, cw, h)
		var charges := _strat.charges(id)
		var cap := _strat.cap(id)
		var col: Color = def.color
		var usable := charges > 0 and not _strat.locked
		UiStyle.panel(self, r, Color(col, 0.28) if usable else UiStyle.PANEL_SOLID, 8.0)
		var flash: float = _strat.gained.get(id, 99.0)
		UiStyle.panel_outline(self, r, UiStyle.YELLOW if flash < 1.0 else (col if usable else Color(1, 1, 1, 0.2)), 8.0, 3.0 if flash < 1.0 else 2.0)
		draw_rect(Rect2(r.position + Vector2(8, 8), Vector2(18, 18)), col if usable else Color(0.4, 0.4, 0.4))
		UiStyle.text(self, r.position + Vector2(32, 22), def.short, 14, UiStyle.TEXT if usable else UiStyle.TEXT_DIM)
		UiStyle.text(self, r.position + Vector2(0, 30), "x%d" % charges, 24, UiStyle.YELLOW if usable else UiStyle.TEXT_DIM,
			HORIZONTAL_ALIGNMENT_RIGHT, cw - 10)
		UiStyle.text(self, r.position + Vector2(0, 44), "/%d" % cap, 11, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT, cw - 10)
		var bar := Rect2(r.position + Vector2(8, h - 14), Vector2(cw - 16, 7))
		var frac := _strat.meter_frac(id)
		UiStyle.bar(self, bar, frac, col if _strat.fill_enabled else Color(0.5, 0.5, 0.5))
		if _strat.locked:
			UiStyle.text(self, r.position + Vector2(8, 42), "locked", 12, UiStyle.RED)
		elif not _strat.fill_enabled:
			UiStyle.text(self, r.position + Vector2(8, 42), "meter off", 12, ORANGE)


## Code entry list while the stratagem menu is open: name, arrows (matched part lit), cost.
func _draw_stratagem_code() -> void:
	if _strat == null or not _strat.entering:
		return
	var x := 150.0
	var y := 200.0
	var row := 46.0
	var r := Rect2(x, y, 420, 20 + row * _strat.equipped.size())
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
		var code: Array = def.code
		for i in code.size():
			var on := lit and i < _strat.input.size()
			var c := Vector2(x + 62 + i * 22, yy + 24)
			_code_arrow(c, int(code[i]), UiStyle.YELLOW if on else (UiStyle.TEXT if lit else UiStyle.TEXT_DIM))
		UiStyle.text(self, Vector2(x, yy + 24), "x%d" % _strat.charges(id), 14, UiStyle.TEXT if ok else UiStyle.RED, HORIZONTAL_ALIGNMENT_RIGHT, 400)
		yy += row


func _code_arrow(c: Vector2, d: int, col: Color) -> void:
	var v: Vector2 = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT][d]
	var side := v.orthogonal()
	draw_colored_polygon(PackedVector2Array([c + v * 7.0, c - v * 5.0 + side * 6.0, c - v * 5.0 - side * 6.0]), col)


func _draw_interact_prompt(vp: Vector2) -> void:
	var it: Interactable = _player.interact_target
	if it == null or _player.dead:
		return
	var r := Rect2(vp.x * 0.5 - 170, vp.y - 260, 340, 46)
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
	UiStyle.text(self, Vector2(x, y + 72), "stim", 13, UiStyle.TEXT_DIM)
	for i in _player.max_stims:
		draw_rect(Rect2(x + 42 + i * 13, y + 60, 9, 14), UiStyle.GREEN if i < _player.stims else Color(1, 1, 1, 0.15))
	UiStyle.text(self, Vector2(x + 110, y + 72), "nade", 13, UiStyle.TEXT_DIM)
	for i in _player.max_grenades:
		draw_circle(Vector2(x + 158 + i * 14, y + 67), 5.0, UiStyle.YELLOW if i < _player.grenades else Color(1, 1, 1, 0.15))

	var wx := r.position.x + 250
	draw_line(Vector2(wx - 14, y + 12), Vector2(wx - 14, y + 74), Color(1, 1, 1, 0.15), 2.0)
	var w := _weapon
	UiStyle.text(self, Vector2(wx, y + 24), "%s  %s" % [w.stats.display_name, w.fire_mode_name()], 15, UiStyle.YELLOW)
	if w.has_support():
		var other: FirearmStats = w.slots[1 - w.slot].stats
		UiStyle.text(self, Vector2(wx + 150, y + 78), "swap: " + other.display_name, 12, UiStyle.GREEN)
	var total := w.rounds_loaded()
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


# --- Overlays -----------------------------------------------------------------------

func _draw_death(vp: Vector2) -> void:
	if _mission and _mission.end_ready:
		return
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.5))
	UiStyle.text(self, Vector2(0, vp.y * 0.42), "you died", 52, UiStyle.RED, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
	var sub := "tap to restart"
	if _mission:
		var rin: float = _s.respawn_in
		if rin >= 0.0:
			sub = "reinforcing in %d" % ceili(rin)
		else:
			sub = ""
	UiStyle.text(self, Vector2(0, vp.y * 0.42 + 46), sub, 22, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_CENTER, vp.x)


func _draw_pause(vp: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.65))
	var w := 360.0
	var x := vp.x * 0.5 - w * 0.5
	UiStyle.text(self, Vector2(0, vp.y * 0.28), "paused", 40, UiStyle.YELLOW, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
	_buttons["resume"] = UiStyle.button(self, Rect2(x, vp.y * 0.36, w, 64), "RESUME", true)
	_buttons["restart"] = UiStyle.button(self, Rect2(x, vp.y * 0.36 + 80, w, 64), "RESTART")
	_buttons["menu"] = UiStyle.button(self, Rect2(x, vp.y * 0.36 + 160, w, 64), "ABANDON MISSION" if _mission else "MAIN MENU")


## Run lost / mission complete: objectives done or failed, kills, samples, time.
func _draw_end(vp: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.7))
	var ok: bool = _s.end == "won"
	var all: Array = _s.all_objectives
	var shown: Array = all.filter(func(o): return o.type != "extract")
	var h := 400.0 + shown.size() * 28.0
	var r := Rect2(vp.x * 0.5 - 330, maxf(vp.y * 0.5 - h * 0.5, 8.0), 660, h)
	UiStyle.panel(self, r, UiStyle.PANEL_SOLID, 16.0)
	UiStyle.panel_outline(self, r, UiStyle.YELLOW if ok else UiStyle.RED, 16.0)
	UiStyle.text(self, Vector2(r.position.x, r.position.y + 62), "mission complete" if ok else "run lost", 42,
		UiStyle.YELLOW if ok else UiStyle.RED, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	UiStyle.text(self, Vector2(r.position.x, r.position.y + 92), _s.mission_name if ok else _s.end_reason, 16,
		UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	var y := r.position.y + 130
	for o in shown:
		var st: String = o.status
		var col := UiStyle.YELLOW if st == "done" else (UiStyle.RED if st == "failed" else UiStyle.TEXT_DIM)
		UiStyle.text(self, Vector2(r.position.x + 70, y), ("(optional) " if o.type == "optional" else "") + o.text, 16, UiStyle.TEXT)
		UiStyle.text(self, Vector2(r.position.x + 70, y), "done" if st == "done" else ("failed" if st == "failed" else "not done"),
			16, col, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 140)
		y += 28.0
	y += 14.0
	var t := int(_s.elapsed)
	var done_n := shown.filter(func(o): return o.status == "done").size()
	var rows := [
		["objectives done / failed", "%d / %d" % [done_n, shown.filter(func(o): return o.status != "done").size()]],
		["kills", str(_s.kills)],
		["samples", str(_s.samples)],
		["reinforcements left", str(_s.reinforcements)],
		["time", "%d:%02d" % [t / 60, t % 60]],
	]
	for row in rows:
		UiStyle.text(self, Vector2(r.position.x + 70, y), row[0], 18, UiStyle.TEXT_DIM)
		UiStyle.text(self, Vector2(r.position.x + 70, y), row[1], 18, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 140)
		y += 32
	var bw := 250.0
	_buttons["retry"] = UiStyle.button(self, Rect2(r.get_center().x - bw - 10, r.end.y - 84, bw, 60), "RESTART", true)
	_buttons["menu"] = UiStyle.button(self, Rect2(r.get_center().x + 10, r.end.y - 84, bw, 60), "MENU")
