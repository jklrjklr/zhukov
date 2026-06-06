class_name InventorySlot
extends RefCounted

const SUB_WEAPON_MAX_SIZE := Vector2i(3, 2)

var slot_type: String = ""
var item: Item = null

func _init(p_slot_type: String) -> void:
	slot_type = p_slot_type

func accepts(candidate: Item) -> bool:
	match slot_type:
		"helmet":      return candidate.type == "helmet"
		"armor":       return candidate.type == "armor"
		"rig":         return candidate.type == "rig"
		"quick_use":   return candidate.type in ["consumable", "grenade", "tactical"]
		"main_weapon": return candidate.type == "weapon"
		"sub_weapon":
			if candidate.type != "weapon":
				return false
			return candidate.grid_size.x <= SUB_WEAPON_MAX_SIZE.x \
				and candidate.grid_size.y <= SUB_WEAPON_MAX_SIZE.y
	return false

func equip(candidate: Item) -> bool:
	if not accepts(candidate):
		return false
	item = candidate
	return true

func unequip() -> Item:
	var prev := item
	item = null
	return prev

func is_empty() -> bool:
	return item == null

func to_dict() -> Dictionary:
	return {} if item == null else item.to_dict()
