extends Object


func _make_item(id: String, type: String, w: int = 1, h: int = 1) -> Item:
	var item := Item.new()
	item.item_id = id
	item.display_name = id
	item.type = type
	item.grid_size = Vector2i(w, h)
	item.quantity = 1
	return item


func test_to_dict_includes_all_fields() -> void:
	var item := _make_item("helmet_basic", "helmet")
	item.weight = 1.5
	item.quantity = 3
	var d := item.to_dict()
	assert(d["id"] == "helmet_basic")
	assert(d["type"] == "helmet")
	assert(d["grid_size"] == [1, 1])
	assert(d["weight"] == 1.5)
	assert(d["quantity"] == 3)


func test_from_save_roundtrip() -> void:
	var orig := _make_item("ammo_556", "consumable", 1, 2)
	orig.quantity = 120
	orig.weight = 0.5
	var loaded := Item.from_save(orig.to_dict())
	assert(loaded.item_id == orig.item_id)
	assert(loaded.type == orig.type)
	assert(loaded.grid_size == orig.grid_size)
	assert(loaded.quantity == orig.quantity)
	assert(loaded.weight == orig.weight)


func test_inventory_system_to_dict() -> void:
	var sys := InventorySystem.new()
	sys._init_slots()
	sys.set_backpack_layout("{(3,3)}")
	sys.equip("helmet", _make_item("h1", "helmet"))
	sys.add_to_backpack(_make_item("ammo", "consumable", 1, 1), 0, Vector2i(0, 0))
	var d := sys.to_dict()
	assert(d.has("equipment"))
	assert(d.has("backpack"))
	assert((d["equipment"] as Dictionary)["helmet"] != null)
	assert((d["backpack"] as Dictionary)["layout"] == "{(3,3)}")


func test_save_and_load_file() -> void:
	var path := "user://test_inventory_save.json"
	var sys := InventorySystem.new()
	sys._init_slots()
	sys.set_backpack_layout("{(4,4)}")
	var helmet := _make_item("helmet_tac", "helmet")
	sys.equip("helmet", helmet)
	var ammo := _make_item("ammo_9mm", "consumable", 1, 2)
	ammo.quantity = 60
	sys.add_to_backpack(ammo, 0, Vector2i(1, 1))
	sys.save(path)

	var sys2 := InventorySystem.new()
	sys2._init_slots()
	sys2.load_from_file(path)
	assert(not sys2.helmet.is_empty(), "helmet should be loaded")
	assert(sys2.helmet.item.item_id == "helmet_tac", "helmet id preserved")
	var loaded_ammo := sys2.backpack_compartments[0].get_item_at(Vector2i(1, 1))
	assert(loaded_ammo != null, "ammo should be at (1,1)")
	assert(loaded_ammo.item_id == "ammo_9mm", "ammo id preserved")
	assert(loaded_ammo.quantity == 60, "quantity preserved")
