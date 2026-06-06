extends CanvasLayer

var _inventory: InventorySystem
var _slot_cells: Dictionary = {}      # slot_name -> SlotCell
var _comp_grids: Array[CompartmentGrid] = []

func setup(p_inventory: InventorySystem) -> void:
	_inventory = p_inventory
	_build()
	p_inventory.inventory_changed.connect(refresh)
	visible = false

func toggle() -> void:
	visible = not visible
	if visible:
		refresh()

func refresh() -> void:
	for cell: SlotCell in _slot_cells.values():
		cell.refresh()
	for cg: CompartmentGrid in _comp_grids:
		cg.refresh()

func _build() -> void:
	var bg := Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg_s := StyleBoxFlat.new()
	bg_s.bg_color = Color(0.05, 0.05, 0.08, 0.92)
	bg.add_theme_stylebox_override("panel", bg_s)
	add_child(bg)

	var close_btn := Button.new()
	close_btn.text = "✕  CLOSE"
	close_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	close_btn.offset_left = -140
	close_btn.offset_bottom = 44
	close_btn.pressed.connect(func(): visible = false)
	bg.add_child(close_btn)

	var title := Label.new()
	title.text = "INVENTORY"
	title.add_theme_font_size_override("font_size", 18)
	title.position = Vector2(20, 12)
	bg.add_child(title)

	var scroll_eq := ScrollContainer.new()
	scroll_eq.position = Vector2(16, 56)
	scroll_eq.custom_minimum_size = Vector2(200, 620)
	bg.add_child(scroll_eq)
	scroll_eq.add_child(_build_equipment_panel())

	var scroll_bp := ScrollContainer.new()
	scroll_bp.position = Vector2(228, 56)
	scroll_bp.custom_minimum_size = Vector2(980, 620)
	bg.add_child(scroll_bp)
	scroll_bp.add_child(_build_backpack_panel())

func _build_equipment_panel() -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)

	var lbl := Label.new()
	lbl.text = "EQUIPMENT"
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.modulate = Color(0.7, 0.7, 0.7)
	vbox.add_child(lbl)

	for slot_name in ["helmet", "body_armor", "chest_rig",
			"quick_use_1", "quick_use_2",
			"main_weapon_1", "main_weapon_2", "sub_weapon"]:
		var cell := SlotCell.new()
		cell.setup(slot_name, _inventory)
		cell.item_dropped.connect(_on_equip_drop)
		vbox.add_child(cell)
		_slot_cells[slot_name] = cell

	return vbox

func _build_backpack_panel() -> Control:
	var rows: Array = BackpackLayout.parse(_inventory.backpack_layout)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)

	var lbl := Label.new()
	lbl.text = "BACKPACK"
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.modulate = Color(0.7, 0.7, 0.7)
	outer.add_child(lbl)

	for row: Array in rows:
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 10)
		for dim: Vector2i in row:
			var idx := _comp_grids.size()
			var cg := CompartmentGrid.new()
			cg.setup(idx, _inventory)
			cg.item_dropped.connect(_on_pack_drop)
			hbox.add_child(cg)
			_comp_grids.append(cg)
		outer.add_child(hbox)

	return outer

func _on_equip_drop(slot_name: String, item: Item, source_key: String) -> void:
	_remove_source(source_key)
	_inventory.equip(slot_name, item)

func _on_pack_drop(ci: int, item: Item, gp: Vector2i, rotated: bool, source_key: String) -> void:
	_remove_source(source_key)
	_inventory.add_to_backpack(item, ci, gp, rotated)

func _remove_source(key: String) -> void:
	var parts := key.split(":")
	if parts[0] == "equip":
		_inventory.unequip(parts[1])
	elif parts[0] == "pack":
		_inventory.remove_from_backpack(parts[2], int(parts[1]))
