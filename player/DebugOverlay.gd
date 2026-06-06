# DebugOverlay.gd — CanvasLayer child of Player

extends CanvasLayer

const JOYSTICK_RADIUS: float = 80.0
const RING_COLOR       := Color(1, 1, 1, 0.25)
const KNOB_COLOR       := Color(0, 1, 0.6, 0.85)
const CAM_ARROW_COLOR  := Color(0, 0.8, 1, 0.9)
const BODY_ARROW_COLOR := Color(1, 0.4, 0, 0.9)
const VEL_BAR_COLOR    := Color(1, 0.9, 0, 0.85)
const SPEED_BAR_COLOR  := Color(0.4, 1, 0.4, 0.85)
const ARROW_LEN: float = 60.0

var _draw_node: Node2D
var _player: Player

func _ready() -> void:
	layer = 10
	_player = get_parent() as Player
	_draw_node = Node2D.new()
	add_child(_draw_node)
	_draw_node.draw.connect(_on_draw)

func _process(_delta: float) -> void:
	_draw_node.queue_redraw()

func _on_draw() -> void:
	_draw_joystick()
	_draw_swipe_bar()
	_draw_facing_arrows()
	_draw_stats()

func _draw_joystick() -> void:
	var th := TouchInputHandler
	if th._joystick_touch_index == -1:
		var ghost := Vector2(120, DisplayServer.window_get_size().y - 120)
		_draw_node.draw_arc(ghost, JOYSTICK_RADIUS, 0, TAU, 48, Color(1,1,1,0.1), 2.0)
		return
	var origin  : Vector2 = th._joystick_origin
	var delta_v : Vector2 = (th._joystick_current - origin).limit_length(JOYSTICK_RADIUS)
	_draw_node.draw_arc(origin, JOYSTICK_RADIUS, 0, TAU, 48, RING_COLOR, 2.0)
	_draw_node.draw_line(origin + Vector2(-10,0), origin + Vector2(10,0), RING_COLOR, 1.0)
	_draw_node.draw_line(origin + Vector2(0,-10), origin + Vector2(0,10), RING_COLOR, 1.0)
	var knob := origin + delta_v
	_draw_node.draw_circle(knob, 18.0, KNOB_COLOR)
	_draw_node.draw_line(origin, knob, KNOB_COLOR, 2.0)
	_draw_string_at(knob + Vector2(22,5), "%.2f" % (delta_v / JOYSTICK_RADIUS).length(), KNOB_COLOR)

func _draw_swipe_bar() -> void:
	var screen := Vector2(DisplayServer.window_get_size())
	var center := Vector2(screen.x * 0.5, 40)
	var vel: float = TouchInputHandler.get_camera_angular_velocity()
	var fill   := clampf(vel / 3.0, -1.0, 1.0)
	var bar_hw := 120.0
	_draw_node.draw_rect(Rect2(center + Vector2(-bar_hw,-8), Vector2(bar_hw*2,16)), Color(1,1,1,0.1))
	if absf(fill) > 0.01:
		var fw := bar_hw * absf(fill)
		var fx := center.x if fill > 0 else center.x - fw
		_draw_node.draw_rect(Rect2(Vector2(fx, center.y-8), Vector2(fw,16)), VEL_BAR_COLOR)
	_draw_node.draw_line(center+Vector2(0,-10), center+Vector2(0,10), Color(1,1,1,0.5), 1.5)
	_draw_string_at(center+Vector2(-18,22), "cam ω: %.3f r/s" % vel, VEL_BAR_COLOR)
	if TouchInputHandler._swipe_touch_index != -1:
		_draw_node.draw_circle(TouchInputHandler._swipe_last_pos, 10.0, Color(1,0.9,0,0.4))

func _draw_facing_arrows() -> void:
	if not _player: return
	var cam: Camera2D = _player.get_node_or_null("Camera2D")
	if not cam: return
	var center := Vector2(DisplayServer.window_get_size()) * 0.5
	var cam_fwd_angle: float = cam.rotation + _player.facing_offset
	var cam_fwd  := Vector2.from_angle(cam_fwd_angle) * ARROW_LEN
	var body_fwd := Vector2.from_angle(_player._sprite.rotation) * ARROW_LEN
	_draw_arrow(center, center + cam_fwd,  CAM_ARROW_COLOR,  "cam")
	_draw_arrow(center, center + body_fwd, BODY_ARROW_COLOR, "body")
	var gap_deg := rad_to_deg(absf(_player.angle_difference(_player._sprite.rotation, cam_fwd_angle)))
	_draw_string_at(center + Vector2(10, ARROW_LEN + 20), "gap: %.1f°" % gap_deg, Color(1,1,1,0.7))

	# Draw ease_start arc so you can see the threshold visually
	var ease_r := ARROW_LEN * 0.7
	_draw_node.draw_arc(center, ease_r,
		cam_fwd_angle - deg_to_rad(_player.ease_start_deg),
		cam_fwd_angle + deg_to_rad(_player.ease_start_deg),
		32, Color(0.4, 1, 0.4, 0.2), 1.5)

func _draw_arrow(from: Vector2, to: Vector2, color: Color, label: String) -> void:
	_draw_node.draw_line(from, to, color, 2.5)
	var dir := (to - from).normalized()
	var perp := dir.rotated(deg_to_rad(90))
	_draw_node.draw_line(to, to - dir*10 + perp*6, color, 2.0)
	_draw_node.draw_line(to, to - dir*10 - perp*6, color, 2.0)
	_draw_string_at(to + dir*6, label, color)

func _draw_stats() -> void:
	if not _player: return
	var screen := Vector2(DisplayServer.window_get_size())
	var pos    := Vector2(screen.x - 220, screen.y - 120)

	# Compute live turn speed for this frame
	var cam_fwd_angle: float = _player._camera.rotation + _player.facing_offset
	var gap: float = absf(_player.angle_difference(_player._facing_angle, cam_fwd_angle))
	var ease_rad: float = deg_to_rad(_player.ease_start_deg)
	var speed_factor: float
	if gap >= ease_rad:
		speed_factor = 1.0
	else:
		var t: float = gap / ease_rad
		speed_factor = lerpf(_player.ease_min_factor, 1.0, smoothstep(0.0, 1.0, t))
	var live_speed_dps: float = rad_to_deg(_player._turn_speed_rad) * speed_factor

	var ergo: float = _player.ergonomics
	_draw_string_at(pos,                "ergo:      %.2f"   % ergo,                           Color(1,1,1,0.8))
	_draw_string_at(pos+Vector2(0,18),  "max turn:  %.0f°/s" % rad_to_deg(_player._turn_speed_rad), Color(1,1,1,0.6))
	_draw_string_at(pos+Vector2(0,36),  "live turn: %.0f°/s" % live_speed_dps,                SPEED_BAR_COLOR)
	_draw_string_at(pos+Vector2(0,54),  "gap:       %.1f°"  % rad_to_deg(gap),                Color(1,1,1,0.6))
	_draw_string_at(pos+Vector2(0,72),  "ease zone: ±%.0f°" % _player.ease_start_deg,         Color(0.4,1,0.4,0.7))

	# Live speed bar
	var bar_pos := pos + Vector2(0, 110)
	var bar_w   := 180.0
	_draw_node.draw_rect(Rect2(bar_pos, Vector2(bar_w, 8)), Color(1,1,1,0.1))
	_draw_node.draw_rect(Rect2(bar_pos, Vector2(bar_w * speed_factor, 8)), SPEED_BAR_COLOR)

func _draw_string_at(pos: Vector2, text: String, color: Color) -> void:
	var font := ThemeDB.fallback_font
	_draw_node.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
