class_name Zone
extends Node2D
## One 120 x 120 m zone of the Terminid planet (v0.5 slice). The layout (walls, ruins,
## compounds, barricades) is hand-built per zone type; rocks, trees, crates and the
## objective / POI / enemy slots chosen on top of it are randomised each run.
## Zone-local layout is authored in metres (north = -y); the node sits at the zone's
## world centre. South and north walls have an 8 m opening where the passages join.
## Draws the static ground, walls and rocks in one canvas item (z below actors).
## Props with behaviour (crates, trees, nest holes, terminals) are created by Mission
## from the spot lists here.

enum Type { INSERTION, MIDDLE, EXTRACTION }

const PX := Firearm.PX_PER_M
## Props, walls and buildings are VISUAL_SCALE bigger (positions, ranges and the 8 m openings are not).
const K := Vis.VISUAL_SCALE
const SIZE_M := 120.0
const HALF_M := SIZE_M * 0.5
const HALF := HALF_M * PX
const GAP_M := 8.0
const NAMES := ["INSERTION ZONE", "MIDDLE ZONE", "EXTRACTION ZONE"]
const GROUNDS := [Color(0.33, 0.29, 0.2), Color(0.3, 0.27, 0.21), Color(0.27, 0.29, 0.21)]
const WALL := Color(0.5, 0.47, 0.42)
const CONCRETE := Color(0.4, 0.39, 0.36)

var type := Type.INSERTION
var zone_name := ""
## World rectangle of the zone interior.
var rect := Rect2()
## World positions.
var start_pos := Vector2.ZERO
var terminal_pos := Vector2.INF
var pad_pos := Vector2.INF
var entrance_pt := Vector2.ZERO
var exit_pt := Vector2.ZERO
## name -> Array[Vector2] (world): nest, sample, ammo, pack, edge, elite.
var slots := {}
var trees: Array[Vector2] = []
var crates: Array[Vector2] = []
## Drawn layers (zone-local px).
var walls: Array[Rect2] = []
var floors: Array[Rect2] = []
var rocks: Array[Dictionary] = []

var _rng := RandomNumberGenerator.new()
var _clear: Array[Dictionary] = [] # {pos, r} px, local: keep free of rocks/trees/crates
var _forest: Array[Dictionary] = []
## Detail items (cracks, pebbles, tufts, goo...) bucketed in CHUNKS x CHUNKS draw nodes so
## off-screen chunks are culled by the renderer. Baked once in build().
var _chunks: Array = []
var _goo_spots: Array[Vector2] = []


## Build the layout. Call after the node is in the tree and positioned.
func build(t: int, world_center: Vector2, seed_value: int) -> void:
	type = t as Type
	zone_name = NAMES[t]
	position = world_center
	rect = Rect2(world_center - Vector2(HALF, HALF), Vector2(HALF, HALF) * 2.0)
	z_index = -10
	_rng.seed = seed_value
	_border()
	var local_slots := {"nest": [], "sample": [], "ammo": [], "pack": [], "edge": [], "elite": []}
	match type:
		Type.INSERTION:
			_layout_insertion(local_slots)
		Type.MIDDLE:
			_layout_middle(local_slots)
		Type.EXTRACTION:
			_layout_extraction(local_slots)
	for k in local_slots:
		var list: Array = local_slots[k]
		var out: Array[Vector2] = []
		for p in list:
			out.append(position + (p as Vector2) * PX)
		out.shuffle()
		slots[k] = out
	entrance_pt = position + Vector2(0, HALF_M - 2.0) * PX
	exit_pt = position + Vector2(0, -HALF_M + 2.0) * PX
	_scatter()
	_bake()


func contains(p: Vector2, margin := 0.0) -> bool:
	return rect.grow(margin).has_point(p)


func _m(x: float, y: float) -> Vector2:
	return Vector2(x, y) * PX


# --- Layouts (metres, zone-local) --------------------------------------------------

func _border() -> void:
	var t := 2.0 * K
	var h := HALF_M
	var g := GAP_M * 0.5
	# North and south walls with the passage openings.
	for y in [-h - t, h]:
		_wall_rect(Rect2(-h - t, y, h - g + t, t))
		_wall_rect(Rect2(g, y, h - g + t, t))
	_wall_rect(Rect2(-h - t, -h, t, h * 2.0))
	_wall_rect(Rect2(h, -h, t, h * 2.0))
	_clear.append({"pos": _m(0, h - 6), "r": 12.0 * PX})
	_clear.append({"pos": _m(0, -h + 6), "r": 12.0 * PX})


func _layout_insertion(s: Dictionary) -> void:
	start_pos = position + _m(0, 44)
	_clear.append({"pos": _m(0, 44), "r": 9.0 * PX})
	_ruin(Vector2(-36, 14), 14, 10)
	_ruin(Vector2(36, 18), 12, 10)
	_ruin(Vector2(-6, -8), 10, 8)
	_ruin(Vector2(26, -24), 10, 8)
	_seg(Vector2(-12, 36), Vector2(-5, 36))
	_seg(Vector2(5, 36), Vector2(12, 36))
	_seg(Vector2(-22, -24), Vector2(-12, -24))
	_seg(Vector2(10, 4), Vector2(20, 4))
	_seg(Vector2(-26, 40), Vector2(-17, 40))
	s.nest = [Vector2(-34, -38), Vector2(32, -40), Vector2(2, -32), Vector2(-46, -10), Vector2(46, -12)]
	s.sample = [Vector2(-48, 42), Vector2(48, 40), Vector2(0, -50), Vector2(-24, -4)]
	s.ammo = [Vector2(-22, 38), Vector2(22, 38), Vector2(-52, 30), Vector2(52, 30)]
	s.pack = [Vector2(-30, -8), Vector2(30, -8), Vector2(12, -36), Vector2(-16, -32), Vector2(-42, 28),
		Vector2(40, 4), Vector2(0, 12)]
	s.edge = [Vector2(-56, -12), Vector2(56, -12), Vector2(-56, 20), Vector2(56, 20), Vector2(-30, -56),
		Vector2(30, -56)]
	s.elite = [Vector2(-20, -42), Vector2(22, -38), Vector2(-4, 20)]
	_keep_clear(s)


func _layout_middle(s: Dictionary) -> void:
	start_pos = position + _m(0, 54)
	terminal_pos = position + _m(0, -4)
	_compound(Vector2(0, -4), 28, 20, 6.0)
	_ruin(Vector2(-40, -34), 12, 10)
	_ruin(Vector2(40, -30), 12, 10)
	_ruin(Vector2(-42, 26), 12, 10)
	_ruin(Vector2(42, 30), 12, 10)
	_seg(Vector2(-14, 30), Vector2(-4, 30))
	_seg(Vector2(4, 30), Vector2(14, 30))
	_seg(Vector2(-20, -32), Vector2(-8, -32))
	_seg(Vector2(8, -32), Vector2(20, -32))
	s.sample = [Vector2(-24, 44), Vector2(26, 44), Vector2(-50, 0), Vector2(50, -2)]
	s.ammo = [Vector2(-16, 14), Vector2(16, 14), Vector2(-46, -16), Vector2(46, -14)]
	s.pack = [Vector2(-26, 8), Vector2(26, 8), Vector2(-28, -22), Vector2(28, -20), Vector2(0, -26),
		Vector2(-12, 24), Vector2(14, 22), Vector2(-48, 12), Vector2(48, 14)]
	s.edge = [Vector2(-56, -26), Vector2(56, -26), Vector2(-56, 4), Vector2(56, 4), Vector2(-30, -56),
		Vector2(30, -56)]
	s.elite = [Vector2(-24, -46), Vector2(26, -44), Vector2(0, 36)]
	s.nest = [Vector2(-30, -48), Vector2(32, -48), Vector2(-54, 46), Vector2(54, 46)]
	_keep_clear(s)


func _layout_extraction(s: Dictionary) -> void:
	start_pos = position + _m(0, 54)
	pad_pos = position + _m(0, -30)
	terminal_pos = position + _m(16, -16)
	_clear.append({"pos": _m(0, -30), "r": 11.0 * K * PX})
	floors.append(Rect2(_m(-9 * K, -30 - 9 * K), _m(18 * K, 18 * K)))
	_compound(Vector2(16, -16), 12, 10, 5.0)
	_ruin(Vector2(-38, -4), 14, 10)
	_ruin(Vector2(38, 10), 14, 10)
	_ruin(Vector2(-22, 26), 10, 8)
	_ruin(Vector2(24, 34), 10, 8)
	_seg(Vector2(-16, 6), Vector2(-6, 6))
	_seg(Vector2(6, 6), Vector2(16, 6))
	_seg(Vector2(-30, -26), Vector2(-20, -26))
	s.sample = [Vector2(-50, 40), Vector2(50, 44), Vector2(-46, -44), Vector2(44, -42)]
	s.ammo = [Vector2(-10, 20), Vector2(10, 20), Vector2(-48, 12), Vector2(48, 22)]
	s.pack = [Vector2(-28, -14), Vector2(30, -2), Vector2(-14, 12), Vector2(18, 22), Vector2(-46, -30),
		Vector2(46, -26), Vector2(0, -8), Vector2(-40, 30)]
	s.edge = [Vector2(-56, -20), Vector2(56, -20), Vector2(-56, 10), Vector2(56, 10), Vector2(-30, -56),
		Vector2(30, -56)]
	s.elite = [Vector2(-24, -40)]
	s.nest = [Vector2(-34, -44), Vector2(34, -46), Vector2(-52, 30), Vector2(52, 36)]
	_keep_clear(s)


## Slots, objectives and POIs keep rocks/trees away.
func _keep_clear(s: Dictionary) -> void:
	for k in s:
		for p in s[k]:
			_clear.append({"pos": (p as Vector2) * PX, "r": 3.5 * K * PX})


## Wall from a to b (metres), 1 m thick.
func _seg(a: Vector2, b: Vector2, thick := 1.0) -> void:
	_wall_rect(Rect2(a, Vector2.ZERO).expand(b).grow(thick * K * 0.5))


## Ruined building: broken walls with doorways (half-size w/2 x h/2 around c).
func _ruin(c: Vector2, w: float, h: float) -> void:
	w *= K
	h *= K
	var hw := w * 0.5
	var hh := h * 0.5
	floors.append(Rect2((c - Vector2(hw, hh)) * PX, Vector2(w, h) * PX))
	_seg(c + Vector2(-hw, -hh), c + Vector2(hw * 0.2, -hh), 0.8)
	_seg(c + Vector2(-hw, -hh), c + Vector2(-hw, hh * 0.3), 0.8)
	_seg(c + Vector2(hw, -hh * 0.2), c + Vector2(hw, hh), 0.8)
	_seg(c + Vector2(-hw * 0.3, hh), c + Vector2(hw, hh), 0.8)
	_clear.append({"pos": c * PX, "r": maxf(w, h) * 0.5 * PX + 2.0 * PX})


## Walled square with an opening of `gap` m in the middle of every side.
func _compound(c: Vector2, w: float, h: float, gap: float) -> void:
	w *= K
	h *= K
	var hw := w * 0.5
	var hh := h * 0.5
	var g := gap * 0.5
	floors.append(Rect2((c - Vector2(hw, hh)) * PX, Vector2(w, h) * PX))
	for y in [-hh, hh]:
		_seg(c + Vector2(-hw, y), c + Vector2(-g, y), 1.0)
		_seg(c + Vector2(g, y), c + Vector2(hw, y), 1.0)
	for x in [-hw, hw]:
		_seg(c + Vector2(x, -hh), c + Vector2(x, -g), 1.0)
		_seg(c + Vector2(x, g), c + Vector2(x, hh), 1.0)
	_clear.append({"pos": c * PX, "r": maxf(w, h) * 0.5 * PX + 3.0 * PX})


# --- Random props on top ------------------------------------------------------------

func _scatter() -> void:
	var fields := [Vector2(-30, -30), Vector2(30, -40), Vector2(-50, 10), Vector2(50, 0), Vector2(0, 30),
		Vector2(-20, 46), Vector2(24, -8), Vector2(-8, -48)]
	fields.shuffle()
	for c in fields.slice(0, 5):
		var center: Vector2 = (c as Vector2) * PX + Vector2(_rng.randf_range(-5, 5), _rng.randf_range(-5, 5)) * PX
		for i in _rng.randi_range(3, 6):
			var p := center + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0, 7) * PX
			if not _blocked(p, 2.5 * K * PX):
				_add_rock(p, _rng.randf_range(0.8, 2.4) * K * PX)
	for i in 28:
		var p := Vector2(_rng.randf_range(-HALF + 120, HALF - 120), _rng.randf_range(-HALF + 120, HALF - 120))
		if not _blocked(p, 2.5 * K * PX):
			_add_rock(p, _rng.randf_range(0.5, 1.4) * K * PX)
	for i in 3:
		var f := {"pos": Vector2(_rng.randf_range(-48, 48), _rng.randf_range(-48, 48)) * PX, "r": _rng.randf_range(8, 12) * PX}
		if _blocked(f.pos, 4.0 * K * PX):
			continue
		_forest.append(f)
		for j in int(pow(f.r / PX, 2) * 0.07 / (K * K)):
			var p: Vector2 = f.pos + Vector2.from_angle(_rng.randf() * TAU) * sqrt(_rng.randf()) * f.r
			if not _blocked(p, 2.0 * K * PX) and not _near(trees, p, 2.6 * K * PX):
				trees.append(p + position)
	for i in 10:
		var p := Vector2(_rng.randf_range(-HALF + 150, HALF - 150), _rng.randf_range(-HALF + 150, HALF - 150))
		if not _blocked(p, 2.5 * K * PX):
			crates.append(p + position)
			_clear.append({"pos": p, "r": 1.0 * K * PX})


func _blocked(p: Vector2, margin: float) -> bool:
	if absf(p.x) > HALF - 100.0 or absf(p.y) > HALF - 100.0:
		return true
	for c in _clear:
		if p.distance_to(c.pos) < c.r + margin:
			return true
	for r in walls:
		if r.grow(margin).has_point(p):
			return true
	return false


func _near(list: Array[Vector2], p: Vector2, d: float) -> bool:
	for t in list:
		if (t - position).distance_squared_to(p) < d * d:
			return true
	return false


## Wall from a rectangle in metres.
func _wall_rect(r: Rect2, visible_wall := true) -> void:
	var rect_px := Rect2(r.position * PX, r.size * PX)
	var body := StaticBody2D.new()
	body.position = rect_px.get_center()
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect_px.size
	col.shape = shape
	body.add_child(col)
	add_child(body)
	if visible_wall:
		walls.append(rect_px)
		Vision.add_occluder(body, Vision.rect_points(rect_px.size))


func _add_rock(p: Vector2, radius: float) -> void:
	var poly := _blunt_blob(radius)
	var body := StaticBody2D.new()
	body.position = p
	var col := CollisionPolygon2D.new()
	col.polygon = poly
	body.add_child(col)
	Vision.add_occluder(body, poly)
	add_child(body)
	var world_poly := PackedVector2Array()
	for v in poly:
		world_poly.append(v + p)
	rocks.append({"poly": world_poly, "pos": p, "r": radius, "shade": _rng.randf_range(0.3, 0.45)})
	_clear.append({"pos": p, "r": radius + 30.0})


func _blunt_blob(radius: float) -> PackedVector2Array:
	var n := 14
	var radii: Array[float] = []
	for i in n:
		radii.append(radius * _rng.randf_range(0.75, 1.0))
	for pass_i in 2:
		var smooth: Array[float] = []
		for i in n:
			smooth.append((radii[i - 1] + radii[i] * 2.0 + radii[(i + 1) % n]) / 4.0)
		radii = smooth
	var start := _rng.randf() * TAU
	var pts := PackedVector2Array()
	for i in n:
		var a := start + TAU * i / n
		pts.append(Vector2(cos(a), sin(a)) * radii[i])
	return pts



# --- Baked visuals ---------------------------------------------------------------------
## Ground = base colour + three noise layers (NoiseTexture2D with a colour ramp, tinted per
## zone type) + soft blotches; detail items live in culled chunks; props (rocks, walls) in
## one node with drop shadows and height shading. Nothing is re-recorded after build().

const CHUNKS := 4
const GRASS := [Color(0.3, 0.38, 0.18), Color(0.36, 0.42, 0.2), Color(0.44, 0.44, 0.22)]
const GOO := Color(0.46, 0.34, 0.3)

static var _soft_tex: GradientTexture2D


static func soft_texture() -> GradientTexture2D:
	if _soft_tex == null:
		_soft_tex = GradientTexture2D.new()
		_soft_tex.fill = GradientTexture2D.FILL_RADIAL
		_soft_tex.fill_from = Vector2(0.5, 0.5)
		_soft_tex.fill_to = Vector2(1.0, 0.5)
		_soft_tex.width = 64
		_soft_tex.height = 64
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_soft_tex.gradient = g
	return _soft_tex


func _noise_tex(size: int, freq: float, ramp: Gradient, seamless := false, octaves := 3) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = _rng.randi()
	n.frequency = freq
	n.fractal_octaves = octaves
	var t := NoiseTexture2D.new()
	t.noise = n
	t.width = size
	t.height = size
	t.seamless = seamless
	t.color_ramp = ramp
	t.generate_mipmaps = false
	return t


## Colour ramp over the normalised noise value: `a` below 0.4, clear at 0.5, `c` above 0.6
## (simplex noise rarely reaches the extremes, so the transitions sit in the middle).
func _ramp(a: Color, b: Color, c: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, a)
	g.set_color(1, c)
	g.add_point(0.38, a)
	g.add_point(0.5, b)
	g.add_point(0.62, c)
	return g


func _bake() -> void:
	var ground: Color = GROUNDS[type]
	var clear := Color(ground.r, ground.g, ground.b, 0.0)
	# Layer textures.
	var tint: Array = [Color(0.55, 0.38, 0.15), Color(0.4, 0.4, 0.42), Color(0.2, 0.42, 0.14)]
	var big := _noise_tex(512, 0.010, _ramp(Color(0.1, 0.07, 0.04, 0.55), clear, Color(1.0, 0.9, 0.65, 0.4)))
	var blotch := _noise_tex(512, 0.024, _ramp(Color(tint[type] as Color, 0.0), clear, Color((tint[type] as Color), 0.5)), false, 2)
	var grain := _noise_tex(256, 0.035, _ramp(Color(0, 0, 0, 0.12), clear, Color(1, 1, 0.9, 0.08)), true, 2)
	var ground_node := Node2D.new()
	ground_node.name = "Ground"
	ground_node.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	add_child(ground_node)
	var patches: Array[Dictionary] = []
	for i in 46:
		patches.append({"pos": Vector2(_rng.randf_range(-HALF, HALF), _rng.randf_range(-HALF, HALF)),
			"r": _rng.randf_range(4, 13) * PX, "col": ground.lightened(_rng.randf_range(-0.14, 0.1))})
	ground_node.draw.connect(func():
		var full := Rect2(-HALF, -HALF, HALF * 2.0, HALF * 2.0)
		ground_node.draw_rect(Rect2(-HALF - 120, -HALF - 120, HALF * 2 + 240, HALF * 2 + 240), Color(0.06, 0.06, 0.05))
		ground_node.draw_rect(full, ground)
		var soft := soft_texture()
		for p in patches:
			var r: float = p.r
			var c: Color = p.col
			c.a = 0.55
			ground_node.draw_texture_rect(soft, Rect2((p.pos as Vector2) - Vector2(r, r), Vector2(r, r) * 2.0), false, c)
		ground_node.draw_texture_rect(big, full, false)
		ground_node.draw_texture_rect(blotch, full, false)
		ground_node.draw_texture_rect(grain, full, true)
		# Darker rim toward the walls so the zone reads as an arena.
		var e := 6.0 * PX
		for k in 3:
			var inset := e * (k + 1) / 3.0
			ground_node.draw_rect(full.grow(-inset + e), Color(0, 0, 0, 0.05), false, e / 3.0))
	_make_details()
	for i in CHUNKS * CHUNKS:
		var items: Array = _chunks[i]
		if items.is_empty():
			continue
		var cn := Node2D.new()
		add_child(cn)
		cn.draw.connect(_draw_chunk.bind(cn, items))
	var props := Node2D.new()
	props.name = "Props"
	add_child(props)
	props.draw.connect(_draw_props.bind(props))


func _chunk_of(p: Vector2) -> int:
	var cx := clampi(int((p.x + HALF) / (HALF * 2.0) * CHUNKS), 0, CHUNKS - 1)
	var cy := clampi(int((p.y + HALF) / (HALF * 2.0) * CHUNKS), 0, CHUNKS - 1)
	return cy * CHUNKS + cx


func _in_wall(p: Vector2, margin: float) -> bool:
	for r in walls:
		if r.grow(margin).has_point(p):
			return true
	return false


func _add_item(it: Dictionary) -> void:
	(_chunks[_chunk_of(it.p)] as Array).append(it)


func _make_details() -> void:
	_chunks.clear()
	for i in CHUNKS * CHUNKS:
		_chunks.append([])
	var ground: Color = GROUNDS[type]
	var grass_col: Color = GRASS[type]
	var density: float = [0.5, 0.8, 1.5][type]
	# Bug goo around the outpost holes (nests are the first N slots).
	var holes := 3 if type == Type.INSERTION else (2 if type == Type.MIDDLE else 0)
	var nests: Array = slots.get("nest", [])
	for i in mini(holes, nests.size()):
		var c: Vector2 = (nests[i] as Vector2) - position
		_goo_spots.append(c)
		var blobs := PackedVector3Array()
		for j in 14:
			var q := c + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.0, 2.8) * PX
			blobs.append(Vector3(q.x, q.y, _rng.randf_range(0.35, 0.9) * PX))
		_add_item({"k": "goo", "p": c, "b": blobs})
		for j in 9:
			var a := _rng.randf() * TAU
			var q := c + Vector2.from_angle(a) * _rng.randf_range(1.2, 3.2) * PX
			_add_item({"k": "pustule", "p": q, "r": _rng.randf_range(4, 9)})
		for j in 7:
			var a := _rng.randf() * TAU
			_add_item({"k": "claw", "p": c + Vector2.from_angle(a) * 1.6 * PX, "a": a, "len": _rng.randf_range(2.0, 4.5) * PX})
	for i in int(260 * density + 60):
		var p := Vector2(_rng.randf_range(-HALF, HALF), _rng.randf_range(-HALF, HALF))
		if _in_wall(p, 8.0):
			continue
		var a := _rng.randf() * TAU
		var pts := PackedVector2Array([p])
		var cur := p
		var dir := Vector2.from_angle(a)
		for j in _rng.randi_range(3, 5):
			dir = dir.rotated(_rng.randf_range(-0.7, 0.7))
			cur += dir * _rng.randf_range(10, 34)
			pts.append(cur)
		_add_item({"k": "crack", "p": p, "pts": pts, "w": _rng.randf_range(1.2, 2.6)})
	for i in 420:
		var p := Vector2(_rng.randf_range(-HALF, HALF), _rng.randf_range(-HALF, HALF))
		if _in_wall(p, 8.0):
			continue
		var cl := PackedVector3Array()
		for j in _rng.randi_range(2, 5):
			var q := p + Vector2(_rng.randf_range(-9, 9), _rng.randf_range(-9, 9))
			cl.append(Vector3(q.x, q.y, _rng.randf_range(1.6, 4.2)))
		_add_item({"k": "pebbles", "p": p, "b": cl, "tone": _rng.randf()})
	for i in int(700 * density):
		var p := Vector2(_rng.randf_range(-HALF, HALF), _rng.randf_range(-HALF, HALF))
		if _in_wall(p, 8.0):
			continue
		_add_item({"k": "tuft", "p": p, "a": _rng.randf_range(-0.4, 0.4), "n": _rng.randi_range(4, 7),
			"col": grass_col.lerp(Color(0.5, 0.45, 0.2), _rng.randf() * 0.5).darkened(_rng.randf_range(0.0, 0.2)),
			"h": _rng.randf_range(8, 16)})
	for i in 110:
		var p := Vector2(_rng.randf_range(-HALF, HALF), _rng.randf_range(-HALF, HALF))
		if _in_wall(p, 8.0):
			continue
		_add_item({"k": "rubble", "p": p, "r": _rng.randf_range(3, 7), "a": _rng.randf() * TAU})
	for f in _forest:
		for j in 26:
			var q: Vector2 = f.pos + Vector2.from_angle(_rng.randf() * TAU) * sqrt(_rng.randf()) * f.r
			_add_item({"k": "leaf", "p": q, "a": _rng.randf() * TAU})
		_add_item({"k": "moss", "p": f.pos, "r": f.r})
	for r in floors:
		_add_item({"k": "floor", "p": r.get_center(), "rect": r})
	if pad_pos != Vector2.INF:
		_add_item({"k": "pad", "p": pad_pos - position})
	if type == Type.INSERTION:
		_add_item({"k": "dropzone", "p": start_pos - position})


func _draw_chunk(n: Node2D, items: Array) -> void:
	var ground: Color = GROUNDS[type]
	var dark := ground.darkened(0.38)
	var lite := ground.lightened(0.18)
	for it: Dictionary in items:
		var p: Vector2 = it.p
		if it.k != "floor": # floors are already sized in the layout; everything else grows about its own point
			n.draw_set_transform(p * (1.0 - K), 0.0, Vector2(K, K))
		else:
			n.draw_set_transform(Vector2.ZERO)
		match it.k:
			"crack":
				var pts: PackedVector2Array = it.pts
				n.draw_polyline(pts, Color(0.06, 0.05, 0.04, 0.35), (it.w as float) + 1.6)
				n.draw_polyline(pts, dark, it.w)
				n.draw_polyline(pts, Color(lite, 0.35), 0.8)
			"pebbles":
				var tone: float = it.tone
				for b: Vector3 in it.b:
					var c := Vector2(b.x, b.y)
					if Game.shadows_enabled: n.draw_circle(c + Vector2(1.5, 2.0), b.z, Color(0, 0, 0, 0.3))
					n.draw_circle(c, b.z, ground.darkened(0.22 + tone * 0.2))
					n.draw_circle(c + Vector2(-b.z * 0.25, -b.z * 0.25), b.z * 0.55, ground.lightened(0.1 + tone * 0.15))
			"tuft":
				var col: Color = it.col
				var h: float = it.h
				n.draw_circle(p + Vector2(1.5, 2.5), 3.5, Color(0, 0, 0, 0.18))
				for k in (it.n as int):
					var a := (it.a as float) + (k - (it.n as int) * 0.5) * 0.28
					var tip := p + Vector2(sin(a) * h * 0.9, -cos(a) * h)
					n.draw_line(p, tip, col.darkened(0.35), 2.2)
					n.draw_line(p, tip, col, 1.3)
			"rubble":
				var r: float = it.r
				var a: float = it.a
				if Game.shadows_enabled: n.draw_circle(p + Vector2(2, 3), r, Color(0, 0, 0, 0.28))
				n.draw_circle(p, r, Color(0.07, 0.07, 0.07))
				n.draw_circle(p, r - 1.2, ground.darkened(0.15).lerp(Color(0.45, 0.43, 0.4), 0.5))
				n.draw_circle(p + Vector2.from_angle(a) * -r * 0.3, r * 0.45, Color(0.58, 0.56, 0.52, 0.8))
			"leaf":
				n.draw_line(p, p + Vector2.from_angle(it.a) * 5.0, Color(0.14, 0.2, 0.08, 0.6), 2.0)
			"moss":
				var r: float = it.r
				n.draw_circle(p, r, Color(0.1, 0.14, 0.06, 0.28))
				n.draw_circle(p, r * 0.7, Color(0.1, 0.14, 0.06, 0.2))
			"goo":
				var b: PackedVector3Array = it.b
				for v in b:
					n.draw_circle(Vector2(v.x, v.y), v.z + 3.0, Color(0.1, 0.06, 0.07, 0.4))
				for v in b:
					n.draw_circle(Vector2(v.x, v.y), v.z, Color(GOO, 0.62))
				for v in b:
					n.draw_circle(Vector2(v.x - v.z * 0.2, v.y - v.z * 0.25), v.z * 0.5, Color(0.58, 0.42, 0.36, 0.55))
				n.draw_circle(p, 0.5 * PX, Color(0.7, 0.55, 0.3, 0.18))
			"pustule":
				var r: float = it.r
				if Game.shadows_enabled: n.draw_circle(p + Vector2(1.5, 2.5), r, Color(0, 0, 0, 0.3))
				n.draw_circle(p, r + 1.2, Color(0.12, 0.06, 0.06))
				n.draw_circle(p, r, Color(0.62, 0.42, 0.38))
				n.draw_circle(p + Vector2(-r * 0.3, -r * 0.3), r * 0.4, Color(0.85, 0.7, 0.6, 0.8))
			"claw":
				var d := Vector2.from_angle(it.a)
				for k in 3:
					var o := d.orthogonal() * (k - 1) * 5.0
					n.draw_line(p + o, p + o + d * (it.len as float) * (0.8 + 0.1 * k), Color(0.12, 0.08, 0.06, 0.5), 2.5)
			"floor":
				_draw_floor(n, it.rect)
			"pad":
				_draw_pad(n, p)
			"dropzone":
				n.draw_arc(p, 4.0 * PX, 0, TAU, 48, Color(1, 1, 1, 0.16), 6.0)
				n.draw_arc(p, 2.4 * PX, 0, TAU, 40, Color(1, 1, 1, 0.1), 3.0)
				for i in 4:
					var d := Vector2.from_angle(i * PI / 2.0 + PI / 4.0)
					n.draw_line(p + d * 2.8 * PX, p + d * 4.6 * PX, UiStyle.YELLOW.darkened(0.45), 5.0)


func _draw_floor(n: Node2D, r: Rect2) -> void:
	var base := CONCRETE.darkened(0.25)
	n.draw_rect(r.grow(3.0), Color(0.07, 0.07, 0.07))
	n.draw_rect(r, base)
	# Slab grid, stains and cracks.
	var step := 2.0 * PX
	var x := r.position.x + step
	while x < r.end.x:
		n.draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), base.darkened(0.25), 1.5)
		x += step
	var y := r.position.y + step
	while y < r.end.y:
		n.draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), base.darkened(0.25), 1.5)
		y += step
	var srng := RandomNumberGenerator.new()
	srng.seed = int(r.position.x * 7.0 + r.position.y * 13.0)
	for i in int(r.get_area() / 40000.0) + 2:
		var c := r.position + Vector2(srng.randf() * r.size.x, srng.randf() * r.size.y)
		n.draw_circle(c, srng.randf_range(10, 34), Color(0.05, 0.05, 0.04, 0.16))
	for i in 3:
		var c := r.position + Vector2(srng.randf() * r.size.x, srng.randf() * r.size.y)
		var pts := PackedVector2Array([c, c + Vector2(srng.randf_range(-30, 30), srng.randf_range(10, 40)),
			c + Vector2(srng.randf_range(-50, 50), srng.randf_range(40, 80))])
		n.draw_polyline(pts, base.darkened(0.5), 1.8)
	n.draw_rect(r, Color(1, 1, 1, 0.08), false, 2.0)


func _draw_pad(n: Node2D, lp: Vector2) -> void:
	if Game.shadows_enabled: n.draw_circle(lp + Vector2(6, 8), 8.2 * PX, Color(0, 0, 0, 0.25))
	n.draw_circle(lp, 8.0 * PX, CONCRETE.darkened(0.05))
	n.draw_circle(lp, 7.2 * PX, CONCRETE.darkened(0.15))
	n.draw_arc(lp, 8.0 * PX, 0, TAU, 64, UiStyle.YELLOW.darkened(0.3), 8.0)
	# Hazard dashes on the rim.
	for i in 24:
		var a := TAU * i / 24.0
		n.draw_arc(lp, 7.5 * PX, a, a + TAU / 48.0, 4, Color(0.05, 0.05, 0.05), 8.0)
	n.draw_arc(lp, 5.0 * PX, 0, TAU, 48, UiStyle.YELLOW.darkened(0.5), 4.0)
	n.draw_line(lp + Vector2(-3, 0) * PX, lp + Vector2(3, 0) * PX, Color(1, 1, 1, 0.3), 8.0)
	n.draw_line(lp + Vector2(0, -3) * PX, lp + Vector2(0, 3) * PX, Color(1, 1, 1, 0.3), 8.0)
	for i in 4:
		var d := Vector2.from_angle(i * PI / 2.0)
		n.draw_circle(lp + d * 6.2 * PX, 7.0, UiStyle.YELLOW.darkened(0.2))
		n.draw_circle(lp + d * 6.2 * PX, 3.5, Color(0.1, 0.1, 0.1))


func _draw_props(n: Node2D) -> void:
	var sh := Vector2(7, 9)
	var wall_col: Color = WALL.lerp(GROUNDS[type], 0.12)
	# Rocks: shadow, outline, body, lit facet, top, cracks.
	for r in rocks:
		var shade: float = r.shade
		var poly: PackedVector2Array = r.poly
		var center: Vector2 = r.pos
		var rad: float = r.r
		if Game.shadows_enabled:
			var sp := PackedVector2Array()
			for v in poly:
				sp.append(v + sh * clampf(rad / 60.0, 0.5, 1.4))
			n.draw_colored_polygon(sp, Color(0, 0, 0, 0.3))
		for o in Geometry2D.offset_polygon(poly, 2.0 * K):
			n.draw_colored_polygon(o, Color(0.08, 0.08, 0.08))
		n.draw_colored_polygon(poly, Color(shade, shade * 0.95, shade * 0.85))
		# Shaded lower-right half.
		var low := PackedVector2Array()
		for i in poly.size():
			var v := poly[i]
			if (v - center).dot(Vector2(0.6, 0.8)) > 0.0:
				low.append(v)
		if low.size() >= 3:
			n.draw_colored_polygon(low, Color(0, 0, 0, 0.16))
		var top := PackedVector2Array()
		for v in poly:
			top.append(center + (v - center) * 0.55 + Vector2(-0.18, -0.18) * rad)
		n.draw_colored_polygon(top, Color(shade + 0.08, shade + 0.08, shade + 0.04))
		var lit := PackedVector2Array()
		for v in top:
			lit.append(center + (v - center) * 0.55 + Vector2(-0.1, -0.1) * rad)
		n.draw_colored_polygon(lit, Color(shade + 0.16, shade + 0.15, shade + 0.1, 0.8))
		if rad > 40.0:
			var a := absf(center.x * 0.37 + center.y * 0.11)
			var d := Vector2.from_angle(a)
			n.draw_polyline(PackedVector2Array([center - d * rad * 0.4, center + d.orthogonal() * rad * 0.1,
				center + d * rad * 0.35]), Color(0.1, 0.09, 0.08, 0.7), 1.6)
	# Walls: drop shadow, outline, side shade (south/east), top face, highlight, seams, damage.
	if Game.shadows_enabled:
		for r in walls:
			n.draw_rect(Rect2(r.position + sh, r.size), Color(0, 0, 0, 0.3))
	for r in walls:
		n.draw_rect(r.grow(2.0 * K), Color(0.08, 0.08, 0.08))
		n.draw_rect(r, wall_col.darkened(0.3)) # side faces
		var top := Rect2(r.position, r.size - Vector2(minf(6.0 * K, r.size.x * 0.4), minf(7.0 * K, r.size.y * 0.4)))
		n.draw_rect(top, wall_col)
		n.draw_rect(Rect2(top.position, Vector2(top.size.x, minf(3.0 * K, top.size.y))), wall_col.lightened(0.22))
		n.draw_rect(Rect2(top.position, Vector2(minf(3.0 * K, top.size.x), top.size.y)), wall_col.lightened(0.12))
		var long_x := r.size.x >= r.size.y
		var length := r.size.x if long_x else r.size.y
		var seam := 2.0 * PX
		var t := seam
		while t < length - 10.0:
			if long_x:
				n.draw_line(Vector2(r.position.x + t, top.position.y + 3), Vector2(r.position.x + t, top.end.y), wall_col.darkened(0.3), 1.5)
			else:
				n.draw_line(Vector2(top.position.x + 3, r.position.y + t), Vector2(top.end.x, r.position.y + t), wall_col.darkened(0.3), 1.5)
			t += seam
		# Damage chips and rivets (deterministic per wall).
		var wr := RandomNumberGenerator.new()
		wr.seed = int(r.position.x * 3.0 + r.position.y * 5.0)
		for i in int(length / 90.0) + 1:
			var q := r.position + Vector2(wr.randf() * r.size.x, wr.randf() * r.size.y)
			n.draw_circle(q, wr.randf_range(2.5, 6.0) * K, wall_col.darkened(0.22))
		var rv := 40.0
		while rv < length - 20.0 and minf(r.size.x, r.size.y) > 14.0 * K:
			var rp := (Vector2(r.position.x + rv, top.position.y + 7.0) if long_x else Vector2(top.position.x + 7.0, r.position.y + rv))
			n.draw_circle(rp, 2.0 * K, wall_col.lightened(0.2))
			rv += 80.0
		# Rubble at the foot (south side).
		if long_x and r.size.x > 100.0:
			for i in 2:
				var q := Vector2(r.position.x + wr.randf() * r.size.x, r.end.y + wr.randf_range(4.0, 10.0))
				n.draw_circle(q, wr.randf_range(2.5, 5.0), wall_col.darkened(0.2))
