class_name PauseMenu
extends CanvasLayer

const SAVE_PATH     := "user://quicksave.json"
const SETTINGS_PATH := "user://settings.json"

signal resumed
signal edit_layout_requested

var _player: Player = null
var _inventory: InventorySystem = null

var _main_panel: Control
var _settings_panel: Control
var _vol_slider: HSlider
var _sens_slider: HSlider

func setup(player: Player, inventory: InventorySystem) -> void:
	_player    = player
	_inventory = inventory

func _ready() -> void:
	layer        = 10
	process_mode = PROCESS_MODE_ALWAYS
	visible      = false
	_build_ui()
	_apply_saved_settings()

func open() -> void:
	_main_panel.visible     = true
	_settings_panel.visible = false
	visible = true
	get_tree().paused = true

func close() -> void:
	visible = false
	get_tree().paused = false
	resumed.emit()

# ── UI construction ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_main_panel = _make_card()
	var mv := _main_panel.get_meta("vbox") as VBoxContainer
	_add_title(mv, "PAUSED", 22)
	_add_btn(mv, "CONTINUE",  Color(0.12, 0.45, 0.22), close)
	_add_btn(mv, "SETTINGS",  Color(0.15, 0.30, 0.55), _show_settings)
	_add_btn(mv, "SAVE GAME", Color(0.40, 0.30, 0.08), _save_game)
	_add_btn(mv, "EXIT",      Color(0.50, 0.10, 0.10), _exit)
	center.add_child(_main_panel)

	_settings_panel = _make_card()
	_settings_panel.visible = false
	var sv := _settings_panel.get_meta("vbox") as VBoxContainer
	_add_title(sv, "SETTINGS", 20)
	_vol_slider  = _add_slider(sv, "Master Volume", 0.0, 100.0, 80.0)
	_sens_slider = _add_slider(sv, "Camera Sens.",  1.0, 10.0,  5.0)
	_add_btn(sv, "EDIT LAYOUT", Color(0.25, 0.25, 0.50), _on_edit_layout)
	_add_btn(sv, "BACK",        Color(0.30, 0.20, 0.08), _hide_settings)
	center.add_child(_settings_panel)

func _make_card() -> Control:
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
	vbox.custom_minimum_size = Vector2(220, 0)
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	pc.set_meta("vbox", vbox)
	return pc

func _add_title(vbox: VBoxContainer, text: String, font_size: int) -> void:
	var lbl := Label.new()
	lbl.text                = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(lbl)

	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 6)
	vbox.add_child(sep)

func _add_btn(vbox: VBoxContainer, text: String, color: Color, callback: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(220, 48)
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_stylebox_override("normal",  _flat_style(color))
	b.add_theme_stylebox_override("hover",   _flat_style(color.lightened(0.15)))
	b.add_theme_stylebox_override("pressed", _flat_style(color.darkened(0.15)))
	b.pressed.connect(callback)
	vbox.add_child(b)

func _add_slider(vbox: VBoxContainer, label: String, min_v: float, max_v: float, default_v: float) -> HSlider:
	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	vbox.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value          = min_v
	slider.max_value          = max_v
	slider.value              = default_v
	slider.custom_minimum_size = Vector2(220, 24)
	vbox.add_child(slider)
	return slider

func _flat_style(col: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color                   = col
	s.corner_radius_top_left     = 6
	s.corner_radius_top_right    = 6
	s.corner_radius_bottom_left  = 6
	s.corner_radius_bottom_right = 6
	return s

# ── Panel switching ───────────────────────────────────────────────────────────

func _show_settings() -> void:
	_main_panel.visible     = false
	_settings_panel.visible = true

func _hide_settings() -> void:
	_save_settings()
	_settings_panel.visible = false
	_main_panel.visible     = true

func _on_edit_layout() -> void:
	close()
	edit_layout_requested.emit()

# ── Save / Load ───────────────────────────────────────────────────────────────

func _save_game() -> void:
	if _player == null:
		return
	var s := _player.survival
	var data: Dictionary = {
		"health":     _player.health,
		"max_health": _player.max_health,
		"position":   [_player.global_position.x, _player.global_position.y],
		"survival": {
			"stamina": s.stamina,
			"hunger":  s.hunger,
			"thirst":  s.thirst,
		},
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))

func _save_settings() -> void:
	var data: Dictionary = {
		"volume":      _vol_slider.value,
		"sensitivity": _sens_slider.value,
	}
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
	_apply_volume(_vol_slider.value)
	_apply_sensitivity(_sens_slider.value)

func _apply_saved_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if not f:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		return
	var d := parsed as Dictionary
	if d.has("volume"):
		var vol := float(d["volume"])
		_vol_slider.value = vol
		_apply_volume(vol)
	if d.has("sensitivity"):
		var sens := float(d["sensitivity"])
		_sens_slider.value = sens
		_apply_sensitivity(sens)

func _apply_volume(pct: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(clampf(pct / 100.0, 0.0001, 1.0)))

func _apply_sensitivity(value: float) -> void:
	TouchInputHandler.swipe_sensitivity = value * 0.002

func _exit() -> void:
	get_tree().paused = false
	get_tree().quit()
