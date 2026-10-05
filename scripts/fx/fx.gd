class_name Fx
extends Node2D
## Central visual effects (graphics pass). One instance per scene, created lazily by the
## static helpers (Fx.explosion(self, ...)); gameplay code only calls the helpers.
## - Persistent decals (blood, pools, scorch, bile, casings, bullet pocks): ring buffer
##   capped at DECAL_CAP, the oldest ones fade out. Drawn by one canvas item that is only
##   re-recorded when a decal was added or is fading (never every frame).
## - Particles (dust, smoke, debris, sparks, flashes, shockwave rings): pooled dictionaries,
##   hard cap PARTICLE_CAP, drawn in two batched canvas items: LOW (under the sight
##   darkness: blood, dust, smoke) and HIGH (unshaded, glows through the dark: flashes,
##   sparks, rings).
## - Screen shake (small, capped, respects Game.shake_enabled) and optional hit-stop.

const DECAL_CAP := 300
const FADE_TIME := 4.0
const PARTICLE_CAP := 380
const SHAKE_MAX := 12.0
const PX := 60.0

const BLOOD_GREEN := Color(0.45, 0.62, 0.12)
const BLOOD_ORANGE := Color(0.88, 0.45, 0.1)
const BLOOD_SPITTER := Color(0.62, 0.85, 0.15)
const SPARK := Color(1.0, 0.85, 0.25)
const BRASS := Color(0.85, 0.65, 0.25)

enum P { DOT, SPARK, CHIP, RING, FLASH }

static var _inst: Fx

var _decal_node: Node2D
var _low: Node2D
var _high: Node2D
var _decals: Array[Dictionary] = []
var _live := 0
var _fading := 0
var _dirty := false
var _redraw_cd := 0.0
var _low_p: Array[Dictionary] = []
var _high_p: Array[Dictionary] = []
var _shake := 0.0
var _last_muzzle := -1.0
var _stop_active := false


# --- Instance / static API ---------------------------------------------------------

static func get_fx(from: Node) -> Fx:
	if is_instance_valid(_inst) and not _inst.is_queued_for_deletion():
		return _inst
	var tree := from.get_tree() if from != null else null
	if tree == null:
		return null
	var parent: Node = tree.current_scene if tree.current_scene != null else tree.root
	_inst = Fx.new()
	_inst.name = "Fx"
	parent.add_child.call_deferred(_inst)
	return _inst


## Drop the old instance (new mission / scene).
static func reset() -> void:
	if is_instance_valid(_inst):
		_inst.queue_free()
	_inst = null


## Direction on the canvas that points to the top of the screen (the camera rotates).
static func screen_up(n: CanvasItem) -> Vector2:
	var vp := n.get_viewport()
	if vp == null:
		return Vector2.UP
	return vp.get_canvas_transform().affine_inverse().basis_xform(Vector2.UP).normalized()


static func muzzle(from: Node, pos: Vector2, dir: Vector2) -> void:
	var f := get_fx(from)
	if f:
		f._muzzle(pos, dir)


## Bullet hit on world geometry / ground. kind: "dust", "rock", "metal".
static func impact(from: Node, pos: Vector2, dir: Vector2, kind := "dust") -> void:
	var f := get_fx(from)
	if f:
		f._impact(pos, dir, kind)


## Armor ricochet: yellow sparks.
static func spark(from: Node, pos: Vector2, dir: Vector2, count := 7) -> void:
	var f := get_fx(from)
	if f:
		f._spark(pos, dir, count)


## Flesh hit: goo spray plus a splat decal.
static func splat(from: Node, pos: Vector2, dir: Vector2, col: Color, big := false) -> void:
	var f := get_fx(from)
	if f:
		f._splat(pos, dir, col, big)


static func death(from: Node, pos: Vector2, col: Color, size: float) -> void:
	var f := get_fx(from)
	if f:
		f._death(pos, col, size)


static func explosion(from: Node, pos: Vector2, radius_px: float, player_pos := Vector2.INF) -> void:
	var f := get_fx(from)
	if f:
		f._explosion(pos, radius_px, player_pos)


## Hellpod / drop pod touching down: dust ring, debris, shake.
static func landing(from: Node, pos: Vector2, radius_px := 110.0) -> void:
	var f := get_fx(from)
	if f:
		f._landing(pos, radius_px)


static func casing(from: Node, pos: Vector2, rot: float) -> void:
	var f := get_fx(from)
	if f:
		f.add_decal("casing", pos, rot, 1.0, BRASS)


static func bile_pool(from: Node, pos: Vector2, radius: float) -> void:
	var f := get_fx(from)
	if f:
		f.add_decal("bile", pos, randf() * TAU, radius, Color(0.5, 0.7, 0.12))


static func bile_splash(from: Node, pos: Vector2) -> void:
	var f := get_fx(from)
	if f:
		f._bile_splash(pos)


static func dust_puff(from: Node, pos: Vector2, size := 1.0) -> void:
	var f := get_fx(from)
	if f:
		f._dust(pos, size)


## Persistent decal of any kind (blood, pool, scorch, bile, casing, pock).
static func decal(from: Node, kind: String, pos: Vector2, size: float, col: Color, dir := Vector2.ZERO) -> void:
	var f := get_fx(from)
	if f:
		f.add_decal(kind, pos, dir.angle() if dir != Vector2.ZERO else randf() * TAU, size, col)


static func shake(from: Node, amount: float) -> void:
	var f := get_fx(from)
	if f:
		f._add_shake(amount)


## Shake attenuated by the distance to the player (full inside `range_px / 3`).
static func shake_at(from: Node, pos: Vector2, amount: float, range_px := 1500.0) -> void:
	var f := get_fx(from)
	if f == null:
		return
	var pl := from.get_tree().get_first_node_in_group("player") as Node2D
	if pl == null:
		return
	var k := 1.0 - clampf((pl.global_position.distance_to(pos) - range_px / 3.0) / (range_px * 0.667), 0.0, 1.0)
	f._add_shake(amount * k)


## Brief slow-motion on big hits (skipped headless / when effects are off).
static func hit_stop(from: Node, seconds := 0.05) -> void:
	var f := get_fx(from)
	if f:
		f._hit_stop(seconds)


## Pod / hellpod dropping from above (draw helper for any canvas item): fire trail + hull.
static func draw_pod(ci: CanvasItem, pos: Vector2, up: Vector2, k: float, height: float, size: float) -> void:
	var top := pos + up * (height * (1.0 - k))
	var side := up.orthogonal()
	var pts := PackedVector2Array([top + side * size * 0.8, top - side * size * 0.8, top - side * 3.0 + up * 190.0, top + side * 3.0 + up * 190.0])
	var cols := PackedColorArray([Color(1, 0.7, 0.25, 0.85), Color(1, 0.7, 0.25, 0.85), Color(1, 0.35, 0.1, 0.0), Color(1, 0.35, 0.1, 0.0)])
	ci.draw_polygon(pts, cols)
	ci.draw_circle(top, size + 2.0, Color(0.08, 0.08, 0.08))
	ci.draw_circle(top, size, Color(0.3, 0.31, 0.34))
	ci.draw_circle(top - up * 3.0, size * 0.55, Color(0.55, 0.56, 0.6))
	ci.draw_circle(top, size * 0.35, UiStyle.YELLOW)
	for i in 4:
		var a := TAU * i / 4.0 + PI / 4.0
		ci.draw_line(top, top + Vector2.from_angle(a) * size * 1.5, Color(0.1, 0.1, 0.1), 3.0)


static func decal_count() -> int:
	return _inst._live if is_instance_valid(_inst) else 0


static func particle_count() -> int:
	return (_inst._low_p.size() + _inst._high_p.size()) if is_instance_valid(_inst) else 0


# --- Setup --------------------------------------------------------------------------

func _init() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_decal_node = _layer(-8, false)
	_decal_node.draw.connect(_draw_decals)
	_low = _layer(9, false)
	_low.draw.connect(_draw_low)
	_high = _layer(13, true)
	_high.draw.connect(_draw_high)


func _layer(z: int, unshaded: bool) -> Node2D:
	var n := Node2D.new()
	n.z_index = z
	n.z_as_relative = false
	if unshaded:
		var m := CanvasItemMaterial.new()
		m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		n.material = m
	add_child(n)
	return n


# --- Decals -------------------------------------------------------------------------

func add_decal(kind: String, pos: Vector2, rot: float, size: float, col: Color) -> void:
	var blobs := PackedVector3Array()
	var dir := Vector2.from_angle(rot)
	var side := dir.orthogonal()
	var hl := PackedVector3Array()
	match kind:
		"blood":
			blobs.append(Vector3(pos.x, pos.y, size * randf_range(0.5, 0.75)))
			for i in randi_range(4, 7):
				var q := pos + dir * randf_range(0.4, 2.4) * size + side * randf_range(-1.0, 1.0) * size
				blobs.append(Vector3(q.x, q.y, size * randf_range(0.1, 0.38)))
		"pool":
			for i in 6:
				var q := pos + Vector2.from_angle(randf() * TAU) * randf_range(0.0, 0.55) * size
				blobs.append(Vector3(q.x, q.y, size * randf_range(0.45, 0.8)))
			for i in 3:
				var q := pos + Vector2.from_angle(randf() * TAU) * randf_range(0.0, 0.3) * size
				hl.append(Vector3(q.x - size * 0.12, q.y - size * 0.12, size * randf_range(0.12, 0.25)))
			for i in 4:
				var q := pos + Vector2.from_angle(randf() * TAU) * randf_range(1.0, 1.5) * size
				blobs.append(Vector3(q.x, q.y, size * randf_range(0.08, 0.2)))
		"scorch":
			blobs.append(Vector3(pos.x, pos.y, size * 0.9))
			for i in 9:
				var q := pos + Vector2.from_angle(randf() * TAU) * randf_range(0.3, 1.0) * size
				blobs.append(Vector3(q.x, q.y, size * randf_range(0.2, 0.5)))
			for i in 4:
				hl.append(Vector3(pos.x + randf_range(-0.3, 0.3) * size, pos.y + randf_range(-0.3, 0.3) * size, size * randf_range(0.2, 0.4)))
		"bile":
			for i in 6:
				var q := pos + Vector2.from_angle(randf() * TAU) * randf_range(0.0, 0.5) * size
				blobs.append(Vector3(q.x, q.y, size * randf_range(0.35, 0.6)))
			for i in 5:
				var q := pos + Vector2.from_angle(randf() * TAU) * randf_range(0.0, 0.7) * size
				hl.append(Vector3(q.x, q.y, size * randf_range(0.04, 0.09)))
		"pock":
			blobs.append(Vector3(pos.x, pos.y, size))
			for i in 4:
				var q := pos + Vector2.from_angle(randf() * TAU) * size * randf_range(1.5, 2.8)
				hl.append(Vector3(q.x, q.y, 0.7))
		"casing":
			pass
	_decals.append({"k": kind, "p": pos, "r": rot, "s": size, "c": col, "b": blobs, "h": hl, "f": -1.0})
	_live += 1
	if _live > DECAL_CAP:
		for d in _decals:
			if (d.f as float) < 0.0:
				d.f = 0.0
				_live -= 1
				_fading += 1
				break
	_dirty = true


func _update_decals(delta: float) -> void:
	if _fading > 0:
		var gone := false
		for d in _decals:
			var f: float = d.f
			if f >= 0.0:
				d.f = f + delta
				if f + delta >= FADE_TIME:
					gone = true
		if gone:
			_decals = _decals.filter(func(d): return (d.f as float) < FADE_TIME)
			_fading = _decals.size() - _live
		_dirty = true
	_redraw_cd -= delta
	if _dirty and _redraw_cd <= 0.0:
		_dirty = false
		_redraw_cd = 0.1
		_decal_node.queue_redraw()


func _draw_decals() -> void:
	var n := _decal_node
	for d in _decals:
		var a := 1.0
		var f: float = d.f
		if f >= 0.0:
			a = 1.0 - f / FADE_TIME
		var col: Color = d.c
		var s: float = d.s
		var p: Vector2 = d.p
		var blobs: PackedVector3Array = d.b
		var hl: PackedVector3Array = d.h
		match d.k:
			"blood":
				col.a = 0.72 * a
				for b in blobs:
					n.draw_circle(Vector2(b.x, b.y), b.z, col)
			"pool":
				col.a = 0.82 * a
				for b in blobs:
					n.draw_circle(Vector2(b.x, b.y), b.z, col.darkened(0.15))
				var lc := col.lightened(0.25)
				lc.a = 0.55 * a
				for b in hl:
					n.draw_circle(Vector2(b.x, b.y), b.z, lc)
			"scorch":
				for b in blobs:
					n.draw_circle(Vector2(b.x, b.y), b.z, Color(0.03, 0.025, 0.02, 0.2 * a))
				for b in hl:
					n.draw_circle(Vector2(b.x, b.y), b.z, Color(0.0, 0.0, 0.0, 0.25 * a))
			"bile":
				col.a = 0.6 * a
				for b in blobs:
					n.draw_circle(Vector2(b.x, b.y), b.z, col.darkened(0.2))
				for b in hl:
					n.draw_circle(Vector2(b.x, b.y), b.z, Color(0.85, 1.0, 0.4, 0.7 * a))
			"pock":
				n.draw_circle(p, s, Color(0.04, 0.035, 0.03, 0.55 * a))
				for b in hl:
					n.draw_circle(Vector2(b.x, b.y), b.z, Color(0.1, 0.09, 0.08, 0.5 * a))
			"casing":
				var dir := Vector2.from_angle(d.r)
				col.a = a
				n.draw_line(p - dir * 2.4, p + dir * 2.4, Color(0.08, 0.06, 0.03, 0.6 * a), 3.6)
				n.draw_line(p - dir * 2.0, p + dir * 2.0, col, 2.2)
				n.draw_circle(p + dir * 2.0, 0.9, col.lightened(0.4))


# --- Particles ----------------------------------------------------------------------

func _spawn(high: bool, d: Dictionary) -> void:
	var arr: Array[Dictionary] = _high_p if high else _low_p
	if _low_p.size() + _high_p.size() >= PARTICLE_CAP:
		if high or arr.is_empty():
			return
		arr.remove_at(0) # keep the newest
	d.t = 0.0
	arr.append(d)


func _dot(high: bool, pos: Vector2, vel: Vector2, life: float, s0: float, s1: float, col: Color, drag := 3.0, soft := false) -> void:
	_spawn(high, {"k": P.DOT, "p": pos, "v": vel, "life": life, "s0": s0, "s1": s1, "c": col, "drag": drag, "soft": soft})


func _streak(pos: Vector2, vel: Vector2, life: float, length: float, width: float, col: Color) -> void:
	_spawn(true, {"k": P.SPARK, "p": pos, "v": vel, "life": life, "s0": length, "s1": width, "c": col, "drag": 2.5})


func _chip(high: bool, pos: Vector2, vel: Vector2, life: float, size: Vector2, col: Color) -> void:
	_spawn(high, {"k": P.CHIP, "p": pos, "v": vel, "life": life, "s0": size.x, "s1": size.y, "c": col,
		"drag": 4.0, "rot": randf() * TAU, "spin": randf_range(-12.0, 12.0)})


func _ring(high: bool, pos: Vector2, r0: float, r1: float, life: float, width: float, col: Color) -> void:
	_spawn(high, {"k": P.RING, "p": pos, "v": Vector2.ZERO, "life": life, "s0": r0, "s1": r1, "w": width, "c": col, "drag": 0.0})


func _flash(pos: Vector2, r: float, life: float, col: Color) -> void:
	_spawn(true, {"k": P.FLASH, "p": pos, "v": Vector2.ZERO, "life": life, "s0": r * 0.5, "s1": r, "c": col, "drag": 0.0})


func _update_particles(arr: Array[Dictionary], delta: float) -> void:
	var i := arr.size() - 1
	while i >= 0:
		var q: Dictionary = arr[i]
		var t: float = q.t + delta
		q.t = t
		if t >= (q.life as float):
			arr[i] = arr[arr.size() - 1]
			arr.pop_back()
		else:
			var v: Vector2 = q.v
			var drag: float = q.drag
			if drag > 0.0:
				v *= exp(-drag * delta)
				q.v = v
			q.p = (q.p as Vector2) + v * delta
			if q.has("spin"):
				q.rot = (q.rot as float) + (q.spin as float) * delta
		i -= 1


func _draw_particles(n: Node2D, arr: Array[Dictionary]) -> void:
	for q in arr:
		var k: float = (q.t as float) / (q.life as float)
		var col: Color = q.c
		var p: Vector2 = q.p
		var s0: float = q.s0
		var s1: float = q.s1
		match q.k:
			P.DOT:
				col.a *= 1.0 - k
				var rr := lerpf(s0, s1, k)
				if q.get("soft", false):
					n.draw_texture_rect(Zone.soft_texture(), Rect2(p - Vector2(rr, rr), Vector2(rr, rr) * 2.0), false, col)
				else:
					n.draw_circle(p, rr, col)
			P.SPARK:
				var v: Vector2 = q.v
				col.a *= 1.0 - k
				n.draw_line(p, p - v.normalized() * s0 * (1.0 - k * 0.6), col, s1)
			P.CHIP:
				col.a *= 1.0 - k * k
				n.draw_set_transform(p, q.rot)
				n.draw_rect(Rect2(-s0 * 0.5, -s1 * 0.5, s0, s1), col)
				n.draw_set_transform(Vector2.ZERO)
			P.RING:
				var e := 1.0 - pow(1.0 - k, 3.0)
				col.a *= 1.0 - k
				n.draw_arc(p, lerpf(s0, s1, e), 0.0, TAU, 40, col, maxf((q.w as float) * (1.0 - k * 0.7), 1.0))
			P.FLASH:
				col.a *= 1.0 - k
				var r := lerpf(s0, s1, sqrt(k))
				n.draw_circle(p, r, col)
				var c2 := Color(1, 1, 0.9, col.a)
				n.draw_circle(p, r * 0.5, c2)


func _draw_low() -> void:
	_draw_particles(_low, _low_p)


func _draw_high() -> void:
	_draw_particles(_high, _high_p)


# --- Effect recipes -----------------------------------------------------------------

func _muzzle(pos: Vector2, dir: Vector2) -> void:
	var now := Time.get_ticks_msec() * 0.001
	if now - _last_muzzle < 0.02:
		return
	_last_muzzle = now
	_flash(pos + dir * 8.0, 26.0, 0.06, Color(1.0, 0.8, 0.35, 0.5))
	for i in 2:
		_streak(pos, dir.rotated(randf_range(-0.35, 0.35)) * randf_range(500, 900), 0.07, 14.0, 1.6, Color(1, 0.85, 0.4, 0.9))
	_dot(false, pos + dir * 6.0, dir * randf_range(30, 70) + Vector2(randf_range(-15, 15), randf_range(-15, 15)), 0.45, 4.0, 11.0, Color(0.7, 0.7, 0.68, 0.3), 3.0, true)


func _impact(pos: Vector2, dir: Vector2, kind: String) -> void:
	var back := -dir.normalized()
	match kind:
		"metal":
			_spark(pos, dir, 4)
		"rock":
			for i in 3:
				_chip(false, pos, back.rotated(randf_range(-1.2, 1.2)) * randf_range(80, 200), 0.4, Vector2(2.5, 1.8), Color(0.5, 0.47, 0.42))
			_streak(pos, back.rotated(randf_range(-0.9, 0.9)) * 380.0, 0.12, 9.0, 1.4, Color(1, 0.9, 0.55, 0.9))
		_:
			pass
	_dust(pos, 0.5)
	if randf() < 0.55:
		add_decal("pock", pos, 0.0, randf_range(1.6, 2.6), Color.BLACK)


func _spark(pos: Vector2, dir: Vector2, count: int) -> void:
	var back := -dir.normalized()
	_flash(pos, 11.0, 0.07, Color(1.0, 0.9, 0.4, 0.8))
	for i in count:
		var a := back.rotated(randf_range(-1.1, 1.1))
		_streak(pos, a * randf_range(200, 520), randf_range(0.1, 0.22), randf_range(8, 16), 1.8, SPARK)


func _splat(pos: Vector2, dir: Vector2, col: Color, big: bool) -> void:
	var fwd := dir.normalized()
	for i in (7 if big else 4):
		var c := col.lerp(Color.WHITE, randf_range(0.0, 0.15))
		c.a = 0.85
		_dot(false, pos, fwd.rotated(randf_range(-0.7, 0.7)) * randf_range(70, 260), randf_range(0.2, 0.45),
			randf_range(1.5, 3.2), 0.6, c, 5.0)
	add_decal("blood", pos + fwd * 8.0, fwd.angle(), randf_range(2.2, 4.0) * (1.6 if big else 1.0), col)


func _death(pos: Vector2, col: Color, size: float) -> void:
	add_decal("pool", pos, 0.0, size, col)
	for i in 9:
		var c := col
		c.a = 0.9
		_dot(false, pos, Vector2.from_angle(randf() * TAU) * randf_range(60, 200), randf_range(0.3, 0.6), randf_range(2.0, 4.5), 0.8, c, 5.0)
	for i in 3:
		_chip(false, pos, Vector2.from_angle(randf() * TAU) * randf_range(60, 150), 0.7,
			Vector2(randf_range(3, 6), randf_range(2, 3)), col.darkened(0.35))


func _dust(pos: Vector2, size: float) -> void:
	for i in 2:
		_dot(false, pos, Vector2.from_angle(randf() * TAU) * randf_range(10, 40) * size, randf_range(0.35, 0.6),
			6.0 * size, 16.0 * size, Color(0.62, 0.55, 0.42, 0.5), 2.5, true)


func _bile_splash(pos: Vector2) -> void:
	for i in 12:
		_dot(false, pos, Vector2.from_angle(randf() * TAU) * randf_range(60, 220), randf_range(0.3, 0.6),
			randf_range(2.0, 4.5), 1.0, Color(0.7, 0.95, 0.2, 0.85), 4.0)
	_ring(false, pos, 8.0, 90.0, 0.4, 4.0, Color(0.7, 0.95, 0.2, 0.7))


func _explosion(pos: Vector2, r: float, player_pos: Vector2) -> void:
	var big := r > 4.0 * PX
	_flash(pos, r * 0.9, 0.16, Color(1.0, 0.75, 0.3, 0.75))
	_flash(pos, r * 0.45, 0.1, Color(1.0, 0.95, 0.8, 0.9))
	# Fireball: orange blobs that expand and cool.
	for i in (12 if big else 7):
		var d := Vector2.from_angle(randf() * TAU) * randf_range(0.0, r * 0.55)
		_dot(true, pos + d, d * 1.6, randf_range(0.25, 0.5), r * 0.22, r * 0.38,
			Color(1.0, randf_range(0.4, 0.65), 0.1, 0.8), 2.0, true)
	_ring(true, pos, r * 0.2, r * 1.15, 0.4, 5.0 if big else 3.0, Color(1, 0.92, 0.7, 0.8))
	if big:
		_ring(true, pos, r * 0.1, r * 0.8, 0.55, 3.0, Color(1, 0.7, 0.3, 0.5))
	# Debris and sparks.
	for i in (22 if big else 12):
		var dir := Vector2.from_angle(randf() * TAU)
		_streak(pos, dir * randf_range(250, 700) * clampf(r / 150.0, 0.7, 2.0), randf_range(0.2, 0.5),
			randf_range(10, 22), 2.0, Color(1, randf_range(0.6, 0.9), 0.3))
	for i in (14 if big else 8):
		var dir := Vector2.from_angle(randf() * TAU)
		_chip(false, pos, dir * randf_range(100, 420) * clampf(r / 150.0, 0.7, 1.8), randf_range(0.6, 1.4),
			Vector2(randf_range(3, 8), randf_range(2, 4)), Color(0.28, 0.24, 0.2).lerp(Color(0.5, 0.42, 0.3), randf()))
	# Smoke puffs, long lived.
	for i in (9 if big else 5):
		var d := Vector2.from_angle(randf() * TAU) * randf_range(0.0, r * 0.5)
		var g := randf_range(0.18, 0.3)
		_dot(false, pos + d, d * 0.5 + Vector2(randf_range(-12, 12), randf_range(-12, 12)), randf_range(1.0, 2.0),
			r * 0.3, r * 0.7, Color(g, g, g * 0.95, 0.55), 1.2, true)
	add_decal("scorch", pos, 0.0, r * 0.4, Color.BLACK)
	var strength := clampf(r / PX * 1.1, 2.0, SHAKE_MAX)
	if player_pos != Vector2.INF:
		var k := 1.0 - clampf((player_pos.distance_to(pos) - r) / (900.0), 0.0, 1.0)
		strength *= k
	_add_shake(strength)
	if big and strength > 7.0:
		_hit_stop(0.06)


func _landing(pos: Vector2, r: float) -> void:
	_ring(false, pos, r * 0.2, r * 1.6, 0.8, 10.0, Color(0.62, 0.55, 0.42, 0.7))
	_ring(true, pos, r * 0.1, r * 1.0, 0.35, 3.0, Color(1, 0.85, 0.5, 0.7))
	_flash(pos, r * 0.7, 0.14, Color(1.0, 0.85, 0.5, 0.6))
	for i in 14:
		var a := randf() * TAU
		_dot(false, pos + Vector2.from_angle(a) * r * 0.3, Vector2.from_angle(a) * randf_range(120, 260), randf_range(0.7, 1.3),
			14.0, 34.0, Color(0.6, 0.53, 0.4, 0.55), 2.5, true)
	for i in 10:
		_chip(false, pos, Vector2.from_angle(randf() * TAU) * randf_range(120, 380), 1.0,
			Vector2(randf_range(3, 7), randf_range(2, 4)), Color(0.4, 0.35, 0.28))
	add_decal("scorch", pos, 0.0, r * 0.45, Color.BLACK)
	_add_shake(6.0)


# --- Shake / hit-stop ---------------------------------------------------------------

func _add_shake(amount: float) -> void:
	if not Game.shake_enabled:
		return
	_shake = minf(_shake + amount, SHAKE_MAX)


func _hit_stop(seconds: float) -> void:
	if not Game.shake_enabled or _stop_active or DisplayServer.get_name() == "headless" or not is_inside_tree():
		return
	_stop_active = true
	Engine.time_scale = 0.1
	var t := get_tree().create_timer(seconds, true, false, true)
	t.timeout.connect(func():
		Engine.time_scale = 1.0
		_stop_active = false)


func _process(delta: float) -> void:
	_update_particles(_low_p, delta)
	_update_particles(_high_p, delta)
	if not _low_p.is_empty() or _low.get_meta("had", false):
		_low.queue_redraw()
		_low.set_meta("had", not _low_p.is_empty())
	if not _high_p.is_empty() or _high.get_meta("had", false):
		_high.queue_redraw()
		_high.set_meta("had", not _high_p.is_empty())
	_update_decals(delta)
	var cam := get_viewport().get_camera_2d()
	if cam:
		if _shake > 0.05:
			cam.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
			_shake = maxf(_shake - (4.0 + _shake * 4.0) * delta, 0.0)
		elif cam.offset != Vector2.ZERO:
			cam.offset = Vector2.ZERO
