class_name SafehouseScene
extends Node2D

# ── Constants ─────────────────────────────────────────────────────────────────

const WALL_T        := 32.0
const DOOR_W        := 120.0
const MOVE_SPD      := 160.0
const INTERACT_DIST := 110.0
const WORLD_W       := 1808.0
const WORLD_H       := 896.0

# 3-column × 2-row grid of 560×400 rooms separated by 32px walls
# col inner x
const C0X1 := 32.0;   const C0X2 := 592.0
const C1X1 := 624.0;  const C1X2 := 1184.0
const C2X1 := 1216.0; const C2X2 := 1776.0
# row inner y
const R0Y1 := 32.0;   const R0Y2 := 432.0
const R1Y1 := 464.0;  const R1Y2 := 864.0

# Room layout (row 0 = top, row 1 = bottom)
# Row 0: Living | Workshop | Planning
# Row 1: Stash  | Entry    | Armory
# Exit door on south wall of Entry

# ── State ─────────────────────────────────────────────────────────────────────

var _player:          CharacterBody2D
var _player_sprite:   Sprite2D
var _inv_sys:         InventorySystem
var _inv_ui:          CanvasLayer
var _ui_layer:        CanvasLayer
var _workshop_panel:  CanvasLayer
var _interact_btns:   Dictionary = {}   # station id → Button
var _stat_fills:      Dictionary = {}   # stat name → ColorRect fill node
var _playtime:        float = 0.0
var _resting:         bool  = false

# ── Ready ─────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_playtime = GameState.playtime
	_build_floors()
	_build_walls()
	_build_station_visuals()
	_build_player()
	_build_inventory()
	_build_ui()
	_build_workshop_panel()

# ── Floors ────────────────────────────────────────────────────────────────────

func _build_floors() -> void:
	var rooms := [
		[Rect2(C0X1, R0Y1, 560, 400), Color(0.13, 0.09, 0.07)],  # living
		[Rect2(C1X1, R0Y1, 560, 400), Color(0.07, 0.09, 0.14)],  # workshop
		[Rect2(C2X1, R0Y1, 560, 400), Color(0.07, 0.10, 0.13)],  # planning
		[Rect2(C0X1, R1Y1, 560, 400), Color(0.07, 0.11, 0.08)],  # stash
		[Rect2(C1X1, R1Y1, 560, 400), Color(0.09, 0.08, 0.10)],  # entry
		[Rect2(C2X1, R1Y1, 560, 400), Color(0.13, 0.08, 0.06)],  # armory
	]
	for info: Array in rooms:
		var r: Rect2   = info[0]
		var col: Color = info[1]
		var bg := ColorRect.new()
		bg.position = r.position
		bg.size     = r.size
		bg.color    = col
		add_child(bg)
		var step := 40.0
		var lx := r.position.x + step
		while lx < r.position.x + r.size.x:
			_floor_line(Vector2(lx, r.position.y), Vector2(1, r.size.y), col)
			lx += step
		var ly := r.position.y + step
		while ly < r.position.y + r.size.y:
			_floor_line(Vector2(r.position.x, ly), Vector2(r.size.x, 1), col)
			ly += step

func _floor_line(pos: Vector2, sz: Vector2, base_col: Color) -> void:
	var l := ColorRect.new()
	l.color    = base_col.lightened(0.07)
	l.position = pos
	l.size     = sz
	add_child(l)

# ── Walls ─────────────────────────────────────────────────────────────────────

func _build_walls() -> void:
	var wc := Color(0.16, 0.14, 0.12)

	# Outer perimeter
	_wall(Vector2(0, 0),     Vector2(WORLD_W, WALL_T), wc)   # north
	_wall(Vector2(0, 0),     Vector2(WALL_T, WORLD_H), wc)   # west
	_wall(Vector2(C2X2, 0),  Vector2(WALL_T, WORLD_H), wc)   # east
	# South wall with exit door gap centred on Entry (x = 844→964)
	var _edx := _cx(1) - DOOR_W * 0.5                        # 844
	_wall(Vector2(0,          R1Y2), Vector2(_edx,             WALL_T), wc)
	_wall(Vector2(_edx + DOOR_W, R1Y2), Vector2(WORLD_W - _edx - DOOR_W, WALL_T), wc)

	# Exit door frame accent (south of entry)
	var ef := ColorRect.new()
	ef.position = Vector2(C1X1 + (C1X2 - C1X1) * 0.5 - DOOR_W * 0.5 - 4, R1Y2 - 4)
	ef.size     = Vector2(DOOR_W + 8, WALL_T + 8)
	ef.color    = Color(0.20, 0.55, 0.28, 0.45)
	add_child(ef)

	# Horizontal divider row0/row1 (y=R0Y2..R1Y1) — 3 doors
	var hsegs := [
		[C0X1, C0X1 + (C0X2 - C0X1) * 0.5 - DOOR_W * 0.5],     # left of col0 door
		[C0X1 + (C0X2 - C0X1) * 0.5 + DOOR_W * 0.5, C1X1 + (C1X2 - C1X1) * 0.5 - DOOR_W * 0.5],  # between col0 and col1 doors
		[C1X1 + (C1X2 - C1X1) * 0.5 + DOOR_W * 0.5, C2X1 + (C2X2 - C2X1) * 0.5 - DOOR_W * 0.5],  # between col1 and col2 doors
		[C2X1 + (C2X2 - C2X1) * 0.5 + DOOR_W * 0.5, C2X2],      # right of col2 door
	]
	for seg: Array in hsegs:
		var x0: float = seg[0]
		var x1: float = seg[1]
		if x1 > x0:
			_wall(Vector2(x0, R0Y2), Vector2(x1 - x0, WALL_T), wc)

	# Door frame accents for horizontal divider
	for col_cx in [_cx(0), _cx(1), _cx(2)]:
		var acc := ColorRect.new()
		acc.position = Vector2(col_cx - DOOR_W * 0.5 - 4, R0Y2 - 4)
		acc.size     = Vector2(DOOR_W + 8, WALL_T + 8)
		acc.color    = Color(0.18, 0.18, 0.22, 0.40)
		add_child(acc)

	# Vertical divider col0/col1 (x=C0X2..C1X1) — 2 doors
	var v01_segs := [
		[R0Y1, _cy(0) - DOOR_W * 0.5],
		[_cy(0) + DOOR_W * 0.5, _cy(1) - DOOR_W * 0.5],
		[_cy(1) + DOOR_W * 0.5, R1Y2],
	]
	for seg: Array in v01_segs:
		var y0: float = seg[0]
		var y1: float = seg[1]
		if y1 > y0:
			_wall(Vector2(C0X2, y0), Vector2(WALL_T, y1 - y0), wc)

	# Vertical divider col1/col2 (x=C1X2..C2X1) — 2 doors
	for seg: Array in v01_segs:
		var y0: float = seg[0]
		var y1: float = seg[1]
		if y1 > y0:
			_wall(Vector2(C1X2, y0), Vector2(WALL_T, y1 - y0), wc)

	# Door frame accents for vertical dividers
	for ry in [_cy(0), _cy(1)]:
		for dx in [C0X2, C1X2]:
			var acc := ColorRect.new()
			acc.position = Vector2(dx - 4, ry - DOOR_W * 0.5 - 4)
			acc.size     = Vector2(WALL_T + 8, DOOR_W + 8)
			acc.color    = Color(0.18, 0.18, 0.22, 0.40)
			add_child(acc)

func _wall(pos: Vector2, sz: Vector2, col: Color) -> void:
	var vis := ColorRect.new()
	vis.position = pos
	vis.size     = sz
	vis.color    = col
	add_child(vis)

	var body  := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rect  := RectangleShape2D.new()
	rect.size       = sz
	shape.position  = pos + sz * 0.5
	shape.shape     = rect
	body.add_child(shape)
	add_child(body)

# Room centre helpers
func _cx(col: int) -> float:
	match col:
		0: return (C0X1 + C0X2) * 0.5
		1: return (C1X1 + C1X2) * 0.5
		_: return (C2X1 + C2X2) * 0.5

func _cy(row: int) -> float:
	return (R0Y1 + R0Y2) * 0.5 if row == 0 else (R1Y1 + R1Y2) * 0.5

# ── Station visuals ───────────────────────────────────────────────────────────

const _STATIONS := [
	{"id": "exit",     "name": "EXIT",     "pos": Vector2(904, 820),
	 "color": Color(0.15, 0.48, 0.22), "size": Vector2(80, 60),  "active": true},
	{"id": "stash",    "name": "STASH",    "pos": Vector2(312, 664),
	 "color": Color(0.10, 0.30, 0.20), "size": Vector2(120, 300), "active": true},
	{"id": "armory",   "name": "ARMORY",   "pos": Vector2(1496, 664),
	 "color": Color(0.38, 0.18, 0.08), "size": Vector2(260, 120), "active": false},
	{"id": "workshop", "name": "WORKSHOP", "pos": Vector2(904, 200),
	 "color": Color(0.14, 0.22, 0.40), "size": Vector2(440, 80),  "active": true},
	{"id": "bed",      "name": "REST",     "pos": Vector2(312, 180),
	 "color": Color(0.28, 0.20, 0.12), "size": Vector2(280, 68),  "active": true},
	{"id": "planning", "name": "PLANNING", "pos": Vector2(1496, 232),
	 "color": Color(0.20, 0.28, 0.38), "size": Vector2(420, 68),  "active": false},
]

func _build_station_visuals() -> void:
	for s: Dictionary in _STATIONS:
		var pos: Vector2  = s["pos"]
		var sz: Vector2   = s["size"]
		var col: Color    = s["color"]
		var half          := sz * 0.5

		# Background
		var bg := ColorRect.new()
		bg.position = pos - half
		bg.size     = sz
		bg.color    = col.darkened(0.55)
		add_child(bg)

		# Border edges
		for edge: Rect2 in [
			Rect2(pos - half,                           Vector2(sz.x, 2)),
			Rect2(pos - half + Vector2(0, sz.y - 2),    Vector2(sz.x, 2)),
			Rect2(pos - half,                           Vector2(2, sz.y)),
			Rect2(pos - half + Vector2(sz.x - 2, 0),    Vector2(2, sz.y)),
		]:
			var line := ColorRect.new()
			line.position = edge.position
			line.size     = edge.size
			line.color    = col.lightened(0.1)
			add_child(line)

		# Name label
		var lbl := Label.new()
		lbl.text = s["name"]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", col.lightened(0.6))
		lbl.position = pos - half + Vector2(0, sz.y * 0.5 - 8)
		lbl.size     = Vector2(sz.x, 18)
		add_child(lbl)

# ── Player ────────────────────────────────────────────────────────────────────

func _build_player() -> void:
	_player = CharacterBody2D.new()
	_player.position    = Vector2(_cx(1), _cy(1))   # spawn in Entry
	_player.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING

	_player_sprite = Sprite2D.new()
	_player_sprite.texture = load("res://assets/Player.png")
	_player_sprite.scale   = Vector2(0.7, 0.7)
	_player.add_child(_player_sprite)

	var col   := CollisionShape2D.new()
	var shape := CapsuleShape2D.new()
	shape.radius = 10.0
	shape.height = 30.0
	col.rotation = PI / 2
	col.scale    = Vector2(4, 4)
	col.shape    = shape
	_player.add_child(col)

	# Camera follows player
	var cam := Camera2D.new()
	cam.limit_left   = 0
	cam.limit_top    = 0
	cam.limit_right  = int(WORLD_W)
	cam.limit_bottom = int(WORLD_H)
	_player.add_child(cam)

	add_child(_player)

# ── Inventory ─────────────────────────────────────────────────────────────────

func _build_inventory() -> void:
	_inv_sys = InventorySystem.new()
	add_child(_inv_sys)

	if GameState.save_data.has("inventory"):
		_inv_sys.load_from_dict(GameState.save_data["inventory"])
	else:
		_seed_items()

	_inv_ui = load("res://inventory/ui/InventoryUI.tscn").instantiate() as CanvasLayer
	_inv_ui.layer = 12
	add_child(_inv_ui)
	_inv_ui.setup(_inv_sys)
	_inv_ui.visibility_changed.connect(func():
		TouchInputHandler.joystick_disabled = _inv_ui.visible)

func _seed_items() -> void:
	var helmet := Item.new()
	helmet.item_id = "helmet_basic"; helmet.display_name = "Basic Helmet"
	helmet.type = "helmet"; helmet.grid_size = Vector2i(1, 1)
	_inv_sys.equip("helmet", helmet)

	var ammo := Item.new()
	ammo.item_id = "ammo_9mm"; ammo.display_name = "9mm x60"
	ammo.type = "consumable"; ammo.grid_size = Vector2i(1, 2); ammo.quantity = 60
	_inv_sys.auto_add_to_backpack(ammo)

	var medkit := Item.new()
	medkit.item_id = "medkit"; medkit.display_name = "Medkit"
	medkit.type = "consumable"; medkit.grid_size = Vector2i(2, 2)
	_inv_sys.auto_add_to_backpack(medkit)

# ── HUD / UI layer ────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 5
	add_child(_ui_layer)

	# Header
	var hdr := Label.new()
	hdr.text = "HIDEOUT  ·  SLOT %d" % (GameState.save_slot + 1)
	hdr.position = Vector2(12, 6)
	hdr.add_theme_font_size_override("font_size", 14)
	hdr.add_theme_color_override("font_color", Color(0.80, 0.68, 0.28))
	_ui_layer.add_child(hdr)

	# Stat panel top-right
	_ui_layer.add_child(_make_stat_panel())

	# Proximity interaction buttons (one per station)
	for s: Dictionary in _STATIONS:
		var btn := _make_station_btn(s)
		_ui_layer.add_child(btn)
		_interact_btns[s["id"]] = btn

func _make_station_btn(s: Dictionary) -> Button:
	var active: bool = s["active"]
	var col: Color   = s["color"]

	var btn := Button.new()
	btn.text    = s["name"]
	btn.visible = false
	btn.custom_minimum_size = Vector2(120, 38)
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", Color.WHITE)

	var sty := StyleBoxFlat.new()
	sty.bg_color = col if active else Color(0.25, 0.25, 0.30)
	sty.set_corner_radius_all(5)
	btn.add_theme_stylebox_override("normal", sty)

	var sty_h := sty.duplicate() as StyleBoxFlat
	sty_h.bg_color = col.lightened(0.2) if active else Color(0.30, 0.30, 0.36)
	btn.add_theme_stylebox_override("hover", sty_h)

	if active:
		var captured_id: String = s["id"]
		btn.pressed.connect(func(): _on_station_action(captured_id))
	else:
		btn.disabled = true

	# Position button above station (world → screen: coords are the same here
	# because the camera scrolls but CanvasLayer stays fixed — so we update position in _process)
	return btn

func _make_stat_panel() -> Control:
	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	vb.offset_left  = -210
	vb.offset_right = -8
	vb.offset_top   = 8
	vb.add_theme_constant_override("separation", 3)

	var sv: Dictionary = GameState.save_data.get("survival",
		{"stamina": 100.0, "hunger": 100.0, "thirst": 100.0})
	var hp     := float(GameState.save_data.get("health", 100))
	var hp_max := float(GameState.save_data.get("max_health", 100))

	_add_stat_row(vb, "HP",     Color(0.22, 0.65, 0.28), hp / hp_max,                        "hp")
	_add_stat_row(vb, "STA",    Color(0.25, 0.48, 0.78), sv.get("stamina", 100.0) / 100.0,   "stamina")
	_add_stat_row(vb, "HUNGER", Color(0.72, 0.50, 0.16), sv.get("hunger",  100.0) / 100.0,   "hunger")
	_add_stat_row(vb, "THIRST", Color(0.28, 0.55, 0.72), sv.get("thirst",  100.0) / 100.0,   "thirst")

	return vb

func _add_stat_row(parent: VBoxContainer, label: String, col: Color, ratio: float, key: String) -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 5)
	parent.add_child(hbox)

	var lbl := Label.new()
	lbl.text = label
	lbl.custom_minimum_size = Vector2(52, 0)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(0.58, 0.58, 0.65))
	hbox.add_child(lbl)

	var bg := PanelContainer.new()
	bg.custom_minimum_size = Vector2(140, 10)
	var s_bg := StyleBoxFlat.new()
	s_bg.bg_color = Color(0.15, 0.15, 0.20)
	s_bg.set_corner_radius_all(3)
	bg.add_theme_stylebox_override("panel", s_bg)

	var fill := ColorRect.new()
	fill.color = col
	fill.size  = Vector2(140.0 * clampf(ratio, 0.0, 1.0), 10)
	fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	bg.add_child(fill)
	hbox.add_child(bg)

	_stat_fills[key] = fill

# ── Workshop panel ────────────────────────────────────────────────────────────

func _build_workshop_panel() -> void:
	_workshop_panel = CanvasLayer.new()
	_workshop_panel.layer   = 14
	_workshop_panel.visible = false
	add_child(_workshop_panel)

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.10, 0.92)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_workshop_panel.add_child(bg)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	_workshop_panel.add_child(root)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(600, 400)
	panel.offset_left  = -300
	panel.offset_top   = -200
	panel.offset_right  = 300
	panel.offset_bottom = 200
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.07, 0.08, 0.13)
	ps.set_border_width_all(2)
	ps.border_color = Color(0.20, 0.25, 0.40)
	ps.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", ps)
	root.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 20)
	panel.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	margin.add_child(vb)

	# Header
	var hdr_hbox := HBoxContainer.new()
	vb.add_child(hdr_hbox)
	var title := Label.new()
	title.text = "WORKSHOP"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.55, 0.70, 0.90))
	hdr_hbox.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "✕  CLOSE"
	close_btn.add_theme_font_size_override("font_size", 12)
	var close_sty := StyleBoxFlat.new()
	close_sty.bg_color = Color(0.20, 0.20, 0.28)
	close_sty.set_corner_radius_all(4)
	close_btn.add_theme_stylebox_override("normal", close_sty)
	close_btn.pressed.connect(func(): _workshop_panel.visible = false)
	hdr_hbox.add_child(close_btn)

	# Info text
	var info := Label.new()
	info.text = "Barrel, stock and muzzle device modifications are only available here.\nRail attachments (sights, grips) can be swapped in the field."
	info.add_theme_font_size_override("font_size", 11)
	info.add_theme_color_override("font_color", Color(0.55, 0.55, 0.60))
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(info)

	var sep := ColorRect.new()
	sep.color = Color(0.20, 0.25, 0.40, 0.6)
	sep.custom_minimum_size = Vector2(0, 1)
	vb.add_child(sep)

	# Mod slot grid
	var grid_lbl := Label.new()
	grid_lbl.text = "MOD SLOTS  (workshop-only)"
	grid_lbl.add_theme_font_size_override("font_size", 12)
	grid_lbl.add_theme_color_override("font_color", Color(0.70, 0.70, 0.80))
	vb.add_child(grid_lbl)

	var slots_hbox := HBoxContainer.new()
	slots_hbox.add_theme_constant_override("separation", 10)
	vb.add_child(slots_hbox)

	for slot_info: Array in [
		["BARREL",  "Affects damage falloff,\nmuzzle velocity & sound level",  Color(0.40, 0.25, 0.10)],
		["STOCK",   "Affects recoil recovery\nand ADS speed",                  Color(0.22, 0.30, 0.22)],
		["MUZZLE",  "Suppressor, compensator,\nor flash hider",                Color(0.22, 0.22, 0.32)],
	]:
		slots_hbox.add_child(_mod_slot(slot_info[0], slot_info[1], slot_info[2]))

	var field_lbl := Label.new()
	field_lbl.text = "FIELD-SWAPPABLE"
	field_lbl.add_theme_font_size_override("font_size", 12)
	field_lbl.add_theme_color_override("font_color", Color(0.70, 0.70, 0.80))
	vb.add_child(field_lbl)

	var field_hbox := HBoxContainer.new()
	field_hbox.add_theme_constant_override("separation", 10)
	vb.add_child(field_hbox)

	for slot_info: Array in [
		["SIGHT / OPTIC", "Current: Iron Sights",     Color(0.18, 0.32, 0.18)],
		["GRIP / RAIL",   "Underbarrel grip or laser", Color(0.18, 0.24, 0.32)],
	]:
		field_hbox.add_child(_mod_slot(slot_info[0], slot_info[1], slot_info[2]))

func _mod_slot(slot_name: String, desc: String, col: Color) -> Control:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(0, 80)
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ps := StyleBoxFlat.new()
	ps.bg_color = col.darkened(0.55)
	ps.set_border_width_all(1)
	ps.border_color = col.lightened(0.1)
	ps.set_corner_radius_all(4)
	pc.add_theme_stylebox_override("panel", ps)

	var m := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(side, 8)
	pc.add_child(m)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	m.add_child(vb)

	var name_lbl := Label.new()
	name_lbl.text = slot_name
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.add_theme_color_override("font_color", col.lightened(0.55))
	vb.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = desc
	desc_lbl.add_theme_font_size_override("font_size", 9)
	desc_lbl.add_theme_color_override("font_color", Color(0.50, 0.50, 0.55))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(desc_lbl)

	var empty_lbl := Label.new()
	empty_lbl.text = "[ EMPTY ]"
	empty_lbl.add_theme_font_size_override("font_size", 9)
	empty_lbl.add_theme_color_override("font_color", Color(0.35, 0.35, 0.40))
	empty_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	empty_lbl.vertical_alignment  = VERTICAL_ALIGNMENT_BOTTOM
	vb.add_child(empty_lbl)

	return pc

# ── Runtime ───────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	_playtime += delta
	GameState.playtime = _playtime
	_move_player(delta)
	_update_interaction_buttons()

func _move_player(delta: float) -> void:
	var dir := TouchInputHandler.get_move_vector()
	if dir.length_squared() > 0.01:
		_player.velocity       = dir * MOVE_SPD
		_player_sprite.rotation = dir.angle() + PI * 0.5
	else:
		_player.velocity = _player.velocity.move_toward(Vector2.ZERO, MOVE_SPD * 8.0 * delta)
	_player.move_and_slide()

func _update_interaction_buttons() -> void:
	# Skip button updates while any overlay is open
	var any_open := (_workshop_panel != null and _workshop_panel.visible) \
		or (_inv_ui != null and _inv_ui.visible)

	var screen_origin := _player.global_position - get_viewport().get_visible_rect().size * 0.5

	for s: Dictionary in _STATIONS:
		var id:  String  = s["id"]
		var btn: Button  = _interact_btns.get(id)
		if btn == null:
			continue
		var station_world: Vector2 = s["pos"]
		var dist := _player.global_position.distance_to(station_world)
		var in_range := dist < INTERACT_DIST and not any_open
		btn.visible = in_range
		if in_range:
			# Convert world position to screen position
			var screen_pos := station_world - screen_origin
			btn.position = screen_pos + Vector2(-60, -50)

# ── Station actions ───────────────────────────────────────────────────────────

func _on_station_action(id: String) -> void:
	match id:
		"stash":
			_inv_ui.toggle()
		"exit":
			_deploy()
		"workshop":
			_workshop_panel.visible = true
		"bed":
			_do_rest()

func _do_rest() -> void:
	if _resting:
		return
	_resting = true

	# Restore all stats to max in GameState
	var hp_max := int(GameState.save_data.get("max_health", 100))
	GameState.save_data["health"] = hp_max
	if not GameState.save_data.has("survival"):
		GameState.save_data["survival"] = {}
	GameState.save_data["survival"]["stamina"] = 100.0
	GameState.save_data["survival"]["hunger"]  = 100.0
	GameState.save_data["survival"]["thirst"]  = 100.0

	# Animate stat bars
	var tween := create_tween()
	tween.set_parallel(true)
	_tween_stat(tween, "hp",     1.0)
	_tween_stat(tween, "stamina", 1.0)
	_tween_stat(tween, "hunger",  1.0)
	_tween_stat(tween, "thirst",  1.0)
	tween.finished.connect(func(): _resting = false)

func _tween_stat(tween: Tween, key: String, target_ratio: float) -> void:
	var fill: ColorRect = _stat_fills.get(key)
	if fill == null:
		return
	tween.tween_property(fill, "size:x", 140.0 * target_ratio, 1.2)

func _deploy() -> void:
	GameState.save_data["inventory"] = _inv_sys.to_dict()
	GameState.playtime = _playtime
	get_tree().change_scene_to_file("res://main.tscn")
