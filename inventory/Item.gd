class_name Item
extends RefCounted

var item_id: String = ""
var display_name: String = ""
var type: String = ""
var grid_size: Vector2i = Vector2i(1, 1)
var weight: float = 0.0
var max_stack: int = 1
var quantity: int = 1
# For weapon items: maps attachment slot name → attachment item_id.
# Persisted in save data so loadouts survive between sessions.
var attachments: Dictionary = {}

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
	var d: Dictionary = {
		"id": item_id,
		"display_name": display_name,
		"type": type,
		"grid_size": [grid_size.x, grid_size.y],
		"weight": weight,
		"max_stack": max_stack,
		"quantity": quantity,
	}
	if not attachments.is_empty():
		d["attachments"] = attachments.duplicate()
	return d

static func from_save(d: Dictionary) -> Item:
	var item := Item.new()
	item.item_id     = d.get("id", "")
	item.display_name = d.get("display_name", "")
	item.type        = d.get("type", "")
	var sz: Array    = d.get("grid_size", [1, 1])
	item.grid_size   = Vector2i(sz[0], sz[1])
	item.weight      = d.get("weight", 0.0)
	item.max_stack   = d.get("max_stack", 1)
	item.quantity    = d.get("quantity", 1)
	if d.has("attachments"):
		item.attachments = (d["attachments"] as Dictionary).duplicate()
	return item
