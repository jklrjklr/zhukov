class_name MainMenu
extends CanvasLayer

signal slot_selected(slot_index: int)
signal exit_requested

var _main_panel:  Control
var _slot_panel:  Control
var _slot_buttons: Array[Button] = []

func _ready() -> void:
	layer        = 19
	process_mode = PROCESS_MODE_ALWAYS

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.04, 0.06, 0.97)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	# ── Main panel ────────────────────────────────────────────────────────────
	_main_panel = _card()
	var mv := _vb(_main_panel)
	_heading(mv, "ZHUKOV", 36)
	_btn(mv, "START", Color(0.12, 0.40, 0.18), func(): _open_slots())
	_btn(mv, "SAVE",  Color(0.15, 0.28, 0.50), func(): _open_slots())
	_btn(mv, "EXIT",  Color(0.50, 0.10, 0.10), func(): exit_requested.emit())
	center.add_child(_main_panel)

	# ── Slot picker panel ─────────────────────────────────────────────────────
	_slot_panel = _card()
	_slot_panel.visible = false
	var sv := _vb(_slot_panel)
	_heading(sv, "SELECT SLOT", 22)
	for i in 3:
		var idx := i
		var b: Button = _btn(sv, _slot_label(i), Color(0.18, 0.25, 0.40), func(): _pick(idx))
		b.custom_minimum_size = Vector2(260, 60)
		_slot_buttons.append(b)
	_btn(sv, "BACK", Color(0.28, 0.18, 0.08), func():
		_slot_panel.visible = false
		_main_panel.visible = true)
	center.add_child(_slot_panel)

func _open_slots() -> void:
	for i in 3:
		_slot_buttons[i].text = _slot_label(i)
	_main_panel.visible = false
	_slot_panel.visible = true

func _pick(slot: int) -> void:
	slot_selected.emit(slot)

# ── Save-file helpers ─────────────────────────────────────────────────────────

static func save_path(slot: int) -> String:
	return "user://save_slot_%d.json" % slot

func _slot_label(slot: int) -> String:
	var path := save_path(slot)
	var name_str := "SLOT %d" % (slot + 1)
	if not FileAccess.file_exists(path):
		return "%s  —  New Game" % name_str
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "%s  —  New Game" % name_str
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		return "%s  —  New Game" % name_str
	var pt: float = float((parsed as Dictionary).get("playtime", 0.0))
	return "%s  —  %s" % [name_str, _fmt(pt)]

static func _fmt(secs: float) -> String:
	var h := int(secs) / 3600
	var m := (int(secs) % 3600) / 60
	var s := int(secs) % 60
	if h > 0:
		return "%dh %02dm" % [h, m]
	return "%dm %02ds" % [m, s]

# ── Widget helpers ────────────────────────────────────────────────────────────

func _card() -> Control:
	var pc := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color                   = Color(0.08, 0.08, 0.12, 0.95)
	style.corner_radius_top_left     = 12
	style.corner_radius_top_right    = 12
	style.corner_radius_bottom_left  = 12
	style.corner_radius_bottom_right = 12
	pc.add_theme_stylebox_override("panel", style)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   32)
	margin.add_theme_constant_override("margin_right",  32)
	margin.add_theme_constant_override("margin_top",    32)
	margin.add_theme_constant_override("margin_bottom", 32)
	pc.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(280, 0)
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)
	pc.set_meta("vbox", vbox)
	return pc

func _vb(panel: Control) -> VBoxContainer:
	return panel.get_meta("vbox") as VBoxContainer

func _heading(vbox: VBoxContainer, text: String, size: int) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(lbl)
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 6)
	vbox.add_child(sep)

func _btn(vbox: VBoxContainer, text: String, color: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(280, 52)
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_stylebox_override("normal",  _flat(color))
	b.add_theme_stylebox_override("hover",   _flat(color.lightened(0.15)))
	b.add_theme_stylebox_override("pressed", _flat(color.darkened(0.15)))
	b.pressed.connect(cb)
	vbox.add_child(b)
	return b

func _flat(col: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color                   = col
	s.corner_radius_top_left     = 6
	s.corner_radius_top_right    = 6
	s.corner_radius_bottom_left  = 6
	s.corner_radius_bottom_right = 6
	return s
