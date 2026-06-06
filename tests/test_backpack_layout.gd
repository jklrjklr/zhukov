extends Object


func test_two_compartments_side_by_side() -> void:
	var result := BackpackLayout.parse("{(3,2),(4,3)}")
	assert(result.size() == 1, "one row")
	assert(result[0].size() == 2, "two compartments")
	assert(result[0][0] == Vector2i(3, 2), "first: 3x2")
	assert(result[0][1] == Vector2i(4, 3), "second: 4x3")


func test_vertical_split_produces_two_rows() -> void:
	var result := BackpackLayout.parse("{(2,2) | (4,4)}")
	assert(result.size() == 2, "two rows from pipe separator")
	assert(result[0][0] == Vector2i(2, 2), "top row")
	assert(result[1][0] == Vector2i(4, 4), "bottom row")


func test_mixed_layout() -> void:
	var result := BackpackLayout.parse("{(2,2),(2,2) | (4,4)}")
	assert(result.size() == 2, "two rows")
	assert(result[0].size() == 2, "first row has two compartments")
	assert(result[1].size() == 1, "second row has one compartment")
	assert(result[1][0] == Vector2i(4, 4), "bottom compartment 4x4")


func test_single_compartment() -> void:
	var result := BackpackLayout.parse("{(5,5)}")
	assert(result.size() == 1)
	assert(result[0].size() == 1)
	assert(result[0][0] == Vector2i(5, 5))


func test_preset_combat_ready() -> void:
	var result := BackpackLayout.parse("{(2,3),(3,3) | (2,4),(2,4)}")
	assert(result.size() == 2, "two rows")
	assert(result[0].size() == 2, "top row: two compartments")
	assert(result[1].size() == 2, "bottom row: two compartments")


func test_preset_tactical_columns() -> void:
	var result := BackpackLayout.parse("{(3,6),(3,6),(3,6)}")
	assert(result.size() == 1, "one row")
	assert(result[0].size() == 3, "three columns")
	for dim: Vector2i in result[0]:
		assert(dim == Vector2i(3, 6), "each column is 3x6")


func test_spaces_ignored_around_separators() -> void:
	var a := BackpackLayout.parse("{(3,2) , (4,3)}")
	var b := BackpackLayout.parse("{(3,2),(4,3)}")
	assert(a.size() == b.size(), "rows equal despite spaces")
	assert(a[0].size() == b[0].size(), "compartments equal despite spaces")


func test_inventory_system_applies_layout() -> void:
	var sys := InventorySystem.new()
	sys._init_slots()
	sys.set_backpack_layout("{(2,2),(3,3) | (4,4)}")
	assert(sys.backpack_compartments.size() == 3, "three compartments created")
	assert(sys.backpack_compartments[0].cols == 2 and sys.backpack_compartments[0].rows == 2)
	assert(sys.backpack_compartments[1].cols == 3 and sys.backpack_compartments[1].rows == 3)
	assert(sys.backpack_compartments[2].cols == 4 and sys.backpack_compartments[2].rows == 4)
