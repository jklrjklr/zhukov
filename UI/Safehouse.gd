class_name Safehouse
extends CanvasLayer

signal deployed

const _LAYER := 15

var _slot: int = 0
var _playtime: float = 0.0
var _player: Player = null
var _inventory_ui: CanvasLayer = null

func setup(slot: int, playtime: float, player: Player, inventory_ui: CanvasLayer) -> void:
	_slot         = slot
	_playtime     = playtime
	_player       = player
	_inventory_ui = inventory_ui

func _ready() -> void:
	layer        = _LAYER
	process_mode = PROCESS_MODE_ALWAYS
	if _inventory_ui != null:
		_inventory_ui.layer = _LAYER + 1
	_build()

# ── Build ─────────────────────────────────────────────────────────────────────

func _build() -> void:
	# Background
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.07, 0.09)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	# Full-height VBox: header | body | footer
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 0)
	root.add_child(layout)

	layout.add_child(_build_header())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	var body_margin := MarginContainer.new()
	body_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_margin.add_theme_constant_override("margin_left",   24)
	body_margin.add_theme_constant_override("margin_right",  24)
	body_margin.add_theme_constant_override("margin_top",    20)
	body_margin.add_theme_constant_override("margin_bottom", 20)
	body_margin.add_child(body)
	layout.add_child(body_margin)

	# Left: station grid
	var stations := VBoxContainer.new()
	stations.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stations.add_theme_constant_override("separation", 16)
	body.add_child(stations)

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 16)
	row1.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row1.add_child(_station("STASH",     "Open your inventory and manage\nyour gear before deploying.",
		Color(0.10, 0.38, 0.24), true))
	row1.add_child(_station("ARMORY",    "Configure your weapon loadout\nand attached equipment.",
		Color(0.40, 0.20, 0.08), false))
	row1.add_child(_station("WORKBENCH", "Modify weapons, craft items\nand upgrade your equipment.",
		Color(0.12, 0.22, 0.45), false))
	stations.add_child(row1)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 16)
	row2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row2.add_child(_station("INTEL",   "Mission briefing, area maps\nand enemy intelligence.",
		Color(0.32, 0.14, 0.38), false))
	row2.add_child(_station("TRADING", "Buy and sell items with\nthe local network.",
		Color(0.14, 0.28, 0.36), false))
	row2.add_child(_station("REST",    "Recover stamina and health\nbefore your next operation.",
		Color(0.28, 0.22, 0.10), false))
	stations.add_child(row2)

	# Right: player status panel
	var right_margin := MarginContainer.new()
	right_margin.add_theme_constant_override("margin_left", 16)
	right_margin.custom_minimum_size = Vector2(230, 0)
	right_margin.add_child(_build_player_panel())
	body.add_child(right_margin)

	layout.add_child(_build_footer())

# ── Header ────────────────────────────────────────────────────────────────────

func _build_header() -> Control:
	var pc := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.04, 0.06)
	style.border_color = Color(0.20, 0.18, 0.14)
	style.border_width_bottom = 1
	pc.add_theme_stylebox_override("panel", style)
	pc.custom_minimum_size = Vector2(0, 62)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",  20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top",    0)
	margin.add_theme_constant_override("margin_bottom", 0)
	pc.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(hbox)

	var title := Label.new()
	title.text = "HIDEOUT"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.85, 0.72, 0.30))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(title)

	var info := Label.new()
	var pt := _fmt(_playtime)
	info.text = "SLOT %d   ·   %s" % [_slot + 1, pt]
	info.add_theme_font_size_override("font_size", 14)
	info.add_theme_color_override("font_color", Color(0.55, 0.55, 0.60))
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(info)

	return pc

# ── Station card ──────────────────────────────────────────────────────────────

func _station(title: String, desc: String, accent: Color, active: bool) -> Control:
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.size_flags_vertical   = Control.SIZE_EXPAND_FILL

	var style := StyleBoxFlat.new()
	style.bg_color = accent.darkened(0.60)
	style.set_border_width_all(2)
	style.border_color = accent.darkened(0.10)
	style.set_corner_radius_all(8)
	pc.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   16)
	margin.add_theme_constant_override("margin_right",  16)
	margin.add_theme_constant_override("margin_top",    14)
	margin.add_theme_constant_override("margin_bottom", 14)
	pc.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	margin.add_child(vb)

	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_color", accent.lightened(0.55))
	vb.add_child(title_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = desc
	desc_lbl.add_theme_font_size_override("font_size", 10)
	desc_lbl.add_theme_color_override("font_color", Color(0.58, 0.58, 0.63))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(desc_lbl)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(spacer)

	if active:
		var btn := Button.new()
		btn.text = "OPEN"
		btn.custom_minimum_size = Vector2(0, 34)
		btn.add_theme_color_override("font_color", Color.WHITE)
		btn.add_theme_font_size_override("font_size", 13)
		btn.add_theme_stylebox_override("normal",  _flat(accent))
		btn.add_theme_stylebox_override("hover",   _flat(accent.lightened(0.18)))
		btn.add_theme_stylebox_override("pressed", _flat(accent.darkened(0.15)))
		btn.pressed.connect(_open_stash)
		vb.add_child(btn)
	else:
		var tag := Label.new()
		tag.text = "COMING SOON"
		tag.add_theme_font_size_override("font_size", 10)
		tag.add_theme_color_override("font_color", Color(0.38, 0.38, 0.42))
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(tag)

	return pc

# ── Player status panel ───────────────────────────────────────────────────────

func _build_player_panel() -> Control:
	var pc := PanelContainer.new()
	pc.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.85)
	style.set_border_width_all(1)
	style.border_color = Color(0.18, 0.18, 0.24)
	style.set_corner_radius_all(8)
	pc.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   16)
	margin.add_theme_constant_override("margin_right",  16)
	margin.add_theme_constant_override("margin_top",    16)
	margin.add_theme_constant_override("margin_bottom", 16)
	pc.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	margin.add_child(vb)

	# Title
	var header := Label.new()
	header.text = "OPERATOR"
	header.add_theme_font_size_override("font_size", 13)
	header.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(header)

	# Silhouette placeholder
	var silhouette := ColorRect.new()
	silhouette.color = Color(0.14, 0.14, 0.20)
	silhouette.custom_minimum_size = Vector2(0, 110)
	silhouette.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(silhouette)

	var silhouette_lbl := Label.new()
	silhouette_lbl.text = "[ OPERATOR ]"
	silhouette_lbl.add_theme_font_size_override("font_size", 11)
	silhouette_lbl.add_theme_color_override("font_color", Color(0.30, 0.30, 0.38))
	silhouette_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	silhouette_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	silhouette_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	silhouette.add_child(silhouette_lbl)

	# Stat bars
	vb.add_child(_stat_bar("HEALTH",  Color(0.20, 0.65, 0.25),
		float(_player.health) / float(_player.max_health) if _player else 1.0))
	vb.add_child(_stat_bar("STAMINA", Color(0.25, 0.45, 0.75),
		_player.survival.stamina / 100.0 if _player else 1.0))
	vb.add_child(_stat_bar("HUNGER",  Color(0.70, 0.50, 0.15),
		_player.survival.hunger  / 100.0 if _player else 1.0))

	return pc

func _stat_bar(label: String, color: Color, ratio: float) -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)

	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(0.60, 0.60, 0.65))
	vb.add_child(lbl)

	var bar_bg := PanelContainer.new()
	bar_bg.custom_minimum_size = Vector2(0, 8)
	var bg_s := StyleBoxFlat.new()
	bg_s.bg_color = Color(0.15, 0.15, 0.20)
	bg_s.set_corner_radius_all(3)
	bar_bg.add_theme_stylebox_override("panel", bg_s)

	var bar_fill := ColorRect.new()
	bar_fill.color = color
	bar_fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	bar_fill.size.x = 0  # will be set after layout
	bar_fill.set_meta("ratio", ratio)
	bar_bg.add_child(bar_fill)

	# Resize bar fill proportionally after layout
	bar_bg.resized.connect(func():
		var r: float = bar_fill.get_meta("ratio")
		bar_fill.size = Vector2(bar_bg.size.x * r, bar_bg.size.y))

	vb.add_child(bar_bg)
	return vb

# ── Footer ────────────────────────────────────────────────────────────────────

func _build_footer() -> Control:
	var pc := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.04, 0.06)
	style.border_color = Color(0.20, 0.18, 0.14)
	style.border_width_top = 1
	pc.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   20)
	margin.add_theme_constant_override("margin_right",  20)
	margin.add_theme_constant_override("margin_top",    10)
	margin.add_theme_constant_override("margin_bottom", 10)
	pc.add_child(margin)

	var hbox := HBoxContainer.new()
	margin.add_child(hbox)

	var hint := Label.new()
	hint.text = "Select a station or deploy directly to the field."
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.42, 0.42, 0.48))
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(hint)

	var deploy := Button.new()
	deploy.text = "DEPLOY TO FIELD  ▶"
	deploy.custom_minimum_size = Vector2(220, 48)
	deploy.add_theme_font_size_override("font_size", 15)
	deploy.add_theme_color_override("font_color", Color.WHITE)
	deploy.add_theme_stylebox_override("normal",  _flat(Color(0.12, 0.45, 0.22)))
	deploy.add_theme_stylebox_override("hover",   _flat(Color(0.16, 0.55, 0.28)))
	deploy.add_theme_stylebox_override("pressed", _flat(Color(0.09, 0.35, 0.18)))
	deploy.pressed.connect(_on_deploy)
	hbox.add_child(deploy)

	return pc

# ── Actions ───────────────────────────────────────────────────────────────────

func _open_stash() -> void:
	if _inventory_ui != null:
		_inventory_ui.toggle()

func _on_deploy() -> void:
	if _inventory_ui != null:
		_inventory_ui.layer = 1
		if _inventory_ui.visible:
			_inventory_ui.toggle()
	deployed.emit()
	queue_free()

# ── Helpers ───────────────────────────────────────────────────────────────────

func _fmt(secs: float) -> String:
	var h := int(secs) / 3600
	var m := (int(secs) % 3600) / 60
	if h > 0:
		return "%dh %02dm" % [h, m]
	return "%dm %02ds" % [m, int(secs) % 60]

func _flat(col: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.set_corner_radius_all(5)
	return s
