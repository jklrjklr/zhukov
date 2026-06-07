class_name QuickUseBar
extends HBoxContainer

signal item_used(slot_name: String, item: Item)

var _inventory: InventorySystem = null
var _btn1: Button
var _btn2: Button

func setup(inventory: InventorySystem) -> void:
	_inventory = inventory

	_btn1 = _make_button("Q1")
	_btn1.pressed.connect(func(): _use("quick_use_1"))
	add_child(_btn1)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(8, 0)
	add_child(spacer)

	_btn2 = _make_button("Q2")
	_btn2.pressed.connect(func(): _use("quick_use_2"))
	add_child(_btn2)

	inventory.inventory_changed.connect(_refresh)
	_refresh()

func _make_button(default_label: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(80, 80)
	btn.text = "[%s]" % default_label
	btn.add_theme_font_size_override("font_size", 11)
	btn.clip_text = true
	return btn

func _refresh() -> void:
	if _inventory == null:
		return
	_btn1.text = _label(_inventory.quick_use_1, "Q1")
	_btn2.text = _label(_inventory.quick_use_2, "Q2")
	_btn1.modulate = Color.WHITE if not _inventory.quick_use_1.is_empty() else Color(0.5, 0.5, 0.5)
	_btn2.modulate = Color.WHITE if not _inventory.quick_use_2.is_empty() else Color(0.5, 0.5, 0.5)

func _label(slot: InventorySlot, default_key: String) -> String:
	return slot.item.display_name if not slot.is_empty() else "[%s]" % default_key

func _use(slot_name: String) -> void:
	if _inventory == null:
		return
	var slot := _inventory.get_slot(slot_name)
	if slot.is_empty():
		return
	item_used.emit(slot_name, slot.item)
