class_name EnemyUi
extends RefCounted
## Shared real-time overlays of the enemies: HP bar, awareness icon ("?" yellow, filling with
## suspicion / "!" red = alert), ricochet shield, floating damage numbers. They are drawn on
## small screen-upright child nodes that only exist visibly while something is shown (see
## Enemies.make_overlay); the bodies themselves are cutout rigs and never re-record any drawing.

enum Icon { NONE, SUSPICIOUS, ALERT }

const YELLOW := Color(1.0, 0.85, 0.15)
const RED := Color(1.0, 0.25, 0.15)


static func hp_bar(ci: CanvasItem, top: float, w: float, h: float, frac: float, a: float, heavy: bool, color_override := Color(0, 0, 0, 0)) -> void:
	var r := Rect2(-w * 0.5, top, w, h)
	ci.draw_rect(r.grow(1.5), Color(0, 0, 0, 0.7 * a))
	var f := clampf(frac, 0.0, 1.0)
	var col := Color(0.4, 0.9, 0.3, a) if f > 0.5 else (Color(1, 0.8, 0.1, a) if f > 0.25 else Color(0.95, 0.2, 0.15, a))
	if color_override.a > 0.0:
		col = color_override if f > 0.3 else Color(1.0, 0.15, 0.1)
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x * f, r.size.y)), col)
	if heavy:
		ci.draw_rect(r, Color(1, 1, 1, 0.3), false, 1.0)


## Round badge with "?" (fill 0..1 = suspicion, the ring fills up) or "!" (alert, pops in).
static func icon(ci: CanvasItem, kind: int, c: Vector2, size: float, fill: float, pop: float) -> void:
	if kind == Icon.NONE:
		return
	var font := ThemeDB.fallback_font
	var col := YELLOW if kind == Icon.SUSPICIOUS else RED
	var rr := size * pop
	ci.draw_circle(c, rr + 1.5, Color(0.05, 0.04, 0.04, 0.9))
	ci.draw_circle(c, rr, Color(col, 0.35 if kind == Icon.SUSPICIOUS else 0.92))
	if kind == Icon.SUSPICIOUS:
		# Fill level: the badge fills from the bottom with the suspicion meter.
		var f := clampf(fill, 0.0, 1.0)
		ci.draw_arc(c, rr * 0.5, PI * 0.5 - PI * f, PI * 0.5 + PI * f, 16, Color(col, 0.95), rr, true)
		ci.draw_arc(c, rr + 0.5, -PI * 0.5, -PI * 0.5 + TAU * f, 24, col, 2.2, true)
	var txt := "?" if kind == Icon.SUSPICIOUS else "!"
	ci.draw_string(font, c + Vector2(-rr, rr * 0.62), txt, HORIZONTAL_ALIGNMENT_CENTER, rr * 2.0, int(rr * 1.9), Color(0.08, 0.05, 0.03))


static func shield(ci: CanvasItem, c: Vector2, a: float, k := 1.0) -> void:
	var shield_pts := PackedVector2Array([Vector2(-6, -7), Vector2(6, -7), Vector2(6, 1), Vector2(0, 8), Vector2(-6, 1)])
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for v in shield_pts:
		outer.append(c + v * 1.3 * k)
		inner.append(c + v * k)
	ci.draw_colored_polygon(outer, Color(0.05, 0.05, 0.05, 0.9 * a))
	ci.draw_colored_polygon(inner, Color(1.0, 0.88, 0.2, a))
	ci.draw_line(c + Vector2(-4, 4) * k, c + Vector2(4, -4) * k, Color(0.1, 0.08, 0.04, a), 2.0 * k)


static func numbers(ci: CanvasItem, list: Array, base_y: float, crit_col: Color, sz: int, k := 1.0) -> void:
	var font := ThemeDB.fallback_font
	for n in list:
		var a: float = 1.0 - n.t / 0.9
		var col := crit_col if n.crit else Color(1, 0.95, 0.5)
		col.a = a
		ci.draw_string(font, Vector2(n.x * k - 50, base_y - n.t * 40.0 * k), n.text, HORIZONTAL_ALIGNMENT_CENTER, 100,
			int((sz + 4 if n.crit else sz) * k), col)
