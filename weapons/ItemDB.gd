extends Node

const DB_PATH := "res://data/items.json"

var _db: Dictionary = {}

func _ready() -> void:
	_load()

func _load() -> void:
	var file := FileAccess.open(DB_PATH, FileAccess.READ)
	if not file:
		push_error("ItemDB: cannot open %s" % DB_PATH)
		return
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		_db = parsed as Dictionary
		print("ItemDB: loaded %d items" % _db.size())
	else:
		push_error("ItemDB: JSON parse failed")

func get_item(id: String) -> Dictionary:
	if _db.has(id):
		return _db[id] as Dictionary
	push_warning("ItemDB: unknown item id '%s'" % id)
	return {}

func get_ids_by_type(type: String) -> Array:
	var result: Array = []
	for id: String in _db:
		if (_db[id] as Dictionary).get("type", "") == type:
			result.append(id)
	return result

func has_item(id: String) -> bool:
	return _db.has(id)
