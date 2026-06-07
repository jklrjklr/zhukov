extends Node2D

var _playtime:    float = 0.0
var _game_active: bool  = false
var _pause_menu:  PauseMenu = null

func _ready() -> void:
	var slot      := GameState.save_slot
	var save_data := GameState.save_data

	# Fallback for running main.tscn directly during dev
	if slot < 0:
		slot = 0

	_playtime = GameState.playtime

	var player:        Player            = $Player
	var inventory_sys: InventorySystem   = $Player/InventorySystem
	var inventory_ui:  CanvasLayer       = $InventoryUI

	if save_data.has("inventory"):
		inventory_sys.load_from_dict(save_data["inventory"])
	else:
		_seed_demo_items(inventory_sys)

	inventory_ui.setup(inventory_sys)
	inventory_ui.visibility_changed.connect(func():
		TouchInputHandler.joystick_disabled = inventory_ui.visible)
	$HUD.inventory_requested.connect(inventory_ui.toggle)

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

	var ads_overlay: CanvasLayer = $AdsOverlay
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

	_game_active = true


func _process(delta: float) -> void:
	if _game_active and not get_tree().paused:
		_playtime += delta
		if _pause_menu != null:
			_pause_menu.playtime = _playtime
		GameState.playtime = _playtime


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
