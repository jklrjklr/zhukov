class_name CompartmentGrid
extends Control

const CELL_SIZE := 56

signal item_dropped(compartment_index: int, item: Item, grid_pos: Vector2i, rotated: bool, source_key: String)

var compartment_index: int
var _inventory: InventorySystem
var _grid: InventoryGrid
var _icons: Dictionary = {}   # item_id -> ItemIcon

func setup(p_index: int, p_inventory: InventorySystem) -> void:
	compartment_index = p_index
	_inventory        = p_inventory
	_grid             = p_inventory.backpack_compartments[p_index]
	custom_minimum_size = Vector2(_grid.cols * CELL_SIZE, _grid.rows * CELL_SIZE)
	size = custom_minimum_size
	_build_cells()

func _build_cells() -> void:
	for r in _grid.rows:
		for c in _grid.cols:
			var cell := Panel.new()
			cell.position = Vector2(c * CELL_SIZE + 1, r * CELL_SIZE + 1)
			cell.size     = Vector2(CELL_SIZE - 2, CELL_SIZE - 2)
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var s := StyleBoxFlat.new()
			s.bg_color = Color(0.10, 0.10, 0.15, 0.92)
			s.border_width_all = 1
			s.border_color = Color(0.25, 0.25, 0.30, 0.6)
			cell.add_theme_stylebox_override("panel", s)
			add_child(cell)

func refresh() -> void:
	for icon: ItemIcon in _icons.values():
		icon.queue_free()
	_icons.clear()

	for item_id: String in _grid._placed:
		var entry: Dictionary  = _grid._placed[item_id]
		var item:  Item        = entry["item"]
		var pos:   Vector2i    = entry["pos"]
		var rotated: bool      = entry["rotated"]
		var eff := Vector2i(item.grid_size.y, item.grid_size.x) if rotated else item.grid_size
		var icon := ItemIcon.new()
		add_child(icon)
		icon.setup(item, "pack:%d:%s" % [compartment_index, item_id], eff.x, eff.y)
		icon.position = Vector2(pos.x * CELL_SIZE + 1, pos.y * CELL_SIZE + 1)
		_icons[item_id] = icon

func _can_drop_data(at_pos: Vector2, data: Variant) -> bool:
	if not (data is Dictionary) or not data.has("item"):
		return false
	var item := data["item"] as Item
	var gp := _to_grid(at_pos)
	return _grid.can_place(item, gp, false) or _grid.can_place(item, gp, true)

func _drop_data(at_pos: Vector2, data: Variant) -> void:
	var item       := data["item"] as Item
	var source_key := data["source_key"] as String
	var gp := _to_grid(at_pos)
	var rotated := not _grid.can_place(item, gp, false) and _grid.can_place(item, gp, true)
	item_dropped.emit(compartment_index, item, gp, rotated, source_key)

func _to_grid(pos: Vector2) -> Vector2i:
	return Vector2i(int(pos.x / CELL_SIZE), int(pos.y / CELL_SIZE))
