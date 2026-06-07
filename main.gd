extends Node2D

var _playtime: float = 0.0
var _game_active: bool = false
var _pause_menu: PauseMenu = null

func _ready() -> void:
	_hide_game()
	var title := TitleScreen.new()
	add_child(title)
	title.start_pressed.connect(func():
		title.queue_free()
		_open_main_menu())

func _open_main_menu() -> void:
	var menu := MainMenu.new()
	add_child(menu)
	menu.slot_selected.connect(_start_game)
	menu.exit_requested.connect(func(): get_tree().quit())

func _process(delta: float) -> void:
	if _game_active and not get_tree().paused:
		_playtime += delta
		if _pause_menu != null:
			_pause_menu.playtime = _playtime

func _hide_game() -> void:
	for node: Node in [$GridBackground, $Player, $HUD, $AdsOverlay, $InventoryUI]:
		node.visible = false
	$Player.process_mode = Node.PROCESS_MODE_DISABLED
	$HUD.process_mode    = Node.PROCESS_MODE_DISABLED

func _start_game(slot: int) -> void:
	for child in get_children():
		if child is MainMenu:
			child.queue_free()

	# Load save
	var slot_path := MainMenu.save_path(slot)
	var save_data: Dictionary = {}
	if FileAccess.file_exists(slot_path):
		var f := FileAccess.open(slot_path, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			save_data = parsed
	_playtime = float(save_data.get("playtime", 0.0))

	var player: Player            = $Player
	var inventory_sys: InventorySystem = $Player/InventorySystem
	var inventory_ui: CanvasLayer = $InventoryUI

	# Restore or seed inventory
	if save_data.has("inventory"):
		inventory_sys.load_from_dict(save_data["inventory"])
	else:
		_seed_demo_items(inventory_sys)

	# Restore player state
	if save_data.has("health"):
		player.health     = int(save_data["health"])
		player.max_health = int(save_data.get("max_health", 100))
	if save_data.has("position"):
		var pos: Array = save_data["position"]
		player.global_position = Vector2(float(pos[0]), float(pos[1]))
	if save_data.has("survival"):
		var sv: Dictionary = save_data["survival"]
		player.survival.stamina = float(sv.get("stamina", 100.0))
		player.survival.hunger  = float(sv.get("hunger",  100.0))
		player.survival.thirst  = float(sv.get("thirst",  100.0))

	# Wire up game systems (skip if already connected)
	if not $HUD.inventory_requested.is_connected(inventory_ui.toggle):
		inventory_ui.setup(inventory_sys)
		inventory_ui.visibility_changed.connect(func():
			TouchInputHandler.joystick_disabled = inventory_ui.visible)
		$HUD.inventory_requested.connect(inventory_ui.toggle)

	var ads_overlay: CanvasLayer = $AdsOverlay
	if not player.entered_ads.is_connected(ads_overlay.show_ads):
		player.entered_ads.connect(ads_overlay.show_ads)
		player.exited_ads.connect(ads_overlay.hide_ads)
		$HUD.ads_pressed.connect(_on_ads_pressed)
		$HUD.ads_released.connect(player.on_ads_released)

	var screen_fx := ScreenEffects.new()
	add_child(screen_fx)

	_pause_menu = PauseMenu.new()
	_pause_menu.setup(player, inventory_sys, screen_fx)
	_pause_menu.save_slot = slot
	_pause_menu.playtime  = _playtime
	add_child(_pause_menu)
	$HUD.pause_requested.connect(_pause_menu.open)
	_pause_menu.edit_layout_requested.connect($HUD.begin_layout_edit)

	# Enable and show game
	$Player.process_mode = Node.PROCESS_MODE_INHERIT
	$HUD.process_mode    = Node.PROCESS_MODE_INHERIT
	for node: Node in [$GridBackground, $Player, $HUD, $AdsOverlay]:
		node.visible = true

	_game_active = true


func _on_ads_pressed() -> void:
	var player: Player = $Player
	var weapon_sys: WeaponSystem = player.get_node("WeaponSystem")
	var sight: SightData = weapon_sys.get_active_weapon().get_sight() \
		if weapon_sys.get_active_weapon() != null else SightData.iron_sights()
	player.on_ads_pressed(sight)


func _seed_demo_items(inv: InventorySystem) -> void:
	var helmet := Item.new()
	helmet.item_id      = "helmet_basic"
	helmet.display_name = "Basic Helmet"
	helmet.type         = "helmet"
	helmet.grid_size    = Vector2i(1, 1)
	inv.equip("helmet", helmet)

	var ammo := Item.new()
	ammo.item_id      = "ammo_9mm"
	ammo.display_name = "9mm x60"
	ammo.type         = "consumable"
	ammo.grid_size    = Vector2i(1, 2)
	ammo.quantity     = 60
	inv.auto_add_to_backpack(ammo)

	var medkit := Item.new()
	medkit.item_id      = "medkit"
	medkit.display_name = "Medkit"
	medkit.type         = "consumable"
	medkit.grid_size    = Vector2i(2, 2)
	inv.auto_add_to_backpack(medkit)
