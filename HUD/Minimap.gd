class_name Minimap
extends Node2D

const RADIUS    := 68.0
const DOT_R     := 4.5
const ARROW_LEN := 12.0
const ENEMY_DOT := 3.0
# How many world units map to the full minimap diameter.
const WORLD_SPAN := 1800.0

var _player: Player = null
var _font: Font

func setup(player: Player) -> void:
	_player = player

func _ready() -> void:
	_font = ThemeDB.fallback_font

func _process(_dt: float) -> void:
	queue_redraw()

func _draw() -> void:
	# Dark background
	draw_circle(Vector2.ZERO, RADIUS, Color(0.04, 0.04, 0.07, 0.80))

	if _player != null:
		var player_pos: Vector2 = _player.global_position
		var facing: float       = _player.facing_angle

		# Other characters shown as red dots
		for body_node in get_tree().get_nodes_in_group("character"):
			var body := body_node as Node2D
			if body == null or body == _player:
				continue
			var offset: Vector2 = (body.global_position - player_pos) * (RADIUS * 2.0 / WORLD_SPAN)
			if offset.length() < RADIUS - ENEMY_DOT:
				draw_circle(offset, ENEMY_DOT, Color(0.95, 0.25, 0.25, 0.9))

		# Player dot + direction arrow
		draw_circle(Vector2.ZERO, DOT_R, Color(0.25, 1.0, 0.35, 1.0))
		var arrow_dir: Vector2 = Vector2.UP.rotated(facing)
		draw_line(Vector2.ZERO, arrow_dir * ARROW_LEN,
			Color(0.25, 1.0, 0.35, 1.0), 2.0, true)

	# Border ring
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 64,
		Color(0.45, 0.45, 0.45, 0.85), 1.5)

	# "MAP" label
	if _font != null:
		draw_string(_font, Vector2(-12.0, RADIUS - 4.0),
			"MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 8,
			Color(0.55, 0.55, 0.55, 0.7))
