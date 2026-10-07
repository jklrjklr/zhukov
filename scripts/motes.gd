class_name Motes
extends Node2D
## Fireflies drifting around the view: a fixed pool that wraps around the camera, drawn as
## one additive canvas item (one draw call). Positions in world px.

const COUNT := 48
## Half-size (world px) of the square around the camera the pool wraps in.
const AREA := 700.0
const COLORS := [Color(1.0, 0.85, 0.4), Color(0.65, 1.0, 0.55), Color(0.55, 0.85, 1.0)]

var _p := PackedVector2Array()
var _v := PackedVector2Array()
var _phase := PackedFloat32Array()
var _t := 0.0
var _cam: Node2D


func _ready() -> void:
	z_index = 20
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = m
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in COUNT:
		_p.append(Vector2(rng.randf_range(-AREA, AREA), rng.randf_range(-AREA, AREA)))
		_v.append(Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(6.0, 18.0))
		_phase.append(rng.randf() * TAU)


func _process(delta: float) -> void:
	if _cam == null or not is_instance_valid(_cam):
		_cam = get_tree().get_first_node_in_group("view_camera") as Node2D
		if _cam == null:
			return
	_t += delta
	var c := _cam.global_position
	for i in COUNT:
		var wobble := Vector2(sin(_t * 0.7 + _phase[i]), cos(_t * 0.9 + _phase[i] * 1.3)) * 10.0
		var p := _p[i] + (_v[i] + wobble) * delta
		# Wrap around the camera so the pool always surrounds the view.
		p.x = c.x + wrapf(p.x - c.x, -AREA, AREA)
		p.y = c.y + wrapf(p.y - c.y, -AREA, AREA)
		_p[i] = p
	queue_redraw()


func _draw() -> void:
	var s := 1.0 / Vis.CAM_ZOOM # one buffer pixel
	for i in COUNT:
		var glow := 0.5 + 0.5 * sin(_t * 2.3 + _phase[i] * 3.0)
		if glow < 0.15:
			continue
		var col: Color = COLORS[i % COLORS.size()]
		var p := (_p[i] / s).floor() * s
		draw_rect(Rect2(p - Vector2(s, s), Vector2(3 * s, 3 * s)), Color(col, 0.3 * glow))
		draw_rect(Rect2(p, Vector2(s, s)), Color(col, glow))
