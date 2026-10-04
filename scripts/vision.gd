class_name Vision
extends Node2D
## Player sight cone with shadows, two render modes:
## - LIGHT (native builds, default): a cone-shaped PointLight2D on the head with
##   real-time per-frame shadows from LightOccluder2Ds (rocks, walls, crates, trunks);
##   a CanvasModulate darkens everything unlit. Soft edges, shadows every frame.
## - RAYS (web, cheap): RAYS rays cast across the cone; anything outside the sight
##   polygon is covered by a dark fan overlay.
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
const FAR := 4000.0
## Collision layer that blocks sight (world geometry).
const SIGHT_MASK := 1
const DARK := Color(0.02, 0.03, 0.04, 0.8)
## LIGHT mode: ambient darkness and cone texture size.
const AMBIENT := Color(0.2, 0.22, 0.25)
const TEX_SIZE := 320
## Light mask bit used only for the player's own body light.
const SELF_MASK := 2

enum Mode { AUTO, LIGHT, RAYS }
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
## AUTO = LIGHT on native builds, RAYS on web.
@export var mode := Mode.AUTO

var _player: CharacterBody2D
var _weapon: Firearm
## Visible end point of each ray (global), first to last across the cone.
var _ends := PackedVector2Array()
var _origin := Vector2.ZERO
var _forward := Vector2.UP
var _half_fov := 0.0
var _tick := 0
var _use_light := false
var _cone: PointLight2D
var _hip_tex: ImageTexture
var _ads_tex: ImageTexture


func _ready() -> void:
	_player = get_parent()
	_weapon = _player.get_node("Firearm")
	top_level = true
	z_as_relative = false
	z_index = Z
	_use_light = mode == Mode.LIGHT or (mode == Mode.AUTO and not OS.has_feature("web"))
	if _use_light:
		_setup_light.call_deferred()


## Shadow caster for a prop (LIGHT mode). Only edges facing away from the light cast,
## so the prop's own top stays lit and its shadow starts behind it.
static func add_occluder(body: Node2D, points: PackedVector2Array) -> LightOccluder2D:
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
	_hip_tex = _build_texture(fov_degrees)
	_ads_tex = _build_texture(_weapon.stats.ads_fov)
	_cone = PointLight2D.new()
	_cone.texture = _hip_tex
	_cone.texture_scale = view_distance * PX / (TEX_SIZE / 2.0)
	_cone.shadow_enabled = true
	_cone.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	_cone.shadow_filter_smooth = 1.5
	_cone.energy = 0.85
	_cone.range_item_cull_mask = 1
	_player.add_child(_cone)
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
	if _use_light:
		if _cone:
			_cone.texture = _ads_tex if _weapon.ads_amount() >= 0.5 else _hip_tex
	elif _tick % 2 == 0 or _ends.is_empty():
		_cast_rays()
		queue_redraw()
	_update_concealment(delta)


func _cast_rays() -> void:
	var space := get_world_2d().direct_space_state
	var reach := view_distance * PX
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


func _update_concealment(delta: float) -> void:
	var space := get_world_2d().direct_space_state
	for n in get_tree().get_nodes_in_group("concealable"):
		var item := n as CanvasItem
		var to: Vector2 = item.global_position - _origin
		var meters := to.length() / PX
		var target := 0.0
		if meters <= view_distance and absf(_forward.angle_to(to)) <= _half_fov:
			var q := PhysicsRayQueryParameters2D.create(_origin, item.global_position, SIGHT_MASK)
			q.exclude = [_player.get_rid()]
			if space.intersect_ray(q).is_empty():
				target = 1.0
		if target < 1.0:
			target = (1.0 - smoothstep(sense_full, sense_start, meters)) * sense_alpha
		item.modulate.a = move_toward(item.modulate.a, target, delta * 5.0)
		item.visible = item.modulate.a > 0.01


func _draw() -> void:
	if _use_light or _ends.is_empty():
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
