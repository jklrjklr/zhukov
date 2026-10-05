class_name RigArt
extends RefCounted
## Vector drawing helpers for baking rig part textures. Every draw callable of a part has the
## signature draw(ci: CanvasItem, t: Transform2D, mode: int) and paints the part around its own
## origin; `t` maps part-local art units to the canvas (the atlas baker or the corpse composite
## supplies it). Modes: NORMAL, WOUND (damaged variant), DEAD (corpse palette).

enum Mode { NORMAL, WOUND, DEAD }

const OUTLINE := Color(0.07, 0.05, 0.04)


## Ellipse as a scaled unit circle (no triangulation), with a dark outline.
static func ell(ci: CanvasItem, t: Transform2D, c: Vector2, r: Vector2, col: Color, outline := true, ow := 1.4) -> void:
	if outline:
		ci.draw_set_transform_matrix(t * Transform2D(Vector2(r.x + ow, 0), Vector2(0, r.y + ow), c))
		ci.draw_circle(Vector2.ZERO, 1.0, OUTLINE)
	ci.draw_set_transform_matrix(t * Transform2D(Vector2(r.x, 0), Vector2(0, r.y), c))
	ci.draw_circle(Vector2.ZERO, 1.0, col)
	ci.draw_set_transform_matrix(t)


## Round-capped segment with a dark outline.
static func limb(ci: CanvasItem, t: Transform2D, a: Vector2, b: Vector2, w: float, col: Color, ow := 1.7) -> void:
	ci.draw_set_transform_matrix(t)
	ci.draw_line(a, b, OUTLINE, w + ow * 2.0)
	ci.draw_circle(a, (w + ow * 2.0) * 0.5, OUTLINE)
	ci.draw_circle(b, (w + ow * 2.0) * 0.5, OUTLINE)
	ci.draw_line(a, b, col, w)
	ci.draw_circle(a, w * 0.5, col)
	ci.draw_circle(b, w * 0.5, col)


## Draw a whole rig definition as one static picture (corpse, decal): parts in order at their
## rest transforms, `overrides` {id: {pos, rot}} replacing some, everything in `mode`.
static func composite(ci: CanvasItem, t: Transform2D, parts: Array, overrides: Dictionary, mode: int) -> void:
	var world := {"": t}
	for p in parts:
		var pos: Vector2 = p.pos
		var rot: float = p.rot
		var o: Dictionary = overrides.get(p.id, {})
		if not o.is_empty():
			pos = o.get("pos", pos)
			rot = o.get("rot", rot)
		var xf: Transform2D = (world[p.parent] as Transform2D) * Transform2D(rot, pos)
		world[p.id] = xf
		if p.has("draw") and not p.get("skip_corpse", false):
			(p.draw as Callable).call(ci, xf, mode)
