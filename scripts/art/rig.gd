class_name Rig
extends Node2D
## Cutout rig: a small hierarchy of RigParts textured from the shared RigAtlas and animated only by
## transforms (position / rotation / scale / modulate) every frame. Parts are positioned in art units
## (set_pos multiplies by RigAtlas.SS: this node is scaled art_scale / SS, so parts live in texel
## units). Nothing is a node or a draw command: every drawn part owns one instance slot in one of
## three shared AtlasBatch layers (legs / shadow, body, head), so ALL enemies of the mission cost
## three draw calls, and an enemy costs no scene-tree nodes for its parts. Layer order replaces the
## per-enemy tree order: all legs under all bodies under all heads.
## Subclasses (BugRig, ChargerRig) provide the def and the procedural animation (which ends with
## commit()); the owner calls flush() every frame (cheap: one transform multiply per part), swaps
## wound variants and converts the whole rig into a baked corpse decal when it has settled.

const LAYERS := 3

var rdef: Dictionary
var nodes := {} # id -> RigPart
var parts: Array[RigPart] = []
## Non-null once the rig was baked into a corpse decal (the rig then owns no instances).
var corpse_sprite: Object
var _drawn: Array[RigPart] = []
var _variant := {}
var _hidden := false
var _col_dirty := true
var _dirty := true
var _last_root := Transform2D()
var _last_mod := Color(0, 0, 0, 0)
var _last_alpha := -1.0
var _art_scale := 1.0
static var _batches: Array[AtlasBatch] = []
static var _holder: Node2D


## The three shared layers. They are created on first use and parented next to the enemies
## (above the other actors) by the first rig that enters a tree; re-created after a mission change.
static func batches() -> Array[AtlasBatch]:
	if _holder != null and is_instance_valid(_holder) and not _holder.is_queued_for_deletion():
		return _batches
	_batches = []
	_holder = Node2D.new()
	_holder.name = "RigBatches"
	_holder.z_index = 1
	for i in LAYERS:
		var b := AtlasBatch.new(RigAtlas.texture(), 1024)
		b.name = "RigLayer%d" % i
		_holder.add_child(b)
		_batches.append(b)
	return _batches


## Create the layers and put them next to the enemies (done at mission start by Warmup, otherwise
## by the first rig that enters a tree).
static func attach(host: Node) -> void:
	Rig.batches()
	if _holder.get_parent() == null and not _holder.has_meta("queued"):
		_holder.set_meta("queued", true)
		host.add_child.call_deferred(_holder)


func _enter_tree() -> void:
	var host: Node = get_parent().get_parent() if get_parent() != null and get_parent().get_parent() != null else get_tree().current_scene
	Rig.attach(host)


func setup(d: Dictionary, art_scale: float) -> void:
	rdef = d
	_art_scale = art_scale
	scale = Vector2(art_scale, art_scale) / RigAtlas.SS
	var bs := Rig.batches()
	var atlas_size := Vector2(RigAtlas.texture().get_size())
	var seen_body := false
	for p in d.parts:
		var rp := RigPart.new()
		rp.id = p.id
		rp.position = (p.pos as Vector2) * RigAtlas.SS
		rp.rotation = p.rot
		rp.parent = null if p.parent == "" else nodes[p.parent]
		if p.has("draw"):
			rp.drawn = true
			rp.tex_key = "%s/%s" % [d.key, p.get("tex", p.id)]
			var e := RigAtlas.entry(rp.tex_key)
			var r := Rect2(e.rect)
			rp.quad = Transform2D(Vector2(r.size.x, 0), Vector2(0, r.size.y), (e.bounds as Rect2).position * RigAtlas.SS)
			rp.uv = _uv(r, atlas_size)
			rp.layer = _layer_of(rp, p, seen_body)
			rp.slot = bs[rp.layer].alloc()
			bs[rp.layer].set_uv(rp.slot, rp.uv)
			_drawn.append(rp)
		elif p.id == "body":
			seen_body = true
		nodes[p.id] = rp
		parts.append(rp)
	tree_exiting.connect(_release_all)
	visibility_changed.connect(_on_visibility)


static func _uv(r: Rect2, atlas_size: Vector2) -> Color:
	return Color(r.position.x / atlas_size.x, r.position.y / atlas_size.y, r.size.x / atlas_size.x, r.size.y / atlas_size.y)


## Layer 0: legs / things under the body, 2: head and what hangs on it, 1: the rest.
func _layer_of(rp: RigPart, p: Dictionary, seen_body: bool) -> int:
	if p.has("layer"):
		return p.layer
	if p.get("behind", false):
		return 1
	var a: RigPart = rp.parent
	while a != null:
		if a.id == "head":
			return 2
		a = a.parent
	if rp.id == "head":
		return 2
	if rp.parent == null and not seen_body:
		return 0
	return 1


func part(id: String) -> RigPart:
	return nodes[id]


## Position in art units.
static func place(n: RigPart, v: Vector2) -> void:
	n.position = v * RigAtlas.SS


## Back to the rest pose of every part.
func reset_pose() -> void:
	for p in rdef.parts:
		var n: RigPart = nodes[p.id]
		n.position = (p.pos as Vector2) * RigAtlas.SS
		n.rotation = p.rot
		n.scale = Vector2.ONE
	commit()


## Swap a part to a baked variant ("" = normal), e.g. wound damage.
func set_variant(id: String, variant: String) -> void:
	if _variant.get(id, "") == variant:
		return
	_variant[id] = variant
	var rp: RigPart = nodes[id]
	var key := rp.tex_key
	if variant != "":
		key += ":" + variant
	rp.uv = _uv(Rect2(RigAtlas.entry(key).rect), Vector2(RigAtlas.texture().get_size()))
	if rp.slot >= 0 and corpse_sprite == null:
		Rig.batches()[rp.layer].set_uv(rp.slot, rp.uv)


## The pose changed (called at the end of animate()): the next flush recomposes every part.
func commit() -> void:
	_dirty = true


## Parts that the rig's animation never touches are composed once (their local transform is cached).
func fix_static(animated: Array) -> void:
	for p in parts:
		p.fixed = not animated.has(p)
		if p.fixed:
			p.local = Transform2D(p.rotation, p.scale, 0.0, p.position)


## Write the world transforms (and tint) into the batch slots. Cheap enough to run every frame:
## after an animation step every part is recomposed (parent chain x local x quad); when only the
## body moved, the stored instance transforms are shifted by the root's change (one multiply each).
func flush() -> void:
	if _hidden or corpse_sprite != null:
		return
	var root := global_transform
	var bs := _batches
	var par := get_parent() as CanvasItem
	var alpha := par.modulate.a if par != null else 1.0
	if _col_dirty or modulate != _last_mod or alpha != _last_alpha:
		_last_mod = modulate
		_last_alpha = alpha
		_col_dirty = false
		var m := Color(modulate.r, modulate.g, modulate.b, modulate.a * alpha)
		for p in _drawn:
			bs[p.layer].set_color(p.slot, m * p.self_modulate)
	if _dirty:
		_dirty = false
		for p in parts:
			var loc: Transform2D = p.local if p.fixed else Transform2D(p.rotation, p.scale, 0.0, p.position)
			var ch: Transform2D = (root if p.parent == null else p.parent.world) * loc
			p.world = ch
			if p.drawn:
				var t: Transform2D = ch * p.quad
				p.inst = t
				if p.visible:
					bs[p.layer].set_xf(p.slot, t)
				else:
					bs[p.layer].hide_slot(p.slot)
	elif root != _last_root:
		var delta := root * _last_root.affine_inverse()
		for p in _drawn:
			if p.visible:
				var t: Transform2D = delta * p.inst
				p.inst = t
				bs[p.layer].set_xf(p.slot, t)
	_last_root = root


## Mark colours dirty (a part's self_modulate / visible changed).
func touch_colors() -> void:
	_col_dirty = true


func _on_visibility() -> void:
	var h := not is_visible_in_tree()
	if h == _hidden:
		return
	_hidden = h
	if corpse_sprite != null:
		return
	if h:
		var bs := Rig.batches()
		for p in _drawn:
			bs[p.layer].hide_slot(p.slot)
	else:
		_col_dirty = true
		_dirty = true
		flush()


func _release_all() -> void:
	if _drawn.is_empty() or _batches.is_empty():
		return
	for p in _drawn:
		if p.slot >= 0 and is_instance_valid(_batches[p.layer]):
			_batches[p.layer].release(p.slot)
		p.slot = -1
	_drawn.clear()


## Bake the rig as ONE static corpse picture into the decal layer and give the slots back
## (dead enemies cost nothing per frame and no draw call of their own).
func become_corpse() -> void:
	if corpse_sprite != null:
		return
	var b: Rect2 = (rdef.corpse.bounds as Rect2)
	var ext := 0.0
	for c in [b.position, b.end, Vector2(b.position.x, b.end.y), Vector2(b.end.x, b.position.y)]:
		ext = maxf(ext, (c as Vector2).length())
	_hidden = false
	Fx.corpse(self, "%s/corpse" % rdef.key, global_transform, ext * _art_scale * 1.05)
	_release_all()
	corpse_sprite = self
	modulate = Color.WHITE
