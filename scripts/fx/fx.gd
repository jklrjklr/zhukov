class_name Fx
extends Node2D
## Central visual effects (graphics pass). One instance per scene, created lazily by the
## static helpers (Fx.explosion(self, ...)); gameplay code only calls the helpers.
## - Persistent decals (blood, pools, scorch, bile, casings, bullet pocks, baked corpses): kept in
##   CELL x CELL px cells, each rendered INTO A TEXTURE (SubViewport, premultiplied) that new decals
##   are blitted into incrementally; fading / expired decals rebuild their cell (rate limited, fade in
##   FADE_STEPS steps). The cost on screen is one draw call per visible cell, not one per blob.
## - Particles (dust, smoke, debris, sparks, flashes, shockwave rings): pooled dictionaries,
##   hard cap PARTICLE_CAP, drawn through two ShapeBatch MultiMeshes (one draw call each): LOW (under
##   the sight darkness: blood, dust, smoke) and HIGH (unshaded, glows through the dark: flashes,
##   sparks, rings).
## - Screen shake (small, capped, respects Game.shake_enabled) and optional hit-stop.

const DECAL_CAP := 300
const CORPSE_CAP := 24
const FADE_TIME := 4.0
const FADE_STEPS := 3
## Decal cells: world px per cell, texels per px, and the extra texels around a cell.
const CELL := 1024.0
const DECAL_SCALE := 0.6
const CELL_MARGIN := 8.0
const CELL_JOBS := 2
const REBUILD_COOLDOWN := 0.6
const PARTICLE_CAP := 380
const SHAKE_MAX := 12.0
const PX := 60.0
## Sizes of dots / streaks / chips / decals are drawn VISUAL_SCALE bigger (blast radii stay).
const K := Vis.VISUAL_SCALE

const BLOOD_GREEN := Color(0.45, 0.62, 0.12)
const BLOOD_ORANGE := Color(0.88, 0.45, 0.1)
const BLOOD_SPITTER := Color(0.62, 0.85, 0.15)
const SPARK := Color(1.0, 0.85, 0.25)
const BRASS := Color(0.85, 0.65, 0.25)

enum P { DOT, SPARK, CHIP, RING, FLASH }

static var _inst: Fx

var _cells := {} # Vector2i -> {vp, sprite, painter, items: Array, pending: Array, job: Array, rebuild: bool, last: float, v: Vector2i}
var _low: ShapeBatch
var _high: ShapeBatch
var _decals: Array[Dictionary] = [] # creation order, live ones only (fading ones move to _fade)
var _fade: Array[Dictionary] = []
var _live := 0
var _live_corpses := 0
var _recent_blood: Array = [] # [pos, msec] of the latest blood decals (merged when stacked)
var _blit_mat: CanvasItemMaterial
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


## A dead enemy's baked picture (RigAtlas entry key, the rig's world transform, world extent in px).
static func corpse(from: Node, key: String, xf: Transform2D, extent: float) -> void:
	var f := get_fx(from)
	if f:
		f.add_corpse(key, xf, extent)


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


## Pod / hellpod coming down (draw helper for any canvas item), top-down depth effect at the
## landing spot: starts ~4x its ground size and semi-transparent with a fire-trail glow ring,
## shrinks to `size` as k goes 0 -> 1 (the caller draws the darkening ground marker).
## `up` / `height` are unused (kept for the old falling-from-the-sky callers).
static func draw_pod(ci: CanvasItem, pos: Vector2, _up: Vector2, k: float, _height: float, size: float) -> void:
	k = clampf(k, 0.0, 1.0)
	var sc := 1.0 + 3.0 * (1.0 - k) # 4x -> 1x
	var a := 0.4 + 0.6 * k
	var r := size * sc
	# Fire-trail glow: soft halo plus a hot ring that tightens onto the hull.
	var hot := 1.0 - k * 0.6
	ci.draw_circle(pos, r * 1.7, Color(1, 0.4, 0.1, 0.10 * hot))
	ci.draw_circle(pos, r * 1.3, Color(1, 0.6, 0.2, 0.18 * hot))
	ci.draw_arc(pos, r * 1.25, 0.0, TAU, 40, Color(1, 0.75, 0.3, 0.8 * hot), maxf(r * 0.22, 3.0))
	ci.draw_arc(pos, r * 1.05, 0.0, TAU, 40, Color(1, 0.95, 0.7, 0.6 * hot), maxf(r * 0.08, 1.5))
	ci.draw_circle(pos, r + 2.0 * sc, Color(0.08, 0.08, 0.08, a))
	ci.draw_circle(pos, r, Color(0.3, 0.31, 0.34, a))
	ci.draw_circle(pos, r * 0.55, Color(0.55, 0.56, 0.6, a))
	ci.draw_circle(pos, r * 0.35, Color(UiStyle.YELLOW, a))
	for i in 4:
		var ang := TAU * i / 4.0 + PI / 4.0
		ci.draw_line(pos, pos + Vector2.from_angle(ang) * r * 1.5, Color(0.1, 0.1, 0.1, a), 3.0 * sc)


static func decal_count() -> int:
	return _inst._live if is_instance_valid(_inst) else 0


static func corpse_count() -> int:
	return _inst._live_corpses if is_instance_valid(_inst) else 0


static func particle_count() -> int:
	return (_inst._low_p.size() + _inst._high_p.size()) if is_instance_valid(_inst) else 0


# --- Setup --------------------------------------------------------------------------

func _init() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_low = ShapeBatch.new(PARTICLE_CAP, false)
	_low.z_index = 9
	_low.z_as_relative = false
	add_child(_low)
	_high = ShapeBatch.new(PARTICLE_CAP, true)
	_high.z_index = 13
	_high.z_as_relative = false
	add_child(_high)
	_blit_mat = CanvasItemMaterial.new()
	_blit_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA


# --- Decals -------------------------------------------------------------------------

static func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL)), int(floor(p.y / CELL)))


## World bounds of what a decal draws (everything grows by K about the decal's point).
func _decal_bb(d: Dictionary) -> Rect2:
	var p: Vector2 = d.p
	var s: float = d.s
	var r := 12.0
	match d.k:
		"blood":
			r = 3.8 * s
		"pool":
			r = 1.9 * s
		"scorch":
			r = 1.6 * s
		"bile":
			r = 1.3 * s
		"pock":
			r = 3.2 * s + 2.0
		"casing":
			r = 6.0
		"corpse":
			r = d.r
	if d.k == "corpse":
		return Rect2(p, Vector2.ZERO).grow(r + 4.0)
	return Rect2(p, Vector2.ZERO).grow(r * K + 4.0)


func _get_cell(v: Vector2i) -> Dictionary:
	if _cells.has(v):
		return _cells[v]
	var px := int(ceil((CELL + CELL_MARGIN * 2.0) * DECAL_SCALE))
	var s := float(px) / (CELL + CELL_MARGIN * 2.0)
	var origin := Vector2(v) * CELL - Vector2(CELL_MARGIN, CELL_MARGIN)
	var vp := SubViewport.new()
	vp.size = Vector2i(px, px)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var xf := Transform2D(Vector2(s, 0), Vector2(0, s), -origin * s)
	vp.tree_entered.connect(func() -> void: vp.canvas_transform = xf) # needs the viewport's canvas, i.e. in the tree
	add_child(vp)
	var painter := Node2D.new()
	vp.add_child(painter)
	var sprite := Sprite2D.new()
	sprite.name = "Decal%d_%d" % [v.x, v.y]
	sprite.centered = false
	sprite.position = origin
	sprite.scale = Vector2.ONE / s
	sprite.texture = vp.get_texture()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.material = _blit_mat
	sprite.z_index = -8
	sprite.z_as_relative = false
	add_child(sprite)
	var cell := {"vp": vp, "sprite": sprite, "painter": painter, "items": [], "pending": [], "job": [], "rebuild": true,
		"last": -10.0, "v": v}
	painter.draw.connect(func() -> void:
		for d in cell.job:
			_draw_decal(painter, d))
	_cells[v] = cell
	return cell


func _file_decal(d: Dictionary) -> void:
	var bb := _decal_bb(d)
	var c0 := _cell_of(bb.position)
	var c1 := _cell_of(bb.end)
	var cl: Array[Vector2i] = []
	for y in range(c0.y, c1.y + 1):
		for x in range(c0.x, c1.x + 1):
			var cell := _get_cell(Vector2i(x, y))
			(cell.items as Array).append(d)
			(cell.pending as Array).append(d)
			cl.append(Vector2i(x, y))
	d["cells"] = cl


func _unfile_decal(d: Dictionary) -> void:
	for v: Vector2i in d.cells:
		if _cells.has(v):
			var cell: Dictionary = _cells[v]
			(cell.items as Array).erase(d)
			cell.rebuild = true


func _touch_cells(d: Dictionary) -> void:
	for v: Vector2i in d.cells:
		if _cells.has(v):
			_cells[v].rebuild = true


func add_decal(kind: String, pos: Vector2, rot: float, size: float, col: Color) -> void:
	if kind == "blood":
		# Stacked hits (an automatic weapon / the sentry on one bug) leave one stain, not twenty.
		var now := Time.get_ticks_msec()
		for r in _recent_blood:
			if now - (r[1] as int) < 600 and (r[0] as Vector2).distance_squared_to(pos) < 16.0 * 16.0:
				return
		_recent_blood.append([pos, now])
		if _recent_blood.size() > 6:
			_recent_blood.pop_front()
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
	var d := {"k": kind, "p": pos, "r": rot, "s": size, "c": col, "b": blobs, "h": hl, "f": -1.0, "step": 0}
	_decals.append(d)
	_file_decal(d)
	_live += 1
	if _live > DECAL_CAP:
		for o in _decals:
			if o.k != "corpse":
				_start_fade(o)
				break


## A dead enemy's static corpse picture (RigAtlas entry `key`, drawn with the rig's final transform).
func add_corpse(key: String, xf: Transform2D, extent: float) -> void:
	var d := {"k": "corpse", "p": xf.origin, "r": extent, "s": 1.0, "c": Color.WHITE, "b": PackedVector3Array(), "h": PackedVector3Array(),
		"f": -1.0, "step": 0, "key": key, "xf": xf}
	_decals.append(d)
	_file_decal(d)
	_live_corpses += 1
	if _live_corpses > CORPSE_CAP:
		for o in _decals:
			if o.k == "corpse":
				_start_fade(o)
				break


func _start_fade(d: Dictionary) -> void:
	_decals.erase(d)
	d.f = 0.0
	_fade.append(d)
	if d.k == "corpse":
		_live_corpses -= 1
	else:
		_live -= 1


func _update_decals(delta: float) -> void:
	if not _fade.is_empty():
		var step_t := FADE_TIME / FADE_STEPS
		var gone: Array[Dictionary] = []
		for d in _fade:
			d.f = (d.f as float) + delta
			var st := int((d.f as float) / step_t)
			if st != d.step:
				d.step = st
				if st >= FADE_STEPS:
					gone.append(d)
				else:
					_touch_cells(d)
		for d in gone:
			_fade.erase(d)
			_unfile_decal(d)
	_flush_cells()


func _flush_cells() -> void:
	var now := Time.get_ticks_msec() * 0.001
	var jobs := 0
	var dead: Array[Vector2i] = []
	for v in _cells:
		var cell: Dictionary = _cells[v]
		if (cell.items as Array).is_empty():
			dead.append(v)
			continue
		if jobs >= CELL_JOBS:
			continue
		var vp: SubViewport = cell.vp
		var do_rebuild: bool = cell.rebuild and now - (cell.last as float) >= REBUILD_COOLDOWN
		if not do_rebuild and (cell.pending as Array).is_empty():
			continue
		var list: Array = cell.items if do_rebuild else cell.pending
		if not RigAtlas.baked:
			var wait := false
			for d in list:
				if d.k == "corpse":
					wait = true
					break
			if wait:
				continue
		cell.job = list.duplicate()
		(cell.pending as Array).clear()
		if do_rebuild:
			cell.rebuild = false
			cell.last = now
			vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
		else:
			vp.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		(cell.painter as Node2D).queue_redraw()
		jobs += 1
	for v in dead:
		var cell: Dictionary = _cells[v]
		_cells.erase(v)
		(cell.sprite as Node).queue_free()
		(cell.vp as Node).queue_free()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED:
		for v in _cells:
			_cells[v].rebuild = true
			_cells[v].last = -10.0


static var _disc: ImageTexture


## 64 px anti-aliased white disc: decal blobs are textured rects (they batch; draw_circle polygons do not).
static func disc_texture() -> ImageTexture:
	if _disc == null:
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			for x in 64:
				var d := Vector2(x + 0.5 - 32.0, y + 0.5 - 32.0).length() / 32.0
				img.set_pixel(x, y, Color(1, 1, 1, clampf((1.0 - d) * 32.0 * 0.5 + 0.5, 0.0, 1.0)))
		_disc = ImageTexture.create_from_image(img)
	return _disc


static func _blob(n: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	n.draw_texture_rect(disc_texture(), Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false, col)


func _draw_decal(n: Node2D, d: Dictionary) -> void:
	var a := 1.0 - float(d.step) / FADE_STEPS
	var col: Color = d.c
	var p: Vector2 = d.p
	if d.k == "corpse":
		var e := RigAtlas.entry(d.key)
		var xf: Transform2D = d.xf
		n.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		n.draw_set_transform_matrix(xf)
		var r := Rect2(e.rect)
		n.draw_texture_rect_region(RigAtlas.texture(), Rect2((e.bounds as Rect2).position * RigAtlas.SS, r.size), r, Color(1, 1, 1, a))
		return
	n.draw_set_transform(p * (1.0 - K), 0.0, Vector2(K, K))
	var blobs: PackedVector3Array = d.b
	var hl: PackedVector3Array = d.h
	match d.k:
		"blood":
			col.a = 0.72 * a
			for b in blobs:
				_blob(n, Vector2(b.x, b.y), b.z, col)
		"pool":
			col.a = 0.82 * a
			for b in blobs:
				_blob(n, Vector2(b.x, b.y), b.z, col.darkened(0.15))
			var lc := col.lightened(0.25)
			lc.a = 0.55 * a
			for b in hl:
				_blob(n, Vector2(b.x, b.y), b.z, lc)
		"scorch":
			for b in blobs:
				_blob(n, Vector2(b.x, b.y), b.z, Color(0.03, 0.025, 0.02, 0.2 * a))
			for b in hl:
				_blob(n, Vector2(b.x, b.y), b.z, Color(0.0, 0.0, 0.0, 0.25 * a))
		"bile":
			col.a = 0.6 * a
			for b in blobs:
				_blob(n, Vector2(b.x, b.y), b.z, col.darkened(0.2))
			for b in hl:
				_blob(n, Vector2(b.x, b.y), b.z, Color(0.85, 1.0, 0.4, 0.7 * a))
		"pock":
			_blob(n, p, d.s, Color(0.04, 0.035, 0.03, 0.55 * a))
			for b in hl:
				_blob(n, Vector2(b.x, b.y), b.z, Color(0.1, 0.09, 0.08, 0.5 * a))
		"casing":
			var dir := Vector2.from_angle(d.r)
			col.a = a
			n.draw_line(p - dir * 2.4, p + dir * 2.4, Color(0.08, 0.06, 0.03, 0.6 * a), 3.6)
			n.draw_line(p - dir * 2.0, p + dir * 2.0, col, 2.2)
			_blob(n, p + dir * 2.0, 0.9, col.lightened(0.4))


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


func _write_particles(b: ShapeBatch, arr: Array[Dictionary]) -> void:
	b.begin()
	for q in arr:
		var k: float = (q.t as float) / (q.life as float)
		var col: Color = q.c
		var p: Vector2 = q.p
		var s0: float = q.s0
		var s1: float = q.s1
		match q.k:
			P.DOT:
				col.a *= 1.0 - k
				var rr := lerpf(s0, s1, k) * K
				if q.get("soft", false):
					b.soft(p, rr, col)
				else:
					b.disc(p, rr, col)
			P.SPARK:
				var v: Vector2 = q.v
				col.a *= 1.0 - k
				b.line(p, p - v.normalized() * s0 * K * (1.0 - k * 0.6), s1 * K, col)
			P.CHIP:
				col.a *= 1.0 - k * k
				b.rect(p, Vector2(s0 * K, s1 * K), q.rot, col)
			P.RING:
				var e := 1.0 - pow(1.0 - k, 3.0)
				col.a *= 1.0 - k
				b.ring(p, lerpf(s0, s1, e), maxf((q.w as float) * K * (1.0 - k * 0.7), 1.0), col)
			P.FLASH:
				col.a *= 1.0 - k
				b.flash(p, lerpf(s0, s1, sqrt(k)), col)
	b.end()


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
	_write_particles(_low, _low_p)
	_write_particles(_high, _high_p)
	_update_decals(delta)
	Enemies.reap(2)
	var cam := get_viewport().get_camera_2d()
	if cam:
		if _shake > 0.05:
			cam.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
			_shake = maxf(_shake - (4.0 + _shake * 4.0) * delta, 0.0)
		elif cam.offset != Vector2.ZERO:
			cam.offset = Vector2.ZERO
