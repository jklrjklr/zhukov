extends Node2D


func _ready() -> void:
	var inventory_ui: CanvasLayer = $InventoryUI
	var inventory_sys: InventorySystem = $Player/InventorySystem
	inventory_ui.setup(inventory_sys)
	$HUD.inventory_requested.connect(inventory_ui.toggle)
	_seed_demo_items(inventory_sys)


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
