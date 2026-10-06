class_name RigPart
extends RefCounted
## One bone / sprite of a cutout rig. A plain data object (the old Sprite2D / Node2D per part is
## gone): the procedural animation writes position / rotation / scale / visible / self_modulate in
## rig texel units, and Rig composes the transforms into MultiMesh instance slots.

var id := ""
var parent: RigPart
var position := Vector2.ZERO
var rotation := 0.0
var scale := Vector2.ONE
var visible := true
var self_modulate := Color.WHITE
## Drawn parts own a slot in an AtlasBatch layer; plain bones only carry a transform.
var drawn := false
var layer := 1
var slot := -1
var tex_key := ""
## Unit quad -> part-local texel rect (offset / size of the art in texels).
var quad := Transform2D()
## Normalised atlas rect (x, y, w, h) of the current texture variant.
var uv := Color(0, 0, 0, 0)
## Composed transform in rig space, and the same with the quad (what the instance uses).
var chain := Transform2D()
var rel := Transform2D()
