class_name Vision
extends Node2D
## Player sight cone, three render modes (Game.vision_mode, pause-menu toggle, saved):
## - QUAD (default, all platforms, no 2D lights / CanvasModulate / occluders): one dark quad with a
##   shader. The RAYS ray fan is uploaded each cast as a 1-D distance texture; the shader works out
##   cone, wall-limited range and soft edges per pixel and shades explored areas lighter (memory fog,
##   a low-res explored grid). One draw call.
## - RAYS: the same ray fan covered by a dark triangle-fan polygon outside the sight cone (one draw call).
## - LIGHT (comparison): a cone-shaped PointLight2D on the head; a CanvasModulate darkens the rest.
## World geometry (collision layer 1) blocks sight; enemies/dummies (layer 2) do not.
## Nodes in group "concealable" (enemies, dummies) fade out when not in sight; close
## ones stay faintly visible ("you sense them"). Hidden ones are not drawn at all.
## Aiming down sights narrows the cone to the weapon's ads_fov.
## Child of Player (follows it), but draws in world space above the world and
## below the player (z_index).

const PX := Firearm.PX_PER_M
## Rays across the cone (recast every other physics tick).
const RAYS := 64
## px; far edge of the darkness fan (must cover the screen at the widest zoom).
const FAR := 9000.0
## Collision layer that blocks sight (world geometry).
const SIGHT_MASK := 1
const DARK := Color(0.02, 0.03, 0.04, 0.8)
## LIGHT mode: ambient darkness and cone texture size.
const AMBIENT := Color(0.2, 0.22, 0.25)
const TEX_SIZE := 320
## Light mask bit used only for the player's own body light.
const SELF_MASK := 2

enum Mode { AUTO, LIGHT, RAYS, QUAD }
## Draw order: above world, enemies, props; below projectiles and the player.
const Z := 10

## Full sight angle in degrees.
@export var fov_degrees := 120.0
## m, how far the cone reaches.
@export var view_distance := 24.0
## m, unseen concealables start fading in at this distance...
@export var sense_start := 7.0
## m, ...and reach sense_alpha here.
@export var sense_full := 3.0
@export_range(0.0, 1.0) var sense_alpha := 0.55
## AUTO = follow Game.vision_mode (the pause-menu setting); anything else forces that mode.
@export var mode := Mode.AUTO

var _player: CharacterBody2D
var _weapon: Firearm
## Visible end point of each ray (global), first to last across the cone.
var _ends := PackedVector2Array()
var _origin := Vector2.ZERO
var _forward := Vector2.UP
var _half_fov := 0.0
var _tick := 0
var _mode := -1
var _cone: PointLight2D
var _light_nodes: Array[Node] = []
var _ray_img: Image
var _ray_tex: ImageTexture
var _quad_mat: ShaderMaterial
var _quad_center := Vector2(INF, INF)
var _cast_origin := Vector2.ZERO
var _cast_forward := Vector2.UP
var _cast_half := 0.0
var _explored: PackedByteArray
var _explored_img: Image
var _explored_tex: ImageTexture
var _explored_dirty := false
var _hip_tex: ImageTexture
var _ads_tex: ImageTexture


func _ready() -> void:
	_player = get_parent()
	_weapon = _player.get_node("Firearm")
	top_level = true
	z_as_relative = false
	z_index = Z
	_apply_mode.call_deferred()
	Game.vision_mode_changed.connect(_apply_mode)


func _wanted_mode() -> int:
	return Game.vision_mode if mode == Mode.AUTO else mode


## (Re)build the active mode; also used by the runtime toggle. Tears the other modes down.
func _apply_mode() -> void:
	var want := _wanted_mode()
	if want == _mode:
		return
	if _mode == Mode.LIGHT:
		_teardown_light()
	_mode = want
	material = null
	_ends.clear()
	_quad_center = Vector2(INF, INF)
	if _mode == Mode.LIGHT:
		_setup_light()
	elif _mode == Mode.QUAD:
		_setup_quad()
	queue_redraw()


## Shadow caster for a prop (LIGHT mode; null while Game.shadows_enabled is off). Only edges facing away from the light cast,
## so the prop's own top stays lit and its shadow starts behind it.
static func add_occluder(body: Node2D, points: PackedVector2Array) -> LightOccluder2D:
	if not Game.shadows_enabled:
		return null # no shadows: the cone is a plain cone (sight itself is still raycast)
	var poly := OccluderPolygon2D.new()
	poly.polygon = points
	poly.cull_mode = OccluderPolygon2D.CULL_COUNTER_CLOCKWISE
	var occ := LightOccluder2D.new()
	occ.occluder = poly
	body.add_child(occ)
	return occ


static func rect_points(size: Vector2) -> PackedVector2Array:
	var h := size / 2.0
	return PackedVector2Array([Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)])


static func circle_points(r: float, n := 10) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		pts.append(Vector2.from_angle(TAU * i / n) * r)
	return pts


func _setup_light() -> void:
	var dark := CanvasModulate.new()
	dark.color = AMBIENT
	get_tree().current_scene.add_child(dark)
	_light_nodes.append(dark)
	_hip_tex = _build_texture(fov_degrees)
	_ads_tex = _build_texture(_weapon.stats.ads_fov)
	_cone = PointLight2D.new()
	_cone.texture = _hip_tex
	_cone.texture_scale = view_distance * PX / (TEX_SIZE / 2.0)
	_cone.shadow_enabled = Game.shadows_enabled
	_cone.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	_cone.shadow_filter_smooth = 1.5
	_cone.energy = 0.85
	_cone.range_item_cull_mask = 1
	_player.add_child(_cone)
	_light_nodes.append(_cone)
	# The cone's apex is on the head, so give the body its own small light
	# that only affects the player (light mask bit 2).
	for ci in [_player] + _player.get_children():
		if ci is CanvasItem and ci != self:
			ci.light_mask = SELF_MASK
	var grad := GradientTexture2D.new()
	grad.fill = GradientTexture2D.FILL_RADIAL
	grad.fill_from = Vector2(0.5, 0.5)
	grad.fill_to = Vector2(1.0, 0.5)
	grad.width = 64
	grad.height = 64
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.7, Color(1, 1, 1, 1))
	grad.gradient = g
	var self_light := PointLight2D.new()
	self_light.texture = grad
	self_light.texture_scale = 1.8
	self_light.energy = 0.85
	self_light.range_item_cull_mask = SELF_MASK
	_player.add_child(self_light)
	_light_nodes.append(self_light)


func _teardown_light() -> void:
	for n in _light_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_light_nodes.clear()
	_cone = null
	for ci in [_player] + _player.get_children():
		if ci is CanvasItem and ci != self:
			ci.light_mask = 1


func _build_texture(fov: float) -> ImageTexture:
	var half_fov := deg_to_rad(fov / 2.0)
	var edge := deg_to_rad(5.0)
	var c := TEX_SIZE / 2.0
	var data := PackedByteArray()
	data.resize(TEX_SIZE * TEX_SIZE * 2)
	var i := 0
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var d := Vector2(x + 0.5 - c, y + 0.5 - c) / c
			var r := d.length()
			var ang := absf(Vector2.UP.angle_to(d))
			var cone := 1.0 - smoothstep(half_fov - edge, half_fov + edge, ang)
			var fade := 1.0 - smoothstep(0.75, 1.0, r)
			data[i] = 255
			data[i + 1] = int(cone * fade * 255.0)
			i += 2
	return ImageTexture.create_from_image(Image.create_from_data(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_LA8, data))


func _physics_process(delta: float) -> void:
	global_position = Vector2.ZERO
	global_rotation = 0.0
	_origin = _player.global_position
	_forward = Vector2.UP.rotated(_player.global_rotation)
	_half_fov = deg_to_rad(lerpf(fov_degrees, _weapon.stats.ads_fov, _weapon.ads_amount()) / 2.0)
	_tick += 1
	if _wanted_mode() != _mode:
		_apply_mode()
	if _mode == Mode.LIGHT:
		if _cone:
			_cone.texture = _ads_tex if _weapon.ads_amount() >= 0.5 else _hip_tex
	elif _tick % 2 == 0 or _ends.is_empty():
		_cast_rays()
		if _mode == Mode.QUAD:
			_update_quad()
		else:
			queue_redraw()
	_update_concealment(delta)


func _cast_rays() -> void:
	var space := get_world_2d().direct_space_state
	var reach := view_distance * PX
	_cast_origin = _origin
	_cast_forward = _forward
	_cast_half = _half_fov
	_ends.resize(RAYS + 1)
	for i in RAYS + 1:
		var a := lerpf(-_half_fov, _half_fov, float(i) / RAYS)
		var to := _origin + _forward.rotated(a) * reach
		var q := PhysicsRayQueryParameters2D.create(_origin, to, SIGHT_MASK)
		q.exclude = [_player.get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			_ends[i] = to
		else:
			# Let the near face of the blocker show before darkness starts.
			_ends[i] = (hit.position as Vector2) + _forward.rotated(a) * 10.0


## Concealment: the LOS ray of each concealable (enemies, dummies) is cast every
## CONCEAL_EVERY s (half of them per step, alternating); the fade itself runs every frame.
const CONCEAL_EVERY := 0.05
var _conceal_t := 0.0
var _conceal_parity := 0
var _c_items: Array = []
var _c_target: Dictionary = {}


func _update_concealment(delta: float) -> void:
	_conceal_t -= delta
	if _conceal_t <= 0.0:
		_conceal_t = CONCEAL_EVERY
		_conceal_parity ^= 1
		if _conceal_parity == 0:
			_c_items = get_tree().get_nodes_in_group("concealable")
			for k in _c_target.keys():
				if not is_instance_valid(k):
					_c_target.erase(k)
		_retarget()
	for item in _c_items:
		if not is_instance_valid(item):
			continue
		var ci := item as CanvasItem
		var target: float = _c_target.get(item, ci.modulate.a)
		if ci.modulate.a != target:
			ci.modulate.a = move_toward(ci.modulate.a, target, delta * 5.0)
			ci.visible = ci.modulate.a > 0.01


func _retarget() -> void:
	var space := get_world_2d().direct_space_state
	var i := _conceal_parity
	while i < _c_items.size():
		var item = _c_items[i]
		i += 2
		if not is_instance_valid(item):
			continue
		var to: Vector2 = (item as Node2D).global_position - _origin
		var meters := to.length() / PX
		var target := 0.0
		if meters <= view_distance and absf(_forward.angle_to(to)) <= _half_fov:
			var q := PhysicsRayQueryParameters2D.create(_origin, (item as Node2D).global_position, SIGHT_MASK)
			q.exclude = [_player.get_rid()]
			if space.intersect_ray(q).is_empty():
				target = 1.0
		if target < 1.0:
			target = (1.0 - smoothstep(sense_full, sense_start, meters)) * sense_alpha
		_c_target[item] = target


func _draw() -> void:
	if _mode == Mode.QUAD:
		_draw_quad_rect()
		return
	if _mode != Mode.RAYS or _ends.is_empty():
		return
	# One triangle batch (no triangulation, one draw call):
	# - a fan from the head around the back (outside the cone),
	# - inside the cone, the strip between each ray's visible end and FAR.
	var pts := PackedVector2Array()
	var steps := 24
	var prev := _origin + _forward.rotated(_half_fov) * FAR
	for i in range(1, steps + 1):
		var a := lerpf(_half_fov, TAU - _half_fov, float(i) / steps)
		var cur := _origin + _forward.rotated(a) * FAR
		pts.append_array([_origin, prev, cur])
		prev = cur
	for i in RAYS:
		var f0 := _origin + _forward.rotated(lerpf(-_half_fov, _half_fov, float(i) / RAYS)) * FAR
		var f1 := _origin + _forward.rotated(lerpf(-_half_fov, _half_fov, float(i + 1) / RAYS)) * FAR
		pts.append_array([_ends[i], _ends[i + 1], f1, _ends[i], f1, f0])
	var indices := PackedInt32Array()
	indices.resize(pts.size())
	for i in pts.size():
		indices[i] = i
	var colors := PackedColorArray()
	colors.resize(pts.size())
	colors.fill(DARK)
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), indices, pts, colors)


# --- QUAD mode ------------------------------------------------------------------------

const QUAD_HALF := 9000.0
const QUAD_SHADER := """
shader_type canvas_item;
render_mode unshaded;
uniform vec2 origin;
uniform vec2 pl_pos;
uniform vec2 fwd;
uniform float half_fov;
uniform float reach;
uniform float n_rays;
uniform sampler2D rays : filter_linear, repeat_disable;
uniform sampler2D explored : filter_linear, repeat_disable;
uniform vec4 bounds;
uniform vec4 dark;
uniform float mem_amount;
varying vec2 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}
void fragment() {
	vec2 d = wpos - origin;
	float r = length(d);
	vec2 dn = d / max(r, 0.001);
	float a = atan(fwd.x * dn.y - fwd.y * dn.x, dot(fwd, dn));
	float u = clamp(a / half_fov * 0.5 + 0.5, 0.0, 1.0);
	float vd = texture(rays, vec2((u * n_rays + 0.5) / (n_rays + 1.0), 0.5)).r * reach;
	float edge = 0.0873;
	float cone = 1.0 - smoothstep(half_fov - edge, half_fov + edge, abs(a));
	float wall = 1.0 - smoothstep(vd - 30.0, vd + 12.0, r);
	float far_fade = 1.0 - smoothstep(0.75 * reach, reach, r);
	float self_lit = 1.0 - smoothstep(80.0, 115.0, length(wpos - pl_pos));
	float vis = max(cone * wall * far_fade, self_lit);
	float mem = texture(explored, (wpos - bounds.xy) / bounds.zw).r;
	COLOR = vec4(dark.rgb, dark.a * (1.0 - vis) * (1.0 - mem_amount * mem));
}
"""
## Memory fog grid: world rectangle (m) covered by all zones + passages, cell size (m).
const MEM_RECT := Rect2(-80.0, -350.0, 160.0, 430.0)
const MEM_CELL := 2.5
## Darkness left over in explored (seen before) areas, as a fraction of the full dark alpha.
const MEM_AMOUNT := 0.35
var _mem_w := 0
var _mem_h := 0


func _setup_quad() -> void:
	var sh := Shader.new()
	sh.code = QUAD_SHADER
	_quad_mat = ShaderMaterial.new()
	_quad_mat.shader = sh
	if _ray_img == null:
		var n := (RAYS + 1) * 2
		var d := PackedByteArray()
		d.resize(n)
		_ray_img = Image.create_from_data(RAYS + 1, 1, false, Image.FORMAT_RH, d)
		_ray_tex = ImageTexture.create_from_image(_ray_img)
		_mem_w = ceili(MEM_RECT.size.x / MEM_CELL)
		_mem_h = ceili(MEM_RECT.size.y / MEM_CELL)
		_explored = PackedByteArray()
		_explored.resize(_mem_w * _mem_h)
		_explored_img = Image.create_from_data(_mem_w, _mem_h, false, Image.FORMAT_R8, _explored)
		_explored_tex = ImageTexture.create_from_image(_explored_img)
	_quad_mat.set_shader_parameter("rays", _ray_tex)
	_quad_mat.set_shader_parameter("explored", _explored_tex)
	_quad_mat.set_shader_parameter("n_rays", float(RAYS))
	_quad_mat.set_shader_parameter("dark", DARK)
	_quad_mat.set_shader_parameter("mem_amount", MEM_AMOUNT)
	_quad_mat.set_shader_parameter("bounds", Vector4(MEM_RECT.position.x * PX, MEM_RECT.position.y * PX, MEM_RECT.size.x * PX, MEM_RECT.size.y * PX))
	_quad_mat.set_shader_parameter("reach", view_distance * PX)
	material = _quad_mat


## One dark quad around the player (re-recorded only when the player walked far from its centre).
func _draw_quad_rect() -> void:
	_quad_center = _player.global_position if _player else Vector2.ZERO
	draw_rect(Rect2(_quad_center - Vector2.ONE * QUAD_HALF, Vector2.ONE * QUAD_HALF * 2.0), Color.WHITE)


func _update_quad() -> void:
	var reach := view_distance * PX
	var bytes := _ray_img.get_data()
	for i in RAYS + 1:
		bytes.encode_half(i * 2, minf(_origin.distance_to(_ends[i]) / reach, 1.0))
	_ray_img.set_data(RAYS + 1, 1, false, Image.FORMAT_RH, bytes)
	_ray_tex.update(_ray_img)
	_quad_mat.set_shader_parameter("origin", _cast_origin)
	_quad_mat.set_shader_parameter("pl_pos", _player.global_position)
	_quad_mat.set_shader_parameter("fwd", _cast_forward)
	_quad_mat.set_shader_parameter("half_fov", _cast_half)
	if _origin.distance_squared_to(_quad_center) > 3000.0 * 3000.0:
		queue_redraw()
	if _tick % 6 == 0:
		_mark_explored()
	if _explored_dirty and _tick % 12 == 0:
		_explored_dirty = false
		_explored_img.set_data(_mem_w, _mem_h, false, Image.FORMAT_R8, _explored)
		_explored_tex.update(_explored_img)


## Mark the cells along every other ray (up to its wall hit) as explored.
func _mark_explored() -> void:
	var cell := MEM_CELL * PX
	var org := MEM_RECT.position * PX
	for i in range(0, RAYS + 1, 2):
		var to: Vector2 = _ends[i] - _origin
		var n := int(to.length() / cell) + 1
		for k in n + 1:
			var p := _origin + to * (float(k) / n)
			var cx := int((p.x - org.x) / cell)
			var cy := int((p.y - org.y) / cell)
			if cx < 0 or cy < 0 or cx >= _mem_w or cy >= _mem_h:
				continue
			var idx := cy * _mem_w + cx
			if _explored[idx] == 0:
				_explored[idx] = 255
				_explored_dirty = true
