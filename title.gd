extends Node2D

func _ready() -> void:
	var title := TitleScreen.new()
	add_child(title)
	title.start_pressed.connect(func():
		title.queue_free()
		_open_menu())

func _open_menu() -> void:
	var menu := MainMenu.new()
	add_child(menu)
	menu.slot_selected.connect(_on_slot)
	menu.exit_requested.connect(func(): get_tree().quit())

func _on_slot(slot: int) -> void:
	GameState.load_slot(slot)
	get_tree().change_scene_to_file("res://safehouse/Safehouse.tscn")
