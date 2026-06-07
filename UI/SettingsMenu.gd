class_name SettingsMenu
extends CanvasLayer

const SETTINGS_PATH := "user://settings.json"
const _FPS_VALUES   := [30, 60, 120, 0]

var _screen_fx: ScreenEffects = null

var _main_panel:       Control
var _video_panel:      Control
var _audio_panel:      Control
var _general_panel:    Control

var _fps_option:        OptionButton
var _quality_option:    OptionButton
var _brightness_slider: HSlider
var _contrast_slider:   HSlider
var _sens_slider:       HSlider
var _master_slider:     HSlider
var _gameplay_slider:   HSlider
var _music_slider:      HSlider
var _ads_mode_option:   OptionButton

func setup(screen_fx: ScreenEffects = null) -> void:
	_screen_fx = screen_fx

func _ready() -> void:
	layer        = 25
	process_mode = PROCESS_MODE_ALWAYS
	visible      = false
	_ensure_audio_buses()
	_build_ui()
	_apply_saved_settings()

func open() -> void:
	_show_only(_main_panel)
	visible = true

func close() -> void:
	visible = false

# ── Audio buses ───────────────────────────────────────────────────────────────

func _ensure_audio_buses() -> void:
	for bus_name in ["Gameplay", "Music"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.get_bus_count() - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")

# ── UI construction ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.60)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_main_panel = _card()
	var mv := _vb(_main_panel)
	_heading(mv, "SETTINGS", 22)
	_btn(mv, "GENERAL", Color(0.28, 0.20, 0.36), func(): _show_only(_general_panel))
	_btn(mv, "VIDEO",   Color(0.15, 0.35, 0.50), func(): _show_only(_video_panel))
	_btn(mv, "AUDIO",   Color(0.20, 0.40, 0.25), func(): _show_only(_audio_panel))
	_btn(mv, "BACK",    Color(0.30, 0.20, 0.08), close)
	center.add_child(_main_panel)

	_video_panel = _card()
	_video_panel.visible = false
	var vv := _vb(_video_panel)
	_heading(vv, "VIDEO", 20)
	_fps_option        = _option(vv, "Frame Rate",       ["30 FPS", "60 FPS", "120 FPS", "Unlimited"])
	_quality_option    = _option(vv, "Graphics Quality", ["Low", "Medium", "High"])
	_brightness_slider = _slider(vv, "Brightness",  -1.0,  1.0, 0.0)
	_contrast_slider   = _slider(vv, "Contrast",     0.5,  2.0, 1.0)
	_sens_slider       = _slider(vv, "Camera Speed", 1.0, 10.0, 5.0)
	_btn(vv, "BACK", Color(0.30, 0.20, 0.08), func():
		_apply_video()
		_write_settings()
		_show_only(_main_panel))
	center.add_child(_video_panel)

	_audio_panel = _card()
	_audio_panel.visible = false
	var av := _vb(_audio_panel)
	_heading(av, "AUDIO", 20)
	_master_slider   = _slider(av, "Master Volume",   0.0, 100.0, 80.0)
	_gameplay_slider = _slider(av, "Gameplay Volume", 0.0, 100.0, 80.0)
	_music_slider    = _slider(av, "Music Volume",    0.0, 100.0, 80.0)
	_btn(av, "BACK", Color(0.30, 0.20, 0.08), func():
		_apply_audio()
		_write_settings()
		_show_only(_main_panel))
	center.add_child(_audio_panel)

	_general_panel = _card()
	_general_panel.visible = false
	var gv := _vb(_general_panel)
	_heading(gv, "GENERAL", 20)
	_ads_mode_option = _option(gv, "ADS Mode", ["Press & Hold", "Toggle"])
	_btn(gv, "BACK", Color(0.30, 0.20, 0.08), func():
		_apply_general()
		_write_settings()
		_show_only(_main_panel))
	center.add_child(_general_panel)

func _show_only(panel: Control) -> void:
	for p: Control in [_main_panel, _video_panel, _audio_panel, _general_panel]:
		p.visible = (p == panel)

# ── Apply ─────────────────────────────────────────────────────────────────────

func _apply_video() -> void:
	Engine.max_fps = _FPS_VALUES[_fps_option.selected]
	var vp := get_viewport()
	match _quality_option.selected:
		0:
			vp.screen_space_aa        = Viewport.SCREEN_SPACE_AA_DISABLED
			vp.texture_default_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		1:
			vp.screen_space_aa        = Viewport.SCREEN_SPACE_AA_DISABLED
			vp.texture_default_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
		2:
			vp.screen_space_aa        = Viewport.SCREEN_SPACE_AA_FXAA
			vp.texture_default_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	if _screen_fx != null:
		_screen_fx.set_brightness(_brightness_slider.value)
		_screen_fx.set_contrast(_contrast_slider.value)
	TouchInputHandler.swipe_sensitivity = _sens_slider.value * 0.002

func _apply_general() -> void:
	GameState.ads_toggle_mode = (_ads_mode_option.selected == 1)

func _apply_audio() -> void:
	_set_bus_volume("Master",   _master_slider.value)
	_set_bus_volume("Gameplay", _gameplay_slider.value)
	_set_bus_volume("Music",    _music_slider.value)

func _set_bus_volume(bus_name: String, pct: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx != -1:
		AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(pct / 100.0, 0.0001, 1.0)))

# ── Persistence ───────────────────────────────────────────────────────────────

func _write_settings() -> void:
	var data: Dictionary = {
		"master_volume":   _master_slider.value,
		"gameplay_volume": _gameplay_slider.value,
		"music_volume":    _music_slider.value,
		"brightness":      _brightness_slider.value,
		"contrast":        _contrast_slider.value,
		"fps_index":       _fps_option.selected,
		"quality":         _quality_option.selected,
		"sensitivity":     _sens_slider.value,
		"ads_toggle":      _ads_mode_option.selected,
	}
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))

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
	if d.has("master_volume"):   _master_slider.value   = float(d["master_volume"])
	if d.has("gameplay_volume"): _gameplay_slider.value = float(d["gameplay_volume"])
	if d.has("music_volume"):    _music_slider.value    = float(d["music_volume"])
	if d.has("brightness"):      _brightness_slider.value = float(d["brightness"])
	if d.has("contrast"):        _contrast_slider.value   = float(d["contrast"])
	if d.has("fps_index"):       _fps_option.select(int(d["fps_index"]))
	if d.has("quality"):         _quality_option.select(int(d["quality"]))
	if d.has("sensitivity"):     _sens_slider.value = float(d["sensitivity"])
	if d.has("ads_toggle"):      _ads_mode_option.select(int(d["ads_toggle"]))
	_apply_video()
	_apply_audio()
	_apply_general()

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

func _heading(vbox: VBoxContainer, text: String, font_size: int) -> void:
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

func _slider(vbox: VBoxContainer, label: String, min_v: float, max_v: float, default_v: float) -> HSlider:
	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	vbox.add_child(lbl)
	var s := HSlider.new()
	s.min_value           = min_v
	s.max_value           = max_v
	s.value               = default_v
	s.custom_minimum_size = Vector2(240, 24)
	vbox.add_child(s)
	return s

func _option(vbox: VBoxContainer, label: String, items: Array) -> OptionButton:
	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	vbox.add_child(lbl)
	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(240, 36)
	for item: String in items:
		opt.add_item(item)
	vbox.add_child(opt)
	return opt

func _flat(col: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color                   = col
	s.corner_radius_top_left     = 6
	s.corner_radius_top_right    = 6
	s.corner_radius_bottom_left  = 6
	s.corner_radius_bottom_right = 6
	return s
