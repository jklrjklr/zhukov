# Visual weapon mod view: weapon sprite with slot pins at physical positions.
# Clicking a pin opens a side panel to swap or remove that part.
class_name WeaponModVisual
extends Control

signal part_swapped(slot_name: String, new_part_id: String, old_part_id: String)
signal shop_search_requested(tag: String)

const PIN_SIZE := Vector2(22.0, 22.0)
const SPRITE_DISPLAY_SIZE := Vector2(320.0, 400.0)

var _weapon: WeaponData = null
var _inventory: InventorySystem = null
var _item_db: Node = null

var _sprite_rect: TextureRect = null
var _pins_layer: Control = null
var _detail_panel: PanelContainer = null
var _selected_slot: String = ""

# Detail panel children
var _detail_slot_label: Label = null
var _detail_part_label: Label = null
var _detail_vital_label: Label = null
var _detail_stats_box: VBoxContainer = null
var _swap_btn: Button = null
var _remove_btn: Button = null
var _compat_scroll: ScrollContainer = null
var _compat_list: VBoxContainer = null
var _shop_btn: Button = null

func _init() -> void:
	name = "WeaponModVisual"

func setup(weapon: WeaponData, inventory: InventorySystem, item_db: Node) -> void:
	_weapon = weapon
	_inventory = inventory
	_item_db = item_db
	_build_ui()
	_refresh_pins()

func _build_ui() -> void:
	custom_minimum_size = Vector2(880.0, 540.0)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(hbox)

	# --- Left: weapon image + pins ---
	var weapon_area := Control.new()
	weapon_area.custom_minimum_size = Vector2(500.0, 0.0)
	weapon_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(weapon_area)

	_sprite_rect = TextureRect.new()
	_sprite_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sprite_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_sprite_rect.size = SPRITE_DISPLAY_SIZE
	_sprite_rect.position = (Vector2(500.0, 540.0) - SPRITE_DISPLAY_SIZE) * 0.5
	if _weapon != null and not _weapon.sprite_path.is_empty():
		var tex = load(_weapon.sprite_path)
		if tex:
			_sprite_rect.texture = tex
	weapon_area.add_child(_sprite_rect)

	_pins_layer = Control.new()
	_pins_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pins_layer.size = SPRITE_DISPLAY_SIZE
	_pins_layer.position = _sprite_rect.position
	weapon_area.add_child(_pins_layer)

	# --- Right: slot detail panel ---
	_detail_panel = PanelContainer.new()
	_detail_panel.custom_minimum_size = Vector2(340.0, 0.0)
	_detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_panel.visible = false
	hbox.add_child(_detail_panel)

	var detail_vbox := VBoxContainer.new()
	detail_vbox.add_theme_constant_override("separation", 6)
	_detail_panel.add_child(detail_vbox)

	_detail_slot_label = Label.new()
	_detail_slot_label.add_theme_font_size_override("font_size", 15)
	detail_vbox.add_child(_detail_slot_label)

	_detail_vital_label = Label.new()
	_detail_vital_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	detail_vbox.add_child(_detail_vital_label)

	_detail_part_label = Label.new()
	_detail_part_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_vbox.add_child(_detail_part_label)

	var sep1 := HSeparator.new()
	detail_vbox.add_child(sep1)

	var stats_title := Label.new()
	stats_title.text = "Stat modifiers:"
	detail_vbox.add_child(stats_title)

	_detail_stats_box = VBoxContainer.new()
	detail_vbox.add_child(_detail_stats_box)

	var sep2 := HSeparator.new()
	detail_vbox.add_child(sep2)

	var compat_title := Label.new()
	compat_title.text = "In inventory:"
	detail_vbox.add_child(compat_title)

	_compat_scroll = ScrollContainer.new()
	_compat_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_compat_scroll.custom_minimum_size = Vector2(0.0, 120.0)
	detail_vbox.add_child(_compat_scroll)

	_compat_list = VBoxContainer.new()
	_compat_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_compat_scroll.add_child(_compat_list)

	_swap_btn = Button.new()
	_swap_btn.text = "Swap Part"
	_swap_btn.visible = false
	_swap_btn.pressed.connect(_on_swap_requested)
	detail_vbox.add_child(_swap_btn)

	_remove_btn = Button.new()
	_remove_btn.text = "Remove Part"
	_remove_btn.visible = false
	_remove_btn.pressed.connect(_on_remove_requested)
	detail_vbox.add_child(_remove_btn)

	_shop_btn = Button.new()
	_shop_btn.text = "Find in Shop..."
	_shop_btn.pressed.connect(_on_shop_pressed)
	detail_vbox.add_child(_shop_btn)

func _refresh_pins() -> void:
	for child in _pins_layer.get_children():
		child.queue_free()

	if _weapon == null:
		return

	for slot_name: String in _weapon.get_slot_names():
		var slot_def := _weapon.get_slot_def(slot_name)
		var ui_pos: Vector2 = slot_def.get("ui_pos", Vector2(0.5, 0.5))
		var is_vital: bool = slot_def.get("vital", false)
		var att: AttachmentData = _weapon.get_attachment(slot_name)
		var filled := att != null

		var btn := Button.new()
		btn.custom_minimum_size = PIN_SIZE
		btn.size = PIN_SIZE
		btn.position = ui_pos * SPRITE_DISPLAY_SIZE - PIN_SIZE * 0.5
		btn.tooltip_text = slot_def.get("display_name", slot_name)
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		_pins_layer.mouse_filter = Control.MOUSE_FILTER_PASS

		# Color coding
		var style := StyleBoxFlat.new()
		style.corner_radius_top_left = 11
		style.corner_radius_top_right = 11
		style.corner_radius_bottom_left = 11
		style.corner_radius_bottom_right = 11
		if filled:
			style.bg_color = Color(0.2, 0.8, 0.3) if is_vital else Color(0.2, 0.7, 1.0)
		else:
			style.bg_color = Color(0.9, 0.2, 0.2) if is_vital else Color(0.35, 0.35, 0.35)
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
		btn.text = "V" if is_vital else "o"
		btn.add_theme_font_size_override("font_size", 10)

		var captured_slot := slot_name
		btn.pressed.connect(func(): _select_slot(captured_slot))
		_pins_layer.add_child(btn)

func _select_slot(slot_name: String) -> void:
	_selected_slot = slot_name
	_detail_panel.visible = true

	var slot_def := _weapon.get_slot_def(slot_name)
	var is_vital: bool = slot_def.get("vital", false)
	var att: AttachmentData = _weapon.get_attachment(slot_name)

	_detail_slot_label.text = slot_def.get("display_name", slot_name).to_upper()
	_detail_vital_label.text = "★ VITAL — gun disabled if empty" if is_vital else ""
	_detail_vital_label.visible = is_vital
	_detail_part_label.text = att.display_name if att != null else "(empty)"

	# Stat mods display
	for c in _detail_stats_box.get_children():
		c.queue_free()
	if att != null and not att.stat_mods.is_empty():
		for stat: String in att.stat_mods:
			var val: float = float(att.stat_mods[stat])
			var lbl := Label.new()
			var sign_str := "+" if val >= 0.0 else ""
			lbl.text = "  %s: %s%.2f" % [stat, sign_str, val]
			lbl.add_theme_color_override("font_color",
				Color(0.4, 1.0, 0.4) if val >= 0.0 else Color(1.0, 0.5, 0.5))
			lbl.add_theme_font_size_override("font_size", 11)
			_detail_stats_box.add_child(lbl)
	else:
		var lbl := Label.new()
		lbl.text = "  (none)"
		lbl.add_theme_font_size_override("font_size", 11)
		_detail_stats_box.add_child(lbl)

	_remove_btn.visible = att != null and not is_vital
	_swap_btn.visible = false

	# Compatible items in inventory
	_refresh_compat_list(slot_name, slot_def)

func _refresh_compat_list(slot_name: String, slot_def: Dictionary) -> void:
	for c in _compat_list.get_children():
		c.queue_free()
	_swap_btn.visible = false

	var accepts_tag: String = slot_def.get("accepts_tag", "")
	var compatible_items := _find_compatible_in_inventory(accepts_tag)

	if compatible_items.is_empty():
		var lbl := Label.new()
		lbl.text = "Nothing compatible in inventory."
		lbl.add_theme_font_size_override("font_size", 11)
		_compat_list.add_child(lbl)
		return

	for item: Item in compatible_items:
		var row := HBoxContainer.new()
		var name_lbl := Label.new()
		name_lbl.text = item.display_name
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", 11)
		row.add_child(name_lbl)

		var equip_btn := Button.new()
		equip_btn.text = "Equip"
		equip_btn.add_theme_font_size_override("font_size", 10)
		var captured_item := item
		equip_btn.pressed.connect(func(): _on_equip_from_inventory(slot_name, captured_item))
		row.add_child(equip_btn)
		_compat_list.add_child(row)

func _find_compatible_in_inventory(accepts_tag: String) -> Array:
	if _inventory == null or _item_db == null or accepts_tag.is_empty():
		return []
	var result: Array = []
	for grid: InventoryGrid in _inventory.backpack_compartments:
		for item: Item in grid.get_all_items():
			var def: Dictionary = _item_db.get_item(item.item_id)
			var tags: Array = def.get("tags", [])
			if tags.has(accepts_tag):
				result.append(item)
	return result

func _on_equip_from_inventory(slot_name: String, inv_item: Item) -> void:
	var old_att := _weapon.get_attachment(slot_name)
	var old_id := old_att.item_id if old_att != null else ""

	# Return old part to inventory
	if old_att != null:
		var old_def := _item_db.get_item(old_att.item_id)
		if not old_def.is_empty():
			_inventory.auto_add_to_backpack(Item.from_dict(old_att.item_id, old_def))

	# Remove new part from inventory
	for i in _inventory.backpack_compartments.size():
		if _inventory.backpack_compartments[i].get_item_by_id(inv_item.item_id) != null:
			_inventory.backpack_compartments[i].remove_item(inv_item.item_id)
			break

	# Attach to weapon
	var new_def := _item_db.get_item(inv_item.item_id)
	var new_att := AttachmentData.from_dict(inv_item.item_id, new_def)
	_weapon.attach(slot_name, new_att)

	_refresh_pins()
	_select_slot(slot_name)
	part_swapped.emit(slot_name, inv_item.item_id, old_id)

func _on_swap_requested() -> void:
	pass  # reserved; compatible list handles equipping directly

func _on_remove_requested() -> void:
	if _selected_slot.is_empty() or _weapon == null:
		return
	if _weapon.is_vital(_selected_slot):
		return
	var old_att := _weapon.detach(_selected_slot)
	if old_att != null and _inventory != null and _item_db != null:
		var def := _item_db.get_item(old_att.item_id)
		if not def.is_empty():
			_inventory.auto_add_to_backpack(Item.from_dict(old_att.item_id, def))
	_refresh_pins()
	_select_slot(_selected_slot)
	part_swapped.emit(_selected_slot, "", old_att.item_id if old_att else "")

func _on_shop_pressed() -> void:
	if _selected_slot.is_empty() or _weapon == null:
		return
	var slot_def := _weapon.get_slot_def(_selected_slot)
	var tag: String = slot_def.get("accepts_tag", "")
	shop_search_requested.emit(tag)

func refresh() -> void:
	_refresh_pins()
	if not _selected_slot.is_empty():
		_select_slot(_selected_slot)
