class_name StratMenu
extends Control
## Stratagem selection UI (screen space, drawn with _draw()). State lives in Stratagems:
##   RADIAL  press-and-swipe: ring of the loadout around the thumb, release toward one
##           to quick-throw it; release in the centre dead-zone cancels.
##   MENU    tap: large list rows (tap one -> aim mode). Locked rows say why.
##   AIM     throw arc, landing marker with the effect radius (barrage circle, Eagle line
##           perpendicular to the throw, sentry footprint), THROW / CANCEL buttons.
## Plus the arrow glyphs that tick above the Helldiver's head while the code is typed.
## Geometry helpers are static so TouchControls can hit-test the same layout.
## Category colours come from Stratagems.DEFS (Eagle red, Orbital red-orange, Support
## blue, Defensive green, Supply blue-grey).

const RADIAL_R := 150.0
const ITEM_R := 46.0
const DEAD_ZONE := 48.0
const ROW_H := 82.0
const LIST_W := 540.0
const HEAD_H := 58.0
const THROW_R := 80.0
const CANCEL_R := 50.0
const DARK := Color(0.04, 0.04, 0.04, 0.95)
const GREY := Color(0.5, 0.5, 0.5)

var _strat: Stratagems
var _player: Node2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 5


func _process(_delta: float) -> void:
	if _strat == null:
		_strat = get_tree().get_first_node_in_group("stratagems") as Stratagems
		_player = get_tree().get_first_node_in_group("player") as Node2D
	queue_redraw()


# --- Geometry (static: shared with TouchControls) ---------------------------------------------

## Ring centre kept fully on screen.
static func clamp_center(c: Vector2, vp: Vector2) -> Vector2:
	var m := RADIAL_R + ITEM_R + 12.0
	return Vector2(clampf(c.x, m, maxf(vp.x - m, m)), clampf(c.y, m, maxf(vp.y - m, m)))


static func radial_pos(i: int, n: int, center: Vector2) -> Vector2:
	return center + Vector2.from_angle(-PI / 2.0 + TAU * i / maxi(n, 1)) * RADIAL_R


## Item the pointer is swiping toward (-1 = centre dead-zone).
static func radial_hover(center: Vector2, pointer: Vector2, n: int) -> int:
	var d := pointer - center
	if n <= 0 or d.length() < DEAD_ZONE:
		return -1
	var a := wrapf(d.angle() + PI / 2.0, 0.0, TAU)
	return int(roundf(a / (TAU / n))) % n


static func list_rect(vp: Vector2, n: int) -> Rect2:
	var h := HEAD_H + ROW_H * n + 52.0
	return Rect2(Vector2((vp.x - LIST_W) * 0.5, maxf((vp.y - h) * 0.5, 8.0)), Vector2(LIST_W, h))


static func row_rect(vp: Vector2, n: int, i: int) -> Rect2:
	var r := list_rect(vp, n)
	return Rect2(r.position + Vector2(10, HEAD_H + i * ROW_H), Vector2(r.size.x - 20, ROW_H - 8))


static func close_rect(vp: Vector2, n: int) -> Rect2:
	var r := list_rect(vp, n)
	return Rect2(r.end.x - 70, r.position.y + 4, 64, 50)


## Row under p, -1 none.
static func row_at(vp: Vector2, n: int, p: Vector2) -> int:
	for i in n:
		if row_rect(vp, n, i).has_point(p):
			return i
	return -1


static func throw_center(vp: Vector2) -> Vector2:
	return Vector2(vp.x - 170, vp.y - 170)


static func cancel_center(vp: Vector2) -> Vector2:
	return Vector2(vp.x - 175, vp.y - 335)


# --- Drawing ------------------------------------------------------------------------------------

func _draw() -> void:
	if _strat == null or _player == null or _player.get("dead"):
		return
	var vp := get_viewport_rect().size
	match _strat.ui:
		Stratagems.Ui.AIM:
			_draw_aim(vp)
		Stratagems.Ui.RADIAL:
			_draw_radial(vp)
		Stratagems.Ui.MENU:
			_draw_list(vp)
	if _strat.typing_id != "":
		_draw_typing()


func _label(pos: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var t := s.to_upper()
	draw_string_outline(UiStyle.font(), pos, t, align, width, size, maxi(size / 4, 3), DARK)
	draw_string(UiStyle.font(), pos, t, align, width, size, col)


func _info(id: String) -> Dictionary:
	var why := _strat.pick_error(id)
	var def: Dictionary = Stratagems.DEFS[id]
	var col: Color = def.color
	return {"why": why, "ok": why == "", "col": col if why == "" else GREY, "cat": col, "def": def}


## A disc with a dark outline and a coloured ring.
func _disc(c: Vector2, r: float, col: Color, fill: Color, width := 3.0) -> void:
	draw_circle(c, r + 3.0, DARK)
	draw_circle(c, r, fill)
	draw_arc(c, r - 1.0, 0.0, TAU, 40, col, width)


func _draw_radial(vp: Vector2) -> void:
	var n := _strat.equipped.size()
	var c := _strat.radial_center
	var hover := radial_hover(c, _strat.radial_pointer, n)
	draw_circle(c, RADIAL_R + ITEM_R + 8.0, Color(0, 0, 0, 0.3))
	draw_arc(c, RADIAL_R, 0.0, TAU, 64, Color(1, 1, 1, 0.12), 2.0)
	_disc(c, DEAD_ZONE - 8.0, UiStyle.YELLOW_DIM, Color(0, 0, 0, 0.5), 2.0)
	for i in n:
		var id: String = _strat.equipped[i]
		var inf := _info(id)
		var p := radial_pos(i, n, c)
		var on := i == hover
		if on:
			draw_line(c, p, Color(inf.col, 0.5), 4.0)
		var r := ITEM_R * (1.15 if on else 1.0)
		var fill := Color(inf.cat, 0.55) if (on and inf.ok) else (Color(0.12, 0.12, 0.12, 0.92) if inf.ok else Color(0.08, 0.08, 0.08, 0.92))
		_disc(p, r, UiStyle.YELLOW if on and inf.ok else inf.col, fill, 4.0 if on else 3.0)
		UiIcons.strat(self, id, p + Vector2(0, -4), 17.0, inf.col)
		_label(p + Vector2(-r, r + 18), inf.def.short, 15, UiStyle.TEXT if inf.ok else UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0)
		# Charges, and the meter toward the next one around the disc.
		_label(p + Vector2(r * 0.55, -r * 0.55), "x%d" % _strat.charges(id), 15, UiStyle.YELLOW if inf.ok else UiStyle.RED)
		var mf := _strat.meter_frac(id)
		if mf > 0.0:
			draw_arc(p, r + 7.0, -PI / 2.0, -PI / 2.0 + TAU * mf, 28, Color(inf.cat, 0.9), 3.0)
	# Centre text: what is hovered and why it is locked.
	if hover >= 0:
		var id: String = _strat.equipped[hover]
		var inf := _info(id)
		_label(c + Vector2(-110, -4), inf.def.name, 13, UiStyle.YELLOW if inf.ok else UiStyle.RED, HORIZONTAL_ALIGNMENT_CENTER, 220.0)
		_label(c + Vector2(-110, 14), "release to throw" if inf.ok else inf.why, 12, UiStyle.TEXT if inf.ok else UiStyle.RED, HORIZONTAL_ALIGNMENT_CENTER, 220.0)
	else:
		_label(c + Vector2(-60, 5), "cancel", 13, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, 120.0)
	_label(c + Vector2(-160, -RADIAL_R - ITEM_R - 20), "swipe to a stratagem", 14, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, 320.0)


func _draw_list(vp: Vector2) -> void:
	var n := _strat.equipped.size()
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.35))
	var r := list_rect(vp, n)
	UiStyle.panel(self, r.grow(3.0), DARK, 14.0)
	UiStyle.panel(self, r, UiStyle.PANEL_SOLID, 12.0)
	UiStyle.panel_outline(self, r, UiStyle.RED if _strat.error_t > 0.0 else UiStyle.YELLOW, 12.0, 2.5)
	_label(r.position + Vector2(20, 38), "stratagems", 24, UiStyle.YELLOW)
	var cr := close_rect(vp, n)
	UiStyle.panel(self, cr, Color(0.12, 0.12, 0.12), 8.0)
	UiStyle.panel_outline(self, cr, UiStyle.TEXT_DIM, 8.0, 2.0)
	_label(cr.position + Vector2(0, 33), "X", 24, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_CENTER, cr.size.x)
	for i in n:
		var id: String = _strat.equipped[i]
		var inf := _info(id)
		var rr := row_rect(vp, n, i)
		UiStyle.panel(self, rr, Color(inf.cat, 0.22) if inf.ok else Color(0.1, 0.1, 0.1, 0.95), 10.0)
		UiStyle.panel_outline(self, rr, inf.col if inf.ok else Color(1, 1, 1, 0.2), 10.0, 2.5)
		draw_rect(Rect2(rr.position + Vector2(0, 4), Vector2(6, rr.size.y - 8)), inf.col)
		# Hotkey badge, icon box.
		_label(rr.position + Vector2(16, 44), str(i + 1), 20, UiStyle.TEXT_DIM)
		var ib := Rect2(rr.position + Vector2(44, 8), Vector2(rr.size.y - 16, rr.size.y - 16))
		draw_rect(ib.grow(2.0), DARK)
		draw_rect(ib, Color(0.1, 0.1, 0.1, 0.9))
		UiIcons.strat(self, id, ib.get_center(), 17.0, inf.col)
		var tx := ib.end.x + 14.0
		_label(Vector2(tx, rr.position.y + 28), inf.def.name, 18, UiStyle.TEXT if inf.ok else UiStyle.TEXT_DIM)
		if inf.ok:
			var code: Array = inf.def.code
			for k in code.size():
				UiIcons.arrow(self, Vector2(tx + 8 + k * 20, rr.position.y + 54), [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT][int(code[k])], 7.0, UiStyle.TEXT_DIM)
			_label(Vector2(tx + 12 + code.size() * 20, rr.position.y + 59), "auto %.1f s" % _strat.code_time(id), 13, UiStyle.TEXT_DIM)
		else:
			_label(Vector2(tx, rr.position.y + 56), inf.why, 14, UiStyle.RED)
		# Charges and meter on the right.
		var cap := _strat.cap(id)
		_label(Vector2(rr.end.x - 150, rr.position.y + 30), "x%d / %d" % [_strat.charges(id), cap], 20, UiStyle.YELLOW if inf.ok else UiStyle.RED, HORIZONTAL_ALIGNMENT_RIGHT, 140.0)
		UiStyle.bar(self, Rect2(rr.end.x - 150, rr.position.y + 46, 140, 9), _strat.meter_frac(id), inf.cat if _strat.fill_enabled else GREY)
	_label(r.position + Vector2(0, r.size.y - 18), "tap a stratagem to aim   -   Q / 1-5", 14, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


func _draw_aim(vp: Vector2) -> void:
	var id := _strat.aim_id
	if id == "":
		return
	var xf := get_viewport().get_canvas_transform()
	var sc := xf.get_scale().x
	var inf := _info(id)
	var col: Color = inf.cat
	var from: Vector2 = _player.global_position
	var want := _strat.aim_point()
	var land := _strat.landing_point(want)
	var blocked := land.distance_to(want) > 2.0
	var sky_bad: bool = _strat.DEFS[id].get("airborne", false) and _strat.roofed(land)
	if sky_bad:
		col = UiStyle.RED
	var P := xf * from
	var L := xf * land
	var dir := (L - P).normalized() if L.distance_to(P) > 1.0 else Vector2.UP
	# Throw arc: dashed parabola from the Helldiver to the landing point.
	var dist := P.distance_to(L)
	var h := clampf(dist * 0.28, 16.0, 150.0)
	var pts := PackedVector2Array()
	for i in 25:
		var t := i / 24.0
		pts.append(P.lerp(L, t) + Vector2.UP * sin(t * PI) * h)
	for i in range(0, 24, 2):
		draw_line(pts[i], pts[i + 1], DARK, 6.0)
	for i in range(0, 24, 2):
		draw_line(pts[i], pts[i + 1], Color(col, 0.95), 3.0)
	# Effect footprint.
	var pv := _strat.preview(id)
	var rp: float = float(pv.r_m) * Firearm.PX_PER_M * sc
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.008)
	if pv.kind == "line":
		var perp := dir.orthogonal()
		var span: float = float(pv.span_m) * Firearm.PX_PER_M * sc * 0.5
		draw_line(L - perp * (span + rp), L + perp * (span + rp), DARK, 7.0)
		draw_line(L - perp * (span + rp), L + perp * (span + rp), Color(col, 0.9), 3.0)
		for i in 5:
			var bc := L + perp * (i - 2) * (span / 2.0)
			draw_circle(bc, rp, Color(col, 0.14 + 0.06 * pulse))
			draw_arc(bc, rp + 1.5, 0.0, TAU, 28, DARK, 4.0)
			draw_arc(bc, rp, 0.0, TAU, 28, Color(col, 0.9), 2.0)
		draw_line(L, L + dir * 40.0, Color(col, 0.9), 3.0) # flight bearing
		draw_colored_polygon(PackedVector2Array([L + dir * 56.0, L + dir * 40.0 + perp * 9.0, L + dir * 40.0 - perp * 9.0]), Color(col, 0.9))
	else:
		draw_circle(L, rp, Color(col, 0.13 + 0.06 * pulse))
		draw_arc(L, rp + 1.5, 0.0, TAU, 56, DARK, 5.0)
		draw_arc(L, rp, 0.0, TAU, 56, Color(col, 0.95), 3.0)
		if pv.get("sentry", false):
			var s := Firearm.PX_PER_M * sc * 0.5
			draw_rect(Rect2(L - Vector2(s, s), Vector2(s, s) * 2.0), Color(col, 0.4))
			draw_rect(Rect2(L - Vector2(s, s), Vector2(s, s) * 2.0), DARK, false, 2.0)
	# Landing marker.
	draw_circle(L, 7.0, DARK)
	draw_circle(L, 4.5, Color(col.lightened(0.3), 1.0))
	for i in 4:
		var d := Vector2.from_angle(i * PI / 2.0 + PI / 4.0)
		draw_line(L + d * 9.0, L + d * 17.0, DARK, 5.0)
		draw_line(L + d * 9.0, L + d * 17.0, col, 2.5)
	if blocked:
		var W := xf * want
		draw_line(W + Vector2(-7, -7), W + Vector2(7, 7), UiStyle.RED, 3.0)
		draw_line(W + Vector2(-7, 7), W + Vector2(7, -7), UiStyle.RED, 3.0)
	# Text next to the marker.
	var meters := roundi(from.distance_to(land) / Firearm.PX_PER_M)
	var tag := "%s  %d m" % [Stratagems.DEFS[id].name, meters]
	if pv.kind == "line":
		tag += "  -  line"
	else:
		tag += "  -  R %s m" % [str(snappedf(float(pv.r_m), 0.1))]
	_label(L + Vector2(-160, -maxf(rp, 30.0) - 14.0), tag, 15, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 320.0)
	if sky_bad:
		_label(L + Vector2(-160, maxf(rp, 30.0) + 26.0), "no sky access - roofed", 15, UiStyle.RED, HORIZONTAL_ALIGNMENT_CENTER, 320.0)
	elif blocked:
		_label(L + Vector2(-160, maxf(rp, 30.0) + 26.0), "wall blocks the throw", 15, UiStyle.YELLOW, HORIZONTAL_ALIGNMENT_CENTER, 320.0)
	# Buttons / hints.
	if _strat.aim_mouse:
		_label(Vector2(vp.x * 0.5 - 300, vp.y - 40), "click: throw    right click / q: cancel", 16, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 600.0)
		return
	var tc := throw_center(vp)
	var waiting := _strat.is_typing()
	_disc(tc, THROW_R, UiStyle.YELLOW, Color(UiStyle.YELLOW, 0.5) if not waiting else Color(0.1, 0.1, 0.1, 0.85), 3.0)
	_label(tc + Vector2(-THROW_R, 8), "wait" if (waiting and _strat.throw_queued) else "throw", 24, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, THROW_R * 2.0)
	if waiting:
		draw_arc(tc, THROW_R - 7.0, -PI / 2.0, -PI / 2.0 + TAU * _strat.typing_t / _strat.code_time(_strat.typing_id), 40, UiStyle.YELLOW, 6.0)
	var cc := cancel_center(vp)
	_disc(cc, CANCEL_R, UiStyle.RED, Color(0, 0, 0, 0.6), 3.0)
	_label(cc + Vector2(-CANCEL_R, 7), "cancel", 17, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, CANCEL_R * 2.0)
	_label(Vector2(vp.x - 420, vp.y - 420), "drag to aim  -  release to throw", 15, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, 380.0)


## Arrows ticking above the Helldiver's head while the code is typed.
func _draw_typing() -> void:
	var id := _strat.typing_id
	var code: Array = Stratagems.DEFS[id].code
	var col: Color = Stratagems.DEFS[id].color
	var xf := get_viewport().get_canvas_transform()
	var head := xf * _player.global_position + Vector2(0, -62)
	var n := code.size()
	var step := 26.0
	var w := n * step + 16.0
	var bg := Rect2(head - Vector2(w * 0.5, 17), Vector2(w, 34))
	draw_rect(bg.grow(2.0), DARK)
	draw_rect(bg, Color(0.06, 0.06, 0.06, 0.85))
	var typed := int(_strat.typing_t / Stratagems.TYPE_PER_ARROW + 0.0001)
	var flash: float = _strat.typing_flash
	for i in n:
		var c := head + Vector2((i - (n - 1) * 0.5) * step, 0)
		var v: Vector2 = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT][int(code[i])]
		var lit := i < typed
		var colr := Color(col.lightened(0.35), 1.0) if lit else Color(1, 1, 1, 0.28)
		if flash > 0.0:
			colr = UiStyle.RED
		UiIcons.arrow(self, c, v, 8.0 if lit else 7.0, colr)
	if flash > 0.0:
		_label(head + Vector2(-80, -24), "interrupted", 14, UiStyle.RED, HORIZONTAL_ALIGNMENT_CENTER, 160.0)
	elif _strat.typing_ready():
		draw_rect(Rect2(bg.position, Vector2(w, 3)), Color(col, 0.9))
