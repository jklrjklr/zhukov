class_name UiStyle
## Helldivers-style look: black glass panels, hazard yellow accents, upper-case text,
## clipped corners. Static draw helpers used by the HUD and menus.

const YELLOW := Color(1.0, 0.9, 0.06)
const YELLOW_DIM := Color(1.0, 0.9, 0.06, 0.35)
const PANEL := Color(0.0, 0.0, 0.0, 0.55)
const PANEL_SOLID := Color(0.05, 0.05, 0.05, 0.92)
const TEXT := Color(0.95, 0.95, 0.92)
const TEXT_DIM := Color(0.95, 0.95, 0.92, 0.5)
const RED := Color(0.9, 0.2, 0.15)
const GREEN := Color(0.45, 0.9, 0.4)
const BLUE := Color(0.4, 0.7, 1.0)


static func font() -> Font:
	return ThemeDB.fallback_font


## Panel with the top-left and bottom-right corners clipped.
static func panel(ci: CanvasItem, r: Rect2, fill := PANEL, cut := 10.0) -> void:
	ci.draw_colored_polygon(_clipped(r, cut), fill)


static func panel_outline(ci: CanvasItem, r: Rect2, col := YELLOW, cut := 10.0, width := 2.0) -> void:
	var pts := _clipped(r, cut)
	pts.append(pts[0])
	ci.draw_polyline(pts, col, width)


## Short yellow bar on the left edge of a panel (the HD2 "tab" accent).
static func accent(ci: CanvasItem, r: Rect2, col := YELLOW) -> void:
	ci.draw_rect(Rect2(r.position.x, r.position.y + 4, 4, r.size.y - 8), col)


static func text(ci: CanvasItem, pos: Vector2, s: String, size := 18, col := TEXT,
		align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	ci.draw_string(font(), pos, s.to_upper(), align, width, size, col)


## Segmented bar (health, progress).
static func bar(ci: CanvasItem, r: Rect2, frac: float, col: Color, segments := 0) -> void:
	ci.draw_rect(r, Color(0, 0, 0, 0.6))
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac, 0.0, 1.0), r.size.y)), col)
	for i in range(1, segments):
		var x := r.position.x + r.size.x * i / segments
		ci.draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color(0, 0, 0, 0.7), 2.0)
	ci.draw_rect(r, Color(1, 1, 1, 0.25), false, 1.0)


## Diamond marker (objectives).
static func diamond(ci: CanvasItem, c: Vector2, r: float, col: Color, filled := true) -> void:
	var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
	if filled:
		ci.draw_colored_polygon(pts, col)
	else:
		pts.append(pts[0])
		ci.draw_polyline(pts, col, 2.0)


## Big clipped button; returns its rect for hit testing.
static func button(ci: CanvasItem, r: Rect2, label: String, active := false, size := 24) -> Rect2:
	panel(ci, r, YELLOW if active else PANEL_SOLID, 12.0)
	panel_outline(ci, r, YELLOW, 12.0, 2.0)
	text(ci, Vector2(r.position.x, r.get_center().y + size * 0.35), label, size,
		Color(0.05, 0.05, 0.05) if active else YELLOW, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	return r


static func _clipped(r: Rect2, cut: float) -> PackedVector2Array:
	return PackedVector2Array([
		r.position + Vector2(cut, 0), Vector2(r.end.x, r.position.y),
		r.end - Vector2(0, cut), r.end - Vector2(cut, 0),
		Vector2(r.position.x, r.end.y), r.position + Vector2(0, cut),
	])
