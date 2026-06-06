extends Node2D

var reticle_type: String = "dot"
var color: Color = Color(1.0, 1.0, 1.0, 0.92)
var outline: Color = Color(0.0, 0.0, 0.0, 0.5)

func set_type(t: String) -> void:
	reticle_type = t
	queue_redraw()

func _draw() -> void:
	match reticle_type:
		"dot":
			draw_circle(Vector2.ZERO, 2.5, outline)
			draw_circle(Vector2.ZERO, 1.8, color)
		"crosshair":
			const GAP := 5.0
			const ARM := 13.0
			const W   := 1.5
			for v in [[Vector2(-ARM - GAP, 0), Vector2(-GAP, 0)],
					  [Vector2(GAP, 0), Vector2(ARM + GAP, 0)],
					  [Vector2(0, -ARM - GAP), Vector2(0, -GAP)],
					  [Vector2(0, GAP), Vector2(0, ARM + GAP)]]:
				draw_line(v[0], v[1], outline, W + 1.5)
				draw_line(v[0], v[1], color, W)
		"circle":
			draw_arc(Vector2.ZERO, 22.0, 0, TAU, 48, outline, 3.0)
			draw_arc(Vector2.ZERO, 22.0, 0, TAU, 48, color,   1.5)
		"none":
			pass
