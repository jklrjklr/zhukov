extends Node2D


func _ready() -> void:
	var inventory_ui: CanvasLayer = $InventoryUI
	var inventory_sys: InventorySystem = $Player/InventorySystem
	inventory_ui.setup(inventory_sys)
	inventory_ui.visibility_changed.connect(func():
		TouchInputHandler.joystick_disabled = inventory_ui.visible)
	$HUD.inventory_requested.connect(inventory_ui.toggle)
	_seed_demo_items(inventory_sys)

	var ads_overlay: CanvasLayer = $AdsOverlay
	var player: Player = $Player
	player.entered_ads.connect(ads_overlay.show_ads)
	player.exited_ads.connect(ads_overlay.hide_ads)

	$HUD.ads_pressed.connect(_on_ads_pressed)
	$HUD.ads_released.connect(player.on_ads_released)

	var screen_fx := ScreenEffects.new()
	add_child(screen_fx)

	var pause_menu := PauseMenu.new()
	pause_menu.setup(player, inventory_sys, screen_fx)
	add_child(pause_menu)
	$HUD.pause_requested.connect(pause_menu.open)
	pause_menu.edit_layout_requested.connect($HUD.begin_layout_edit)


func _on_ads_pressed() -> void:
	var player: Player = $Player
	var weapon_sys: WeaponSystem = player.get_node("WeaponSystem")
	var sight: SightData = weapon_sys.get_active_weapon().get_sight() if weapon_sys.get_active_weapon() != null else SightData.iron_sights()
	player.on_ads_pressed(sight)


func _seed_demo_items(inv: InventorySystem) -> void:
	var helmet := Item.new()
	helmet.item_id = "helmet_basic"
	helmet.display_name = "Basic Helmet"
	helmet.type = "helmet"
	helmet.grid_size = Vector2i(1, 1)
	inv.equip("helmet", helmet)

	var ammo := Item.new()
	ammo.item_id = "ammo_9mm"
	ammo.display_name = "9mm x60"
	ammo.type = "consumable"
	ammo.grid_size = Vector2i(1, 2)
	ammo.quantity = 60
	inv.auto_add_to_backpack(ammo)

	var medkit := Item.new()
	medkit.item_id = "medkit"
	medkit.display_name = "Medkit"
	medkit.type = "consumable"
	medkit.grid_size = Vector2i(2, 2)
	inv.auto_add_to_backpack(medkit)
