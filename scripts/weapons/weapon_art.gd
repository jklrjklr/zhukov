class_name WeaponArt
## Top-down weapon silhouettes. Pointing up (-Y), origin at the pistol grip, 60 px = 1 m.

const OUTLINE := Color(0.06, 0.06, 0.07)


## bolt: px the cocking lever is pulled back (+Y).
static func draw(ci: CanvasItem, model: String, bolt := 0.0) -> void:
	match model:
		"smg5":
			_smg5(ci, bolt)
		"liberator":
			_liberator(ci, bolt)
		"eat17":
			_eat17(ci)
		_:
			_parts(ci, [[Rect2(-2.5, -30, 5, 40), Color(0.2, 0.2, 0.22)]])


## MP5A2-style, simplified: fixed stock, slim receiver, wider handguard,
## cocking lever on the left, drum rear sight, front sight hood, 3-lug barrel.
static func _smg5(ci: CanvasItem, bolt: float) -> void:
	var metal := Color(0.2, 0.2, 0.22)
	var poly := Color(0.13, 0.13, 0.14)
	_parts(ci, [
		[Rect2(-3.5, 8, 7, 2.5), poly], # butt pad
		[Rect2(-2.5, 1, 5, 8), poly], # stock
		[Rect2(-2.5, -20, 5, 22), metal], # receiver
		[Rect2(-3.5, -24, 7, 10), poly], # handguard
		[Rect2(-4.8, -22 + bolt, 2, 3.5), metal], # cocking lever
		[Rect2(-1.6, -28, 3.2, 4), metal], # front sight hood
		[Rect2(-1, -31, 2, 3), Color(0.08, 0.08, 0.08)], # barrel / 3-lug
	])
	ci.draw_circle(Vector2(0, 0.5), 1.7, Color(0.32, 0.32, 0.34)) # drum sight
	ci.draw_line(Vector2(0, -2), Vector2(0, -19), Color(1, 1, 1, 0.08), 1.0) # top rib highlight


## AR-23 Liberator: bullpup-ish rifle, carry rail with optic, chunky handguard, muzzle brake.
static func _liberator(ci: CanvasItem, bolt: float) -> void:
	var metal := Color(0.22, 0.23, 0.24)
	var poly := Color(0.14, 0.15, 0.15)
	_parts(ci, [
		[Rect2(-3.8, 10, 7.6, 3), poly], # butt pad
		[Rect2(-3, 1, 6, 10), poly], # stock
		[Rect2(-3, -26, 6, 28), metal], # receiver
		[Rect2(-4, -38, 8, 14), poly], # handguard
		[Rect2(-1.4, -44, 2.8, 6), Color(0.08, 0.08, 0.08)], # barrel
		[Rect2(-2.4, -46, 4.8, 3), metal], # muzzle brake
		[Rect2(3.0, -15 + bolt, 2.2, 3), metal], # charging handle (right)
	])
	ci.draw_rect(Rect2(-2, -21, 4, 11), Color(0.08, 0.08, 0.09)) # optic body
	ci.draw_circle(Vector2(0, -21), 1.6, Color(0.4, 0.7, 1.0, 0.8)) # lens
	ci.draw_rect(Rect2(-3, -6, 6, 2), Color(1.0, 0.9, 0.06, 0.8)) # Super Earth yellow band


## EAT-17: olive disposable launcher tube on the shoulder.
static func _eat17(ci: CanvasItem) -> void:
	var olive := Color(0.33, 0.37, 0.24)
	_parts(ci, [
		[Rect2(-5, -42, 10, 60), olive], # tube
		[Rect2(-6, -44, 12, 4), olive.darkened(0.3)], # front ring
		[Rect2(-6, 14, 12, 4), olive.darkened(0.3)], # rear ring
	])
	ci.draw_rect(Rect2(-5, -30, 10, 3), Color(1.0, 0.9, 0.06, 0.9)) # warning band
	ci.draw_rect(Rect2(5, -12, 3, 8), Color(0.12, 0.12, 0.12)) # sight


## Outlines first, then fills, so parts merge into one silhouette.
static func _parts(ci: CanvasItem, parts: Array) -> void:
	for p in parts:
		ci.draw_rect((p[0] as Rect2).grow(1.0), OUTLINE)
	for p in parts:
		ci.draw_rect(p[0], p[1])
