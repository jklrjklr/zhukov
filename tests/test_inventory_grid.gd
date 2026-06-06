extends Object


func _item(id: String, w: int, h: int) -> Item:
	var item := Item.new()
	item.item_id = id
	item.type = "consumable"
	item.grid_size = Vector2i(w, h)
	return item


func test_place_and_retrieve() -> void:
	var grid := InventoryGrid.new(4, 4)
	var item := _item("a", 2, 2)
	assert(grid.place_item(item, Vector2i(0, 0)), "place 2x2 at origin")
	assert(grid.get_item_at(Vector2i(0, 0)) == item, "top-left cell returns item")
	assert(grid.get_item_at(Vector2i(1, 1)) == item, "bottom-right cell of item returns item")
	assert(grid.get_item_at(Vector2i(2, 0)) == null, "cell outside item is empty")


func test_overlap_prevented() -> void:
	var grid := InventoryGrid.new(4, 4)
	assert(grid.place_item(_item("a", 2, 2), Vector2i(0, 0)), "first place ok")
	assert(not grid.place_item(_item("b", 2, 2), Vector2i(1, 1)), "overlapping place fails")


func test_out_of_bounds_rejected() -> void:
	var grid := InventoryGrid.new(3, 3)
	assert(not grid.place_item(_item("a", 2, 2), Vector2i(2, 2)), "extends past boundary")
	assert(not grid.place_item(_item("b", 1, 1), Vector2i(-1, 0)), "negative column")


func test_remove_frees_cells() -> void:
	var grid := InventoryGrid.new(4, 4)
	grid.place_item(_item("a", 2, 2), Vector2i(0, 0))
	grid.remove_item("a")
	assert(grid.place_item(_item("b", 2, 2), Vector2i(0, 0)), "cells freed after removal")


func test_rotation_allows_tall_item_sideways() -> void:
	var grid := InventoryGrid.new(3, 2)
	var tall := _item("t", 1, 3)  # 1 col, 3 rows — won't fit upright in 2-row grid
	assert(not grid.can_place(tall, Vector2i(0, 0), false), "1x3 upright doesn't fit in 2-row grid")
	assert(grid.can_place(tall, Vector2i(0, 0), true), "rotated 1x3 becomes 3x1, fits in 3-col grid")
	assert(grid.place_item(tall, Vector2i(0, 0), true), "rotated placement succeeds")


func test_find_free_spot_skips_occupied() -> void:
	var grid := InventoryGrid.new(4, 4)
	grid.place_item(_item("a", 2, 2), Vector2i(0, 0))
	var pos := grid.find_free_spot(_item("b", 2, 2))
	assert(pos.x >= 0, "found a free spot")
	assert(grid.can_place(_item("b", 2, 2), pos), "reported spot is actually free")


func test_find_free_spot_returns_negative_when_full() -> void:
	var grid := InventoryGrid.new(2, 2)
	grid.place_item(_item("a", 2, 2), Vector2i(0, 0))
	var pos := grid.find_free_spot(_item("b", 1, 1))
	assert(pos == Vector2i(-1, -1), "no room in full grid")


func test_to_dict_round_trip() -> void:
	var grid := InventoryGrid.new(4, 4)
	var item := _item("ammo_556", 1, 1)
	item.quantity = 30
	grid.place_item(item, Vector2i(2, 3))
	var d := grid.to_dict()
	assert(d["size"] == [4, 4], "size serialised")
	assert(d["items"].size() == 1, "one item in dict")
	assert(d["items"][0]["item_id"] == "ammo_556", "item id correct")
	assert(d["items"][0]["grid_pos"] == [2, 3], "grid pos correct")
