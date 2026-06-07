class_name StatusBars
extends Node2D

const BAR_W   := 160.0
const BAR_H   := 12.0
const GAP     := 5.0
const LABEL_W := 32.0

const _DEFS := [
	{"label": "HP",  "color": Color(0.85, 0.15, 0.15, 0.92)},
	{"label": "STA", "color": Color(0.20, 0.55, 0.95, 0.92)},
	{"label": "HNG", "color": Color(0.90, 0.60, 0.10, 0.92)},
	{"label": "THR", "color": Color(0.10, 0.72, 0.90, 0.92)},
]

var _player: Player = null
var _font: Font

func setup(player: Player) -> void:
	_player = player

func _ready() -> void:
	_font = ThemeDB.fallback_font

func _process(_dt: float) -> void:
	queue_redraw()

func _draw() -> void:
	if _player == null or _font == null:
		return
	var s := _player.survival
	var values := [
		float(_player.health) / float(_player.max_health),
		s.stamina / s.max_stamina,
		s.hunger  / s.max_hunger,
		s.thirst  / s.max_thirst,
	]
	for i in _DEFS.size():
		var y   := i * (BAR_H + GAP)
		var pct := clampf(values[i], 0.0, 1.0)
		# Background
		draw_rect(Rect2(LABEL_W, y, BAR_W, BAR_H), Color(0.08, 0.08, 0.08, 0.7))
		# Fill — shift to orange/red when low
		var col: Color = _DEFS[i].color
		if pct < 0.25:
			col = col.lerp(Color(1.0, 0.2, 0.1, 0.92), (0.25 - pct) / 0.25)
		draw_rect(Rect2(LABEL_W, y, BAR_W * pct, BAR_H), col)
		# Label
		draw_string(_font, Vector2(0.0, y + BAR_H - 2.0),
			_DEFS[i].label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
			Color(0.88, 0.88, 0.88, 0.9))
