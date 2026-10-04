class_name Vision
extends PointLight2D
## Player sight: a cone-shaped light with its apex on the head, casting shadows from
## LightOccluder2Ds. Everything outside it stays dark (CanvasModulate in main scene).
## Nodes in group "concealable" (enemies, dummies) fade out when not in sight; close
## ones stay faintly visible ("you sense them"). Child of Player, rotates with it.

const TEX_SIZE := 384
const PX := Firearm.PX_PER_M
## Light mask bit used only for the player's own body light.
const SELF_MASK := 2

## Full sight angle in degrees.
@export var fov_degrees := 120.0
## m, how far the cone reaches.
@export var view_distance := 24.0
## m, unseen concealables start fading in at this distance...
@export var sense_start := 7.0
## m, ...and reach sense_alpha here.
@export var sense_full := 3.0
@export_range(0.0, 1.0) var sense_alpha := 0.55


func _ready() -> void:
	shadow_enabled = true
	shadow_filter = Light2D.SHADOW_FILTER_PCF5
	shadow_filter_smooth = 1.5
	energy = 0.85
	texture = _build_texture()
	texture_scale = view_distance * PX / (TEX_SIZE / 2.0)
	range_item_cull_mask = 1
	_setup_self_light()


## Occluder for props: only edges facing away from the light cast, so the prop's
## own top stays lit and the shadow starts behind it.
static func make_occluder(points: PackedVector2Array) -> LightOccluder2D:
	var poly := OccluderPolygon2D.new()
	poly.polygon = points
	poly.cull_mode = OccluderPolygon2D.CULL_COUNTER_CLOCKWISE
	var occ := LightOccluder2D.new()
	occ.occluder = poly
	return occ


func _physics_process(delta: float) -> void:
	var player := get_parent() as CollisionObject2D
	var space := get_world_2d().direct_space_state
	var forward := Vector2.UP.rotated(global_rotation)
	var half_fov := deg_to_rad(fov_degrees / 2.0)
	for n in get_tree().get_nodes_in_group("concealable"):
		var item := n as CanvasItem
		var to: Vector2 = item.global_position - global_position
		var meters := to.length() / PX
		var target := 0.0
		if meters <= view_distance and absf(forward.angle_to(to)) <= half_fov:
			var q := PhysicsRayQueryParameters2D.create(global_position, item.global_position)
			q.exclude = [player.get_rid(), (n as CollisionObject2D).get_rid()]
			if space.intersect_ray(q).is_empty():
				target = 1.0
		if target < 1.0:
			target = (1.0 - smoothstep(sense_full, sense_start, meters)) * sense_alpha
		item.modulate.a = move_toward(item.modulate.a, target, delta * 5.0)


## The cone apex is on the head, so the body would sit in the dark: give the player
## its own small light that only affects the player (light mask bit 2).
func _setup_self_light() -> void:
	var player := get_parent() as CanvasItem
	for ci in [player] + player.get_children():
		if ci is CanvasItem:
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
	self_light.texture_scale = 1.6
	self_light.energy = 0.85
	self_light.range_item_cull_mask = SELF_MASK
	add_child(self_light)


func _build_texture() -> ImageTexture:
	var half_fov := deg_to_rad(fov_degrees / 2.0)
	var edge := deg_to_rad(6.0)
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
