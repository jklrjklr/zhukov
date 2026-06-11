class_name InventoryGrid
extends RefCounted

var cols: int = 0
var rows: int = 0

# _cells[row][col] = item_id string, "" if empty
var _cells: Array = []
# item_id -> {item: Item, pos: Vector2i, rotated: bool}
var _placed: Dictionary = {}

func _init(p_cols: int, p_rows: int) -> void:
	cols = p_cols
	rows = p_rows
	_cells.resize(rows)
	for i in rows:
		_cells[i] = []
		_cells[i].resize(cols)
		_cells[i].fill("")

func can_place(item: Item, pos: Vector2i, rotated: bool = false) -> bool:
	var sz := _effective_size(item, rotated)
	if pos.x < 0 or pos.y < 0:
		return false
	if pos.x + sz.x > cols or pos.y + sz.y > rows:
		return false
	for dy in sz.y:
		for dx in sz.x:
			if _cells[pos.y + dy][pos.x + dx] != "":
				return false
	return true

func place_item(item: Item, pos: Vector2i, rotated: bool = false) -> bool:
	if not can_place(item, pos, rotated):
		return false
	var sz := _effective_size(item, rotated)
	for dy in sz.y:
		for dx in sz.x:
			_cells[pos.y + dy][pos.x + dx] = item.item_id
	_placed[item.item_id] = {"item": item, "pos": pos, "rotated": rotated}
	return true

func remove_item(item_id: String) -> Item:
	if not _placed.has(item_id):
		return null
	var entry: Dictionary = _placed[item_id]
	var item: Item = entry["item"]
	var pos: Vector2i = entry["pos"]
	var rotated: bool = entry["rotated"]
	var sz := _effective_size(item, rotated)
	for dy in sz.y:
		for dx in sz.x:
			_cells[pos.y + dy][pos.x + dx] = ""
	_placed.erase(item_id)
	return item

func get_item_at(pos: Vector2i) -> Item:
	if pos.x < 0 or pos.y < 0 or pos.x >= cols or pos.y >= rows:
		return null
	var id: String = _cells[pos.y][pos.x]
	if id.is_empty() or not _placed.has(id):
		return null
	return (_placed[id] as Dictionary)["item"] as Item

func get_placement(item_id: String) -> Dictionary:
	return _placed.get(item_id, {})

# Scans row-major for the first position that fits. Returns (-1,-1) if none.
func find_free_spot(item: Item, rotated: bool = false) -> Vector2i:
	for r in rows:
		for c in cols:
			if can_place(item, Vector2i(c, r), rotated):
				return Vector2i(c, r)
	return Vector2i(-1, -1)

func to_dict() -> Dictionary:
	var items_list: Array = []
	for id: String in _placed:
		var entry: Dictionary = _placed[id]
		var pos: Vector2i = entry["pos"]
		# Embed the full item payload (id, type, grid_size, weight, …) so the
		# entry round-trips through Item.from_save, then add placement fields.
		var item_data := (entry["item"] as Item).to_dict()
		item_data["item_id"] = id
		item_data["grid_pos"] = [pos.x, pos.y]
		item_data["rotated"] = entry["rotated"]
		items_list.append(item_data)
	return {"size": [cols, rows], "items": items_list}

func clear() -> void:
	for i in rows:
		_cells[i].fill("")
	_placed.clear()

func _effective_size(item: Item, rotated: bool) -> Vector2i:
	if rotated:
		return Vector2i(item.grid_size.y, item.grid_size.x)
	return item.grid_size
