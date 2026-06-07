extends CanvasLayer

signal inventory_requested
signal ads_pressed
signal ads_released
signal pause_requested

@onready var _fire_visual: TextureRect = $FireButton
@onready var _reload_btn: TextureRect = $ReloadButton
@onready var _fire_mode_btn: TextureRect = $FireModeButton
@onready var _mode_label: Label = $FireModeButton/ModeLabel
@onready var _progress_circle: ProgressCircle = $ProgressCircle
@onready var _weapon_system: Node = get_parent().get_node("Player/WeaponSystem")

var _run_label: Label = null
var _player: Player = null
var _editor: InputLayoutEditor = null
var _inv_btn: Button = null
var _ads_btn: Button = null

func _ready() -> void:
	await get_tree().process_frame

	TouchInputHandler.fire_button_rect      = _fire_visual.get_global_rect()
	TouchInputHandler.reload_button_rect    = _reload_btn.get_global_rect()
	TouchInputHandler.fire_mode_button_rect = _fire_mode_btn.get_global_rect()

	_progress_circle.position = Vector2(DisplayServer.window_get_size()) * 0.5
	_player = get_parent().get_node("Player")

	# ── Buttons ────────────────────────────────────────────────────────────
	_inv_btn = Button.new()
	_inv_btn.text = "BAG"
	_inv_btn.position = Vector2(16, 16)
	_inv_btn.size = Vector2(72, 44)
	_inv_btn.pressed.connect(func(): inventory_requested.emit())
	add_child(_inv_btn)

	_ads_btn = Button.new()
	_ads_btn.text = "ADS"
	_ads_btn.position = Vector2(16, 70)
	_ads_btn.size = Vector2(72, 44)
	_ads_btn.button_down.connect(func(): ads_pressed.emit())
	_ads_btn.button_up.connect(func(): ads_released.emit())
	add_child(_ads_btn)

	# ── Status bars ────────────────────────────────────────────────────────
	var status_bars := StatusBars.new()
	status_bars.position = Vector2(102, 14)
	status_bars.setup(_player)
	add_child(status_bars)

	# ── Minimap ────────────────────────────────────────────────────────────
	var minimap := Minimap.new()
	minimap.position = Vector2(1060, 10)
	minimap.setup(_player)
	add_child(minimap)

	# ── Quick-use bar ──────────────────────────────────────────────────────
	var quick_bar := QuickUseBar.new()
	quick_bar.position = Vector2(660, 610)
	quick_bar.setup(_player.inventory)
	add_child(quick_bar)

	# ── Run indicator ──────────────────────────────────────────────────────
	_run_label = Label.new()
	_run_label.text = "▶  RUNNING"
	_run_label.visible = false
	_run_label.position = Vector2(540, 584)
	_run_label.add_theme_font_size_override("font_size", 14)
	_run_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
	add_child(_run_label)

	# ── Weapon / reload events ─────────────────────────────────────────────
	_weapon_system.reloading.connect(_on_reloading)
	_weapon_system.reload_complete.connect(_progress_circle.hide_progress)
	_weapon_system.fire_mode_changed.connect(_on_fire_mode_changed)
	_progress_circle.cancelled.connect(_on_reload_cancelled)

	var w: WeaponData = _weapon_system.get_active_weapon()
	if w != null:
		_update_mode_label(w.active_fire_mode)
		_fire_mode_btn.modulate = Color(0.4, 0.4, 0.4) if w.fire_modes.size() <= 1 else Color.WHITE
		_reload_btn.modulate    = Color(0.4, 0.4, 0.4) if w.ammo_current >= w.magazine_size else Color.WHITE

	# ── Layout editor (must be last child so it renders on top) ────────────
	_editor = InputLayoutEditor.new()
	add_child(_editor)

	# Register every draggable element
	_editor.register("fire",        "FIRE",       _fire_visual)
	_editor.register("reload",      "RELOAD",     _reload_btn)
	_editor.register("fire_mode",   "FIRE MODE",  _fire_mode_btn)
	_editor.register("bag",         "BAG",        _inv_btn)
	_editor.register("ads",         "ADS",        _ads_btn)
	_editor.register("status_bars", "STATUS BARS", status_bars)
	_editor.register("minimap",     "MINIMAP",    minimap)
	_editor.register("quick_use",   "QUICK USE",  quick_bar)
	_editor.register("run_label",   "RUN LABEL",  _run_label)

	_editor.load_saved()

	# "Edit layout" trigger button — small gear at top-center
	var edit_btn := Button.new()
	edit_btn.text = "⚙"
	edit_btn.position = Vector2(DisplayServer.window_get_size().x * 0.5 - 20, 4)
	edit_btn.size = Vector2(40, 32)
	edit_btn.add_theme_font_size_override("font_size", 18)
	edit_btn.pressed.connect(_editor.begin_edit)
	add_child(edit_btn)

	# Pause / menu button — top-right corner
	var menu_btn := Button.new()
	menu_btn.text = "||"
	menu_btn.position = Vector2(DisplayServer.window_get_size().x - 52.0, 4)
	menu_btn.size = Vector2(44, 32)
	menu_btn.add_theme_font_size_override("font_size", 14)
	menu_btn.pressed.connect(func(): pause_requested.emit())
	add_child(menu_btn)
	_editor.register("menu_btn", "MENU", menu_btn)

	# Re-sync touch rects after layout may have shifted
	await get_tree().process_frame
	_sync_touch_rects()

func _sync_touch_rects() -> void:
	TouchInputHandler.fire_button_rect      = _fire_visual.get_global_rect()
	TouchInputHandler.reload_button_rect    = _reload_btn.get_global_rect()
	TouchInputHandler.fire_mode_button_rect = _fire_mode_btn.get_global_rect()

func _on_reloading(_duration: float) -> void:
	_progress_circle.start("RELOAD", true)

func _on_reload_cancelled() -> void:
	_weapon_system.cancel_reload()

func _on_fire_mode_changed(mode: String) -> void:
	_update_mode_label(mode)

func begin_layout_edit() -> void:
	_editor.begin_edit()

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

	if _run_label != null and _player != null:
		_run_label.visible = _player.state_machine.is_running()

	_fire_visual.modulate = Color(0.7, 0.7, 0.7) if TouchInputHandler.fire_held else Color.WHITE

	var is_full: bool = w.ammo_current >= w.magazine_size
	_reload_btn.modulate    = Color(0.4, 0.4, 0.4) if is_full else Color.WHITE
	_fire_mode_btn.modulate = Color(0.4, 0.4, 0.4) if w.fire_modes.size() <= 1 else Color.WHITE
	_update_mode_label(w.active_fire_mode)
