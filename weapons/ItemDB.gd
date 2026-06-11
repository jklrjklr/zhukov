extends Node

const _PATHS: Array[String] = [
	"res://data/weapons.json",
	"res://data/ammo.json",
	"res://data/attachments.json",
	"res://data/backpack.json",
	"res://data/rig.json",
	"res://data/headgear.json",
	"res://data/consumables.json",
	"res://data/items.json",
]

var _db: Dictionary = {}

func _ready() -> void:
	_load()

func _load() -> void:
	for path: String in _PATHS:
		var file := FileAccess.open(path, FileAccess.READ)
		if not file:
			push_error("ItemDB: cannot open %s" % path)
			continue
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if not (parsed is Dictionary):
			push_error("ItemDB: JSON parse failed in %s" % path)
			continue
		for id: String in (parsed as Dictionary):
			if _db.has(id):
				push_warning("ItemDB: duplicate id '%s' in %s — skipping" % [id, path])
				continue
			_db[id] = (parsed as Dictionary)[id]
	print("ItemDB: loaded %d items" % _db.size())

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
