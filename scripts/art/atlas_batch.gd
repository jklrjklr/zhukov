class_name AtlasBatch
extends MultiMeshInstance2D
## One MultiMesh of textured quads from a single atlas = one draw call for every instance in it
## (the enemy rig layers, UI badges ...). Each instance has a Transform2D mapping the unit quad onto
## its place (offset / size / rotation of the art included), an instance colour (tint, alpha) and
## the normalised atlas rect in the custom data. The instance data lives in ONE PackedFloat32Array
## (16 floats per instance: 2D transform in 8, colour 4, custom 4) that users write with plain
## stores (a native call per part per frame is several times slower) and that is uploaded once per
## frame, after every user has run (late process priority). Slots are allocated / released by the
## users; unused ones are collapsed to a degenerate quad. The buffer doubles when full.
## Keep the node at the canvas origin without a transform (instance transforms are world).

const SHADER := """
shader_type canvas_item;
void vertex() {
	UV = INSTANCE_CUSTOM.xy + UV * INSTANCE_CUSTOM.zw;
}
"""
const STRIDE := 16
static var _shader: Shader

var _mm: MultiMesh
var _cap := 0
var _hi := 0
var _free: Array[int] = []
var _buf := PackedFloat32Array()
var _dirty := false
var _fn := 0


func _init(tex: Texture2D, cap := 512) -> void:
	_cap = cap
	_buf.resize(cap * STRIDE)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_2D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = QuadMesh2D.corner()
	_mm.instance_count = cap
	_mm.custom_aabb = AABB(Vector3(-1.0e6, -1.0e6, -1.0), Vector3(2.0e6, 2.0e6, 2.0)) # never culled by a stale bound
	# NOTE: visible_instance_count is never touched: every change of it costs a whole-buffer rebuild in
	# the renderer (measured +20 ms / frame on desktop GL). Unused slots stay degenerate (zero scale).
	multimesh = _mm
	texture = tex
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	material = m
	process_priority = 1000 # after every enemy / overlay has written its instances this frame


func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		_mm.buffer = _buf


func alloc() -> int:
	if not _free.is_empty():
		return _free.pop_back()
	if _hi >= _cap:
		_grow()
	var i := _hi
	_hi += 1
	return i


func release(i: int) -> void:
	hide_slot(i)
	_free.append(i)


func hide_slot(i: int) -> void:
	var o := i * STRIDE
	_buf[o] = 0.0
	_buf[o + 1] = 0.0
	_buf[o + 3] = 0.0
	_buf[o + 4] = 0.0
	_buf[o + 5] = 0.0
	_buf[o + 7] = 0.0
	_dirty = true


func set_xf(i: int, xf: Transform2D) -> void:
	var o := i * STRIDE
	var a := xf.x
	var b := xf.y
	var c := xf.origin
	_buf[o] = a.x
	_buf[o + 1] = b.x
	_buf[o + 3] = c.x
	_buf[o + 4] = a.y
	_buf[o + 5] = b.y
	_buf[o + 7] = c.y
	_dirty = true


func set_color(i: int, c: Color) -> void:
	var o := i * STRIDE + 8
	_buf[o] = c.r
	_buf[o + 1] = c.g
	_buf[o + 2] = c.b
	_buf[o + 3] = c.a
	_dirty = true


func set_uv(i: int, r: Color) -> void:
	var o := i * STRIDE + 12
	_buf[o] = r.r
	_buf[o + 1] = r.g
	_buf[o + 2] = r.b
	_buf[o + 3] = r.a
	_dirty = true


## Per-frame mode (overlays): frame_begin(), frame_push() ..., frame_end(); slots 0..n-1 are rewritten.
func frame_begin() -> void:
	_fn = 0


func frame_push(xf: Transform2D, c: Color, uv_rect: Color) -> void:
	if _fn >= _cap:
		_grow()
	set_xf(_fn, xf)
	set_color(_fn, c)
	set_uv(_fn, uv_rect)
	_fn += 1


func frame_end() -> void:
	for i in range(_fn, _hi):
		hide_slot(i) # rows the previous frame used and this one did not
	_hi = _fn
	visible = _fn > 0


func used() -> int:
	return _hi - _free.size()


func _grow() -> void:
	_cap *= 2
	_buf.resize(_cap * STRIDE)
	_mm.instance_count = _cap
	_mm.buffer = _buf
