# List weapon mod view: weapon preview + stat summary | slot rows | compatible parts panel.
class_name WeaponModList
extends Control

signal part_swapped(slot_name: String, new_part_id: String, old_part_id: String)
signal shop_search_requested(tag: String)

var _weapon: WeaponData = null
var _inventory: InventorySystem = null
var _item_db: Node = null

var _selected_slot: String = ""
var _selected_inv_item: Item = null

# Left panel
var _weapon_tex: TextureRect = null
var _stats_label: Label = null
var _functional_label: Label = null

# Middle panel
var _slot_list: VBoxContainer = null

# Right panel
var _right_panel: VBoxContainer = null
var _right_title: Label = null
var _parts_list: VBoxContainer = null
var _confirm_btn: Button = null
var _shop_btn: Button = null

func _init() -> void:
	name = "WeaponModList"

func setup(weapon: WeaponData, inventory: InventorySystem, item_db: Node) -> void:
	_weapon = weapon
	_inventory = inventory
	_item_db = item_db
	_build_ui()
	_refresh_slots()
	_refresh_stats()

func _build_ui() -> void:
	custom_minimum_size = Vector2(880.0, 540.0)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 0)
	add_child(hbox)

	# --- Left: weapon image + stats ---
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(200.0, 0.0)
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	hbox.add_child(left)

	_weapon_tex = TextureRect.new()
	_weapon_tex.custom_minimum_size = Vector2(180.0, 220.0)
	_weapon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_weapon_tex.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	if _weapon != null and not _weapon.sprite_path.is_empty():
		var tex = load(_weapon.sprite_path)
		if tex:
			_weapon_tex.texture = tex
	left.add_child(_weapon_tex)

	_functional_label = Label.new()
	_functional_label.add_theme_font_size_override("font_size", 13)
	left.add_child(_functional_label)

	_stats_label = Label.new()
	_stats_label.add_theme_font_size_override("font_size", 11)
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_stats_label)

	hbox.add_child(VSeparator.new())

	# --- Middle: slot list ---
	var mid := VBoxContainer.new()
	mid.custom_minimum_size = Vector2(270.0, 0.0)
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 4)
	hbox.add_child(mid)

	var mid_title := Label.new()
	mid_title.text = "SLOTS"
	mid_title.add_theme_font_size_override("font_size", 14)
	mid.add_child(mid_title)
	mid.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(scroll)

	_slot_list = VBoxContainer.new()
	_slot_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slot_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_slot_list)

	hbox.add_child(VSeparator.new())

	# --- Right: compatible parts ---
	_right_panel = VBoxContainer.new()
	_right_panel.custom_minimum_size = Vector2(290.0, 0.0)
	_right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right_panel.add_theme_constant_override("separation", 6)
	_right_panel.visible = false
	hbox.add_child(_right_panel)

	_right_title = Label.new()
	_right_title.add_theme_font_size_override("font_size", 13)
	_right_panel.add_child(_right_title)
	_right_panel.add_child(HSeparator.new())

	var parts_scroll := ScrollContainer.new()
	parts_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right_panel.add_child(parts_scroll)

	_parts_list = VBoxContainer.new()
	_parts_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_parts_list.add_theme_constant_override("separation", 3)
	parts_scroll.add_child(_parts_list)

	_right_panel.add_child(HSeparator.new())

	_confirm_btn = Button.new()
	_confirm_btn.text = "Equip Selected"
	_confirm_btn.visible = false
	_confirm_btn.pressed.connect(_on_confirm_equip)
	_right_panel.add_child(_confirm_btn)

	_shop_btn = Button.new()
	_shop_btn.text = "Find in Shop..."
	_shop_btn.pressed.connect(_on_shop_pressed)
	_right_panel.add_child(_shop_btn)

func _refresh_stats() -> void:
	if _weapon == null:
		return
	var functional := _weapon.is_functional()
	_functional_label.text = "FUNCTIONAL" if functional else "★ DISABLED — missing vital part"
	_functional_label.add_theme_color_override("font_color",
		Color(0.3, 1.0, 0.4) if functional else Color(1.0, 0.3, 0.3))

	_stats_label.text = (
		"DMG  %.0f\nRPM  %d\nSPRD %.2f°\nERGO %.0f%%\nWT   %.2fkg\nRDS  %d/%d" % [
		_weapon.get_effective_damage(),
		_weapon.rpm,
		_weapon.get_effective_spread(),
		_weapon.get_effective_ergonomics() * 100.0,
		_weapon.get_effective_weight(),
		_weapon.ammo_current,
		_weapon.get_effective_magazine_size(),
	])

func _refresh_slots() -> void:
	for c in _slot_list.get_children():
		c.queue_free()
	if _weapon == null:
		return

	for slot_name: String in _weapon.get_slot_names():
		var slot_def := _weapon.get_slot_def(slot_name)
		var is_vital: bool = slot_def.get("vital", false)
		var att: AttachmentData = _weapon.get_attachment(slot_name)
		var filled := att != null

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		# Status dot
		var dot := Label.new()
		dot.add_theme_font_size_override("font_size", 14)
		if filled:
			dot.text = "●"
			dot.add_theme_color_override("font_color",
				Color(0.2, 0.9, 0.3) if is_vital else Color(0.2, 0.8, 1.0))
		else:
			dot.text = "○"
			dot.add_theme_color_override("font_color",
				Color(1.0, 0.2, 0.2) if is_vital else Color(0.5, 0.5, 0.5))
		row.add_child(dot)

		var slot_col := VBoxContainer.new()
		slot_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var slot_name_lbl := Label.new()
		slot_name_lbl.text = slot_def.get("display_name", slot_name)
		slot_name_lbl.add_theme_font_size_override("font_size", 12)
		slot_col.add_child(slot_name_lbl)

		var part_lbl := Label.new()
		part_lbl.text = att.display_name if att != null else "(empty)"
		part_lbl.add_theme_font_size_override("font_size", 10)
		part_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		slot_col.add_child(part_lbl)

		row.add_child(slot_col)

		var arrow_btn := Button.new()
		arrow_btn.text = "→"
		arrow_btn.add_theme_font_size_override("font_size", 12)
		var captured := slot_name
		arrow_btn.pressed.connect(func(): _select_slot(captured))
		row.add_child(arrow_btn)

		_slot_list.add_child(row)

func _select_slot(slot_name: String) -> void:
	_selected_slot = slot_name
	_selected_inv_item = null
	_confirm_btn.visible = false
	_right_panel.visible = true

	var slot_def := _weapon.get_slot_def(slot_name)
	var is_vital: bool = slot_def.get("vital", false)
	var att: AttachmentData = _weapon.get_attachment(slot_name)
	var title := slot_def.get("display_name", slot_name).to_upper()
	if is_vital:
		title += " [VITAL]"
	_right_title.text = title

	for c in _parts_list.get_children():
		c.queue_free()

	var accepts_tag: String = slot_def.get("accepts_tag", "")

	# "Remove" entry if a non-vital part is installed
	if att != null and not is_vital:
		_add_part_entry("(Remove part)", "", att.item_id, is_vital)

	# Items in inventory
	var inv_items := _find_compatible_in_inventory(accepts_tag)
	if inv_items.is_empty() and att == null:
		var lbl := Label.new()
		lbl.text = "Nothing in inventory."
		lbl.add_theme_font_size_override("font_size", 11)
		_parts_list.add_child(lbl)
	else:
		for item: Item in inv_items:
			_add_part_entry(item.display_name, item.item_id, "", is_vital)

func _add_part_entry(label_text: String, item_id: String, replaces_id: String, _is_vital: bool) -> void:
	var row := HBoxContainer.new()

	var name_lbl := Label.new()
	name_lbl.text = label_text
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 11)

	# Show key stat delta if we can
	if not item_id.is_empty() and _item_db != null:
		var def := _item_db.get_item(item_id)
		var mods: Dictionary = def.get("stat_mods", {})
		if not mods.is_empty():
			var first_key: String = mods.keys()[0]
			var v: float = float(mods[first_key])
			var col := Color(0.4, 1.0, 0.4) if v >= 0.0 else Color(1.0, 0.5, 0.5)
			name_lbl.add_theme_color_override("font_color", col)

	row.add_child(name_lbl)

	var sel_btn := Button.new()
	sel_btn.text = "Select"
	sel_btn.add_theme_font_size_override("font_size", 10)
	var captured_id := item_id
	var captured_rep := replaces_id
	sel_btn.pressed.connect(func(): _on_part_selected(captured_id, captured_rep))
	row.add_child(sel_btn)

	_parts_list.add_child(row)

func _on_part_selected(item_id: String, replaces_id: String) -> void:
	if item_id.is_empty() and replaces_id.is_empty():
		return

	if item_id.is_empty():
		# Remove action
		_on_confirm_remove()
		return

	# Find the item in inventory to confirm
	_selected_inv_item = _find_item_in_inventory(item_id)
	if _selected_inv_item == null:
		return
	_confirm_btn.visible = true

func _on_confirm_equip() -> void:
	if _selected_inv_item == null or _selected_slot.is_empty():
		return

	var old_att := _weapon.get_attachment(_selected_slot)
	var old_id := old_att.item_id if old_att != null else ""

	if old_att != null and _inventory != null and _item_db != null:
		var old_def := _item_db.get_item(old_att.item_id)
		if not old_def.is_empty():
			_inventory.auto_add_to_backpack(Item.from_dict(old_att.item_id, old_def))

	for i in _inventory.backpack_compartments.size():
		if _inventory.backpack_compartments[i].get_item_by_id(_selected_inv_item.item_id) != null:
			_inventory.backpack_compartments[i].remove_item(_selected_inv_item.item_id)
			break

	var new_def := _item_db.get_item(_selected_inv_item.item_id)
	var new_att := AttachmentData.from_dict(_selected_inv_item.item_id, new_def)
	_weapon.attach(_selected_slot, new_att)

	_selected_inv_item = null
	_confirm_btn.visible = false
	_refresh_slots()
	_refresh_stats()
	_select_slot(_selected_slot)
	part_swapped.emit(_selected_slot, new_att.item_id, old_id)

func _on_confirm_remove() -> void:
	if _selected_slot.is_empty() or _weapon == null:
		return
	if _weapon.is_vital(_selected_slot):
		return
	var old_att := _weapon.detach(_selected_slot)
	if old_att != null and _inventory != null and _item_db != null:
		var def := _item_db.get_item(old_att.item_id)
		if not def.is_empty():
			_inventory.auto_add_to_backpack(Item.from_dict(old_att.item_id, def))
	_refresh_slots()
	_refresh_stats()
	_select_slot(_selected_slot)
	part_swapped.emit(_selected_slot, "", old_att.item_id if old_att else "")

func _on_shop_pressed() -> void:
	if _selected_slot.is_empty() or _weapon == null:
		return
	var tag: String = _weapon.get_slot_def(_selected_slot).get("accepts_tag", "")
	shop_search_requested.emit(tag)

func _find_compatible_in_inventory(accepts_tag: String) -> Array:
	if _inventory == null or _item_db == null or accepts_tag.is_empty():
		return []
	var result: Array = []
	for grid: InventoryGrid in _inventory.backpack_compartments:
		for item: Item in grid.get_all_items():
			var def: Dictionary = _item_db.get_item(item.item_id)
			if (def.get("tags", []) as Array).has(accepts_tag):
				result.append(item)
	return result

func _find_item_in_inventory(item_id: String) -> Item:
	if _inventory == null:
		return null
	for grid: InventoryGrid in _inventory.backpack_compartments:
		var found := grid.get_item_by_id(item_id)
		if found != null:
			return found
	return null

func refresh() -> void:
	_refresh_slots()
	_refresh_stats()
	if not _selected_slot.is_empty():
		_select_slot(_selected_slot)
