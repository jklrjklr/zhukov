class_name AtlasBatch
extends MultiMeshInstance2D
## One MultiMesh of textured quads from a single atlas = one draw call for every instance in it
## (the enemy rig layers, UI icons ...). Each instance has a Transform2D mapping the unit quad onto
## its place (offset / size / rotation of the art included), an instance colour (tint, alpha) and
## the normalised atlas rect in the custom data. Slots are allocated / released by the users;
## unused ones are collapsed to a degenerate quad. The buffer doubles when full.
## Keep the node at the canvas origin without a transform (instance transforms are world).

const SHADER := """
shader_type canvas_item;
void vertex() {
	UV = INSTANCE_CUSTOM.xy + UV * INSTANCE_CUSTOM.zw;
}
"""
static var _shader: Shader
const ZERO := Transform2D(Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)

var _mm: MultiMesh
var _cap := 0
var _hi := 0
var _free: Array[int] = []


func _init(tex: Texture2D, cap := 512) -> void:
	_cap = cap
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_2D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = QuadMesh2D.corner()
	_mm.instance_count = cap
	_mm.custom_aabb = AABB(Vector3(-1.0e6, -1.0e6, -1.0), Vector3(2.0e6, 2.0e6, 2.0)) # never culled by a stale / identity bound
	_mm.visible_instance_count = 0
	multimesh = _mm
	texture = tex
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	material = m


func alloc() -> int:
	if not _free.is_empty():
		return _free.pop_back()
	if _hi >= _cap:
		_grow()
	var i := _hi
	_hi += 1
	_mm.visible_instance_count = _hi
	_mm.set_instance_transform_2d(i, ZERO)
	return i


func release(i: int) -> void:
	_mm.set_instance_transform_2d(i, ZERO)
	_free.append(i)


func hide_slot(i: int) -> void:
	_mm.set_instance_transform_2d(i, ZERO)


func set_xf(i: int, xf: Transform2D) -> void:
	_mm.set_instance_transform_2d(i, xf)


func set_color(i: int, c: Color) -> void:
	_mm.set_instance_color(i, c)


func set_uv(i: int, r: Color) -> void:
	_mm.set_instance_custom_data(i, r)


## Per-frame mode (overlays): frame_begin(), frame_push() ..., frame_end(); slots 0..n-1 are rewritten.
var _fn := 0


func frame_begin() -> void:
	_fn = 0


func frame_push(xf: Transform2D, c: Color, uv_rect: Color) -> void:
	if _fn >= _cap:
		_grow()
	_mm.set_instance_transform_2d(_fn, xf)
	_mm.set_instance_color(_fn, c)
	_mm.set_instance_custom_data(_fn, uv_rect)
	_fn += 1


func frame_end() -> void:
	_hi = _fn
	_mm.visible_instance_count = _fn
	visible = _fn > 0


func used() -> int:
	return _hi - _free.size()


func _grow() -> void:
	var old := _mm.buffer
	_cap *= 2
	_mm.instance_count = _cap
	if not old.is_empty():
		old.resize(_cap * 16)
		_mm.buffer = old
	_mm.visible_instance_count = _hi
