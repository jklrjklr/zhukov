class_name Vision
extends PointLight2D
## Player sight: a cone-shaped light (plus a small all-round awareness circle) with
## shadows. Everything outside the cone or behind LightOccluder2Ds stays dark
## (CanvasModulate in main scene). Child of Player, so it rotates with the aim.

const TEX_SIZE := 384

## Full sight angle in degrees.
@export var fov_degrees := 100.0
## m, how far the cone reaches.
@export var view_distance := 24.0
## m, all-round awareness radius (hear/feel what is right behind you).
@export var peripheral := 2.5


func _ready() -> void:
	shadow_enabled = true
	shadow_filter = Light2D.SHADOW_FILTER_PCF5
	shadow_filter_smooth = 1.5
	energy = 0.85
	texture = _build_texture()
	texture_scale = view_distance * Firearm.PX_PER_M / (TEX_SIZE / 2.0)


## Occluder for props: only edges facing away from the light cast, so the prop's
## own top stays lit and the shadow starts behind it.
static func make_occluder(points: PackedVector2Array) -> LightOccluder2D:
	var poly := OccluderPolygon2D.new()
	poly.polygon = points
	poly.cull_mode = OccluderPolygon2D.CULL_COUNTER_CLOCKWISE
	var occ := LightOccluder2D.new()
	occ.occluder = poly
	return occ


func _build_texture() -> ImageTexture:
	var half_fov := deg_to_rad(fov_degrees / 2.0)
	var edge := deg_to_rad(6.0)
	var near := peripheral / view_distance
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
			var around := 1.0 - smoothstep(near * 0.7, near, r)
			var v := maxf(cone * fade, around)
			data[i] = 255
			data[i + 1] = int(v * 255.0)
			i += 2
	return ImageTexture.create_from_image(Image.create_from_data(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_LA8, data))
