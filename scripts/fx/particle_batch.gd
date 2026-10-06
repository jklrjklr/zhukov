class_name ParticleBatch
extends MultiMeshInstance2D
## GPU-animated particles: ONE draw call, and no per-particle work on the CPU after the spawn.
## A spawn writes 4 RGBA32F texels (one row of the data texture); the vertex shader reads its row by
## INSTANCE_ID and derives the position (initial velocity with exponential drag), size, spin and
## fade from the age (uniform `now` - spawn time), so a particle costs the CPU one Image write when
## it appears and nothing while it lives. Slots are a ring: when full the oldest is overwritten.
## Kinds: DOT (hard / soft disc), SPARK (streak along its velocity), CHIP (spinning rectangle),
## RING (expanding ring), FLASH (two-tone disc).
## Row layout:  0: p0.xy v0.xy | 1: t0 life drag kind | 2: s0 s1 width seed | 3: r g b a

enum Kind { DOT, SOFT, SPARK, CHIP, RING, FLASH }

const SHADER := """
shader_type canvas_item;
render_mode %s;
uniform sampler2D data : filter_nearest, repeat_disable;
uniform float now = 0.0;
varying flat vec4 v_col;
varying flat vec4 v_shape;

float hash(float x) { return fract(sin(x * 91.3458) * 47453.5453); }

void vertex() {
	int row = INSTANCE_ID;
	vec4 a = texelFetch(data, ivec2(0, row), 0);
	vec4 b = texelFetch(data, ivec2(1, row), 0);
	vec4 c = texelFetch(data, ivec2(2, row), 0);
	vec4 col = texelFetch(data, ivec2(3, row), 0);
	float dt = now - b.x;
	float life = b.y;
	v_shape = vec4(-1.0);
	if (dt < 0.0 || dt >= life || life <= 0.0) {
		VERTEX = vec2(0.0);
	} else {
	float k = dt / life;
	float kind = b.w;
	float drag = b.z;
	vec2 v0 = a.zw;
	vec2 off = drag > 0.0 ? v0 * ((1.0 - exp(-drag * dt)) / drag) : v0 * dt;
	vec2 p = a.xy + off;
	vec2 q = VERTEX;
	float alpha = col.a;
	vec2 pos;
	float thick = 0.0;
	if (kind < 1.5) { // DOT hard (0) / soft (1)
		float r = mix(c.x, c.y, k);
		alpha *= 1.0 - k;
		pos = p + q * (r + 0.6);
	} else if (kind < 2.5) { // SPARK: streak from p back along the velocity direction
		vec2 v = v0 * exp(-drag * dt);
		vec2 dir = length(v) > 0.001 ? normalize(v) : vec2(1.0, 0.0);
		float len = c.x * (1.0 - k * 0.6);
		alpha *= 1.0 - k;
		vec2 mid = p - dir * len * 0.5;
		pos = mid + dir * (q.x * len * 0.5) + vec2(-dir.y, dir.x) * (q.y * c.y * 0.5);
	} else if (kind < 3.5) { // CHIP
		float ang = hash(c.w) * 6.2831853 + (hash(c.w + 7.0) - 0.5) * 24.0 * dt;
		float cs = cos(ang);
		float sn = sin(ang);
		vec2 l = q * vec2(c.x, c.y) * 0.5;
		alpha *= 1.0 - k * k;
		pos = p + vec2(l.x * cs - l.y * sn, l.x * sn + l.y * cs);
	} else if (kind < 4.5) { // RING
		float e = 1.0 - pow(1.0 - k, 3.0);
		float r = mix(c.x, c.y, e);
		float w = max(c.z * (1.0 - k * 0.7), 1.0);
		float o = r + w * 0.5 + 0.6;
		alpha *= 1.0 - k;
		thick = min((w + 0.6) / o, 1.0);
		pos = p + q * o;
	} else { // FLASH
		float r = mix(c.x, c.y, sqrt(k));
		alpha *= 1.0 - k;
		pos = p + q * (r + 0.6);
	}
	VERTEX = pos;
	v_col = vec4(col.rgb, alpha);
	v_shape = vec4(kind, thick, 0.0, 1.0);
	}
}

void fragment() {
	if (v_shape.w < 0.0) {
		discard;
	}
	vec2 q = UV * 2.0 - 1.0;
	float d = length(q);
	float aa = max(fwidth(d), 0.001);
	float disc = 1.0 - smoothstep(1.0 - aa, 1.0, d);
	float kind = v_shape.x;
	vec4 col = v_col;
	if (kind < 0.5) {
		col.a *= disc;
	} else if (kind < 1.5) {
		col.a *= clamp(1.0 - d, 0.0, 1.0);
	} else if (kind < 3.5) {
		// SPARK / CHIP: plain rectangle
	} else if (kind < 4.5) {
		float t = v_shape.y;
		col.a *= disc * smoothstep(1.0 - t - aa, 1.0 - t, d);
	} else {
		float inner = 1.0 - smoothstep(0.5 - aa, 0.5, d);
		float oa = col.a * disc;
		float ia = col.a * inner;
		float ra = ia + oa * (1.0 - ia);
		vec3 c2 = vec3(1.0, 1.0, 0.9);
		col.rgb = (c2 * ia + col.rgb * oa * (1.0 - ia)) / max(ra, 0.0001);
		col.a = ra;
	}
	COLOR = col;
}
"""

static var _shaders := {}

var cap := 512
var _mm: MultiMesh
var _img: Image
var _tex: ImageTexture
var _mat: ShaderMaterial
var _cursor := 0
var _clock := 0.0
var _dirty := false
var _expire := PackedFloat32Array()


func _init(capacity := 512, unshaded := false) -> void:
	cap = capacity
	_expire.resize(cap)
	_img = Image.create(4, cap, false, Image.FORMAT_RGBAF)
	_tex = ImageTexture.create_from_image(_img)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_2D
	_mm.mesh = QuadMesh2D.centered()
	_mm.instance_count = cap
	_mm.custom_aabb = AABB(Vector3(-1.0e6, -1.0e6, -1.0), Vector3(2.0e6, 2.0e6, 2.0)) # never culled by a stale / identity bound
	for i in cap:
		_mm.set_instance_transform_2d(i, Transform2D.IDENTITY) # geometry is computed in the vertex shader
	multimesh = _mm
	var key := "unshaded" if unshaded else "lit"
	if not _shaders.has(key):
		var sh := Shader.new()
		sh.code = SHADER % ("unshaded" if unshaded else "blend_mix")
		_shaders[key] = sh
	_mat = ShaderMaterial.new()
	_mat.shader = _shaders[key]
	_mat.set_shader_parameter("data", _tex)
	_mat.set_shader_parameter("now", 0.0)
	material = _mat


## Advance the clock (call every frame with the game delta; paused game = frozen particles).
func tick(delta: float) -> void:
	_clock += delta
	_mat.set_shader_parameter("now", _clock)
	if _dirty:
		_dirty = false
		_tex.update(_img)


func now() -> float:
	return _clock


func live_count() -> int:
	var n := 0
	for i in cap:
		if _expire[i] > _clock:
			n += 1
	return n


func _spawn(kind: int, p: Vector2, v: Vector2, life: float, drag: float, s0: float, s1: float, w: float, col: Color) -> void:
	var row := _cursor
	_cursor = (_cursor + 1) % cap
	_expire[row] = _clock + life
	_img.set_pixel(0, row, Color(p.x, p.y, v.x, v.y))
	_img.set_pixel(1, row, Color(_clock, life, drag, kind))
	_img.set_pixel(2, row, Color(s0, s1, w, randf() * 50.0))
	_img.set_pixel(3, row, col)
	_dirty = true


func dot(pos: Vector2, vel: Vector2, life: float, s0: float, s1: float, col: Color, drag: float, soft: bool) -> void:
	_spawn(Kind.SOFT if soft else Kind.DOT, pos, vel, life, drag, s0, s1, 0.0, col)


func streak(pos: Vector2, vel: Vector2, life: float, length: float, width: float, col: Color, drag: float) -> void:
	_spawn(Kind.SPARK, pos, vel, life, drag, length, width, 0.0, col)


func chip(pos: Vector2, vel: Vector2, life: float, size: Vector2, col: Color, drag: float) -> void:
	_spawn(Kind.CHIP, pos, vel, life, drag, size.x, size.y, 0.0, col)


func ring(pos: Vector2, r0: float, r1: float, life: float, width: float, col: Color) -> void:
	_spawn(Kind.RING, pos, Vector2.ZERO, life, 0.0, r0, r1, width, col)


func flash(pos: Vector2, r0: float, r1: float, life: float, col: Color) -> void:
	_spawn(Kind.FLASH, pos, Vector2.ZERO, life, 0.0, r0, r1, 0.0, col)
