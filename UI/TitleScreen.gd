class_name TitleScreen
extends CanvasLayer

signal start_pressed

var _fired: bool = false

func _ready() -> void:
	layer        = 20
	process_mode = PROCESS_MODE_ALWAYS

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.04, 0.06)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 28)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "ZHUKOV"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 80)
	title.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(title)

	var prompt := Label.new()
	prompt.text = "PRESS ANYWHERE TO START"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 16)
	prompt.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	vbox.add_child(prompt)

	var tween := create_tween().set_loops()
	tween.tween_property(prompt, "modulate:a", 0.2, 0.85).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(prompt, "modulate:a", 1.0, 0.85).set_ease(Tween.EASE_IN_OUT)

func _input(event: InputEvent) -> void:
	if _fired:
		return
	var pressed := false
	if event is InputEventScreenTouch:
		pressed = event.pressed
	elif event is InputEventMouseButton:
		pressed = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if pressed:
		_fired = true
		get_viewport().set_input_as_handled()
		start_pressed.emit()
