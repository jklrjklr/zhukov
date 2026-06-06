class_name InventorySystem
extends Node

signal inventory_changed

# Fixed equipment slots
var helmet: InventorySlot
var body_armor: InventorySlot
var chest_rig: InventorySlot
var quick_use_1: InventorySlot
var quick_use_2: InventorySlot
var main_weapon_1: InventorySlot
var main_weapon_2: InventorySlot
var sub_weapon: InventorySlot

# Backpack
var backpack_layout: String = "{(3,3),(3,3)}"
var backpack_compartments: Array[InventoryGrid] = []

func _ready() -> void:
	_init_slots()
	set_backpack_layout(backpack_layout)

func _init_slots() -> void:
	helmet       = InventorySlot.new("helmet")
	body_armor   = InventorySlot.new("armor")
	chest_rig    = InventorySlot.new("rig")
	quick_use_1  = InventorySlot.new("quick_use")
	quick_use_2  = InventorySlot.new("quick_use")
	main_weapon_1 = InventorySlot.new("main_weapon")
	main_weapon_2 = InventorySlot.new("main_weapon")
	sub_weapon   = InventorySlot.new("sub_weapon")

func set_backpack_layout(notation: String) -> void:
	backpack_layout = notation
	backpack_compartments.clear()
	var rows: Array = BackpackLayout.parse(notation)
	for row: Array in rows:
		for dim: Vector2i in row:
			backpack_compartments.append(InventoryGrid.new(dim.x, dim.y))

# Equip an item into a named slot. Returns false if the slot rejects it.
func equip(slot_name: String, item: Item) -> bool:
	var slot := _get_slot(slot_name)
	if slot == null:
		return false
	if slot.equip(item):
		inventory_changed.emit()
		return true
	return false

# Remove and return the item in the named slot.
func unequip(slot_name: String) -> Item:
	var slot := _get_slot(slot_name)
	if slot == null:
		return null
	var item := slot.unequip()
	if item != null:
		inventory_changed.emit()
	return item

# Place item at an explicit position in a backpack compartment.
func add_to_backpack(item: Item, compartment_index: int, grid_pos: Vector2i, rotated: bool = false) -> bool:
	if compartment_index >= backpack_compartments.size():
		return false
	if backpack_compartments[compartment_index].place_item(item, grid_pos, rotated):
		inventory_changed.emit()
		return true
	return false

# Remove an item by id from a specific compartment.
func remove_from_backpack(item_id: String, compartment_index: int) -> Item:
	if compartment_index >= backpack_compartments.size():
		return null
	var item := backpack_compartments[compartment_index].remove_item(item_id)
	if item != null:
		inventory_changed.emit()
	return item

# Tries each compartment in order, both orientations. Returns false if no space.
func auto_add_to_backpack(item: Item) -> bool:
	for i in backpack_compartments.size():
		var grid := backpack_compartments[i]
		for rotated in [false, true]:
			var pos := grid.find_free_spot(item, rotated)
			if pos.x >= 0:
				return add_to_backpack(item, i, pos, rotated)
	return false

func get_slot(slot_name: String) -> InventorySlot:
	return _get_slot(slot_name)

func to_dict() -> Dictionary:
	var slot_names := ["helmet", "body_armor", "chest_rig",
		"quick_use_1", "quick_use_2", "main_weapon_1", "main_weapon_2", "sub_weapon"]
	var equipment: Dictionary = {}
	for name: String in slot_names:
		var slot := _get_slot(name)
		equipment[name] = null if slot.is_empty() else slot.to_dict()

	var compartments_data: Array = []
	for i in backpack_compartments.size():
		var d := backpack_compartments[i].to_dict()
		d["compartment_id"] = i
		compartments_data.append(d)

	return {
		"equipment": equipment,
		"backpack": {"layout": backpack_layout, "compartments": compartments_data},
	}

func _get_slot(name: String) -> InventorySlot:
	match name:
		"helmet":       return helmet
		"body_armor":   return body_armor
		"chest_rig":    return chest_rig
		"quick_use_1":  return quick_use_1
		"quick_use_2":  return quick_use_2
		"main_weapon_1": return main_weapon_1
		"main_weapon_2": return main_weapon_2
		"sub_weapon":   return sub_weapon
	return null
