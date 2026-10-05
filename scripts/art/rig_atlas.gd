class_name RigAtlas
extends Node
## One shared texture atlas with every part texture of every rigged enemy type, baked ONCE at
## startup from the parts' vector drawing (SubViewport -> mipmapped ImageTexture). All enemy
## sprites use it, so they batch into a handful of draw calls. The layout is pure maths, so
## sprites can be configured before the bake finishes: the shared ImageTexture is filled in
## place when it is done. Headless (no renderer) nothing is baked and the texture stays blank.
##
## A def is {key, parts: Array[{id, parent, pos, rot, bounds: Rect2, draw: Callable,
## variants: {name: Callable}, tex: shared texture id (optional)}], corpse: {bounds: Rect2, over: {id: {pos, rot}}}}.

## Texels per art unit.
const SS := 2.0
const PAD := 6
const WIDTH := 1024

static var _entries: Dictionary = {} # key -> {rect: Rect2i, bounds: Rect2, draw: Callable, mode: int, def, composite: bool}
static var _size := Vector2i(WIDTH, 64)
static var _tex: ImageTexture
static var _defs: Array = []
static var _laid := false
static var _started := false
static var baked := false


static func defs() -> Array:
	if _defs.is_empty():
		for k in Terminid.KINDS:
			_defs.append(BugRig.rig_def(k))
		_defs.append(ChargerRig.rig_def())
	return _defs


static func texture() -> ImageTexture:
	_layout()
	return _tex


## {rect: Rect2i, bounds: Rect2} of an entry ("<def>/<part>", "<def>/<part>:<variant>", "<def>/corpse").
static func entry(key: String) -> Dictionary:
	_layout()
	return _entries[key]


static func _layout() -> void:
	if _laid:
		return
	_laid = true
	var x := PAD
	var y := PAD
	var row_h := 0
	var list: Array = []
	var seen := {}
	for d in defs():
		for p in d.parts:
			if not p.has("draw"):
				continue
			var tk: String = p.get("tex", p.id) # parts may share one texture (left / right legs)
			if seen.has(d.key + "/" + tk):
				continue
			seen[d.key + "/" + tk] = true
			list.append({"key": "%s/%s" % [d.key, tk], "bounds": p.bounds, "draw": p.draw, "mode": RigArt.Mode.NORMAL})
			for v in p.get("variants", {}):
				list.append({"key": "%s/%s:%s" % [d.key, tk, v], "bounds": p.bounds, "draw": p.variants[v], "mode": RigArt.Mode.WOUND})
		if d.has("corpse"):
			var c: Dictionary = d.corpse
			var parts: Array = d.parts
			var over: Dictionary = c.over
			list.append({"key": "%s/corpse" % d.key, "bounds": c.bounds, "mode": RigArt.Mode.DEAD,
				"draw": func(ci: CanvasItem, t: Transform2D, mode: int) -> void: RigArt.composite(ci, t, parts, over, mode)})
	for e in list:
		var b: Rect2 = e.bounds
		var w := int(ceil(b.size.x * SS))
		var h := int(ceil(b.size.y * SS))
		if x + w + PAD > WIDTH:
			x = PAD
			y += row_h + PAD
			row_h = 0
		e.rect = Rect2i(x, y, w, h)
		x += w + PAD
		row_h = maxi(row_h, h)
		_entries[e.key] = e
	_size = Vector2i(WIDTH, int(ceil((y + row_h + PAD) / 8.0)) * 8)
	var img := Image.create(_size.x, _size.y, false, Image.FORMAT_RGBA8)
	_tex = ImageTexture.create_from_image(img)


## Start the bake (idempotent). Call from anything in the tree; no-op headless.
static func ensure(tree: SceneTree) -> void:
	_layout()
	if _started or tree == null or DisplayServer.get_name() == "headless":
		return
	_started = true
	var n := RigAtlas.new()
	n.name = "RigAtlasBaker"
	tree.root.add_child.call_deferred(n)


func _ready() -> void:
	_bake.call_deferred()


func _bake() -> void:
	var vp := SubViewport.new()
	vp.size = _size
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var painter := Node2D.new()
	vp.add_child(painter)
	painter.draw.connect(func() -> void:
		for k in _entries:
			var e: Dictionary = _entries[k]
			var b: Rect2 = e.bounds
			var r: Rect2i = e.rect
			var t := Transform2D(0.0, Vector2(SS, SS), 0.0, Vector2(r.position) - b.position * SS)
			painter.draw_set_transform_matrix(t)
			(e.draw as Callable).call(painter, t, e.mode))
	add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img != null and not img.is_empty():
		img.generate_mipmaps()
		_tex.set_image(img)
		baked = true
	queue_free()
