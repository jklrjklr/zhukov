class_name ShootingRange
extends Node2D

const WALL_T        := 32.0
const INTERACT_DIST := 110.0
const WORLD_W       := 576.0
const WORLD_H       := 1984.0

@onready var _player:      Player      = $Player
@onready var _ads_overlay: CanvasLayer = $AdsOverlay

var _targets:    Array  = []
var _total_hits: int    = 0
var _total_dmg:  int    = 0
var _stats_lbl:  Label  = null
var _back_btn:   Button = null

func _ready() -> void:
	_setup_player()
	_build_tilemap()
	_build_walls()
	_build_targets()
	_build_ui()

# ── Player setup ──────────────────────────────────────────────────────────────

func _setup_player() -> void:
	_player.global_position = Vector2(WORLD_W * 0.5, 80.0)

	var cam := _player.get_node("Camera2D") as PlayerCamera
	cam.rotation      = 0.0
	cam.limit_enabled = true
	cam.limit_left    = 0
	cam.limit_top     = 0
	cam.limit_right   = int(WORLD_W)
	cam.limit_bottom  = int(WORLD_H)

	_ads_overlay.setup(_player)
	_player.entered_ads.connect(_ads_overlay.show_ads)
	_player.exited_ads.connect(_ads_overlay.hide_ads)
	$HUD.ads_pressed.connect(_on_ads_pressed)
	$HUD.ads_released.connect(_player.on_ads_released)
	$HUD.pause_requested.connect(func(): pass)

# ── Tilemap ───────────────────────────────────────────────────────────────────

func _build_tilemap() -> void:
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
	layer.z_index  = -1
	add_child(layer)

	var tx1 := int(WALL_T) / TILE
	var tx2 := int(WORLD_W - WALL_T) / TILE
	var ty1 := int(WALL_T) / TILE
	var ty2 := int(WORLD_H - WALL_T) / TILE
	for tx in range(tx1, tx2):
		for ty in range(ty1, ty2):
			layer.set_cell(Vector2i(tx, ty), src_id, Vector2i(7, 0))

# ── Walls ─────────────────────────────────────────────────────────────────────

func _build_walls() -> void:
	var wc := Color(0.16, 0.14, 0.12)
	_wall(Vector2(0,                  0),          Vector2(WORLD_W, WALL_T), wc)
	_wall(Vector2(0, WORLD_H - WALL_T),            Vector2(WORLD_W, WALL_T), wc)
	_wall(Vector2(0,                  0),          Vector2(WALL_T,  WORLD_H), wc)
	_wall(Vector2(WORLD_W - WALL_T,   0),          Vector2(WALL_T,  WORLD_H), wc)

func _wall(pos: Vector2, sz: Vector2, col: Color) -> void:
	var vis := ColorRect.new()
	vis.position = pos
	vis.size     = sz
	vis.color    = col
	add_child(vis)

	var body  := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rect  := RectangleShape2D.new()
	rect.size      = sz
	shape.position = pos + sz * 0.5
	shape.shape    = rect
	body.add_child(shape)
	add_child(body)

# ── Targets ───────────────────────────────────────────────────────────────────

func _build_targets() -> void:
	var rows: Array = [
		[280.0,   [128.0, 288.0, 448.0]],
		[520.0,   [160.0, 288.0, 416.0]],
		[780.0,   [128.0, 288.0, 448.0]],
		[1080.0,  [160.0, 288.0, 416.0]],
		[1420.0,  [128.0, 288.0, 448.0]],
	]
	var dist_labels := ["10m", "20m", "30m", "40m", "50m"]

	for i in range(rows.size()):
		var row_y: float = rows[i][0]
		var xs: Array    = rows[i][1]

		var lane := ColorRect.new()
		lane.position = Vector2(WALL_T, row_y - 80.0)
		lane.size     = Vector2(WORLD_W - 2.0 * WALL_T, 1.0)
		lane.color    = Color(0.28, 0.28, 0.30)
		add_child(lane)

		var dist_lbl := Label.new()
		dist_lbl.text     = dist_labels[i]
		dist_lbl.position = Vector2(WALL_T + 4.0, row_y - 94.0)
		dist_lbl.add_theme_font_size_override("font_size", 9)
		dist_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.60))
		add_child(dist_lbl)

		for x: float in xs:
			var tgt := ShootingTarget.new()
			tgt.position = Vector2(x, row_y)
			tgt.hit_registered.connect(_on_target_hit)
			add_child(tgt)
			_targets.append(tgt)

func _on_target_hit(damage: int, _headshot: bool) -> void:
	_total_hits += 1
	_total_dmg  += damage
	if _stats_lbl:
		_stats_lbl.text = "HITS: %d   DAMAGE: %d" % [_total_hits, _total_dmg]

func _reset_targets() -> void:
	_total_hits = 0
	_total_dmg  = 0
	if _stats_lbl:
		_stats_lbl.text = "HITS: 0   DAMAGE: 0"
	for t: ShootingTarget in _targets:
		t.reset()

# ── UI ────────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var ui := CanvasLayer.new()
	ui.layer = 3
	add_child(ui)

	_back_btn = Button.new()
	_back_btn.text    = "◀  SAFEHOUSE"
	_back_btn.visible = false
	_back_btn.custom_minimum_size = Vector2(150, 38)
	_back_btn.add_theme_font_size_override("font_size", 13)
	_back_btn.add_theme_color_override("font_color", Color.WHITE)
	var sty := StyleBoxFlat.new()
	sty.bg_color = Color(0.18, 0.22, 0.32)
	sty.set_corner_radius_all(5)
	_back_btn.add_theme_stylebox_override("normal", sty)
	var sty_h := sty.duplicate() as StyleBoxFlat
	sty_h.bg_color = Color(0.25, 0.30, 0.42)
	_back_btn.add_theme_stylebox_override("hover", sty_h)
	_back_btn.pressed.connect(_go_back)
	ui.add_child(_back_btn)

	var pc := PanelContainer.new()
	pc.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	pc.offset_left   = 8
	pc.offset_bottom = -8
	pc.offset_right  = 460
	pc.offset_top    = -52
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.06, 0.06, 0.10, 0.85)
	ps.set_border_width_all(1)
	ps.border_color = Color(0.22, 0.22, 0.30)
	ps.set_corner_radius_all(4)
	pc.add_theme_stylebox_override("panel", ps)
	var m := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(side, 6)
	pc.add_child(m)
	var hbox := HBoxContainer.new()
	m.add_child(hbox)
	var title := Label.new()
	title.text = "RANGE"
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", Color(0.65, 0.50, 0.20))
	title.custom_minimum_size = Vector2(48, 0)
	hbox.add_child(title)
	_stats_lbl = Label.new()
	_stats_lbl.text = "HITS: 0   DAMAGE: 0"
	_stats_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats_lbl.add_theme_font_size_override("font_size", 11)
	_stats_lbl.add_theme_color_override("font_color", Color(0.80, 0.80, 0.85))
	hbox.add_child(_stats_lbl)
	var reset_btn := Button.new()
	reset_btn.text = "RESET"
	reset_btn.add_theme_font_size_override("font_size", 11)
	var rs := StyleBoxFlat.new()
	rs.bg_color = Color(0.22, 0.18, 0.12)
	rs.set_corner_radius_all(3)
	reset_btn.add_theme_stylebox_override("normal", rs)
	reset_btn.pressed.connect(_reset_targets)
	hbox.add_child(reset_btn)
	ui.add_child(pc)

# ── Runtime ───────────────────────────────────────────────────────────────────

func _physics_process(_delta: float) -> void:
	_update_back_button()

func _update_back_button() -> void:
	if _back_btn == null:
		return
	var spawn  := Vector2(WORLD_W * 0.5, 80.0)
	var in_rng := _player.global_position.distance_to(spawn) < INTERACT_DIST
	_back_btn.visible = in_rng
	if in_rng:
		var sp := get_viewport().get_canvas_transform() * spawn
		_back_btn.position = sp + Vector2(-75.0, -50.0)

func _go_back() -> void:
	get_tree().change_scene_to_file("res://safehouse/Safehouse.tscn")

func _on_ads_pressed() -> void:
	var ws    := _player.get_node("WeaponSystem") as WeaponSystem
	var sight := ws.get_active_weapon().get_sight() \
		if ws.get_active_weapon() != null else SightData.iron_sights()
	_player.on_ads_pressed(sight)
