class_name PauseMenu
extends CanvasLayer

const SAVE_PATH := "user://quicksave.json"

signal resumed
signal edit_layout_requested

var save_slot: int   = -1
var playtime:  float = 0.0

var _player:       Player          = null
var _inventory:    InventorySystem = null
var _settings_menu: SettingsMenu   = null

func setup(player: Player, inventory: InventorySystem, screen_fx: ScreenEffects = null) -> void:
	_player    = player
	_inventory = inventory
	_settings_menu = SettingsMenu.new()
	_settings_menu.setup(screen_fx)

func _ready() -> void:
	layer        = 10
	process_mode = PROCESS_MODE_ALWAYS
	visible      = false
	if _settings_menu != null:
		add_child(_settings_menu)
	_build_ui()

func open() -> void:
	visible = true
	get_tree().paused = true

func close() -> void:
	visible = false
	get_tree().paused = false
	resumed.emit()

# ── UI ────────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := _card()
	var mv := _vb(panel)
	_title(mv, "PAUSED", 22)
	_btn(mv, "CONTINUE",      Color(0.12, 0.45, 0.22), close)
	_btn(mv, "SETTINGS",      Color(0.15, 0.30, 0.55), func(): if _settings_menu: _settings_menu.open())
	_btn(mv, "INPUT UI EDIT", Color(0.35, 0.25, 0.50), _on_edit_layout)
	_btn(mv, "SAVE GAME",     Color(0.40, 0.30, 0.08), _save_game)
	_btn(mv, "EXIT",          Color(0.50, 0.10, 0.10), _exit)
	center.add_child(panel)

# ── Widget helpers ────────────────────────────────────────────────────────────

func _card() -> Control:
	var pc := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color                   = Color(0.08, 0.08, 0.12, 0.92)
	style.corner_radius_top_left     = 10
	style.corner_radius_top_right    = 10
	style.corner_radius_bottom_left  = 10
	style.corner_radius_bottom_right = 10
	pc.add_theme_stylebox_override("panel", style)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   24)
	margin.add_theme_constant_override("margin_right",  24)
	margin.add_theme_constant_override("margin_top",    24)
	margin.add_theme_constant_override("margin_bottom", 24)
	pc.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(240, 0)
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)
	pc.set_meta("vbox", vbox)
	return pc

func _vb(panel: Control) -> VBoxContainer:
	return panel.get_meta("vbox") as VBoxContainer

func _title(vbox: VBoxContainer, text: String, font_size: int) -> void:
	var lbl := Label.new()
	lbl.text                 = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(lbl)
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 6)
	vbox.add_child(sep)

func _btn(vbox: VBoxContainer, text: String, color: Color, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(240, 48)
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_stylebox_override("normal",  _flat(color))
	b.add_theme_stylebox_override("hover",   _flat(color.lightened(0.15)))
	b.add_theme_stylebox_override("pressed", _flat(color.darkened(0.15)))
	b.pressed.connect(cb)
	vbox.add_child(b)

func _flat(col: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color                   = col
	s.corner_radius_top_left     = 6
	s.corner_radius_top_right    = 6
	s.corner_radius_bottom_left  = 6
	s.corner_radius_bottom_right = 6
	return s

# ── Actions ───────────────────────────────────────────────────────────────────

func _save_game() -> void:
	if _player == null:
		return
	var path := MainMenu.save_path(save_slot) if save_slot >= 0 else SAVE_PATH
	var s := _player.survival
	var data: Dictionary = {
		"playtime":   playtime,
		"health":     _player.health,
		"max_health": _player.max_health,
		"position":   [_player.global_position.x, _player.global_position.y],
		"survival": {
			"stamina": s.stamina,
			"hunger":  s.hunger,
			"thirst":  s.thirst,
		},
		"inventory": _inventory.to_dict() if _inventory != null else {},
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))

func _on_edit_layout() -> void:
	close()
	edit_layout_requested.emit()

func _exit() -> void:
	get_tree().paused = false
	get_tree().quit()
