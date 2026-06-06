extends CanvasLayer

signal inventory_requested
signal ads_pressed
signal ads_released

@onready var _fire_visual: TextureRect = $FireButton
@onready var _reload_btn: TextureRect = $ReloadButton
@onready var _fire_mode_btn: TextureRect = $FireModeButton
@onready var _mode_label: Label = $FireModeButton/ModeLabel
@onready var _progress_circle: ProgressCircle = $ProgressCircle
@onready var _weapon_system: Node = get_parent().get_node("Player/WeaponSystem")

func _ready() -> void:
	await get_tree().process_frame

	TouchInputHandler.fire_button_rect      = _fire_visual.get_global_rect()
	TouchInputHandler.reload_button_rect    = _reload_btn.get_global_rect()
	TouchInputHandler.fire_mode_button_rect = _fire_mode_btn.get_global_rect()

	_progress_circle.position = Vector2(DisplayServer.window_get_size()) * 0.5

	var inv_btn := Button.new()
	inv_btn.text = "BAG"
	inv_btn.position = Vector2(16, 16)
	inv_btn.size = Vector2(72, 44)
	inv_btn.pressed.connect(func(): inventory_requested.emit())
	add_child(inv_btn)

	var ads_btn := Button.new()
	ads_btn.text = "ADS"
	ads_btn.position = Vector2(16, 70)
	ads_btn.size = Vector2(72, 44)
	ads_btn.button_down.connect(func(): ads_pressed.emit())
	ads_btn.button_up.connect(func(): ads_released.emit())
	add_child(ads_btn)

	_weapon_system.reloading.connect(_on_reloading)
	_weapon_system.reload_complete.connect(_progress_circle.hide_progress)
	_weapon_system.fire_mode_changed.connect(_on_fire_mode_changed)
	_progress_circle.cancelled.connect(_on_reload_cancelled)

	var w: WeaponData = _weapon_system.get_active_weapon()
	if w != null:
		_update_mode_label(w.active_fire_mode)
		_fire_mode_btn.modulate = Color(0.4, 0.4, 0.4) if w.fire_modes.size() <= 1 else Color.WHITE
		_reload_btn.modulate    = Color(0.4, 0.4, 0.4) if w.ammo_current >= w.magazine_size else Color.WHITE

func _on_reloading(_duration: float) -> void:
	_progress_circle.start("RELOAD", true)

func _on_reload_cancelled() -> void:
	_weapon_system.cancel_reload()

func _on_fire_mode_changed(mode: String) -> void:
	_update_mode_label(mode)

func _update_mode_label(mode: String) -> void:
	match mode:
		"semi":   _mode_label.text = "1"
		"burst3": _mode_label.text = "3"
		"burst5": _mode_label.text = "5"
		"auto":   _mode_label.text = "A"
		_:        _mode_label.text = "?"

func _physics_process(_delta: float) -> void:
	var w: WeaponData = _weapon_system.get_active_weapon()

	if w == null:
		TouchInputHandler.fire_just_pressed      = false
		TouchInputHandler.reload_just_pressed    = false
		TouchInputHandler.fire_mode_just_pressed = false
		return

	match w.active_fire_mode:
		"semi":
			if TouchInputHandler.fire_just_pressed:
				_weapon_system.shoot()
		"auto":
			if TouchInputHandler.fire_held:
				_weapon_system.shoot()
		"burst3":
			if TouchInputHandler.fire_just_pressed:
				_weapon_system.start_burst(3)
		"burst5":
			if TouchInputHandler.fire_just_pressed:
				_weapon_system.start_burst(5)

	TouchInputHandler.fire_just_pressed = false

	if TouchInputHandler.reload_just_pressed:
		_weapon_system.reload()
	TouchInputHandler.reload_just_pressed = false

	if TouchInputHandler.fire_mode_just_pressed:
		_weapon_system.cycle_fire_mode()
	TouchInputHandler.fire_mode_just_pressed = false

	if _weapon_system.get_is_reloading():
		_progress_circle.set_progress(_weapon_system.get_reload_progress())

	_fire_visual.modulate = Color(0.7, 0.7, 0.7) if TouchInputHandler.fire_held else Color.WHITE

	var is_full: bool = w.ammo_current >= w.magazine_size
	_reload_btn.modulate    = Color(0.4, 0.4, 0.4) if is_full else Color.WHITE
	_fire_mode_btn.modulate = Color(0.4, 0.4, 0.4) if w.fire_modes.size() <= 1 else Color.WHITE
	_update_mode_label(w.active_fire_mode)
