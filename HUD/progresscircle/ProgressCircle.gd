# res://HUD/ProgressCircle.gd
class_name ProgressCircle
extends Node2D

@export var radius: float = 36.0
@export var thickness: float = 6.0
@export var bg_color: Color = Color(1, 1, 1, 0.15)
@export var fill_color: Color = Color(1, 1, 1, 0.9)

signal cancelled

var _progress: float = 0.0
var _active: bool = false
var _label: String = ""

@onready var _cancel_btn: Button = $CancelButton

func _ready() -> void:
	_cancel_btn.visible = false
	_cancel_btn.pressed.connect(func(): cancelled.emit(); hide_progress())
	visible = false

func start(label: String = "", with_cancel: bool = false) -> void:
	_label = label
	_progress = 0.0
	_active = true
	visible = true
	_cancel_btn.visible = with_cancel
	queue_redraw()

func set_progress(value: float) -> void:
	_progress = clampf(value, 0.0, 1.0)
	queue_redraw()
	if _progress >= 1.0:
		hide_progress()

func hide_progress() -> void:
	_active = false
	_progress = 0.0
	visible = false
	queue_redraw()

func _draw() -> void:
	if not _active:
		return

	# background ring
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, bg_color, thickness, true)

	# filled arc clockwise from top
	var end_angle: float = -PI / 2.0 + TAU * _progress
	draw_arc(Vector2.ZERO, radius, -PI / 2.0, end_angle, 64, fill_color, thickness, true)

	# center text
	var font := ThemeDB.fallback_font
	var font_size := 13
	var text := _label if _label != "" else "%d%%" % int(_progress * 100)
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(font, -text_size * 0.5, text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 0.9))
