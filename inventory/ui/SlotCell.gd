class_name SlotCell
extends Panel

const CELL_SIZE := 56
const CELL_W    := 3   # equipment slot display width in cells
const CELL_H    := 1   # equipment slot display height in cells

signal item_dropped(slot_name: String, item: Item, source_key: String)

var slot_name: String
var _inventory: InventorySystem
var _name_label: Label
var _icon: ItemIcon = null

func setup(p_slot_name: String, p_inventory: InventorySystem) -> void:
	slot_name    = p_slot_name
	_inventory   = p_inventory
	custom_minimum_size = Vector2(CELL_W * CELL_SIZE, CELL_H * CELL_SIZE + 20)
	size = custom_minimum_size
	_apply_style(Color(0.12, 0.12, 0.18, 0.92))

	_name_label = Label.new()
	_name_label.text = p_slot_name.replace("_", " ").to_upper()
	_name_label.add_theme_font_size_override("font_size", 9)
	_name_label.modulate = Color(0.55, 0.55, 0.55)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_label)

func refresh() -> void:
	if _icon:
		_icon.queue_free()
		_icon = null
	var slot := _inventory.get_slot(slot_name)
	if slot == null or slot.is_empty():
		return
	_icon = ItemIcon.new()
	add_child(_icon)
	_icon.setup(slot.item, "equip:" + slot_name, CELL_W, CELL_H)
	_icon.position = Vector2(0, 20)

func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	if not (data is Dictionary) or not data.has("item"):
		return false
	var slot := _inventory.get_slot(slot_name)
	return slot != null and slot.accepts(data["item"] as Item)

func _drop_data(_pos: Vector2, data: Variant) -> void:
	item_dropped.emit(slot_name, data["item"] as Item, data["source_key"] as String)

func _apply_style(color: Color) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_width_all = 1
	s.border_color = Color(0.4, 0.4, 0.4, 0.5)
	s.corner_radius_all = 3
	add_theme_stylebox_override("panel", s)
