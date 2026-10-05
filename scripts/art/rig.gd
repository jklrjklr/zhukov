class_name Rig
extends Node2D
## Cutout rig: a small hierarchy of Sprite2D parts textured from the shared RigAtlas, animated
## only by transforms (position / rotation / scale / modulate) every frame. Parts are positioned
## in art units (set_pos multiplies by RigAtlas.SS: the rig root is scaled art_scale / SS, so
## its children live in texel units). Subclasses (BugRig, ChargerRig) provide the def and the
## procedural animation; this base builds the node tree, swaps wound variants and converts the
## whole rig into one static corpse sprite.

var rdef: Dictionary
var nodes := {}
var corpse_sprite: Sprite2D
var _variant := {}


func setup(d: Dictionary, art_scale: float) -> void:
	rdef = d
	scale = Vector2(art_scale, art_scale) / RigAtlas.SS
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for p in d.parts:
		var n: Node2D
		if p.has("draw"):
			var s := Sprite2D.new()
			var e := RigAtlas.entry("%s/%s" % [d.key, p.get("tex", p.id)])
			s.texture = RigAtlas.texture()
			s.region_enabled = true
			s.region_filter_clip_enabled = true
			s.region_rect = Rect2(e.rect)
			s.centered = false
			s.offset = (e.bounds as Rect2).position * RigAtlas.SS
			n = s
		else:
			n = Node2D.new()
		n.position = (p.pos as Vector2) * RigAtlas.SS
		n.rotation = p.rot
		n.name = p.id
		if p.get("behind", false):
			n.show_behind_parent = true
		var parent: Node = self if p.parent == "" else nodes[p.parent]
		parent.add_child(n)
		nodes[p.id] = n


func part(id: String) -> Node2D:
	return nodes[id]


## Position in art units.
static func place(n: Node2D, v: Vector2) -> void:
	n.position = v * RigAtlas.SS


## Back to the rest pose of every part.
func reset_pose() -> void:
	for p in rdef.parts:
		var n: Node2D = nodes[p.id]
		n.position = (p.pos as Vector2) * RigAtlas.SS
		n.rotation = p.rot
		n.scale = Vector2.ONE


## Swap a part to a baked variant ("" = normal), e.g. wound damage.
func set_variant(id: String, variant: String) -> void:
	if _variant.get(id, "") == variant:
		return
	_variant[id] = variant
	var p: Dictionary = {}
	for q in rdef.parts:
		if q.id == id:
			p = q
			break
	var key := "%s/%s" % [rdef.key, p.get("tex", id)]
	if variant != "":
		key += ":" + variant
	(nodes[id] as Sprite2D).region_rect = Rect2(RigAtlas.entry(key).rect)


## Replace the whole part hierarchy by ONE static corpse sprite (dead enemies cost one quad and no
## per-frame work).
func become_corpse() -> void:
	if corpse_sprite != null:
		return
	for c in get_children():
		c.queue_free()
	nodes.clear()
	modulate = Color.WHITE
	var s := Sprite2D.new()
	var e := RigAtlas.entry("%s/corpse" % rdef.key)
	s.texture = RigAtlas.texture()
	s.region_enabled = true
	s.region_filter_clip_enabled = true
	s.region_rect = Rect2(e.rect)
	s.centered = false
	s.offset = (e.bounds as Rect2).position * RigAtlas.SS
	add_child(s)
	corpse_sprite = s
