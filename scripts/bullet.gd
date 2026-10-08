class_name Bullet
extends Node2D
## Player bullet: a fast tracer. Moves in a straight line, kills the first enemy on its path
## (swept against the segment travelled each tick, so it can't tunnel), fades at the end of its range.

const SPEED := 1500.0
const RANGE := 900.0
const TRACER := 34.0
const HIT_RADIUS := 22.0

var dir := Vector2.UP
var _travelled := 0.0


func _ready() -> void:
	z_index = 12
	rotation = dir.angle()


func _physics_process(delta: float) -> void:
	var step := dir * SPEED * delta
	for e in get_tree().get_nodes_in_group("enemies"):
		var z := e as Node2D
		var c := Geometry2D.get_closest_point_to_segment(z.global_position, global_position, global_position + step)
		if c.distance_to(z.global_position) < HIT_RADIUS and z.has_method("die"):
			z.die(dir)
			queue_free()
			return
	global_position += step
	_travelled += step.length()
	if _travelled > RANGE:
		queue_free()
	queue_redraw()


func _draw() -> void:
	# Drawn along +X (the node is rotated to the direction): bright core, warm halo.
	var l := minf(TRACER, _travelled + 6.0)
	draw_line(Vector2(-l, 0), Vector2.ZERO, Color(1.0, 0.75, 0.25, 0.8), 3.0)
	draw_line(Vector2(-l * 0.7, 0), Vector2.ZERO, Color(1.0, 0.97, 0.8), 1.5)
