extends Node2D
## Placeholder test ground in the pixel style: a dithered ground texture (generated once,
## drawn as one tiled rect), scattered grass / flowers / pebbles, shaded rocks and bushes,
## border walls. All of it is static: each _draw() runs once and the canvas keeps the
## commands. Props live in CHUNK-sized child items so off-screen ones are culled whole.

const HALF_SIZE := 3000.0
const ROCK_COUNT := 140
const BUSH_COUNT := 420
## Vegetation comes in clumps: CLUSTERS centres, CLUSTER_SIZE items each, plus loose ones.
const CLUSTERS := 420
const CLUSTER_SIZE := 14
const LOOSE_DECOR := 1500
## World px per prop chunk (one canvas item each).
const CHUNK := 600.0
## World px per ground texel: one texel = one buffer pixel at the base zoom.
const TEXEL := 1.0 / Vis.CAM_ZOOM
const GROUND_TEX_SIZE := 256
## Light comes from the top-left of the world; shadows fall bottom-right.
const SHADOW_OFFSET := Vector2(7, 9)

## Placeholder enemies around the spawn.
const ZOMBIES := 10

const BAYER4 := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

var _ground: ImageTexture
var _rocks: Array[Dictionary] = []
var _bushes: Array[Dictionary] = []
var _decor: Array[Dictionary] = []
## Chunk key -> {"decor": [], "rocks": [], "bushes": []}
var _chunks := {}


func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_ground = _make_ground()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	while _rocks.size() < ROCK_COUNT:
		var pos := _spot(rng)
		if pos.length() < 300.0:
			continue # keep spawn clear
		var r := rng.randf_range(25.0, 80.0)
		var poly := _blob(rng, r, 9)
		_add_wall(pos, poly)
		_rocks.append({"pos": pos, "poly": poly, "r": r})
	while _bushes.size() < BUSH_COUNT:
		var pos := _spot(rng)
		if pos.length() < 250.0:
			continue
		var blobs: Array[Vector3] = []
		for i in rng.randi_range(3, 5):
			blobs.append(Vector3(rng.randf_range(-22, 22), rng.randf_range(-16, 16), rng.randf_range(14, 24)))
		_bushes.append({"pos": pos, "blobs": blobs})
	for i in CLUSTERS:
		var c := _spot(rng)
		var col: Color = [Pal.FLOWER_A, Pal.FLOWER_B, Pal.FLOWER_C][rng.randi_range(0, 2)]
		var flowers := rng.randf() < 0.4
		for j in CLUSTER_SIZE:
			var p := c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 70.0) * rng.randf()
			var kind := rng.randi_range(5, 7) if flowers and rng.randf() < 0.5 else rng.randi_range(0, 4)
			_decor.append({"pos": p, "kind": kind, "flip": rng.randf() < 0.5, "col": col})
	for i in LOOSE_DECOR:
		_decor.append({"pos": _spot(rng), "kind": rng.randi_range(0, 9), "flip": rng.randf() < 0.5,
			"col": [Pal.FLOWER_A, Pal.FLOWER_B, Pal.FLOWER_C][rng.randi_range(0, 2)]})
	for d in _decor:
		_bucket(d.pos, "decor").append(d)
	for b in _bushes:
		_bucket(b.pos, "bushes").append(b)
	for r in _rocks:
		_bucket(r.pos, "rocks").append(r)
	for key in _chunks:
		var c := Node2D.new()
		var lists: Dictionary = _chunks[key]
		c.draw.connect(_draw_chunk.bind(c, lists))
		add_child(c)
	for i in ZOMBIES:
		var z := Zombie.new()
		z.skin = "zombieA" if i % 2 == 0 else "zombieC"
		z.position = Vector2.from_angle(TAU * i / ZOMBIES + 0.3) * rng.randf_range(380.0, 700.0)
		z.rotation = rng.randf() * TAU
		add_child(z)
	var h := HALF_SIZE
	for r in [Rect2(-h, -h - 50, 2 * h, 50), Rect2(-h, h, 2 * h, 50), Rect2(-h - 50, -h, 50, 2 * h), Rect2(h, -h, 50, 2 * h)]:
		_add_wall(Vector2.ZERO, PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]))


## Tileable noise, posterised to the 4 ground shades with a 4x4 ordered dither.
func _make_ground() -> ImageTexture:
	var n := FastNoiseLite.new()
	n.seed = 7
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.012
	n.fractal_octaves = 3
	var s := GROUND_TEX_SIZE
	var img := n.get_seamless_image(s, s)
	img.convert(Image.FORMAT_L8)
	var data := img.get_data()
	var out := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var levels := Pal.GROUND.size()
	for y in s:
		for x in s:
			var v := float(data[y * s + x]) / 255.0
			v = clampf((v - 0.25) / 0.5, 0.0, 0.999) * (levels - 1)
			var t := (float(BAYER4[(y % 4) * 4 + x % 4]) + 0.5) / 16.0
			var i := mini(int(v) + (1 if fmod(v, 1.0) > t else 0), levels - 1)
			out.set_pixel(x, y, Pal.GROUND[i])
	# Speckles: single lighter / darker pixels and tiny grass ticks (free detail, baked).
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in s * s / 40:
		var x := rng.randi_range(0, s - 1)
		var y := rng.randi_range(0, s - 2)
		var r := rng.randf()
		if r < 0.45:
			out.set_pixel(x, y, Pal.GROUND[mini(levels - 1, _shade_at(out, x, y) + 1)])
		elif r < 0.8:
			out.set_pixel(x, y, Pal.GROUND[maxi(0, _shade_at(out, x, y) - 1)])
		else:
			out.set_pixel(x, y, Pal.MOSS)
			out.set_pixel(x, y + 1, Pal.GROUND[0])
	return ImageTexture.create_from_image(out)


func _shade_at(img: Image, x: int, y: int) -> int:
	return maxi(0, Pal.GROUND.find(img.get_pixel(x, y)))


func _bucket(pos: Vector2, kind: String) -> Array:
	var key := Vector2i((pos / CHUNK).floor())
	if not _chunks.has(key):
		_chunks[key] = {"decor": [], "rocks": [], "bushes": []}
	return _chunks[key][kind]


func _spot(rng: RandomNumberGenerator) -> Vector2:
	return Vector2(rng.randf_range(-HALF_SIZE + 100, HALF_SIZE - 100), rng.randf_range(-HALF_SIZE + 100, HALF_SIZE - 100))


func _add_wall(pos: Vector2, poly: PackedVector2Array) -> void:
	var body := StaticBody2D.new()
	body.position = pos
	var col := CollisionPolygon2D.new()
	col.polygon = poly
	body.add_child(col)
	add_child(body)


func _blob(rng: RandomNumberGenerator, radius: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n + rng.randf_range(-0.2, 0.2)
		pts.append(Vector2.from_angle(a) * radius * rng.randf_range(0.75, 1.1))
	return pts


func _draw() -> void:
	var h := HALF_SIZE
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * TEXEL)
	draw_texture_rect(_ground, Rect2(-h / TEXEL, -h / TEXEL, 2 * h / TEXEL, 2 * h / TEXEL), true)
	draw_set_transform(Vector2.ZERO)


## Decor first (flat), then bushes, then rocks, within a chunk.
func _draw_chunk(ci: CanvasItem, lists: Dictionary) -> void:
	for d in lists.decor:
		_draw_decor(ci, d)
	for b in lists.bushes:
		_draw_bush(ci, b.pos, b.blobs)
	for r in lists.rocks:
		_draw_rock(ci, r.pos, r.poly, r.r)


func _draw_decor(ci: CanvasItem, d: Dictionary) -> void:
	var p: Vector2 = d.pos
	var s := TEXEL
	var f := -1.0 if d.flip else 1.0
	match d.kind:
		0, 1, 2: # grass tuft: blades of 2-4 pixels, lit tips
			for i in 3:
				var x := (i - 1) * s * f
				var hgt := (2 + (i + int(d.flip)) % 3) * s
				ci.draw_rect(Rect2(p + Vector2(x, -hgt), Vector2(s, hgt)), Pal.GRASS)
				ci.draw_rect(Rect2(p + Vector2(x, -hgt), Vector2(s, s)), Pal.GRASS_LIGHT)
		3, 4: # moss patch
			ci.draw_rect(Rect2(p, Vector2(4 * s, s)), Pal.MOSS)
			ci.draw_rect(Rect2(p + Vector2(s, -s), Vector2(3 * s, s)), Pal.MOSS)
			ci.draw_rect(Rect2(p + Vector2(2 * s, -2 * s), Vector2(s, s)), Pal.MOSS)
		5, 6: # flower: stem, 2x2 head with a light pixel
			ci.draw_rect(Rect2(p + Vector2(0, -s), Vector2(s, 2 * s)), Pal.GRASS)
			ci.draw_rect(Rect2(p + Vector2(-s * 0.5, -3 * s), Vector2(2 * s, 2 * s)), Pal.INK)
			ci.draw_rect(Rect2(p + Vector2(0, -3 * s), Vector2(s, s)), (d.col as Color).lightened(0.3))
			ci.draw_rect(Rect2(p + Vector2(0, -2 * s), Vector2(s, s)), d.col)
			ci.draw_rect(Rect2(p + Vector2(s * 0.5, -2.5 * s), Vector2(s, s)), d.col)
		7: # flower cluster
			for o in [Vector2(0, 0), Vector2(3, 1), Vector2(1, 3)]:
				ci.draw_rect(Rect2(p + o * s, Vector2(s, s)), d.col)
				ci.draw_rect(Rect2(p + o * s + Vector2(0, s), Vector2(s, s)), Pal.GRASS)
		_: # pebble
			ci.draw_rect(Rect2(p + Vector2(s, s), Vector2(2 * s, s)), Pal.SHADOW)
			ci.draw_rect(Rect2(p, Vector2(2 * s, s)), Pal.PEBBLE)
			ci.draw_rect(Rect2(p, Vector2(s, s)), Pal.STONE_LIGHT)


## Rock: drop shadow, dark base, lit face (shrunk toward the light), top highlight, ink outline.
func _draw_rock(ci: CanvasItem, pos: Vector2, poly: PackedVector2Array, r: float) -> void:
	ci.draw_set_transform(pos + SHADOW_OFFSET * (r / 40.0))
	ci.draw_colored_polygon(poly, Pal.SHADOW)
	ci.draw_set_transform(pos)
	ci.draw_colored_polygon(poly, Pal.STONE_DARK)
	ci.draw_set_transform(pos + Vector2(-0.12, -0.15) * r, 0.0, Vector2.ONE * 0.8)
	ci.draw_colored_polygon(poly, Pal.STONE)
	ci.draw_set_transform(pos + Vector2(-0.25, -0.3) * r, 0.0, Vector2.ONE * 0.5)
	ci.draw_colored_polygon(poly, Pal.STONE_LIGHT)
	ci.draw_set_transform(pos + Vector2(-0.33, -0.4) * r, 0.0, Vector2.ONE * 0.22)
	ci.draw_colored_polygon(poly, Pal.STONE_TOP)
	ci.draw_set_transform(pos)
	var outline := poly.duplicate()
	outline.append(poly[0])
	ci.draw_polyline(outline, Pal.INK, TEXEL)
	ci.draw_set_transform(Vector2.ZERO)


## Bush: overlapping leaf blobs, each with a shadow, dark rim and lit top-left.
func _draw_bush(ci: CanvasItem, pos: Vector2, blobs: Array[Vector3]) -> void:
	for b in blobs:
		ci.draw_circle(pos + Vector2(b.x, b.y) + SHADOW_OFFSET, b.z, Pal.SHADOW)
	for b in blobs:
		ci.draw_circle(pos + Vector2(b.x, b.y), b.z + TEXEL, Pal.INK)
	for b in blobs:
		ci.draw_circle(pos + Vector2(b.x, b.y), b.z, Pal.LEAF_DARK)
	for b in blobs:
		ci.draw_circle(pos + Vector2(b.x, b.y) + Vector2(-0.2, -0.25) * b.z, b.z * 0.7, Pal.LEAF)
	for b in blobs:
		ci.draw_circle(pos + Vector2(b.x, b.y) + Vector2(-0.4, -0.45) * b.z, b.z * 0.3, Pal.LEAF_LIGHT)
