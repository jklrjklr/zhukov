extends Object


func _item(type: String, id: String = "test", w: int = 1, h: int = 1) -> Item:
	var item := Item.new()
	item.item_id = id
	item.type = type
	item.grid_size = Vector2i(w, h)
	return item


func test_helmet_accepts_only_helmet() -> void:
	var slot := InventorySlot.new("helmet")
	assert(slot.accepts(_item("helmet")), "helmet slot accepts helmet")
	assert(not slot.accepts(_item("armor")), "helmet slot rejects armor")
	assert(not slot.accepts(_item("weapon")), "helmet slot rejects weapon")


func test_quick_use_accepts_consumables_grenades_tactical() -> void:
	var slot := InventorySlot.new("quick_use")
	assert(slot.accepts(_item("consumable")), "accepts consumable")
	assert(slot.accepts(_item("grenade")), "accepts grenade")
	assert(slot.accepts(_item("tactical")), "accepts tactical")
	assert(not slot.accepts(_item("weapon")), "rejects weapon")


func test_main_weapon_accepts_any_weapon_size() -> void:
	var slot := InventorySlot.new("main_weapon")
	assert(slot.accepts(_item("weapon", "sniper", 6, 3)), "main weapon takes large weapon")
	assert(not slot.accepts(_item("consumable")), "main weapon rejects consumable")


func test_sub_weapon_enforces_size_limit() -> void:
	var slot := InventorySlot.new("sub_weapon")
	assert(slot.accepts(_item("weapon", "pistol", 2, 1)), "fits within 3x2")
	assert(slot.accepts(_item("weapon", "uzi", 3, 2)), "exactly 3x2 fits")
	assert(not slot.accepts(_item("weapon", "rifle", 4, 2)), "4x2 is too wide")
	assert(not slot.accepts(_item("weapon", "sniper", 3, 3)), "3x3 is too tall")


func test_equip_and_unequip_roundtrip() -> void:
	var slot := InventorySlot.new("helmet")
	var item := _item("helmet", "h1")
	assert(slot.is_empty(), "starts empty")
	assert(slot.equip(item), "equip succeeds")
	assert(not slot.is_empty(), "occupied after equip")
	var removed := slot.unequip()
	assert(removed == item, "unequip returns the same item")
	assert(slot.is_empty(), "empty after unequip")


func test_equip_rejects_wrong_type() -> void:
	var slot := InventorySlot.new("armor")
	assert(not slot.equip(_item("helmet")), "armor slot rejects helmet")
	assert(slot.is_empty(), "slot remains empty on failed equip")
