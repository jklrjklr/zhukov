extends Control
## Helldivers-style HUD (info only; controls are TouchControls). Every number comes from
## DATA INPUTS, never from game internals:
##   - Mission.hud_state() (Dictionary, see mission.gd): objectives, timer + stage,
##     reinforcements, samples, kills, kill feed, banners, passage warning, minimap data, end data.
##   - the Player node (hp, stims, grenades, stamina, hurt, hit_dirs, interact_target, dead) and
##     its Firearm (ammo, mags, fire mode, state)
##   - the Stratagems node (equipped, charges(), cap(), meter_frac(), cost(), locked,
##     fill_enabled, error_t, gained)
## Layout (virtual 1280 x 720 minimum, uniformly scaled up on bigger viewports):
##   top-left objectives (status icons, counts, distance arrows)   top-centre timer + lives
##   top-right pause + minimap, kill feed to the left of it         left vitals (health, stamina,
##   stims, grenades)   bottom-centre stratagem cards + weapon / ammo panel   centre: radio
##   banners, passage warning, objective markers around / on the world.
## The bottom-centre block lives between the move hint (left) and the STIM / RELOAD buttons
## (right) of TouchControls so it never covers a control; the minimap ends above the SWAP button.
## Works without a Mission (firing range): mission widgets hidden, death -> restart.
## Must come after TouchControls in the tree so it sees touches first.

@export var player_path: NodePath

const MINIMAP_SIZE := 160.0
const ORANGE := Color(1.0, 0.6, 0.1)
const WARN := Color(1.0, 0.72, 0.1)
const CHAT_DARK := Color(0.03, 0.04, 0.03, 0.8)

static var _vignette: ImageTexture

var _player: CharacterBody2D
var _weapon: Firearm
var _mission: Mission
var _paused := false
var _buttons := {} # name -> Rect2 of the current frame (real viewport pixels)
var _strat: Stratagems
var _s := {} # mission.hud_state() of this frame
var _u := 1.0 # uniform UI scale
var _vp := Vector2(1280, 720) # viewport size in UI units
var _xf := Transform2D.IDENTITY # canvas (camera) transform
var _t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player = get_node(player_path)
	_weapon = _player.get_node("Firearm")
	_mission = get_tree().get_first_node_in_group("mission") as Mission
	_s = _mission.hud_state() if _mission else {}


func _process(delta: float) -> void:
	_t += delta
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
			"shake":
				Game.set_shake(not Game.shake_enabled)
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


## Register a hit rect (UI units) in real pixels.
func _btn(name: String, r: Rect2) -> Rect2:
	_buttons[name] = Rect2(r.position * _u, r.size * _u)
	return r


func _draw() -> void:
	_buttons.clear()
	var real := get_viewport_rect().size
	_u = clampf(minf(real.x / 1280.0, real.y / 720.0), 1.0, 1.6)
	_vp = real / _u
	_xf = get_viewport().get_canvas_transform()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(_u, _u))
	var vp := _vp
	_draw_screen_fx(vp)
	if _mission:
		_draw_markers(vp)
		_draw_objectives()
		_draw_timer(vp)
		_draw_minimap(vp)
		_draw_kill_feed(vp)
		_draw_passage_warning(vp)
		_draw_banners(vp)
		_draw_board_progress(vp)
	else:
		UiStyle.panel(self, Rect2(16, 16, 240, 40))
		UiStyle.accent(self, Rect2(16, 16, 240, 40))
		UiStyle.text(self, Vector2(30, 43), "firing range", 20, UiStyle.YELLOW)
	_draw_top_buttons(vp)
	_draw_vitals()
	_draw_interact_prompt(vp)
	_draw_stratagem_bar(vp)
	_draw_weapon_panel(vp)
	_draw_perf(vp)
	if _player.dead:
		_draw_death(vp)
	if _mission and _mission.end_ready:
		_draw_end(vp)
	if _paused:
		_draw_pause(vp)


# --- Screen effects: vignette, damage direction -------------------------------------

static func _vignette_tex() -> ImageTexture:
	if _vignette == null:
		var n := 64
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var d := Vector2((x + 0.5) / n - 0.5, (y + 0.5) / n - 0.5).length() * 2.0
				img.set_pixel(x, y, Color(1, 1, 1, smoothstep(0.55, 1.25, d)))
		_vignette = ImageTexture.create_from_image(img)
	return _vignette


func _draw_screen_fx(vp: Vector2) -> void:
	var full := Rect2(Vector2.ZERO, vp)
	var hp_frac: float = _player.hp / _player.max_hp
	var a := 0.0
	if _player.hurt > 0.0:
		a = maxf(a, _player.hurt * 0.55)
	if hp_frac < 0.35 and not _player.dead:
		var pulse := 0.5 + 0.5 * sin(_t * (3.0 + (0.35 - hp_frac) * 12.0))
		a = maxf(a, (0.35 + 0.35 * pulse) * (1.0 - hp_frac / 0.35 * 0.5))
	if a > 0.0:
		draw_texture_rect(_vignette_tex(), full, false, Color(0.85, 0.02, 0.02, clampf(a, 0.0, 0.9)))
	# Red arcs at the screen edge pointing to where damage came from.
	var center := vp * 0.5
	for h in _player.hit_dirs:
		var from: Vector2 = h.from
		var k := 1.0 - clampf((h.t as float) / 1.6, 0.0, 1.0)
		var to: Vector2 = _xf.basis_xform(from - _player.global_position)
		if to.length() < 1.0:
			continue
		var ang := to.angle()
		var rx := vp.x * 0.5 - 40.0
		var ry := vp.y * 0.5 - 40.0
		var pts := PackedVector2Array()
		var steps := 10
		for i in steps + 1:
			var aa := ang - 0.3 + 0.6 * i / steps
			pts.append(center + Vector2(cos(aa) * rx, sin(aa) * ry))
		draw_polyline(pts, Color(0.9, 0.05, 0.03, 0.35 * k), 22.0)
		draw_polyline(pts, Color(1.0, 0.2, 0.15, 0.9 * k), 8.0)
		var tip := center + Vector2(cos(ang) * (rx + 22.0), sin(ang) * (ry + 22.0))
		UiIcons.arrow(self, center + Vector2(cos(ang) * (rx - 26.0), sin(ang) * (ry - 26.0)), Vector2.from_angle(ang), 12.0, Color(1.0, 0.2, 0.15, k))


# --- Objectives ---------------------------------------------------------------------

func _nav_targets() -> Array:
	var out: Array = []
	var m: Dictionary = _s.minimap
	for t in m.targets:
		out.append({"pos": t.pos, "id": t.id, "optional": t.optional, "label": ""})
	if _s.zone_index < 2 and m.main_done:
		out.append({"pos": m.exit, "id": "exit", "optional": false, "label": "EXIT"})
	elif _s.zone_index == 2 and (_s.pelican == "called" or _s.pelican == "landed"):
		var ex: Vector2 = m.exit
		if ex != Vector2.INF:
			out.append({"pos": ex, "id": "pelican", "optional": false, "label": "PELICAN"})
	return out


func _dist_m(p: Vector2) -> int:
	return roundi(_player.global_position.distance_to(p) / Firearm.PX_PER_M)


func _nearest_target(id: String) -> Variant:
	var best: Variant = null
	var bd := INF
	for t in _nav_targets():
		if t.id == id:
			var d: float = _player.global_position.distance_to(t.pos)
			if d < bd:
				bd = d
				best = t
	return best


## Top-left: zone name and its objectives (status icon, text, count, bar, distance arrow).
func _draw_objectives() -> void:
	var x := 16.0
	var y := 12.0
	var w := 350.0
	var rows: Array = _s.objectives
	var h := 40.0 + rows.size() * 42.0
	UiStyle.panel(self, Rect2(x, y, w, h))
	UiStyle.accent(self, Rect2(x, y, w, h))
	UiStyle.text(self, Vector2(x + 16, y + 26), _s.zone_name, 18, UiStyle.YELLOW)
	UiStyle.text(self, Vector2(x, y + 26), "zone %d/3" % (int(_s.zone_index) + 1), 14, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT, w - 14)
	var yy := y + 52.0
	for o in rows:
		var status: String = o.status
		var done := status == "done"
		var failed := status == "failed"
		var optional: bool = o.type == "optional"
		var col := UiStyle.TEXT
		if done:
			col = UiStyle.TEXT_DIM
		elif failed:
			col = UiStyle.RED
		elif optional:
			col = Color(0.8, 0.85, 0.95)
		var ic := Vector2(x + 28, yy - 5)
		if done:
			draw_circle(ic, 9.0, UiStyle.YELLOW)
			UiIcons.check(self, ic, 7.0, Color(0.05, 0.05, 0.05))
		elif failed:
			draw_circle(ic, 9.0, Color(0.35, 0.05, 0.04))
			UiIcons.cross(self, ic, 6.5, UiStyle.RED)
		elif optional:
			UiIcons.star(self, ic, 9.0, Color(0.75, 0.85, 1.0))
		else:
			draw_arc(ic, 8.5, 0.0, TAU, 18, UiStyle.YELLOW, 2.5)
			draw_circle(ic, 3.0 + 1.0 * sin(_t * 5.0), UiStyle.YELLOW)
		var label: String = o.text
		if optional:
			label = "bonus: " + label
		UiStyle.text(self, Vector2(x + 48, yy), label, 16, col)
		if done:
			var tw := UiStyle.font().get_string_size(label.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			draw_line(Vector2(x + 48, yy - 5), Vector2(x + 48 + tw, yy - 5), col, 1.5)
		var right := x + w - 14
		if status == "active":
			var t = _nearest_target(o.id)
			if t != null:
				var d := _dist_m(t.pos)
				var to: Vector2 = _xf.basis_xform(t.pos - _player.global_position)
				var s := "%d m" % d
				var sw := UiStyle.font().get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
				UiStyle.text(self, Vector2(right - sw, yy), s, 14, UiStyle.YELLOW if not optional else UiStyle.TEXT)
				UiIcons.arrow(self, Vector2(right - sw - 14, yy - 5), to.normalized() if to.length() > 1.0 else Vector2.UP, 7.0, UiStyle.YELLOW)
		var bar := Rect2(x + 48, yy + 6, w - 70, 6)
		if o.total > 1:
			# One segment per hole / step.
			draw_rect(bar, Color(0, 0, 0, 0.6))
			var seg: float = bar.size.x / float(o.total)
			for i in int(o.total):
				var sr := Rect2(bar.position.x + i * seg + 1.0, bar.position.y, seg - 2.0, bar.size.y)
				draw_rect(sr, UiStyle.YELLOW if i < int(o.count) else Color(1, 1, 1, 0.14))
			UiStyle.text(self, Vector2(x, yy), "%d/%d" % [o.count, o.total], 15, col, HORIZONTAL_ALIGNMENT_RIGHT, w - 14 - (60 if status == "active" else 0))
		elif status == "active" and o.progress > 0.0:
			UiStyle.bar(self, bar, o.progress, UiStyle.YELLOW)
			UiStyle.text(self, Vector2(x, yy), "%d%%" % int(o.progress * 100.0), 14, UiStyle.YELLOW, HORIZONTAL_ALIGNMENT_RIGHT, w - 14 - 60)
		if failed:
			UiStyle.text(self, Vector2(x + 48, yy + 15), "failed", 12, UiStyle.RED)
		yy += 42.0


## Under the timer while standing in a passage before its midline.
func _draw_passage_warning(vp: Vector2) -> void:
	var list: Array = _s.passage_warning
	if list.is_empty():
		return
	var w := 420.0
	var pulse := 0.5 + 0.5 * sin(_t * 8.0)
	var r := Rect2(vp.x * 0.5 - w * 0.5, 124, w, 44.0 + list.size() * 24.0)
	UiStyle.panel(self, r, Color(0.35, 0.04, 0.02, 0.85))
	UiStyle.panel_outline(self, r, Color(UiStyle.RED, 0.5 + 0.5 * pulse), 10.0, 3.0)
	UiIcons.exit_marker(self, r.position + Vector2(26, 26), 10.0, UiStyle.RED)
	UiStyle.text(self, r.position + Vector2(48, 28), "passage seals ahead - will fail:", 16, UiStyle.RED)
	var yy := r.position.y + 54.0
	for t in list:
		UiIcons.cross(self, Vector2(r.position.x + 34, yy - 5), 6.0, UiStyle.RED)
		UiStyle.text(self, Vector2(r.position.x + 52, yy), str(t), 15, UiStyle.TEXT)
		yy += 24.0


## Top-centre: mission timer (colour by stage), progress bar with the departure mark,
## reinforcements, samples, kills.
func _draw_timer(vp: Vector2) -> void:
	var w := 350.0
	var r := Rect2(vp.x * 0.5 - w * 0.5, 10, w, 104)
	var t: float = maxf(_s.time_left, 0.0)
	var stage: String = _s.stage
	var col := UiStyle.TEXT
	var edge := Color(UiStyle.YELLOW, 0.5)
	var label := "mission time"
	var pulse := 0.5 + 0.5 * sin(_t * 9.0)
	var alarm := false
	# Pulse around the 5:00 and 1:00 warnings and the final 10 s.
	for wt in [300.0, 60.0]:
		if t <= wt and t > wt - 7.0:
			alarm = true
	if t <= 10.0 and stage != "departed":
		alarm = true
	if stage == "main" and t <= 60.0:
		col = WARN
	if stage == "departure":
		col = ORANGE if pulse > 0.5 else UiStyle.YELLOW
		label = "destroyer leaving"
		edge = Color(ORANGE, 0.9)
	elif stage == "departed":
		col = UiStyle.RED
		label = "destroyer departed"
		edge = Color(UiStyle.RED, 0.5 + 0.5 * pulse)
	if alarm:
		edge = Color(WARN, 0.4 + 0.6 * pulse)
		col = col.lerp(Color.WHITE, 0.3 * pulse)
	UiStyle.panel(self, r, Color(0, 0, 0, 0.62) if not alarm else Color(0.2, 0.1, 0.0, 0.7))
	UiStyle.panel_outline(self, r, edge, 10.0, 2.5 if alarm or stage != "main" else 1.5)
	UiStyle.text(self, Vector2(r.position.x, r.position.y + 20), label, 14, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	var big := 42 + (int(pulse * 3.0) if alarm else 0)
	UiStyle.text(self, Vector2(r.position.x, r.position.y + 58), "%d:%02d" % [int(t) / 60, int(t) % 60], big, col, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	if _s.stage == "departed":
		UiStyle.text(self, Vector2(r.position.x, r.position.y + 58), "stratagems offline", 12, UiStyle.RED, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 14)
	# Time bar to the 10:00 cap, with the 2:00 departure mark.
	var bar := Rect2(r.position.x + 16, r.position.y + 68, r.size.x - 32, 6)
	draw_rect(bar, Color(0, 0, 0, 0.6))
	var f := clampf(t / Mission.MAX_TIME, 0.0, 1.0)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), col if stage != "main" else Color(UiStyle.YELLOW, 0.9))
	var mx := bar.position.x + bar.size.x * (Mission.DEPARTURE_AT / Mission.MAX_TIME)
	draw_line(Vector2(mx, bar.position.y - 3), Vector2(mx, bar.end.y + 3), UiStyle.RED, 2.0)
	# Reinforcements (helmets), samples, kills.
	var y := r.position.y + 94.0
	var rf: int = _s.reinforcements
	var hc := UiStyle.RED if rf <= 1 else UiStyle.YELLOW
	for i in maxi(Mission.REINFORCEMENTS, rf):
		var ic := Vector2(r.position.x + 24 + i * 17, y - 5)
		UiIcons.helmet(self, ic, 6.5, hc if i < rf else Color(1, 1, 1, 0.16))
	UiStyle.text(self, Vector2(r.position.x + 24 + maxi(Mission.REINFORCEMENTS, rf) * 17, y), "x%d" % rf, 14, hc)
	UiIcons.sample(self, Vector2(r.position.x + r.size.x * 0.5 - 14, y - 6), 7.0, UiStyle.BLUE)
	UiStyle.text(self, Vector2(r.position.x + r.size.x * 0.5 - 2, y), "%d" % _s.samples, 15, UiStyle.BLUE)
	UiIcons.skull(self, Vector2(r.end.x - 64, y - 6), 6.5, UiStyle.TEXT)
	UiStyle.text(self, Vector2(r.position.x, y), "%d" % _s.kills, 15, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 16)


## Radio-styled announcement banners (newest at the bottom), sliding in and fading out.
func _draw_banners(vp: Vector2) -> void:
	var y := 128.0
	var warn_list: Array = _s.passage_warning
	if not warn_list.is_empty():
		y += 52.0 + warn_list.size() * 24.0
	var shown: Array = _s.banners.slice(maxi(_s.banners.size() - 3, 0))
	for b in shown:
		var age: float = b.t
		var a := clampf(5.5 - age, 0.0, 1.0)
		var slide := clampf(age / 0.18, 0.0, 1.0)
		var text: String = str(b.text)
		var up := text.to_upper()
		var col := UiStyle.YELLOW
		if up.contains("FAILED") or up.contains("LEFT ORBIT") or up.contains("DEPARTED") or up.contains("REFUSED") or up.contains("OFFLINE") or up.contains("BREACH"):
			col = Color(1.0, 0.4, 0.3)
		elif up.contains("COMPLETE") or up.contains("CLEARED") or up.contains("SEALED") or up.contains("REINFORCED"):
			col = Color(0.75, 1.0, 0.55)
		elif up.contains("LEAVE") or up.contains("REMAINING"):
			col = ORANGE
		var tw := UiStyle.font().get_string_size(up, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
		var w := minf(maxf(tw + 96.0, 300.0), vp.x - 560.0)
		var r := Rect2(vp.x * 0.5 - w * 0.5 + (1.0 - slide) * -60.0, y, w, 44)
		var fa := a * slide
		UiStyle.panel(self, r, Color(CHAT_DARK, 0.8 * fa), 9.0)
		UiStyle.panel_outline(self, r, Color(col, 0.55 * fa), 9.0, 1.5)
		draw_rect(Rect2(r.position + Vector2(0, 5), Vector2(4, r.size.y - 10)), Color(col, fa))
		UiIcons.radio(self, r.position + Vector2(28, 22), 9.0, Color(col, fa), age)
		UiStyle.text(self, r.position + Vector2(52, 15), "incoming transmission", 11, Color(col, 0.6 * fa))
		var font_size := 19 if tw + 96.0 <= w else 16
		UiStyle.text(self, r.position + Vector2(52, 36), text, font_size, Color(col, fa), HORIZONTAL_ALIGNMENT_LEFT, w - 62)
		# Scanlines.
		for i in 4:
			draw_line(r.position + Vector2(6, 8 + i * 10), r.position + Vector2(r.size.x - 6, 8 + i * 10), Color(0, 0, 0, 0.12 * fa), 1.0)
		y += 50.0


func _draw_board_progress(vp: Vector2) -> void:
	if _s.pelican == "landed" and _s.board_progress > 0.0:
		UiStyle.bar(self, Rect2(vp.x * 0.5 - 150, vp.y * 0.6, 300, 14), _s.board_progress, UiStyle.YELLOW)
		UiStyle.text(self, Vector2(0, vp.y * 0.6 - 8), "boarding", 16, UiStyle.YELLOW, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
	elif _s.pelican == "landed":
		UiStyle.text(self, Vector2(0, vp.y * 0.6), "board pelican-1", 20, UiStyle.YELLOW, HORIZONTAL_ALIGNMENT_CENTER, vp.x)


## Objective markers: a diamond with the distance on targets that are on screen; arrows on a
## ring around the player for those that are not (kept off the touch-control edges).
func _draw_markers(vp: Vector2) -> void:
	if _player.dead:
		return
	var targets := _nav_targets()
	targets.sort_custom(func(a, b): return _player.global_position.distance_squared_to(a.pos) < _player.global_position.distance_squared_to(b.pos))
	var ps: Vector2 = (_xf * _player.global_position) / _u
	var shown_arrows := 0
	var inner := Rect2(24, 130, vp.x - 48, vp.y - 260)
	for t in targets:
		var col := UiStyle.YELLOW if not t.optional else Color(0.85, 0.9, 1.0)
		if t.id == "exit" or t.id == "pelican":
			col = UiStyle.BLUE
		var d := _dist_m(t.pos)
		var sp: Vector2 = (_xf * (t.pos as Vector2)) / _u
		var label: String = ("%s  " % t.label if t.label != "" else "") + "%d m" % d
		if inner.has_point(sp):
			if d < 6:
				continue
			var mp := sp + Vector2(0, -78)
			_marker_icon(t.id, mp, col)
			UiStyle.text(self, mp + Vector2(-60, 28), label, 14, col, HORIZONTAL_ALIGNMENT_CENTER, 120)
		elif shown_arrows < 3:
			shown_arrows += 1
			var dir := (sp - ps).normalized()
			var rpos := ps + dir * 118.0
			rpos = rpos.clamp(Vector2(30, 140), Vector2(vp.x - 130, vp.y - 250))
			UiIcons.arrow(self, rpos, dir, 13.0, col)
			var lp := rpos + dir * 30.0
			lp = lp.clamp(Vector2(60, 150), Vector2(vp.x - 190, vp.y - 240))
			UiStyle.text(self, lp + Vector2(-50, 5), label, 14, col, HORIZONTAL_ALIGNMENT_CENTER, 100)


func _marker_icon(id: String, c: Vector2, col: Color) -> void:
	match id:
		"nest":
			UiIcons.hole(self, c, 10.0, col)
		"elite":
			UiIcons.skull(self, c, 10.0, col)
		"exit", "pelican":
			UiIcons.exit_marker(self, c, 11.0, col)
		_:
			UiStyle.diamond(self, c, 10.0, col)
			draw_circle(c, 3.0, Color(0.05, 0.05, 0.05))


# --- Minimap ------------------------------------------------------------------------

## Top-right minimap of the current zone: terrain, fog, objectives, POIs, exit, bugs, player.
func _draw_minimap(vp: Vector2) -> void:
	var m: Dictionary = _s.minimap
	var rect: Rect2 = m.rect
	var size := MINIMAP_SIZE
	var origin := Vector2(vp.x - 16.0 - size, 76.0)
	var scale := size / rect.size.x
	var to_map := func(p: Vector2) -> Vector2: return origin + (p - rect.position) * scale
	UiStyle.text(self, Vector2(origin.x, origin.y - 4), "tactical map", 12, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT, size)
	draw_rect(Rect2(origin - Vector2(3, 3), Vector2(size + 6, size + 6)), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(origin, Vector2(size, size)), Color(0.2, 0.18, 0.13, 0.95))
	var zpos: Vector2 = m.zone_pos
	for r: Rect2 in m.floors:
		draw_rect(Rect2(to_map.call(r.position + zpos), r.size * scale), Color(0.3, 0.3, 0.28, 0.9))
	for r: Rect2 in m.walls:
		var rr := Rect2(to_map.call(r.position + zpos), r.size * scale)
		if rr.size.x < 1.5:
			rr.size.x = 1.5
		if rr.size.y < 1.5:
			rr.size.y = 1.5
		var inside := Rect2(origin - Vector2(4, 4), Vector2(size + 8, size + 8)).intersects(rr)
		if inside:
			draw_rect(rr.intersection(Rect2(origin, Vector2(size, size))), Color(0.62, 0.6, 0.55))
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
				draw_rect(Rect2(origin + Vector2(x0 * cs, yy * cs), Vector2((x - x0) * cs, cs)), Color(0, 0, 0, 0.72))
			else:
				x += 1
	draw_rect(Rect2(origin, Vector2(size, size)), UiStyle.YELLOW_DIM, false, 2.0)
	for c in [origin, origin + Vector2(size, 0), origin + Vector2(0, size), origin + Vector2(size, size)]:
		draw_circle(c, 2.5, UiStyle.YELLOW)
	UiStyle.text(self, origin + Vector2(0, 14), "n", 12, UiStyle.YELLOW, HORIZONTAL_ALIGNMENT_CENTER, size)
	# Entrance (south) and exit (north).
	var ent: Vector2 = to_map.call(m.entrance)
	draw_rect(Rect2(ent + Vector2(-8, -2), Vector2(16, 4)), Color(UiStyle.TEXT_DIM, 0.8))
	var exit_pos: Vector2 = m.exit
	var pulse := 0.5 + 0.5 * sin(_t * 5.0)
	if exit_pos != Vector2.INF:
		var ec: Vector2 = to_map.call(exit_pos)
		var ready: bool = m.main_done or _s.pelican == "landed"
		var ecol := UiStyle.GREEN.lerp(Color.WHITE, pulse * 0.4) if ready else UiStyle.BLUE
		if _s.zone_index == 2:
			draw_arc(ec, 7.0, 0, TAU, 16, ecol, 2.5)
			UiStyle.text(self, ec + Vector2(-30, 18), "pad", 11, ecol, HORIZONTAL_ALIGNMENT_CENTER, 60)
		else:
			ec.y = maxf(ec.y, origin.y + 8.0)
			UiIcons.exit_marker(self, ec + Vector2(0, 2), 5.5, ecol)
	for p in m.pois:
		var c: Vector2 = to_map.call(p.pos)
		if p.kind == "sample":
			UiIcons.sample(self, c, 4.5, UiStyle.BLUE)
		else:
			draw_rect(Rect2(c - Vector2(3.5, 3.5), Vector2(7, 7)), Color(0.05, 0.05, 0.05))
			draw_rect(Rect2(c - Vector2(2.5, 2.5), Vector2(5, 5)), UiStyle.GREEN)
	for t in m.targets:
		var c: Vector2 = to_map.call(t.pos)
		var tc := UiStyle.YELLOW if not t.optional else UiStyle.TEXT
		draw_circle(c, 7.0 + 2.0 * pulse, Color(tc, 0.2))
		if t.id == "nest":
			UiIcons.hole(self, c, 5.0, tc)
		elif t.id == "elite":
			UiIcons.skull(self, c, 5.0, tc)
		else:
			UiStyle.diamond(self, c, 6.0, tc)
	for e in m.enemies:
		var ep: Vector2 = to_map.call(e.pos)
		if e.alert:
			draw_circle(ep, 3.2, Color(0.05, 0.0, 0.0))
			draw_circle(ep, 2.4, UiStyle.RED)
		else:
			draw_circle(ep, 2.2, Color(1, 0.55, 0.3, 0.75))
	var pc: Vector2 = to_map.call(m.player)
	var f := Vector2.UP.rotated(m.look)
	# Sight cone and the player arrow.
	var cone := PackedVector2Array([pc, pc + f.rotated(-0.9) * 28.0 * scale * 1.4, pc + f.rotated(0.0) * 30.0 * scale * 1.4, pc + f.rotated(0.9) * 28.0 * scale * 1.4])
	draw_colored_polygon(cone, Color(UiStyle.GREEN, 0.18))
	UiIcons.arrow(self, pc, f, 6.5, UiStyle.GREEN)


func _draw_kill_feed(vp: Vector2) -> void:
	var feed: Array = _s.kill_feed
	var right := vp.x - 16.0 - MINIMAP_SIZE - 12.0
	var y := 90.0
	for k in feed:
		var a := clampf(5.0 - (k.t as float), 0.0, 1.0)
		var slide := clampf((k.t as float) / 0.15, 0.0, 1.0)
		var txt := str(k.text)
		var pts := "+%d" % k.pts
		var tw := UiStyle.font().get_string_size(txt.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var w := tw + 70.0
		var r := Rect2(right - w + (1.0 - slide) * 40.0, y - 15, w, 22)
		draw_rect(r, Color(0, 0, 0, 0.45 * a))
		UiIcons.skull(self, Vector2(r.position.x + 12, y - 4), 6.0, Color(UiStyle.TEXT, a))
		UiStyle.text(self, Vector2(r.position.x + 24, y), txt, 14, Color(UiStyle.TEXT, a))
		UiStyle.text(self, Vector2(r.position.x, y), pts, 14, Color(UiStyle.YELLOW, a), HORIZONTAL_ALIGNMENT_RIGHT, w - 6)
		y += 25.0


func _draw_top_buttons(vp: Vector2) -> void:
	var right := vp.x - (100.0 if OS.has_feature("web") else 16.0)
	_btn("pause", UiStyle.button(self, Rect2(right - 70, 10, 70, 46), "II", false, 20))


# --- Vitals (left column, below the STRAT button) -----------------------------------

func _draw_vitals() -> void:
	var r := Rect2(16, 322, 236, 100)
	UiStyle.panel(self, r)
	UiStyle.accent(self, r)
	var hp_frac: float = clampf(_player.hp / _player.max_hp, 0.0, 1.0)
	var low := hp_frac < 0.3
	var hp_col := UiStyle.RED if low else (UiStyle.YELLOW if hp_frac < 0.6 else UiStyle.TEXT)
	var pulse := 0.5 + 0.5 * sin(_t * 8.0)
	UiIcons.heart(self, r.position + Vector2(26, 24), 9.0 + (1.5 * pulse if low else 0.0), hp_col)
	UiStyle.bar(self, Rect2(r.position.x + 44, r.position.y + 12, 140, 18), hp_frac, hp_col, 10)
	UiStyle.text(self, Vector2(r.position.x + 44, r.position.y + 27), "%d" % ceili(_player.hp), 16, Color(0.05, 0.05, 0.05) if hp_frac > 0.2 else UiStyle.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 140)
	if _player.is_healing():
		UiStyle.text(self, Vector2(r.position.x, r.position.y + 27), "+", 22, UiStyle.GREEN, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 14)
	# Stamina.
	var st: float = _player.stamina
	var scol := Color(0.4, 0.8, 1.0) if st > 0.25 else ORANGE
	UiStyle.text(self, Vector2(r.position.x + 16, r.position.y + 51), "stm", 12, UiStyle.TEXT_DIM)
	UiStyle.bar(self, Rect2(r.position.x + 44, r.position.y + 41, 140, 8), st, scol)
	# Stims and grenades.
	var y := r.position.y + 78.0
	for i in _player.max_stims:
		UiIcons.syringe(self, Vector2(r.position.x + 30 + i * 22, y - 2), 8.0, UiStyle.GREEN if i < _player.stims else Color(1, 1, 1, 0.15))
	for i in _player.max_grenades:
		UiIcons.grenade(self, Vector2(r.position.x + 130 + i * 21, y - 2), 8.0, UiStyle.YELLOW if i < _player.grenades else Color(1, 1, 1, 0.15))


# --- Stratagems ---------------------------------------------------------------------

## Bottom-centre block between the move hint and the STIM / RELOAD buttons.
func _block_rect(vp: Vector2) -> Rect2:
	var left := 300.0
	var right := vp.x - 510.0
	var avail := right - left
	var w := minf(avail, 600.0)
	return Rect2(left + (avail - w) * 0.5, 0, w, 0)


## Cards: category glyph, short name, charges (+ cap pips), meter fill (cost) toward the next charge.
func _draw_stratagem_bar(vp: Vector2) -> void:
	if _strat == null or _strat.equipped.is_empty():
		return
	var b := _block_rect(vp)
	var n := _strat.equipped.size()
	var gap := 6.0
	var cw := (b.size.x - gap * (n - 1)) / n
	var h := 66.0
	var y := vp.y - 92.0 - 8.0 - h
	for i in n:
		var id: String = _strat.equipped[i]
		var def: Dictionary = Stratagems.DEFS[id]
		var r := Rect2(b.position.x + i * (cw + gap), y, cw, h)
		var charges := _strat.charges(id)
		var cap := _strat.cap(id)
		var col: Color = def.color
		var usable := charges > 0 and not _strat.locked
		var flash: float = _strat.gained.get(id, 99.0)
		var cd: float = _strat.status[id].cd
		UiStyle.panel(self, r, Color(col, 0.26) if usable else UiStyle.PANEL_SOLID, 8.0)
		var outline_col := UiStyle.YELLOW if flash < 1.2 else (col if usable else Color(1, 1, 1, 0.2))
		UiStyle.panel_outline(self, r, outline_col, 8.0, 3.0 if flash < 1.2 else 2.0)
		if flash < 1.2:
			var fa := 1.0 - flash / 1.2
			draw_rect(r, Color(UiStyle.YELLOW, 0.3 * fa))
		var gc := col if usable else Color(0.45, 0.45, 0.45)
		UiIcons.strat(self, id, r.position + Vector2(20, 22), 12.0, gc)
		var qty_col := UiStyle.YELLOW if usable else UiStyle.TEXT_DIM
		UiStyle.text(self, r.position + Vector2(0, 28), "x%d" % charges, 24, qty_col, HORIZONTAL_ALIGNMENT_RIGHT, cw - 8)
		# Cap pips.
		for k in cap:
			draw_circle(r.position + Vector2(cw - 12 - (cap - 1 - k) * 8, 36), 2.6, qty_col if k < charges else Color(1, 1, 1, 0.18))
		var label: String = def.short
		if id.begins_with("eagle") and charges == 0:
			label = "rearm"
		UiStyle.text(self, r.position + Vector2(8, 46), label, 14, UiStyle.TEXT if usable else UiStyle.TEXT_DIM)
		var bar := Rect2(r.position + Vector2(6, h - 13), Vector2(cw - 12, 7))
		var frac := _strat.meter_frac(id)
		UiStyle.bar(self, bar, frac, col if _strat.fill_enabled else Color(0.5, 0.5, 0.5))
		if cd > 0.0 and not _strat.locked:
			draw_rect(Rect2(r.position, Vector2(r.size.x * cd, r.size.y)), Color(0, 0, 0, 0.5))
		if _strat.locked:
			draw_rect(r, Color(0, 0, 0, 0.5))
			UiStyle.text(self, r.position + Vector2(0, 40), "locked", 14, UiStyle.RED, HORIZONTAL_ALIGNMENT_CENTER, cw)


func _draw_interact_prompt(vp: Vector2) -> void:
	var it: Interactable = _player.interact_target
	if it == null or _player.dead:
		return
	var b := _block_rect(vp)
	var r := Rect2(b.position.x + b.size.x * 0.5 - 150, vp.y - 92.0 - 8.0 - 66.0 - 62.0, 300, 50)
	UiStyle.panel(self, r, UiStyle.PANEL_SOLID)
	UiStyle.accent(self, r)
	UiStyle.text(self, r.position + Vector2(16, 22), "hold  " + it.label, 16, UiStyle.YELLOW)
	UiStyle.bar(self, Rect2(r.position + Vector2(16, 32), Vector2(r.size.x - 32, 9)), it.progress / it.hold_time, UiStyle.YELLOW)


## Bottom: weapon silhouette, name + fire mode, rounds, magazine pips, spare mags, status.
func _draw_weapon_panel(vp: Vector2) -> void:
	var b := _block_rect(vp)
	var r := Rect2(b.position.x, vp.y - 92.0, b.size.x, 82)
	UiStyle.panel(self, r)
	UiStyle.accent(self, r)
	var w := _weapon
	var x := r.position.x + 16
	var y := r.position.y
	# Silhouette (rotated to point right) and name.
	var local := Transform2D(PI / 2.0, Vector2(1.0, 1.0), 0.0, Vector2(x + 44, y + 40))
	draw_set_transform_matrix(Transform2D(Vector2(_u, 0), Vector2(0, _u), Vector2.ZERO) * local)
	WeaponArt.draw(self, w.stats.model, 0.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(_u, _u))
	UiStyle.text(self, Vector2(x + 96, y + 22), w.stats.display_name, 15, UiStyle.YELLOW)
	var mode := w.fire_mode_name()
	var mw := UiStyle.font().get_string_size(mode.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 12
	UiStyle.panel(self, Rect2(r.end.x - mw - 14, y + 8, mw, 20), Color(UiStyle.YELLOW, 0.2), 4.0)
	UiStyle.text(self, Vector2(r.end.x - mw - 14, y + 23), mode, 12, UiStyle.YELLOW, HORIZONTAL_ALIGNMENT_CENTER, mw)
	if w.has_support():
		var other: FirearmStats = w.slots[1 - w.slot].stats
		UiStyle.text(self, Vector2(x, y + 76), "swap: " + other.display_name, 12, UiStyle.GREEN)
	# Rounds.
	var total := w.rounds_loaded()
	var low := total <= w.stats.mag_size / 4
	var rounds := "%d+1" % w.stats.mag_size if total > w.stats.mag_size else "%d" % total
	UiStyle.text(self, Vector2(x + 96, y + 62), rounds, 34, UiStyle.RED if low else UiStyle.TEXT)
	var rw := UiStyle.font().get_string_size(rounds.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
	# Magazine pips: one per round, fills right to left.
	var n: int = w.stats.mag_size
	var avail := r.end.x - (x + 96 + rw + 14) - 12.0
	var spare: int = w.mags.size()
	var mag_w := minf(12.0 * spare, 70.0)
	var pip_area := avail - mag_w - 16.0
	var pw := clampf(pip_area / maxf(n, 1), 1.5, 7.0)
	var px0 := x + 96 + rw + 14
	var busy := w.state == Firearm.State.RELOADING or w.state == Firearm.State.CLEARING
	if busy:
		var k := w.state_progress()
		UiStyle.bar(self, Rect2(px0, y + 44, pip_area, 12), k, UiStyle.BLUE if not w.jammed else UiStyle.RED)
	else:
		var rows := 1 if pw * n <= pip_area else 2
		var per_row := int(ceil(n / float(rows)))
		pw = clampf(pip_area / maxf(per_row, 1), 1.5, 7.0)
		for i in n:
			var rr := i / per_row
			var cc := i % per_row
			var filled := i < w.mag
			var c := Color(0.95, 0.95, 0.9) if filled else Color(1, 1, 1, 0.14)
			if filled and low:
				c = UiStyle.RED
			draw_rect(Rect2(px0 + cc * pw, y + 40 + rr * 11, maxf(pw - 1.0, 1.0), 9), c)
	# Spare mags (fill = rounds left) and count.
	var mx := r.end.x - mag_w - 14
	for i in spare:
		var mh := 22.0
		var fill := mh * w.mags[i] / float(maxi(w.stats.mag_size, 1))
		var rx := mx + i * 12
		if rx > r.end.x - 20:
			break
		draw_rect(Rect2(rx, y + 40, 9, mh), Color(1, 1, 1, 0.14))
		draw_rect(Rect2(rx, y + 40 + mh - fill, 9, fill), UiStyle.TEXT)
		draw_rect(Rect2(rx, y + 40, 9, mh), Color(0, 0, 0, 0.6), false, 1.0)
	UiStyle.text(self, Vector2(mx, y + 74), "mags %d" % spare, 13, UiStyle.TEXT_DIM if spare > 0 else UiStyle.RED)
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
		var nw := UiStyle.font().get_string_size(str(w.stats.display_name).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		UiStyle.text(self, Vector2(x + 96 + nw + 12, y + 22), status, 14, col)


func _draw_perf(vp: Vector2) -> void:
	var proc_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	UiStyle.text(self, Vector2(10, vp.y - 6), "%d fps  proc %.1f  phys %.1f  decals %d  fx %d" % [Engine.get_frames_per_second(), proc_ms, phys_ms, Fx.decal_count(), Fx.particle_count()], 12, Color(1, 1, 1, 0.3))


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
	if _mission and _s.respawn_in >= 0.0:
		for i in Mission.REINFORCEMENTS:
			UiIcons.helmet(self, Vector2(vp.x * 0.5 - (Mission.REINFORCEMENTS - 1) * 14.0 + i * 28.0, vp.y * 0.42 + 80), 9.0,
				UiStyle.YELLOW if i < int(_s.reinforcements) else Color(1, 1, 1, 0.15))


func _draw_pause(vp: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.65))
	var w := 360.0
	var x := vp.x * 0.5 - w * 0.5
	UiStyle.text(self, Vector2(0, vp.y * 0.24), "paused", 40, UiStyle.YELLOW, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
	_btn("resume", UiStyle.button(self, Rect2(x, vp.y * 0.31, w, 60), "RESUME", true))
	_btn("restart", UiStyle.button(self, Rect2(x, vp.y * 0.31 + 72, w, 60), "RESTART"))
	_btn("shake", UiStyle.button(self, Rect2(x, vp.y * 0.31 + 144, w, 60), "SCREEN SHAKE: " + ("ON" if Game.shake_enabled else "OFF"), false, 20))
	_btn("menu", UiStyle.button(self, Rect2(x, vp.y * 0.31 + 216, w, 60), "ABANDON MISSION" if _mission else "MAIN MENU"))


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
		var ic := Vector2(r.position.x + 52, y - 5)
		if st == "done":
			UiIcons.check(self, ic, 8.0, UiStyle.YELLOW)
		elif st == "failed":
			UiIcons.cross(self, ic, 7.0, UiStyle.RED)
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
	_btn("retry", UiStyle.button(self, Rect2(r.get_center().x - bw - 10, r.end.y - 84, bw, 60), "RESTART", true))
	_btn("menu", UiStyle.button(self, Rect2(r.get_center().x + 10, r.end.y - 84, bw, 60), "MENU"))
