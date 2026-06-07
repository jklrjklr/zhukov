class_name InputLayoutEditor
extends Control

const SAVE_PATH  := "user://input_layout.json"
const COL_BORDER := Color(0.30, 0.72, 1.00, 0.90)
const COL_DRAG   := Color(1.00, 0.82, 0.10, 1.00)
const COL_BG     := Color(0.00, 0.00, 0.00, 0.42)
const COL_LABEL  := Color(1.00, 1.00, 1.00, 0.95)

signal editing_done

# id → { "node": Node, "label": String, "default_pos": Vector2 }
var _entries: Dictionary = {}
var _drag_id:   String  = ""
var _drag_off:  Vector2 = Vector2.ZERO
var _touch_idx: int     = -1
var _font: Font
var _done_btn:  Button
var _reset_btn: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false
	_font = ThemeDB.fallback_font

	_done_btn  = _make_btn("✓  DONE",  Color(0.12, 0.55, 0.22))
	_done_btn.pressed.connect(end_edit)
	add_child(_done_btn)

	_reset_btn = _make_btn("⟳  RESET", Color(0.50, 0.20, 0.08))
	_reset_btn.pressed.connect(reset_to_defaults)
	add_child(_reset_btn)

func _make_btn(label: String, bg: Color) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(140, 50)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_stylebox_override("normal",
		_flat_style(bg))
	b.add_theme_stylebox_override("hover",
		_flat_style(bg.lightened(0.15)))
	b.add_theme_stylebox_override("pressed",
		_flat_style(bg.darkened(0.15)))
	return b

func _flat_style(col: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.corner_radius_top_left     = 6
	s.corner_radius_top_right    = 6
	s.corner_radius_bottom_left  = 6
	s.corner_radius_bottom_right = 6
	return s

# ── Public API ─────────────────────────────────────────────────────────────

func register(id: String, label: String, node: Node) -> void:
	_entries[id] = {
		"node":        node,
		"label":       label,
		"default_pos": _node_pos(node),
	}

func begin_edit() -> void:
	_normalize_anchors()
	var sw := get_viewport_rect().size.x
	_done_btn.position  = Vector2(sw * 0.5 - 155.0, 16.0)
	_reset_btn.position = Vector2(sw * 0.5 + 15.0,  16.0)
	visible = true
	mouse_filter = MOUSE_FILTER_STOP
	queue_redraw()

func end_edit() -> void:
	_drag_id   = ""
	_touch_idx = -1
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false
	save()
	editing_done.emit()

func reset_to_defaults() -> void:
	for id in _entries:
		_set_node_pos(_entries[id].node, _entries[id].default_pos)
	queue_redraw()

func save() -> void:
	var data: Dictionary = {}
	for id: String in _entries:
		var pos := _node_pos(_entries[id].node)
		data[id] = [pos.x, pos.y]
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))

func load_saved() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not f:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		return
	for id: String in (parsed as Dictionary):
		if not _entries.has(id):
			continue
		var arr: Variant = (parsed as Dictionary)[id]
		if arr is Array and (arr as Array).size() >= 2:
			_set_node_pos(_entries[id].node,
				Vector2((arr as Array)[0], (arr as Array)[1]))

# ── Input ───────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_on_drag(event as InputEventScreenDrag)

func _on_touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		if _touch_idx != -1:
			return
		for id: String in _entries:
			var rect := Rect2(_node_pos(_entries[id].node), _node_size(_entries[id].node))
			if rect.has_point(e.position):
				_drag_id   = id
				_drag_off  = _node_pos(_entries[id].node) - e.position
				_touch_idx = e.index
				queue_redraw()
				get_viewport().set_input_as_handled()
				return
	else:
		if e.index == _touch_idx:
			_drag_id   = ""
			_touch_idx = -1
			queue_redraw()

func _on_drag(e: InputEventScreenDrag) -> void:
	if e.index != _touch_idx or _drag_id == "":
		return
	var sz     := _node_size(_entries[_drag_id].node)
	var screen := get_viewport_rect().size
	var new_pos: Vector2 = (e.position + _drag_off).clamp(
		Vector2.ZERO, screen - sz)
	_set_node_pos(_entries[_drag_id].node, new_pos)
	queue_redraw()
	get_viewport().set_input_as_handled()

# ── Drawing ─────────────────────────────────────────────────────────────────

func _draw() -> void:
	draw_rect(get_rect(), COL_BG)
	if _font != null:
		var sw := size.x
		draw_string(_font,
			Vector2(sw * 0.5 - 55.0, 10.0),
			"EDIT LAYOUT",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)

	for id: String in _entries:
		var node  = _entries[id].node
		var pos   := _node_pos(node)
		var sz    := _node_size(node)
		var rect  := Rect2(pos, sz)
		var col   := COL_DRAG if id == _drag_id else COL_BORDER

		draw_rect(rect, Color(col.r, col.g, col.b, 0.18))
		draw_rect(rect, col, false, 2.5)

		if _font != null:
			draw_string(_font, pos + Vector2(5.0, sz.y * 0.5 + 6.0),
				_entries[id].label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
				COL_LABEL if id != _drag_id else COL_DRAG)

# ── Helpers ─────────────────────────────────────────────────────────────────

func _normalize_anchors() -> void:
	for id: String in _entries:
		var node = _entries[id].node
		if not (node is Control):
			continue
		var ctrl := node as Control
		if ctrl.anchor_left != 0.0 or ctrl.anchor_top != 0.0:
			var abs_pos := ctrl.get_global_rect().position
			var abs_size := ctrl.get_global_rect().size
			ctrl.set_anchors_and_offsets_preset(PRESET_TOP_LEFT)
			ctrl.position = abs_pos
			ctrl.size     = abs_size
		_entries[id].default_pos = ctrl.position

func _node_pos(node: Node) -> Vector2:
	if node is Control: return (node as Control).position
	if node is Node2D:  return (node as Node2D).position
	return Vector2.ZERO

func _set_node_pos(node: Node, pos: Vector2) -> void:
	if node is Control: (node as Control).position = pos
	elif node is Node2D: (node as Node2D).position = pos

func _node_size(node: Node) -> Vector2:
	if node is Control: return (node as Control).size
	return Vector2(140.0, 60.0)
