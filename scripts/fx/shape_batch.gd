class_name ShapeBatch
extends MultiMeshInstance2D
## Analytic 2D shapes (discs, soft discs, rings, arcs, flashes, rectangles / lines) in ONE MultiMesh
## = ONE draw call, instead of one canvas command per circle / arc / polygon (those never batch).
## The fragment shader evaluates the shape from the instance's custom data, so no texture and no
## atlas are needed. Used by the particle layers, projectiles and the enemy overlays: the owner calls
## begin(), then disc() / ring() / line() ..., then end(), once per frame (or per physics tick).
## Coordinates are canvas (world) px: keep this node at the origin without a transform.

enum K { DISC, SOFT, RING, FLASH, RECT, ARC }

const SHADER := """
shader_type canvas_item;
render_mode %s;
varying flat vec4 v_shape;
void vertex() {
	v_shape = INSTANCE_CUSTOM;
}
void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float d = length(q);
	float aa = max(fwidth(d), 0.001);
	float k = v_shape.x;
	float disc = 1.0 - smoothstep(1.0 - aa, 1.0, d);
	if (k < 0.5) {
		COLOR.a *= disc;
	} else if (k < 1.5) {
		COLOR.a *= clamp(1.0 - d, 0.0, 1.0);
	} else if (k < 2.5) {
		float t = v_shape.y;
		COLOR.a *= disc * smoothstep(1.0 - t - aa, 1.0 - t, d);
	} else if (k < 3.5) {
		float a = COLOR.a * disc;
		float inner = 1.0 - smoothstep(0.5 - aa, 0.5, d);
		vec3 c2 = vec3(1.0, 1.0, 0.9);
		float oa = a;
		float ia = COLOR.a * inner;
		float ra = ia + oa * (1.0 - ia);
		vec3 rc = (c2 * ia + COLOR.rgb * oa * (1.0 - ia)) / max(ra, 0.0001);
		COLOR = vec4(rc, ra);
	} else if (k > 4.5) {
		float t = v_shape.y;
		float ang = mod(atan(q.y, q.x) - v_shape.z + 6.2831853, 6.2831853);
		COLOR.a *= disc * smoothstep(1.0 - t - aa, 1.0 - t, d) * step(ang, v_shape.w);
	}
}
"""

static var _shaders := {}

var _mm: MultiMesh
var _n := 0
var _cap := 0
## Instance data (16 floats each: transform in 8, colour 4, custom 4), uploaded once in end().
var _buf := PackedFloat32Array()
var _prev := 0


func _init(cap := 512, unshaded := false) -> void:
	_cap = cap
	_buf.resize(cap * 16)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_2D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = QuadMesh2D.centered()
	_mm.instance_count = cap
	_mm.custom_aabb = AABB(Vector3(-1.0e6, -1.0e6, -1.0), Vector3(2.0e6, 2.0e6, 2.0)) # never culled by a stale / identity bound
	multimesh = _mm
	var key := "unshaded" if unshaded else "lit"
	if not _shaders.has(key):
		var sh := Shader.new()
		sh.code = SHADER % ("unshaded" if unshaded else "blend_mix")
		_shaders[key] = sh
	var m := ShaderMaterial.new()
	m.shader = _shaders[key]
	material = m
	visible = false


func begin() -> void:
	_n = 0


## Rows the previous frame used and this one did not are collapsed. visible_instance_count is never
## touched: every change of it costs a whole-buffer rebuild in the renderer (+20 ms / frame measured).
func end() -> void:
	for i in range(_n, _prev):
		var o := i * 16
		_buf[o] = 0.0
		_buf[o + 1] = 0.0
		_buf[o + 3] = 0.0
		_buf[o + 4] = 0.0
		_buf[o + 5] = 0.0
		_buf[o + 7] = 0.0
	if _n > 0 or _prev > 0:
		_mm.buffer = _buf
	_prev = _n
	visible = _n > 0


func count() -> int:
	return _n


func is_full() -> bool:
	return _n >= _cap


func _put(xf: Transform2D, col: Color, kind: float, p1 := 0.0, p2 := 0.0, p3 := 0.0) -> void:
	if _n >= _cap:
		return
	var o := _n * 16
	var a := xf.x
	var b := xf.y
	var c := xf.origin
	_buf[o] = a.x
	_buf[o + 1] = b.x
	_buf[o + 3] = c.x
	_buf[o + 4] = a.y
	_buf[o + 5] = b.y
	_buf[o + 7] = c.y
	_buf[o + 8] = col.r
	_buf[o + 9] = col.g
	_buf[o + 10] = col.b
	_buf[o + 11] = col.a
	_buf[o + 12] = kind
	_buf[o + 13] = p1
	_buf[o + 14] = p2
	_buf[o + 15] = p3
	_n += 1


func disc(p: Vector2, r: float, col: Color) -> void:
	_put(Transform2D(Vector2(r + 0.6, 0), Vector2(0, r + 0.6), p), col, K.DISC)


func soft(p: Vector2, r: float, col: Color) -> void:
	_put(Transform2D(Vector2(r, 0), Vector2(0, r), p), col, K.SOFT)


## Ring centred on radius r, `width` thick (draw_arc full circle).
func ring(p: Vector2, r: float, width: float, col: Color) -> void:
	var o := r + width * 0.5 + 0.6
	_put(Transform2D(Vector2(o, 0), Vector2(0, o), p), col, K.RING, minf((width + 0.6) / o, 1.0))


## Arc from angle a0 sweeping `sweep` rad (clockwise on screen like draw_arc), `width` thick.
func arc(p: Vector2, r: float, a0: float, sweep: float, width: float, col: Color) -> void:
	var o := r + width * 0.5 + 0.6
	_put(Transform2D(Vector2(o, 0), Vector2(0, o), p), col, K.ARC, minf((width + 0.6) / o, 1.0), a0, clampf(sweep, 0.0, TAU))


## Two-tone flash: colour disc with a smaller bright core.
func flash(p: Vector2, r: float, col: Color) -> void:
	_put(Transform2D(Vector2(r + 0.6, 0), Vector2(0, r + 0.6), p), col, K.FLASH)


func rect(center: Vector2, size: Vector2, rot: float, col: Color) -> void:
	_put(Transform2D(rot, size * 0.5, 0.0, center), col, K.RECT)


## Axis-aligned rectangle from its top-left corner.
func box(pos: Vector2, size: Vector2, col: Color) -> void:
	_put(Transform2D(Vector2(size.x * 0.5, 0), Vector2(0, size.y * 0.5), pos + size * 0.5), col, K.RECT)


func line(a: Vector2, b: Vector2, width: float, col: Color) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.01:
		return
	_put(Transform2D(d.angle(), Vector2(l * 0.5, width * 0.5), 0.0, (a + b) * 0.5), col, K.RECT)
