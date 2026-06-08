class_name SafehouseScene
extends Node2D

# ── Constants ─────────────────────────────────────────────────────────────────

const WALL_T        := 32.0
const DOOR_W        := 120.0
const INTERACT_DIST := 110.0
const WORLD_W       := 1808.0
const WORLD_H       := 896.0    # two rows + outer walls

# 3-col × 2-row layout:
#  Row 0 (top): Living | Workshop | Planning
#  Row 1 (mid): Stash  | Entry    | Armory
const C0X1 := 32.0;   const C0X2 := 592.0
const C1X1 := 624.0;  const C1X2 := 1184.0
const C2X1 := 1216.0; const C2X2 := 1776.0
const R0Y1 := 32.0;   const R0Y2 := 432.0
const R1Y1 := 464.0;  const R1Y2 := 864.0

# ── Scene references ──────────────────────────────────────────────────────────

@onready var _player:      Player      = $Player
@onready var _ads_overlay: CanvasLayer = $AdsOverlay

# ── Station definitions ───────────────────────────────────────────────────────

const _STATIONS := [
	{"id": "shooting_range", "name": "RANGE",    "pos": Vector2(904, 510),
	 "color": Color(0.30, 0.20, 0.08), "size": Vector2(80, 50),   "active": true},
	{"id": "exit",           "name": "EXIT",     "pos": Vector2(904, 800),
	 "color": Color(0.15, 0.48, 0.22), "size": Vector2(60, 50),   "active": true},
	{"id": "stash",          "name": "STASH",    "pos": Vector2(312, 664),
	 "color": Color(0.10, 0.30, 0.20), "size": Vector2(120, 300), "active": true},
	{"id": "armory",         "name": "ARMORY",   "pos": Vector2(1496, 664),
	 "color": Color(0.38, 0.18, 0.08), "size": Vector2(260, 120), "active": false},
	{"id": "workshop",       "name": "WORKSHOP", "pos": Vector2(904, 200),
	 "color": Color(0.14, 0.22, 0.40), "size": Vector2(440, 80),  "active": true},
	{"id": "bed",            "name": "REST",     "pos": Vector2(312, 180),
	 "color": Color(0.28, 0.20, 0.12), "size": Vector2(280, 68),  "active": true},
	{"id": "planning",       "name": "PLANNING", "pos": Vector2(1496, 232),
	 "color": Color(0.20, 0.28, 0.38), "size": Vector2(420, 68),  "active": false},
]

# ── State ─────────────────────────────────────────────────────────────────────

var _inv_ui:         CanvasLayer
var _workshop_panel: CanvasLayer
var _local_ui:       CanvasLayer
var _interact_btns:  Dictionary = {}   # station id → Button
var _playtime:       float = 0.0
var _resting:        bool  = false

# ── Ready ─────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_playtime = GameState.playtime
	_setup_player()
	_build_floor_tilemap()
	_build_walls()
	_build_station_visuals()
	_build_inventory()
	_build_local_ui()
	_build_workshop_panel()

# ── Player setup ──────────────────────────────────────────────────────────────

func _setup_player() -> void:
	var save_data := GameState.save_data

	# Restore health
	if save_data.has("health"):
		_player.health     = int(save_data["health"])
		_player.max_health = int(save_data.get("max_health", 100))

	# Spawn in centre of Entry Hall
	_player.global_position = Vector2(_cx(1), _cy(1))

	# Restore survival
	if save_data.has("survival"):
		var sv: Dictionary = save_data["survival"]
		_player.survival.stamina = float(sv.get("stamina", 100.0))
		_player.survival.hunger  = float(sv.get("hunger",  100.0))
		_player.survival.thirst  = float(sv.get("thirst",  100.0))

	# Camera world limits
	var cam := _player.get_node("Camera2D") as PlayerCamera
	cam.rotation      = 0.0
	cam.limit_enabled = true
	cam.limit_left    = 0
	cam.limit_top     = 0
	cam.limit_right   = int(WORLD_W)
	cam.limit_bottom  = int(WORLD_H)

	# Block weapon fire in safehouse
	(_player.get_node("WeaponSystem") as WeaponSystem).fire_blocked = true

	# FOV overlay — needs player reference for world-space tracking
	_ads_overlay.setup(_player)
	_player.entered_ads.connect(_ads_overlay.show_ads)
	_player.exited_ads.connect(_ads_overlay.hide_ads)
	$HUD.ads_pressed.connect(_on_ads_pressed)
	$HUD.ads_released.connect(_player.on_ads_released)

	# Pause signal → no pause menu in safehouse, just ignore
	$HUD.pause_requested.connect(func(): pass)

# ── Floor tilemap ─────────────────────────────────────────────────────────────

func _build_floor_tilemap() -> void:
	const TILE := 16
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(TILE, TILE)

	var src := TileSetAtlasSource.new()
	src.texture = load("res://assets/tiles/safehouse_atlas.png") as Texture2D
	src.texture_region_size = Vector2i(TILE, TILE)
	for i in range(9):
		src.create_tile(Vector2i(i, 0))
	var src_id := tileset.add_source(src)

	var layer := TileMapLayer.new()
	layer.tile_set = tileset
	layer.z_index = -1
	add_child(layer)

	# atlas col → tile index: 0=wall 1=entry 2=living 3=workshop 4=stash 5=armory 6=planning 7=range 8=door_frame
	var rooms: Array = [
		[C0X1, R0Y1, C0X2, R0Y2, 2],  # living
		[C1X1, R0Y1, C1X2, R0Y2, 3],  # workshop
		[C2X1, R0Y1, C2X2, R0Y2, 6],  # planning
		[C0X1, R1Y1, C0X2, R1Y2, 4],  # stash
		[C1X1, R1Y1, C1X2, R1Y2, 1],  # entry
		[C2X1, R1Y1, C2X2, R1Y2, 5],  # armory
	]
	for room: Array in rooms:
		var tx1 := int(room[0]) / TILE
		var ty1 := int(room[1]) / TILE
		var tx2 := int(room[2]) / TILE
		var ty2 := int(room[3]) / TILE
		var tidx: int = int(room[4])
		for tx in range(tx1, tx2):
			for ty in range(ty1, ty2):
				layer.set_cell(Vector2i(tx, ty), src_id, Vector2i(tidx, 0))

# ── Walls ─────────────────────────────────────────────────────────────────────

func _build_walls() -> void:
	var wc := Color(0.16, 0.14, 0.12)

	# Outer perimeter
	_wall(Vector2(0, 0),    Vector2(WORLD_W, WALL_T), wc)   # north
	_wall(Vector2(0, R1Y2), Vector2(WORLD_W, WALL_T), wc)   # south
	_wall(Vector2(0, 0),    Vector2(WALL_T, WORLD_H), wc)   # west
	_wall(Vector2(C2X2, 0), Vector2(WALL_T, WORLD_H), wc)   # east

	# Horizontal row0/row1 divider — 3 doors (one per column)
	_hwall_with_doors(R0Y2, [_cx(0), _cx(1), _cx(2)], wc)

	# Vertical col0/col1 divider — 2 doors (at row centres)
	_vwall_with_doors(C0X2, R0Y1, R1Y2, [_cy(0), _cy(1)], wc)

	# Vertical col1/col2 divider — same
	_vwall_with_doors(C1X2, R0Y1, R1Y2, [_cy(0), _cy(1)], wc)

func _hwall_with_doors(y: float, door_centres_x: Array, col: Color) -> void:
	var xs: Array[float] = [C0X1]
	for cx: float in door_centres_x:
		xs.append(cx - DOOR_W * 0.5)
		xs.append(cx + DOOR_W * 0.5)
	xs.append(C2X2)
	var i := 0
	while i < xs.size() - 1:
		var x0: float = xs[i]
		var x1: float = xs[i + 1]
		if x1 > x0:
			_wall(Vector2(x0, y), Vector2(x1 - x0, WALL_T), col)
		i += 2   # skip door gap
	# Door frame accents
	for cx: float in door_centres_x:
		_door_accent(Vector2(cx - DOOR_W * 0.5 - 4, y - 4), Vector2(DOOR_W + 8, WALL_T + 8))

func _vwall_with_doors(x: float, y_start: float, y_end: float, door_centres_y: Array, col: Color) -> void:
	var ys: Array[float] = [y_start]
	for cy: float in door_centres_y:
		ys.append(cy - DOOR_W * 0.5)
		ys.append(cy + DOOR_W * 0.5)
	ys.append(y_end)
	var i := 0
	while i < ys.size() - 1:
		var y0: float = ys[i]
		var y1: float = ys[i + 1]
		if y1 > y0:
			_wall(Vector2(x, y0), Vector2(WALL_T, y1 - y0), col)
		i += 2
	for cy: float in door_centres_y:
		_door_accent(Vector2(x - 4, cy - DOOR_W * 0.5 - 4), Vector2(WALL_T + 8, DOOR_W + 8))

func _door_accent(pos: Vector2, sz: Vector2) -> void:
	var acc := ColorRect.new()
	acc.position = pos
	acc.size     = sz
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

func _cx(col: int) -> float:
	match col:
		0: return (C0X1 + C0X2) * 0.5   # 312
		1: return (C1X1 + C1X2) * 0.5   # 904
		_: return (C2X1 + C2X2) * 0.5   # 1496

func _cy(row: int) -> float:
	match row:
		0: return (R0Y1 + R0Y2) * 0.5   # 232
		1: return (R1Y1 + R1Y2) * 0.5   # 664
		_: return (R2Y1 + R2Y2) * 0.5   # 1096

# ── Station visuals ───────────────────────────────────────────────────────────

func _build_station_visuals() -> void:
	for s: Dictionary in _STATIONS:
		var pos:  Vector2 = s["pos"]
		var sz:   Vector2 = s["size"]
		var col:  Color   = s["color"]
		var half           := sz * 0.5

		var bg := ColorRect.new()
		bg.position = pos - half
		bg.size     = sz
		bg.color    = col.darkened(0.55)
		add_child(bg)

		for edge: Rect2 in [
			Rect2(pos - half,                         Vector2(sz.x, 2)),
			Rect2(pos - half + Vector2(0, sz.y - 2),  Vector2(sz.x, 2)),
			Rect2(pos - half,                         Vector2(2, sz.y)),
			Rect2(pos - half + Vector2(sz.x - 2, 0),  Vector2(2, sz.y)),
		]:
			var line := ColorRect.new()
			line.position = edge.position
			line.size     = edge.size
			line.color    = col.lightened(0.1)
			add_child(line)

		var lbl := Label.new()
		lbl.text = s["name"]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", col.lightened(0.6))
		lbl.position = pos - half + Vector2(0, sz.y * 0.5 - 8)
		lbl.size     = Vector2(sz.x, 18)
		add_child(lbl)

# ── Inventory ─────────────────────────────────────────────────────────────────

func _build_inventory() -> void:
	if GameState.save_data.has("inventory"):
		_player.inventory.load_from_dict(GameState.save_data["inventory"])
	else:
		_seed_items()

	_inv_ui = load("res://inventory/ui/InventoryUI.tscn").instantiate() as CanvasLayer
	_inv_ui.layer = 12
	add_child(_inv_ui)
	_inv_ui.setup(_player.inventory)
	_inv_ui.visibility_changed.connect(func():
		TouchInputHandler.joystick_disabled = _inv_ui.visible)
	$HUD.inventory_requested.connect(_inv_ui.toggle)

func _seed_items() -> void:
	var helmet := Item.new()
	helmet.item_id = "helmet_basic"; helmet.display_name = "Basic Helmet"
	helmet.type = "helmet"; helmet.grid_size = Vector2i(1, 1)
	_player.inventory.equip("helmet", helmet)

	var ammo := Item.new()
	ammo.item_id = "ammo_9mm"; ammo.display_name = "9mm x60"
	ammo.type = "consumable"; ammo.grid_size = Vector2i(1, 2); ammo.quantity = 60
	_player.inventory.auto_add_to_backpack(ammo)

	var medkit := Item.new()
	medkit.item_id = "medkit"; medkit.display_name = "Medkit"
	medkit.type = "consumable"; medkit.grid_size = Vector2i(2, 2)
	_player.inventory.auto_add_to_backpack(medkit)

# ── Local UI layer ────────────────────────────────────────────────────────────

func _build_local_ui() -> void:
	_local_ui = CanvasLayer.new()
	_local_ui.layer = 3
	add_child(_local_ui)

	# Slot header (below HUD)
	var hdr := Label.new()
	hdr.text = "HIDEOUT  ·  SLOT %d" % (GameState.save_slot + 1)
	hdr.position = Vector2(12, 52)
	hdr.add_theme_font_size_override("font_size", 12)
	hdr.add_theme_color_override("font_color", Color(0.75, 0.62, 0.25))
	_local_ui.add_child(hdr)

	# Proximity buttons
	for s: Dictionary in _STATIONS:
		var btn := _make_station_btn(s)
		_local_ui.add_child(btn)
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

	return btn

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
	panel.custom_minimum_size = Vector2(640, 420)
	panel.offset_left   = -320
	panel.offset_top    = -210
	panel.offset_right  = 320
	panel.offset_bottom = 210
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.07, 0.08, 0.13)
	ps.set_border_width_all(2)
	ps.border_color = Color(0.20, 0.25, 0.40)
	ps.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", ps)
	root.add_child(panel)

	var m := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(side, 20)
	panel.add_child(m)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	m.add_child(vb)

	# Header row
	var hrow := HBoxContainer.new()
	vb.add_child(hrow)
	var title := Label.new()
	title.text = "WORKSHOP"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.55, 0.70, 0.90))
	hrow.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "✕  CLOSE"
	close_btn.add_theme_font_size_override("font_size", 12)
	var csty := StyleBoxFlat.new()
	csty.bg_color = Color(0.20, 0.20, 0.28)
	csty.set_corner_radius_all(4)
	close_btn.add_theme_stylebox_override("normal", csty)
	close_btn.pressed.connect(func(): _workshop_panel.visible = false)
	hrow.add_child(close_btn)

	var info := Label.new()
	info.text = "Barrel, stock and muzzle modifications are workshop-only.\nSight / rail attachments can be swapped in the field."
	info.add_theme_font_size_override("font_size", 11)
	info.add_theme_color_override("font_color", Color(0.55, 0.55, 0.60))
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(info)

	var sep := ColorRect.new()
	sep.color = Color(0.20, 0.25, 0.40, 0.6)
	sep.custom_minimum_size = Vector2(0, 1)
	vb.add_child(sep)

	vb.add_child(_section_label("WORKSHOP-ONLY MODIFICATIONS"))
	var ws_row := HBoxContainer.new()
	ws_row.add_theme_constant_override("separation", 10)
	vb.add_child(ws_row)
	for d: Array in [
		["BARREL",  "Affects damage falloff,\nmuzzle velocity & sound",  Color(0.40, 0.25, 0.10)],
		["STOCK",   "Recoil recovery\n& ADS speed",                      Color(0.22, 0.30, 0.22)],
		["MUZZLE",  "Suppressor / compensator\n/ flash hider",           Color(0.22, 0.22, 0.32)],
	]:
		ws_row.add_child(_mod_slot(d[0], d[1], d[2]))

	vb.add_child(_section_label("FIELD-SWAPPABLE"))
	var fs_row := HBoxContainer.new()
	fs_row.add_theme_constant_override("separation", 10)
	vb.add_child(fs_row)
	for d: Array in [
		["SIGHT / OPTIC", "Current: Iron Sights",     Color(0.18, 0.32, 0.18)],
		["GRIP / RAIL",   "Underbarrel grip or laser", Color(0.18, 0.24, 0.32)],
	]:
		fs_row.add_child(_mod_slot(d[0], d[1], d[2]))

func _section_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.70, 0.70, 0.80))
	return lbl

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

	var n := Label.new()
	n.text = slot_name
	n.add_theme_font_size_override("font_size", 11)
	n.add_theme_color_override("font_color", col.lightened(0.55))
	vb.add_child(n)

	var d := Label.new()
	d.text = desc
	d.add_theme_font_size_override("font_size", 9)
	d.add_theme_color_override("font_color", Color(0.50, 0.50, 0.55))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(d)

	var e := Label.new()
	e.text = "[ EMPTY ]"
	e.add_theme_font_size_override("font_size", 9)
	e.add_theme_color_override("font_color", Color(0.35, 0.35, 0.40))
	e.size_flags_vertical = Control.SIZE_EXPAND_FILL
	e.vertical_alignment  = VERTICAL_ALIGNMENT_BOTTOM
	vb.add_child(e)

	return pc

# ── Runtime ───────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	_playtime += delta
	GameState.playtime = _playtime
	_update_interaction_buttons()

func _update_interaction_buttons() -> void:
	var any_open := (_workshop_panel != null and _workshop_panel.visible) \
		or (_inv_ui != null and _inv_ui.visible)
	var vt := get_viewport().get_canvas_transform()

	for s: Dictionary in _STATIONS:
		var id:  String  = s["id"]
		var btn: Button  = _interact_btns.get(id)
		if btn == null:
			continue
		var world_pos: Vector2 = s["pos"]
		var dist := _player.global_position.distance_to(world_pos)
		var in_range := dist < INTERACT_DIST and not any_open
		btn.visible = in_range
		if in_range:
			var screen_pos: Vector2 = vt * world_pos
			btn.position = screen_pos + Vector2(-60, -50)

# ── Station actions ───────────────────────────────────────────────────────────

func _on_station_action(id: String) -> void:
	match id:
		"stash":          _inv_ui.toggle()
		"exit":           _deploy()
		"workshop":       _workshop_panel.visible = true
		"bed":            _do_rest()
		"shooting_range": get_tree().change_scene_to_file("res://safehouse/ShootingRange.tscn")

func _on_ads_pressed() -> void:
	var ws := _player.get_node("WeaponSystem") as WeaponSystem
	var sight := ws.get_active_weapon().get_sight() \
		if ws.get_active_weapon() != null else SightData.iron_sights()
	_player.on_ads_pressed(sight)

func _do_rest() -> void:
	if _resting:
		return
	_resting = true

	# Restore player live stats
	_player.heal(_player.max_health - _player.health)
	_player.survival.stamina = 100.0
	_player.survival.hunger  = 100.0
	_player.survival.thirst  = 100.0

	# Update GameState for persistence
	GameState.save_data["health"] = _player.max_health
	if not GameState.save_data.has("survival"):
		GameState.save_data["survival"] = {}
	GameState.save_data["survival"]["stamina"] = 100.0
	GameState.save_data["survival"]["hunger"]  = 100.0
	GameState.save_data["survival"]["thirst"]  = 100.0

	var tween := create_tween()
	tween.tween_interval(0.8)
	tween.finished.connect(func(): _resting = false)

func _deploy() -> void:
	GameState.save_data["inventory"] = _player.inventory.to_dict()
	GameState.save_data["health"]    = _player.health
	GameState.save_data["max_health"] = _player.max_health
	var s := _player.survival
	GameState.save_data["survival"] = {
		"stamina": s.stamina,
		"hunger":  s.hunger,
		"thirst":  s.thirst,
	}
	GameState.playtime = _playtime
	get_tree().change_scene_to_file("res://main.tscn")
