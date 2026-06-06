class_name ItemIcon
extends Panel

const CELL_SIZE := 56

var item: Item
var source_key: String   # "equip:slot_name" | "pack:ci:item_id"

var _label: Label

func _ready() -> void:
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 11)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

func setup(p_item: Item, p_source_key: String, forced_cols: int = -1, forced_rows: int = -1) -> void:
	item = p_item
	source_key = p_source_key
	var c := forced_cols if forced_cols > 0 else p_item.grid_size.x
	var r := forced_rows if forced_rows > 0 else p_item.grid_size.y
	custom_minimum_size = Vector2(c * CELL_SIZE - 2, r * CELL_SIZE - 2)
	size = custom_minimum_size
	_label.text = p_item.display_name if p_item.display_name != "" else p_item.item_id
	var s := StyleBoxFlat.new()
	s.bg_color = _color_for_type(p_item.type)
	s.border_width_all = 2
	s.border_color = Color(1, 1, 1, 0.65)
	s.corner_radius_all = 4
	add_theme_stylebox_override("panel", s)

func _get_drag_data(_pos: Vector2) -> Variant:
	var ghost := duplicate() as Control
	ghost.modulate.a = 0.55
	set_drag_preview(ghost)
	return {"item": item, "source_key": source_key}

static func _color_for_type(t: String) -> Color:
	match t:
		"helmet":     return Color(0.35, 0.55, 0.85, 0.92)
		"armor":      return Color(0.45, 0.45, 0.65, 0.92)
		"rig":        return Color(0.55, 0.65, 0.45, 0.92)
		"weapon":     return Color(0.75, 0.35, 0.35, 0.92)
		"consumable": return Color(0.35, 0.75, 0.45, 0.92)
		"grenade":    return Color(0.85, 0.65, 0.25, 0.92)
		"tactical":   return Color(0.65, 0.55, 0.80, 0.92)
		_:            return Color(0.45, 0.45, 0.45, 0.92)
