class_name Item
extends RefCounted

var item_id: String = ""
var display_name: String = ""
var type: String = ""
var grid_size: Vector2i = Vector2i(1, 1)
var weight: float = 0.0
var max_stack: int = 1
var quantity: int = 1

static func from_dict(id: String, def: Dictionary) -> Item:
	var item := Item.new()
	item.item_id = id
	item.display_name = def.get("display_name", id)
	item.type = def.get("type", "")
	var sz: Array = def.get("grid_size", [1, 1])
	item.grid_size = Vector2i(sz[0], sz[1])
	item.weight = def.get("weight", 0.0)
	item.max_stack = def.get("max_stack", 1)
	item.quantity = def.get("quantity", 1)
	return item

func to_dict() -> Dictionary:
	return {
		"id": item_id,
		"quantity": quantity,
	}
