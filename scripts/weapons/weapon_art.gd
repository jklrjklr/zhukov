class_name WeaponArt
## Top-down weapon silhouettes. Pointing up (-Y), origin at the pistol grip, 60 px = 1 m.

const OUTLINE := Color(0.06, 0.06, 0.07)


static func draw(ci: CanvasItem, model: String) -> void:
	match model:
		"smg5":
			_smg5(ci)
		_:
			_parts(ci, [[Rect2(-2.5, -30, 5, 40), Color(0.2, 0.2, 0.22)]])


## MP5A2-style, simplified: fixed stock, slim receiver, wider handguard,
## cocking lever on the left, drum rear sight, front sight hood, 3-lug barrel.
static func _smg5(ci: CanvasItem) -> void:
	var metal := Color(0.2, 0.2, 0.22)
	var poly := Color(0.13, 0.13, 0.14)
	_parts(ci, [
		[Rect2(-3.5, 8, 7, 2.5), poly], # butt pad
		[Rect2(-2.5, 1, 5, 8), poly], # stock
		[Rect2(-2.5, -20, 5, 22), metal], # receiver
		[Rect2(-3.5, -24, 7, 10), poly], # handguard
		[Rect2(-4.8, -22, 2, 3.5), metal], # cocking lever
		[Rect2(-1.6, -28, 3.2, 4), metal], # front sight hood
		[Rect2(-1, -31, 2, 3), Color(0.08, 0.08, 0.08)], # barrel / 3-lug
	])
	ci.draw_circle(Vector2(0, 0.5), 1.7, Color(0.32, 0.32, 0.34)) # drum sight
	ci.draw_line(Vector2(0, -2), Vector2(0, -19), Color(1, 1, 1, 0.08), 1.0) # top rib highlight


## Outlines first, then fills, so parts merge into one silhouette.
static func _parts(ci: CanvasItem, parts: Array) -> void:
	for p in parts:
		ci.draw_rect((p[0] as Rect2).grow(1.0), OUTLINE)
	for p in parts:
		ci.draw_rect(p[0], p[1])
