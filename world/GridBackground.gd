# GridBackground.gd — attach to a Node2D placed behind everything (y_sort disabled)
# Draws an infinite-feeling grid that tiles as the camera moves.
# No texture assets needed — pure draw_line calls.

extends Node2D

@export var cell_size: float = 64.0
@export var grid_color: Color = Color(0.25, 0.25, 0.25, 1.0)
@export var accent_color: Color = Color(0.4, 0.4, 0.4, 1.0)  # every Nth line
@export var accent_interval: int = 4
@export var bg_color: Color = Color(0.08, 0.08, 0.08, 1.0)

const OVERDRAW: int = 4

func _draw() -> void:
	var cam := _get_camera()
	if not cam:
		return

	var viewport_size := get_viewport_rect().size
	var zoom := cam.zoom
	var half_w := (viewport_size.x / zoom.x) * 0.5
	var half_h := (viewport_size.y / zoom.y) * 0.5
	var half_diag := sqrt(half_w * half_w + half_h * half_h)
	var pad := half_diag + cell_size * OVERDRAW

	var cam_pos := cam.global_position

	# Background fill
	draw_rect(Rect2(cam_pos - Vector2(pad, pad), Vector2(pad, pad) * 2.0), bg_color)

	# Snap to cell grid so lines feel world-anchored
	var origin_x := snappedf(cam_pos.x, cell_size)
	var origin_y := snappedf(cam_pos.y, cell_size)

	# Vertical lines
	var x := origin_x - pad
	while x <= origin_x + pad:
		var is_accent := is_zero_approx(fmod(abs(x), cell_size * accent_interval))
		var col   := accent_color if is_accent else grid_color
		var width := 1.5 if is_accent else 0.75
		draw_line(Vector2(x, cam_pos.y - pad), Vector2(x, cam_pos.y + pad), col, width)
		x += cell_size

	# Horizontal lines
	var y := origin_y - pad
	while y <= origin_y + pad:
		var is_accent := is_zero_approx(fmod(abs(y), cell_size * accent_interval))
		var col   := accent_color if is_accent else grid_color
		var width := 1.5 if is_accent else 0.75
		draw_line(Vector2(cam_pos.x - pad, y), Vector2(cam_pos.x + pad, y), col, width)
		y += cell_size

	# World origin cross so you always know where (0,0) is
	draw_line(Vector2(-20, 0), Vector2(20, 0), Color(1, 0.3, 0.3, 0.8), 2.0)
	draw_line(Vector2(0, -20), Vector2(0, 20), Color(0.3, 1, 0.3, 0.8), 2.0)

func _process(_delta: float) -> void:
	queue_redraw()

func _get_camera() -> Camera2D:
	var vp := get_viewport()
	if vp:
		return vp.get_camera_2d()
	return null
