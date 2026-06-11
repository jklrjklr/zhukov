# Weapon modification screen.
# Two view modes: Visual (sprite + pin buttons) and List (slot rows + parts panel).
# Open with WeaponModScreen.open(weapon_data, inventory, item_db, parent_node).
class_name WeaponModScreen
extends Control

signal closed
signal part_changed(slot_name: String, new_part_id: String, old_part_id: String)
signal shop_search_requested(tag: String)

var _weapon: WeaponData = null
var _inventory: InventorySystem = null
var _item_db: Node = null

var _visual_view: WeaponModVisual = null
var _list_view: WeaponModList = null
var _visual_btn: Button = null
var _list_btn: Button = null
var _title_label: Label = null

# Opens a new WeaponModScreen as a child of parent_node.
static func open(weapon: WeaponData, inventory: InventorySystem, item_db: Node,
		parent: Node) -> WeaponModScreen:
	var screen := WeaponModScreen.new()
	parent.add_child(screen)
	screen._setup(weapon, inventory, item_db)
	return screen

func _setup(weapon: WeaponData, inventory: InventorySystem, item_db: Node) -> void:
	_weapon = weapon
	_inventory = inventory
	_item_db = item_db
	_build_ui()
	_switch_view(false)  # start in List view

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Semi-transparent backdrop
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.0, 0.0, 0.72)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Centered main panel
	var outer := CenterContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(outer)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(920.0, 620.0)
	outer.add_child(panel)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 4)
	panel.add_child(root_vbox)

	# --- Header ---
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	root_vbox.add_child(header)

	_title_label = Label.new()
	_title_label.text = "WEAPON MODDING"
	_title_label.add_theme_font_size_override("font_size", 16)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)

	var view_hbox := HBoxContainer.new()
	header.add_child(view_hbox)

	_visual_btn = Button.new()
	_visual_btn.text = "Visual"
	_visual_btn.toggle_mode = true
	_visual_btn.pressed.connect(func(): _switch_view(true))
	view_hbox.add_child(_visual_btn)

	_list_btn = Button.new()
	_list_btn.text = "List"
	_list_btn.toggle_mode = true
	_list_btn.button_pressed = true
	_list_btn.pressed.connect(func(): _switch_view(false))
	view_hbox.add_child(_list_btn)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.pressed.connect(_on_close)
	header.add_child(close_btn)

	root_vbox.add_child(HSeparator.new())

	# --- Content area ---
	var content := Control.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.custom_minimum_size = Vector2(0.0, 540.0)
	root_vbox.add_child(content)

	if _weapon != null:
		_title_label.text = "WEAPON MODDING — %s" % _weapon.display_name

	_visual_view = WeaponModVisual.new()
	_visual_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_visual_view.part_swapped.connect(_on_part_swapped)
	_visual_view.shop_search_requested.connect(func(tag): shop_search_requested.emit(tag))
	content.add_child(_visual_view)
	_visual_view.setup(_weapon, _inventory, _item_db)

	_list_view = WeaponModList.new()
	_list_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_list_view.part_swapped.connect(_on_part_swapped)
	_list_view.shop_search_requested.connect(func(tag): shop_search_requested.emit(tag))
	content.add_child(_list_view)
	_list_view.setup(_weapon, _inventory, _item_db)

func _switch_view(visual: bool) -> void:
	if _visual_view == null or _list_view == null:
		return
	_visual_view.visible = visual
	_list_view.visible = not visual
	if _visual_btn != null:
		_visual_btn.button_pressed = visual
	if _list_btn != null:
		_list_btn.button_pressed = not visual

func _on_part_swapped(slot_name: String, new_id: String, old_id: String) -> void:
	# Keep both views in sync
	if _visual_view != null and _visual_view.visible:
		_list_view.refresh()
	else:
		_visual_view.refresh()
	part_changed.emit(slot_name, new_id, old_id)

func _on_close() -> void:
	closed.emit()
	queue_free()
