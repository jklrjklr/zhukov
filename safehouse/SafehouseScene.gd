class_name SafehouseScene
extends Node2D

# Room constants (matches 1280×720 viewport, camera centred at 640,360)
const RW       := 1280.0
const RH       := 720.0
const WALL_T   := 36.0
const MOVE_SPD := 160.0
const INTERACT_RADIUS := 130.0

# Station definitions: name, description, rect (pos+size), accent colour, active
const _STATIONS := [
	{
		"id": "stash",
		"name": "STASH",
		"desc": "Manage your inventory",
		"rect": Rect2(56, 210, 120, 300),
		"color": Color(0.10, 0.30, 0.20),
		"active": true,
	},
	{
		"id": "exit",
		"name": "EXIT",
		"desc": "Deploy to the field",
		"rect": Rect2(1190, 270, 54, 180),
		"color": Color(0.15, 0.48, 0.22),
		"active": true,
	},
	{
		"id": "armory",
		"name": "ARMORY",
		"desc": "Configure your loadout",
		"rect": Rect2(900, 52, 260, 150),
		"color": Color(0.38, 0.18, 0.08),
		"active": false,
	},
	{
		"id": "workbench",
		"name": "WORKBENCH",
		"desc": "Modify weapons & craft",
		"rect": Rect2(420, 592, 440, 68),
		"color": Color(0.14, 0.22, 0.40),
		"active": false,
	},
	{
		"id": "bed",
		"name": "REST",
		"desc": "Recover stamina & health",
		"rect": Rect2(56, 584, 280, 68),
		"color": Color(0.28, 0.20, 0.12),
		"active": false,
	},
]

var _player: CharacterBody2D
var _player_sprite: Sprite2D
var _inv_sys: InventorySystem
var _inv_ui: CanvasLayer
var _interact_btns: Dictionary = {}   # station id → Button
var _playtime: float = 0.0

# ── Build ─────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_playtime = GameState.playtime
	_build_floor()
	_build_walls()
	_build_station_visuals()
	_build_player()
	_build_camera()
	_build_inventory()
	_build_ui()

func _build_floor() -> void:
	var floor_bg := ColorRect.new()
	floor_bg.position = Vector2(WALL_T, WALL_T)
	floor_bg.size     = Vector2(RW - WALL_T * 2, RH - WALL_T * 2)
	floor_bg.color    = Color(0.11, 0.10, 0.09)
	add_child(floor_bg)

	# Subtle grid lines
	for i in range(1, 8):
		var h := ColorRect.new()
		h.color    = Color(0.14, 0.12, 0.11)
		h.position = Vector2(WALL_T, WALL_T + i * ((RH - WALL_T * 2) / 8.0))
		h.size     = Vector2(RW - WALL_T * 2, 1)
		add_child(h)
	for i in range(1, 12):
		var v := ColorRect.new()
		v.color    = Color(0.14, 0.12, 0.11)
		v.position = Vector2(WALL_T + i * ((RW - WALL_T * 2) / 12.0), WALL_T)
		v.size     = Vector2(1, RH - WALL_T * 2)
		add_child(v)

func _build_walls() -> void:
	var wall_col := Color(0.16, 0.14, 0.12)

	# North wall
	_solid_wall(Vector2(0, 0),            Vector2(RW, WALL_T),      wall_col)
	# South wall
	_solid_wall(Vector2(0, RH - WALL_T),  Vector2(RW, WALL_T),      wall_col)
	# West wall
	_solid_wall(Vector2(0, WALL_T),       Vector2(WALL_T, RH - WALL_T * 2), wall_col)
	# East wall – two segments with door gap at y 270–450
	_solid_wall(Vector2(RW - WALL_T, WALL_T),       Vector2(WALL_T, 234),        wall_col)
	_solid_wall(Vector2(RW - WALL_T, WALL_T + 234 + 180), Vector2(WALL_T, RH - WALL_T * 2 - 234 - 180), wall_col)

	# Door frame accent
	var frame := ColorRect.new()
	frame.position = Vector2(RW - WALL_T - 6, WALL_T + 234 - 6)
	frame.size     = Vector2(WALL_T + 6, 180 + 12)
	frame.color    = Color(0.20, 0.55, 0.28, 0.5)
	add_child(frame)

func _solid_wall(pos: Vector2, sz: Vector2, col: Color) -> void:
	var vis := ColorRect.new()
	vis.position = pos
	vis.size     = sz
	vis.color    = col
	add_child(vis)

	var body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rect  := RectangleShape2D.new()
	rect.size        = sz
	shape.position   = pos + sz * 0.5
	shape.shape      = rect
	body.add_child(shape)
	add_child(body)

func _build_station_visuals() -> void:
	for s: Dictionary in _STATIONS:
		var r: Rect2   = s["rect"]
		var ac: Color  = s["color"]
		var id: String = s["id"]

		if id == "exit":
			continue  # exit is just the door frame, built in _build_walls

		# Background fill
		var bg := ColorRect.new()
		bg.position = r.position
		bg.size     = r.size
		bg.color    = ac.darkened(0.55)
		add_child(bg)

		# Accent border
		for edge in [
			Rect2(r.position,                         Vector2(r.size.x, 2)),  # top
			Rect2(r.position + Vector2(0, r.size.y-2), Vector2(r.size.x, 2)),  # bottom
			Rect2(r.position,                         Vector2(2, r.size.y)),  # left
			Rect2(r.position + Vector2(r.size.x-2, 0), Vector2(2, r.size.y)), # right
		]:
			var line := ColorRect.new()
			line.position = edge.position
			line.size     = edge.size
			line.color    = ac.lightened(0.1)
			add_child(line)

		# Name label on the object
		var lbl := Label.new()
		lbl.text = s["name"]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", ac.lightened(0.6))
		lbl.position = r.position + Vector2(0, r.size.y * 0.5 - 8)
		lbl.size     = Vector2(r.size.x, 18)
		add_child(lbl)

func _build_player() -> void:
	_player = CharacterBody2D.new()
	_player.position = Vector2(480, 360)
	_player.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING

	_player_sprite = Sprite2D.new()
	_player_sprite.texture = load("res://assets/Player.png")
	_player_sprite.scale   = Vector2(0.7, 0.7)
	_player.add_child(_player_sprite)

	var col   := CollisionShape2D.new()
	var shape := CapsuleShape2D.new()
	shape.radius       = 10.0
	shape.height       = 30.0
	col.rotation       = PI / 2
	col.scale          = Vector2(4, 4)
	col.shape          = shape
	_player.add_child(col)

	add_child(_player)

func _build_camera() -> void:
	var cam := Camera2D.new()
	cam.position = Vector2(RW / 2, RH / 2)
	add_child(cam)

func _build_inventory() -> void:
	_inv_sys = InventorySystem.new()
	add_child(_inv_sys)

	if GameState.save_data.has("inventory"):
		_inv_sys.load_from_dict(GameState.save_data["inventory"])
	else:
		_seed_items()

	_inv_ui = load("res://inventory/ui/InventoryUI.tscn").instantiate() as CanvasLayer
	_inv_ui.layer = 10
	add_child(_inv_ui)
	_inv_ui.setup(_inv_sys)

	_inv_ui.visibility_changed.connect(func():
		TouchInputHandler.joystick_disabled = _inv_ui.visible)

func _seed_items() -> void:
	var helmet := Item.new()
	helmet.item_id      = "helmet_basic"
	helmet.display_name = "Basic Helmet"
	helmet.type         = "helmet"
	helmet.grid_size    = Vector2i(1, 1)
	_inv_sys.equip("helmet", helmet)

	var ammo := Item.new()
	ammo.item_id      = "ammo_9mm"
	ammo.display_name = "9mm x60"
	ammo.type         = "consumable"
	ammo.grid_size    = Vector2i(1, 2)
	ammo.quantity     = 60
	_inv_sys.auto_add_to_backpack(ammo)

	var medkit := Item.new()
	medkit.item_id      = "medkit"
	medkit.display_name = "Medkit"
	medkit.type         = "consumable"
	medkit.grid_size    = Vector2i(2, 2)
	_inv_sys.auto_add_to_backpack(medkit)

# ── Interaction UI ────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)

	# Header: room name + playtime
	var header := _make_header_label()
	layer.add_child(header)

	# Player stat bars (top-right)
	layer.add_child(_make_stat_panel())

	# One floating button per station
	for s: Dictionary in _STATIONS:
		var r: Rect2   = s["rect"]
		var id: String = s["id"]
		var active: bool = s["active"]

		var btn := Button.new()
		btn.text    = s["name"]
		btn.visible = false
		btn.add_theme_font_size_override("font_size", 13)
		btn.add_theme_color_override("font_color", Color.WHITE)
		btn.custom_minimum_size = Vector2(120, 38)

		var col: Color = s["color"]
		var sty := StyleBoxFlat.new()
		sty.bg_color = col if active else Color(0.25, 0.25, 0.30)
		sty.set_corner_radius_all(5)
		btn.add_theme_stylebox_override("normal", sty)
		var sty_h := sty.duplicate() as StyleBoxFlat
		sty_h.bg_color = (col.lightened(0.2) if active else Color(0.30, 0.30, 0.36))
		btn.add_theme_stylebox_override("hover", sty_h)

		if active:
			var captured_id := id
			btn.pressed.connect(func(): _on_station_action(captured_id))
		else:
			btn.disabled = true

		# Position button above station centre (screen coords = world coords here)
		var cx: float = r.position.x + r.size.x * 0.5
		var cy: float = r.position.y - 46
		btn.position = Vector2(cx - 60, cy)

		layer.add_child(btn)
		_interact_btns[id] = btn

func _make_header_label() -> Label:
	var lbl := Label.new()
	lbl.text = "HIDEOUT  ·  SLOT %d" % (GameState.save_slot + 1)
	lbl.position = Vector2(12, 6)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.80, 0.68, 0.28))
	return lbl

func _make_stat_panel() -> Control:
	var vb := VBoxContainer.new()
	vb.position = Vector2(RW - 210, 8)
	vb.add_theme_constant_override("separation", 3)

	var hp := int(GameState.save_data.get("health", 100))
	var hp_max := int(GameState.save_data.get("max_health", 100))
	var sv: Dictionary = GameState.save_data.get("survival",
		{"stamina": 100.0, "hunger": 100.0, "thirst": 100.0})

	_add_stat(vb, "HP",     Color(0.22, 0.65, 0.28), float(hp) / float(hp_max))
	_add_stat(vb, "STA",    Color(0.25, 0.48, 0.78), float(sv.get("stamina", 100.0)) / 100.0)
	_add_stat(vb, "HUNGER", Color(0.72, 0.50, 0.16), float(sv.get("hunger",  100.0)) / 100.0)

	return vb

func _add_stat(parent: VBoxContainer, label: String, col: Color, ratio: float) -> void:
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

# ── Runtime ───────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	_playtime += delta
	_move_player(delta)
	_update_interactions()

func _move_player(delta: float) -> void:
	var dir := TouchInputHandler.get_move_vector()
	if dir.length_squared() > 0.01:
		_player.velocity = dir * MOVE_SPD
		_player_sprite.rotation = dir.angle() + PI * 0.5
	else:
		_player.velocity = _player.velocity.move_toward(Vector2.ZERO, MOVE_SPD * 8.0 * delta)
	_player.move_and_slide()

func _update_interactions() -> void:
	var pp := _player.position
	for s: Dictionary in _STATIONS:
		var id: String = s["id"]
		if not _interact_btns.has(id):
			continue
		var r: Rect2  = s["rect"]
		var centre    := r.position + r.size * 0.5
		var dist      := pp.distance_to(centre)
		_interact_btns[id].visible = (dist < INTERACT_RADIUS)

# ── Station actions ───────────────────────────────────────────────────────────

func _on_station_action(id: String) -> void:
	match id:
		"stash":
			_inv_ui.toggle()
		"exit":
			_deploy()

func _deploy() -> void:
	# Persist state back to GameState
	GameState.save_data["inventory"] = _inv_sys.to_dict()
	GameState.playtime = _playtime
	get_tree().change_scene_to_file("res://main.tscn")
